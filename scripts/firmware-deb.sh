#!/bin/bash
# Usage: scripts/firmware-deb.sh
# Packages the PowerVR BXE-4-32 firmware (not in upstream linux-firmware) as
# debs/powervr-firmware-jh7110_<ver>_all.deb -> /lib/firmware/powervr/rogue_36.50.54.182_v1.fw
# Source: Imagination's linux-firmware fork, branch powervr, pinned commit below.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMMIT=8a58f81883f7be458daa34e418cc4079f995b279
FW=rogue_36.50.54.182_v1.fw
SHA=59127d3a02e48876310a520b7dc355f7430d3748d2940caaa33f39237d517abb
URL=https://gitlab.freedesktop.org/imagination/linux-firmware/-/raw/$COMMIT
VER=1.1+git8a58f818-1

D=$ROOT/firmware
mkdir -p "$D/powervr"
[ -f "$D/powervr/$FW" ] || curl -fsSL -o "$D/powervr/$FW" "$URL/powervr/$FW"
[ -f "$D/LICENSE.powervr" ] || curl -fsSL -o "$D/LICENSE.powervr" "$URL/LICENSE.powervr"
echo "$SHA  $D/powervr/$FW" | sha256sum -c -

P=$(mktemp -d)
trap 'rm -rf "$P"' EXIT
install -D -m644 "$D/powervr/$FW" "$P/lib/firmware/powervr/$FW"
install -D -m644 "$D/LICENSE.powervr" "$P/usr/share/doc/powervr-firmware-jh7110/copyright"
mkdir -p "$P/DEBIAN"
cat > "$P/DEBIAN/control" <<EOF
Package: powervr-firmware-jh7110
Version: $VER
Architecture: all
Maintainer: linux-drm-jh7110 <noreply@localhost>
Section: non-free-firmware/kernel
Priority: optional
Description: PowerVR BXE-4-32 (StarFive JH7110) GPU firmware for drm/imagination
 $FW from gitlab.freedesktop.org/imagination/linux-firmware commit $COMMIT (FW v1.1).
EOF
mkdir -p "$ROOT/debs"
fakeroot dpkg-deb --build -Zxz "$P" "$ROOT/debs/powervr-firmware-jh7110_${VER}_all.deb"
