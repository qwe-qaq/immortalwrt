# SPDX-License-Identifier: GPL-2.0-only
#
# Radio firmware and parameter tables for the RTL9617C reference-design
# gateways (TYFZA1 / PT1570-H10). The blobs are extracted from the vendor
# firmware and are redistributed from this project's own firmware repository;
# per-device calibration (bosa-calibration.bin, flash-calibration.bin) is
# intentionally excluded - it is read from the device flash at runtime.
#
# The source archive is produced by bundling the lib/firmware/realtek tree of
# the PonWRT-TYFZA1 runtime inputs (radio firmware + parameter tables), see
# scripts/tyfza1 for the CI wiring.

include $(TOPDIR)/rules.mk

PKG_NAME:=tyfza1-wifi-firmware
# Dots only: apk rejects package versions containing '-' (reserved as the
# version/revision separator), so date versions must not use %Y-%m-%d.
PKG_VERSION:=2026.10.24
PKG_RELEASE:=1
PKG_LICENSE:=Proprietary

PKG_SOURCE:=tyfza1-wifi-firmware-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/qwe-qaq/tyfza1-firmware/releases/download/v$(PKG_VERSION)
PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/tyfza1-wifi-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  URL:=https://github.com/qwe-qaq/tyfza1-firmware
  TITLE:=RTL8852C/8192XB radio firmware and RFE tables
  DEPENDS:=@TARGET_rtl9617c
  PKGARCH:=all
endef

define Package/tyfza1-wifi-firmware/description
  Vendor radio firmware, TSSI tables and the RFE54 (TYFZA1) / RFE50 +
  RTK66587_BPF_YH1570 (PT1570-H10) parameter sets for the RTL8852C 5 GHz
  and RTL8192XB 2.4 GHz radios. Extracted from the vendor firmware; not
  redistributable under a free licence.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)
endef

define Build/Compile
	true
endef

define Package/tyfza1-wifi-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/realtek/tyfza1
	$(CP) $(PKG_BUILD_DIR)/lib/firmware/realtek/tyfza1/. \
		$(1)/lib/firmware/realtek/tyfza1/
endef

$(eval $(call BuildPackage,tyfza1-wifi-firmware))
