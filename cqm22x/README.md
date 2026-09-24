# CQM22x build environment

Reproducible build environment for Cavli firmware, for Cavli developers, CI
and customers alike — the same image everywhere, so a build that works on one
machine produces the same binaries on the others.

Covers three product lines from one image:

| Product | Chip | Userspace | Bundles it needs |
|---|---|---|---|
| `cqm220-3` | sdx35 | OpenWrt | qcom + openwrt |
| `cqm220-0` | sdx32 | OpenWrt | qcom + openwrt |
| `cqm211` | sdx61/62/65 | Yocto | qcom + yocto |

## Quick start

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/refs/heads/main/cqm22x/container_docker_helper.sh -O container_docker_helper.sh
bash container_docker_helper.sh -w /mnt/ -u '<qcom bundle link>' -c '<sha256>'
docker start -i build_cqm22x_jammy_$(whoami)
```

Cavli supplies the **qcom** bundle link and its sha256 — that one archive is
proprietary and cannot be published. Everything else the script knows how to
fetch by itself.

The script installs Docker if it is missing, downloads and verifies the bundles
the selected products need, unpacks them once, creates one container per product
and checks each environment. It is safe to re-run: a bundle already on disk is
not downloaded again.

## Docker v2 (`cqm22x-setup`)

A newer, additive entry point, `cqm22x-setup`, for anyone starting fresh.
Unlike `container_docker_helper.sh` above (still works exactly as before,
one container per product), it creates **one container per user**,
`build_cqm2xx_<user>`, holding every installed product, and made to mirror
the host: same user name, uid/gid, groups, and `$HOME` — files a build writes
into a mounted workspace come out owned by you, and paths behave the same
inside and outside the container.

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/main/cqm22x/cqm22x-setup && chmod +x cqm22x-setup
./cqm22x-setup setup              # all products, one container, no qcom (customer)
./cqm22x-setup setup cqm211       # add a product; re-run later to add another
./cqm22x-setup setup --full       # internal: also install Qualcomm tools (GitHub login, no password)
./cqm22x-setup update             # image + bundles, in place, same mounts, same mode
./cqm22x-setup status
docker exec -it --user $(id -un) -e HOME=$HOME build_cqm2xx_$(whoami) bash -l
```

By default `setup` never fetches, stages or mounts anything Qualcomm — a
customer gets a working openwrt/yocto build environment with no qcom bundle
and no login prompt. `--full` (internal use) logs in to GitHub with a device
code — access is `cavli-wireless` org membership, no password — and pulls
the qcom bundle from a private release; the mode is remembered in the state
file, so plain `setup`/`update` afterwards keep it without repeating the
flag. `status` shows `mode: customer` or `mode: full`. In customer mode,
`cqm-doctor` reports qcom checks as "not installed (customer install)"
instead of failing, and a shell opened with `bash -l` prints a reminder that
modem/tz/boot builds need the full install.

Home inside is `$CQM_ROOT/home` (never your real one) bind-mounted at your
host `$HOME` path; `~/.ssh` is mounted read-only at the same path by default
(skipped if you don't have one, `--no-ssh` to turn it off). `-m <dir>`
(repeatable) mounts an extra host directory at the same path — the default,
always mounted, is `$CQM_ROOT/workspace`. Mounts and flags are remembered in
the state file and reused by `update` and later `setup` runs.

`CQM_ROOT` defaults to `$HOME/cqm22x`, so `$CQM_ROOT/workspace` (or an `-m`
dir under it) sits inside the home bind mount; Docker auto-creates its
mountpoint through that bind at container start, leaving an empty root-owned
stub inside `$CQM_ROOT/home` — harmless, but `rm -rf $CQM_ROOT` then needs
`sudo` for that one stub. Set `CQM_ROOT` outside `$HOME` to avoid it.

`--full` runs a throwaway container from the same image (mounting your
`$CQM_ROOT/home` and `$CQM_ROOT/qcom`) that checks `gh auth status` and, if
needed, prints a device code and URL for `gh auth login --web` — open it in
any browser, on any machine, works the same over SSH since nothing needs a
browser on the host. It then downloads the qcom release, verifies
`SHA256SUMS` and unpacks it. The GitHub token stays in
`$CQM_ROOT/home/.config/gh` (mode 600) and is reused by later `update`s — not
an org member, or no access, and it fails with one clear error and installs
nothing. openwrt and yocto are public and need neither `--full` nor a login;
their links are already in the script. Full walkthrough and the per-product
links: the manifests repo's README (`cqm22x-manifests`, `cqm211-manifests`,
`cqm212-manifests`).

Already have the bundles on disk (offline, or no network)? `--bundle-dir
<dir>` (or `CQM_BUNDLE_DIR`) reads `<dir>/<component>/` instead — same layout
as the upload (files + `SHA256SUMS` + `BUNDLE_VERSION`), still checked
against the pinned checksums. qcom is the plain per-file layout, no login
needed:

```bash
./cqm22x-setup --bundle-dir /path/to/pkg-bundles setup --full cqm220-3
```

The directory is remembered in the state file, so a later `update` keeps
using it.

Everything under `/pkg/...` stays container-only and may differ from the
host. The qcom bundle and the read-only openwrt/yocto toolchains are shared
(identical regardless of which installed product uses them); the *writable*
ccache and OpenWrt build_dir/staging_dir caches are namespaced per product —
`/ccache/<product>` and `/pkg/openwrt/<product>` — so two openwrt products
(cqm220-0/cqm220-3) sharing one container never share one ccache or build
cache. Neither path is hardcoded by `set_openwrt_env.sh` or the build
scripts, so this needs no build-script change: point `CCACHE_DIR` (and, if
you use it, your build_dir/staging_dir symlink) at the `/<product>` subpath
for whichever product you are building, e.g. `export
CCACHE_DIR=/ccache/cqm220-0`.

`cqm-doctor` inside a v2 container checks every installed product by
default, or one: `docker exec --user $(id -un) build_cqm2xx_$(whoami)
cqm-doctor cqm211`.

Pick products with `-p` (old flow):

```bash
# sdx35 (the default)
bash container_docker_helper.sh -w /mnt/ -u '<link>' -c '<sha256>'

# sdx61/62/65
bash container_docker_helper.sh -w /mnt/ -p cqm211 -u '<link>' -c '<sha256>'

# both, downloading the shared qcom bundle only once
bash container_docker_helper.sh -w /mnt/ -p cqm220-3,cqm211 -u '<link>' -c '<sha256>'

# everything
bash container_docker_helper.sh -w /mnt/ -p all -u '<link>' -c '<sha256>'
```

Application developers who only build packages against the Cavli SDK tarball
do not need the qcom bundle at all:

```bash
# SDK only: openwrt bundle, no -u, container build_cqm22x_jammy_<user>_sdk
bash container_docker_helper.sh -p sdk -l -w ~/cqm-sdk
```

Other ways to supply the qcom bundle:

```bash
# the archive is already on this machine
bash container_docker_helper.sh -w /mnt/ -f ~/cqm22x-qcom-1.1.0.tar.zst

# it is already unpacked somewhere
bash container_docker_helper.sh -w /mnt/ -t /data/cqm22x-qcom

# only fetch and unpack, do not create containers
bash container_docker_helper.sh -p all -u '<link>' -c '<sha256>' -n
```

`-h` lists every option.

## How it is put together

One public image plus three bundles, deliberately kept apart:

| | Contents | Size | Needed by | Distribution |
|---|---|---|---|---|
| **Base image** | Ubuntu 22.04, Python 2.7/3.6/3.8/3.10, gcc-10, repo, dtc, rclone, bitbake host tools | ~2.4 GB | everything | `ghcr.io/cavli-wireless-public/cqm22x-buildenv`, public |
| **qcom** | HEXAGON, LLVM, linaro, sectools, prebuilts | ~13 GB packed, ~60 GB unpacked | every product | supplied by Cavli, mounted read-only |
| **yocto** | bitbake `DL_DIR` cache + LLVM/ARM toolchain | ~24 GB packed, ~27 GB unpacked | cqm211 | link built into the setup script |
| **openwrt** | OpenWrt prebuilt host tools and cross toolchain | ~2.3 GB packed, ~10 GB unpacked | cqm220-0/3 | link built into the setup script |

Nothing licensed is in the image, because it is published publicly — and nobody
can pull a 50 GB image anyway. Splitting also means a toolchain update does not
force everyone to re-pull the base image, or the other way round.

The bundles are split from each other for a plainer reason: the two cache
bundles serve different product lines. A cqm220 developer would otherwise
download 24 GB of Yocto sources they will never build, and a cqm211 developer
10 GB of OpenWrt toolchain they will never use. With the split, a cqm220 machine
pulls ~15 GB and a cqm211 machine ~37 GB, and a machine set up for both fetches
the shared qcom bundle exactly once.

**The qcom link is never committed here.** It points at Qualcomm proprietary
toolchains and is passed in with `-u` per recipient. The yocto and openwrt
bundles carry nothing proprietary — public source tarballs, an LLVM build and
OpenWrt's own host tools — so their links live in the script and no recipient
has to be told them.

## The environment contract

`cqm-doctor` runs at the end of setup and asserts every value that can change
build output without producing an error:

```
interpreters   python3 = 3.8.12, python = 3.8.12, 3.6/3.8/3.10 present, _ctypes importable
toolchain      gcc/g++ = 10.5.0, /bin/sh -> bash, LANG = en_US.UTF-8
device tree    dtc 1.6.0, and a reference .dts compiles to a known sha256
qcom bundle    required subtrees present, mounted read-only, spot checksums match
openwrt        prebuilt cache present            (cqm220-0/3 only)
yocto          LLVM/ARM toolchain present, DL_DIR prefilled   (cqm211 only)
caches         /ccache, /work and the product's own cache writable
identity       not running as root, so build output is not root-owned
```

This is not ceremony. Two environments that were meant to be identical had
drifted to different default `python3` versions (3.10 against 3.8) and
different locales (POSIX against `en_US.UTF-8`) — which changes `sort`
collation and Python's default text encoding. Neither raised an error; the two
places simply built different things. The check makes that class of drift
impossible to miss.

It checks the bundles the container's own product needs, and only those — a
cqm211 container is not expected to carry the OpenWrt cache, and vice versa.

Run it any time:

```bash
docker exec -u "$(id -u):$(id -g)" build_cqm22x_jammy_$(whoami) cqm-doctor
./cqmdev -p cqm211 doctor
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
- **Caches are per product.** `cqm220-0`, `cqm220-3` and `cqm211` never share an
  OpenWrt `build_dir` or `staging_dir`, which is why each product gets its own
  container rather than one container serving all of them.
- **Toolchains are mounted read-only,** so a build cannot mutate the shared copy
  that everyone else depends on. The one writable exception is bitbake's
  `DL_DIR`: it ships prefilled but has to accept new downloads, and it is a
  cache rather than a toolchain.
- **No `--privileged`.** USB works through device-cgroup rules scoped to USB
  (189) and USB serial (188), plus an `rslave` bind of `/dev/bus/usb` so
  hotplugged devices appear. Pass `-U` on a build-only machine.

## Layout on disk

```
$HOME/cqm22x                     (override with -r)
├── qcom/<version>/              read-only, every product mounts it
├── yocto/<version>/             cqm211 only — downloads/, llvm-arm-toolchain-ship/
├── openwrt/<version>/           cqm220-* only — openwrt-prebuilt-backup/
└── cache/
    ├── cqm220-3/{openwrt,ccache}
    ├── cqm220-0/{openwrt,ccache}
    └── cqm211/{openwrt,ccache}
```

Each bundle is versioned on its own, so several versions can sit side by side
and `-V` picks which one the containers mount.

Sources live wherever `-w` points, mounted at `/work`.

## Files

| File | Purpose |
|---|---|
| `container_docker_helper.sh` | Setup — the only file a new machine needs |
| `Dockerfile` | The public base image |
| `entrypoint.sh` | Runtime UID/GID mapping |
| `doctor.sh` | The environment contract, installed as `cqm-doctor` |
| `cqmdev` | Optional day-to-day wrapper (`sync`, `shell`, `build`, `status`) |
| `pack-bundle.sh` | Cavli-side: build and publish the qcom / yocto / openwrt bundles |
| `cqm22x-setup` | Docker v2 — setup/update/status, all products by default |
| `pack-qcom-release.sh` | Cavli-side: split qcom into a GitHub release layout (v2 `--full`) |

## Publishing a new toolchain bundle (Cavli only)

On a host with a known-good `/pkg`:

```bash
# all three
./pack-bundle.sh --component all --version 1.1.0 --source /pkg --upload

# just one
./pack-bundle.sh --component openwrt --version 1.1.0 --source /pkg --upload
```

Each run stages that component's subtrees, writes `MANIFEST.txt` and a sampled
`SHA256SUMS.spot`, compresses with zstd and uploads the archive with its
checksum.

- **qcom (v1, `container_docker_helper.sh`)** — hand the resulting link and
  sha256 to each recipient; they pass them to `-u` and `-c`. Never commit them.
- **yocto**, **openwrt** — make the Drive files link-shareable, then put the
  links and checksums in `container_docker_helper.sh` (see `URL_yocto` /
  `URL_openwrt` near the top).
- **qcom (v2, `cqm22x-setup --full`)** — private GitHub release, access via
  `cavli-wireless` org membership:
  ```bash
  ./pack-qcom-release.sh --source /pkg-or-packed-qcom-dir --outdir /tmp/qcom-release
  GH_TOKEN=$(gh auth token --user khoacavli) gh release create qcom-1.1.0 \
      /tmp/qcom-release/* -R cavli-wireless/cqm2xx-qcom-bundles
  ```
  Tag = bundle version (`qcom-<version>`); files over 1.9 GiB are split into
  parts by `pack-qcom-release.sh`, with `SHA256SUMS` covering the parts and
  the untouched whole files.

Compression level defaults per component: 15 for qcom, which is raw binaries
and compresses about 4:1, and 1 for the other two, whose payload is already
compressed — a high level there burns hours of CPU for a fraction of a percent.

## Relationship to the other directories here

None. `sdx/`, `sdx35/`, `c10qm/`, `cqs290/`, `le/` and `common/` are untouched
and keep working exactly as before. This environment uses its own image path,
its own `build_cqm22x_jammy_*` container names and its own directories, and
`container_docker_helper.sh` aborts rather than reuse any of theirs.
