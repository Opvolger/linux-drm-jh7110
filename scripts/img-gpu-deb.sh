#!/bin/bash
# Usage: scripts/img-gpu-deb.sh
# Phase C: packages Imagination's closed PowerVR userspace for the JH7110 (DDK 1.19.6345021, from
# github.com/starfive-tech/soft_3rdpart IMG_GPU/out) as debs/img-gpu-jh7110_1.19.6345021-<rev>_riscv64.deb.
#   /opt/img-gpu/lib/...   driver libraries (NOT the GLES/Vulkan/OpenCL loader libs, so Debian's
#                          glvnd libGLESv2, Vulkan loader and OpenCL ICD loader are not shadowed)
#   /opt/img-gpu/icd.d/    Vulkan ICD json (use VK_DRIVER_FILES; not in /etc/vulkan/icd.d)
#   /lib/firmware/rgx.{fw,sh}.36.50.54.182   firmware for the vendor kernel's pvrsrvkm
# Needs the vendor kernel (6.12.5-vf2); the open drm/imagination stack is not affected.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VER=1.19.6345021
REV=${PKGREV:-1}
URL=https://github.com/starfive-tech/soft_3rdpart/raw/JH7110_VisionFive2_devel/IMG_GPU/out/img-gpu-powervr-bin-$VER.tar.gz
D=$ROOT/vendor
mkdir -p "$D"
[ -f "$D/img-gpu-powervr-bin-$VER.tar.gz" ] || curl -fsSL -o "$D/img-gpu-powervr-bin-$VER.tar.gz" "$URL"
rm -rf "$D/x"; mkdir -p "$D/x"
tar xzf "$D/img-gpu-powervr-bin-$VER.tar.gz" -C "$D/x"
T=$D/x/img-gpu-powervr-bin-$VER/target

P=$(mktemp -d); chmod 755 "$P"
trap 'rm -rf "$P"' EXIT
mkdir -p "$P/opt/img-gpu/lib" "$P/opt/img-gpu/icd.d" "$P/lib/firmware" "$P/DEBIAN"
for f in "$T"/usr/lib/*.so*; do
	case "$(basename "$f")" in
	libGLESv2.so*|libGLESv1_CM.so*|libvulkan.so*|libOpenCL.so*) continue ;;
	esac
	cp -a "$f" "$P/opt/img-gpu/lib/"
done
cp -a "$T"/lib/firmware/rgx.* "$P/lib/firmware/"
sed 's#"library_path": *"[^"]*"#"library_path": "/opt/img-gpu/lib/libVK_IMG.so.1"#' \
	"$T/etc/vulkan/icd.d/icdconf.json" > "$P/opt/img-gpu/icd.d/img_icd.json"
# pvrsrvkm is built into the vendor kernel and probes before the root fs is mounted: put the
# firmware into the initramfs.
install -D -m755 /dev/stdin "$P/usr/share/initramfs-tools/hooks/img-gpu-jh7110" <<'HOOK'
#!/bin/sh
[ "$1" = prereqs ] && exit 0
. /usr/share/initramfs-tools/hook-functions
copy_file firmware /lib/firmware/rgx.fw.36.50.54.182
copy_file firmware /lib/firmware/rgx.sh.36.50.54.182
HOOK
for s in postinst postrm; do
	printf '#!/bin/sh\nset -e\nif command -v update-initramfs >/dev/null; then update-initramfs -u -k all; fi\n' > "$P/DEBIAN/$s"
	chmod 755 "$P/DEBIAN/$s"
done
cat > "$P/DEBIAN/control" <<EOF
Package: img-gpu-jh7110
Version: $VER-$REV
Architecture: riscv64
Maintainer: linux-drm-jh7110 <noreply@localhost>
Section: non-free/libs
Priority: optional
Description: Imagination PowerVR DDK $VER userspace for StarFive JH7110 (closed), in /opt/img-gpu
 From starfive-tech/soft_3rdpart. Needs the vendor kernel (pvrsrvkm). Does not replace Debian's
 GLES/Vulkan/OpenCL loaders.
EOF
mkdir -p "$ROOT/debs"
fakeroot dpkg-deb --build -Zxz "$P" "$ROOT/debs/img-gpu-jh7110_${VER}-${REV}_riscv64.deb"
