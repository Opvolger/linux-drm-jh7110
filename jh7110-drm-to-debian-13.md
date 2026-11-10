# JH7110 (VisionFive 2): accelerated HDMI on Debian 13

> **For a new Claude Code session:** read this whole file first. Check **Current status** and
> the **Progress log** (newest entry at the bottom). Continue from the first open item in the
> **Plan**. Update this file *while working* (after each step that succeeds or fails), not only
> at the end, so a session that hangs or dies loses no progress.

## Goal

1. HDMI output with GPU acceleration on the StarFive VisionFive 2 (JH7110), running Debian 13
   (trixie).
2. Half-Life 2 (one of the builds in `~/games` on the board) starts and runs on it.
3. A tested **rollback how-to**: return the board to the stock Debian 13 kernel/Mesa packages.

## Rules / working method

- Same setup as `~/code/linux-kernel-jupiter-1`: a mainline kernel plus a patch series, a
  Makefile that checks out, patches and builds `.deb` packages, with the patches kept in this
  project.
- Build on this machine (Fedora x86_64) by **cross-compiling**. If tools are missing, use a
  Docker image with a cross toolchain. **No native builds under QEMU emulation** (far too slow).
- You may install tools on the board for testing HDMI/DRM (`drm_info`, `modetest`, `kmscube`,
  `vulkaninfo`, `glmark2`, etc.).
- Every package we replace must have a documented way back to the Debian package (see
  **Rollback**).
- Keep the stock Debian kernel installed and bootable at all times (GRUB fallback entry).

## Current status

| Part | Status | Notes |
| --- | --- | --- |
| Board reachable (SSH/serial/power) | ✅ | Debian 13.7, running Debian kernel `6.12.74+deb13+1` |
| Kernel 7.3 + patches | ⏳ not started | display series v7 found (based on 7.4-rc1), see *Kernel* |
| Display (DC8200 + HDMI) via DRM/KMS | ⏳ | `/dev/dri` does not exist yet on 6.12 |
| GPU (IMG BXE-4-32, `drm/imagination`) | ⏳ | |
| Mesa (PowerVR Vulkan + Zink) | ⏳ | backports Mesa `25.2.6-1~bpo13+1` already installed |
| Half-Life 2 | ⏳ | |
| Rollback how-to tested | ⏳ | |

## Plan

1. [ ] Set up the project: git repo, `Makefile`, `scripts/`, `linux-7.3-patches/` (copy the
       structure of `~/code/linux-kernel-jupiter-1`).
2. [ ] Kernel 7.3 (mainline) + patches for the display controller, HDMI and GPU; cross-build
       `.deb`s (a modules + initramfs flavor based on the Debian config).
3. [ ] Install next to the Debian kernel, boot it, check: `/dev/dri/card*`, `modetest`, a console
       on HDMI (watch via the UGREEN capture).
4. [ ] GPU: `drm/imagination` loads and its firmware is found (`/lib/firmware/powervr/`).
5. [ ] Mesa: check whether trixie-backports is enough (PowerVR Vulkan driver for BXE-4-32,
       Zink for OpenGL). If not, cross-build Mesa `.deb`s.
6. [ ] Test: `vulkaninfo`, `kmscube`/`vkcube`, `glmark2`; then a desktop/compositor if needed.
7. [ ] Start Half-Life 2.
8. [ ] Write and **test** the rollback how-to.

## Board facts (found during sessions)

- Model: `StarFive VisionFive 2 v1.3B`, DTB `/boot/jh7110-starfive-visionfive-2-v1.3b.dtb`.
- Boot: U-Boot → EFI (`/boot/efi` on `mmcblk1p4`, SPI/SD) → GRUB → kernel on `mmcblk0p1` (eMMC).
- Kernels already in `/boot`: Debian `6.12.x`, `6.17.13`, `7.0.10+deb13`, `7.1.7+deb13`
  (installed earlier; their origin is not documented yet).
- Root filesystem: 54G, **94% full (~3.5G free)**. Watch this when installing kernels/Mesa.
- Mesa: `mesa-vulkan-drivers` / `libgl1-mesa-dri` `25.2.6-1~bpo13+1` from trixie-backports
  (trixie itself has `25.0.7-2+deb13u1`).
- `~/games` on the board: only `hl2-source`. More builds are on the build machine in
  `~/games` (`hl2-dxvk`, `hl2-wayland-pr`, ...); copy one over if needed. Port notes:
  `/home/opvolger/code/source-engine/port-to-riscv.md`.
- KDE Plasma is already installed (HL2 ran before on an AMD GPU in this board).
- The Debian `7.0.10` and `7.1.7` kernels (backports) may be removed to free space.

## Software

### Kernel

Base: mainline **7.3** (stable). The patches should apply to 7.3 with small changes.

Display patches (provided by the user): **"[PATCH v7 00/19] drm: starfive: jh7110: Enable display
subsystem"** by Michal Wilczynski, 2026-11-06.

- Thread: https://kernelthread.org/t/CGME20261106135849eucas1p242718d72fa1f38e31477210fd9ee30bc@eucas1p2.samsung.com
- lore: https://lore.kernel.org/all/20261106-jh7110-clean-send-v7-0-68f7ea9913db@samsung.com/
- **Based on v7.4-rc1**, not 7.3. Dependencies:
  - PHY series "phy: Add the StarFive JH7110 Innosilicon HDMI PHY" v7:
    https://lore.kernel.org/all/20261106-jh7110-inno-hdmi-phy-v7-0-d49368303800@samsung.com/
  - clk patch `af384d6e0573` (merged in v7.4-rc1): backport this to 7.3.
- Contents: inno-hdmi bridge refactor + fixes, DT bindings, `soc: starfive` hdmi/vout subsystem
  drivers, JH7110 HDMI bridge driver, DTS update.
- External test write-up: https://big-grey.co.uk/2026/01/26/testing-starfive-jh7110-display-controller-patches/

What 7.3 already has (checked in `~/code/linux-kernel-jupiter-1/linux-7.3-vanilla`): the
Verisilicon DC driver (`drivers/gpu/drm/verisilicon/`) and `drivers/gpu/drm/bridge/inno-hdmi.c`.

**GPU (BXE-4-32): not in mainline.** 7.3 has no `gpu@` node in `jh7110.dtsi` and no JH7110 or BXE
compatible in `drm/imagination`. The kernel docs list BXE-4-32 as unsupported, and Mesa's
`imagination` Vulkan driver does not support it either (as of 2026-11; to be verified). This
display series gives **KMS/HDMI only, no 3D acceleration**.

### Mesa

First try Debian 13 backports (already installed: 25.2.6). Only build Mesa ourselves if
backports lacks support for the JH7110 GPU.

### Other software

Anything else that is needed (firmware, DTB, tools) gets the same patch-and-package setup.

## Controlling the hardware

### Power on/off

Home Assistant; the token is in `/home/opvolger/home-assistant.txt` (do not copy it into this
file or into git).

```bash
TOKEN=$(cat /home/opvolger/home-assistant.txt)
URL=http://192.168.2.202:8123/api/services/switch
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"entity_id":"switch.zolder_sonoff_plug_1"}' $URL/turn_on     # or turn_off / toggle
```

### SSH

`ssh opvolger@192.168.2.33`: no password, passwordless `sudo`. You may install kernels, Mesa and
other packages yourself as needed for the goal.

### Serial console (U-Boot and Linux console)

`/dev/ttyUSB0`, 115200 baud. U-Boot commands can be entered here.

### TFTP (network boot from U-Boot)

A TFTP server runs in Docker on this machine (container `tftp`). If it has crashed, you may
restart it:

```bash
docker run -d --name tftp --network host -v $(pwd):/var/tftpboot pghalliday/tftp
```

Useful when a kernel hangs completely: boot a test kernel over the network from U-Boot without
touching the eMMC.

### Helper scripts (`board-tools/`, copied from the jupiter project)

- `board-tools/power.sh on|off|toggle|state`: shut down cleanly first (`ssh ... sudo poweroff`).
- `python3 -I board-tools/catch.py ' ' 60`: run it right after a reboot; it spams keys and stops
  U-Boot autoboot (prompt `StarFive #`).
- `python3 -I board-tools/ser.py <secs> 'cmd1' 'cmd2'`: send commands, e.g. `'boot'`.
- `board-tools/screenshot.sh shots/x.png`: grab an HDMI frame.

Verified 2026-11-10: power state ✅, HDMI capture ✅ (`/dev/video2`, UGREEN), reboot + U-Boot
interrupt ✅ (U-Boot 2025.07-rc3, `bootcmd=bootflow scan`), `dhcp` in U-Boot ✅, `boot` back to
Linux ✅. TFTP ✅ after the user ran `sudo firewall-cmd --add-service=tftp`. This is **deliberately not
permanent** (the user opens it per session for safety on other networks). If TFTP times out at
`Loading:`, ask the user to run that command again. Do not suggest `--permanent`. Build machine
IP: `192.168.2.34`. In U-Boot: `dhcp` sets `serverip` to the router (.254), so run
`setenv serverip 192.168.2.34` **after** `dhcp`; send U-Boot commands one per `ser.py` call
(they get garbled when sent while `dhcp` is still running). Example load: `tftpboot 0x44000000 <file>`.

**Power cycle:** a powerstation sits behind the plug and buffers power. After `poweroff`, **5 s off
is not enough** (the board stays dead). **60 s off works.** Do: `ssh ... sudo poweroff`, wait about
20 s, `power.sh off`, wait 60 s, `power.sh on`. Don't `pkill -f` with a pattern that matches your
own shell command.

### Watching the HDMI output (UGREEN capture)

An HDMI capture device is connected to this machine (`/dev/video*`; which node is still to be
`/dev/video2` "UGREEN HDMI Capture"; the script looks it up by name). Grab a frame to see what the board shows on HDMI.

## Rollback to stock Debian 13

*(to be written and tested in step 8)*. Expected outline:

1. Boot the Debian kernel; `apt purge` our kernel packages; `update-grub`.
2. Mesa: `apt install --allow-downgrades` the Debian versions (or the backports version) of
   the Mesa packages we replaced; remove any apt pinning we added.
3. Remove our extra firmware/DTB files.

## Open questions

(none open)

## Decisions (user, 2026-11-10)

1. Kernel base: **7.4-rc1** is fine (instead of 7.3).
2. Phase A: KDE Plasma on HDMI with display-only (llvmpipe). Take screenshots with a terminal
   running `fastfetch` for the documentation.
3. Phase B: look for out-of-tree BXE-4-32 GPU work (Linux, maybe also FreeBSD/Haiku, etc.) and
   try it. **Do not start HL2 in this phase.**
4. Phase C: if B really does not work, use the StarFive vendor kernel 6.6 + their Mesa/GPU
   packages to get HL2 running (still with a rollback how-to).
5. The user leaves the machine; work autonomously.


## Progress log

Newest entry at the bottom. Per entry: date, what was tried, result (✅/❌), where logs are.

- **2026-11-10**: Document restructured and translated to English. Board inventory taken (see
  *Board facts*). Nothing built yet.
- **2026-11-10**: git repo created. Display patch series identified (v7, base 7.4-rc1, needs
  PHY series + clk backport). Found that the BXE-4-32 GPU has no mainline kernel/Mesa support.
