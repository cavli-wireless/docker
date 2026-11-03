# cqm2xx build environment

Docker build environment for Cavli firmware. The tool is `cqm2xx/cqm2xx-setup`; the old
one (`cqm22x/`) is unchanged and keeps working. This version covers **cqm220** only
(one product, `cqm220`). Other lines come later.

One container per user, `cqm2xx_<user>`, mirroring the host: same user name,
uid/gid and `$HOME`, so files a build writes come out owned by you.

## What gets installed

| # | Item | Source | Needed for |
|---|---|---|---|
| 1 | Qualcomm tools (`qcom`) | private GitHub release, `--internal` only | boot / tz / modem / meta, qcap |
| 2 | Kernel prebuilt tool (`kp220`: clang, build-tools, NDK) | public GitHub release `bundles-1.1.0` | kernel + ABL |
| 3 | OpenWrt prebuilt tool (`openwrt-prebuilt-backup`) | public GitHub release `bundles-1.1.0` | OpenWrt app build |

Items 2 and 3 need no login (about 7 GB unpacked, sha256-checked, resumable).
Item 1 is Cavli only: `cavli-wireless` org membership and a GitHub device login.

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
./cqm2xx-setup setup --internal cqm220 -m /path/to/src
docker exec --user $(id -un) cqm2xx_$(whoami) cqm-doctor
```

`update` brings the image and bundles up to date with the same mounts and mode.

## Build

Get the code and the exact build command from the line's manifest README
(`cqm22x-manifests`). Typical cqm220 build inside the container:

```bash
cd /path/to/src/<tree>/chipcode
./build/build.sh -t mbb-cavli -m app -V 1.0.0 -v perf      # app only (external)
./build/build.sh -t mbb-cavli -m all -V 1.0.0 -v perf      # full (internal)
```

An OpenWrt `app` build can fail at random under parallel make (gdbm, loc-core, and
similar). Re-run the same command; it passes.

## Offline, old files, other sources

- `--bundle-dir <dir>` (or `CQM_BUNDLE_DIR`) reads `<dir>/<component>/` instead of downloading.
- `CQM_BUNDLE_SOURCE=drive` takes items 2 and 3 from the old Google Drive files.
- `CQM_BUNDLES_REPO=<owner/repo>` points the public release elsewhere.

## Known state of this version

- Work in progress, reviewed step by step. Not yet changed from the old tool:
  `setup` still also stages the Buildroot bundle and the per-line OpenWrt cache from
  Google Drive; if Drive is over its quota it stops with "Drive returned a web page".
- The Qualcomm tools are still one archive (no per-line split yet).
- Not covered here: other lines (cqm211, cqm212); use the old tool `cqm22x/` for them.

## Other directories

- `cqm2xx/`: this tool (`cqm2xx-setup`).
- `cqm22x/`: the previous tool, `cqm22x-setup`, for all lines. Unchanged.
- `sdx/`, `sdx35/`, `c10qm/`, `cqs290/`, `le/`, `common/`: legacy environments, unchanged.
