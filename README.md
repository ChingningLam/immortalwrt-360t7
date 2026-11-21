# ImmortalWrt 25.12 for 360T7

[Qihoo 360T7](https://openwrt.org/toh/qihoo/360t7)（MT7981B / Filogic 820）的 ImmortalWrt 25.12 固件，面向 **有线中继 AP + 802.11r/k/v 无缝漫游** 场景。固件在 GitHub Actions 上云端编译，仓库本身不存放二进制。

- 基线：`immortalwrt/immortalwrt` 标签 `v25.12.2`（`openwrt-25.12`，Linux 6.12 LTS）
- 设备：官方 `qihoo_360t7` / `qihoo_360t7-ubi`，mt76 开源驱动 + MT7981 WED 固件
- 无线：`wpad-openssl` 完整版，802.11r (FT-PSK) / 802.11k (RRM) / 802.11v (BTM) 全部可用
- 主题：Aurora（默认），中文 LuCI
- 预置 `/usr/sbin/360t7-ap-setup`：一条命令完成有线中继 + 漫游配置
- 可选 DAWN 跨 AP 引导（默认不启动）
- 不含 openclash / ua3f / 广告拦截等属于主路由的插件

## 为什么选官方 25.12，而不是 mtwifi 分支

| 项目 | ImmortalWrt 25.12 主线 | hanwckf/immortalwrt-mt798x | padavanonly/immortalwrt-mt798x-6.6 |
|---|---|---|---|
| 内核 | 6.12 LTS | 5.4（21.02 基线） | 6.6（24.10 基线） |
| 无线驱动 | mt76 开源 | mtwifi 闭源 | mtwifi 闭源 |
| 硬件 NAT | 无（软件 flow offload） | HNAT | HNAT |
| 安全更新 | 跟随官方 | 基本停更 | 跟随 24.10 |
| 有线中继适用性 | 好 | 好，但 HNAT 无用武之地 | 好，但 HNAT 无用武之地 |

关键点：**有线中继 / AP 模式是二层桥接，没有 NAT，HNAT 不会生效**。三类固件在 AP 场景的差异主要来自 WiFi 驱动本身。mt76 在 MT7981 上 5G 160MHz 2×2 实测 AP→STA 可达 1.1–1.3 Gbps，已经超过千兆口的实际上限；闭源驱动略高 5–10%，但要放弃 25.12 的内核与安全更新。因此这个仓库选官方主线。

> 如果你的目标是「纯无线吞吐极限」而不是「稳定 + 可维护」，可以看 hanwckf 或 padavanonly；本仓库不为这个目标做妥协。

## 镜像说明

| 文件 | 用途 |
|---|---|
| `*-squashfs-sysupgrade.itb` | 正常升级 / 首次安装（需已有 U-Boot 或 OpenWrt） |
| `*-initramfs-recovery.itb` | 恢复模式、UBI 迁移安装器 |
| `*-bl31-uboot.fip` | ATF + U-Boot，**写错会变砖** |
| `*-preloader.bin` | BL2，**写错会变砖** |

两种布局：

- **标准布局**（`qihoo_360t7`）：兼容 360T7 常见的第三方 U-Boot 分区表，刷机风险最低。
- **UBI 布局**（`qihoo_360t7-ubi`）：多约 20 MB 可用空间，factory/fip 放进 UBI 更可靠；**只能从已运行标准布局 OpenWrt 的机器迁移**，不能从原厂直刷。

两个镜像都会在一次编译中产出，文件名带 `-ubi-` 的属于 UBI 布局，别刷错。

## 编译（GitHub Actions）

1. 把本仓库推到 GitHub（或 fork）。
2. Actions → **build-360t7** → Run workflow：
   - `version`：ImmortalWrt 标签或分支，默认 `v25.12.2`
   - `release`：是否同时创建 GitHub Release
3. 首次全量编译约 60–90 分钟；之后命中 `dl` 缓存会快很多。
4. 产物在 Actions run 的 **Artifacts** 里，包含全部 `.itb / .fip / .bin` 与 `sha256sums.txt`。

工作流做的事：克隆指定标签 → 把 Aurora 主题以本地包形式放进 `package/`（固定 commit）→ 安装 feeds → 应用 `configs/360t7.config` → `make defconfig` 并校验关键符号 → 下载 → 编译 → 收集产物。**不会在本地编译。**

## 刷机

完整步骤、风险与救砖见 [docs/flashing.md](docs/flashing.md)。先记住三条：

- 刷之前备份全部 mtd 分区（`cat /proc/mtd` 逐个 `dd`）。
- 写 `preloader.bin` / `bl31-uboot.fip` 时断电大概率变砖，必须接稳压电源。
- 已有 OpenWrt 的机器用 `sysupgrade` 最安全；原厂机器必须先有可用的 U-Boot。

## 有线中继配置

固件已内置脚本，SSH 到 360T7 后直接运行：

```sh
360t7-ap-setup -s "MyWiFi" -k "your-password" \
  -i 192.168.1.2 -g 192.168.1.1 -m 3607 -n 360t7
```

脚本会：

- 给 LAN 桥接设静态 IP，关闭本机 DHCP/RA
- 删除 WAN 接口，关闭 firewall 服务（纯二层 AP，不做 NAT）
- 把所有 AP 接口设成同一 SSID / PSK
- 打开 802.11r (FT-PSK)、802.11k (RRM)、802.11v (BTM)
- 5 GHz 固定到 **信道 149 / HE80**，避开 DFS

参数含义：

| 参数 | 说明 |
|---|---|
| `-s` / `-k` | SSID 与密码（密码至少 8 位） |
| `-i` | 本机 LAN IP，默认 `192.168.1.2` |
| `-g` | 主路由 IP，默认 `192.168.1.1` |
| `-m` | mobility domain，4 位十六进制，**两台必须一致** |
| `-n` | NAS ID，**每台必须唯一** |
| `-d` | 同时启用 DAWN |
| `-F` | 关闭 802.11r，只保留 11k/v（排障用） |

手动配置的关键 UCI 项（等价于脚本）：

```sh
uci set wireless.@wifi-iface[0].ieee80211r=1
uci set wireless.@wifi-iface[0].mobility_domain=3607
uci set wireless.@wifi-iface[0].ft_over_ds=0
uci set wireless.@wifi-iface[0].ft_psk_generate_local=1
uci set wireless.@wifi-iface[0].reassociation_deadline=20000
uci set wireless.@wifi-iface[0].ieee80211k=1
uci set wireless.@wifi-iface[0].bss_transition=1
```

## 无缝漫游

结论：**跨芯片（ath11k ↔ mt76）的 802.11r 可行**，因为 FT 在 hostapd 用户态完成，驱动只负责转发认证帧。前提是两台 AP：

- 同一 SSID、同一 PSK、同一加密套件（建议 `psk2+ccmp`）
- 同一 `mobility_domain`，不同的 `nasid`
- 都跑完整版 wpad（本固件是 `wpad-openssl`；主路由也要确认）
- 关闭 FT over DS（`ft_over_ds=0`），PSK 下开 `ft_psk_generate_local=1`

**只做 11r/k/v 就够了**，不装 DAWN/usteer 也能无缝。DAWN 是"踢人"控制器，用来引导粘性客户端，不是漫游的前提；双 AP 有线回程场景收益有限，本固件只作为可选项编译进去。

详细配置、验证命令与排错见 [docs/roaming.md](docs/roaming.md)。

## 性能与加速

- **有线**：MT7531 交换机 + 2.5G CPU 链路，4 个千兆口，跑满千兆无压力。
- **无线**：5G 2×2 160MHz PHY 2402 Mbps，实测 AP→STA 约 1.1–1.3 Gbps。上行受 mt76 TX ring 限制，通常 800 Mbps–1.1 Gbps。
- **160MHz 还是 80MHz**：千兆口吃不满 160MHz，80MHz 已足够；160MHz 更容易受干扰、触发 DFS/漫游问题。脚本默认 `HE80`，想要极限吞吐可以改 `HE160` 并观察稳定性。
- **flow offload**：只有路由/NAT 模式才有意义；纯 AP 桥接用不上。`firewall4` 默认已经带 `kmod-nft-offload`。
- **WED**：MT7981 支持无线卸载，但 256 MB 机型开启后可用内存会从约 100 MB 掉到约 50 MB，默认不启用。AP 场景收益有限，不建议开。

## 已知问题

| 问题 | 影响 | 规避 |
|---|---|---|
| [openwrt#22308](https://github.com/openwrt/openwrt/issues/22308)：MT7981 开 `ieee80211r` 后 5 GHz phy 消失 | 出现在 DFS 信道（如 ch100），伴随 `key addition failed` | 5G 放非 DFS 信道（149）、`ft_over_ds=0`；仍复现则用 `-F` 关闭 11r，保留 11k/v |
| [openwrt#22200](https://github.com/openwrt/openwrt/issues/22200)：25.12 早期 SAE + FT 漫游失败 | 只影响 WPA3/SAE | 本固件脚本用 `psk2+ccmp`，避开 SAE |
| [openwrt#26782](https://github.com/openwrt/openwrt/issues/26782)：160MHz 长时间后下行掉速 | 报告基于非官方构建，未被上游复现 | 用 80MHz；或定期重关联 |
| 2.4G 信号偏弱 | 硬件/天线限制，非驱动问题 | 5G 为主，2.4G 只覆盖近场 IoT |

## 目录结构

```
.github/workflows/build.yml   GitHub Actions 编译流水线
configs/360t7.config          固件 .config
files/usr/sbin/360t7-ap-setup 有线中继 + 漫游配置脚本（打进固件）
docs/flashing.md              刷机与救砖
docs/roaming.md               802.11r/k/v 与 DAWN 详解
```

## 参考

- [ImmortalWrt 25.12.2 filogic 下载目录](https://downloads.immortalwrt.org/releases/25.12.2/targets/mediatek/filogic/)
- [OpenWrt Wi-Fi roaming 指南](https://openwrt.org/docs/guide-user/network/wifi/roaming)
- [OpenWrt 360T7 UBI 支持 commit](https://github.com/openwrt/openwrt/commit/b7af9b49f892)
- [Aurora 主题](https://github.com/eamonxg/luci-theme-aurora)
- [DAWN](https://github.com/berlin-open-wireless-lab/DAWN)

## License

仓库内的脚本与文档使用 MIT；固件本身遵循 ImmortalWrt/OpenWrt 的 GPL-2.0。
