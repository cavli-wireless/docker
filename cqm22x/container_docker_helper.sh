#!/bin/bash
#
# container_docker_helper.sh — CQM22x build container setup.
#
#   wget https://raw.githubusercontent.com/cavli-wireless/docker/refs/heads/main/cqm22x/container_docker_helper.sh -O container_docker_helper.sh
#   bash container_docker_helper.sh -w /mnt/ -u '<google drive link to the pkg bundle>'
#   docker start -i build_cqm22x_jammy_$(whoami)
#
# The container image itself is public and carries no licensed material. What
# it needs at runtime comes in three separate bundles, downloaded only when the
# selected products actually need them:
#
#   qcom     Qualcomm toolchain, ~13 GB packed. EVERY product needs it.
#            Proprietary — Cavli hands out the link per recipient, and it is
#            never committed here. Supply it with -u (and -c for its sha256).
#   yocto    Yocto download cache + LLVM/ARM toolchain, ~26 GB. cqm211 only.
#   openwrt  OpenWrt prebuilt host tools and cross toolchain, ~2.3 GB.
#            cqm220-0 and cqm220-3 only.
#
# yocto and openwrt carry nothing proprietary, so their links are built into
# this script and nobody has to be told them. That is the whole point of the
# split: a cqm220 developer never downloads the 26 GB yocto cache, and a cqm211
# developer never downloads the OpenWrt one.
#
# Bundles already on disk are not downloaded again.
#
# ---------------------------------------------------------------------------
# This never touches the older build environments in this repository
# (sdx/, sdx35/, c10qm/ ... and their build_* containers). It uses its own
# image path, container name and directories, and refuses to do otherwise.
# ---------------------------------------------------------------------------

set -euo pipefail

print_usage()
{
    cat <<'EOF'
container_docker_helper.sh [options]

  Sets up the CQM22x build containers: installs Docker if it is missing,
  fetches and verifies the bundles the selected products need, creates one
  container per product and checks that each matches the environment CI
  builds with.

  Safe to re-run. Anything already in place is left alone.

  options:
  -h: print help
  -d: dry run: print what will be done
  -w: working path for sources, mounted at /work
  -p: product list, comma separated, or 'all'  (default cqm220-3)
        cqm220-3   sdx35, OpenWrt userspace
        cqm220-0   sdx32, OpenWrt userspace
        cqm211     sdx61/62/65, Yocto userspace
  -u: URL of the QCOM bundle — a Google Drive share link or any direct
      HTTPS URL. Cavli supplies this; it is the only bundle this script
      cannot fetch on its own.
  -c: expected sha256 of the qcom bundle (strongly recommended; Cavli
      publishes it alongside the link)
  -t: path to an already-extracted qcom bundle; skips its download
  -f: path to an already-downloaded qcom .tar.zst; skips its download
  -r: root directory for the bundles and build caches
      (default $HOME/cqm22x)
  -V: bundle version                         (default 1.1.0)
      Several versions can live side by side under -r; this picks one.
  -k: keep downloaded archives after unpacking
  -F: re-download even if a bundle is already installed
  -P: do not pull the image; use the local copy
  -D: do not install Docker; fail if it is missing
  -U: do not pass USB through (build only, no flashing)
  -R: replace existing containers
  -n: fetch and unpack the bundles only; do not create containers

BUNDLES

  Three archives, downloaded only when a selected product needs them:

    qcom      ~13 GB packed, ~60 GB unpacked.  every product
              Qualcomm proprietary — supplied by Cavli, pass with -u/-c.
    openwrt   ~2.3 GB packed.                  cqm220-0, cqm220-3
    yocto     ~24 GB packed, ~27 GB unpacked.  cqm211
              Both public; their links are built into this script.

  So a cqm220 machine downloads ~15 GB, a cqm211 machine ~37 GB, and a
  machine set up for everything downloads each archive exactly once.

EXAMPLES
  # sdx35 only — the default
  bash container_docker_helper.sh -w /mnt/ -u '<qcom link>' -c <sha256>

  # sdx61/62/65
  bash container_docker_helper.sh -w /mnt/ -p cqm211 -u '<qcom link>' -c <sha256>

  # both, sharing the qcom bundle
  bash container_docker_helper.sh -w /mnt/ -p cqm220-3,cqm211 -u '<link>' -c <sha256>

  # everything
  bash container_docker_helper.sh -w /mnt/ -p all -u '<link>' -c <sha256>

  # the qcom archive is already here
  bash container_docker_helper.sh -w /mnt/ -f ~/cqm22x-qcom-1.1.0.tar.zst

  # only fetch and unpack, do not create containers
  bash container_docker_helper.sh -p all -u '<link>' -c <sha256> -n

NOTE
  This container is based on ghcr.io/cavli-wireless-public/cqm22x-buildenv
  The container user is created from the caller's own uid/gid, so files
  written into the mounted work path stay owned by you.
EOF
}

# ---- defaults --------------------------------------------------------------
DOCKER_PRV_NAME=build_cqm22x_jammy
DOCKER_IMG="${CQM_IMAGE_REPO:-ghcr.io/cavli-wireless-public/cqm22x-buildenv}"
DOCKER_IMG_TAG="${CQM_IMAGE_TAG:-latest}"
LEGACY_IMAGES="sdx/jammy/owrt cqm220/jammy/owrt sdx35/jammy/owrt"

BUNDLE_VERSION="${CQM_BUNDLE_VERSION:-1.1.0}"
CQM_ROOT="${CQM_ROOT:-$HOME/cqm22x}"
WORK_PATH=""
PKG_URL=""
PKG_SHA256=""
TOOL_PATH=""
FILE_TOOL_PATH=""
PRODUCTS_ARG=cqm220-3

# ---------------------------------------------------------------------------
# Which bundle each product needs.
#
#   cqm220-0 / cqm220-3   sdx35 / sdx32   OpenWrt userspace  -> qcom + openwrt
#   cqm211                sdx61/62/65     Yocto userspace    -> qcom + yocto
#
# Everything needs qcom; the second component is what differs, and it is the
# reason the toolchain is not one archive any more.
# ---------------------------------------------------------------------------
ALL_PRODUCTS="cqm220-3 cqm220-0 cqm211"
components_for() {
    case "$1" in
        cqm220-0|cqm220-3) echo "qcom openwrt";;
        cqm211)            echo "qcom yocto";;
        *) die "unknown product: $1 (expected one of: $ALL_PRODUCTS)";;
    esac
}

# ---------------------------------------------------------------------------
# Where the public bundles live.
#
# These two carry no Qualcomm material — yocto/downloads is public source
# tarballs, llvm-arm-toolchain-ship is an LLVM build, and openwrt-prebuilt-
# backup is OpenWrt's own host tools — so their links belong here, where a
# recipient needs to be told nothing at all.
#
# The qcom link is deliberately absent and must stay absent: this repository is
# public and that bundle is Qualcomm proprietary. It is passed in with -u.
#
# Override any of them with CQM_QCOM_URL / CQM_YOCTO_URL / CQM_OPENWRT_URL (and
# the matching _SHA256) when serving from a local mirror.
# ---------------------------------------------------------------------------
URL_qcom="${CQM_QCOM_URL:-}"
SHA_qcom="${CQM_QCOM_SHA256:-}"
URL_yocto="${CQM_YOCTO_URL:-https://drive.google.com/file/d/1V5Mnrdh4dxf4-ribimCH6rktMU0CGOlx/view?usp=sharing}"
SHA_yocto="${CQM_YOCTO_SHA256:-d32d303ebc47a1ce9fb6fb9a2494b3c9c16741d95502e28eb6b1132600ed7c06}"
URL_openwrt="${CQM_OPENWRT_URL:-https://drive.google.com/file/d/1sPOzmaDvJBZ4rASOLVJphqs6u0FmY8MZ/view?usp=sharing}"
SHA_openwrt="${CQM_OPENWRT_SHA256:-cdf8f8e3ece1619a32e8ae948f0aee2f5eecf0467b65d5590026c5d235384405}"
KEEP_ARCHIVE=no
FORCE_FETCH=no
SKIP_PULL=no
INSTALL_DOCKER=yes
ENABLE_USB=yes
RECREATE=no
FETCH_ONLY=no
DRYRUNCMD=""

while getopts "hdw:u:c:t:f:r:p:V:kFPDURn" flag; do
  case $flag in
    d) DRYRUNCMD="echo";;
    w) WORK_PATH=$OPTARG;;
    u) PKG_URL=$OPTARG;;
    c) PKG_SHA256=$OPTARG;;
    t) TOOL_PATH=$OPTARG;;
    f) FILE_TOOL_PATH=$OPTARG;;
    r) CQM_ROOT=$OPTARG;;
    p) PRODUCTS_ARG=$OPTARG;;
    V) BUNDLE_VERSION=$OPTARG;;
    k) KEEP_ARCHIVE=yes;;
    F) FORCE_FETCH=yes;;
    P) SKIP_PULL=yes;;
    D) INSTALL_DOCKER=no;;
    U) ENABLE_USB=no;;
    R) RECREATE=yes;;
    n) FETCH_ONLY=yes;;
    h) print_usage; exit 0;;
    *) print_usage; exit 1;;
  esac
done
shift $(( OPTIND - 1 ))

C_INFO=$'\e[36m'; C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'; C_OFF=$'\e[0m'
[[ -t 1 ]] || { C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_OFF=""; }
log()  { printf '%s==>%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s==>%s %s\n' "$C_OK"   "$C_OFF" "$*"; }
warn() { printf '%s==> %s%s\n' "$C_WARN" "$*" "$C_OFF" >&2; }
die()  { printf '%s==> %s%s\n' "$C_ERR"  "$*" "$C_OFF" >&2; exit 1; }
run()  { if [ -n "$DRYRUNCMD" ]; then echo "+ $*"; else "$@"; fi; }

__USERNAME=$(id -un)
__UID=$(id -u)
__GID=$(id -g)

# -p takes a list: "cqm220-3", "cqm220-3,cqm211", or "all". One container is
# created per product; they share whatever bundles they have in common, so
# asking for two products does not download qcom twice.
if [ "$PRODUCTS_ARG" = all ]; then
    PRODUCTS="$ALL_PRODUCTS"
else
    PRODUCTS="$(printf '%s' "$PRODUCTS_ARG" | tr ',' ' ')"
fi
for _p in $PRODUCTS; do components_for "$_p" >/dev/null; done

# cqm220-3 is the default product and gets the plain container name, so it is
# the one the setup output tells you to `docker start -i`.
container_for() {
    case "$1" in
        cqm220-3) echo "${DOCKER_PRV_NAME}_${__USERNAME}";;
        *)        echo "${DOCKER_PRV_NAME}_${__USERNAME}_$1";;
    esac
}

# The union of what every selected product needs, in a stable order.
NEEDED_COMPONENTS=""
for _p in $PRODUCTS; do
    for _c in $(components_for "$_p"); do
        case " $NEEDED_COMPONENTS " in *" $_c "*) ;; *) NEEDED_COMPONENTS="$NEEDED_COMPONENTS $_c";; esac
    done
done
NEEDED_COMPONENTS="$(printf '%s' "$NEEDED_COMPONENTS" | sed 's/^ *//')"

CACHE_ROOT="$CQM_ROOT/cache"
IMAGE="$DOCKER_IMG:$DOCKER_IMG_TAG"
[[ -n "$WORK_PATH" ]] || WORK_PATH="$CQM_ROOT/workspace"

# Each component unpacks into its own versioned directory, so a toolchain
# update to one does not disturb the others and several versions can sit side
# by side.
QCOM_DIR_OVERRIDE=""
comp_dir()  {
    # -t hands us a qcom tree that lives wherever the caller put it.
    [ "$1" = qcom ] && [ -n "$QCOM_DIR_OVERRIDE" ] && { echo "$QCOM_DIR_OVERRIDE"; return; }
    echo "$CQM_ROOT/$1/$BUNDLE_VERSION"
}
comp_url()  { eval "printf '%s' \"\${URL_$1}\""; }
comp_sha()  { eval "printf '%s' \"\${SHA_$1}\""; }
# Peak space each component needs: the archive plus what it unpacks to, since
# the download is only deleted after a successful unpack.
comp_gb()   { case "$1" in qcom) echo 75;; yocto) echo 55;; openwrt) echo 13;; esac; }

count=0
[[ -n "$PKG_URL" ]]        && count=$((count+1))
[[ -n "$TOOL_PATH" ]]      && count=$((count+1))
[[ -n "$FILE_TOOL_PATH" ]] && count=$((count+1))
(( count <= 1 )) || die "give only one of -u, -t or -f"

# -u/-c/-t/-f all refer to the qcom bundle: it is the one a recipient is handed
# and the only one this script cannot fetch on its own.
[[ -n "$PKG_URL" ]] && URL_qcom="$PKG_URL"
[[ -n "$PKG_SHA256" ]] && SHA_qcom="$PKG_SHA256"

# ===========================================================================
# Guards — the other build environments in this repository are off limits
# ===========================================================================
assert_no_legacy_collision() {
    local legacy
    for legacy in $LEGACY_IMAGES; do
        [[ "$DOCKER_IMG" != *"$legacy" ]] \
            || die "refusing to use $legacy — other projects depend on that image"
    done
    # Every pre-existing environment in this repository publishes under a
    # */jammy/owrt name. Staying out of that family entirely means a typo in
    # CQM_IMAGE_REPO can never overwrite one of them.
    [[ "$DOCKER_IMG" != */jammy/owrt ]] \
        || die "refusing to publish under the */jammy/owrt naming family used by the other environments"
    local prod name
    for prod in $PRODUCTS; do
        name="$(container_for "$prod")"
        [[ "$name" == "${DOCKER_PRV_NAME}_"* ]] \
            || die "container name '$name' is outside the ${DOCKER_PRV_NAME}_* namespace"
    done
}

# ===========================================================================
# Docker
# ===========================================================================
docker_ready() { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }

install_docker() {
    log "installing Docker"
    command -v sudo >/dev/null 2>&1 || die "sudo is required to install Docker"
    . /etc/os-release 2>/dev/null || die "cannot identify this distribution"
    case "${ID:-}" in
        ubuntu|debian) ;;
        *) die "automatic Docker installation supports Ubuntu and Debian only (found '${ID:-unknown}').
Install Docker yourself, then re-run with -D.";;
    esac

    # Docker's own apt repository, configured explicitly rather than by piping
    # a remote script into a shell.
    run sudo install -m 0755 -d /etc/apt/keyrings
    run sudo curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
    run sudo chmod a+r /etc/apt/keyrings/docker.asc
    if [ -z "$DRYRUNCMD" ]; then
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID ${VERSION_CODENAME} stable" \
            | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    fi
    run sudo apt-get update -qq
    run sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true

    local need_relogin=no
    if ! id -nG "$__USERNAME" | tr ' ' '\n' | grep -qx docker; then
        log "adding $__USERNAME to the docker group"
        run sudo usermod -aG docker "$__USERNAME"
        need_relogin=yes
    fi
    docker_ready && return 0
    [[ "$need_relogin" != yes ]] || die "Docker is installed, but '$__USERNAME' only just joined the
'docker' group. Log out and back in (or run: newgrp docker), then re-run this script."
    die "Docker was installed but the daemon is not reachable. Check: systemctl status docker"
}

ensure_docker() {
    if docker_ready; then
        log "Docker $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo present) is ready"
        return 0
    fi
    if command -v docker >/dev/null 2>&1; then
        die "Docker is installed but the daemon is not reachable.
Start it (sudo systemctl start docker), or add '$__USERNAME' to the docker group and log back in."
    fi
    [[ "$INSTALL_DOCKER" == yes ]] || die "Docker is not installed and -D was given."
    install_docker
}

# ===========================================================================
# Bundle
# ===========================================================================

# Returns the file id for any of the shapes a Drive link comes in, or nothing
# if this is not a Drive URL.
gdrive_file_id() {
    local url="$1"
    case "$url" in
        *drive.google.com/file/d/*) sed -E 's#.*/file/d/([^/?]+).*#\1#' <<<"$url";;
        *drive.google.com/*id=*)    sed -E 's#.*[?&]id=([^&]+).*#\1#' <<<"$url";;
        *) return 0;;
    esac
}

# Abort a transfer that has effectively stopped. Drive routinely leaves a
# multi-GB download connected but idle; curl's --retry never fires for that,
# because nothing has failed — the socket simply goes quiet forever. These two
# turn a silent hang into a timeout that the retry loop can act on.
CURL_STALL_OPTS=(--connect-timeout 30 --speed-limit 30000 --speed-time 60)

# Google Drive will not hand over a large file on the first request: it answers
# with an HTML page carrying a confirmation token that has to be posted back.
# Reproducing that exchange here means the target machine needs nothing beyond
# curl — no gdown, no rclone, no Google account.
#
# The token is short-lived, so each retry re-resolves it rather than reusing a
# stale one, and resumes the partial file with -C -.
fetch_gdrive() {
    local id="$1" dest="$2" cookie page confirm uuid url
    local attempt=0 max=8 before after rc
    cookie="$(mktemp)"; page="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$cookie' '$page'" RETURN

    while :; do
        attempt=$((attempt + 1))
        before="$(stat -c %s "$dest" 2>/dev/null || echo 0)"

        log "resolving Google Drive file $id${before:+ }$( [ "$before" -gt 0 ] && printf '(resuming from %s)' "$(numfmt --to=iec "$before" 2>/dev/null || echo "$before bytes")" )"
        : > "$page"
        curl -sL "${CURL_STALL_OPTS[@]}" -c "$cookie" -o "$page" \
            "https://drive.google.com/uc?export=download&id=${id}" || true

        if head -c 512 "$page" | grep -qiE '<!doctype html|<html'; then
            if grep -qiE 'quota|too many users|cannot currently be viewed' "$page"; then
                die "Google Drive is refusing this file right now (download quota exceeded).
Try again later, or ask Cavli for a direct HTTPS mirror and pass that to -u."
            fi
            confirm="$(grep -oE 'name="confirm" value="[^"]*"' "$page" | head -1 | sed -E 's/.*value="([^"]*)".*/\1/')"
            uuid="$(grep -oE 'name="uuid" value="[^"]*"' "$page" | head -1 | sed -E 's/.*value="([^"]*)".*/\1/')"
            url="https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=${confirm:-t}&uuid=${uuid}"
            [ "$attempt" -eq 1 ] && log "downloading (large-file confirmation accepted)"
        else
            url="https://drive.google.com/uc?export=download&id=${id}"
            [ "$attempt" -eq 1 ] && log "downloading"
        fi

        rc=0
        curl -L -b "$cookie" -C - "${CURL_STALL_OPTS[@]}" \
             --retry 3 --retry-delay 5 --progress-bar -o "$dest" "$url" || rc=$?
        [ "$rc" -eq 0 ] && return 0

        # 33 = server will not resume, 416 surfaces as 22/36 depending on
        # version. If the file is already complete these are expected; the
        # checksum check that follows is the real verdict, so stop retrying.
        case "$rc" in 33|36) log "server declined to resume — treating the file as complete"; return 0;; esac

        after="$(stat -c %s "$dest" 2>/dev/null || echo 0)"
        [ "$attempt" -lt "$max" ] || die "download failed after $max attempts (curl exit $rc).
Got $(numfmt --to=iec "$after" 2>/dev/null || echo "$after bytes") so far; the partial file is kept, so
re-running resumes from there. If Drive keeps stalling, ask Cavli for an HTTPS mirror."

        if [ "$after" -le "$before" ]; then
            warn "attempt $attempt made no progress (curl exit $rc) — retrying in 10s"
        else
            log "attempt $attempt stopped at $(numfmt --to=iec "$after" 2>/dev/null || echo "$after") — resuming"
        fi
        sleep 10
    done
}

fetch_any() {
    local url="$1" dest="$2" id
    id="$(gdrive_file_id "$url")"
    if [ -n "$id" ]; then
        fetch_gdrive "$id" "$dest"
    else
        log "downloading $url"
        curl -fL -C - "${CURL_STALL_OPTS[@]}" --retry 10 --retry-delay 10 \
             --progress-bar -o "$dest" "$url"
    fi
}

check_free_space() {
    local path="$1" need_gb="$2" have_gb
    mkdir -p "$path"
    have_gb="$(df -BG --output=avail "$path" 2>/dev/null | tail -1 | tr -dc '0-9')"
    [ -n "$have_gb" ] || return 0
    [ "$have_gb" -ge "$need_gb" ] \
        || die "only ${have_gb} GB free at $path; about ${need_gb} GB is needed. Use -r to point somewhere larger."
}

verify_archive() {
    local archive="$1" sumfile="$2" want="${3:-}" url="${4:-}" got
    if [ -z "$want" ]; then
        # A plain HTTPS mirror publishes <url>.sha256 next to the archive. A
        # Drive link cannot: every Drive file has its own id, so appending
        # ".sha256" would just be a malformed id. Hence -c.
        if [ -n "$url" ] && [ -z "$(gdrive_file_id "$url")" ]; then
            fetch_any "${url}.sha256" "$sumfile" >/dev/null 2>&1 || true
        fi
        [ -r "$sumfile" ] && want="$(awk '{print $1}' "$sumfile" | head -1)"
    fi
    if [ -z "$want" ]; then
        warn "no checksum available — the archive was NOT verified.
Pass -c <sha256> (Cavli publishes it with the link) so a truncated download is caught here."
        return 0
    fi
    log "verifying archive checksum"
    got="$(sha256sum "$archive" | cut -d' ' -f1)"
    [ "$want" = "$got" ] || die "checksum mismatch
  expected $want
  got      $got
The download is corrupt or incomplete. Re-run with -F."
    ok "checksum ok"
}

# One directory that must exist inside each component's archive. Used both to
# detect an extra wrapping directory and to reject an archive of the wrong kind
# before it is moved into place under the wrong name.
comp_marker() {
    case "$1" in
        qcom)    echo qct;;
        yocto)   echo downloads;;
        openwrt) echo openwrt-prebuilt-backup;;
    esac
}

extract_archive() {
    local archive="$1" dest="$2" component="$3" root marker
    marker="$(comp_marker "$component")"
    command -v zstd >/dev/null 2>&1 || die "zstd is required to unpack the bundle (sudo apt install zstd)"
    log "unpacking $component to $dest — this takes several minutes"
    rm -rf "$dest.partial"; mkdir -p "$dest.partial"
    # --long=27 must match the window the bundle was packed with.
    tar --use-compress-program="zstd -d -T0 --long=27" -xf "$archive" -C "$dest.partial"
    root="$dest.partial"
    if [ ! -d "$root/$marker" ]; then
        root="$(find "$dest.partial" -mindepth 1 -maxdepth 1 -type d | head -1)"
        [ -n "$root" ] && [ -d "$root/$marker" ] \
            || die "this does not look like the $component bundle: no $marker/ inside $archive"
    fi
    rm -rf "$dest"; mv "$root" "$dest"; rm -rf "$dest.partial"
    chmod 0755 "$dest"
}

comp_required() {
    case "$1" in
        qcom)    echo "qct/software sectools prebuilts";;
        yocto)   echo "downloads llvm-arm-toolchain-ship";;
        openwrt) echo "openwrt-prebuilt-backup";;
    esac
}

finalise_bundle() {
    local dir="$1" component="$2" required
    for required in $(comp_required "$component"); do
        [ -d "$dir/$required" ] || die "the $component bundle is incomplete: $dir/$required is missing"
    done
    printf '%s\n' "$BUNDLE_VERSION" > "$dir/BUNDLE_VERSION"
    if [ -r "$dir/SHA256SUMS.spot" ]; then
        log "verifying unpacked files"
        ( cd "$dir" && sha256sum -c --quiet SHA256SUMS.spot ) \
            || die "the unpacked bundle failed its own checksums"
        ok "$(wc -l < "$dir/SHA256SUMS.spot") sampled files verified"
    else
        warn "bundle ships no SHA256SUMS.spot; contents not verified"
    fi
    touch "$dir/.complete"
    ok "$component $BUNDLE_VERSION ready ($(du -sh "$dir" | cut -f1)) at $dir"
}

acquire_component() {
    local component="$1"
    local dir url sha archive sumfile downloaded=no

    dir="$(comp_dir "$component")"
    url="$(comp_url "$component")"
    sha="$(comp_sha "$component")"

    # -t points at a qcom bundle the caller already unpacked; use it in place.
    if [ "$component" = qcom ] && [ -n "$TOOL_PATH" ]; then
        [ -d "$TOOL_PATH/qct/software" ] \
            || die "-t $TOOL_PATH does not look like an unpacked qcom bundle (no qct/software)"
        QCOM_DIR_OVERRIDE="$TOOL_PATH"
        log "using the qcom bundle at $TOOL_PATH"
        return 0
    fi

    if [ -n "$DRYRUNCMD" ]; then
        if [ -f "$dir/.complete" ] && [ "$FORCE_FETCH" != yes ]; then
            echo "+ $component $BUNDLE_VERSION already installed at $dir — no download"
        elif [ "$component" = qcom ] && [ -n "$FILE_TOOL_PATH" ]; then
            echo "+ verify and unpack $FILE_TOOL_PATH -> $dir"
        else
            echo "+ download ${url:-<no link for $component>} -> $CQM_ROOT/$component/cqm22x-$component-${BUNDLE_VERSION}.tar.zst"
            echo "+ verify sha256, then unpack -> $dir"
        fi
        return 0
    fi

    if [ -f "$dir/.complete" ] && [ "$FORCE_FETCH" != yes ]; then
        ok "$component $BUNDLE_VERSION is already installed at $dir — nothing to download"
        return 0
    fi

    if [ "$component" = qcom ] && [ -n "$FILE_TOOL_PATH" ]; then
        [ -f "$FILE_TOOL_PATH" ] || die "not a file: $FILE_TOOL_PATH"
        archive="$FILE_TOOL_PATH"
        sumfile="$FILE_TOOL_PATH.sha256"
    else
        if [ -z "$url" ]; then
            if [ "$component" = qcom ]; then
                die "no qcom bundle given.
The Qualcomm toolchain is not public, so this script cannot fetch it on its own.
Cavli supplies a link and its sha256 — pass them with -u and -c, or point -t at
an already-unpacked copy, or -f at an already-downloaded archive."
            fi
            die "no link is built in for the $component bundle.
Set CQM_$(printf '%s' "$component" | tr '[:lower:]' '[:upper:]')_URL to a mirror, or pass -t/-f for a local copy."
        fi
        mkdir -p "$CQM_ROOT/$component"
        check_free_space "$CQM_ROOT/$component" "$(comp_gb "$component")"
        archive="$CQM_ROOT/$component/cqm22x-${component}-${BUNDLE_VERSION}.tar.zst"
        sumfile="$archive.sha256"
        log "fetching the $component bundle"
        fetch_any "$url" "$archive"
        downloaded=yes
    fi

    verify_archive "$archive" "$sumfile" "$sha" "$url"
    extract_archive "$archive" "$dir" "$component"
    finalise_bundle "$dir" "$component"

    if [ "$downloaded" = yes ] && [ "$KEEP_ARCHIVE" != yes ]; then
        log "removing $(basename "$archive") (-k to keep it)"
        rm -f "$archive" "$sumfile"
    fi
}

# Fetch every component the selected products need, once each.
acquire_all() {
    local c
    for c in $NEEDED_COMPONENTS; do
        acquire_component "$c"
    done
}

# ===========================================================================
# Image and container
# ===========================================================================
pull_image() {
    if [ "$SKIP_PULL" = yes ]; then
        docker image inspect "$IMAGE" >/dev/null 2>&1 || die "-P was given but $IMAGE is not present locally"
        log "using the local image $IMAGE"
        return
    fi
    if [ -n "$DRYRUNCMD" ]; then
        echo "+ docker pull $IMAGE"
        return
    fi
    log "pulling $IMAGE"
    docker pull "$IMAGE" && return
    cat >&2 <<EOF

Could not pull $IMAGE.

If ghcr.io is unreachable from this network, Cavli also ships the image as a
tar file. Download it, then:

    docker load -i cqm22x-buildenv.tar
    bash $0 -w "$WORK_PATH" -p $(printf '%s' "$PRODUCTS" | tr ' ' ',') -P

EOF
    exit 1
}

create_container() {
    local product="$1"
    local container; container="$(container_for "$product")"
    local comps; comps="$(components_for "$product")"

    if docker ps -a --format '{{.Names}}' | grep -qx "$container"; then
        if [ "$RECREATE" != yes ]; then
            log "container $container already exists — reusing it (-R to rebuild)"
            [ -n "$DRYRUNCMD" ] || docker start "$container" >/dev/null
            return
        fi
        log "removing the existing container $container"
        run docker rm -f "$container" >/dev/null
    fi

    local qcom_dir openwrt_dir yocto_dir
    qcom_dir="$(comp_dir qcom)"

    # Validate every bind source up front. Docker silently creates an empty
    # directory for a missing one, which turns a clear setup error into a
    # confusing "toolchain not found" halfway through a build.
    local missing=() pth
    for pth in qct/software/HEXAGON_Tools qct/software/arm qct/software/llvm sectools prebuilts; do
        [ -e "$qcom_dir/$pth" ] || missing+=("qcom:$pth")
    done
    case " $comps " in
        *" openwrt "*)
            openwrt_dir="$(comp_dir openwrt)"
            [ -e "$openwrt_dir/openwrt-prebuilt-backup" ] || missing+=("openwrt:openwrt-prebuilt-backup")
            ;;
    esac
    case " $comps " in
        *" yocto "*)
            yocto_dir="$(comp_dir yocto)"
            for pth in downloads llvm-arm-toolchain-ship; do
                [ -e "$yocto_dir/$pth" ] || missing+=("yocto:$pth")
            done
            ;;
    esac
    if [ ${#missing[@]} -ne 0 ]; then
        # Under -d nothing has been downloaded, so absent bundles are expected
        # and are not an error: the point of a dry run is to see the plan on a
        # machine where none of this exists yet.
        [ -n "$DRYRUNCMD" ] \
            && warn "not present yet (would be downloaded first): ${missing[*]}" \
            || die "bundles for $product are incomplete: ${missing[*]}"
    fi

    # Caches are kept per product: two products must not share one OpenWrt
    # build_dir and staging_dir.
    run mkdir -p "$CACHE_ROOT/$product/openwrt" "$CACHE_ROOT/$product/ccache" "$WORK_PATH"

    local -a args=(
        --name "$container" --hostname "$DOCKER_PRV_NAME"
        # -dit with bash as the command, so `docker start -i` attaches to a
        # login shell — the same way every other helper in this repository
        # behaves. No --restart: the container is meant to end when you exit.
        -dit
        -e "TERM=xterm-256color"
        -e "CQM_UID=$__UID" -e "CQM_GID=$__GID" -e "CQM_USER=$__USERNAME"
        -e "CQM_PRODUCT=$product"
        --add-host "${DOCKER_PRV_NAME}:127.0.0.1"
        -v "$qcom_dir/qct/software/HEXAGON_Tools:/pkg/qct/software/HEXAGON_Tools:ro"
        -v "$qcom_dir/qct/software/arm:/pkg/qct/software/arm:ro"
        -v "$qcom_dir/qct/software/llvm:/pkg/qct/software/llvm:ro"
        -v "$qcom_dir/sectools:/pkg/sectools:ro"
        -v "$qcom_dir/prebuilts:/pkg/prebuilts:ro"
        -v "$CACHE_ROOT/$product/openwrt:/pkg/openwrt"
        -v "$CACHE_ROOT/$product/ccache:/ccache"
        -v "$WORK_PATH:/work"
        -v /etc/localtime:/etc/localtime:ro
    )
    [ -f "$qcom_dir/BUNDLE_VERSION" ]  && args+=( -v "$qcom_dir/BUNDLE_VERSION:/pkg/BUNDLE_VERSION:ro" )
    [ -r "$qcom_dir/SHA256SUMS.spot" ] && args+=( -v "$qcom_dir/SHA256SUMS.spot:/pkg/SHA256SUMS.spot:ro" )

    # OpenWrt's own prebuilt tool/toolchain cache. set_openwrt_env.sh finds it
    # here by default and restores it automatically on the first app build,
    # instead of compiling gcc/binutils/musl from scratch.
    if [ -n "${openwrt_dir:-}" ]; then
        args+=( -v "$openwrt_dir/openwrt-prebuilt-backup:/pkg/openwrt-prebuilt-backup:ro" )
        [ -f "$openwrt_dir/BUNDLE_VERSION" ] && args+=( -v "$openwrt_dir/BUNDLE_VERSION:/pkg/OPENWRT_VERSION:ro" )
    fi

    if [ -n "${yocto_dir:-}" ]; then
        # llvm-arm-toolchain-ship is a toolchain and is mounted read-only like
        # every other one.
        args+=( -v "$yocto_dir/llvm-arm-toolchain-ship:/pkg/yocto/llvm-arm-toolchain-ship:ro" )
        # downloads is NOT a toolchain — it is bitbake's DL_DIR, and bitbake
        # writes into it whenever a recipe needs a tarball the bundle did not
        # carry. Mounting it read-only would break the first build that needs
        # anything new, so it is writable on purpose. Shipping it prefilled is
        # the entire reason this component exists: it turns the first cqm211
        # build from a long series of downloads into a local read.
        args+=( -v "$yocto_dir/downloads:/pkg/yocto/downloads" )
        [ -f "$yocto_dir/BUNDLE_VERSION" ] && args+=( -v "$yocto_dir/BUNDLE_VERSION:/pkg/YOCTO_VERSION:ro" )
    fi

    [ -d "$HOME/.ssh" ] && args+=( -v "$HOME/.ssh:/home/$__USERNAME/.ssh:ro" )

    if [ "$ENABLE_USB" = yes ]; then
        # Enough access to drive EDL/QDL and the DIAG serial port without
        # running the whole container privileged: 189 = USB devices,
        # 188 = USB serial. /dev/bus/usb is bound rslave so hotplugged
        # devices show up inside.
        args+=(
            --mount "type=bind,source=/dev/bus/usb,target=/dev/bus/usb,bind-propagation=rslave"
            --device-cgroup-rule "c 189:* rmw"
            --device-cgroup-rule "c 188:* rmw"
        )
        local gids="" g gid
        for g in plugdev dialout uucp; do
            gid="$(getent group "$g" 2>/dev/null | cut -d: -f3)"
            [ -n "$gid" ] && gids="${gids:+$gids,}$gid"
        done
        [ -n "$gids" ] && args+=( -e "CQM_GROUPS=$gids" )
    fi

    log "creating container $container ($product: $comps)"
    if [ -n "$DRYRUNCMD" ]; then
        echo "+ docker run ${args[*]} $IMAGE bash -l"
    else
        docker run "${args[@]}" "$IMAGE" bash -l >/dev/null
    fi
}

verify_container() {
    local container; container="$(container_for "$1")"
    [ -z "$DRYRUNCMD" ] || return 0
    log "checking the environment"
    # `docker exec` does not run the image entrypoint, so it would land as root
    # and leave root-owned files in the mounted work path. Carry the caller's
    # identity explicitly. -it only when there is a real terminal.
    local tty=()
    [ -t 0 ] && [ -t 1 ] && tty=(-i -t)
    docker exec "${tty[@]}" -u "$__UID:$__GID" \
        -e "HOME=/home/$__USERNAME" -e "USER=$__USERNAME" \
        "$container" cqm-doctor \
        || die "the environment check failed — see above. Builds from this container would not match CI."
}

# ===========================================================================
# Say where everything is going before spending an hour putting it there.
# -w and -r are independent, and it is not obvious: -w only sets where the
# source lives. Without -r the toolchain lands in $HOME, which on many machines
# is a small root partition.
print_plan() {
    local c dir probe fs free
    printf '%s==>%s Plan\n\n' "$C_INFO" "$C_OFF"
    printf '  products    %s\n' "$PRODUCTS"
    printf '  bundles     %s (version %s)\n\n' "$NEEDED_COMPONENTS" "$BUNDLE_VERSION"
    for c in $NEEDED_COMPONENTS; do
        dir="$(comp_dir "$c")"
        # df fails on a path that does not exist yet, so ask about the nearest
        # ancestor that does.
        probe="$dir"
        while [ ! -d "$probe" ] && [ "$probe" != / ]; do probe="$(dirname "$probe")"; done
        fs="$(df -h --output=target "$probe" 2>/dev/null | tail -1 | tr -d ' ' || true)"
        free="$(df -h --output=avail "$probe" 2>/dev/null | tail -1 | tr -d ' ' || true)"
        printf '  %-11s %s\n' "$c" "$dir"
        printf '              on %s, %s free — needs ~%s GB (change with -r)\n' "$fs" "$free" "$(comp_gb "$c")"
        if [ -f "$dir/.complete" ] && [ "$FORCE_FETCH" != yes ]; then
            printf '              already installed, will not be downloaded\n'
        elif [ -z "$(comp_url "$c")" ] && [ "$c" = qcom ] && [ -z "$TOOL_PATH$FILE_TOOL_PATH" ]; then
            printf '              %sno link given — pass -u and -c%s\n' "$C_WARN" "$C_OFF"
        fi
    done
    printf '\n  source      %s  ->  /work\n' "$WORK_PATH"
    printf '  image       %s\n' "$IMAGE"
    for c in $PRODUCTS; do
        printf '  container   %-38s (%s)\n' "$(container_for "$c")" "$(components_for "$c")"
        printf '  caches      %s\n' "$CACHE_ROOT/$c"
    done
    printf '\n'
}

main() {
    assert_no_legacy_collision
    print_plan

    if [ "$FETCH_ONLY" = yes ]; then
        acquire_all
        printf '\n'
        ok "Bundles installed under $CQM_ROOT"
        printf '\nTo build with them:\n\n    bash %s -w %s -p %s\n\n' \
            "$0" "$WORK_PATH" "$(printf '%s' "$PRODUCTS" | tr ' ' ',')"
        return 0
    fi

    ensure_docker
    for t in curl tar; do
        command -v "$t" >/dev/null 2>&1 || die "missing required tool: $t"
    done

    acquire_all
    pull_image

    local p
    for p in $PRODUCTS; do
        create_container "$p"
        verify_container "$p"
    done

    printf '\n'
    ok "DONE — $(printf '%s' "$PRODUCTS" | wc -w) container(s) ready for user $__USERNAME"
    cat <<EOF

  Work path : $WORK_PATH  ->  /work
  Bundles   : $(for c in $NEEDED_COMPONENTS; do printf '%s ' "$(comp_dir "$c")"; done)
  USB       : $([ "$ENABLE_USB" = yes ] && echo "passed through, flashing available" || echo "disabled")

Let start it
EOF
    for p in $PRODUCTS; do
        printf 'docker start -i %s\n' "$(container_for "$p")"
    done
    cat <<EOF

The other build environments in this repository were not modified.
EOF
}

main "$@"
