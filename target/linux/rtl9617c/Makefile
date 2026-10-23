# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

ARCH:=aarch64
BOARD:=rtl9617c
BOARDNAME:=Realtek RTL9617C (Taurus)
# The SoC has Cortex-A55 cores, but code is built for the a53-compatible
# armv8-a baseline: -mcpu=cortex-a55 trips GCC's always_inline memset/
# memcpy target-option checks in the musl headers (mbedtls et al), and the
# aarch64_cortex-a53 userspace feed is what this target ships against.
CPU_TYPE:=cortex-a53
SUBTARGETS:=generic
FEATURES:=fpu nand ramdisk squashfs targz usb
DEPENDS:=+@DRIVER_11AC_SUPPORT +@DRIVER_11AX_SUPPORT
KERNEL_PATCHVER:=6.18
KERNELNAME:=Image
DEVICE_TYPE:=router

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += ubi-utils nand-utils ucode-mod-uci

define Target/Description
  Native RTL9617C support. TYFZA1 serial bring-up; hardware validation pending.
endef

$(eval $(call BuildTarget))
