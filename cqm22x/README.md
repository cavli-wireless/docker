# CQM22x build environment

Reproducible build environment for CQM220 firmware, for Cavli developers, CI
and customers alike — the same image everywhere, so a build that works on one
machine produces the same binaries on the others.

## Quick start

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/refs/heads/main/cqm22x/container_docker_helper.sh -O container_docker_helper.sh
bash container_docker_helper.sh -w /mnt/ -u '<toolchain bundle link>' -c '<sha256>'
docker start -i build_cqm22x_jammy_$(whoami)
```

Cavli supplies the bundle link and its sha256. The script installs Docker if it
is missing, downloads and verifies the bundle, unpacks it once, creates the
container and checks the environment. It is safe to re-run: a bundle already on
disk is not downloaded again.

Other ways to supply the toolchain:

```bash
# the archive is already on this machine
bash container_docker_helper.sh -w /mnt/ -f ~/cqm22x-pkg-1.0.0.tar.zst

# it is already unpacked somewhere
bash container_docker_helper.sh -w /mnt/ -t /data/cqm22x-pkg

# only fetch and unpack it, do not create a container
bash container_docker_helper.sh -u '<link>' -c '<sha256>' -n
```

`-h` lists every option.

## How it is put together

Two pieces, deliberately kept apart:

| | Contents | Size | Distribution |
|---|---|---|---|
| **Base image** | Ubuntu 22.04, Python 3.6/3.8/3.10, gcc-10, repo, dtc, rclone | ~2.4 GB | `ghcr.io/cavli-wireless-public/cqm22x/jammy/owrt`, public |
| **Toolchain bundle** | `/pkg` — HEXAGON, LLVM, linaro, sectools, prebuilts | ~12 GB packed, ~48 GB unpacked | supplied by Cavli, mounted read-only |

The bundle is kept out of the image for two reasons: this image is published
publicly and must contain no licensed material, and nobody can pull a 50 GB
image. Splitting them also means a toolchain update does not force everyone to
re-pull the base image, or the other way round.

**The bundle link is never committed here.** It points at Qualcomm proprietary
toolchains and is passed in with `-u` per recipient.

## The environment contract

`cqm-doctor` runs at the end of setup and asserts every value that can change
build output without producing an error:

```
interpreters   python3 = 3.8.12, python = 3.8.12, 3.6/3.8/3.10 present, _ctypes importable
toolchain      gcc/g++ = 10.5.0, /bin/sh -> bash, LANG = en_US.UTF-8
device tree    dtc 1.6.0, and a reference .dts compiles to a known sha256
bundle         required subtrees present, mounted read-only, spot checksums match
caches         /pkg/openwrt, /pkg/yocto/downloads, /ccache, /work writable
identity       not running as root, so build output is not root-owned
```

This is not ceremony. Two environments that were meant to be identical had
drifted to different default `python3` versions (3.10 against 3.8) and
different locales (POSIX against `en_US.UTF-8`) — which changes `sort`
collation and Python's default text encoding. Neither raised an error; the two
places simply built different things. The check makes that class of drift
impossible to miss.

Run it any time:

```bash
docker exec -u "$(id -u):$(id -g)" build_cqm22x_jammy_$(whoami) cqm-doctor
```

## Design notes

- **Nothing large lives in the container.** Toolchain, source and every build
  cache are bind mounts, so the container stays a few hundred kB and can be
  recreated at any time without losing work.
- **One image for everyone.** UID and GID are mapped at container start by
  `entrypoint.sh`, so there is no per-developer image to build and files
  written into the mounted work path stay owned by the caller.
- **Reproducible by construction.** The base is pinned by digest and every
  download in the `Dockerfile` is verified against a recorded sha256.
- **Caches are per product.** `cqm220-0` and `cqm220-3` never share an OpenWrt
  `build_dir` or `staging_dir`.
- **The toolchain is mounted read-only,** so a build cannot mutate the shared
  copy that everyone else depends on.
- **No `--privileged`.** USB works through device-cgroup rules scoped to USB
  (189) and USB serial (188), plus an `rslave` bind of `/dev/bus/usb` so
  hotplugged devices appear. Pass `-U` on a build-only machine.

## Layout on disk

```
$HOME/cqm22x                     (override with -r)
├── toolchain/<version>/         read-only bundle, one directory per version
└── cache/
    ├── shared/yocto-downloads/  source download cache
    ├── cqm220-0/{openwrt,ccache}
    └── cqm220-3/{openwrt,ccache}
```

Sources live wherever `-w` points, mounted at `/work`.

## Files

| File | Purpose |
|---|---|
| `container_docker_helper.sh` | Setup — the only file a new machine needs |
| `Dockerfile` | The public base image |
| `entrypoint.sh` | Runtime UID/GID mapping |
| `doctor.sh` | The environment contract, installed as `cqm-doctor` |
| `cqmdev` | Optional day-to-day wrapper (`sync`, `shell`, `build`, `status`) |
| `pack-bundle.sh` | Cavli-side: build and publish a toolchain bundle |

## Publishing a new toolchain bundle (Cavli only)

On a host with a known-good `/pkg`:

```bash
./pack-bundle.sh --version 1.0.1 --source /pkg --upload
```

That stages the licensed subtrees, writes `MANIFEST.txt` and a sampled
`SHA256SUMS.spot`, compresses with zstd and uploads the archive with its
checksum. Recipients then use the resulting link with `-u`.

## Relationship to the other directories here

None. `sdx/`, `sdx35/`, `c10qm/`, `cqs290/`, `le/` and `common/` are untouched
and keep working exactly as before. This environment uses its own image path,
its own `build_cqm22x_jammy_*` container names and its own directories, and
`container_docker_helper.sh` aborts rather than reuse any of theirs.
