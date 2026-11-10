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
| Kernel 7.3 + patches | ⏳ not started | patch list still needed (see Open questions) |
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
- `~/games` on the board: `hl2-dxvk`, `hl2-dxvk-pr`, `hl2-libjpeg-pr`, `hl2-riscv-pr-x86`,
  `hl2-source`, `hl2-wayland-pr`.

## Software

### Kernel

Base: mainline **7.3** (stable). The patches should apply to 7.3 with small changes.

Patches: *(list still to be provided; see Open questions)*

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

### Watching the HDMI output (UGREEN capture)

An HDMI capture device is connected to this machine (`/dev/video*`; which node is still to be
determined). Grab a frame to see what the board shows on HDMI.

## Rollback to stock Debian 13

*(to be written and tested in step 8)*. Expected outline:

1. Boot the Debian kernel; `apt purge` our kernel packages; `update-grub`.
2. Mesa: `apt install --allow-downgrades` the Debian versions (or the backports version) of
   the Mesa packages we replaced; remove any apt pinning we added.
3. Remove our extra firmware/DTB files.

## Open questions

- Which patches (the list under *Kernel* is empty).
- Which HL2 build in `~/games` is the target.
- Desktop or no desktop (X11/Wayland, which DE/compositor), or HL2 directly on KMS/DRM.

## Progress log

Newest entry at the bottom. Per entry: date, what was tried, result (✅/❌), where logs are.

- **2026-11-10**: Document restructured and translated to English. Board inventory taken (see
  *Board facts*). Nothing built yet.
