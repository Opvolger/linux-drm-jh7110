# StarFive VisionFive 2 (JH7110): mainline kernel + display (HDMI) patches as Debian packages.
#
#   make help
#   make deb-7.4            check out v7.4-rc1, apply linux-7.4-patches/, build linux-image .deb
#
# The kernel tree is linux-V/ (git worktree of .kernel.git, branch jh7110-V, started at TAG_V),
# built out of tree in build/V/obj. The config is the Debian riscv64 config from the board
# (configs/debian/), adapted by scripts/make-config.sh.

VERSIONS ?= $(patsubst linux-%-patches,%,$(wildcard linux-*-patches))
# Tag each version starts from (default v<version>)
TAG_7.4  ?= v7.4-rc1

ARCH          := riscv
CROSS_COMPILE ?= riscv64-linux-gnu-
JOBS          ?= $(shell nproc)
DIST          ?= trixie
PKGREV        ?=
DEBDIR        ?= $(CURDIR)/debs
# linux-headers can't be cross-built (no riscv64 glibc on the host); no -dbg package
DEB_PROFILES  ?= pkg.linux-upstream.nokernelheaders pkg.linux-upstream.nokerneldbg

tag = $(or $(TAG_$(1)),v$(1))
KMAKE = $$(MAKE) --no-print-directory -C linux-$(1) O=$(CURDIR)/build/$(1)/obj \
	ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) LOCALVERSION=

.DEFAULT_GOAL := help
.PHONY: help

help:
	@echo "Versions: $(VERSIONS)"
	@echo "  make checkout-V      create linux-V/ (from TAG_V) and apply missing patches"
	@echo "  make config-V        build/V/obj/.config from configs/debian/ (scripts/make-config.sh)"
	@echo "  make deb-V           linux-image-*.deb into $(DEBDIR)"
	@echo "  make image-V         only Image + dtbs + modules (quick compile check)"
	@echo "  make menuconfig-V"
	@echo "  make export-V        write commits in linux-V/ back to linux-V-patches/"
	@echo "  make clean-V"
	@echo "Variables: PKGREV=<n>, JOBS=$(JOBS), DIST=$(DIST), DEBDIR=$(DEBDIR)"

define version_rules
.PHONY: checkout-$(1) config-$(1) deb-$(1) image-$(1) menuconfig-$(1) export-$(1) clean-$(1)

checkout-$(1):
	TAG=$(call tag,$(1)) KERNEL_DEPTH=$$$${KERNEL_DEPTH:-1} scripts/kernel-tree.sh $(1)

config-$(1): checkout-$(1)
	scripts/make-config.sh $(1)

image-$(1): config-$(1)
	$(call KMAKE,$(1)) -j$(JOBS) Image dtbs modules

deb-$(1): config-$(1)
	@mkdir -p $(DEBDIR); \
	rel=$$$$($(call KMAKE,$(1)) -s kernelrelease); \
	ver=$$$$($(call KMAKE,$(1)) -s kernelversion); \
	rev=$(PKGREV); \
	if [ -z "$$$$rev" ]; then \
		last=$$$$(ls $(DEBDIR) | sed -n "s/^linux-image-$$$${rel}_$$$${ver}-\([0-9]*\)_riscv64\.deb$$$$/\1/p" | sort -n | tail -1); \
		rev=$$$$(( $$$${last:-0} + 1 )); \
	fi; \
	echo ">> $$$$rel, package version $$$$ver-$$$$rev"; \
	rm -f build/$(1)/*.deb; \
	DEB_BUILD_PROFILES="$(DEB_PROFILES)" \
	$(call KMAKE,$(1)) -j$(JOBS) KBUILD_IMAGE=arch/riscv/boot/Image INSTALL_MOD_STRIP=1 \
		KDEB_PKGVERSION=$$$$ver-$$$$rev KDEB_CHANGELOG_DIST=$(DIST) DPKG_FLAGS=-d bindeb-pkg && \
	cp -v build/$(1)/*.deb $(DEBDIR)/

menuconfig-$(1): config-$(1)
	$(call KMAKE,$(1)) menuconfig

export-$(1):
	TAG=$(call tag,$(1)) scripts/export-patches.sh $(1)

clean-$(1):
	rm -rf build/$(1)
endef

$(foreach v,$(VERSIONS),$(eval $(call version_rules,$(v))))
