#!/bin/bash
# pack-bundle.sh — Cavli-side: build the /pkg bundles and publish them.
#
# Run this on a machine that already has a known-good /pkg (the CI host is the
# reference). It produces versioned, checksummed archives and optionally
# uploads them to the Drive folder the setup script downloads from.
#
# Customers never run this. They only consume the output.
#
#   ./pack-bundle.sh --component all --version 1.1.0 --source /pkg --upload
#
# COMPONENTS, PACKED SEPARATELY
#
# The toolchain used to be one 50 GB archive that every recipient had to take
# whole. It is split now, because the pieces have different audiences and very
# different licence status:
#
#   qcom       qct/software/{HEXAGON_Tools,arm,llvm}, sectools, prebuilts
#              ~49 GB. Needed by EVERY product. Qualcomm proprietary — its
#              link is never committed and is handed out per recipient.
#
#   yocto      yocto/{downloads,llvm-arm-toolchain-ship}
#              ~27 GB. Only for cqm211 (sdx61/62/65). Public source tarballs
#              and an LLVM build; nothing proprietary, so the link ships in
#              the setup script.
#
#   openwrt    openwrt-prebuilt-backup
#              ~10 GB raw, ~2.3 GB packed. Only for cqm220-0/3 (sdx35/32).
#              OpenWrt's own host tools and cross toolchain (arm gcc-11.2) —
#              also public.
#
#   openwrt212 openwrt-prebuilt-backup, same layout as openwrt above, but for
#              cqm212 (sdx85/Kobuk): aarch64 gcc-13.3.0 musl instead of arm
#              gcc-11.2. Kept as its own component, not folded into "openwrt"
#              or "all", because the two toolchains are not interchangeable —
#              restoring one into the other product's tree is refused by the
#              build scripts. Pack it from a CQM212 build host's /pkg, never
#              from a cqm220 one.
#
# Splitting means a cqm220 developer never downloads the 27 GB of yocto cache,
# and a cqm211 developer never downloads an OpenWrt one. Everyone still needs
# qcom, which is why it stays a component of its own rather than being merged
# into any of the others.
#
# Layout inside each archive (extracted to <root>/<component>/<version>/):
#   <payload subtrees>
#   BUNDLE_VERSION         the version string
#   SHA256SUMS.spot        sampled checksums, verified by cqm-doctor at runtime
#   MANIFEST.txt           human-readable inventory with sizes and provenance

set -euo pipefail

VERSION=""
SOURCE=/pkg
OUTDIR="${PWD}"
STAGE_DIR=""          # defaults to $OUTDIR/.stage — see below
ZSTD_LEVEL=""        # empty = pick a sensible level per component, see zstd_level()
UPLOAD=no
SPOT_COUNT=200
COMPONENTS=()
RCLONE_REMOTE="${CQM_RCLONE_REMOTE:-GGDrive}"
RCLONE_CONFIG_FILE="${CQM_RCLONE_CONFIG:-$HOME/rclone_fw_share.conf}"
REMOTE_DIR="${CQM_BUNDLE_REMOTE_DIR:-/cqm22x-buildenv/toolchain}"

# "all" deliberately excludes openwrt212: it lives on a different host (a
# CQM212 build box, not a cqm220 one) and has no place in a routine "pack
# everything from this /pkg" run. Pack it explicitly with --component openwrt212.
ALL_COMPONENTS=(qcom yocto openwrt)
KNOWN_COMPONENTS=("${ALL_COMPONENTS[@]}" openwrt212)

log()  { printf '\e[36m==>\e[0m %s\n' "$*"; }
die()  { printf '\e[31m==> %s\e[0m\n' "$*" >&2; exit 1; }

declare -A MAP=()

STAGE_CURRENT=""
trap 'rm -rf "${STAGE_CURRENT:-}"' EXIT

usage() {
cat <<EOF
pack-bundle.sh --component C --version V [options]

  --component C      qcom | yocto | openwrt | openwrt212 | all   (repeatable)
  --version V        bundle version, e.g. 1.1.0            (required)
  --source DIR       /pkg tree to pack from                (default $SOURCE)
  --map REL=DIR      take REL from DIR instead of \$SOURCE/REL (repeatable)
                     REL is the path INSIDE the archive, e.g.
                     --map downloads=/srv/yocto-dl
  --outdir DIR       where to write the archives           (default \$PWD)
  --stage-dir DIR    staging area, needs ~50 GB free       (default OUTDIR/.stage)
  --level N          zstd compression level      (default 15 for qcom, 1 for
                     yocto and openwrt — their payload is already compressed)
  --upload           upload archives + checksums to Drive afterwards
  --spot-count N     files to sample for SHA256SUMS.spot   (default $SPOT_COUNT)
  --remote-dir P     Drive folder                          (default $REMOTE_DIR)

COMPONENTS

  qcom        qct/software/{HEXAGON_Tools,arm,llvm}, sectools, prebuilts
              every product needs it — PROPRIETARY, link handed out per recipient
  yocto       yocto/{downloads,llvm-arm-toolchain-ship}
              cqm211 (sdx61/62/65) only — public
  openwrt     openwrt-prebuilt-backup (arm gcc-11.2)
              cqm220-0/3 (sdx35/32) only — public
  openwrt212  openwrt-prebuilt-backup (aarch64 gcc-13.3.0 musl)
              cqm212 (sdx85/Kobuk) only — public, not part of --component all

Staging defaults to a directory beside the output rather than /tmp: the qcom
tree is around 50 GB, and /tmp is frequently a tmpfs sized well below that.

--map exists because a reference /pkg is not always assembled in one place.
On a host where the toolchain lives in a checkout and the prebuilts came from
somewhere else:

  ./pack-bundle.sh --component qcom --version 1.1.0 \\
      --source /srv/sdx_buildtools \\
      --map prebuilts=/srv/rescue/pkg/kernel/prebuilts

The yocto tree usually is not under /pkg on the packing host either:

  ./pack-bundle.sh --component yocto --version 1.1.0 \\
      --map downloads=/srv/yocto/downloads \\
      --map llvm-arm-toolchain-ship=/srv/yocto/llvm-arm-toolchain-ship
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --component)  COMPONENTS+=("$2"); shift 2;;
        --version)    VERSION="$2"; shift 2;;
        --source)     SOURCE="$2"; shift 2;;
        --map)        [[ "$2" == *=* ]] || die "--map expects REL=DIR, got: $2"
                      MAP["${2%%=*}"]="${2#*=}"; shift 2;;
        --outdir)     OUTDIR="$2"; shift 2;;
        --stage-dir)  STAGE_DIR="$2"; shift 2;;
        --level)      ZSTD_LEVEL="$2"; shift 2;;
        --upload)     UPLOAD=yes; shift;;
        --spot-count) SPOT_COUNT="$2"; shift 2;;
        --remote-dir) REMOTE_DIR="$2"; shift 2;;
        -h|--help)    usage; exit 0;;
        *) die "unknown option: $1";;
    esac
done

[[ -n "$VERSION" ]] || { usage; die "--version is required"; }
[[ ${#COMPONENTS[@]} -gt 0 ]] || { usage; die "--component is required (qcom, yocto, openwrt, openwrt212 or all)"; }

# Expand "all", reject anything unknown before an hour of copying starts.
expanded=()
for c in "${COMPONENTS[@]}"; do
    case "$c" in
        all)                          expanded+=("${ALL_COMPONENTS[@]}");;
        qcom|yocto|openwrt|openwrt212) expanded+=("$c");;
        *) die "unknown component: $c (expected qcom, yocto, openwrt, openwrt212 or all)";;
    esac
done
# De-duplicate while keeping the declared order. Iterates KNOWN_COMPONENTS
# (not ALL_COMPONENTS) so an explicit --component openwrt212 survives even
# though "all" does not expand to it.
COMPONENTS=()
for c in "${KNOWN_COMPONENTS[@]}"; do
    for e in "${expanded[@]}"; do
        [[ "$c" == "$e" ]] && { COMPONENTS+=("$c"); break; }
    done
done

mkdir -p "$OUTDIR"
: "${STAGE_DIR:=$OUTDIR/.stage}"
mkdir -p "$STAGE_DIR"

# ---------------------------------------------------------------------------
# Component definitions.
#
# INCLUDE_* lists paths as they appear INSIDE the archive. SRCREL_* maps an
# entry to its path under $SOURCE when the two differ — the yocto component
# flattens away the leading yocto/ so the archive extracts straight into
# <root>/yocto/<version>/{downloads,llvm-arm-toolchain-ship}.
# ---------------------------------------------------------------------------
INCLUDE_qcom=(qct/software/HEXAGON_Tools qct/software/arm qct/software/llvm sectools prebuilts)
INCLUDE_yocto=(downloads llvm-arm-toolchain-ship)
INCLUDE_openwrt=(openwrt-prebuilt-backup)
# Same include path as openwrt on purpose: EXCLUDE_FROM below is keyed by
# this path, not by component name, so the *.tar exclusion applies to both
# without repeating it.
INCLUDE_openwrt212=(openwrt-prebuilt-backup)

declare -A SRCREL=(
    [downloads]=yocto/downloads
    [llvm-arm-toolchain-ship]=yocto/llvm-arm-toolchain-ship
)

# The openwrt cache directory holds both foo.tar and foo.tar.zst — the same
# payload twice. Ship only the compressed copies; restore prefers them anyway.
declare -A EXCLUDE_FROM=(
    [openwrt-prebuilt-backup]='--exclude=*.tar'
)

# The qcom tree is raw binaries and compresses about 4:1, so it is worth a slow
# level. The other two are already-compressed archives — yocto/downloads is 864
# .tar.gz/.tar.bz2 files, openwrt-prebuilt-backup ships .tar.zst — where a high
# level burns hours of CPU to save a fraction of a percent. Level 1 there keeps
# tar streaming at disk speed.
zstd_level() {
    [[ -n "$ZSTD_LEVEL" ]] && { echo "$ZSTD_LEVEL"; return; }
    case "$1" in
        qcom) echo 15;;
        *)    echo 1;;
    esac
}

component_blurb() {
    case "$1" in
        qcom)       echo "Qualcomm toolchain — required by every product (cqm220-0/3, cqm211, cqm212)";;
        yocto)      echo "Yocto download cache and LLVM/ARM toolchain — cqm211 (sdx61/62/65)";;
        openwrt)    echo "OpenWrt prebuilt host tools and cross toolchain (arm gcc-11.2) — cqm220-0/3 (sdx35/32)";;
        openwrt212) echo "OpenWrt prebuilt host tools and cross toolchain (aarch64 gcc-13.3.0 musl) — cqm212 (sdx85/Kobuk)";;
    esac
}

pack_one() {
    local component="$1"
    local -n includes="INCLUDE_${component}"

    log "===== component: $component ($VERSION)"

    # Resolve each include to a real directory, honouring --map.
    local -A src_of=()
    local p src
    for p in "${includes[@]}"; do
        src="${MAP[$p]:-$SOURCE/${SRCREL[$p]:-$p}}"
        [[ -d "$src" ]] || die "source for '$p' is missing: $src
Pass --map $p=<dir> if it lives somewhere else on this host."
        src_of["$p"]="$src"
    done

    # Fail before spending an hour copying, not after.
    # -L dereferences: a source is routinely a symlink into another tree (the
    # openwrt cache is usually rescued from a previous build host), and plain
    # du then reports the size of the link itself — 0 GB — so the space check
    # would wave through a copy that does not fit.
    local need_kb=0 have_kb
    for p in "${includes[@]}"; do
        need_kb=$(( need_kb + $(du -skL "${src_of[$p]}" | cut -f1) ))
    done
    have_kb="$(df -Pk "$STAGE_DIR" | awk 'NR==2{print $4}')"
    log "staging needs $(( need_kb / 1024 / 1024 )) GB, $STAGE_DIR has $(( have_kb / 1024 / 1024 )) GB free"
    (( have_kb > need_kb + 5*1024*1024 )) \
        || die "not enough space at $STAGE_DIR — pass --stage-dir pointing somewhere larger"

    local STAGE
    STAGE="$(mktemp -d -p "$STAGE_DIR" "pack-${component}-${VERSION}.XXXXXX")"
    # Two traps on purpose. RETURN clears the staging tree between components,
    # so packing all three does not need 150 GB at once. STAGE_CURRENT plus the
    # EXIT trap covers the other path: die() exits the shell outright, RETURN
    # never fires, and without this a failed run would leave tens of GB behind.
    STAGE_CURRENT="$STAGE"
    # shellcheck disable=SC2064
    trap "rm -rf '$STAGE'; STAGE_CURRENT=''" RETURN
    # mktemp creates the directory 0700, and tar records that mode for "." —
    # which then lands on the recipient's extracted bundle directory.
    chmod 0755 "$STAGE"
    log "staging at $STAGE"

    for p in "${includes[@]}"; do
        log "copying $p  <-  ${src_of[$p]}"
        mkdir -p "$STAGE/$(dirname "$p")"
        # Trailing slash on the source, explicit destination: the content lands
        # at $STAGE/$p regardless of what the source directory is called.
        # shellcheck disable=SC2086
        rsync -aH --numeric-ids ${EXCLUDE_FROM[$p]:-} "${src_of[$p]}/" "$STAGE/$p/"
    done

    printf '%s\n' "$VERSION" > "$STAGE/BUNDLE_VERSION"

    # --- inventory ----------------------------------------------------------
    log "writing MANIFEST.txt"
    {
        echo "CQM22x $component bundle $VERSION"
        echo "$(component_blurb "$component")"
        echo "packed from : $SOURCE"
        echo "packed on   : $(hostname)"
        echo
        echo "contents:"
        for p in "${includes[@]}"; do
            printf '  %-42s %s\n' "$p" "$(du -sh "$STAGE/$p" | cut -f1)"
        done
        echo
        if [[ "$component" == qcom ]]; then
            echo "component versions:"
            [[ -d "$STAGE/qct/software/HEXAGON_Tools" ]] && \
                printf '  HEXAGON_Tools : %s\n' "$(ls "$STAGE/qct/software/HEXAGON_Tools" | tr '\n' ' ')"
            [[ -d "$STAGE/qct/software/llvm/release/arm" ]] && \
                printf '  llvm (arm)    : %s\n' "$(ls "$STAGE/qct/software/llvm/release/arm" | tr '\n' ' ')"
            echo
            echo "This archive contains Qualcomm proprietary toolchains and is supplied"
            echo "under the recipient's licence agreement. Do not redistribute."
        else
            echo "This archive carries no proprietary material: it is a build cache"
            echo "assembled from publicly available sources. It exists to make the"
            echo "first build fast, not to supply anything that cannot be rebuilt."
        fi
    } > "$STAGE/MANIFEST.txt"

    # --- spot checksums -----------------------------------------------------
    # A full checksum of tens of GB takes long enough that nobody would run it.
    # A deterministic sample catches truncated or partial extractions, which is
    # the failure mode that actually happens, and runs in seconds.
    #
    # For qcom the sample is drawn from executables and shared objects — the
    # files a build actually runs. The cache components hold almost no
    # executables (they are tarballs), so there the sample is drawn from every
    # regular file instead; sampling executables would produce an empty list
    # and silently check nothing.
    log "sampling $SPOT_COUNT files for SHA256SUMS.spot"
    (
        cd "$STAGE"
        if [[ "$component" == qcom ]]; then
            find "${includes[@]}" -type f \( -perm -u+x -o -name '*.so*' \) 2>/dev/null
        else
            find "${includes[@]}" -type f 2>/dev/null
        fi \
            | LC_ALL=C sort \
            | awk -v n="$SPOT_COUNT" 'BEGIN{c=0} {a[++c]=$0} END{
                  if (c==0) exit;
                  step = (c>n) ? int(c/n) : 1;
                  for (i=1; i<=c; i+=step) print a[i];
              }' \
            | xargs -d '\n' -r sha256sum > SHA256SUMS.spot
        printf '  %s files\n' "$(wc -l < SHA256SUMS.spot)"
    )

    # --- archive ------------------------------------------------------------
    local ARCHIVE="$OUTDIR/cqm22x-${component}-${VERSION}.tar.zst"
    local level; level="$(zstd_level "$component")"
    log "creating $ARCHIVE at zstd -$level (this takes a while)"
    tar --use-compress-program="zstd -${level} -T0 --long=27" \
        -cf "$ARCHIVE" -C "$STAGE" .

    log "checksumming archive"
    # Run from OUTDIR so the file records a bare filename: the consumer
    # downloads the archive under its own path and checks it there.
    #
    # Write to a temporary name and rename into place. Hashing 14 GB takes a
    # minute, and a plain redirect creates the .sha256 empty for that whole
    # minute — long enough for anything watching the directory, or an upload
    # kicked off in parallel, to pick up a checksum file with nothing in it and
    # silently skip verification.
    ( cd "$OUTDIR" && sha256sum "$(basename "$ARCHIVE")" ) > "$ARCHIVE.sha256.tmp"
    mv -f "$ARCHIVE.sha256.tmp" "$ARCHIVE.sha256"

    printf '\n  archive  %s\n  size     %s\n  sha256   %s\n\n' \
        "$ARCHIVE" "$(du -h "$ARCHIVE" | cut -f1)" "$(awk '{print $1}' "$ARCHIVE.sha256")"

    # --- upload -------------------------------------------------------------
    if [[ "$UPLOAD" == yes ]]; then
        command -v rclone >/dev/null 2>&1 || die "rclone not found"
        [[ -r "$RCLONE_CONFIG_FILE" ]] || die "rclone config not readable: $RCLONE_CONFIG_FILE"
        log "uploading to ${RCLONE_REMOTE}:${REMOTE_DIR}"
        rclone --config "$RCLONE_CONFIG_FILE" --progress --transfers 4 --retries 5 \
            copy "$ARCHIVE" "${RCLONE_REMOTE}:${REMOTE_DIR}/"
        rclone --config "$RCLONE_CONFIG_FILE" \
            copy "$ARCHIVE.sha256" "${RCLONE_REMOTE}:${REMOTE_DIR}/"
    fi
}

for c in "${COMPONENTS[@]}"; do
    pack_one "$c"
done

log "done: ${COMPONENTS[*]} at version $VERSION"
if [[ "$UPLOAD" == yes ]]; then
    cat <<EOF

Uploaded. For the public components (yocto, openwrt), fetch the share links and
put them in container_docker_helper.sh — see BUNDLES near the top of that file.
The qcom link is NOT committed: hand it to each recipient with -u.
EOF
fi
