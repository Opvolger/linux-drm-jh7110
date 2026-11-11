#!/bin/sh
# Build perf for the VisionFive 2 (JH7110) from linux-<version>/tools/perf and package it as a .deb.
#
#   scripts/perf/build-perf.sh [version]          (default 7.3)
#
# Output: linux-perf-jh7110_<kernelversion>-<rev>_riscv64.deb in the repo root, installs /usr/bin/perf.
# Built in a Debian trixie container (see Containerfile) against libraries that are already
# on the board (libelf, libdw, slang, zlib, zstd, libcap, lzma). Left out on purpose, so no extra
# packages are needed on the board: libtraceevent, libpython, libperl, libnuma, libbabeltrace,
# libunwind (libdw does the DWARF unwinding), BPF skeletons (need clang).
set -e
cd "$(dirname "$0")/../.."
V=${1:-7.4}
IMAGE=${IMAGE:-jh7110-perf-build}
[ -d linux-$V/tools/perf ] || { echo "linux-$V/tools/perf missing (make checkout-$V)" >&2; exit 1; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker build -t "$IMAGE" -f scripts/perf/Containerfile scripts/perf

KVER=$(make -s -C linux-$V kernelversion)
last=$(ls debs 2>/dev/null | sed -n "s/^linux-perf-jh7110_${KVER}-\([0-9]*\)_riscv64\.deb$/\1/p" | sort -n | tail -1)
REV=${PKGREV:-$(( ${last:-0} + 1 ))}
OUT=build/perf-$V

docker run --rm -u "$(id -u):$(id -g)" -v "$PWD":/src -w /src "$IMAGE" sh -c "
	set -e
	rm -rf $OUT/pkg; mkdir -p $OUT/obj $OUT/pkg
	make -C linux-$V/tools/perf O=/src/$OUT/obj ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- \
		NO_LIBTRACEEVENT=1 NO_LIBPYTHON=1 NO_LIBPERL=1 NO_LIBNUMA=1 NO_LIBBABELTRACE=1 \
		NO_LIBUNWIND=1 NO_JVMTI=1 BUILD_BPF_SKEL=0 NO_SHELLCHECK=1 WERROR=0 PYTHON=python3 PYTHON_CONFIG=python3 \
		prefix=/usr DESTDIR=/src/$OUT/pkg -j\$(nproc) install-bin
	riscv64-linux-gnu-strip $OUT/pkg/usr/bin/perf
"
mkdir -p $OUT/pkg/DEBIAN
cat > $OUT/pkg/DEBIAN/control <<CTL
Package: linux-perf-jh7110
Version: $KVER-$REV
Architecture: riscv64
Maintainer: linux-drm-jh7110 <noreply@localhost>
Depends: libc6, libelf1t64, libdw1t64, libslang2, zlib1g, libzstd1, libcap2, liblzma5
Conflicts: linux-perf
Section: devel
Priority: optional
Description: perf for the VisionFive 2 (JH7110) kernels (tools/perf from Linux $KVER + JH7110 patches)
 Built by linux-drm-jh7110/scripts/perf/build-perf.sh without libtraceevent,
 python, perl, numa, babeltrace and BPF skeletons.
CTL
mkdir -p debs; fakeroot dpkg-deb --build $OUT/pkg debs/linux-perf-jh7110_${KVER}-${REV}_riscv64.deb
