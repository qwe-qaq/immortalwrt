# PonWRT-TYFZA1 → ImmortalWrt 主线整合报告

以 **ImmortalWrt master** 为基线，将 PonWRT-TYFZA1（天翼 TYFZA1 光猫，
Realtek RTL9617C，四核 Cortex-A55）移植项目整体并入树内。DTS 按要求做了
合并：能合并的合并，纯 bring-up 中间态/外部脚本专用的不再保留。

## 基线兼容性

- 项目锁定基线：OpenWrt main `79bc56cb`（2026-10-07），内核 **6.18.55**
  （sha256 `f4106380…`）。
- ImmortalWrt master 的 `target/linux/generic/kernel-6.18` 与之**完全相同**
  （同版本同 hash），因此 `files-6.18` / `patches-6.18` / `config-6.18`
  目录名与内核补丁全部原样沿用，无内核版本适配成本。

## 整合内容清单

### 1. 新增 target：`target/linux/rtl9617c/`

| 内容 | 处理 |
| --- | --- |
| `Makefile`、`config-6.18`、`modules.mk`、`generic/target.mk` | 原样 |
| `files-6.18/`（139 个平台/驱动源文件，含 PE 无线驱动与预生成的 `pe-tx-code.h`） | 原样 |
| `patches-6.18/`（26 个内核补丁，含 mac80211/flowtable/RTL8221B 等） | 原样 |
| `base-files/`（board.d、uci-defaults、platform.sh、存储迁移等 29 个文件） | 原样 |
| `base-files.mk` | feed 地址改为 `downloads.immortalwrt.org` |
| `dts/` | **整合，见下节** |
| `image/Makefile` | **重写**：去除对树外项目目录（`$(TOPDIR)/../..`）和
  `/usr/bin/mkimage` 的硬依赖，FIT 打包脚本内置化 |
| `image/tyfza1_fit.py` + `image/tyfza1-fit-compression.json` | 新增：自包含的
  双配置签名 FIT 生成器（移植自项目 `make_ubi_fit.py`/`make_boot_fit.py`，
  mkimage 可用 `TYFZA1_MKIMAGE` 指定，压缩契约 JSON 内置） |
| `README.md` | 新增：整合说明 + 构建步骤 |

### 2. DTS 整合（14 个文件 → 4 个）

原项目是一条 bring-up 阶梯（串口 → NAND → 原厂 UBI 布局 → XRAM 网口 →
DMA → NI/LED → PON → PCIe → USB → UBI 生产版），每个中间态都是独立 DTS。
整合后：

| 文件 | 说明 |
| --- | --- |
| `rtl9617c.dtsi` | SoC 公共（原样保留） |
| `rtl9617c-tyfza1.dtsi` | **新增**：整条阶梯合并出的公共板级内容 —— 内存与
  原厂保留区、UART/看门狗、QSPI NAND + 原厂分区表（`static_conf` 保持
  只读，其余可写，与原生产 DTS 语义一致）、MDIO + 4 个千兆 PHY、
  NI/XRAM/DMA/QM 节点、GPIO、LED/灯开关按键（全千兆接线）、I2C BOSA、
  PON MAC、双 PCIe 控制器 + SerDes 表、USB PHY + xHCI |
| `rtl9617c-tyfza1.dts` | 全千兆生产版（`tianyi,tyfza1`） |
| `rtl9617c-tyfza1-2p5g.dts` | 2.5G 生产版（`tianyi,tyfza1-2p5g`）：LED 重排、
  port4 上的 RTL8221B C45 PHY + S3/复位 GPIO（内容并入，不再单独 dtsi） |

**剔除的 10 个变体**（内容已全部包含在公共 dtsi 中，或仅服务于外部脚本）：
`-mdio`、`-xram-lan`、`-dma-tx`、`-ni`、`-pon-status`、`-nand-readonly`、
`-stock-ubi-readonly`、`-pcie`、`-pcie-2p5g`、`-ubi`/`-ubi-2p5g`，以及已并入
的 `-leds.dtsi`、`-2p5g.dtsi`、`-usb.dtsi`。

**保持不变的关键契约**：board name（`tianyi,tyfza1` / `tianyi,tyfza1-2p5g`，
board.d / platform.sh / uci-defaults / 存储迁移全部继续匹配）、OEM 双配置
FIT ABI（conf-0 = 2.5G、conf-1 = 全千兆，由原厂 `b_conf` 选择），因此
**一个 sysupgrade 镜像继续同时支持两种硬件**。属性级 diff 校验确认合并版
与原生产链内容等价（唯一差异：model 字符串改为简洁的主线风格命名）。

### 3. 软件包（新增 `package/` 下三个目录）

`tyfza1-pon-control`（PON 认证/OAM/OMCI 控制，含 Rust OMCI 引擎）、
`tyfza1-storage`（原厂数据迁移/工厂胶囊）、`luci-app-tyfza1-pon`
（LuCI 管理界面）— 原样并入。

### 4. 包级补丁（按 OpenWrt 惯例放入各包 `patches/`，构建时自动应用）

- hostapd `471`（ACS 无 survey 时走 BSS 回退）
- firewall4 `120`/`121`、netifd `120`（VLAN lower 设备/拓扑变更通知）
- iwinfo `130`（txpower unknown 处理）

### 5. 树内直接修改（原 apply-openwrt-patches / regdb 补丁的落地）

- `wifi-scripts`：`mac80211.sh` txpower 设置失败处理（上游已含第一处
  null 判断，补齐其余两处）、`iwinfo.uc`/`iwinfo` txpower 判空
- `tools/mtd-utils`：`--with-zstd`（mkfs.ubifs 需要）
- `wireless-regdb`：随包安装官方签名的 `regulatory.db.p7s`

### 6. 辅助脚本与配置

- `scripts/tyfza1/apply-luci-patches.sh` + `luci-patches/`：feeds 安装后
  给 ImmortalWrt luci feed 打 3 个补丁（系统状态/资源版本/功率标签）
- `scripts/tyfza1/build-fit-tools.sh`：构建带 `TOOLS_LIBCRYPTO` 的 mkimage
  （U-Boot 2026.07，sha256 校验，可自动下载）— 树内自带 mkimage 不支持签名
- `configs/tyfza1-boot.config`：固件种子配置（已并入原 compat.config 的
  常用插件依赖）

## 构建要点（详见 `target/linux/rtl9617c/README.md`）

1. `./scripts/feeds update -a && ./scripts/feeds install -a`
2. `sh scripts/tyfza1/apply-luci-patches.sh`
3. `sh scripts/tyfza1/build-fit-tools.sh ../tyfza1-fit-tools`（一次即可）
4. 准备 RSA2048 签名密钥目录 `keys/tyfza1-build-keys/`（dev.key/dev.crt）
5. `cp configs/tyfza1-boot.config .config && make defconfig`
6. `make TYFZA1_MKIMAGE=$PWD/../tyfza1-fit-tools/bin/mkimage -j$(nproc)`

**注意事项**：
- 无线/PON 运行时固件（`/lib/firmware/realtek/tyfza1/…`）来自原厂提取，
  不可随树分发；构建可用的整机固件前需按原项目流程放入 `files/`，
  否则内核与系统可正常编译但 Wi-Fi/PON 在设备上无法启动。
- `tyfza1-pon-control` 需要主机安装 Rust/cargo（aarch64 musl target）。
- 未做实机冷启动/2.5G 转发的硬件验收（原项目亦如此标注）。

## 云端编译（GitHub Actions）

`.github/workflows/build-tyfza1.yml`：手动触发（或 push `v*` tag），
自动完成依赖安装、Rust 工具链、加密 mkimage 构建、原厂运行时固件
下载（上游公开 release）与安装、luci feed 补丁、FIT 签名
（默认使用 GPL 仓库中的原厂 Verified Boot 密钥，可用
`TYFZA1_FIT_SIGNING_KEY` secret 覆盖）、编译与产物上传；
`release_tag` 输入非空时发布 Release。

对 ImmortalWrt 的两处小适配：
- `luci-app-tyfza1-pon` 去掉 `+luci-i18n-argon-config-zh-cn` 依赖
  （ImmortalWrt 的 luci feed 无 argon-config 包，其 argon 主题自带
  设置界面）；种子配置同步移除该行。
- `scripts/tyfza1/luci-patches/100` 按ImmortalWrt luci 重排
  （系统状态页含 CPU 负载/温度字段、ACL 增加
  `getBuiltinEthernetPorts`）；三个补丁均已在 ImmortalWrt luci
  feed 上验证可应用。

## 新增第二块板：YHTC PT1570-H10（yhtc_pt1570）

参考 [dreamtekcat fork](https://github.com/dreamtekcat/PonWRT-TYFZA1)
的 PT1570 实战工作，以**增量方式**新增第二块板，TYFZA1 的编译产物
（设备定义、DTS、镜像元数据、存储迁移流程）保持不变：

- 新增 `dts/rtl9617c-pt1570.dts` / `-pt1570-2p5g.dts`（compatible
  `yhtc,pt1570-h10` / `yhtc,pt1570-2p5g`，驱动继续匹配
  `tianyi,tyfza1`）；三键面板（reset@8 / lights@103 / wifi@99）
  取代 TYFZA1 的单键；公共 dtsi 的按键定义移入各板文件。
- `image/Makefile` 新增 `yhtc_pt1570` 设备块；FIT 启动脚本的
  槽位翻译参数化——TYFZA1 `31:12/31:9`（ubiblock0_7/0_4），
  PT1570 `31:11/31:8`（ubiblock0_6/0_3，无 ubi_fpga 卷、卷 ID 低 1）。
- `platform.sh` 按 board_name 分支：TYFZA1 保持 `nand_do_upgrade`
  + 存储迁移校验；PT1570 走 fork 的 `tyfza1_write_slots`（LEB 边界
  填充修复）+ `platform_copy_config`。`tyfza1-storage.sh` 的根卷
  ID 校验按板分支（`ubi0_4/7` vs `ubi0_3/6`），两板镜像互拒刷入。
- 无线参数目录按板选择（root compatible 判断，仅影响 PT1570）：
  8192XB 用 `RFE50`（无外置 FEM）、8852C FEM 阶段用
  `RTK66587_BPF_YH1570`；TYFZA1 保持 `RFE54`/`RTK66587_BPF`。
  RFE50/YH1570 参数表已内置 `base-files/lib/firmware/`。RPQ 上报
  阈值（0x9414）按芯片区分：8852C=12，8192XB=121（原厂动态公式值）。
- 射频参数表（RFE50 八件、YH1570 十二件）取自 PT1570 原厂
  rootfs，随 base-files 下发；TYFZA1 的校准仍走运行时固件流程。

## 交付物

- `iw/immortalwrt-master/`：整合完成的完整 ImmortalWrt 主线树
- `tyfza1-immortalwrt-integration.zip`：仅含新增/修改文件的 payload，
  可直接解压覆盖到任意 immortalwrt-master 检出上
