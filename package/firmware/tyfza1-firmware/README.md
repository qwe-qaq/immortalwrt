# tyfza1-firmware packages

The RTL9617C port needs three groups of vendor files at runtime. None of
them are redistributable under a free licence, so they live in this
project's own firmware repository
(https://github.com/qwe-qaq/tyfza1-firmware) instead of the ImmortalWrt
tree, and the two packages here download them at build time like any
other remote-source package.

| Package | Contents | Consumers |
| --- | --- | --- |
| `tyfza1-wifi-firmware` | RTL8852C/8192XB radio firmware, TSSI tables, RFE54 (TYFZA1) / RFE50 + RTK66587_BPF_YH1570 (PT1570) parameter sets | `rtl_ax_ap` via `request_firmware()` |
| `tyfza1-pon-firmware` | `pon_serdes_{epon,epon_d10g,epon_bi10g,gpon,xgpon,xgspon}.bin` | native `pon` driver |

Per-device calibration (`bosa-calibration.bin`,
`flash-calibration.bin`) is deliberately **not** packaged: it is read
from the device's own flash at startup, so flashing a shared blob would
destroy every unit's identity, optical calibration and radio
calibration.

## Producing the source archives

The CI workflow downloads the upstream
`tyfza1-runtime-inputs-v1.tar.gz` release asset, strips the per-device
calibration, and repackages the remainder into the two archives the
packages expect (see `.github/workflows/build-tyfza1.yml`,
step "Build firmware source archives"). To publish by hand:

```sh
tar -xzf tyfza1-runtime-inputs-v1.tar.gz -C inputs
# Version numbers must not contain '-': apk reserves it as the
# version/revision separator, so use dotted dates and matching tags
# (v2026.10.24 in PKG_SOURCE_URL).
ver=$(date +%Y.%m.%d)
# wifi: everything under lib/firmware/realtek/tyfza1
tar -czf "tyfza1-wifi-firmware-$ver.tar.gz" -C inputs lib/firmware/realtek/tyfza1
# pon: the six SerDes images under lib/firmware/realtek/rtl9617c
tar -czf "tyfza1-pon-firmware-$ver.tar.gz" -C inputs lib/firmware/realtek/rtl9617c
```

Upload both as release assets of the firmware repository, matching the
`PKG_VERSION`/`PKG_SOURCE_URL` in the package Makefiles, and record the
sha256 in `PKG_HASH` (replace the `skip` placeholder - set
`PKG_HASH:=skip` only for local builds).

## Mainline-submission layout

For an ImmortalWrt mainline pull request these two packages stay in this
repository (or a dedicated feed): upstream will not carry proprietary
blobs, but it does carry packages that fetch them. The code-side target
tree (`target/linux/rtl9617c`) contains no blobs and is the part to
submit; point the PR description at the firmware repository as the
binary source, mirroring how other vendor-firmware packages reference
their download URLs.
