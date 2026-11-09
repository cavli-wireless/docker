# cqm2xx build environment

Docker build environment for Cavli firmware. The tool is `cqm2xx/cqm2xx-setup`; the old
one (`cqm22x/`) is unchanged and keeps working. This version covers **cqm220**,
**cqm212** and **cqm211** (one product per line: `cqm220`, `cqm212`, `cqm211`).

One container per user, `cqm2xx_<user>`, mirroring the host: same user name,
uid/gid and `$HOME`, so files a build writes come out owned by you.

## What gets installed

`setup` with no product installs all three lines; name one (`setup cqm212`) to add only that line (a line already installed stays).

| # | Item | Source | Needed for |
|---|---|---|---|
| 1 | Qualcomm tools (`qcom_common` + `qcom_220` / `qcom_212` / `qcom_211`) | private GitHub release, `--internal` only | boot / tz / modem / meta |
| 2 | Kernel prebuilt tool (cqm220: `kp220`; cqm212: `kp212`; clang, build-tools, NDK) | public GitHub release `bundles-1.1.0` | kernel + ABL |
| 3 | OpenWrt prebuilt cache (cqm220: `openwrt-prebuilt-backup`; cqm212: `openwrt212`) | public GitHub release `bundles-1.1.0` | OpenWrt tools and toolchain, not rebuilt |
| 4 | Yocto download cache (cqm211: `yocto-downloads`, about 24 GB) | public GitHub release `bundles-1.1.0` | Yocto sources, no internet fetch |

cqm211 uses items 4 and 1 only (no kernel prebuilt tool, no OpenWrt cache).

Items 2, 3 and 4 need no login (sha256-checked, resumable). Only the parts of the lines you
name are downloaded. Item 1 is Cavli only: `cavli-wireless` org membership and a GitHub
device login on the first download (the login is stored under `$CQM_ROOT/home` and reused).

## Before you start

- Linux host with Docker (your user can run `docker`), plus `jq`, `curl`, `tar`, `zstd`, `sha256sum`.
- Network access to `github.com` and `ghcr.io`; free disk for the bundles (several GB per line).
- Everything is kept under `$CQM_ROOT` (default `~/cqm2xx`). The container's `$HOME` is
  `$CQM_ROOT/home`, so your own git config and shell files are not in it.

## Install

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/main/cqm2xx/cqm2xx-setup && chmod +x cqm2xx-setup
./cqm2xx-setup setup cqm220 -m /path/to/src
./cqm2xx-setup status
docker exec -it --user $(id -un) -e HOME=$HOME cqm2xx_$(whoami) bash -l
```

`-m <dir>` mounts a host directory at the same path (repeatable). The source tree
and the build run inside that directory.

Internal (full build, adds the Qualcomm tools):

```bash
./cqm2xx-setup setup --internal cqm220 cqm212 -m /path/to/src
docker exec --user $(id -un) cqm2xx_$(whoami) cqm-doctor
```

`setup` and `update` recreate the container (stop anything running in it). The mode is sticky:
the last `--internal` is reused until you pass `--external`. `update` keeps the mounts and mode,
but takes the image and bundle versions from the script you have: download the newer script first.
`--name <x>` makes a separate container and state (`cqm2xx_<user>_<x>`).

## Build

Get the code and the exact build command from the line's manifest README
(`cqm22x-manifests`, `cqm212-manifests`, `cqm211-manifests`). Inside the container:

```bash
cd /path/to/src/<tree>/chipcode
./build/build.sh -t mbb-cavli -m app -V 1.0.0 -v perf      # cqm220 app only (external)
./build/build.sh -t cavli -m app -v perf                   # cqm212 app only (external)
./build/build.sh -t <target> -m all -v perf                # full (internal), same -t
bash build/bigfile_helper.sh after_pull                    # cqm211, after every sync (mandatory)
bash build/build.sh -m app                                 # cqm211 app only (external)
bash build/build.sh -m all                                 # cqm211 full (internal)
```

The OpenWrt tools and toolchain come from the cache, not a rebuild. Measured on a fresh sync,
`-m app`: cqm220 (branch `cavli_kuno_le_1_0`) 990 s, cqm212 (`main`) 1865 s (3437 s without the cache),
cqm211 (`main`) 3764 s (5591 s without the download cache).

- **Path limit (important).** The cache can only be restored into a tree whose `apps_proc/owrt`
  path is no longer than the path the cache was built at. Past that the cache cannot be restored: the build stops with an error or rebuilds the tools and
  toolchain from scratch (slow).
  Keep the source root short:

  | Line | Cache built at | Source root at most |
  |---|---|---|
  | cqm220 | 56 characters | 32 (the tree has `/chipcode/apps_proc/owrt` below it) |
  | cqm212 | 91 characters | 56 (the tree has `/chipcode/Kobuk_apps/apps_proc/owrt` below it) |

  cqm211 has no cache path limit, but a source root of about 100 characters or more breaks the Yocto build.
  Example: `/mnt/SSD_2TB/cqm220` is fine; `/mnt/SSD_M2/cav/workspaces/cqm220` (33) is too long.
- cqm212 needs the line's cache support (`cqm212-apps-proc`, branch `cavli_kobuk_le_1_1`,
  "restore tools/toolchain/hostpkg from a prebuilt cache"). Without it the build still works but
  rebuilds the tools and toolchain.
- An OpenWrt `app` build can fail at random under parallel make (gdbm, loc-core, init-mss,
  and similar). Re-run the same command (or `make package/<path>/clean` first); it passes.
- Do not move a tree after building: symlinks and the Python venv keep the old path.

## Offline, old files, other sources

- `--bundle-dir <dir>` (or `CQM_BUNDLE_DIR`) reads bundles from `<dir>/<component>/` instead of downloading;
  the directory is remembered for later runs and `update`. A component without a directory is
  still downloaded (qcom would ask for the GitHub login). Components and files:
  - `openwrt` (cqm220): `cqm22x-kp220-1.1.0.tar.zst`, `cqm22x-openwrt-prebuilt-backup-1.1.0.tar.zst`
  - `kprebuilts212`: `cqm22x-kp212-1.1.0.tar.zst`; `openwrt212`: `cqm22x-openwrt212-1.1.0.tar.zst`
  - `yocto` (cqm211): `cqm22x-yocto-downloads-1.1.0.tar.zst`
  - `--internal`: `qcom_common`, `qcom_220`, `qcom_212`, `qcom_211`, each `cqm22x-<part>-1.1.0.tar.zst` (joined, not `.partNN`)
  - every `<component>/` also holds a `BUNDLE_VERSION` file containing `1.1.0`.
- `CQM_BUNDLE_SOURCE=drive` takes items 2, 3 and 4 from the old Google Drive files (for cqm211 that stages the old `downloads` and `llvm-arm-toolchain-ship` packs) (not remembered by `update`).
- `CQM_BUNDLES_REPO=<owner/repo>` points the public release elsewhere.

## Known state of this version

- Work in progress, reviewed step by step. `setup` downloads only the items above; no Buildroot.
- The Qualcomm tools are split per line, so `--internal cqm212` does not download cqm220's.
- `cqm-doctor` reports `/pkg/prebuilts/clang` missing in a cqm212-only or cqm211-only container; cqm212 uses `/pkg/prebuilts-kobuk`, cqm211 needs neither, and both build fine.
- cqm211 external: only `-m app` (`-m meta` needs boot, tz and modem, so it fails without `--internal`).
- Not covered here: other lines; use the old tool `cqm22x/` for them.
