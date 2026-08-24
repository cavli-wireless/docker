# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Docker build environments for Cavli Wireless firmware, one directory per
product family. There is no application code, no test suite and no build
system — everything is bash plus Dockerfiles. "Building" means building a
Docker image; "testing" means running the environment check inside a container.

Two generations live here side by side and share nothing:

- **`cqm22x/`** — the current design. One public image + three separately
  distributed bundles, UID mapped at runtime, environment pinned and asserted.
  Serves three product lines (`cqm220-3`/sdx35, `cqm220-0`/sdx32, `cqm211`/
  sdx61-62-65). This is where active work happens.
- **`sdx/`, `sdx35/{18,20,22}.04/`, `c10qm/`, `cqs290/`, `le/22.04/`,
  `common/`** — the legacy pattern, kept working and deliberately untouched.
  `cqm22x/container_docker_helper.sh` aborts rather than reuse their image
  paths or container names (`assert_no_legacy_collision`).

Do not refactor legacy directories into the cqm22x style, or make cqm22x share
code with `common/`. The separation is intentional.

## Commands

### cqm22x (current)

```bash
# set up a machine: fetch/verify bundles, create one container per product, check each
bash cqm22x/container_docker_helper.sh -w /mnt/ -u '<qcom link>' -c '<sha256>'
bash cqm22x/container_docker_helper.sh -w /mnt/ -p cqm211 -u '<qcom link>' -c '<sha256>'
bash cqm22x/container_docker_helper.sh -w /mnt/ -p all -u '<qcom link>' -c '<sha256>'
bash cqm22x/container_docker_helper.sh -d ...     # dry run — prints the plan, changes nothing
docker start -i build_cqm22x_jammy_$(whoami)

# the environment contract — the closest thing to a test suite here
docker exec -u "$(id -u):$(id -g)" build_cqm22x_jammy_$(whoami) cqm-doctor
./cqm22x/cqmdev doctor

# build the public base image locally (no proprietary content needed)
docker build -t cqm22x-buildenv:dev cqm22x/

# day to day
./cqm22x/cqmdev sync | shell | build -m all -t MBB-CAV -v debug | status
./cqm22x/cqmdev -p cqm220-0 shell        # the second product

# Cavli side: publish bundles (qcom | yocto | openwrt | all)
./cqm22x/pack-bundle.sh --component all --version 1.1.0 --source /pkg --upload
```

Publishing a new base image is a manual `workflow_dispatch` of
`.github/workflows/cqm22x-buildenv.yml` with a version and `push: true`. New
ghcr packages default to private — flip the version to public afterwards.

### Legacy directories

Same two-script shape everywhere (`<family>/[<ubuntu-version>/]`):

```bash
bash create_docker_image.sh      # cp Dockerfile.base Dockerfile; docker build -> ghcr.io/...
bash normal_docker_helper.sh -w <src> -t <tools>   # render Dockerfile.template per user, build, run
```

`Dockerfile` in those directories is a generated artifact (`.gitignore` has
`./**/Dockerfile`, though several were committed before that). Edit
`Dockerfile.base` or `Dockerfile.template`, never `Dockerfile`.
`cqm22x/Dockerfile` is the exception: it is hand-written and tracked.

## Architecture

### The cqm22x split, and why

| | Contents | Needed by | Distribution |
|---|---|---|---|
| Base image | Ubuntu 22.04, Python 3.6/3.8/3.10, gcc-10, repo, dtc, rclone (~2.4 GB) | everything | `ghcr.io/cavli-wireless-public/cqm22x-buildenv`, public |
| `qcom` bundle | HEXAGON, LLVM, linaro, sectools, prebuilts (~13 GB packed, ~60 GB unpacked) | every product | out of band, mounted read-only |
| `yocto` bundle | bitbake `DL_DIR` cache + `llvm-arm-toolchain-ship` (~24 GB packed) | `cqm211` | link committed in the setup script |
| `openwrt` bundle | `openwrt-prebuilt-backup` (~2.3 GB packed) | `cqm220-0/3` | link committed in the setup script |

The image is public and must stay free of licensed material, so the toolchain can
never be baked in. **Never commit the qcom link or its Drive URL** — it points at
Qualcomm proprietary toolchains and this repository is public; it is passed per
recipient with `-u`/`-c`. The yocto and openwrt bundles are caches built from
public sources, so their links (`URL_yocto`, `URL_openwrt` near the top of
`container_docker_helper.sh`) are committed deliberately — that is what makes
setup a single command for those.

The product→bundle mapping lives in `components_for()` in
`container_docker_helper.sh`; adding a product means adding a case there, a
container-name case in `container_for()` and in `cqmdev`, and a branch in
`doctor.sh`'s `WANT_YOCTO`/`WANT_OPENWRT`.

### The environment contract

`cqm22x/doctor.sh` (installed as `cqm-doctor`) is the load-bearing piece.
It pins every value that can change build output *without* raising an error —
default `python3`, gcc version, `LANG`, `/bin/sh` → bash, and the exact sha256
`dtc` produces for a reference `.dts`. Two environments once drifted to
different `python3` versions and locales and silently built different things;
that is what this exists to catch.

These pins are duplicated in three places and must be changed together:

- `cqm22x/Dockerfile` — what gets installed
- `cqm22x/doctor.sh` — `EXPECT_*` constants, including `EXPECT_DTB_SHA`
- `.github/workflows/cqm22x-buildenv.yml` — the same assertions plus the inline
  reference `.dts` fixture and its sha256

Changing a version in the Dockerfile without updating the other two makes CI
fail, which is the intended behaviour — do not "fix" it by relaxing a check.

### Runtime identity

`cqm22x/entrypoint.sh` creates the user from `CQM_UID`/`CQM_GID` at container
start, so one published image serves everyone and files written into `/work`
stay owned by the caller. The legacy helpers instead render
`Dockerfile.template` and build a per-user image tag — that is the pattern
cqm22x deliberately replaced.

Note: `docker exec` bypasses the entrypoint, so anything invoked that way must
pass `-u "$(id -u):$(id -g)"` and cannot rely on env the entrypoint exports
(`cqmdev` and `doctor.sh` both handle this explicitly).

### Container layout

Nothing large lives in the container — toolchains, source and every cache are
bind mounts, so the writable layer stays ~200 kB and the container is
disposable. There is one container per product because caches must not be
shared: two products must never share an OpenWrt `build_dir`/`staging_dir`, and
`/pkg/openwrt` is a fixed path inside the image.

`/pkg` is mounted read-only on purpose: if a build claims it must write there,
that is a build-script bug, not a permission to widen. The single deliberate
exception is `/pkg/yocto/downloads` — bitbake's `DL_DIR` ships prefilled but has
to accept new downloads, and it is a cache rather than a toolchain.

USB uses device-cgroup rules scoped to 189/188 plus an `rslave` bind of
`/dev/bus/usb` — **not** `--privileged` (the legacy helpers do use
`--privileged`; do not copy that into cqm22x).

## Conventions

- Every download in `cqm22x/Dockerfile` is pinned by sha256 as a build ARG.
  Adding an unpinned `curl`/`wget` there is a regression.
- `container_docker_helper.sh` must stay re-runnable and honour `-d` (dry run)
  for every side effect — use its `run()` wrapper, not bare commands.
- `cqm22x/cqmdev` derives container names from the same
  `build_cqm22x_jammy` prefix as the helper; the two must agree
  (cqm220-3 gets the plain name, every other product gets a `_<product>` suffix).
- `pack-bundle.sh` defaults zstd level per component: 15 for `qcom` (raw
  binaries, ~4:1) and 1 for the cache bundles, whose payload is already
  compressed. Do not raise the latter — it costs hours for a fraction of a
  percent.
- Commit messages: `cqm22x: lower-case imperative summary`.
- Substantive comments explain *why* — most existing ones record a specific
  failure that motivated the line. Match that; don't strip them.
- User-facing behaviour changes belong in `cqm22x/README.md` (overview and
  design rationale) and `cqm22x/GUIDE.md` (end-to-end walkthrough and the
  troubleshooting list).
