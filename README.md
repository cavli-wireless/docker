# cqm2xx build environment

Docker build environment for Cavli firmware. The tool is `cqm2xx/cqm2xx-setup`; the old
one (`cqm22x/`) is unchanged and keeps working. This version covers **cqm220** and
**cqm212** (one product per line: `cqm220`, `cqm212`). Other lines come later.

One container per user, `cqm2xx_<user>`, mirroring the host: same user name,
uid/gid and `$HOME`, so files a build writes come out owned by you.

## What gets installed

`setup` with no product installs both lines; name one (`setup cqm212`) to install only it.

| # | Item | Source | Needed for |
|---|---|---|---|
| 1 | Qualcomm tools (`qcom_common` + `qcom_220` / `qcom_212`) | private GitHub release, `--internal` only | boot / tz / modem / meta, qcap |
| 2 | Kernel prebuilt tool (cqm220: `kp220`; cqm212: `kp212`; clang, build-tools, NDK) | public GitHub release `bundles-1.1.0` | kernel + ABL |
| 3 | OpenWrt prebuilt cache (cqm220: `openwrt-prebuilt-backup`; cqm212: `openwrt212`) | public GitHub release `bundles-1.1.0` | OpenWrt tools and toolchain, not rebuilt |

Items 2 and 3 need no login (sha256-checked, resumable). Only the parts of the lines you
name are downloaded. Item 1 is Cavli only: `cavli-wireless` org membership and a GitHub
device login on the first download (the login is kept for later runs).

## Install

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/main/cqm2xx/cqm2xx-setup && chmod +x cqm2xx-setup
./cqm2xx-setup setup cqm220 -m /path/to/src       # flags go after "setup"
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

`update` brings the image and bundles up to date with the same mounts and mode.

## Build

Get the code and the exact build command from the line's manifest README
(`cqm22x-manifests`, `cqm212-manifests`). Inside the container:

```bash
cd /path/to/src/<tree>/chipcode
./build/build.sh -t mbb-cavli -m app -V 1.0.0 -v perf      # cqm220 app only (external)
./build/build.sh -t cavli -m app -v perf                   # cqm212 app only (external)
./build/build.sh -t <target> -m all -v perf                # full (internal), same -t
```

The OpenWrt tools and toolchain come from the cache, not a rebuild. Measured on a fresh sync,
`-m app`: cqm220 (branch `cavli_kuno_le_1_0`) 990 s, cqm212 (`main`) 1865 s (3437 s without the cache).

- **Path limit (important).** The cache can only be restored into a tree whose `apps_proc/owrt`
  path is no longer than the path the cache was built at. Past that the cache cannot be restored: the build stops with an error or rebuilds the tools and
  toolchain from scratch (slow).
  Keep the source root short:

  | Line | Cache built at | Source root at most |
  |---|---|---|
  | cqm220 | 56 characters | 32 (the tree has `/chipcode/apps_proc/owrt` below it) |
  | cqm212 | 91 characters | 56 (the tree has `/chipcode/Kobuk_apps/apps_proc/owrt` below it) |

  Example: `/mnt/SSD_2TB/cqm220` is fine; `/mnt/SSD_M2/cav/workspaces/cqm220` (33) is too long.
- cqm212 needs the line's cache support (`cqm212-apps-proc`, branch `cavli_kobuk_le_1_1`,
  "restore tools/toolchain/hostpkg from a prebuilt cache"). Without it the build still works but
  rebuilds the tools and toolchain.
- An OpenWrt `app` build can fail at random under parallel make (gdbm, loc-core, init-mss,
  and similar). Re-run the same command (or `make package/<path>/clean` first); it passes.
- Do not move a tree after building: symlinks and the Python venv keep the old path.

## Offline, old files, other sources

- `--bundle-dir <dir>` (or `CQM_BUNDLE_DIR`) reads `<dir>/<component>/` instead of downloading.
- `CQM_BUNDLE_SOURCE=drive` takes items 2 and 3 from the old Google Drive files.
- `CQM_BUNDLES_REPO=<owner/repo>` points the public release elsewhere.

## Known state of this version

- Work in progress, reviewed step by step. `setup` downloads only the items above; no Buildroot.
- The Qualcomm tools are split per line, so `--internal cqm212` does not download cqm220's.
- `cqm-doctor` reports `/pkg/prebuilts/clang` missing in a cqm212-only container; cqm212 uses `/pkg/prebuilts-kobuk` and builds fine.
- Not covered here: other lines (cqm211); use the old tool `cqm22x/` for them.

## Other directories

- `cqm2xx/`: this tool (`cqm2xx-setup`).
- `cqm22x/`: the previous tool, `cqm22x-setup`, for all lines. Unchanged.
- `sdx/`, `sdx35/`, `c10qm/`, `cqs290/`, `le/`, `common/`: legacy environments, unchanged.
