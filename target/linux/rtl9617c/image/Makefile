# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/image.mk

# RSA2048 build keys (dev.key / dev.crt) for the signed UBI FIT. Override
# TYFZA1_SIGNING_KEYS to point at your key directory.
# The stock mkimage built by the build system has TOOLS_LIBCRYPTO disabled;
# build a crypto-enabled host mkimage once with
# scripts/tyfza1/build-fit-tools.sh and pass it via TYFZA1_MKIMAGE (or put it
# on PATH).
TYFZA1_SIGNING_KEYS ?= $(TOPDIR)/keys/tyfza1-build-keys
TYFZA1_MKIMAGE ?= mkimage

define Build/tyfza1-ubi-fit
	python3 $(TOPDIR)/target/linux/rtl9617c/image/tyfza1_fit.py \
		$@ $(KDIR)/image-rtl9617c-tyfza1.dtb $@.fit \
		--dtb-2p5g $(KDIR)/image-rtl9617c-tyfza1-2p5g.dtb \
		--keys $(TYFZA1_SIGNING_KEYS) \
		--mkimage $(TYFZA1_MKIMAGE) \
		--kernel-version $(LINUX_VERSION)
	$(CP) $@.fit/image.itb $@
endef

define Build/tyfza1-rootfs-size
	@size="$$(stat -c%s $(IMAGE_ROOTFS))"; \
	[ "$$size" -le 33648640 ] || { \
		echo "TYFZA1 rootfs is $$size bytes; OEM rootfs volume holds 33648640 bytes" >&2; \
		exit 1; \
	}
endef

# One image carries both hardware variants: the FIT keeps the OEM dual
# configuration ABI (conf-0 = 2.5G board DT, conf-1 = four-GbE board DT) and
# the OEM b1/b2 boot script selects the matching configuration, so a single
# sysupgrade image serves both board names.
define Device/tianyi_tyfza1
  DEVICE_VENDOR := Tianyi
  DEVICE_MODEL := TYFZA1
  SUPPORTED_DEVICES += tianyi,tyfza1-2p5g
  DEVICE_DTS := rtl9617c-tyfza1 rtl9617c-tyfza1-2p5g
  DEVICE_DTS_DIR := ../dts
  IMAGE_METADATA := "tyfza1_storage": "factory-v1"
  DEVICE_PACKAGES := kmod-rtl-ax-ap tyfza1-pon-control tyfza1-storage luci-app-tyfza1-pon \
	ubi-utils nand-utils uboot-envtools iw wpad-mbedtls wifi-scripts wireless-regdb \
	kmod-gpio-button-hotplug kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \
	kmod-usb-ledtrig-usbport kmod-tyfza1-usb-led block-mount kmod-fs-vfat kmod-fs-exfat \
	kmod-fs-ntfs3 kmod-fs-ext4 kmod-nls-utf8 kmod-nls-cp437 kmod-nls-iso8859-1
  KERNEL := kernel-bin | tyfza1-ubi-fit
  KERNEL_INITRAMFS := kernel-bin
  KERNEL_SUFFIX := -kernel.itb
  KERNEL_INITRAMFS_SUFFIX := -initramfs-Image
  KERNEL_INSTALL := 1
  FILESYSTEMS := squashfs
  IMAGES := rootfs.squashfs sysupgrade.bin
  IMAGE/rootfs.squashfs := append-rootfs | tyfza1-rootfs-size
  IMAGE/sysupgrade.bin := tyfza1-rootfs-size | sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += tianyi_tyfza1

$(eval $(call BuildImage))
