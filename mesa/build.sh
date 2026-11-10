#!/bin/bash
# Usage: mesa/build.sh [version]          (default 26.3.0; run on the x86_64 build machine)
#
# Cross-builds Mesa for the VisionFive 2 in the docker image mesa-cross-riscv64:trixie
# (mesa/Dockerfile) and packages it as debs/mesa-jh7110_<version>-<rev>_riscv64.deb.
#
# The package installs into /opt/mesa-jh7110 only, so it never replaces Debian's Mesa
# packages: rollback = `apt purge mesa-jh7110`. Programs use it through
# /opt/mesa-jh7110/env.sh (or the wrapper /usr/local/bin/mesa-jh7110-run).
#
# Two stages (the imagination Vulkan driver needs host tools at build time):
#   1. native x86_64 build of the host tools mesa_clc, vtn_bindgen2 and pdsc_precomp
#   2. riscv64 cross build with -Dmesa-clc=system -Dprecomp-compiler=system
# Local Mesa patches: mesa/patches-<version>/*.patch (applied once, marker mesa-<ver>/.patched).
# Drivers: imagination (PowerVR Vulkan, BXE-4-32 is "unsupported" upstream so it needs
# PVR_I_WANT_A_BROKEN_VULKAN_DRIVER=1), zink (OpenGL on Vulkan), softpipe (fallback).
set -euo pipefail
VER=${1:-26.3.0}
REV=${PKGREV:-1}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREFIX=/opt/mesa-jh7110
IMAGE=mesa-cross-riscv64:trixie

cd "$ROOT/mesa"
[ -d "mesa-$VER" ] || { curl -fsSLO "https://archive.mesa3d.org/mesa-$VER.tar.xz" && tar xf "mesa-$VER.tar.xz"; }
# Our patches on top of the release (if any)
if [ -d "patches-$VER" ] && [ ! -f "mesa-$VER/.patched" ]; then
	for p in "patches-$VER"/*.patch; do [ -e "$p" ] && patch -d "mesa-$VER" -p1 < "$p"; done
	touch "mesa-$VER/.patched"
fi

cat > cross-riscv64.ini <<'EOF'
[binaries]
c = 'riscv64-linux-gnu-gcc'
cpp = 'riscv64-linux-gnu-g++'
ar = 'riscv64-linux-gnu-ar'
strip = 'riscv64-linux-gnu-strip'
pkg-config = 'pkg-config'
[properties]
pkg_config_libdir = ['/usr/lib/riscv64-linux-gnu/pkgconfig', '/usr/share/pkgconfig']
[host_machine]
system = 'linux'
cpu_family = 'riscv64'
cpu = 'riscv64'
endian = 'little'
EOF

docker run --rm -u "$(id -u):$(id -g)" -v "$ROOT/mesa:/w" -w /w -e VER="$VER" -e PREFIX="$PREFIX" \
	"$IMAGE" bash -euo pipefail -c '
src=/w/mesa-$VER
# --- stage 1: host tools ---
if [ ! -x /w/build-native/install/bin/mesa_clc ]; then
	meson setup --wipe /w/build-native/obj $src --prefix=/w/build-native/install \
		-Dbuildtype=release -Dplatforms= -Dgallium-drivers= -Dvulkan-drivers=imagination \
		-Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled \
		-Dllvm=enabled -Dmesa-clc=enabled -Dinstall-mesa-clc=true \
		-Dprecomp-compiler=enabled -Dinstall-precomp-compiler=true \
		-Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dvideo-codecs=
	ninja -C /w/build-native/obj install
fi
export PATH=/w/build-native/install/bin:$PATH
# --- stage 2: riscv64 ---
meson setup --wipe /w/build-riscv64/obj $src --cross-file /w/cross-riscv64.ini --prefix=$PREFIX \
	--libdir=lib -Dbuildtype=release \
	-Dplatforms=x11,wayland -Dvulkan-drivers=imagination -Dgallium-drivers=zink,softpipe \
	-Dglx=dri -Degl=enabled -Dgbm=enabled -Dglvnd=disabled -Dgles1=disabled -Dgles2=enabled \
	-Dllvm=disabled -Dmesa-clc=system -Dprecomp-compiler=system \
	-Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dvideo-codecs= \
	-Dvulkan-layers=device-select
ninja -C /w/build-riscv64/obj
rm -rf /w/build-riscv64/pkg
DESTDIR=/w/build-riscv64/pkg ninja -C /w/build-riscv64/obj install
'

# --- package ---
P=build-riscv64/pkg
mkdir -p "$P/DEBIAN" "$P/usr/local/bin"
cat > "$P$PREFIX/env.sh" <<EOF
# Source this to use the Mesa in $PREFIX (PowerVR Vulkan + Zink OpenGL) instead of Debian's.
export LD_LIBRARY_PATH=$PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
export LIBGL_DRIVERS_PATH=$PREFIX/lib/dri
export GBM_BACKENDS_PATH=$PREFIX/lib/gbm
export VK_DRIVER_FILES=\$(ls $PREFIX/share/vulkan/icd.d/*.json | paste -sd:)
export VK_ADD_LAYER_PATH=$PREFIX/share/vulkan/implicit_layer.d
export PVR_I_WANT_A_BROKEN_VULKAN_DRIVER=1
export MESA_VK_DEVICE_SELECT=1010:36054182
# No MESA_LOADER_DRIVER_OVERRIDE: on the display card (driver "verisilicon") Mesa uses kmsro,
# which renders with Zink on the PowerVR GPU into scanout buffers of the display. For
# headless use of the PowerVR render node only, set MESA_LOADER_DRIVER_OVERRIDE=zink yourself.
EOF
cat > "$P/usr/local/bin/mesa-jh7110-run" <<EOF
#!/bin/sh
# Run a program with the Mesa from $PREFIX: mesa-jh7110-run vkcube
. $PREFIX/env.sh
exec "\$@"
EOF
chmod +x "$P/usr/local/bin/mesa-jh7110-run"
cat > "$P/DEBIAN/control" <<EOF
Package: mesa-jh7110
Version: $VER-$REV
Architecture: riscv64
Maintainer: linux-drm-jh7110 <noreply@localhost>
Section: libs
Priority: optional
Depends: libc6, libdrm2, libexpat1, zlib1g, libzstd1, libwayland-client0, libwayland-server0, libx11-6, libx11-xcb1, libxcb1, libxshmfence1
Description: Mesa $VER for the StarFive JH7110 (PowerVR BXE-4-32 Vulkan + Zink), in $PREFIX
 Self-contained Mesa build installed in $PREFIX; does not replace Debian's Mesa.
 Use: . $PREFIX/env.sh  or  mesa-jh7110-run <program>
EOF
mkdir -p "$ROOT/debs"
fakeroot dpkg-deb --build -Zxz "$P" "$ROOT/debs/mesa-jh7110_${VER}-${REV}_riscv64.deb"
