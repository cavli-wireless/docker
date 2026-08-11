#!/bin/bash
# Runtime UID/GID mapping for the CQM22x build container.
#
# The old setup built a separate image per developer just to bake in their
# UID/GID. That meant every machine ran a slightly different image, and the
# per-user tag was rebuilt (and the container destroyed) on every setup run.
# Here the identity is applied at container start instead, so one published
# image serves every developer, CI and customers.
#
# Files created in bind-mounted workspaces still come out owned by the caller
# on the host, which is the only reason the mapping is needed at all.

set -euo pipefail

CQM_UID="${CQM_UID:-1000}"
CQM_GID="${CQM_GID:-1000}"
CQM_USER="${CQM_USER:-builder}"
CQM_GROUPS="${CQM_GROUPS:-}"   # extra host GIDs, comma separated (usb, dialout…)

if [[ "$(id -u)" -ne 0 ]]; then
    # Already running as an explicit --user; nothing to set up.
    exec "$@"
fi

if ! getent group "$CQM_GID" >/dev/null 2>&1; then
    groupadd -g "$CQM_GID" "$CQM_USER"
fi
primary_group="$(getent group "$CQM_GID" | cut -d: -f1)"

if ! getent passwd "$CQM_UID" >/dev/null 2>&1; then
    useradd -u "$CQM_UID" -g "$CQM_GID" -m -s /bin/bash "$CQM_USER"
fi
CQM_USER="$(getent passwd "$CQM_UID" | cut -d: -f1)"
home="$(getent passwd "$CQM_UID" | cut -d: -f6)"

# Passwordless sudo: the vendor build scripts call sudo for locale-gen and a
# few chown steps. The locale is already baked into the image, but the scripts
# are shared with CI and not ours to change here.
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$CQM_USER" > "/etc/sudoers.d/90-$CQM_USER"
chmod 0440 "/etc/sudoers.d/90-$CQM_USER"

# Join supplementary host groups so device nodes (USB/serial) are usable
# without running the whole container privileged.
if [[ -n "$CQM_GROUPS" ]]; then
    IFS=',' read -ra gids <<< "$CQM_GROUPS"
    for gid in "${gids[@]}"; do
        [[ -z "$gid" ]] && continue
        gname="hostgrp$gid"
        getent group "$gid" >/dev/null 2>&1 || groupadd -g "$gid" "$gname"
        usermod -aG "$(getent group "$gid" | cut -d: -f1)" "$CQM_USER"
    done
fi

# git needs to trust bind-mounted worktrees it does not own.
git config --system --add safe.directory '*' 2>/dev/null || true

for d in /ccache "$home"; do
    [[ -d "$d" ]] && chown "$CQM_UID:$CQM_GID" "$d" 2>/dev/null || true
done

# Surface the read-only toolchain bundle version, if one is mounted.
if [[ -r /pkg/BUNDLE_VERSION ]]; then
    export CQM_BUNDLE_VERSION="$(cat /pkg/BUNDLE_VERSION)"
fi

exec setpriv --reuid="$CQM_UID" --regid="$CQM_GID" --init-groups \
     env HOME="$home" USER="$CQM_USER" LOGNAME="$CQM_USER" \
         CQM_BUNDLE_VERSION="${CQM_BUNDLE_VERSION:-none}" \
     "$@"
