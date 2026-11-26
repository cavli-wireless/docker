# Cavli build environment

One Docker container to build Cavli firmware: **cqm220**, **cqm212**, **cqm211** and **aq62** (SA525M).
`cavli-setup` downloads the tools and creates the container `cavli_<user>`, which has your user name, uid/gid and
`$HOME` path.

> **The quick start does not work yet** (checked 2026-11-26): `main` has no `cavli/` directory, so the `wget` URL
> returns 404, and the default image `cqm22x-buildenv:1.1.7` is not on ghcr.io, so `setup` stops with
> `could not pull`. See [Troubleshooting](#troubleshooting).

## Quick start

**Requirements:** Linux with Docker (your user can run `docker`) and `wget`, `jq`, `curl`, `tar`, `zstd`,
`sha256sum`, `flock`; network access to GitHub and `ghcr.io`; free disk as in [the table](#size-time-and-disk)
(about **79 GB** for all four products); GitHub ssh access to the source repositories you will sync.

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/main/cavli/cavli-setup && chmod +x cavli-setup
./cavli-setup setup
```

That is the public install of all four products, with no login. Name products to install only those:

| Product | Install | Disk free needed |
|---|---|---|
| cqm220 | `./cavli-setup setup cqm220` | 12 GB |
| cqm212 | `./cavli-setup setup cqm212` | 15 GB |
| cqm211 | `./cavli-setup setup cqm211` | 52 GB |
| aq62 | `./cavli-setup setup aq62` | about 7 GB |

Enter the container:

```bash
docker exec -it --user $(id -un) -e HOME=$HOME cavli_$(whoami) bash -l
```

Keep sources in `~/cavli/workspace` (mounted at the same path), or add your own existing directory with
`-m /path/to/src` on `setup`. Then see [Build](#build).

## Size, time and disk

Public install (default, `--external`): kernel and app builds. GB = 10^9 bytes, bundles 1.1.x.

| Products | Download | Unpacked | Free disk `setup` asks for |
|---|---|---|---|
| cqm220 | 3.3 GB | 7.3 GB | 12 GB |
| cqm212 | 4.0 GB | 8.8 GB | 15 GB |
| cqm211 | 25.3 GB | 25.9 GB | 52 GB |
| aq62 alone (nothing extra next to cqm220) | 1.1 GB | about 5 GB | not checked, keep about 7 GB |
| all four | 32.6 GB | 42 GB | 79 GB |

Full install (`--internal`, Cavli only) adds the Qualcomm tools:

| Products | Extra download | Extra unpacked | Free disk `setup` asks for, in total |
|---|---|---|---|
| cqm220 | 2.5 GB | 9.5 GB | 25 GB |
| cqm212 | 3.4 GB | 13.7 GB | 34 GB |
| cqm211 | 4.3 GB | 17.5 GB | 75 GB |
| all four | 8.6 GB | 29 GB | 120 GB |

- The image is extra: about 0.7 GB to download, 2.9 GB on Docker's own disk.
- The free-space figures cover `CAVLI_ROOT` during `setup` (downloaded ranges are kept until a bundle is verified).
- **Sources and builds need much more.** Trees on 2026-11-25 after the builds named in [Build](#build) took
  roughly: cqm220 60 GB per line, cqm212 92 GB, cqm211 53 GB, aq62 67 GB (apps, boot, modem).
- `setup` time, 1 Gb/s link, NVMe, image already local, single runs: all four public 5m44s (2026-11-26); earlier
  script versions: cqm220 alone 49 s, all four with `--internal` 6m34s. On a slower link the download sets the time.

### Public or private

| | Source | Login |
|---|---|---|
| `cavli-setup`, image, kernel tools, OpenWrt and Yocto caches | public GitHub repositories and ghcr.io | none (bundles are sha256-checked and resume) |
| Qualcomm tools (`--internal`) | private release `cavli-wireless/cqm2xx-qcom-bundles` | GitHub login, `cavli-wireless` org member |
| Source code | private `cavli-wireless` repositories | your ssh key |

```bash
./cavli-setup setup --internal                      # all four with the Qualcomm tools
```

The first `--internal` download shows a GitHub device code: open the URL it prints and enter the code. The mode is
remembered until you pass `--external`.

### What the container can read

- **Your ssh keys.** `~/.ssh` is mounted read-only by default, so anything running in the container can read and use
  the keys. `--no-ssh` leaves it out (then get the sources some other way).
- **The stored GitHub login.** The device login is saved in `$CAVLI_ROOT/home` (gh's config), which is the container's
  home, so anything in the container can use it. gh's default login can read and write all repositories you can. To
  remove it after the download: `rm $CAVLI_ROOT/home/.config/gh/hosts.yml` (default root: `~/cavli`); a later Qualcomm
  download asks again. Do not share a `CAVLI_ROOT` that holds a login.
- **`GH_TOKEN` (CI, no terminal).** If set, it is used instead of the device login. The script keeps its own copy only
  in the download container's RAM, but while that container exists anyone who can use Docker on the host can read it
  with `docker inspect`. Use a fine-grained token with read-only "Contents" access to the Qualcomm bundles repository
  only and a short expiry (not tested with such a token). Do not pass your everyday `gh` token.

## Use the container

| Command or option | What it does |
|---|---|
| `setup [products]` | download, then create or recreate the container (installed products stay). **Stops anything running in it** |
| `status` | installed products, bundles, mounts |
| `update` | pull the image again and recreate; versions come from your copy of the script, so download the newer one first |
| `version`, `--help` | image and bundle version; all commands |
| `-m <dir>` | mount an existing host directory at the same path (repeatable, remembered) |
| `--internal`, `--external` | full or app-only; remembered |
| `--no-ssh`, `--ssh` | leave out or mount `~/.ssh`; remembered |
| `--name <x>` | container `cavli_<user>_<x>`; pass it on **every** command for that container |
| `CAVLI_ROOT=<dir>` | where everything is kept (default `~/cavli`); set it on every command. With `--name`, a fully separate install |

The container's `$HOME` is `$CAVLI_ROOT/home`, so your host git config is not in it. Set it once, inside the
container, before `repo init`:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global color.ui false                  # stops repo init asking about colour
```

Check the install (inside or outside): `docker exec --user $(id -un) cavli_$(whoami) cqm-doctor`.

## Build

### cqm220, cqm212, cqm211

Get the code (branch, manifest file, post-sync step) from the product's manifest README (`cqm22x-manifests`,
`cqm212-manifests`, `cqm211-manifests`). Inside the container:

```bash
# cqm220
cd <src>/<tree>/chipcode
./build/build.sh -t mbb-cavli -m app -V 1.0.0 -v perf      # app only (public install)
./build/build.sh -t mbb-cavli -m all -V 1.0.0 -v perf      # full (--internal)

# cqm212
cd <src>/<tree>/chipcode
bash build/bigfile_helper.sh after_pull                    # after every sync
./build/build.sh -t cavli -m app -V 1.0.0 -v perf          # app only
./build/build.sh -t cavli -m all -V 1.0.0 -v perf          # full (--internal)

# cqm211
cd <src>/<tree>/chipcode
bash build/bigfile_helper.sh after_pull                    # after every sync (mandatory)
bash build/build.sh -t cavli -m app -v perf                # app only
bash build/build.sh -t cavli -m all -v perf                # full (--internal)
```

`<src>/<tree>` is your own source directory. `./build/build.sh -h` lists the targets of the branch you synced; the
manifest README may add options (cqm220: `-M <model> -w <modem version>`). Without `-V`, the cqm211 zip is named
`v0.0.0`. The `-m all` lines above passed on 2026-11-25 as written (cqm220 on both cqm220-0 and cqm220-3), in a `--internal`
container; the `-m app` lines were not run then, and no image was flashed.

cqm220 builds the OpenWrt tools and toolchain itself by default, in parallel (`-j$(nproc)`); add `-P` to `build.sh` to
restore them from the cache instead. cqm212 always uses its cache. Earlier measurements on a fresh sync, `-m app`: cqm220 about
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

### aq62: lines, sync, build

| Line | Qualcomm drop | Code |
|---|---|---|
| es1, es2, es3 | SA525M.LE.1.0 (kernel 5.15.185) | `aq62_manifest` `release/aq62_es<n>_bringup_release`, `chipcode-aq62-release.xml` |
| main | SA525M.LE.1.0 | `aq62_manifest` `main`, `chipcode-aq62-release.xml` |
| le31 | SA525M.LE.3.1 (kernel 5.15.194) | `aq62_chipcode` + `aq62_apps_proc` `aq62_le_3.1_bringup`, `cqm22x-build-scripts` `sa525m-le3-1` (no manifest yet) |

SELinux upstream renamed `master` to `main`, while `meta-selinux` still pins `branch=master`, so a fresh fetch fails
("Unable to find revision … in branch master"). `setup` puts the CodeLinaro mirror clone (it still has `master`) into the
download cache under the upstream name, so no tree needs a change.

Sync (apps only: no modem). Set your git identity first (see Use the container):

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

### aq62 boot, tz and modem (internal tools)

`cavli-setup` has no Qualcomm part of its own for aq62. In a container installed with `setup --internal` (all four
products), these passed on the es3 line on 2026-11-25, each with `-t pvm_ar -f RELEASE`: `-m boot`; `-m tz` (builds only
the `devcfg*` images, `tz.mbn` is a prebuilt in git); and `-m nonhlos` (boot, modem, tz, meta), after also syncing
`chipcode/SA525M_modem/modem_proc` with `git lfs pull` and after a `-m kernel,app` build whose images the meta step used.
Which Qualcomm parts are the minimum is not known. `-m all` in one run was not tried, and no image was flashed. Check the
per-step logs (`build_boot.log`, `build_mpss.log`, `build_tz.log`): the exit code alone does not show a failure.

## Troubleshooting

| What you see | Cause and fix |
|---|---|
| `wget` returns 404 | `cavli/` is not on `main` yet. |
| `could not pull ...cqm22x-buildenv:1.1.7` | The image is not on ghcr.io. Downloads already started keep running to their end and are kept, so a re-run does not fetch them again. For cqm220, cqm212 and cqm211, `CAVLI_IMAGE_TAG=1.1.6 ./cavli-setup setup cqm220 cqm212 cqm211` uses the published 1.1.6 (`setup` and `cqm-doctor` passed with it on 2026-11-26; no build was run). Set the same variable on later `setup` and `update`. aq62 needs the 1.1.7 host tools. |
| `about N GB free needed` | Free disk, install fewer products, or move `CAVLI_ROOT`. `CAVLI_SKIP_SPACE_CHECK=1` skips the check. |
| `-m ...: no such directory` | Create the directory first. |
| `'cavli_...' already exists and this script did not create it` | Another install made it. Use `--name <x>` and your own `CAVLI_ROOT`. |
| `another setup is using ...` | Wait, or stop the old run's processes (`fuser -v <dir>/.setup.lock`). After `kill -9`, the Qualcomm download container may still run: `docker ps`, `docker stop`. |
| `download of ... failed` or `failed after N tries` | Check the network and re-run: it resumes. |
| A download never ends and prints `curl error 28` every 15 s | A connection trickles under 1000 bytes/s. Stop (Ctrl-C) and re-run. |
| Root-owned files in a **cqm220** tree (`binaries/`, zips) | cqm220 `build/build.sh` runs the modem and meta steps with `sudo`. Give them back on the host: `sudo chown -R -h $(id -un): <tree>` |
| OpenWrt build fails at random (gdbm, loc-core, init-mss...) | Parallel make: run the same command again. |
| aq62 `build.sh` exits 0 but images are missing | It returns 0 even when bitbake fails: read the last lines (`Build apps successfully` / `failed`). |
| `cqm-doctor`: `/pkg/prebuilts/clang` missing (cqm212-only or cqm211-only) | Expected: cqm212 uses `/pkg/prebuilts-kobuk`, cqm211 needs neither. |

## Reference

### What gets installed

`setup` with no product installs all four; name some (`setup cqm212 aq62`) to add only those (installed ones stay).

| # | Item | Source | Needed for |
|---|---|---|---|
| 0 | Image `ghcr.io/cavli-wireless-public/cqm22x-buildenv:1.1.7` (pulled, never built locally) | public | everything; 1.1.7 carries the aq62 host tools |
| 1 | Qualcomm tools (`qcom_common` + `qcom_220` / `qcom_212` / `qcom_211`) | private GitHub release, `--internal` only | boot / tz / modem / meta (not aq62) |
| 2 | Kernel prebuilt tool (cqm220 and aq62: `kp220`; cqm212: `kp212`; clang, build-tools, NDK) | public GitHub release `bundles-1.1.0` | kernel + ABL |
| 3 | OpenWrt prebuilt cache (cqm220: `openwrt-prebuilt-backup`; cqm212: `openwrt212`) | public GitHub release (cqm220: `bundles-1.1.1`; cqm212: `bundles-1.1.0`) | OpenWrt tools and toolchain without a rebuild (cqm220: only with `-P`) |
| 4 | Yocto download cache `/pkg/yocto/downloads` (writable, one for the container) | cqm211: `yocto-downloads`, about 24 GB, public release `bundles-1.1.0`; aq62: filled by the builds, `setup` seeds the SELinux git mirror and four wireless-tools patches | Yocto sources |

cqm211 uses items 4 and 1 only. aq62 uses items 2 and 4 only: apps build (kernel + Yocto image), no modem, tz or boot,
so `--internal` downloads no Qualcomm part for it. aq62 takes the kernel prebuilts from cqm220's copy when cqm220 is installed
(`openwrt/<v>/prebuilts`), else it downloads the `kp220` pack alone (about 1 GB, 4.8 GB unpacked).

**cqm211 and aq62 share `/pkg/yocto/downloads`.** With cqm211 installed it is the staged `yocto/<v>/downloads`; without,
`$CAVLI_ROOT/downloads`. Adding cqm211 to an aq62 install copies the files of `$CAVLI_ROOT/downloads` into it (never
overwriting) once; the old directory can then be deleted.

Host tools added to the image for aq62: `checkpolicy`, `semodule-utils` (TelAF SELinux), `lz4`, `libxml2-utils`,
`mtd-utils` (`ubinize`), OpenJDK 8 (TelAF generator), Jinja2 2.11.3 for `/usr/bin/python3` and `python2.7`
(TelAF `ifgen`, with setuptools 44.1.1), `bz2` for `python2`, git fetching `git://git.codelinaro.org` over https, and
`tar` held at 1.34+dfsg-1build3 (the newer jammy tar breaks pseudo in Yocto `do_package`). The held `tar` applies to
every product in the container.

### How the download works, and tuning

`setup` fetches everything at once: all products' bundles and the image pull run together, each GitHub file is cut
into 256 MB ranges taken by a pool of 12 connections,
and each bundle is read back in order as one stream `sha256 | zstd -d | tar`, so it unpacks while it downloads. The
sha256 is checked on that same stream; a mismatch removes the unpacked files and nothing is marked complete. Ranges stay
in the cache until the bundle is verified, so an interrupted `setup` resumes: it unpacks again from the start, without
downloading the kept ranges again. Each bundle prints downloaded %, unpacking %, MB/s and elapsed time every 10 s
(100% downloaded is not done), and `setup` ends with a timing table.

All bundle files download at once. 2 of them unpack at a time (cqm211's Yocto cache first); the others download
ahead while they wait. No file gets more than 24 ranges ahead of its `tar`, which keeps downloads from running far
ahead of a slow disk. `--internal` downloads the Qualcomm parts in a second container with its own pool and its own 2
unpack slots, so it can use twice the connections.

A connection that stays under 1000 bytes/s for 15 s (or does not connect in 20 s) is dropped and its range resumes
where it stopped. The limit only catches stalls. A range fails after 6 attempts in a row without progress (progress:
1 MB or more, or any bytes in an attempt that lasted 15 s); there is no other limit, so a slow link that keeps moving
finishes. The partial range stays in the cache and a re-run resumes it.
Two exceptions: a connection that keeps trickling under the limit is dropped and resumed with no end, so the run does
not finish (stop it and re-run); and connections that close early, each after less than 1 MB and 15 s, count as no
progress, so such a link can fail a range although bytes arrive. Each finished range prints one line with its
size, seconds, MB/s and tries.

Only one `setup` runs on a `CAVLI_ROOT` (and cache dir) at a time; a second one waits 20 s, then stops. After a killed
run, the lock stays until its last process has ended. The Qualcomm download container is not stopped by killing the
script with `kill -9`: it keeps downloading to its end (see `docker ps`; stop it with `docker stop`), and its own lock
keeps a second one out.

- `CAVLI_DL_JOBS=<n>` connections (default 12), `CAVLI_DL_CHUNK_MB=<n>` range size (default 256).
  `CAVLI_DL_JOBS=0` is the old way, one file at a time.
- `CAVLI_UNPACK_JOBS=<n>` files at a time (default 2, 0 = no limit), `CAVLI_DL_AHEAD=<n>` ranges ahead of `tar`
  (default twice `CAVLI_DL_JOBS`).
- `CAVLI_DL_MIN_BPS=<bytes/s>` the speed under which a connection is dropped after 15 s (default 1000; 0 = never,
  and then a connection that stops sending can hang the run).
- `CAVLI_CACHE_DIR=<absolute dir>` keeps the downloaded ranges there, for example on another disk (default
  `$CAVLI_ROOT/cache`). Unpacking stays under `CAVLI_ROOT`. Give each `CAVLI_ROOT` its own cache dir.
- `CAVLI_DL_KEEP=0` deletes each range once `tar` has read it; a re-run after a failure then downloads the deleted
  ranges again. Each file can still hold `CAVLI_DL_AHEAD` ranges (6 GB at the defaults) and all files download at
  once: at the defaults the cache can reach about 13 GB external and 23 GB with `--internal`.
- With the ranges kept (default), the cache needs about the bundle's size in free disk, on top of the unpacked size,
  until it is verified. All four products took about 75 GB of writes external and 143 GB internal. `setup` checks the free
  space before it downloads (`CAVLI_SKIP_SPACE_CHECK=1` skips the check). The check covers only the disk of
  `CAVLI_ROOT`: it does not check a `CAVLI_CACHE_DIR` on another disk, counts no cache with `CAVLI_DL_KEEP=0` (it can
  reach the sizes above), and does not count aq62's prebuilts or buildroot.

### Download measurements

Measured on one host (1 Gb/s link, NVMe, image already local, few runs, so expect other numbers elsewhere):

- external cqm220+cqm212 from empty, seconds per run: 8 connections 104 and 89, and 84 with `CAVLI_DL_MIN_BPS=0`;
  12 connections 80, 82, 77 and 80; 16 connections 83 and 83, and 73 with `CAVLI_DL_MIN_BPS=0`. The other runs had a
  2 MB/s drop limit (an earlier default). In those builds `0` still meant 1 byte/s. 12 and 16 were level; the default
  is 12.
- drop limit at 12 connections, 2 runs each: 2 MB/s 77 and 80 s (also counted above), 8 MB/s 79 and 83 s with 27
  drops per run. A higher limit gave no gain.
- external, all four products, 12 connections, 2 MB/s limit: 5m51s, 34 GB received at 97 MB/s average (1 run).
- one connection's rate varies: full ranges ran at 2 to 84 MB/s. Part of the low end is likely the connections sharing the
  link (with 16 of them the median range was under 4 MB/s in 2 of 3 runs), not only slow servers. With in-order
  unpacking one slow range can hold up the end of a file.
- `--internal` was not timed with 12 connections (24 with the Qualcomm container).

### Offline, old files, other sources

- `--bundle-dir <dir>` (or `CAVLI_BUNDLE_DIR`) reads bundles from `<dir>/<component>/` instead of downloading; the
  directory is remembered for later runs and `update` (`--bundle-dir ''` goes back to the release). A component without a
  directory is still downloaded (qcom would ask for the GitHub login). Components and files:
  - `openwrt` (cqm220): `cqm22x-kp220-1.1.0.tar.zst`, `cqm22x-openwrt-prebuilt-backup-1.1.1.tar.zst`
  - `prebuilts` (aq62 without cqm220): `cqm22x-kp220-1.1.0.tar.zst`
  - `kprebuilts212`: `cqm22x-kp212-1.1.0.tar.zst`; `openwrt212`: `cqm22x-openwrt212-1.1.0.tar.zst`
  - `yocto` (cqm211): `cqm22x-yocto-downloads-1.1.0.tar.zst`
  - `--internal`: `qcom_common`, `qcom_220`, `qcom_212`, `qcom_211`, each `cqm22x-<part>-1.1.0.tar.zst`, whole or as the
    release's `.partNNN` files. Their sum comes from `<component>/SHA256SUMS`, else from the release's `<file>.sha256`
    next to it; with neither, `setup` stops.
  - every `<component>/` also holds a `BUNDLE_VERSION` file containing `1.1.0`.
- `CAVLI_BUNDLE_SOURCE=drive` takes items 2, 3 and 4 from the old Google Drive files (for cqm211 that stages the old
  `downloads` and `llvm-arm-toolchain-ship` packs) (not remembered by `update`).
- `CAVLI_BUNDLES_REPO=<owner/repo>` points the public release elsewhere; `CAVLI_IMAGE_REPO` / `CAVLI_IMAGE_TAG` pick
  another image (a failed pull falls back to a local image of that name, with a warning).
- A `--bundle-dir` that was removed afterwards stays recorded (`status` shows it); `--bundle-dir ''` on the next `setup`
  clears it.

### Coming from cqm2xx-setup or aq62-setup

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

### Limits

- `setup` downloads only the items above; no Buildroot unless `--buildroot`.
- The Qualcomm tools are split per product, so `--internal cqm212` does not download cqm220's.
- aq62 has no Yocto sstate or download bundle: the first build of a tree without an SDK `downloads.zip` fetches its
  sources.
- Other lines are not covered; use the old tool in `cqm22x/`.
