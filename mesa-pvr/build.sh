#!/bin/bash
# Usage: mesa-pvr/build.sh            (run on the x86_64 build machine)
#
# Phase C (vendor stack): StarFive's Mesa = Mesa 22.1.3 + the patches from
# github.com/starfive-tech/buildroot package/mesa3d (branch JH7110_VisionFive2_devel), incl.
# "Add PVR Gallium driver" (a thin DRI driver on top of Imagination's closed libpvr_dri_support.so
# from img-gpu-powervr-bin 1.19). Gives EGL/GBM/Wayland + GLES for the closed driver.
# Cross-built in the docker image of mesa/Dockerfile, installed into /opt/mesa-pvr and packaged as
# debs/mesa-pvr-jh7110_22.1.3-<rev>_riscv64.deb. Needs the vendor kernel (pvrsrvkm) at runtime.
set -euo pipefail
VER=22.1.3
REV=${PKGREV:-1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREFIX=/opt/mesa-pvr
IMAGE=mesa-cross-riscv64:trixie

cd "$ROOT/mesa-pvr"
if [ ! -d "mesa-$VER" ]; then
	curl -fsSLO "https://archive.mesa3d.org/older-versions/22.x/mesa-$VER.tar.xz"
	tar xf "mesa-$VER.tar.xz"
	for p in $(ls patches/*.patch | sort); do
		echo ">> $p"
		patch -d "mesa-$VER" -p1 --no-backup-if-mismatch -s < "$p"
	done
fi
cp ../mesa/cross-riscv64.ini . 2>/dev/null || true

docker run --rm -u "$(id -u):$(id -g)" -v "$ROOT/mesa-pvr:/w" -w /w -e VER="$VER" -e PREFIX="$PREFIX" \
	"$IMAGE" bash -euo pipefail -c '
meson setup --wipe /w/build/obj /w/mesa-$VER --cross-file /w/cross-riscv64.ini --prefix=$PREFIX \
	--libdir=lib -Dbuildtype=release -Db_ndebug=true \
	-Dplatforms=wayland -Ddri3=disabled -Dgallium-drivers=pvr -Dvulkan-drivers= \
	-Dglx=disabled -Degl=enabled -Dgbm=enabled -Dgles1=enabled -Dgles2=enabled -Dopengl=true \
	-Dshared-glapi=enabled -Dglvnd=false -Dllvm=disabled -Dvalgrind=disabled -Dlibunwind=disabled \
	-Dlmsensors=disabled -Dzstd=enabled -Dgallium-vdpau=disabled \
	-Dgallium-va=disabled -Dgallium-xa=disabled -Dgallium-nine=false -Dgallium-opencl=disabled \
	-Dbuild-tests=false -Dmicrosoft-clc=disabled
ninja -C /w/build/obj
rm -rf /w/build/pkg
DESTDIR=/w/build/pkg ninja -C /w/build/obj install
'

P=build/pkg
mkdir -p "$P/DEBIAN"
cat > "$P$PREFIX/env.sh" <<EOF
# Source this to use StarFive's Mesa (pvr DRI driver on Imagination's closed driver) from $PREFIX.
# Needs the vendor kernel (pvrsrvkm) and the closed userspace from /opt/img-gpu.
export LD_LIBRARY_PATH=$PREFIX/lib:/opt/img-gpu/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
export LIBGL_DRIVERS_PATH=$PREFIX/lib/dri
export GBM_BACKENDS_PATH=$PREFIX/lib/gbm
EOF
cat > "$P/DEBIAN/control" <<EOF
Package: mesa-pvr-jh7110
Version: $VER-$REV
Architecture: riscv64
Maintainer: linux-drm-jh7110 <noreply@localhost>
Section: libs
Priority: optional
Depends: libc6, libdrm2, libexpat1, zlib1g, libzstd1, libwayland-client0, libwayland-server0, libx11-6, libx11-xcb1, libxcb1, libxshmfence1
Description: StarFive Mesa $VER (PVR DRI driver for Imagination's closed driver), in $PREFIX
 Mesa $VER with StarFive's buildroot patches; does not replace Debian's Mesa.
EOF
chmod 755 "$P"
mkdir -p "$ROOT/debs"
fakeroot dpkg-deb --build -Zxz "$P" "$ROOT/debs/mesa-pvr-jh7110_${VER}-${REV}_riscv64.deb"
