# Cross-build environment for Mesa (riscv64, Debian 13 trixie) on an x86_64 host.
# Native (x86_64) packages: compiler, meson, LLVM/clang/libclc for the host tool mesa_clc.
# riscv64 packages (:riscv64): the libraries Mesa links against on the board.
FROM debian:trixie
ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture riscv64 && apt-get update && apt-get install -y --no-install-recommends \
	build-essential crossbuild-essential-riscv64 pkg-config meson ninja-build cmake \
	python3-mako python3-yaml python3-packaging python3-ply python3-pycparser \
	bison flex glslang-tools spirv-tools ca-certificates xz-utils file dpkg-dev fakeroot \
	llvm-19-dev libclang-19-dev clang-19 libclc-19-dev libclc-19 libllvmspirvlib-19-dev \
	libspirv-cross-c-shared-dev libspirv-cross-c-shared0 spirv-headers \
	libexpat1-dev zlib1g-dev libzstd-dev libdrm-dev libelf-dev \
	libwayland-bin wayland-protocols \
	libdrm-dev:riscv64 libexpat1-dev:riscv64 zlib1g-dev:riscv64 libzstd-dev:riscv64 \
	libudev-dev:riscv64 libelf-dev:riscv64 \
	libwayland-dev:riscv64 libwayland-egl-backend-dev:riscv64 \
	libx11-dev:riscv64 libxext-dev:riscv64 libxfixes-dev:riscv64 libxcb-glx0-dev:riscv64 \
	libxcb-shm0-dev:riscv64 libxcb-dri3-dev:riscv64 libxcb-present-dev:riscv64 \
	libxcb-sync-dev:riscv64 libxcb-xfixes0-dev:riscv64 libxcb-randr0-dev:riscv64 \
	libxcb-keysyms1-dev:riscv64 libx11-xcb-dev:riscv64 libxshmfence-dev:riscv64 \
	libxxf86vm-dev:riscv64 libxrandr-dev:riscv64 libxdamage-dev:riscv64 \
	libglvnd-dev:riscv64 \
	&& rm -rf /var/lib/apt/lists/*
# wayland-protocols 1.49 (Mesa subproject) needs wayland-scanner >= 1.24 (trixie has 1.23)
RUN apt-get update && apt-get install -y --no-install-recommends libxml2-dev git curl && \
	curl -fsSL https://gitlab.freedesktop.org/wayland/wayland/-/releases/1.24.0/downloads/wayland-1.24.0.tar.xz | tar xJ -C /tmp && \
	meson setup /tmp/wl /tmp/wayland-1.24.0 --prefix=/usr/local -Dlibraries=false -Ddocumentation=false -Dtests=false -Ddtd_validation=true && \
	ninja -C /tmp/wl install && rm -rf /tmp/wl /tmp/wayland-1.24.0 /var/lib/apt/lists/* && wayland-scanner --version
# meson's wayland module wants the scanner version == the target libwayland (1.23.1), but the
# 1.23 scanner rejects the new "frozen" attribute: wrap 1.24 and report 1.23.1.
RUN mv /usr/local/bin/wayland-scanner /usr/local/bin/wayland-scanner-1.24 && \
	printf '#!/bin/sh\nif [ "$1" = --version ]; then echo "wayland-scanner 1.23.1" >&2; exit 0; fi\na=""; for x in "$@"; do [ "$x" = --strict ] || a="$a \"$x\""; done; eval exec /usr/local/bin/wayland-scanner-1.24 $a\n' > /usr/local/bin/wayland-scanner && \
	chmod +x /usr/local/bin/wayland-scanner && wayland-scanner --version
