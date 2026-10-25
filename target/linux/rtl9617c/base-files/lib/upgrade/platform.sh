#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
REQUIRE_IMAGE_METADATA=1
RAMFS_COPY_BIN='fw_printenv fw_setenv fwtool jsonfilter'
RAMFS_COPY_DATA='/etc/fw_env.config'
# TYFZA1 upgrades re-seed rootfs_data from the factory-v1 overlay seed;
# the file only exists on images that ship tyfza1-storage.
[ -f /usr/share/tyfza1/overlay-seed.ubifs.gz ] && \
	RAMFS_COPY_DATA="$RAMFS_COPY_DATA /usr/share/tyfza1/overlay-seed.ubifs.gz"
CI_UBIPART=ubi_device
. /lib/upgrade/tyfza1-storage.sh

tyfza1_volume_fits() {
	local volume=$(nand_find_volume "$1" "$2")
	local path="/sys/class/ubi/$volume"
	local capacity=$(( $(cat "$path/reserved_ebs") * $(cat "$path/usable_eb_size") ))
	local limit=${4:-$capacity}
	[ "$capacity" -le "$limit" ] || capacity=$limit
	[ "$3" -le "$capacity" ] || {
		echo "$2 image is $3 bytes; volume image limit is $capacity bytes" >&2
		return 1
	}
}

tyfza1_check_sizes() {
	local slot=$(sed -n 's/.*tyfza1.slot=\([01]\).*/\1/p' /proc/cmdline)
	local ubidev=$(nand_find_ubi "$CI_UBIPART")
	case "$slot" in
		0|1) ;;
		*) echo "UBI sysupgrade requires a persistent TYFZA1 boot" >&2; return 1 ;;
	esac
	local rootvol=$(nand_find_volume "$ubidev" "ubi_r$slot")
	tyfza1_plan_storage "$ubidev" "$rootvol" "$1" &&
		tyfza1_volume_fits "$ubidev" "ubi_k$slot" "$2" 6291456
}

# A migrated TYFZA1 unit has no ubi_Config. Older images cannot import its
# calibration. Self-no-op on the PT1570 (no tyfza1_factory volumes there).
tyfza1_check_storage_format() {
	local entry name migrated=0 metadata=/tmp/tyfza1-storage-image.json
	for entry in /sys/class/ubi/ubi0_12/name /sys/class/ubi/ubi0_13/name; do
		[ -f "$entry" ] || continue
		read -r name < "$entry"
		case "$name" in tyfza1_factory|tyfza1_factory_backup) migrated=1;; esac
	done
	[ "$migrated" = 1 ] || return 0
	fwtool -q -i "$metadata" "$1" || return 1
	[ "$(jsonfilter -i "$metadata" -e '@.tyfza1_storage')" = factory-v1 ] || {
		echo 'This unit requires factory-v1 firmware; restore the OEM layout before downgrading' >&2
		return 1
	}
}

platform_check_image() {
	case "$(board_name)" in
		tianyi,tyfza1|tianyi,tyfza1-2p5g|yhtc,pt1570-h10|yhtc,pt1570-2p5g) ;;
		*) echo "Unsupported TYFZA1-family board" >&2; return 1 ;;
	esac
	case "$(board_name)" in
		# The PT1570 has no storage-migration history; the TYFZA1 factory-v1
		# metadata would needlessly fail it below.
		yhtc,pt1570*) ;;
		# A migrated TYFZA1 unit has no ubi_Config. Older images cannot import
		# its calibration.
		*) tyfza1_check_storage_format "$1" || return 1 ;;
	esac
	# Both FIT configurations share one sysupgrade archive directory.
	nand_do_platform_check tianyi,tyfza1 "$1" || return 1
	local board_dir=$(tar tf "$1" | grep -m 1 '^sysupgrade-.*/$')
	board_dir=${board_dir%/}
	local root_size=$(tar xOf "$1" "$board_dir/root" | wc -c)
	local kernel_size=$(tar xOf "$1" "$board_dir/kernel" | wc -c)
	tyfza1_check_sizes "$root_size" "$kernel_size"
}

# Keep the OEM kernel/root volume IDs required by the signed FIT boot script.
nand_upgrade_prepare_ubi() {
	[ "$2" = squashfs ] || return 1
	tyfza1_check_sizes "$1" "$3" || return 1
	local ubidev=$(nand_find_ubi "$CI_UBIPART")
	local rootvol=$(nand_find_volume "$ubidev" "$CI_ROOTPART")
	local datavol=$(nand_find_volume "$ubidev" rootfs_data)
	local seed=/tmp/tyfza1-overlay-seed.ubifs
	local reseed=0
	case "$(board_name)" in
		yhtc,pt1570*) ;;
		# TYFZA1 upgrades restore the factory-v1 rootfs_data layout from the
		# overlay seed shipped by tyfza1-storage; the PT1570 has no seed.
		*) gzip -dc /usr/share/tyfza1/overlay-seed.ubifs.gz > "$seed" || return 1
		   reseed=1 ;;
	esac
	nand_remove_ubiblock "$rootvol" || return 1
	[ -z "$datavol" ] || ubirmvol "/dev/$ubidev" -N rootfs_data || return 1
	# Clear the old image before shrinking, including on static UBI volumes.
	ubiupdatevol "/dev/$rootvol" -t || return 1
	tyfza1_resize_root "$ubidev" "$rootvol" || return 1
	tyfza1_grow_data "$ubidev" || return 1
	if [ "$reseed" = 1 ]; then
		# Match first migration's growth limit, compression and usable capacity.
		ubiupdatevol "/dev/${ubidev}_11" "$seed" || return 1
		rm -f "$seed"
	fi
}

platform_do_upgrade() {
	local slot=$(sed -n 's/.*tyfza1.slot=\([01]\).*/\1/p' /proc/cmdline)
	case "$slot" in
		0|1) ;;
		*) echo "UBI sysupgrade requires a persistent TYFZA1 boot" >&2; return 1 ;;
	esac
	CI_KERNPART="ubi_k$slot"
	CI_ROOTPART="ubi_r$slot"
	case "$(board_name)" in
		yhtc,pt1570*) tyfza1_write_slots "$1" ;;
		# The TYFZA1 flow keeps the stock nand_do_upgrade path, including the
		# tyfza1-storage migration checks.
		*) nand_do_upgrade "$1" ;;
	esac
}

# Write kernel and rootfs directly instead of going through nand_do_upgrade.
#
# ubiupdatevol() fails without a message when the payload ends exactly on a LEB
# boundary. This board's rootfs is 20,916,044 bytes into a 165-LEB volume
# (20,951,040 bytes) - only 34,996 bytes of slack - so the write silently did
# nothing and the box rebooted on the old rootfs with a wiped overlay, which
# looked exactly like "the upgrade had no effect".
#
# Padding the payload to a whole number of LEBs removes the boundary case. The
# extra bytes sit past the end of the squashfs superblock and are never read.
tyfza1_write_slots() {
	local tar="$1"
	local board_dir work kvol rvol ksize rsize pad
	local leb=126976

	board_dir=$(tar tf "$tar" | grep -m 1 '^sysupgrade-.*/$') || return 1
	board_dir=${board_dir%/}
	work=/tmp/tyfza1-upgrade
	rm -rf "$work"
	mkdir -p "$work" || return 1

	tar xOf "$tar" "$board_dir/kernel" > "$work/kernel" || return 1
	tar xOf "$tar" "$board_dir/root" > "$work/root" || return 1
	ksize=$(wc -c < "$work/kernel")
	rsize=$(wc -c < "$work/root")
	[ "$ksize" -gt 0 ] && [ "$rsize" -gt 0 ] || {
		echo "empty kernel or rootfs in $tar" >&2
		return 1
	}

	nand_upgrade_prepare_ubi "$rsize" squashfs "$ksize" "" || return 1

	kvol=$(nand_find_volume ubi0 "$CI_KERNPART") || return 1
	rvol=$(nand_find_volume ubi0 "$CI_ROOTPART") || return 1

	ubiupdatevol "/dev/$kvol" -s "$ksize" "$work/kernel" || return 1

	pad=$(( (leb - rsize % leb) % leb ))
	if [ "$pad" -gt 0 ]; then
		dd if=/dev/zero bs=1 count="$pad" >> "$work/root" 2>/dev/null || return 1
	fi
	ubiupdatevol "/dev/$rvol" "$work/root" || return 1

	rm -rf "$work"

	# nand_do_upgrade() would have called this from nand_do_upgrade_success().
	# Because tyfza1_write_slots() replaces that whole path, the call has to be
	# made here explicitly - otherwise the upgrade finishes "successfully" but
	# the new rootfs_data volume stays empty, and the box comes back with no
	# root password, no PPPoE account and default Wi-Fi settings. That is
	# exactly what happened on the first real run of this function.
	echo "tyfza1_write_slots: config backup $([ -f /tmp/sysupgrade.tgz ] && echo present || echo MISSING)"
	nand_do_restore_config || return 1

	return 0
}

# do_stage2 calls platform_copy_config() after platform_do_upgrade() whenever
# UPGRADE_BACKUP is set. The PT1570 flow bypasses nand_do_upgrade() with
# tyfza1_write_slots(), and /tmp/sysupgrade.tgz was not visible to
# nand_do_restore_config() during the two lan20 test upgrades - the config came
# back empty both times. Implementing the documented hook lets the framework
# hand us the real backup path instead of relying on a hard-coded one.
# The TYFZA1 flow keeps nand_do_upgrade(), which restores the configuration
# itself, so this hook stays a no-op there.
platform_copy_config() {
	local ubidev ubivol

	case "$(board_name)" in
		yhtc,pt1570*) ;;
		*) return 0 ;;
	esac

	[ -n "$UPGRADE_BACKUP" ] && [ -f "$UPGRADE_BACKUP" ] || {
		echo "platform_copy_config: no backup at '$UPGRADE_BACKUP'" >&2
		return 1
	}

	ubidev=$(nand_find_ubi "${CI_UBIPART:-ubi_device}") || return 1
	ubivol=$(nand_find_volume "$ubidev" rootfs_data) || return 1

	mkdir -p /tmp/new_root
	mount -t ubifs "/dev/$ubivol" /tmp/new_root || {
		echo "platform_copy_config: cannot mount $ubivol" >&2
		return 1
	}

	cp -a "$UPGRADE_BACKUP" "/tmp/new_root/$BACKUP_FILE" && sync
	umount /tmp/new_root
	echo "platform_copy_config: configuration saved to $ubivol"
	return 0
}
