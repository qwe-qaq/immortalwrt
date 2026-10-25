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

# Each device ships a signed dual-configuration FIT: the OEM bootloader keeps
# selecting conf-0/conf-1 via b_conf and the embedded script translates its
# ${root_mtd} slot selector into the UBI volume of this unit. The slot
# translation differs between boards: TYFZA1 uses 31:12/31:9 with root
# volumes ubi0_7/ubi0_4, the PT1570 (no ubi_fpga volume) uses 31:11/31:8 with
# ubi0_6/ubi0_3 - one image per board, never cross-flashed.
define Build/tianyi-tyfza1-fit
	python3 $(TOPDIR)/target/linux/rtl9617c/image/tyfza1_fit.py \
		$@ $(KDIR)/image-rtl9617c-tyfza1.dtb $@.fit \
		--dtb-2p5g $(KDIR)/image-rtl9617c-tyfza1-2p5g.dtb \
		--keys $(TYFZA1_SIGNING_KEYS) \
		--mkimage $(TYFZA1_MKIMAGE) \
		--kernel-version $(LINUX_VERSION) \
		--slot1-mtd 31:12 --slot1-block ubiblock0_7 --slot0-block ubiblock0_4
	$(CP) $@.fit/image.itb $@
endef

define Build/yhtc-pt1570-fit
	python3 $(TOPDIR)/target/linux/rtl9617c/image/tyfza1_fit.py \
		$@ $(KDIR)/image-rtl9617c-pt1570.dtb $@.fit \
		--dtb-2p5g $(KDIR)/image-rtl9617c-pt1570-2p5g.dtb \
		--keys $(TYFZA1_SIGNING_KEYS) \
		--mkimage $(TYFZA1_MKIMAGE) \
		--kernel-version $(LINUX_VERSION) \
		--slot1-mtd 31:11 --slot1-block ubiblock0_6 --slot0-block ubiblock0_3
	$(CP) $@.fit/image.itb $@
endef

define Build/tyfza1-dtb
	$(CP) $(KDIR)/image-$(1).dtb $@
endef

define Build/tyfza1-rootfs-size
	@size="$$(stat -c%s $(IMAGE_ROOTFS))"; \
	[ "$$size" -le 33648640 ] || { \
		echo "$${DEVICE_MODEL} rootfs is $$size bytes; OEM rootfs volume holds 33648640 bytes" >&2; \
		exit 1; \
	}
endef

# One image per board family; each carries both hardware variants via the OEM
# dual-configuration ABI (conf-0 = 2.5G board DT, conf-1 = four-GbE board DT)
# selected by the stock b_conf environment.
define Device/tianyi_tyfza1
  DEVICE_VENDOR := Tianyi
  DEVICE_MODEL := TYFZA1
  SUPPORTED_DEVICES += tianyi,tyfza1-2p5g
  DEVICE_DTS := rtl9617c-tyfza1 rtl9617c-tyfza1-2p5g
  DEVICE_DTS_DIR := ../dts
  IMAGE_METADATA := "tyfza1_storage": "factory-v1"
  DEVICE_PACKAGES := kmod-rtl-ax-ap tyfza1-pon-control tyfza1-storage \
	tyfza1-wifi-firmware tyfza1-pon-firmware luci-app-tyfza1-pon \
	ubi-utils nand-utils uboot-envtools iw wpad-mbedtls wifi-scripts wireless-regdb \
	kmod-gpio-button-hotplug kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \
	kmod-usb-ledtrig-usbport kmod-tyfza1-usb-led block-mount kmod-fs-vfat kmod-fs-exfat \
	kmod-fs-ntfs3 kmod-fs-ext4 kmod-nls-utf8 kmod-nls-cp437 kmod-nls-iso8859-1
  KERNEL := kernel-bin | tianyi-tyfza1-fit
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

define Device/yhtc_pt1570
  DEVICE_VENDOR := YHTC
  DEVICE_MODEL := PT1570-H10
  SUPPORTED_DEVICES += yhtc,pt1570-2p5g
  DEVICE_DTS := rtl9617c-pt1570 rtl9617c-pt1570-2p5g
  DEVICE_DTS_DIR := ../dts
  DEVICE_PACKAGES := kmod-rtl-ax-ap tyfza1-pon-control tyfza1-wifi-firmware tyfza1-pon-firmware \
	luci-app-tyfza1-pon \
	ubi-utils nand-utils uboot-envtools iw wpad-mbedtls wifi-scripts wireless-regdb \
	kmod-gpio-button-hotplug kmod-usb3 kmod-usb-storage kmod-usb-storage-uas \
	kmod-usb-ledtrig-usbport kmod-tyfza1-usb-led block-mount kmod-fs-vfat kmod-fs-exfat \
	kmod-fs-ntfs3 kmod-fs-ext4 kmod-nls-utf8 kmod-nls-cp437 kmod-nls-iso8859-1
  KERNEL := kernel-bin | yhtc-pt1570-fit
  KERNEL_INITRAMFS := kernel-bin
  KERNEL_SUFFIX := -kernel.itb
  KERNEL_INITRAMFS_SUFFIX := -initramfs-Image
  KERNEL_INSTALL := 1
  FILESYSTEMS := squashfs
  IMAGES := rootfs.squashfs sysupgrade.bin
  IMAGE/rootfs.squashfs := append-rootfs | tyfza1-rootfs-size
  IMAGE/sysupgrade.bin := tyfza1-rootfs-size | sysupgrade-tar | append-metadata
endef
TARGET_DEVICES += yhtc_pt1570

$(eval $(call BuildImage))
