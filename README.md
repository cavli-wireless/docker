# Cavli build containers

Docker build environments for Cavli CQM2xx firmware. One public image
(`ghcr.io/cavli-wireless-public/cqm22x-buildenv`) plus toolchain bundles,
set up by one script, `cqm22x/cqm22x-setup`, for every product line:

| Product | Userspace | Bundles `setup` fetches |
|---|---|---|
| `cqm211` | Yocto | yocto (+ prebuilts from openwrt) |
| `cqm212` | OpenWrt | openwrt212, kprebuilts212 |
| `cqm220-0` | OpenWrt | openwrt, buildroot |
| `cqm220-3` | OpenWrt | openwrt, buildroot |

All products share one container, `build_cqm2xx_<user>`, which mirrors your host
user (name, uid/gid, groups, `$HOME` path), so build output is owned by you.

There are two install modes:

| Mode | Who | What it can build | Login |
|---|---|---|---|
| customer (default) | customers, application developers | the app build (`-m app`) and the SDK | none |
| full (`--full`) | Cavli engineers | everything above + boot, tz, modem, meta (flashable release) | GitHub, `cavli-wireless` org member |

The full mode adds the Qualcomm toolchains (HEXAGON, LLVM, ARM, sectools). They
are licensed, so they are never in the image or this repository: the script
pulls them from a private release that only `cavli-wireless` members can read.

- [1. Requirements](#1-requirements)
- [2. Customers: set up without login](#2-customers-set-up-without-login)
- [3. Cavli engineers: set up with GitHub login](#3-cavli-engineers-set-up-with-github-login)
- [4. Per product: setup, source, build](#4-per-product-setup-source-build)
- [5. Daily use](#5-daily-use)
- [6. Troubleshooting](#6-troubleshooting)
- [7. Other directories](#7-other-directories)

---

## 1. Requirements

| | |
|---|---|
| Host | Ubuntu / Debian x86_64 with Docker; your user in the `docker` group |
| Tools | `curl`, `wget`, `tar`, `zstd`, `jq` |
| Disk | tens of GB per product for bundles and caches, plus the source trees; full mode adds the Qualcomm toolchains (about 60 GB unpacked) |
| Network | `github.com`, `ghcr.io`, `drive.usercontent.google.com` |

```bash
sudo apt update && sudo apt install -y curl wget tar zstd jq
sudo usermod -aG docker $USER      # then log out and back in
```

Everything the script installs lives under `$CQM_ROOT` (default `~/cqm22x`).
To keep it on a big disk, set it before every command:

```bash
export CQM_ROOT=/mnt/data/cqm22x
```

Get the script:

```bash
wget https://raw.githubusercontent.com/cavli-wireless/docker/main/cqm22x/cqm22x-setup
chmod +x cqm22x-setup
```

---

## 2. Customers: set up without login

```bash
./cqm22x-setup setup cqm220-0 -m /path/to/src     # one product
./cqm22x-setup setup cqm211 cqm212 -m /path/to/src  # several
./cqm22x-setup setup -m /path/to/src              # all four
```

- No GitHub account, password or token is needed: the image and the
  openwrt, openwrt212, kprebuilts212, yocto and buildroot bundles are public,
  and their links and sha256 are pinned in the script.
- Nothing Qualcomm is downloaded or mounted. `cqm-doctor` reports the qcom
  checks as "not installed (customer install)", which is expected.
- `-m <dir>` mounts a host directory at the same path inside (repeatable). Put
  your source trees there. `$CQM_ROOT/workspace` is always mounted.
- Run `setup` again with another product to add it; the container is recreated
  with all installed products, nothing is downloaded twice.

If Cavli gave you the bundles on disk instead of a download (offline site), point
the script at that directory; `--full` is then allowed without a login, because
the qcom bundle is read from disk and checked against its `SHA256SUMS`:

```bash
./cqm22x-setup --bundle-dir /path/to/bundles setup --full cqm220-0 -m /path/to/src
```

Layout: one directory per component your products need, each with a
`BUNDLE_VERSION` file that matches the script's bundle version:

- `qcom/`: the archives plus `SHA256SUMS`, checked before unpacking.
- `openwrt/`, `openwrt212/`, `kprebuilts212/`, `yocto/`, `buildroot/`: the
  files named in the script, each checked against its pinned sha256.
  `buildroot/` is optional: without it the bundle is skipped.

---

## 3. Cavli engineers: set up with GitHub login

You need a GitHub account that is a member of the `cavli-wireless` org, and an
SSH key on that account (for `repo sync` of the private trees).

```bash
./cqm22x-setup setup --full cqm220-0 -m /path/to/src
```

On the first `--full` run the script starts a throwaway container and runs
`gh auth login --web` in it:

1. It prints a one-time device code and `https://github.com/login/device`.
2. Open the URL in any browser (any machine; works the same over SSH), sign in
   with your Cavli GitHub account and enter the code.
3. The script downloads the qcom release, verifies `SHA256SUMS`, unpacks it
   and creates the container.

The GitHub token is kept in `$CQM_ROOT/home/.config/gh`, not in your
real home, and is reused by later `setup` / `update` runs. The mode is
remembered too: later plain `setup` and `update` stay in full mode. Not an org
member, or no access: it stops with one error and installs nothing.

`~/.ssh` is mounted read-only into the container (turn off with `--no-ssh`), so
the key you use on the host works for `repo sync` inside.

Check:

```bash
./cqm22x-setup status        # mode: full, installed products, mounts
```

---

## 4. Per product: setup, source, build

The manifests repository of each line holds the branches, the manifest file and
the full build walkthrough in its README. Keep source paths short (≲ 80
characters): OpenWrt and Yocto builds fail on long absolute paths.

| Product | `setup` argument | Source (`repo init -u`) | Build entry |
|---|---|---|---|
| cqm211 | `cqm211` | `git@github.com:cavli-wireless/cqm211-manifests.git` | `build/build.sh -t cavli` (M.2: `-t cavli-m2`) |
| cqm212 | `cqm212` | `git@github.com:cavli-wireless/cqm212-manifests.git` | `build/build.sh -t cavli` (M.2: `-t cavli-m2`) |
| cqm220-0 | `cqm220-0` | `git@github.com:cavli-wireless/cqm22x-manifests.git` | `build/build.sh -t cavli` from the chipcode root (M.2: `-t cavli-m2`) |
| cqm220-3 | `cqm220-3` | `git@github.com:cavli-wireless/cqm22x-manifests.git` | `build/build.sh -t cavli` from the chipcode root (M.2: `-t cavli-m2`) |

Example (cqm212, full mode):

```bash
./cqm22x-setup setup --full cqm212 -m /mnt/data/src
docker exec -it --user $(id -un) -e HOME=$HOME build_cqm2xx_$(id -un) bash -l

# inside the container
cqm-doctor cqm212
mkdir -p /mnt/data/src/cqm212 && cd /mnt/data/src/cqm212
repo init -u git@github.com:cavli-wireless/cqm212-manifests.git -b <branch> -m <manifest.xml>
repo sync -c -j8
bash build/build.sh -t cavli -m all -V 1.0.0
```

Product notes:

- **cqm211** (Yocto): bitbake's download cache is `/pkg/yocto/downloads`, a
  writable cache kept in `$CQM_ROOT/cache/yocto-downloads`; the LLVM/ARM
  toolchain from the yocto bundle is mounted read-only.
- **cqm212** (OpenWrt): the kernel prebuilts are mounted at
  `/pkg/prebuilts-kobuk`; `--no-kernel-prebuilts` skips that bundle and the build
  then syncs them from CodeLinaro (a large, slow download).
- **cqm220-0 / cqm220-3** (OpenWrt): both use the arm OpenWrt cache at
  `/pkg/openwrt-prebuilt-backup`. The Buildroot bundle (toolchain + `dl/`) is
  mounted at `/pkg/buildroot`; `--no-buildroot` skips it.
- Each product has its own writable caches: `/ccache/<product>` and, for
  cqm220-x, `/pkg/openwrt/<product>`. Set `export CCACHE_DIR=/ccache/<product>`
  before building, so two products never share a cache.
- Customer mode: the app build (`-m app`) and the SDK; `boot`, `tz`, `modem`
  and `meta` need full mode.

---

## 5. Daily use

```bash
docker exec -it --user $(id -un) -e HOME=$HOME build_cqm2xx_$(id -un) bash -l   # shell
docker exec --user $(id -un) build_cqm2xx_$(id -un) cqm-doctor                  # check all products
./cqm22x-setup status        # what is installed, mode, mounts
./cqm22x-setup update        # new image and bundles, same products, mounts and mode
./cqm22x-setup version       # image tag and bundle version this script targets
```

- Always pass `--user $(id -un)` to `docker exec`: without it you land as root
  and the build output becomes root-owned.
- The container holds no state: source, toolchains and caches are bind mounts.
  `setup` and `update` recreate it; anything running inside is stopped.
- Mounts are fixed when the container is created: to add a directory, run
  `./cqm22x-setup update -m <new dir>` (installed products and earlier mounts
  are kept). Plain `setup` with no product installs all four.
- A second, separate container (another user or a test): use a separate
  `CQM_ROOT` and `--name <suffix>` → `build_cqm2xx_<user>_<suffix>`.

---

## 6. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `cqm-doctor` `FAIL  writable … not writable` | a mounted dir is not owned by you; mount a dir your user owns |
| `qcom bundle: nothing installed — … not an org member, or the release is missing` | your GitHub account is not in `cavli-wireless`, or logged in with another account; ask your Cavli contact |
| `curl: (22) … error: 403` or `429` while fetching a bundle | the public download hit a quota or rate limit; retry later, or use `--bundle-dir` |
| `<component>/<file> checksum mismatch` | truncated or wrong download; run `setup` again (a bad file is fetched again) |
| `'<name>' already exists and this script did not create it` | a container with that name exists from another setup; use `--name <suffix>` and a separate `CQM_ROOT` |
| `Permission denied (publickey)` in `repo sync` | no SSH key mounted or no access; test `ssh -T git@github.com` inside |
| build files owned by root | `docker exec` without `--user $(id -un)` |
| "Argument list too long" / E2BIG in OpenWrt or Yocto | source path too long; move the tree to a shorter path |

---

## 7. Other directories

- `cqm22x/` — the current environment: `cqm22x-setup` (this README),
  `Dockerfile` (public image), `doctor.sh` (`cqm-doctor`), bundle packing
  scripts. Design notes: [cqm22x/README.md](cqm22x/README.md).
- `cqm22x/container_docker_helper.sh` — the older flow, one container per
  product (`build_cqm22x_jammy_<user>[_<product>]`), qcom bundle passed with
  `-u <link> -c <sha256>`. Still works; walkthrough in
  [cqm22x/GUIDE.md](cqm22x/GUIDE.md). New machines should use `cqm22x-setup`.
- `sdx/`, `sdx35/`, `c10qm/`, `cqs290/`, `le/`, `common/` — legacy environments
  for older products, kept unchanged.
