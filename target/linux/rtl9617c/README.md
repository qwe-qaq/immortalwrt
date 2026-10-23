# Realtek RTL9617C (Taurus) — Tianyi TYFZA1

Native ImmortalWrt support for the Tianyi TYFZA1 GPON/10G-EPON ONU
(Realtek RTL9617C, quad Cortex-A55, Linux 6.18), integrated from the
[PonWRT-TYFZA1](https://github.com/LeoooChen/PonWRT-TYFZA1) port project
(baseline: OpenWrt main `79bc56cb` / kernel 6.18.55 — the same kernel
version and hash as this tree's `kernel-6.18`).

The port covers the PON MAC (GPON/XG-PON/EPON, OMCI/OAM), the NI/XRAM
wired path with DMA and QM forwarding, both PCIe radios (RTL8852C 5 GHz +
RTL8192XB 2.4 GHz) with dual-PE hardware offload, USB, LEDs, sysupgrade
and the storage migration off the OEM UBI layout.

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
| `dts/rtl9617c-tyfza1.dtsi` | Common board: memory map + stock reservations, UART/watchdog, QSPI NAND + stock partitions (writable), MDIO + 4 GbE PHYs, NI/XRAM/DMA/QM node, GPIO, LEDs + light-switch button (four-GbE wiring), I2C BOSA, PON MAC, PCIe controllers + SerDes tables, USB PHY + xHCI |
| `dts/rtl9617c-tyfza1.dts` | Four-GbE board (`tianyi,tyfza1`) |
| `dts/rtl9617c-tyfza1-2p5g.dts` | 2.5G board (`tianyi,tyfza1-2p5g`): LED remap, RTL8221B Clause45 PHY on port 4, S3/reset GPIOs |

Dropped (bring-up milestones whose content is fully contained in the common
include, or external-script-only workflows): `rtl9617c-tyfza1-mdio`,
`-xram-lan`, `-dma-tx`, `-ni`, `-pon-status`, `-nand-readonly`,
`-stock-ubi-readonly`, `-pcie`, `-pcie-2p5g`, `-ubi`, `-ubi-2p5g`, and the
now-merged `-leds.dtsi`, `-2p5g.dtsi`, `-usb.dtsi` includes. Board names
(`tianyi,tyfza1`, `tianyi,tyfza1-2p5g`) are unchanged, so `board.d`,
`platform.sh`, uci-defaults and the storage migration keep matching.

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
