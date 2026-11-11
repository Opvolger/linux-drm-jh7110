#!/bin/bash
# Usage: board-tools/rollback.sh [--yes]
#
# Puts the VisionFive 2 back on stock Debian 13: Debian kernel 6.12.74 via /boot.scr, Debian's
# Mesa (trixie-backports, as before), no project packages/config. Runs on the build machine and
# does everything over ssh. Without --yes it only prints what it would do.
#
# What it undoes (see "Rollback to stock Debian 13" in jh7110-drm-to-debian-13.md):
#   boot.scr -> Debian 6.12.74 kernel, original /boot.cmd restored
#   packages: linux-image-7.4.0-rc1-jh7110, mesa-jh7110, powervr-firmware-jh7110,
#             linux-image-6.12.5-vf2, img-gpu-jh7110, mesa-pvr-jh7110 (phase C)
#   config: /etc/sddm.conf.d/50-jh7110.conf, /etc/sysctl.d/50-jh7110-printk.conf,
#           ~/.config/plasma-workspace/env/jh7110-*.sh, ~/.config/autostart/jh7110-fastfetch.desktop
#   kwin_wayland file capability (cap_sys_nice) restored via dpkg-reconfigure kwin-wayland
# Not removed (harmless, remove by hand if wanted): the test tools (libdrm-tests drm-info kmscube
# fastfetch mesa-utils vulkan-tools libcap2-bin) and ~/games/hl2-source-togl.
set -euo pipefail
BOARD=${BOARD:-opvolger@192.168.2.33}
STOCK=6.12.74+deb13+1-riscv64
DO=${1:-}

run() {
	echo "+ $*"
	[ "$DO" = --yes ] && ssh -n "$BOARD" "$@"
	return 0
}

# 1. boot the stock kernel again (boot.cmd as it was before the project, then boot.scr for 6.12.74)
run "sudo tee /boot.cmd >/dev/null <<'EOF'
load mmc 0:1 \${kernel_addr_r} /boot/vmlinux-7.1.7+deb13-riscv64
load mmc 0:1 \${fdt_addr_r} /usr/lib/linux-image-7.1.7+deb13-riscv64/starfive/jh7110-starfive-visionfive-2-v1.3b.dtb
load mmc 0:1 \${ramdisk_addr_r} /boot/initrd.img-7.1.7+deb13-riscv64
# we will use partition 4 as rootfs
setenv bootargs 'root=/dev/mmcblk0p1 radeon.si_support=0 radeon.cik_support=0 amdgpu.si_support=1 amdgpu.cik_support=1 amdgpu.dc=0 amdgpu.aspm=0 amdgpu.runpm=0'
# and boot!
booti \$kernel_addr_r \$ramdisk_addr_r:\$filesize \$fdt_addr_r
EOF"
# the boot.scr that really was in use before the project boots 6.12.74 (backup made by set-boot.sh)
run "test -f /boot.scr.bak-$STOCK && sudo cp /boot.scr.bak-$STOCK /boot.scr && dd if=/boot.scr bs=72 skip=1 2>/dev/null | grep -a load"

# 2. user/session configuration
run "sudo rm -f /etc/sddm.conf.d/50-jh7110.conf /etc/sysctl.d/50-jh7110-printk.conf"
run "test -f ~/.config/kwinrc.bak-jh7110 && cp ~/.config/kwinrc.bak-jh7110 ~/.config/kwinrc; true"
run "rm -f ~/.config/plasma-workspace/env/jh7110-kwin.sh ~/.config/plasma-workspace/env/jh7110-mesa.sh ~/.config/autostart/jh7110-fastfetch.desktop"

# 3. packages (firmware postrm rebuilds the initramfs of all kernels without the firmware)
run "sudo apt-get purge -y mesa-jh7110 powervr-firmware-jh7110 linux-image-7.4.0-rc1-jh7110 mesa-pvr-jh7110 img-gpu-jh7110 linux-image-6.12.5-vf2"

# 4. kwin_wayland gets its cap_sys_nice back (the package postinst sets it)
run "sudo dpkg-reconfigure kwin-wayland && /usr/sbin/getcap /usr/bin/kwin_wayland"

# 5. check and reboot
run "dpkg -l | grep -E 'jh7110|mesa-vulkan-drivers|libgl1-mesa-dri' | awk '{print \$1, \$2, \$3}'"
echo "Then: ssh $BOARD sudo systemctl reboot   (expect: uname -r = $STOCK)"
[ "$DO" = --yes ] || echo "(dry run; pass --yes to execute)"
