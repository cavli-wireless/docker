#!/bin/bash
# pack-qcom-release.sh — Cavli side only. Turn an already-packed qcom bundle
# dir (plain layout: *.tar.zst/*.tar + SHA256SUMS + BUNDLE_VERSION +
# MANIFEST.txt, e.g. from pack-bundle.sh --component qcom) into a GitHub
# release layout: files >1.9 GiB split into parts, SHA256SUMS regenerated
# over the parts + the untouched whole files.
#
#   ./pack-qcom-release.sh --source /path/to/qcom --outdir /tmp/qcom-release
#   gh release create qcom-1.1.0 /tmp/qcom-release/* -R cavli-wireless/cqm2xx-qcom-bundles
set -euo pipefail

SOURCE=""
OUTDIR=""
LIMIT_MB=$((1900))   # split anything bigger than this

log() { printf '\e[36m==>\e[0m %s\n' "$*"; }
die() { printf '\e[31m==> %s\e[0m\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
pack-qcom-release.sh --source DIR --outdir DIR

  --source DIR   packed qcom bundle dir (*.tar.zst/*.tar, SHA256SUMS, BUNDLE_VERSION)
  --outdir DIR   where to write the release layout (created)
  -h, --help     this text
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SOURCE="$2"; shift 2;;
        --outdir) OUTDIR="$2"; shift 2;;
        -h|--help) usage; exit 0;;
        *) die "unknown option: $1";;
    esac
done
[[ -n "$SOURCE" && -d "$SOURCE" ]] || die "--source DIR is required and must exist"
[[ -n "$OUTDIR" ]] || die "--outdir DIR is required"
[[ -f "$SOURCE/BUNDLE_VERSION" ]] || die "$SOURCE/BUNDLE_VERSION missing"

mkdir -p "$OUTDIR"
cp -f "$SOURCE/BUNDLE_VERSION" "$OUTDIR/"
[[ -f "$SOURCE/MANIFEST.txt" ]] && cp -f "$SOURCE/MANIFEST.txt" "$OUTDIR/"

: > "$OUTDIR/SHA256SUMS"
for f in "$SOURCE"/*.tar.zst "$SOURCE"/*.tar; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f")"
    size=$(stat -c%s "$f")
    limit=$(( LIMIT_MB * 1024 * 1024 ))
    if (( size > limit )); then
        log "splitting $name ($(du -h "$f" | cut -f1)) into ${LIMIT_MB}M parts"
        split -b "${LIMIT_MB}M" -d -a 3 "$f" "$OUTDIR/$name.part"
        ( cd "$OUTDIR" && sha256sum "$name".part[0-9][0-9][0-9] >> SHA256SUMS )
    else
        log "copying $name ($(du -h "$f" | cut -f1)), no split needed"
        cp -f "$f" "$OUTDIR/$name"
        ( cd "$OUTDIR" && sha256sum "$name" >> SHA256SUMS )
    fi
done

log "release layout ready at $OUTDIR"
du -sh "$OUTDIR"
echo "next: gh release create <tag> $OUTDIR/* -R cavli-wireless/cqm2xx-qcom-bundles"
