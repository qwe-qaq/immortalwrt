# Realtek RTL9617C (Taurus) — Tianyi TYFZA1 / YHTC PT1570-H10

Native ImmortalWrt support for the Tianyi TYFZA1 and YHTC PT1570-H10
GPON/10G-EPON ONUs (Realtek RTL9617C, quad Cortex-A55, Linux 6.18),
integrated from the [PonWRT-TYFZA1](https://github.com/LeoooChen/PonWRT-TYFZA1)
port project (baseline: OpenWrt main `79bc56cb` / kernel 6.18.55 — the same
kernel version and hash as this tree's `kernel-6.18`). The PT1570-H10
addition follows the PT1570 work in the
[dreamtekcat fork](https://github.com/dreamtekcat/PonWRT-TYFZA1).

The port covers the PON MAC (GPON/XG-PON/EPON, OMCI/OAM), the NI/XRAM
wired path with DMA and QM forwarding, both PCIe radios (RTL8852C 5 GHz +
RTL8192XB 2.4 GHz) with dual-PE hardware offload, USB, LEDs, sysupgrade
and the storage migration off the OEM UBI layout.

## Two boards, one target

| | tianyi_tyfza1 | yhtc_pt1570 |
| --- | --- | --- |
| Boards | TYFZA1 / TYFZA1 2.5G (`tianyi,tyfza1*`) | PT1570-H10 / 2.5G (`yhtc,pt1570*`) |
| Boot slot selectors (`${root_mtd}`) | `31:12` / `31:9` | `31:11` / `31:8` |
| OEM root volume IDs | `ubi0_7` / `ubi0_4` | `ubi0_6` / `ubi0_3` (no `ubi_fpga` volume) |
| Upgrade flow | `nand_do_upgrade` + storage-migration checks | direct `tyfza1_write_slots` + `platform_copy_config` |
| Front-panel keys | lights toggle (GPIO 67/66) | reset (8), lights (103/66), wifi (99) |
| 8192XB radio tables | `RFE54` (external 2.4G FEM) | `RFE50` (no external 2.4G FEM) |
| 8852C FEM tables | `RTK66587_BPF` | `RTK66587_BPF_YH1570` |

Both devices share the `tianyi,tyfza1` driver compatible; the PT1570 adds a
leading `yhtc,pt1570-*` compatible so OpenWrt gets a distinct board name, and
the sysupgrade scripts verify the OEM UBI volume IDs before touching any
volume - a TYFZA1 image refuses to flash a PT1570 and vice versa. The radio
parameter directories are selected per board inside the driver (root-node
compatible check); the RFE50 and YH1570 tables ship under
`base-files/lib/firmware/realtek/tyfza1/`.

## What was integrated

| Piece | Location |
| --- | --- |
| New target | `target/linux/rtl9617c/` (this directory) |
| Kernel drivers (`files-6.18/`), kernel patches (`patches-6.18/`), kernel config (`config-6.18`) | unchanged from the project |
| Packages `tyfza1-pon-control`, `tyfza1-storage`, `luci-app-tyfza1-pon` | `package/` |
| firewall4 / netifd / iwinfo / hostapd package patches | `package/network/.../patches/` |
| wifi-scripts txpower failure handling | direct edits in `package/network/config/wifi-scripts/files-ucode/` |
| wireless-regdb ships the signed `regulatory.db.p7s` | direct edit in `package/firmware/wireless-regdb/Makefile` |
| host mtd-utils builds with zstd | direct edit in `tools/mtd-utils/Makefile` |
| LuCI feed patches + applier | `scripts/tyfza1/apply-luci-patches.sh` |
| Signed-FIT host mkimage builder | `scripts/tyfza1/build-fit-tools.sh` |
| Firmware seed config | `configs/tyfza1-boot.config` |
| FIT image builder | `image/tyfza1_fit.py` (self-contained; the project's version reached outside the tree) |

## DTS consolidation

The project shipped a 14-file bring-up ladder plus variants; the ladder is
now folded into one common board include. The stock dual-configuration FIT
ABI is preserved (conf-0 = 2.5G board, conf-1 = four-GbE board, selected by
the OEM `b_conf` strap), so **one sysupgrade image still serves both boards**.

Final device-tree set:

| File | Content |
| --- | --- |
| `dts/rtl9617c.dtsi` | SoC include (unchanged) |
| `dts/rtl9617c-tyfza1.dtsi` | Common board include shared by all four board files: memory map + stock reservations, UART/watchdog, QSPI NAND + stock partitions (writable), MDIO + 4 GbE PHYs, NI/XRAM/DMA/QM node, GPIO, LED block, I2C BOSA, PON MAC, PCIe controllers + SerDes tables, USB PHY + xHCI. Front-panel buttons live in the board files (they differ per board) |
| `dts/rtl9617c-tyfza1.dts` | TYFZA1 four-GbE board (`tianyi,tyfza1`), lights key on GPIO 67 |
| `dts/rtl9617c-tyfza1-2p5g.dts` | TYFZA1 2.5G board (`tianyi,tyfza1-2p5g`): LED remap, RTL8221B Clause45 PHY on port 4, lights key on GPIO 66 |
| `dts/rtl9617c-pt1570.dts` | PT1570-H10 four-GbE board (`yhtc,pt1570-h10`): reset/lights/wifi keys on GPIO 8/103/99 |
| `dts/rtl9617c-pt1570-2p5g.dts` | PT1570-H10 2.5G board (`yhtc,pt1570-2p5g`): LED remap + RTL8221B port 4, lights key on GPIO 66 |

Dropped from the original bring-up ladder (content fully contained in the
common include, or external-script-only workflows): `rtl9617c-tyfza1-mdio`,
`-xram-lan`, `-dma-tx`, `-ni`, `-pon-status`, `-nand-readonly`,
`-stock-ubi-readonly`, `-pcie`, `-pcie-2p5g`, `-ubi`, `-ubi-2p5g`, and the
now-merged `-leds.dtsi`, `-2p5g.dtsi`, `-usb.dtsi` includes. The TYFZA1
board names (`tianyi,tyfza1`, `tianyi,tyfza1-2p5g`) are unchanged, so
`board.d`, uci-defaults and the storage migration keep matching; the
PT1570 boards add their own `yhtc,pt1570-*` names with the same layout.

## Building

Requirements beyond a normal ImmortalWrt build:

1. **Signed-FIT mkimage** — the tree's host mkimage is built without
   `TOOLS_LIBCRYPTO`. Build the pinned crypto-enabled tools once:
   `sh scripts/tyfza1/build-fit-tools.sh ../tyfza1-fit-tools` (downloads and
   sha256-checks U-Boot 2026.07), then build with
   `make TYFZA1_MKIMAGE=$PWD/../tyfza1-fit-tools/bin/mkimage`.
2. **RSA2048 build keys** — generate a key directory:
   `mkdir -p keys/tyfza1-build-keys && cd keys/tyfza1-build-keys &&
   openssl genrsa -out dev.key 2048 &&
   openssl req -new -x509 -key dev.key -out dev.crt -days 3650 -subj /CN=tyfza1`
   (or point `TYFZA1_SIGNING_KEYS=` elsewhere). Note: a self-made key only
   signs a *new* U-Boot chain of trust; the stock bootloader's own key DTB
   governs what it accepts — see the PonWRT-TYFZA1 U-Boot project.
3. **Radio/PON runtime firmware** — the drivers `request_firmware()` the OEM
   radio firmware, calibration and PON runtime blobs from
   `/lib/firmware/realtek/tyfza1/…`. These are extracted from a stock unit
   and are **not** distributable in this tree. Place them under `files/`
   (the upstream project's `prepare_wifi_runtime.py` /
   `prepare_pon_runtime.py` flow, or `TYFZA1_RUNTIME_INPUTS`) before
   `make world`, otherwise Wi-Fi/PON will not come up on the device.

Steps:

```sh
./scripts/feeds update -a && ./scripts/feeds install -a
sh scripts/tyfza1/apply-luci-patches.sh        # after luci feed install
cp configs/tyfza1-boot.config .config && make defconfig
make TYFZA1_MKIMAGE=$PWD/../tyfza1-fit-tools/bin/mkimage -j$(nproc)
```

Output: `bin/targets/rtl9617c/generic/*-tianyi_tyfza1-sysupgrade.bin`
(kernel FIT + squashfs rootfs, works for both board variants).

## Layout notes

- Rootfs is capped at 33648640 bytes (OEM rootfs volume size); the image
  build fails if exceeded. Kernel FIT is capped at 0x600000.
- `files-6.18/drivers/net/wireless/realtek/rtl_ax_ap/pe-tx-code.h` is a
  committed pre-generated PE firmware header; regenerate it with the
  upstream project's `scripts/build_pe_radio_wd.sh` when the PE firmware
  changes.
- Hardware validation status and limits are documented in the upstream
  project's `port/BOARD_VARIANTS.md`; treat cold boot, lamp behaviour and
  2.5G forwarding as pending hardware acceptance.
