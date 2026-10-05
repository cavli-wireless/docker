#!/bin/bash
# pack-buildroot.sh — Cavli-side: pack the Buildroot bundle (prebuilt toolchain
# + dl cache) that cqm22x-setup extracts into <root>/buildroot (/pkg/buildroot).
#
#   ./pack-buildroot.sh --version 1.1.0 \
#       --toolchain cavli-br-toolchain-gcc14.3.0-musl1.2.6-armv7a-hf.tar.gz \
#       --dl ~/cqm22x/buildroot/dl [--outdir DIR] [--upload]
#
# Archive layout: toolchain/ dl/ BUNDLE_VERSION MANIFEST.txt SHA256SUMS
set -euo pipefail

VERSION="" TOOLCHAIN="" DL="" OUTDIR="$PWD" UPLOAD=no LEVEL=10
RCLONE_REMOTE="${CQM_RCLONE_REMOTE:-GGDrive}"
RCLONE_CONFIG_FILE="${CQM_RCLONE_CONFIG:-$HOME/rclone_fw_share.conf}"
REMOTE_DIR="${CQM_BUNDLE_REMOTE_DIR:-/cqm22x-buildenv/toolchain}"

log() { printf '\e[36m==>\e[0m %s\n' "$*"; }
die() { printf '\e[31m==> %s\e[0m\n' "$*" >&2; exit 1; }
usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)   VERSION="$2"; shift 2;;
        --toolchain) TOOLCHAIN="$2"; shift 2;;   # .tar.gz with toplevel toolchain/, or a dir
        --dl)        DL="$2"; shift 2;;
        --outdir)    OUTDIR="$2"; shift 2;;
        --level)     LEVEL="$2"; shift 2;;
        --upload)    UPLOAD=yes; shift;;
        -h|--help)   usage; exit 0;;
        *) die "unknown option: $1";;
    esac
done
[[ -n "$VERSION" && -n "$TOOLCHAIN" && -n "$DL" ]] || { usage; die "--version, --toolchain and --dl are required"; }
[[ -e "$TOOLCHAIN" ]] || die "toolchain not found: $TOOLCHAIN"
[[ -d "$DL" ]] || die "dl dir not found: $DL"

mkdir -p "$OUTDIR"
STAGE="$(mktemp -d -p "$OUTDIR" .pack-buildroot.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
chmod 0755 "$STAGE"

log "toolchain <- $TOOLCHAIN"
if [[ -d "$TOOLCHAIN" ]]; then
    rsync -a "$TOOLCHAIN/" "$STAGE/toolchain/"
else
    tar -xf "$TOOLCHAIN" -C "$STAGE"
fi
gcc="$(ls "$STAGE"/toolchain/bin/*-linux-*-gcc 2>/dev/null | head -1)"
[[ -x "$gcc" ]] || die "no cross gcc under toolchain/bin"
"$gcc" --version >/dev/null || die "$gcc does not run on this host"

# .lock files are flock targets Buildroot recreates; not payload.
log "dl <- $DL"
rsync -a --exclude=.lock "$DL/" "$STAGE/dl/"

printf '%s\n' "$VERSION" > "$STAGE/BUNDLE_VERSION"
{
    echo "CQM22x buildroot bundle $VERSION"
    echo "Buildroot prebuilt toolchain and source download cache — cqm220-0/3"
    echo "toolchain : $("$gcc" --version | head -1)"
    echo "dl        : $(find "$STAGE/dl" -type f | wc -l) files, $(du -sh "$STAGE/dl" | cut -f1)"
    echo "packed by : Cavli $(date -u +%F)"
    echo
    echo "Public sources and a toolchain built from them; no proprietary material."
} > "$STAGE/MANIFEST.txt"
( cd "$STAGE" && find toolchain dl -type f | LC_ALL=C sort | xargs -d '\n' sha256sum > SHA256SUMS )

ARCHIVE="$OUTDIR/cqm22x-buildroot-$VERSION.tar.zst"
log "creating $ARCHIVE (zstd -$LEVEL)"
tar --owner=0 --group=0 --numeric-owner \
    --use-compress-program="zstd -$LEVEL -T0 --long=27" -cf "$ARCHIVE" -C "$STAGE" .
( cd "$OUTDIR" && sha256sum "$(basename "$ARCHIVE")" ) > "$ARCHIVE.sha256.tmp"
mv -f "$ARCHIVE.sha256.tmp" "$ARCHIVE.sha256"
printf '\n  archive  %s\n  size     %s\n  sha256   %s\n\n' \
    "$ARCHIVE" "$(du -h "$ARCHIVE" | cut -f1)" "$(awk '{print $1}' "$ARCHIVE.sha256")"

if [[ "$UPLOAD" == yes ]]; then
    command -v rclone >/dev/null || die "rclone not found"
    log "uploading to ${RCLONE_REMOTE}:${REMOTE_DIR}"
    rclone --config "$RCLONE_CONFIG_FILE" copy "$ARCHIVE" "${RCLONE_REMOTE}:${REMOTE_DIR}/"
    rclone --config "$RCLONE_CONFIG_FILE" copy "$ARCHIVE.sha256" "${RCLONE_REMOTE}:${REMOTE_DIR}/"
    log "now set the Drive id + sha256 in BUNDLE_FILES_buildroot (cqm22x-setup)"
fi
