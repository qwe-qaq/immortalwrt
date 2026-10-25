# SPDX-License-Identifier: GPL-2.0-only
#
# PON SerDes firmware for the RTL9617C reference-design gateways. One image
# per line mode; the pon driver requests the file matching its configured
# mode at SerDes bring-up. Blobs extracted from the vendor firmware and
# redistributed from this project's own firmware repository.

include $(TOPDIR)/rules.mk

PKG_NAME:=tyfza1-pon-firmware
# Dots only: apk rejects package versions containing '-' (reserved as the
# version/revision separator), so date versions must not use %Y-%m-%d.
PKG_VERSION:=2026.10.24
PKG_RELEASE:=1
PKG_LICENSE:=Proprietary

PKG_SOURCE:=tyfza1-pon-firmware-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/qwe-qaq/tyfza1-firmware/releases/download/v$(PKG_VERSION)
PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk

define Package/tyfza1-pon-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  URL:=https://github.com/qwe-qaq/tyfza1-firmware
  TITLE:=RTL9617C PON SerDes firmware
  DEPENDS:=@TARGET_rtl9617c
  PKGARCH:=all
endef

define Package/tyfza1-pon-firmware/description
  SerDes firmware for every supported PON mode (EPON, 10G-EPON variants,
  GPON, XG-PON, XGS-PON) requested by the native pon driver through
  request_firmware().
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(TAR) -xzf $(DL_DIR)/$(PKG_SOURCE) -C $(PKG_BUILD_DIR)
endef

define Build/Compile
	true
endef

define Package/tyfza1-pon-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/realtek/rtl9617c
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/lib/firmware/realtek/rtl9617c/pon_serdes_*.bin \
		$(1)/lib/firmware/realtek/rtl9617c/
endef

$(eval $(call BuildPackage,tyfza1-pon-firmware))
