# Cavli build environment

Docker build environment for Cavli firmware: **cqm220**, **cqm212**, **cqm211** and **aq62** (SA525M apps build).
One tool, `cavli/cavli-setup`, replaces `cqm2xx/cqm2xx-setup` and `aq62/aq62-setup`.

One container per user, `cavli_<user>`, holds all four products. It mirrors the host: same user name,
uid/gid and `$HOME`, so files a build writes come out owned by you.

## What gets installed

`setup` with no product installs all four; name some (`setup cqm212 aq62`) to add only those (installed ones stay).

| # | Item | Source | Needed for |
|---|---|---|---|
| 0 | Image `ghcr.io/cavli-wireless-public/cqm22x-buildenv:1.1.7` (pulled, never built locally) | public | everything; 1.1.7 carries the aq62 host tools |
| 1 | Qualcomm tools (`qcom_common` + `qcom_220` / `qcom_212` / `qcom_211`) | private GitHub release, `--internal` only | boot / tz / modem / meta (not aq62) |
| 2 | Kernel prebuilt tool (cqm220 and aq62: `kp220`; cqm212: `kp212`; clang, build-tools, NDK) | public GitHub release `bundles-1.1.0` | kernel + ABL |
| 3 | OpenWrt prebuilt cache (cqm220: `openwrt-prebuilt-backup`; cqm212: `openwrt212`) | public GitHub release (cqm220: `bundles-1.1.1`; cqm212: `bundles-1.1.0`) | OpenWrt tools and toolchain without a rebuild (cqm220: only with `-P`) |
| 4 | Yocto download cache `/pkg/yocto/downloads` (writable, one for the container) | cqm211: `yocto-downloads`, about 24 GB, public release `bundles-1.1.0`; aq62: filled by the builds, `setup` seeds the SELinux git mirror and four wireless-tools patches | Yocto sources |

cqm211 uses items 4 and 1 only. aq62 uses items 2 and 4 only: apps build (kernel + Yocto image), no modem, tz or boot,
so `--internal` adds nothing for it. aq62 takes the kernel prebuilts from cqm220's copy when cqm220 is installed
(`openwrt/<v>/prebuilts`), else it downloads the `kp220` pack alone (about 1 GB, 4.8 GB unpacked).

**cqm211 and aq62 share `/pkg/yocto/downloads`.** With cqm211 installed it is the staged `yocto/<v>/downloads`; without,
`$CAVLI_ROOT/downloads`. Adding cqm211 to an aq62 install copies the files of `$CAVLI_ROOT/downloads` into it (never
overwriting) once; the old directory can then be deleted.

Host tools added to the image for aq62: `checkpolicy`, `semodule-utils` (TelAF SELinux), `lz4`, `libxml2-utils`,
`mtd-utils` (`ubinize`), OpenJDK 8 (TelAF generator), Jinja2 2.11.3 for `/usr/bin/python3` and `python2.7`
(TelAF `ifgen`, with setuptools 44.1.1), `bz2` for `python2`, git fetching `git://git.codelinaro.org` over https, and
`tar` held at 1.34+dfsg-1build3 (the newer jammy tar breaks pseudo in Yocto `do_package`). The held `tar` applies to
every product in the container.

Items 2, 3 and 4 need no login (sha256-checked, resumable). Only the parts of the products you name are downloaded.
Item 1 is Cavli only: `cavli-wireless` org membership and a GitHub device login on the first download (the login is
stored under `$CAVLI_ROOT/home` and reused).

## Before you start

- Linux host with Docker (your user can run `docker`), plus `jq`, `curl`, `tar`, `zstd`, `sha256sum`.
- Network access to `github.com` and `ghcr.io` (aq62 seeding also `git.codelinaro.org`, `git.yoctoproject.org`);
  free disk for the bundles (several GB per product).
- Everything is kept under `$CAVLI_ROOT` (default `~/cavli`). The container's `$HOME` is `$CAVLI_ROOT/home`, so your
  own git config and shell files are not in it.
- GitHub ssh access to the repos you sync (`~/.ssh` is mounted read-only unless `--no-ssh`).

## Install

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/main/cavli/cavli-setup && chmod +x cavli-setup
./cavli-setup setup cqm220 -m /path/to/src
./cavli-setup status
docker exec -it --user $(id -un) -e HOME=$HOME cavli_$(whoami) bash -l
```

`-m <dir>` mounts a host directory at the same path (repeatable). The source tree and the build run inside that
directory.

Internal (full build, adds the Qualcomm tools):

```bash
./cavli-setup setup --internal cqm220 cqm212 -m /path/to/src
docker exec --user $(id -un) cavli_$(whoami) cqm-doctor
```

`setup` and `update` recreate the container (stop anything running in it). The mode is sticky: the last `--internal`
is reused until you pass `--external`. `update` keeps the mounts and mode, but takes the image and bundle versions from
the script you have: download the newer script first. `--name <x>` makes a separate container and state
(`cavli_<user>_<x>`); with a separate `CAVLI_ROOT` it is a fully isolated instance.

## Download speed

`setup` fetches everything at once: all products' bundles and the image pull run together, each GitHub file is cut
into 256 MB ranges taken by a pool of 8 connections (one connection gives about 35 MB/s, 4 or more fill a 1 Gb/s link),
and each bundle is read back in order as one stream `sha256 | zstd -d | tar`, so it unpacks while it downloads. The
sha256 is checked on that same stream; a mismatch removes the unpacked files and nothing is marked complete. Ranges stay
in `$CAVLI_ROOT/cache` until the bundle is verified, so an interrupted `setup` resumes. Each bundle prints its progress
(MB, MB/s, elapsed) every 10 s, and `setup` ends with a timing table.

- `CAVLI_DL_JOBS=<n>` connections (default 8), `CAVLI_DL_CHUNK_MB=<n>` range size (default 256).
  `CAVLI_DL_JOBS=0` is the old way, one file at a time.
- No extra tool: only `curl`, `tar`, `zstd`, `sha256sum`. Unpacking needs about as much free disk as the bundle is
  big, on top of the unpacked size, until it is verified.
- For `--internal` without a terminal (CI), `GH_TOKEN` in the environment is used instead of the device login; it is
  passed to the throwaway container and never written to disk.

## Coming from cqm2xx-setup or aq62-setup

| Old | New |
|---|---|
| `cqm2xx/cqm2xx-setup`, `aq62/aq62-setup` | `cavli/cavli-setup` (the old paths hold a stub that says so) |
| `CQM_ROOT` (`~/cqm2xx`), `AQ62_ROOT` (`~/aq62`) | `CAVLI_ROOT` (`~/cavli`); one root, state in `$CAVLI_ROOT/state/state.json` |
| container `cqm2xx_<user>`, `aq62_<user>` | `cavli_<user>` |
| `CQM_NAME_SUFFIX`, `CQM_BUNDLE_DIR`, `CQM_IMAGE_TAG`, `CQM_BUNDLE_SOURCE`, ... and the `AQ62_*` ones | `CAVLI_NAME_SUFFIX`, `CAVLI_BUNDLE_DIR`, `CAVLI_IMAGE_TAG`, `CAVLI_BUNDLE_SOURCE`, ... |
| image `aq62-buildenv` built locally | none: the aq62 tools are in `cqm22x-buildenv:1.1.7` |

- An old variable name still works when the `CAVLI_*` one is unset; the script prints which one it used.
- To reuse what you already downloaded: `CAVLI_ROOT=~/cqm2xx ./cavli-setup setup` (or `~/aq62`). The first run in a root
  that has `v2/state.json` from `cqm2xx-setup` takes over its products, mounts and flags (not its containers).
- The old containers are never touched. When `cavli_<user>` works, remove them yourself:
  `docker rm -f cqm2xx_$(whoami) aq62_$(whoami)`.
- aq62 users: `~/aq62/downloads` and `~/aq62/prebuilts` are reused with `CAVLI_ROOT=~/aq62`; run `setup aq62 -m <src>` again
  (mounts are not read from the old aq62 state).

## cqm220, cqm212, cqm211: build

Get the code and the exact build command from the product's manifest README
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

cqm220 builds the OpenWrt tools and toolchain itself by default, in parallel (`-j$(nproc)`); add `-P` to `build.sh` to
restore them from the cache instead. cqm212 always uses its cache. Measured on a fresh sync, `-m app`: cqm220 about
1600 s by default and 840 s with `-P` (20 cores), cqm212 (`main`) 1865 s (3437 s without the cache), cqm211 (`main`)
3764 s (5591 s without the download cache).

- **Path limit (important).** The cache can only be restored into a tree whose `apps_proc/owrt` path is no longer than
  the path the cache was built at. Past that the cache cannot be restored: cqm220 with `-P` says so and builds the tools
  and toolchain itself; cqm212 stops with an error or rebuilds them (slow). Keep the source root short:

  | Line | Cache built at | Source root at most |
  |---|---|---|
  | cqm220-0 | 100 characters | 76 (the tree has `/chipcode/apps_proc/owrt` below it) |
  | cqm220-3 | 100 characters | 59 (the tree has `/chipcode/OWRT.PRODUCT.2.1/apps_proc/owrt` below it) |
  | cqm212 | 91 characters | 56 (the tree has `/chipcode/Kobuk_apps/apps_proc/owrt` below it) |

  cqm211 and aq62 have no cache path limit, but a source root of about 100 characters or more breaks the Yocto build.
  Example for cqm212: `/mnt/SSD_2TB/cqm212` is fine. A cqm220 tree over the limit still builds, without the cache.
- cqm212 needs the line's cache support (`cqm212-apps-proc`, branch `cavli_kobuk_le_1_1`, "restore
  tools/toolchain/hostpkg from a prebuilt cache"). Without it the build still works but rebuilds the tools and toolchain.
- An OpenWrt `app` build can fail at random under parallel make (gdbm, loc-core, init-mss, and similar). Re-run the same
  command (or `make package/<path>/clean` first); it passes.
- Do not move a tree after building: symlinks and the Python venv keep the old path.
- cqm211 external: only `-m app` (`-m meta` needs boot, tz and modem, so it fails without `--internal`).

## aq62: lines, sync, build

| Line | Qualcomm drop | Code |
|---|---|---|
| es1, es2, es3 | SA525M.LE.1.0 (kernel 5.15.185) | `aq62_manifest` `release/aq62_es<n>_bringup_release`, `chipcode-aq62-release.xml` |
| main | SA525M.LE.1.0 | `aq62_manifest` `main`, `chipcode-aq62-release.xml` |
| le31 | SA525M.LE.3.1 (kernel 5.15.194) | `aq62_chipcode` + `aq62_apps_proc` `aq62_le_3.1_bringup`, `cqm22x-build-scripts` `sa525m-le3-1` (no manifest yet) |

SELinux upstream renamed `master` to `main`, while `meta-selinux` still pins `branch=master`, so a fresh fetch fails
("Unable to find revision … in branch master"). `setup` puts the CodeLinaro mirror clone (it still has `master`) into the
download cache under the upstream name, so no tree needs a change.

Sync (apps only: no modem):

```bash
cd /path/to/src/es3
repo init -u git@github.com:cavli-wireless/aq62_manifest.git -b release/aq62_es3_bringup_release -m chipcode-aq62-release.xml --depth=1
repo sync -j8 -c chipcode chipcode/SA525M_apps/apps_proc chipcode/build
repo forall chipcode chipcode/SA525M_apps/apps_proc chipcode/build -c 'git lfs pull'
```

le31 has no manifest: clone `aq62_chipcode` into `chipcode/`, `aq62_apps_proc` into `chipcode/SA525M_apps/apps_proc`
(both `aq62_le_3.1_bringup`) and `cqm22x-build-scripts` `sa525m-le3-1` into `chipcode/build`, then `git lfs pull` in each.

Build (apps only). Inside the container, once per tree link the download cache, then build the kernel and the Yocto image:

```bash
cd /path/to/src/es3/chipcode
[ -e SA525M_apps/apps_proc/downloads ] || ln -s /pkg/yocto/downloads SA525M_apps/apps_proc/downloads
./build/build.sh -m kernel,app -t pvm_ar -f RELEASE     # es1/es2/es3/main: perf kernel + qti-distro-tele-perf
./build/build.sh -m kernel,app -t pvm_ar -f DEBUG       # le31: its scripts build qti-distro-tele-debug
```

Output: `SA525M_apps/apps_proc/build-qti-distro-tele-<perf|debug>/tmp-glibc/deploy/images/sa525m/qti-tele-image/`.

- `-m app` alone fails at `linux-msm do_fetch` ("file://dist"): the image takes the kernel from
  `src/kernel-5.15/out/msm-kernel-sa525-<perf|debug>_defconfig/`, which `-m kernel` builds. Keep `-f` matching the Yocto
  variant of the line.
- `build.sh` returns 0 even when bitbake fails: read the last lines (`Build apps successfully` / `failed`).
- Do not move a tree after building: the Python venv and the build dir keep the old path.

### Build an AQ62 SDK

An SDK (`AQ62_<version>_SDK.tar`, made by `make_sdk_v2.sh`) holds `sdk/src/{apps_proc,build,common}`: the apps source,
`downloads.zip` (Yocto download cache) and three scripts. Inside the container:

```bash
tar -xf AQ62_0.0.3_SDK.tar -C /path/to/src && cd /path/to/src/sdk/src
mv apps_proc/.venv apps_proc/.venv.orig        # the shipped venv points at the maker's path; the script makes a new one
(cd /pkg/yocto && unzip -q -n /path/to/src/sdk/src/apps_proc/downloads.zip)
ln -s /pkg/yocto/downloads apps_proc/downloads
bash build/build.kernel.sh                      # perf kernel → apps_proc/src/kernel-5.15/out/
bash build/build.approc.sh                      # qti-tele-image, qti-distro-tele-perf
cp <modem>/NON-HLOS.ubifs build/ && (cd build && bash make_binary.sh)   # → build/binaries/{sysfs.ubi,boot.img,dtbo.img}
```

- `make_binary.sh` puts the modem image into `sysfs.ubi` (`modem_volume` in `sa525m_ubi_pvm_ar.ini`); the SDK has none,
  so copy the line's `NON-HLOS.ubifs` into `build/` (its `-m` option takes no value).
- Without the `.venv` step bitbake runs on the image's `python3` (3.8, no `sqlite3`) and stops at once.
- Measured on a 20-core host (AQ62 0.0.3 SDK, LE.1.0): kernel 2 min 49 s; apps about 55 min with `downloads.zip`
  (8948 tasks, in two runs).

## Offline, old files, other sources

- `--bundle-dir <dir>` (or `CAVLI_BUNDLE_DIR`) reads bundles from `<dir>/<component>/` instead of downloading; the
  directory is remembered for later runs and `update` (`--bundle-dir ''` goes back to the release). A component without a
  directory is still downloaded (qcom would ask for the GitHub login). Components and files:
  - `openwrt` (cqm220): `cqm22x-kp220-1.1.0.tar.zst`, `cqm22x-openwrt-prebuilt-backup-1.1.1.tar.zst`
  - `prebuilts` (aq62 without cqm220): `cqm22x-kp220-1.1.0.tar.zst`
  - `kprebuilts212`: `cqm22x-kp212-1.1.0.tar.zst`; `openwrt212`: `cqm22x-openwrt212-1.1.0.tar.zst`
  - `yocto` (cqm211): `cqm22x-yocto-downloads-1.1.0.tar.zst`
  - `--internal`: `qcom_common`, `qcom_220`, `qcom_212`, `qcom_211`, each `cqm22x-<part>-1.1.0.tar.zst` (joined, not `.partNN`)
  - every `<component>/` also holds a `BUNDLE_VERSION` file containing `1.1.0`.
- `CAVLI_BUNDLE_SOURCE=drive` takes items 2, 3 and 4 from the old Google Drive files (for cqm211 that stages the old
  `downloads` and `llvm-arm-toolchain-ship` packs) (not remembered by `update`).
- `CAVLI_BUNDLES_REPO=<owner/repo>` points the public release elsewhere; `CAVLI_IMAGE_REPO` / `CAVLI_IMAGE_TAG` pick
  another image (a failed pull falls back to a local image of that name, with a warning).

## Known state of this version

- Work in progress, reviewed step by step. `setup` downloads only the items above; no Buildroot unless `--buildroot`.
- The Qualcomm tools are split per product, so `--internal cqm212` does not download cqm220's.
- `cqm-doctor` reports `/pkg/prebuilts/clang` missing in a cqm212-only or cqm211-only container; cqm212 uses
  `/pkg/prebuilts-kobuk`, cqm211 needs neither, and both build fine.
- aq62: modem, tz, boot and meta are not covered (no `--internal` content yet), and there is no Yocto sstate or download
  bundle: the first build of a tree without an SDK `downloads.zip` fetches its sources.
- Not covered here: other lines; use the old tool `cqm22x/` for them.
