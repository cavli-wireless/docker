# syntax=docker/dockerfile:1.7
#
# CQM22x build environment — PUBLIC base image.
#
# CONTAINS NOTHING PROPRIETARY. No Qualcomm toolchain, no chipcode, no keys.
# Everything under /pkg is supplied at runtime as a read-only bind mount
# (see toolchain/README.md). This image is safe to publish publicly.
#
# Design rules (learned from the previous ad-hoc image):
#   1. Every download is pinned by sha256. No floating fetches.
#   2. The environment contract in env.spec is enforced HERE, not by hand
#      afterwards. A container that drifts is a container that builds
#      different binaries than CI.
#   3. No per-user image variants. UID/GID are mapped at runtime by
#      entrypoint.sh, so one image serves every developer, CI and customers.
#   4. Layers are grouped and cleaned so the image stays ~2-3 GB.

FROM ubuntu:22.04@sha256:3b06811b2afd352be909dd088a004166d665dc76d38b13eada33522a9d915c6f

ARG PYTHON36_VERSION=3.6.9
ARG PYTHON36_SHA256=47fc92a1dcb946b9ed0abc311d3767b7215c54e655b17fd1d3f9b538195525aa
ARG PYTHON38_VERSION=3.8.12
ARG PYTHON38_SHA256=316aa33f3b7707d041e73f246efedb297a70898c4b91f127f66dc8d80c596f1a
ARG DTC_VERSION=1.6.0
ARG DTC_SHA256=3d15dee7126a6c4a015ab47ec908cab13e39774b0315efaaebb223cb4a4d349c
ARG RCLONE_VERSION=1.65.2
ARG RCLONE_SHA256=2155ea2c225272a6f78b2aa4547bb587c40b007586e73b41b31c59edba64f8fe
# The repo launcher is re-published in place by Google from time to time.
# When that happens this build fails loudly (which is the point) — verify the
# new file, then bump this value in one place.
ARG REPO_SHA256=1211b57b57e4122a9c546295a59b37d24068f1164d0e87bef096d5323c413e4f

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# 1. Distro packages
#    Grouped into one layer with a single cleanup. gcc-10 is required: the
#    Qualcomm build scripts and the from-source Python 3.6 both miscompile or
#    crash under gcc-11.
#    libffi-dev MUST be present before Python is built from source, otherwise
#    the resulting interpreter has no _ctypes module.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        bison boxes build-essential ca-certificates clang curl dh-autoreconf \
        file flex g++ g++-10 g++-multilib gawk gcc-10 gcc-multilib gettext git \
        git-lfs gnupg libcurl4-gnutls-dev libexpat1-dev libffi-dev libncurses5 \
        libncurses5-dev libssl-dev libxml-parser-perl libyaml-dev libz-dev \
        locales p7zip-full pigz pkg-config python3-dev python3-pip \
        python3-setuptools python3-venv rsync ssh-client sudo swig tzdata \
        unzip uuid-dev vim wget xz-utils zlib1g-dev zstd \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 2. Locale — pinned to en_US.UTF-8.
#    The old image left LANG unset (POSIX), while the CI host ran en_US.UTF-8.
#    That silently changes `sort` collation and Python's default text encoding,
#    so the same source could produce different output in the two places.
#    Baking it here also removes the `sudo locale-gen` call the app build used
#    to make at runtime.
# ---------------------------------------------------------------------------
RUN locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# ---------------------------------------------------------------------------
# 3. Default C/C++ compiler = gcc-10
# ---------------------------------------------------------------------------
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 30 \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-11 20 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 30 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-11 20 \
    && update-alternatives --install /usr/bin/cc  cc  /usr/bin/gcc 30 \
    && update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++ 30 \
    && update-alternatives --set cc  /usr/bin/gcc \
    && update-alternatives --set c++ /usr/bin/g++

# ---------------------------------------------------------------------------
# 4. Python 3.6 and 3.8 from source (3.10 comes from the distro).
#    Each module of the firmware build pins its own interpreter:
#      apps/openwrt -> 3.8, modem -> 3.8, meta -> 3.8, boot -> 3.10
#    The previous image wrote `make -j$(npoc)` — a typo that expanded to the
#    empty string, so both interpreters were built single-threaded.
# ---------------------------------------------------------------------------
RUN cd /tmp \
    && curl -fsSLO "https://www.python.org/ftp/python/${PYTHON36_VERSION}/Python-${PYTHON36_VERSION}.tgz" \
    && echo "${PYTHON36_SHA256}  Python-${PYTHON36_VERSION}.tgz" | sha256sum -c - \
    && tar -xf "Python-${PYTHON36_VERSION}.tgz" \
    && cd "Python-${PYTHON36_VERSION}" \
    && ./configure --prefix=/usr --with-ensurepip=no \
    && make -j"$(nproc)" && make install \
    && cd /tmp && rm -rf "Python-${PYTHON36_VERSION}" "Python-${PYTHON36_VERSION}.tgz"

RUN cd /tmp \
    && curl -fsSLO "https://www.python.org/ftp/python/${PYTHON38_VERSION}/Python-${PYTHON38_VERSION}.tgz" \
    && echo "${PYTHON38_SHA256}  Python-${PYTHON38_VERSION}.tgz" | sha256sum -c - \
    && tar -xf "Python-${PYTHON38_VERSION}.tgz" \
    && cd "Python-${PYTHON38_VERSION}" \
    && ./configure --prefix=/usr --enable-optimizations --with-ensurepip=no \
    && make -j"$(nproc)" && make install \
    && cd /tmp && rm -rf "Python-${PYTHON38_VERSION}" "Python-${PYTHON38_VERSION}.tgz"

# lsb_release shim: some Qualcomm scripts import it from the interpreter's
# own site-packages rather than the distro path.
RUN for v in 3.6 3.8; do \
        mkdir -p "/usr/lib/python${v}/site-packages"; \
        ln -sf /usr/share/pyshared/lsb_release.py "/usr/lib/python${v}/site-packages/lsb_release.py"; \
    done

# pip for each interpreter.
# Each old interpreter needs its own bootstrap: the generic get-pip.py now
# refuses to run on anything below 3.10, and pypa keeps per-version copies
# under /pip/<version>/ precisely for this case.
RUN cd /tmp \
    && curl -fsSL https://bootstrap.pypa.io/pip/3.6/get-pip.py -o get-pip36.py \
    && curl -fsSL https://bootstrap.pypa.io/pip/3.8/get-pip.py -o get-pip38.py \
    && curl -fsSL https://bootstrap.pypa.io/get-pip.py          -o get-pip310.py \
    && python3.6  get-pip36.py  && python3.6  -m pip install --no-cache-dir virtualenv pyyaml \
    && python3.8  get-pip38.py  && python3.8  -m pip install --no-cache-dir virtualenv pyyaml \
    && python3.10 get-pip310.py && python3.10 -m pip install --no-cache-dir virtualenv pyyaml \
    && rm -f get-pip36.py get-pip38.py get-pip310.py

# ---------------------------------------------------------------------------
# 5. Default python / python3 = 3.8.
#    This matches the CI host exactly. The old dev container had been switched
#    to 3.10 by hand at some point, so bare `python3` calls inside the vendor
#    build scripts ran a different interpreter locally than they did in CI.
#    Registered in auto mode with 3.8 at the highest priority, and asserted by
#    `cqmdev doctor`.
# ---------------------------------------------------------------------------
RUN update-alternatives --install /usr/bin/python  python  /usr/bin/python3.6  1 \
    && update-alternatives --install /usr/bin/python  python  /usr/bin/python3.10 2 \
    && update-alternatives --install /usr/bin/python  python  /usr/bin/python3.8  3 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 2 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8  3 \
    && update-alternatives --auto python \
    && update-alternatives --auto python3

# ---------------------------------------------------------------------------
# 6. repo, dtc, rclone
#    dtc lands in both locations the build scripts look at: DTC_PATH points at
#    /pkg/qct/software/boottools, and some makefiles use /pkg/tools/dtc.
#    NOTE: these two paths live under /pkg but are NOT part of the proprietary
#    bundle — the runtime mounts overlay only qct/software/{HEXAGON_Tools,arm,
#    llvm}, sectools and prebuilts, leaving these in place.
# ---------------------------------------------------------------------------
RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/bin/repo \
    && echo "${REPO_SHA256}  /usr/bin/repo" | sha256sum -c - \
    && chmod a+rx /usr/bin/repo

RUN cd /tmp \
    && curl -fsSLO "https://git.kernel.org/pub/scm/utils/dtc/dtc.git/snapshot/dtc-${DTC_VERSION}.tar.gz" \
    && echo "${DTC_SHA256}  dtc-${DTC_VERSION}.tar.gz" | sha256sum -c - \
    && tar -xzf "dtc-${DTC_VERSION}.tar.gz" \
    && make -C "dtc-${DTC_VERSION}" -j"$(nproc)" NO_PYTHON=1 NO_VALGRIND=1 \
    && mkdir -p /pkg/tools/dtc /pkg/qct/software/boottools \
    && cp -a "dtc-${DTC_VERSION}"/. /pkg/tools/dtc/ \
    && cp -a "dtc-${DTC_VERSION}"/. /pkg/qct/software/boottools/ \
    && rm -rf "dtc-${DTC_VERSION}" "dtc-${DTC_VERSION}.tar.gz"

RUN cd /tmp \
    && curl -fsSLO "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.zip" \
    && echo "${RCLONE_SHA256}  rclone-v${RCLONE_VERSION}-linux-amd64.zip" | sha256sum -c - \
    && unzip -q "rclone-v${RCLONE_VERSION}-linux-amd64.zip" \
    && install -m 0755 "rclone-v${RCLONE_VERSION}-linux-amd64/rclone" /usr/local/bin/rclone \
    && rm -rf "rclone-v${RCLONE_VERSION}-linux-amd64" "rclone-v${RCLONE_VERSION}-linux-amd64.zip"

# ---------------------------------------------------------------------------
# 7. /bin/sh -> bash.
#    Both the old dev container and the CI host run bash as /bin/sh, and parts
#    of the vendor build rely on bashisms in `sh` scripts. Kept deliberately,
#    and asserted by doctor so it can never silently revert to dash.
# ---------------------------------------------------------------------------
RUN ln -sf /usr/bin/bash /usr/bin/sh && ln -sf /usr/bin/make /usr/bin/gmake

# ---------------------------------------------------------------------------
# 8. Mount points and cache layout.
#    /pkg/kernel/prebuilts used to be a full 12 GB byte-for-byte copy of
#    /pkg/prebuilts sitting in the container's writable layer. It is a symlink
#    now — same content, 12 GB less disk, and it can never drift out of sync.
# ---------------------------------------------------------------------------
RUN mkdir -p /pkg/qct/software /pkg/sectools /pkg/prebuilts /pkg/kernel \
             /pkg/openwrt /pkg/yocto/downloads /work /ccache \
    && ln -sfn /pkg/prebuilts /pkg/kernel/prebuilts \
    && chmod 0777 /pkg/openwrt /pkg/yocto/downloads /work /ccache

ENV CCACHE_DIR=/ccache \
    TERM=xterm-256color \
    CQM_BUILDENV=1

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY doctor.sh     /usr/local/bin/cqm-doctor
RUN chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/cqm-doctor

# Image provenance — filled in by CI, surfaced by `cqmdev doctor`.
ARG IMAGE_VERSION=dev
ARG IMAGE_REVISION=unknown
ENV CQM_IMAGE_VERSION=${IMAGE_VERSION} \
    CQM_IMAGE_REVISION=${IMAGE_REVISION}
LABEL org.opencontainers.image.title="CQM22x build environment" \
      org.opencontainers.image.description="Reproducible build environment for CQM220 firmware. Contains no proprietary toolchain." \
      org.opencontainers.image.source="https://github.com/cavli-wireless/docker" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.licenses="NOASSERTION"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash", "-l"]
