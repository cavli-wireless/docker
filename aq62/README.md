# aq62 build environment

Docker build environment for the AQ62 (SA525M) **apps_proc**: kernel and Yocto image, no modem, tz or boot,
no Qualcomm tools. The tool is `aq62/aq62-setup`; it is kept beside `cqm2xx/cqm2xx-setup` (same layout and
options) and replaces the old `le/22.04` container for AQ62.

One container per user, `aq62_<user>`, mirroring the host: same user name, uid/gid and `$HOME`, so files a build
writes come out owned by you. One container builds every AQ62 line.

## Lines

| Line | Qualcomm drop | Code |
|---|---|---|
| es1, es2, es3 | SA525M.LE.1.0 (kernel 5.15.185) | `aq62_manifest` `release/aq62_es<n>_bringup_release`, `chipcode-aq62-release.xml` |
| main | SA525M.LE.1.0 | `aq62_manifest` `main`, `chipcode-aq62-release.xml` |
| le31 | SA525M.LE.3.1 (kernel 5.15.194) | `aq62_chipcode` + `aq62_apps_proc` `aq62_le_3.1_bringup`, `cqm22x-build-scripts` `sa525m-le3-1` (no manifest yet) |

## What gets installed

| Item | Source | Needed for |
|---|---|---|
| Image `aq62-buildenv:1.0.2` | built locally from `cqm22x-buildenv:1.1.6` + the AQ62 host tools | the build |
| Kernel prebuilts (`kp220`: clang r450784e, build-tools, kernel-build-tools, ndk-r23), `/pkg/prebuilts` | public GitHub release `bundles-1.1.0` (the cqm220 pack, same clang) | kernel |
| Yocto download cache `$AQ62_ROOT/downloads`, `/pkg/yocto/downloads` (writable, shared by every tree) | filled by the builds; `setup` seeds the SELinux git mirror and four wireless-tools patches | Yocto sources |

Host tools added to the base image: `checkpolicy`, `semodule-utils` (TelAF SELinux), `lz4`, `libxml2-utils`,
`mtd-utils` (`ubinize`), OpenJDK 8 (TelAF generator), `tar` 1.34+dfsg-1build3 (the newer jammy tar breaks
pseudo in `do_package`), Jinja2 2.11.3 for `/usr/bin/python3` and `python2.7` (TelAF `ifgen`, with setuptools 44.1.1), `bz2` for `python2`, and git fetching
`git://git.codelinaro.org` over https (port 9418 is often blocked; LE.3.1 premirrors it).

SELinux upstream renamed `master` to `main`, while `meta-selinux` still pins `branch=master`, so a fresh fetch fails
("Unable to find revision … in branch master"). `setup` puts the CodeLinaro mirror clone (it still has `master`) into
the download cache under the upstream name, so no tree needs a change.

## Before you start

- Linux host with Docker (your user can run `docker`), plus `jq`, `curl`, `tar`, `zstd`, `sha256sum`.
- Network access to `github.com`, `ghcr.io`, the Ubuntu apt mirrors and PyPI (image build), `git.codelinaro.org`
  and `git.yoctoproject.org` (download seeds); about 5 GB for the prebuilts, plus the source tree and its build.
- Everything is kept under `$AQ62_ROOT` (default `~/aq62`); the container's `$HOME` is `$AQ62_ROOT/home`.
- GitHub ssh access to the `cavli-wireless` AQ62 repos (`~/.ssh` is mounted read-only unless `--no-ssh`).

## Install

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/main/aq62/aq62-setup && chmod +x aq62-setup
./aq62-setup setup -m /path/to/src
./aq62-setup status
docker exec -it --user $(id -un) -e HOME=$HOME aq62_$(whoami) bash -l
```

`-m <dir>` mounts a host directory at the same path (repeatable). `setup` and `update` recreate the container
(stop anything running in it). `--name <x>` makes a separate container (`aq62_<user>_<x>`).
`--bundle-dir <dir>` takes `<dir>/prebuilts/cqm22x-kp220-1.1.0.tar.zst` instead of downloading it (remembered;
`--bundle-dir ''` goes back to the release).

## Sync

```bash
cd /path/to/src/es3
repo init -u git@github.com:cavli-wireless/aq62_manifest.git -b release/aq62_es3_bringup_release -m chipcode-aq62-release.xml --depth=1
repo sync -j8 -c chipcode chipcode/SA525M_apps/apps_proc chipcode/build     # apps only: no modem
repo forall chipcode chipcode/SA525M_apps/apps_proc chipcode/build -c 'git lfs pull'
```

le31 has no manifest: clone `aq62_chipcode` into `chipcode/`, `aq62_apps_proc` into
`chipcode/SA525M_apps/apps_proc` (both `aq62_le_3.1_bringup`) and `cqm22x-build-scripts` `sa525m-le3-1` into
`chipcode/build`, then `git lfs pull` in each.

## Build (apps only)

Inside the container, once per tree link the download cache, then build the kernel and the Yocto image:

```bash
cd /path/to/src/es3/chipcode
[ -e SA525M_apps/apps_proc/downloads ] || ln -s /pkg/yocto/downloads SA525M_apps/apps_proc/downloads
./build/build.sh -m kernel,app -t pvm_ar -f RELEASE     # es1/es2/es3/main: perf kernel + qti-distro-tele-perf
./build/build.sh -m kernel,app -t pvm_ar -f DEBUG       # le31: its scripts build qti-distro-tele-debug
```

Output: `SA525M_apps/apps_proc/build-qti-distro-tele-<perf|debug>/tmp-glibc/deploy/images/sa525m/qti-tele-image/`.

- `-m app` alone fails at `linux-msm do_fetch` ("file://dist"): the image takes the kernel from
  `src/kernel-5.15/out/msm-kernel-sa525-<perf|debug>_defconfig/`, which `-m kernel` builds. Keep `-f` matching the
  Yocto variant of the line.
- `build.sh` returns 0 even when bitbake fails: read the last lines (`Build apps successfully` / `failed`).
- Keep the source root short: a root of about 100 characters or more breaks the Yocto build.
- Do not move a tree after building: the Python venv and the build dir keep the old path.

## Build an AQ62 SDK

An SDK (`AQ62_<version>_SDK.tar`, made by `make_sdk_v2.sh`) holds `sdk/src/{apps_proc,build,common}`: the apps
source, `downloads.zip` (Yocto download cache) and three scripts. Inside the container:

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
- Measured on a 20-core host (AQ62 0.0.3 SDK, LE.1.0): kernel 2 min 49 s; apps about 55 min with `downloads.zip` (8948 tasks, in two runs).

## Not covered yet

- Modem, tz, boot and meta (`--internal` in `cqm2xx-setup`): not in this tool.
- No Yocto download or sstate cache bundle: the first build of a tree without an SDK `downloads.zip` fetches its sources.
