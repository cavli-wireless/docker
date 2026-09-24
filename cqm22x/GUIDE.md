# CQM22x — build environment guide

This covers the per-product `container_docker_helper.sh` flow below. For the
newer one-container-per-user setup, see `cqm22x-setup` in `README.md`.

From a bare machine to a firmware image, for all three product lines:

| Product | Chip | Userspace |
|---|---|---|
| `cqm220-3` | sdx35 | OpenWrt |
| `cqm220-0` | sdx32 | OpenWrt |
| `cqm211` | sdx61/62/65 | Yocto |

- [1. What you need](#1-what-you-need)
- [2. Set up the container](#2-set-up-the-container)
- [3. Get the source](#3-get-the-source)
- [4. Build](#4-build)
- [5. Everyday use](#5-everyday-use)
- [6. When something is wrong](#6-when-something-is-wrong)
- [7. For Cavli: publishing a new bundle](#7-for-cavli-publishing-a-new-bundle)

---

## 1. What you need

| | |
|---|---|
| OS | Ubuntu or Debian x86_64 (other distros work, but install Docker yourself first) |
| Disk | ~120 GB free for one product line, ~150 GB for all of them — see the bundle table in [2](#2-set-up-the-container) |
| RAM | 16 GB minimum, 32 GB comfortable |
| Network | access to `github.com`, `ghcr.io` and `drive.google.com` |
| Tools | `curl`, `wget`, `tar`, `zstd`. Docker is installed for you if missing. |
| From Cavli | the **qcom bundle link** and its **sha256** — that one archive only |

Install the small stuff if it is not there:

```bash
sudo apt update && sudo apt install -y curl wget tar zstd
```

Nothing else. In particular you do **not** need rclone, gdown, or a Google
account — the setup script talks to Google Drive with plain `curl`.

---

## 2. Set up the container

Three commands.

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/refs/heads/main/cqm22x/container_docker_helper.sh -O container_docker_helper.sh
```

```bash
bash container_docker_helper.sh -w /mnt/ -u '<qcom link from Cavli>' -c '<sha256 from Cavli>'
```

```bash
docker start -i build_cqm22x_jammy_$(whoami)
```

The middle command does everything: installs Docker if missing, downloads the
bundles this product needs, verifies their checksums, unpacks them, pulls the
build image, creates the container and checks the environment. Budget 30–60
minutes on a first run, almost all of it download and unpack.

### Three bundles, only what you need

| Bundle | Packed | Unpacked | Who needs it | Where the link comes from |
|---|---|---|---|---|
| `qcom` | ~13 GB | ~60 GB | every product | **Cavli — pass with `-u`/`-c`** |
| `openwrt` | ~2.3 GB | ~10 GB | cqm220-0/3 | built into the script |
| `yocto` | ~24 GB | ~27 GB | cqm211 | built into the script |

So an sdx35 machine downloads about 15 GB and an sdx61 machine about 37 GB. Ask
for both and the shared `qcom` bundle is still fetched only once.

An application developer who only builds packages against the Cavli SDK
tarball needs none of the Qualcomm material: `-p sdk` creates
`build_cqm22x_jammy_<user>_sdk` with the `openwrt` bundle alone (~2.3 GB
download, no `-u`). What it can do is exactly what the SDK contains — OpenWrt
packages (`.ipk`) — not kernel, abl, modem or flashable images.

```bash
bash container_docker_helper.sh -p sdk -l -w ~/cqm-sdk
```

Only `qcom` is proprietary, which is why it is the only one you have to be given
a link for. The other two are build caches assembled from public sources — they
exist to make the first build fast, not to supply anything that could not be
rebuilt.

> **If Cavli hands you a `cqm22x-pkg-1.0.x` link** rather than a `cqm22x-qcom-`
> one, it still works — the script goes by content, not by filename. Be aware
> that those older archives bundled the OpenWrt cache inside the toolchain, so
> on a cqm220 machine you end up fetching that cache twice, about 2 GB of waste.
> Nothing breaks; the separately mounted copy is the one the build uses.

### Choosing products

```bash
# sdx35 — the default, same as passing -p cqm220-3
bash container_docker_helper.sh -w /mnt/ -u '<link>' -c '<sha256>'

# sdx61/62/65
bash container_docker_helper.sh -w /mnt/ -p cqm211 -u '<link>' -c '<sha256>'

# an sdx35 and an sdx61 container side by side
bash container_docker_helper.sh -w /mnt/ -p cqm220-3,cqm211 -u '<link>' -c '<sha256>'

# every product
bash container_docker_helper.sh -w /mnt/ -p all -u '<link>' -c '<sha256>'
```

You get one container per product — `build_cqm22x_jammy_<user>` for cqm220-3 and
`build_cqm22x_jammy_<user>_<product>` for the others. They share the bundles but
never share an OpenWrt `build_dir`, which is the whole reason they are separate
containers.

It is safe to re-run. A bundle already unpacked is not downloaded again.

The download survives a broken or stalled connection: the partial file is kept
and the next run resumes from where it stopped. Google Drive stalling halfway
through a 12 GB transfer is common enough that the script handles it rather
than hanging.

> `raw.githubusercontent.com` caches for a few minutes. Just after a change
> lands in the repository you can still be served the previous copy — wait a
> moment and fetch again if a fix seems to be missing.

### If Docker was just installed for you

You will be told to log out and back in — a new group membership does not apply
to a shell that is already open. Then re-run the same command; it picks up
where it left off.

```bash
newgrp docker      # or just log out and back in
```

### Other ways to supply the toolchain

`-u`, `-c`, `-f` and `-t` all refer to the **qcom** bundle: it is the only one
the script cannot fetch on its own.

```bash
# the .tar.zst is already on this machine
bash container_docker_helper.sh -w /mnt/ -f ~/cqm22x-qcom-1.1.0.tar.zst

# it is already unpacked somewhere
bash container_docker_helper.sh -w /mnt/ -t /data/cqm22x-qcom

# fetch and unpack everything now, set up the containers later
bash container_docker_helper.sh -p all -u '<link>' -c '<sha256>' -n
```

To serve the public bundles from your own mirror instead of Drive, set
`CQM_YOCTO_URL` / `CQM_OPENWRT_URL` (and the matching `_SHA256`).

### Options worth knowing

| Flag | Meaning |
|---|---|
| `-w PATH` | where your **source** lives. Mounted at `/work` inside |
| `-r DIR` | where the **bundles and caches** go (default `$HOME/cqm22x`) |
| `-u URL` | qcom bundle link (Google Drive or plain HTTPS) |
| `-c HEX` | expected sha256 of the qcom bundle |
| `-p LIST` | products, comma separated, or `all`: `cqm220-3` (default), `cqm220-0`, `cqm211` |
| `-p sdk` | application-SDK container: openwrt bundle only, no qcom bundle and no `-u`. For building packages against the Cavli SDK tarball (`sdk-*.tar.gz` from a release); cannot build kernel, abl, modem or images. Not part of `all` |
| `-V VER` | which bundle version to use (default `1.1.0`) |
| `-m PATH` | mount an extra host path into every container, repeatable: `PATH`, `PATH:ro`, `PATH:/inside`, `PATH:/inside:ro` (long form `--mount`) |
| `-U` | no USB passthrough — use on a machine that only builds |
| `-l` | bake your user into a local `cqm22x-buildenv:<user>` image so `docker exec -it <container> bash` lands as you (like `docker start -i` already does); add `-R` to recreate existing containers with it |
| `-R`, `--force` | rebuild the container from scratch |
| `--force-all` | rebuild it *and* re-download the bundles (`-R -F`) |
| `-d` | dry run: print what would happen, change nothing |
| `-h` | full list |

`-h` is the authority; the table above is the short version.

### Mounting another disk with `-m`

`/work` is one path. When the sources you need are spread over more than one
disk — a second SSD, a shared release drop, a checkout that lives outside
`-w` — add them with `-m`:

```bash
bash container_docker_helper.sh -w /mnt/ -m /mnt/SSD_2TB -m /srv/release:ro
```

With no path after it the disk appears inside at the same path it has on the
host, which is what you usually want: paths in build scripts and error
messages then mean the same thing on both sides. Four spellings:

| spec | inside the container |
|---|---|
| `/mnt/SSD_2TB` | `/mnt/SSD_2TB`, writable |
| `/mnt/SSD_2TB:ro` | `/mnt/SSD_2TB`, read-only |
| `/mnt/SSD_2TB:/data` | `/data`, writable |
| `/mnt/SSD_2TB:/data:ro` | `/data`, read-only |

Repeat `-m` for each one. The path has to exist on the host — a typo fails
before anything is downloaded rather than becoming an empty directory inside.

`/pkg`, `/work` and `/ccache` belong to this script; `-m` will not overwrite
them. And because Docker fixes a container's mounts when it is created,
adding `-m` to a container that already exists does nothing until you
recreate it:

```bash
bash container_docker_helper.sh -w /mnt/ -t ~/cqm22x/qcom/1.1.0 -P \
  -m /mnt/SSD_2TB --force
```

The script warns when you hit this rather than leaving you to wonder.

### `-w` and `-r` are different, and it matters

`-w` controls only where the source goes. The bundles follow `-r`, which
defaults to `$HOME/cqm22x` — often a small root partition. So this:

```bash
bash container_docker_helper.sh -w /mnt/ -u '<link>' -c '<sha256>'
```

puts the source under `/mnt/` and 60–100 GB of bundles under `$HOME`. To keep
everything on the big disk, say so:

```bash
bash container_docker_helper.sh -w /mnt/ -r /mnt/tools -u '<link>' -c '<sha256>'
```

The script prints its plan before doing anything, naming the filesystem each
piece lands on and how much room is left there:

```
==> Plan

  products    cqm220-3 cqm211
  bundles     qcom openwrt yocto (version 1.1.0)

  qcom        /mnt/tools/qcom/1.1.0
              on /mnt, 1.3T free — needs ~60 GB (change with -r)
  openwrt     /mnt/tools/openwrt/1.1.0
              on /mnt, 1.3T free — needs ~12 GB (change with -r)
  yocto       /mnt/tools/yocto/1.1.0
              on /mnt, 1.3T free — needs ~30 GB (change with -r)

  source      /mnt/  ->  /work
  image       ghcr.io/cavli-wireless-public/cqm22x-buildenv:latest
  container   build_cqm22x_jammy_you                 (qcom openwrt)
  caches      /mnt/tools/cache/cqm220-3
  container   build_cqm22x_jammy_you_cqm211          (qcom yocto)
  caches      /mnt/tools/cache/cqm211
```

A bundle already installed says so instead of a size, so you can see at a glance
what a re-run would actually download.

Running with `-d` first costs a second and shows exactly this, plus every step
it would take. Worth doing on any new machine.

### Where things end up

```
<-r>/                            default $HOME/cqm22x
├── qcom/
│   ├── cqm22x-qcom-1.1.0.tar.zst  downloaded here, deleted after unpacking
│   │                              unless you pass -k
│   └── 1.1.0/                     unpacked here, ~60 GB, mounted read-only
├── openwrt/1.1.0/                 cqm220-* — openwrt-prebuilt-backup/
├── yocto/1.1.0/                   cqm211 — downloads/, llvm-arm-toolchain-ship/
└── cache/
    ├── cqm220-3/{openwrt,ccache}
    ├── cqm220-0/{openwrt,ccache}
    └── cqm211/{openwrt,ccache}

<-w>/                            your source, mounted at /work
```

Each bundle is versioned separately, so several versions can live side by side;
`-V` picks which the containers mount, without downloading anything again.

| Bundle | Contents | Why it exists |
|---|---|---|
| `qcom` | HEXAGON, LLVM, linaro, sectools, prebuilts | the actual toolchain — nothing builds without it |
| `openwrt` | OpenWrt prebuilt host tools and cross toolchain | the first app build restores it instead of compiling gcc/binutils/musl from source |
| `yocto` | bitbake `DL_DIR` cache + LLVM/ARM toolchain | the first cqm211 build reads sources locally instead of fetching hundreds of tarballs |

Nothing of value lives inside the container — the writable layer stays around
200 kB. Deleting and recreating it costs seconds and loses nothing.

---

## 3. Get the source

Inside the container, or with the `cqmdev` helper from outside:

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/refs/heads/main/cqm22x/cqmdev -O cqmdev && chmod +x cqmdev
./cqmdev sync
```

This runs `repo init`, `repo sync` and then `git lfs pull`. The last step is not
optional: `repo` disables the LFS smudge filter while syncing, so without it
you end up with zero-byte binaries and a build that fails much later, in a much
more confusing way.

Manifests, per product:

| Product | Manifest branch | Manifest file |
|---|---|---|
| `cqm220-3` | `cavli_sdx35_iot_le_1_0` | `chipcode-cqm22x-cav-base.xml` |
| `cqm220-0` | `cavli_kuno_le_1_0` | `chipcode-cqm22x-cav-base.xml` |

By hand, if you prefer:

```bash
docker start -i build_cqm22x_jammy_$(whoami)

cd /work/cqm220-3
repo init -u git@github.com:cavli-wireless/cqm22x-manifests.git \
          -b cavli_sdx35_iot_le_1_0 \
          -m chipcode-cqm22x-cav-base.xml
repo sync -c -j8 --no-clone-bundle --optimized-fetch
repo forall -c 'git lfs pull'
```

Expect roughly 13 GB of git objects and a 48 GB tree when it settles.

### SSH access

The container mounts your `~/.ssh` read-only, so your existing GitHub key works
inside. Two things go wrong most often:

- **`Permission denied (publickey)`** — your key is not loaded, or the account
  has no access to `cavli-wireless`. Test with `ssh -T git@github.com` inside
  the container.
- **`Could not read from remote repository`, hanging first** — port 22 is
  blocked on your network. This is not a permissions problem. Add to
  `~/.ssh/config` **on the host** (the container reads the same file):

  ```
  Host github.com
      HostName ssh.github.com
      Port 443
  ```

---

## 4. Build

### The first build of a fresh tree must be `-m all`

```bash
./cqmdev build -m all -t MBB-CAV -v debug
```

Not `-m nonhlos`. That mode sets `BYPASS_APP=true`: it builds the modem and
then packages a meta build from *already built* app and recovery binaries. On a
tree that has never had the app side built there is nothing to package, and the
meta step dies on a missing `mkfs.ubifs` — a tool OpenWrt only produces as part
of an app build. It is not a broken environment; the mode simply assumes a tree
someone has already built once.

After that first full build, use `-m nonhlos` for the fast modem loop:

```bash
./cqmdev build -m nonhlos -t MBB-CAV -v debug
```

Inside the container instead of through `cqmdev`:

```bash
cd /work/cqm220-3/chipcode
./build/build.sh -m all -t MBB-CAV -v debug
```

### The first app build restores a prebuilt toolchain

Building OpenWrt's host tools and cross toolchain from source takes hours. The
bundle carries a prebuilt cache and `set_openwrt_env.sh` picks it up on its
own:

```
==> tool/toolchain not found in build_dir/staging_dir, checking prebuilt cache
==> cache was built at .../cqm220-0/chipcode/app3/owrt, relocating to
    /work/cqm220-3/chipcode/OWRT.PRODUCT.2.1/apps_proc/owrt (--relocate)
==> relocate: patched 5787 text file(s), 3829 binary file(s)
==> restored prebuilt tool/toolchain from cache
```

That cache bakes its original absolute path into thousands of binaries and can
only be relocated to a path **no longer** than the one it was built at. Inside
the container the tree is always under `/work`, which is short and identical on
every machine — that is what makes the cache usable at all. Outside a
container, where the path differs per machine, it usually is not.

If you see `no usable prebuilt cache found, building tool/toolchain from
scratch`, the bundle predates this or the mount is missing. Check that
`/pkg/openwrt-prebuilt-backup` exists inside the container.

### What the flags mean

```
-m  module   all | app | modem | tz | boot | rpm | recovery | meta
             prebuild  use prebuilt binaries (when building modem only)
             nonhlos   build modem and produce a meta build, using prebuilt
                       app/recovery binaries
-t  target   MBB-CAV | M2-CAV | MBB | M2
-v  variant  perf (default) | debug
-p           build modules in parallel
```

| Target | Description | NAND | DDR |
|---|---|---|---|
| `MBB-CAV` | Cavli mobile broadband, no WiFi | 256 MB | DDR2 |
| `M2-CAV` | Cavli M2, no WiFi | 256 MB | DDR2 |
| `MBB` | Qualcomm mobile broadband, no WiFi | 256 MB | DDR2 |
| `M2` | Qualcomm M2, no WiFi | 256 MB | DDR2 |

Working on the modem only? `./build/build.sh -m nonhlos -t M2-CAV -v debug` is
the recommended loop.

### Where the output lands

Under `chipcode/` in your work path — visible from the host, owned by you, not
by root. That is deliberate: the container maps your uid and gid at start, so
nothing it writes needs `sudo` to clean up afterwards.

---

## 5. Everyday use

```bash
docker start -i build_cqm22x_jammy_$(whoami)     # shell in the container
docker stop  build_cqm22x_jammy_$(whoami)
```

With `cqmdev`:

```bash
./cqmdev shell            # shell, in /work
./cqmdev build [args]     # run build.sh
./cqmdev run <cmd>        # one-off command
./cqmdev doctor           # re-check the environment
./cqmdev status           # container, image and bundle versions
./cqmdev -p cqm220-0 ...  # another product
./cqmdev -p cqm211 shell  # the Yocto line
```

### Several products on one machine

Pass a list to the setup script — `-p cqm220-3,cqm211`, or `-p all`. Each
product gets its own container:

| Product | Container |
|---|---|
| `cqm220-3` | `build_cqm22x_jammy_<user>` |
| `cqm220-0` | `build_cqm22x_jammy_<user>_cqm220-0` |
| `cqm211` | `build_cqm22x_jammy_<user>_cqm211` |

They share the `qcom` bundle — it is downloaded and stored once — but each keeps
its own OpenWrt cache and ccache. Two products must never share a `build_dir`,
or you get stale artefacts from the other product's configuration, and that is
the reason they are separate containers rather than one container with
everything mounted.

The bundles follow from the products you asked for: `-p cqm220-3,cqm220-0` pulls
qcom + openwrt, `-p cqm211` pulls qcom + yocto, `-p all` pulls all three.

### Flashing

USB is passed through by default, so the build machine can also be the test
machine. `/dev/bus/usb` is visible inside and hotplugged devices appear without
restarting the container.

This is done with device-cgroup rules scoped to USB (189) and USB serial (188)
rather than `--privileged`. If a machine only ever builds, pass `-U` and it
gets no device access at all.

---

## 6. When something is wrong

### First, always

```bash
./cqmdev doctor
```

It checks every value that can change build output *without* producing an
error — interpreter versions, compiler version, locale, `/bin/sh`, the exact
bytes `dtc` produces, and the toolchain's own checksums.

This matters more than it sounds. Two environments that were supposed to be
identical once differed only in their default `python3` (3.10 against 3.8) and
their locale (POSIX against `en_US.UTF-8`). Nothing failed. They just built
different things, and it took a long time to work out why. `doctor` turns that
class of problem into a one-line failure.

### Common failures

**`docker pull` fails / `denied`**

Your network cannot reach `ghcr.io`. Ask Cavli for the image tar:

```bash
docker load -i cqm22x-buildenv.tar
bash container_docker_helper.sh -w /mnt/ -t ~/cqm22x/qcom/1.1.0 -P
```

**`checksum mismatch`**

The download was truncated. Re-run with `-F` to fetch it again. Do not try to
unpack it — the script refuses for good reason.

**`Google Drive is refusing this file right now`**

Drive's per-file download quota. Wait, or ask Cavli for an HTTPS mirror and
pass that URL to `-u` instead.

**`only NN GB free`**

The bundle needs about 60 GB unpacked plus the download. Point `-r` at a bigger
filesystem.

**Build fails on a zero-byte binary**

`git lfs pull` did not run. From the tree root:

```bash
repo forall -c 'git lfs pull'
```

**`FileNotFoundError: .../staging_dir/host/bin/mkfs.ubifs` in the meta step**

You ran `-m nonhlos` on a tree that has never had the app side built. Run
`-m all` once first; see [4. Build](#4-build).

**`Modem version: <none>` and `error: pathspec ... cav_common.h did not match`**

The version-stamping step looks for `cav_common.h` at paths that only exist in
the cqm220-0 layout. On cqm220-3 it fails silently and the firmware is built
without a version string. Known issue in the build scripts, not the
environment — the build itself completes.

**Meta step: `boot.img is NOT listed in contents.xml`**

Misleading message: the file *is* listed, but not with the element type the
validator wants. Seen on a clean sync of the current `cqm220-3` branch tip
while an older tree at build-scripts `9366135` packages fine, so it is a
source-side regression rather than anything to fix on your machine. Everything
up to the meta step — tz, boot, modem, app, recovery — builds correctly.

**Something wrote into the toolchain**

It cannot: `/pkg` is mounted read-only. If a build claims it needs to write
there, that is a bug in the build script, not a permissions problem to work
around.

### Reset without losing anything

The container holds no state — the toolchain, source and every cache are bind
mounts from the host. Throwing it away costs nothing:

```bash
bash container_docker_helper.sh -w /mnt/ -t ~/cqm22x/qcom/1.1.0 -P --force
```

---

## 7. For Cavli: publishing a new bundle

On a machine with a known-good `/pkg`:

```bash
./pack-bundle.sh --component all --version 1.1.0 --source /pkg --upload
```

It stages each component's subtrees, writes `MANIFEST.txt` and a sampled
`SHA256SUMS.spot`, compresses with zstd and uploads the archives plus their
checksums to Drive.

For **qcom**, send recipients the link and the sha256; they pass them to `-u`
and `-c`. For **yocto** and **openwrt**, make the Drive files link-shareable and
put the links and checksums into `container_docker_helper.sh` (`URL_yocto` /
`URL_openwrt` near the top) — recipients then need to be told nothing.

The yocto tree is usually not under `/pkg` on the packing host, so point at it
explicitly:

```bash
./pack-bundle.sh --component yocto --version 1.1.0 \
    --map downloads=/srv/yocto/downloads \
    --map llvm-arm-toolchain-ship=/srv/yocto/llvm-arm-toolchain-ship
```

Staging needs ~50 GB. It defaults to a directory beside the output rather than
`/tmp`, which is often a tmpfs far smaller than the bundle.

**Never commit the qcom link.** It points at Qualcomm proprietary toolchains,
and the repository holding these scripts is public. The image itself carries
nothing licensed, which is exactly why it can be published openly while that
bundle cannot. The yocto and openwrt bundles are a different matter: they are
caches built from public sources, so their links are committed on purpose.

### Publishing a new base image

Edit `cqm22x/Dockerfile`, then run the **Build base image** workflow with a
version and `push: true`. The workflow asserts the environment contract and
that `dtc` still reproduces its reference fixture before anything is pushed.

New packages on ghcr are private by default — flip the new version to public in
the package settings, or nobody can pull it.
