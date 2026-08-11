#!/bin/bash
#
# container_docker_helper.sh — CQM22x build container setup.
#
#   wget https://raw.githubusercontent.com/cavli-wireless/docker/refs/heads/main/cqm22x/container_docker_helper.sh -O container_docker_helper.sh
#   bash container_docker_helper.sh -w /mnt/ -u '<google drive link to the pkg bundle>'
#   docker start -i build_cqm22x_jammy_$(whoami)
#
# The container image itself is public and carries no licensed material. The
# Qualcomm toolchain lives in a separate ~12 GB bundle that Cavli supplies a
# link to; this script downloads it, verifies it, unpacks it once and mounts it
# read-only. A bundle already on disk is not downloaded again.
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

  Sets up the CQM22x build container: installs Docker if it is missing,
  fetches and verifies the Qualcomm toolchain bundle, creates the container
  and checks that the environment matches the one CI builds with.

  Safe to re-run. Anything already in place is left alone.

  options:
  -h: print help
  -d: dry run: print what will be done
  -w: working path for sources, mounted at /work
  -u: URL of the toolchain bundle — a Google Drive share link or any
      direct HTTPS URL. Cavli supplies this.
  -c: expected sha256 of the bundle (strongly recommended; Cavli
      publishes it alongside the link)
  -t: path to an already-extracted bundle; skips the download
  -f: path to an already-downloaded .tar.zst; skips the download
  -r: root directory for the bundle and build caches
      (default $HOME/cqm22x)
  -p: product: cqm220-0 or cqm220-3          (default cqm220-3)
  -k: keep the downloaded archive after unpacking
  -F: re-download even if the bundle is already installed
  -P: do not pull the image; use the local copy
  -D: do not install Docker; fail if it is missing
  -U: do not pass USB through (build only, no flashing)
  -R: replace an existing container

EXAMPLES
  # a fresh machine
  bash container_docker_helper.sh -w /mnt/ -u '<drive link>' -c <sha256>

  # the bundle file is already here
  bash container_docker_helper.sh -w /mnt/ -f ~/cqm22x-pkg-1.0.0.tar.zst

  # only fetch and unpack the bundle, do not build a container
  bash container_docker_helper.sh -u '<drive link>' -c <sha256> -n

NOTE
  This container is based on ghcr.io/cavli-wireless-public/cqm22x/jammy/owrt
  The container user is created from the caller's own uid/gid, so files
  written into the mounted work path stay owned by you.
  Roughly 60 GB of free space is needed for the bundle.
EOF
}

# ---- defaults --------------------------------------------------------------
DOCKER_PRV_NAME=build_cqm22x_jammy
DOCKER_IMG="${CQM_IMAGE_REPO:-ghcr.io/cavli-wireless-public/cqm22x/jammy/owrt}"
DOCKER_IMG_TAG="${CQM_IMAGE_TAG:-latest}"
LEGACY_IMAGES="sdx/jammy/owrt cqm220/jammy/owrt sdx35/jammy/owrt"

BUNDLE_VERSION="${CQM_BUNDLE_VERSION:-1.0.0}"
CQM_ROOT="${CQM_ROOT:-$HOME/cqm22x}"
WORK_PATH=""
PKG_URL=""
PKG_SHA256=""
TOOL_PATH=""
FILE_TOOL_PATH=""
PRODUCT=cqm220-3
KEEP_ARCHIVE=no
FORCE_FETCH=no
SKIP_PULL=no
INSTALL_DOCKER=yes
ENABLE_USB=yes
RECREATE=no
FETCH_ONLY=no
DRYRUNCMD=""

while getopts "hdw:u:c:t:f:r:p:kFPDURn" flag; do
  case $flag in
    d) DRYRUNCMD="echo";;
    w) WORK_PATH=$OPTARG;;
    u) PKG_URL=$OPTARG;;
    c) PKG_SHA256=$OPTARG;;
    t) TOOL_PATH=$OPTARG;;
    f) FILE_TOOL_PATH=$OPTARG;;
    r) CQM_ROOT=$OPTARG;;
    p) PRODUCT=$OPTARG;;
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

case "$PRODUCT" in
    cqm220-3) DOCKER_CONTAINER="${DOCKER_PRV_NAME}_${__USERNAME}";;
    cqm220-0) DOCKER_CONTAINER="${DOCKER_PRV_NAME}_${__USERNAME}_${PRODUCT}";;
    *) die "unknown product: $PRODUCT (expected cqm220-0 or cqm220-3)";;
esac

BUNDLE_ROOT="$CQM_ROOT/toolchain"
CACHE_ROOT="$CQM_ROOT/cache"
BUNDLE_DIR="$BUNDLE_ROOT/$BUNDLE_VERSION"
IMAGE="$DOCKER_IMG:$DOCKER_IMG_TAG"
[[ -n "$WORK_PATH" ]] || WORK_PATH="$CQM_ROOT/workspace"

count=0
[[ -n "$PKG_URL" ]]        && count=$((count+1))
[[ -n "$TOOL_PATH" ]]      && count=$((count+1))
[[ -n "$FILE_TOOL_PATH" ]] && count=$((count+1))
(( count <= 1 )) || die "give only one of -u, -t or -f"

# ===========================================================================
# Guards — the other build environments in this repository are off limits
# ===========================================================================
assert_no_legacy_collision() {
    local legacy
    for legacy in $LEGACY_IMAGES; do
        [[ "$DOCKER_IMG" != *"$legacy" ]] \
            || die "refusing to use $legacy — other projects depend on that image"
    done
    [[ "$DOCKER_CONTAINER" == "${DOCKER_PRV_NAME}_"* ]] \
        || die "container name '$DOCKER_CONTAINER' is outside the ${DOCKER_PRV_NAME}_* namespace"
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

# Google Drive will not hand over a large file on the first request: it answers
# with an HTML page carrying a confirmation token that has to be posted back.
# Reproducing that exchange here means the target machine needs nothing beyond
# curl — no gdown, no rclone, no Google account.
fetch_gdrive() {
    local id="$1" dest="$2" cookie page confirm uuid
    cookie="$(mktemp)"; page="$(mktemp)"
    # shellcheck disable=SC2064
    trap "rm -f '$cookie' '$page'" RETURN

    log "resolving Google Drive file $id"
    curl -sL -c "$cookie" -o "$page" "https://drive.google.com/uc?export=download&id=${id}"

    if head -c 512 "$page" | grep -qiE '<!doctype html|<html'; then
        if grep -qiE 'quota|too many users|cannot currently be viewed' "$page"; then
            die "Google Drive is refusing this file right now (download quota exceeded).
Try again later, or ask Cavli for a direct HTTPS mirror and pass that to -u."
        fi
        confirm="$(grep -oE 'name="confirm" value="[^"]*"' "$page" | head -1 | sed -E 's/.*value="([^"]*)".*/\1/')"
        uuid="$(grep -oE 'name="uuid" value="[^"]*"' "$page" | head -1 | sed -E 's/.*value="([^"]*)".*/\1/')"
        log "downloading (large-file confirmation accepted)"
        curl -L -b "$cookie" -C - --retry 5 --retry-delay 5 --progress-bar -o "$dest" \
            "https://drive.usercontent.google.com/download?id=${id}&export=download&confirm=${confirm:-t}&uuid=${uuid}"
    else
        log "downloading"
        curl -L -b "$cookie" -C - --retry 5 --progress-bar -o "$dest" \
            "https://drive.google.com/uc?export=download&id=${id}"
    fi
}

fetch_any() {
    local url="$1" dest="$2" id
    id="$(gdrive_file_id "$url")"
    if [ -n "$id" ]; then fetch_gdrive "$id" "$dest"
    else log "downloading $url"; curl -fL --retry 5 --retry-delay 5 -C - --progress-bar -o "$dest" "$url"
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
    local archive="$1" sumfile="$2" want="" got
    if [ -n "$PKG_SHA256" ]; then
        want="$PKG_SHA256"
    else
        # A plain HTTPS mirror publishes <url>.sha256 next to the archive. A
        # Drive link cannot: every Drive file has its own id, so appending
        # ".sha256" would just be a malformed id. Hence -c.
        if [ -n "$PKG_URL" ] && [ -z "$(gdrive_file_id "$PKG_URL")" ]; then
            fetch_any "${PKG_URL}.sha256" "$sumfile" >/dev/null 2>&1 || true
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

extract_archive() {
    local archive="$1" dest="$2" root
    command -v zstd >/dev/null 2>&1 || die "zstd is required to unpack the bundle (sudo apt install zstd)"
    log "unpacking to $dest — this takes several minutes"
    rm -rf "$dest.partial"; mkdir -p "$dest.partial"
    # --long=27 must match the window the bundle was packed with.
    tar --use-compress-program="zstd -d -T0 --long=27" -xf "$archive" -C "$dest.partial"
    root="$dest.partial"
    if [ ! -d "$root/qct" ]; then
        root="$(find "$dest.partial" -mindepth 1 -maxdepth 1 -type d | head -1)"
        [ -d "$root/qct" ] || die "unexpected archive layout: no qct/ directory inside"
    fi
    rm -rf "$dest"; mv "$root" "$dest"; rm -rf "$dest.partial"
    chmod 0755 "$dest"
}

finalise_bundle() {
    local dir="$1" required
    for required in qct/software sectools prebuilts; do
        [ -d "$dir/$required" ] || die "bundle is incomplete: $dir/$required is missing"
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
    ok "bundle $BUNDLE_VERSION ready ($(du -sh "$dir" | cut -f1)) at $dir"
}

acquire_bundle() {
    # -t points at a bundle the caller already unpacked; use it in place.
    if [ -n "$TOOL_PATH" ]; then
        [ -d "$TOOL_PATH/qct/software" ] \
            || die "-t $TOOL_PATH does not look like an unpacked bundle (no qct/software)"
        BUNDLE_DIR="$TOOL_PATH"
        log "using the bundle at $BUNDLE_DIR"
        [ -f "$BUNDLE_DIR/BUNDLE_VERSION" ] || printf '%s\n' "$BUNDLE_VERSION" > "$BUNDLE_DIR/BUNDLE_VERSION" 2>/dev/null || true
        return 0
    fi

    if [ -f "$BUNDLE_DIR/.complete" ] && [ "$FORCE_FETCH" != yes ]; then
        ok "bundle $BUNDLE_VERSION is already installed at $BUNDLE_DIR — nothing to download"
        log "(pass -F to replace it)"
        return 0
    fi

    [ -n "$PKG_URL" ] || [ -n "$FILE_TOOL_PATH" ] \
        || die "no bundle given. Use -u <link>, -f <archive> or -t <unpacked directory>."

    mkdir -p "$BUNDLE_ROOT"
    local archive sumfile downloaded=no
    if [ -n "$FILE_TOOL_PATH" ]; then
        [ -f "$FILE_TOOL_PATH" ] || die "not a file: $FILE_TOOL_PATH"
        archive="$FILE_TOOL_PATH"
        sumfile="$FILE_TOOL_PATH.sha256"
    else
        check_free_space "$BUNDLE_ROOT" 75
        archive="$BUNDLE_ROOT/cqm22x-pkg-${BUNDLE_VERSION}.tar.zst"
        sumfile="$archive.sha256"
        fetch_any "$PKG_URL" "$archive"
        downloaded=yes
    fi

    verify_archive "$archive" "$sumfile"
    extract_archive "$archive" "$BUNDLE_DIR"
    finalise_bundle "$BUNDLE_DIR"

    if [ "$downloaded" = yes ] && [ "$KEEP_ARCHIVE" != yes ]; then
        log "removing $(basename "$archive") (-k to keep it)"
        rm -f "$archive" "$sumfile"
    fi
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
    bash $0 -w "$WORK_PATH" -t "$BUNDLE_DIR" -P

EOF
    exit 1
}

create_container() {
    if docker ps -a --format '{{.Names}}' | grep -qx "$DOCKER_CONTAINER"; then
        if [ "$RECREATE" != yes ]; then
            log "container $DOCKER_CONTAINER already exists — reusing it (-R to rebuild)"
            docker start "$DOCKER_CONTAINER" >/dev/null
            return
        fi
        log "removing the existing container $DOCKER_CONTAINER"
        run docker rm -f "$DOCKER_CONTAINER" >/dev/null
    fi

    # Validate every bind source up front. Docker silently creates an empty
    # directory for a missing one, which turns a clear setup error into a
    # confusing "toolchain not found" halfway through a build.
    local missing=() p
    for p in qct/software/HEXAGON_Tools qct/software/arm qct/software/llvm sectools prebuilts; do
        [ -e "$BUNDLE_DIR/$p" ] || missing+=("$p")
    done
    [ ${#missing[@]} -eq 0 ] || die "the bundle at $BUNDLE_DIR is missing: ${missing[*]}"

    # Caches are kept per product: the two products must not share one OpenWrt
    # build_dir and staging_dir.
    mkdir -p "$CACHE_ROOT/shared/yocto-downloads" \
             "$CACHE_ROOT/$PRODUCT/openwrt" \
             "$CACHE_ROOT/$PRODUCT/ccache" \
             "$WORK_PATH"

    local -a args=(
        --name "$DOCKER_CONTAINER" --hostname "$DOCKER_PRV_NAME"
        # -dit with bash as the command, so `docker start -i` attaches to a
        # login shell — the same way every other helper in this repository
        # behaves. No --restart: the container is meant to end when you exit.
        -dit
        -e "TERM=xterm-256color"
        -e "CQM_UID=$__UID" -e "CQM_GID=$__GID" -e "CQM_USER=$__USERNAME"
        -e "CQM_PRODUCT=$PRODUCT"
        --add-host "${DOCKER_PRV_NAME}:127.0.0.1"
        -v "$BUNDLE_DIR/qct/software/HEXAGON_Tools:/pkg/qct/software/HEXAGON_Tools:ro"
        -v "$BUNDLE_DIR/qct/software/arm:/pkg/qct/software/arm:ro"
        -v "$BUNDLE_DIR/qct/software/llvm:/pkg/qct/software/llvm:ro"
        -v "$BUNDLE_DIR/sectools:/pkg/sectools:ro"
        -v "$BUNDLE_DIR/prebuilts:/pkg/prebuilts:ro"
        -v "$CACHE_ROOT/$PRODUCT/openwrt:/pkg/openwrt"
        -v "$CACHE_ROOT/$PRODUCT/ccache:/ccache"
        -v "$CACHE_ROOT/shared/yocto-downloads:/pkg/yocto/downloads"
        -v "$WORK_PATH:/work"
        -v /etc/localtime:/etc/localtime:ro
    )
    [ -f "$BUNDLE_DIR/BUNDLE_VERSION" ]  && args+=( -v "$BUNDLE_DIR/BUNDLE_VERSION:/pkg/BUNDLE_VERSION:ro" )
    [ -r "$BUNDLE_DIR/SHA256SUMS.spot" ] && args+=( -v "$BUNDLE_DIR/SHA256SUMS.spot:/pkg/SHA256SUMS.spot:ro" )
    [ -d "$HOME/.ssh" ]                  && args+=( -v "$HOME/.ssh:/home/$__USERNAME/.ssh:ro" )

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

    log "creating container $DOCKER_CONTAINER"
    if [ -n "$DRYRUNCMD" ]; then
        echo "+ docker run ${args[*]} $IMAGE bash -l"
    else
        docker run "${args[@]}" "$IMAGE" bash -l >/dev/null
    fi
}

verify_container() {
    [ -z "$DRYRUNCMD" ] || return 0
    log "checking the environment"
    # `docker exec` does not run the image entrypoint, so it would land as root
    # and leave root-owned files in the mounted work path. Carry the caller's
    # identity explicitly. -it only when there is a real terminal.
    local tty=()
    [ -t 0 ] && [ -t 1 ] && tty=(-i -t)
    docker exec "${tty[@]}" -u "$__UID:$__GID" \
        -e "HOME=/home/$__USERNAME" -e "USER=$__USERNAME" \
        "$DOCKER_CONTAINER" cqm-doctor \
        || die "the environment check failed — see above. Builds from this container would not match CI."
}

# ===========================================================================
main() {
    assert_no_legacy_collision

    if [ "$FETCH_ONLY" = yes ]; then
        acquire_bundle
        printf '\n'
        ok "Bundle installed at $BUNDLE_DIR"
        printf '\nTo build with it:\n\n    bash %s -w %s -t %s\n\n' "$0" "$WORK_PATH" "$BUNDLE_DIR"
        return 0
    fi

    ensure_docker
    for t in curl tar; do
        command -v "$t" >/dev/null 2>&1 || die "missing required tool: $t"
    done
    acquire_bundle
    pull_image
    create_container
    verify_container

    cat <<EOF

$(ok "DONE create container $DOCKER_CONTAINER for user $__USERNAME")

  Work path : $WORK_PATH  ->  /work
  Tools     : $BUNDLE_DIR  ->  /pkg  (read-only)
  Caches    : $CACHE_ROOT/$PRODUCT
  USB       : $([ "$ENABLE_USB" = yes ] && echo "passed through, flashing available" || echo "disabled")

Let start it
docker start -i $DOCKER_CONTAINER

The other build environments in this repository were not modified.
EOF
}

main "$@"
