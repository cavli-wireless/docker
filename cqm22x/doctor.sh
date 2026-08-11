#!/bin/bash
# cqm-doctor — assert this container matches the pinned build environment.
#
# Why this exists: the previous build container had been adjusted by hand over
# time until `python3` resolved to 3.10 locally while CI still ran 3.8, and the
# locale had drifted from en_US.UTF-8 to POSIX. Nothing failed loudly; the two
# environments just quietly compiled different things. Every value checked here
# is one that can change build output without producing an error.
#
# Exit 0 = environment matches. Exit 1 = drift, with the deltas listed.

set -uo pipefail

# ---- pinned contract -------------------------------------------------------
EXPECT_PYTHON3=3.8.12
EXPECT_PYTHON=3.8.12
EXPECT_PY36=3.6.9
EXPECT_PY38=3.8.12
EXPECT_PY310_MAJOR=3.10
EXPECT_GCC=10.5.0
EXPECT_LANG=en_US.UTF-8
# Compared by basename: on a merged-usr distro /bin/sh resolves to
# /usr/bin/bash, on others to /bin/bash. What matters is that it is bash and
# not dash — parts of the vendor build rely on bashisms in `sh` scripts.
EXPECT_SH=bash
EXPECT_DTC_VERSION="DTC 1.6.0"
# sha256 of the reference fixture compiled by dtc — verified byte-identical
# between dtc 1.6.0 and the 1.6.0-g183df9e9 build used on the CI host.
EXPECT_DTB_SHA=f97ab6a0c0a70458a18b83dcd2f86380aa46ba188fc5d5baaf6f5c435e20c2ed

pass=0; fail=0; warn=0
G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; D=$'\e[2m'; N=$'\e[0m'
[[ -t 1 ]] || { G=""; R=""; Y=""; D=""; N=""; }

ok()   { printf "  ${G}PASS${N}  %-34s ${D}%s${N}\n" "$1" "${2:-}"; ((pass++)); }
bad()  { printf "  ${R}FAIL${N}  %-34s expected %s, got %s\n" "$1" "$2" "$3"; ((fail++)); }
note() { printf "  ${Y}WARN${N}  %-34s %s\n" "$1" "${2:-}"; ((warn++)); }

check() { # check <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then ok "$1" "$3"; else bad "$1" "$2" "$3"; fi
}

pyver() { "$1" -c 'import platform;print(platform.python_version())' 2>/dev/null || echo missing; }

# `docker exec` does not run the entrypoint, so the environment it exports is
# not available here. Read the bundle version from the mount instead.
if [[ -z "${CQM_BUNDLE_VERSION:-}" && -r /pkg/BUNDLE_VERSION ]]; then
    CQM_BUNDLE_VERSION="$(cat /pkg/BUNDLE_VERSION)"
fi

echo
echo "cqm22x build environment check"
echo "  image     ${CQM_IMAGE_VERSION:-dev} (${CQM_IMAGE_REVISION:-unknown})"
echo "  bundle    ${CQM_BUNDLE_VERSION:-none}"
echo

# ---- 1. interpreters -------------------------------------------------------
echo "interpreters"
check "python3 default"  "$EXPECT_PYTHON3"    "$(pyver python3)"
check "python default"   "$EXPECT_PYTHON"     "$(pyver python)"
check "python3.6"        "$EXPECT_PY36"       "$(pyver python3.6)"
check "python3.8"        "$EXPECT_PY38"       "$(pyver python3.8)"
p310="$(pyver python3.10)"
check "python3.10"       "$EXPECT_PY310_MAJOR" "${p310%.*}"
if python3 -c 'import ctypes' 2>/dev/null; then ok "python3 _ctypes"; else bad "python3 _ctypes" "importable" "ImportError"; fi

# ---- 2. host compiler and shell -------------------------------------------
echo
echo "toolchain (host side)"
check "gcc"  "$EXPECT_GCC" "$(gcc -dumpfullversion 2>/dev/null || echo missing)"
check "g++"  "$EXPECT_GCC" "$(g++ -dumpfullversion 2>/dev/null || echo missing)"
check "/bin/sh"  "$EXPECT_SH" "$(basename "$(readlink -f /bin/sh 2>/dev/null || echo missing)")"
check "LANG"     "$EXPECT_LANG" "${LANG:-unset}"

# ---- 3. dtc: version and, more importantly, output ------------------------
echo
echo "device tree compiler"
dtc_bin=/pkg/qct/software/boottools/dtc
if [[ -x "$dtc_bin" ]]; then
    check "dtc version" "$EXPECT_DTC_VERSION" "$("$dtc_bin" --version 2>&1 | head -1 | sed 's/^Version: //')"
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    cat > "$tmp/ref.dts" <<'DTS'
/dts-v1/;
/ {
	compatible = "cavli,cqm22x-buildenv-selftest";
	#address-cells = <2>;
	#size-cells = <2>;
	model = "dtc reference fixture";
	chosen { bootargs = "selftest"; };
	memory@80000000 {
		device_type = "memory";
		reg = <0x0 0x80000000 0x0 0x10000000>;
	};
	soc {
		#address-cells = <1>;
		#size-cells = <1>;
		ranges;
		ref0: node@1000 {
			compatible = "cavli,ref";
			reg = <0x1000 0x100>;
			str = "abc";
			bytes = [00 11 22 33];
			cells = <0xdeadbeef 1 2 3>;
		};
	};
};
DTS
    if "$dtc_bin" -I dts -O dtb -o "$tmp/ref.dtb" "$tmp/ref.dts" 2>/dev/null; then
        check "dtc output (fixture sha256)" "$EXPECT_DTB_SHA" "$(sha256sum "$tmp/ref.dtb" | cut -d' ' -f1)"
    else
        bad "dtc output (fixture sha256)" "compiles" "dtc failed"
    fi
else
    bad "dtc" "$dtc_bin executable" "missing"
fi

# ---- 4. proprietary bundle -------------------------------------------------
echo
echo "toolchain bundle (/pkg)"
for p in /pkg/qct/software/HEXAGON_Tools /pkg/qct/software/llvm/release/arm \
         /pkg/qct/software/arm/linaro-toolchain /pkg/sectools/v2/latest/Linux \
         /pkg/prebuilts/clang; do
    if [[ -d "$p" ]]; then ok "present" "$p"; else bad "present" "$p" "missing"; fi
done

if [[ -L /pkg/kernel/prebuilts && "$(readlink -f /pkg/kernel/prebuilts)" == "$(readlink -f /pkg/prebuilts)" ]]; then
    ok "kernel/prebuilts -> prebuilts" "symlink (saves 12 GB)"
else
    note "kernel/prebuilts" "not the expected symlink to /pkg/prebuilts"
fi

# Spot-check the bundle against the checksums it shipped with, rather than
# hardcoding hashes here — the bundle is versioned independently of the image.
if [[ -r /pkg/SHA256SUMS.spot ]]; then
    if (cd /pkg && sha256sum -c --quiet SHA256SUMS.spot) 2>/dev/null; then
        ok "bundle spot checksums" "$(wc -l < /pkg/SHA256SUMS.spot) files verified"
    else
        bad "bundle spot checksums" "match" "mismatch — bundle is corrupt or modified"
    fi
else
    note "bundle spot checksums" "/pkg/SHA256SUMS.spot not found; cannot verify integrity"
fi

# Check the paths that are actually bind-mounted, not their parent: /pkg/qct
# itself belongs to the image and is writable by design, while the licensed
# subtrees underneath it are mounted individually.
rw_mounts=()
for p in /pkg/qct/software/HEXAGON_Tools /pkg/qct/software/arm \
         /pkg/qct/software/llvm /pkg/sectools /pkg/prebuilts; do
    findmnt -no TARGET "$p" >/dev/null 2>&1 || continue   # not a mount at all
    findmnt -no OPTIONS "$p" 2>/dev/null | grep -qw ro || rw_mounts+=("$p")
done
if (( ${#rw_mounts[@]} == 0 )); then
    ok "bundle mounted read-only"
else
    note "bundle mount" "writable: ${rw_mounts[*]} — a build could mutate the shared toolchain"
fi

# ---- 5. writable caches and workspace -------------------------------------
echo
echo "caches"
for p in /pkg/openwrt /pkg/yocto/downloads /ccache /work; do
    if [[ -w "$p" ]]; then ok "writable" "$p"; else bad "writable" "$p" "not writable"; fi
done

# ---- 6. identity -----------------------------------------------------------
echo
echo "identity"
# Running as root means files written into the bind-mounted workspace come out
# root-owned on the host. `docker exec` bypasses the entrypoint that maps the
# caller's UID, so the caller has to pass --user; flag it if it did not.
if [[ "$(id -u)" -eq 0 ]]; then
    note "user" "running as root — build output would be root-owned on the host"
else
    ok "user" "$(id -un) uid=$(id -u) gid=$(id -g)"
fi
if sudo -n true 2>/dev/null; then ok "sudo" "passwordless"; else note "sudo" "unavailable; some vendor scripts call it"; fi

# ---- summary ---------------------------------------------------------------
echo
if (( fail )); then
    printf "${R}%d failed${N}, %d passed, %d warnings\n\n" "$fail" "$pass" "$warn"
    echo "This container will not reproduce CI builds. Do not ship binaries from it."
    exit 1
fi
printf "${G}all %d checks passed${N}%s\n\n" "$pass" "$( ((warn)) && printf ', %d warnings' "$warn")"
