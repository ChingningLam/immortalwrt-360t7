# ImmortalWrt 25.12 for 360T7

[Qihoo 360T7](https://openwrt.org/toh/qihoo/360t7)（MT7981B / Filogic 820）的 ImmortalWrt 25.12 固件，面向 **有线中继 AP + 802.11r/k/v 无缝漫游**。固件在 GitHub Actions 云端编译，编译成功后自动发布到 Releases。

## 默认值

| 项目 | 默认值 |
|---|---|
| 基线 | ImmortalWrt `v25.12.2`（Linux 6.12 LTS） |
| 设备 | `qihoo_360t7`，仅标准布局，单镜像 |
| Wi-Fi 名称 | `immortalwrt-360t7`（2.4G / 5G 同名） |
| Wi-Fi 密码 | 无（开放网络） |
| 管理地址 | `192.168.5.1` |
| 登录账号 | `root`，无密码 |
| 主题 | Aurora，中文 LuCI |
| 漫游 | 802.11r/k/v 就绪；DAWN 已装但**默认不启动** |
| 不含 | openclash、ua3f、广告拦截等（交给主路由） |

> 开放网络无法使用 802.11r（FT 需要 PSK/802.1X 的密钥体系）。先用开放网络进后台，设好密码后跑一次 `360t7-ap-setup`，11r 才会启用。

## 为什么不用 mtwifi 闭源栈

评估过 `tfnhui/immortalwrt-mt798x-25.12`（25.12.4 + MTK OpenWrt Feeds）和 hanwckf / padavanonly 两条 mtwifi 路线，结论是不适合这个场景：

| 项目 | 官方 25.12（mt76） | mtwifi 25.12 / 6.6 |
|---|---|---|
| 360T7 支持 | 官方原生 | 外置设备，靠 rebase 维护 |
| 硬件 NAT | 无 | 有 HNAT，但上游 README 明确「外置设备、以太网作为 LAN：不支持 ❌」 |
| 802.11r 配置 | 标准 hostapd，UCI/LuCI 直接开 | mtwifi-cfg 只有 11k 的 RRMEnable，没有 11r 项 |
| DAWN | 原生兼容 | 依赖标准 hostapd，基本不可用 |
| 安全更新 | 跟随官方 | 跟随 rebase，滞后 |

你的用法是「360T7 有线接主路由当 AP」——**二层桥接没有 NAT，HNAT 完全不生效**；而 mtwifi 栈又给不了标准 11r。所以这里选官方 mt76：5G 160MHz 实测 1.1–1.3 Gbps，已经超过千兆口上限。

## 镜像说明

仓库只产出一个设备的镜像：

| 文件 | 用途 |
|---|---|
| `*-squashfs-sysupgrade.itb` | 正常升级 / 首次安装 |
| `*-initramfs-recovery.itb` | 恢复模式 |
| `*-bl31-uboot.fip` / `*-preloader.bin` | bootloader 相关，**写错会变砖** |

## 编译

Actions → **build-360t7** → Run workflow，`version` 默认 `v25.12.2`。流程：

1. 克隆指定标签，Aurora 主题以本地包形式放进 `package/`（固定 commit）
2. 安装 feeds，应用 `configs/360t7.config`，跑 `scripts/diy.sh` 改默认 LAN IP
3. `make defconfig` 并校验关键符号（缺一个就失败，不会白跑）
4. 下载 + 编译，约 60–90 分钟
5. 产物同时进 **Artifacts** 和 **Releases**（tag 形如 `build-20261121-183000-run12`）

## 刷机

详细步骤与救砖见 [docs/flashing.md](docs/flashing.md)。要点：

- 已经是 ImmortalWrt → 直接 `sysupgrade` 标准版，不保留配置
- 原厂固件 → 必须先有 U-Boot，官方没有 factory 镜像
- 刷前备份 mtd，写 bootloader 分区时保证供电

## 有线中继

固件已内置 `/usr/sbin/360t7-ap-setup`：

```sh
360t7-ap-setup -s "immortalwrt-360t7" -k "your-password" \
  -i 192.168.5.2 -g 192.168.5.1 -m 3607 -n 360t7
```

注意：`-i` 要填**主路由同网段**里没被占用的地址。默认固件的 `192.168.5.1` 只是首次进后台用；如果主路由就是 `192.168.5.1`，务必改用 `192.168.5.2` 之类。

脚本会设静态 IP、关 DHCP/RA、删 WAN、关 firewall、统一 PSK、开 11r/k/v；5G 固定 **36/HE80**（5.2G，非 DFS），2.4G 固定 **11**。如果主路由两个频段 SSID 不同，用 `-s` 指定 5G、`-S` 指定 2.4G。最后 `network restart` 在后台执行，SSH 会断，约 10 秒后连新地址。

## 无缝漫游

- 跨芯片（ath11k ↔ mt76）的 802.11r 可行，FT 在 hostapd 用户态完成
- 两台 AP：同 SSID / 同 PSK / 同 `mobility_domain` / 不同 `nasid` / 都跑完整 wpad
- 建议 `psk2+ccmp`、`ft_over_ds=0`、`ft_psk_generate_local=1`、`reassociation_deadline=20000`
- 先只开 11r/k/v 观察，DAWN 按需再开

详见 [docs/roaming.md](docs/roaming.md)。

## 性能与加速

- 有线：MT7531 交换机 + 2.5G CPU 链路，4 个千兆口
- 无线：5G 2×2 160MHz PHY 2402 Mbps；80MHz 已足够跑满千兆
- flow offload：仅路由/NAT 模式有意义，纯 AP 用不上（`firewall4` 默认带 `kmod-nft-offload`）
- WED：256MB 机型开启后可用内存约减半，默认不开

## 已知问题

| 问题 | 影响 | 规避 |
|---|---|---|
| [openwrt#22308](https://github.com/openwrt/openwrt/issues/22308) | MT7981 开 11r 后 5G phy 可能消失（DFS 信道） | 5G 用 36（非 DFS）；仍复现则 `360t7-ap-setup -F` 关 11r |
| [openwrt#22200](https://github.com/openwrt/openwrt/issues/22200) | 25.12 早期 SAE+FT 漫游失败 | 用 `psk2+ccmp`，脚本已默认 |
| 2.4G 信号一般 | 硬件/天线限制 | 5G 为主，2.4G 覆盖近场 IoT |

## 目录结构

```
.github/workflows/build.yml           GitHub Actions 编译 + Release
configs/360t7.config                  固件 .config（单设备）
scripts/diy.sh                        构建期修改默认 LAN IP
files/etc/uci-defaults/99-360t7-defaults  首启默认 SSID/开放网络/IP
files/usr/sbin/360t7-ap-setup         有线中继 + 漫游配置脚本
docs/flashing.md                      刷机与救砖
docs/roaming.md                       802.11r/k/v 与 DAWN
```

## 参考

- [ImmortalWrt 25.12.2 filogic](https://downloads.immortalwrt.org/releases/25.12.2/targets/mediatek/filogic/)
- [OpenWrt Wi-Fi roaming](https://openwrt.org/docs/guide-user/network/wifi/roaming)
- [Aurora 主题](https://github.com/eamonxg/luci-theme-aurora)
- [DAWN](https://github.com/berlin-open-wireless-lab/DAWN)

## License

脚本与文档 MIT；固件遵循 ImmortalWrt/OpenWrt 的 GPL-2.0。
