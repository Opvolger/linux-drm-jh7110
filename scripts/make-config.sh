#!/bin/bash
# Usage: scripts/make-config.sh <version> [debian-config]
#
# Writes build/<version>/obj/.config: the Debian riscv64 kernel config from the board
# (default: newest configs/debian/config-*) adapted to the VisionFive 2:
#   - other RISC-V SoC families off (only StarFive + generic VIRT stay);
#   - no debug info (smaller modules: the board's root fs is nearly full, faster build);
#   - own release name, module signing with a key generated at build time;
#   - PowerVR GPU + XPbmtUC errata (see below);
#   - JH7110 display stack (Verisilicon DC8200, Innosilicon HDMI bridge + PHY,
#     vout/hdmi subsystem drivers) as modules;
#   - options new since the Debian config get their default (olddefconfig).
set -euo pipefail

V=${1:?usage: $0 <version> [debian-config]}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEBCFG=${2:-$(ls "$ROOT"/configs/debian/config-* | sort -V | tail -1)}
TREE=$ROOT/linux-$V
B=$ROOT/build/$V/obj
KMAKE=(make -s -C "$TREE" O="$B" ARCH=riscv CROSS_COMPILE="${CROSS_COMPILE:-riscv64-linux-gnu-}" LOCALVERSION=)

OTHER_SOCS="ARCH_ANDES ARCH_ANLOGIC ARCH_CANAAN ARCH_ESWIN ARCH_MICROCHIP
	ARCH_MICROCHIP_POLARFIRE ARCH_RENESAS ARCH_SIFIVE ARCH_SOPHGO ARCH_SPACEMIT
	ARCH_SUNXI ARCH_TENSTORRENT ARCH_THEAD ARCH_ULTRARISC"

[ -e "$TREE/.git" ] || { echo "no kernel tree $TREE (make checkout-$V)" >&2; exit 1; }
mkdir -p "$B"
if [ -f "$B/.config" ] && [ "$B/.config" -nt "$DEBCFG" ] && [ "$B/.config" -nt "$0" ]; then
	"${KMAKE[@]}" olddefconfig
	exit 0
fi
echo ">> config from $(basename "$DEBCFG")"
cp "$DEBCFG" "$B/.config"

cfg() { "$TREE/scripts/config" --file "$B/.config" "$@"; }
for s in $OTHER_SOCS; do cfg -d "$s"; done
cfg -e ARCH_STARFIVE -e SOC_STARFIVE -e ARCH_VIRT \
	--set-str LOCALVERSION "-jh7110" -d LOCALVERSION_AUTO \
	-e MODULE_SIG -e MODULE_SIG_ALL --set-str MODULE_SIG_KEY "certs/signing_key.pem" \
	--set-str SYSTEM_TRUSTED_KEYS "" --set-str SYSTEM_REVOCATION_KEYS "" \
	-d DEBUG_INFO -d DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT -d DEBUG_INFO_DWARF5 \
	-d DEBUG_INFO_BTF -e DEBUG_INFO_NONE \
	-d GCC_PLUGINS
# Display stack
cfg -m DRM -m DRM_VERISILICON_DC -m DRM_INNO_HDMI \
	-m DRM_STARFIVE_JH7110_INNO_HDMI -m PHY_STARFIVE_JH7110_INNO_HDMI \
	-m SOC_STARFIVE_JH7110_HDMI_SUBSYSTEM -m SOC_STARFIVE_JH7110_VOUT_SUBSYSTEM \
	-e DRM_FBDEV_EMULATION -e FRAMEBUFFER_CONSOLE \
	-m SND_DESIGNWARE_I2S -m SND_SIMPLE_CARD
# GPU (PowerVR BXE-4-32, out-of-tree bring-up by domibel): uncached mappings through the
# XPbmtUC "errata" (Svpbmt emulation via the uncached memory alias of the JH7110).
# STARFIVE_STARLINK_CACHE is only there to pull in RISCV_NONSTANDARD_CACHE_OPS.
cfg -m DRM_POWERVR -e ERRATA_SIFIVE -e ERRATA_SIFIVE_XPBMTUC \
	-e STARFIVE_STARLINK_CACHE -e RISCV_NONSTANDARD_CACHE_OPS

"${KMAKE[@]}" olddefconfig

# Report what the display options ended up as
grep -E "CONFIG_(DRM_VERISILICON|DRM_INNO|DRM_STARFIVE|PHY_STARFIVE|PHY_INNO|SOC_STARFIVE|ARCH_STARFIVE|DEBUG_INFO_NONE|DRM_POWERVR|ERRATA_SIFIVE|STARFIVE_STARLINK|RISCV_NONSTANDARD_CACHE)" "$B/.config" || true
