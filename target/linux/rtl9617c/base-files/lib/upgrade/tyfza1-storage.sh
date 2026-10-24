#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only

tyfza1_find_volume() {
	local path
	for path in /sys/class/ubi/"$1"_*/name; do
		[ -f "$path" ] || continue
		[ "$(cat "$path")" = "$2" ] || continue
		path=${path%/name}
		echo "${path##*/}"
		return 0
	done
	return 1
}

# Only the selected OpenWrt root and rootfs_data participate in allocation.
# Keep every OEM volume, including the other boot slot, at its original size.
tyfza1_plan_storage() {
	local ubidev="$1" rootvol="$2" size="$3"
	local path="/sys/class/ubi/$rootvol" data free root_ebs data_ebs=0
	local leb=$(cat "$path/usable_eb_size")
	# The OEM root volume IDs differ per board: the PT1570 has no ubi_fpga
	# volume (the last one is ubi_dpi), so its IDs sit one lower than on the
	# TYFZA1 - ubi0_3/ubi0_6 versus ubi0_4/ubi0_7.
	#
	# The check is deliberately strict. Both boards carry the same
	# compatible string (tianyi,tyfza1), so nand_do_platform_check() cannot
	# tell them apart - the UBI volume IDs are the only reliable
	# discriminator left. Accepting the wrong pair here would let one
	# board's image be written onto the other and land on foreign volumes.
	local root_ids
	case "$(board_name)" in
		yhtc,pt1570*) root_ids="ubi_r0:${ubidev}_3|ubi_r1:${ubidev}_6" ;;
		*) root_ids="ubi_r0:${ubidev}_4|ubi_r1:${ubidev}_7" ;;
	esac
	case "$(cat "$path/name"):$rootvol" in
		$root_ids) ;;
		*) echo "Unexpected root volume: $rootvol for board $(board_name)" >&2
		   return 1 ;;
	esac
	[ "$size" -gt 0 ] && [ "$size" -le 33648640 ] || {
		echo "Root image must fit the 33648640-byte OEM slot limit" >&2
		return 1
	}
	free=$(cat "/sys/class/ubi/$ubidev/avail_eraseblocks")
	root_ebs=$(cat "$path/reserved_ebs")
	data=$(tyfza1_find_volume "$ubidev" rootfs_data) || data=
	if [ -n "$data" ]; then
		[ "$data" = "${ubidev}_11" ] || return 1
		data_ebs=$(cat "/sys/class/ubi/$data/reserved_ebs")
	else
		# Never overwrite a differently named volume occupying ID 11.
		[ ! -e "/sys/class/ubi/${ubidev}_11" ] || return 1
	fi
	TYFZA1_ROOT_BYTES=$(( (size + leb - 1) / leb * leb ))
	TYFZA1_DATA_BYTES=$(( (free + root_ebs + data_ebs) * leb - TYFZA1_ROOT_BYTES ))
	[ "$TYFZA1_DATA_BYTES" -ge 16777216 ] || {
		echo "Insufficient UBI space for rootfs and writable data" >&2
		return 1
	}
}

tyfza1_resize_root() {
	local ubidev="$1" rootvol="$2"
	ubirsvol "/dev/$ubidev" -N "$(cat "/sys/class/ubi/$rootvol/name")" \
		-s "$TYFZA1_ROOT_BYTES"
}

tyfza1_grow_data() {
	local ubidev="$1" data current
	data=$(tyfza1_find_volume "$ubidev" rootfs_data) || data=
	if [ -n "$data" ]; then
		current=$(( $(cat "/sys/class/ubi/$data/reserved_ebs") * $(cat "/sys/class/ubi/$data/usable_eb_size") ))
		[ "$current" -le "$TYFZA1_DATA_BYTES" ] || {
			echo "Existing writable data cannot be shrunk; upgrade from OpenWrt" >&2
			return 1
		}
		[ "$current" -eq "$TYFZA1_DATA_BYTES" ] || \
			ubirsvol "/dev/$ubidev" -N rootfs_data -s "$TYFZA1_DATA_BYTES"
	else
		ubimkvol "/dev/$ubidev" -n 11 -N rootfs_data -m
	fi
}
