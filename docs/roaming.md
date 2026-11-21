# 无缝漫游配置（802.11r / 11k / 11v + DAWN）

## 1. 三个协议各干什么

| 协议 | 作用 | 对"无缝"的贡献 |
|---|---|---|
| 802.11r (FT) | 快速切换，跳过完整 4-way 握手 | **关键**，切换中断可压到 50 ms 内 |
| 802.11k (RRM) | AP 向客户端提供邻居报告 | 让客户端知道周围有哪些 AP |
| 802.11v (BTM) | AP 可以建议客户端换 AP | 引导粘性客户端，可选 |

只开 11k/v 不开 11r，客户端仍会重关联，只是慢一点（约 100–300 ms）。要"无缝"，11r 是核心。

## 2. 跨芯片可行吗

**可行。** FT 的认证与密钥派生在 hostapd 用户态完成，ath11k（主路由 IPQ8071）和 mt76（360T7）都只是转发管理帧，不参与 FT 逻辑。

前提条件：

- 两台 AP 的 SSID、PSK、加密套件完全一致
- 同一个 `mobility_domain`（4 位十六进制）
- 每台 AP 的 `nasid` 唯一
- 两台都跑**完整版 wpad**（`wpad-openssl` 或 `wpad-mbedtls`），`wpad-basic` 不带 11k/11v，开了会导致接口起不来
- PSK 场景：`ft_over_ds=0` + `ft_psk_generate_local=1`，不需要配 R0KH/R1KH
- 客户端支持 FT：iPhone、多数 Android、部分 Windows 网卡；Intel 网卡和 Win10/11 在 PSK 下常常不用 11r

Apple 设备对 `ft_over_ds` 敏感，必须 `0`，且 `reassociation_deadline` 建议 `20000`。

## 3. 主路由（ap8220 / IPQ8071）侧

先确认 wpad 版本：

```sh
apk info 2>/dev/null | grep -i wpad || opkg list-installed | grep -i wpad
```

必须是 `wpad-openssl` / `wpad-mbedtls` / `wpad-wolfssl`；如果是 `wpad-basic`，先换掉。

LuCI 路径：网络 → 无线 → 编辑对应 SSID → 无线安全 / 高级设置，勾选：

- 802.11r 快速切换
- 802.11k 无线资源管理
- 802.11v 无线网络管理
- Mobility Domain 填 `3607`
- NAS ID 填 `ap8220`

对应 UCI（索引按实际接口调整）：

```sh
uci set wireless.@wifi-iface[0].ieee80211r=1
uci set wireless.@wifi-iface[0].mobility_domain=3607
uci set wireless.@wifi-iface[0].ft_over_ds=0
uci set wireless.@wifi-iface[0].ft_psk_generate_local=1
uci set wireless.@wifi-iface[0].reassociation_deadline=20000
uci set wireless.@wifi-iface[0].ieee80211k=1
uci set wireless.@wifi-iface[0].rrm_neighbor_report=1
uci set wireless.@wifi-iface[0].rrm_beacon_report=1
uci set wireless.@wifi-iface[0].bss_transition=1
uci set wireless.@wifi-iface[0].nasid=ap8220
uci commit wireless
wifi reload
```

## 4. 360T7 侧

> 固件默认是**开放网络**（无密码），此时没有 PMK，802.11r 不生效，只能靠 11k/v 和客户端自身漫游。先在 LuCI 给 Wi-Fi 设一个 WPA2 密码，或直接用下面的脚本（会自动设 `psk2+ccmp` 并开 11r）。

一条命令（推荐）：

```sh
360t7-ap-setup -s "MyWiFi-5G" -S "MyWiFi-2.4G" -k "your-password" \
  -i 192.168.1.2 -g 192.168.1.1 -m 3607 -n 360t7
```

手动等价配置：

```sh
IF=default_radio1   # 5G；2.4G 是 default_radio0
uci set wireless.$IF.ssid=MyWiFi
uci set wireless.$IF.encryption=psk2+ccmp
uci set wireless.$IF.key=your-password
uci set wireless.$IF.ieee80211r=1
uci set wireless.$IF.mobility_domain=3607
uci set wireless.$IF.ft_over_ds=0
uci set wireless.$IF.ft_psk_generate_local=1
uci set wireless.$IF.reassociation_deadline=20000
uci set wireless.$IF.ieee80211k=1
uci set wireless.$IF.rrm_neighbor_report=1
uci set wireless.$IF.rrm_beacon_report=1
uci set wireless.$IF.bss_transition=1
uci set wireless.$IF.nasid=360t7
uci commit wireless
wifi reload
```

## 5. 信道与 160MHz 的取舍

- 5 GHz 固定 **36 / HE80**（5.2G，非 DFS）：避开 DFS，降低 11r 触发 5G phy 消失（[#22308](https://github.com/openwrt/openwrt/issues/22308)）的概率。
- 160MHz 对千兆口没有实际收益，还更容易受干扰；除非你确定周围 5.8G 干净且不需要 DFS。
- 2.4 GHz 用 1/6/11 中与邻居不重叠的一个，不要和主路由同信道。

## 6. DAWN（可选，不是必需）

DAWN 是去中心化的"踢人"控制器：收集各 AP 看到的客户端信号，主动用 BTM 建议客户端切换。**它不替代 11r**。

什么时候需要：

- 客户端很"粘"，明明在另一个 AP 旁边还不切
- 需要按负载/信号做引导

怎么开：

```sh
360t7-ap-setup ... -d     # 配置 AP 的同时启用 DAWN
```

主路由也要装 DAWN 并启用（`apk add dawn luci-app-dawn` 或 opkg），两台用同一个 LAN 广播地址通信。

关键项：

| 选项 | 建议 | 说明 |
|---|---|---|
| `broadcast_ip` | 你 LAN 的广播地址，如 `192.168.1.255` | 默认 `10.0.0.255` 必须改 |
| `kicking` | `1` 起步 | 先观察，误踢再调 |
| `rrm_mode` | `pat` | 支持 11k 的客户端优先 |
| `set_hostapd_nr` | `1` | 让 hostapd 下发邻居报告 |

风险：DAWN 可能误踢 IoT 设备，或与 11r 叠加导致偶发断流。**建议先只开 11r/k/v 用一周**，确认没问题再考虑 DAWN。

## 7. 验证

### 7.1 配置是否生效

```sh
hostapd_cli -i phy1-ap0 get_config | grep -E "ieee80211r|mobility_domain|nasid|ft_over_ds|ieee80211k|bss_transition"
```

### 7.2 看 FT 事件

```sh
logread -f | grep -iE "FT|AP-STA-CONNECTED"
```

客户端漫游时会看到 `auth_alg=ft`。

### 7.3 客户端视角

```sh
iw dev wlan0 link
wpa_cli -i wlan0 status | grep -E "key_mgmt|bssid"
```

`key_mgmt` 出现 `FT-PSK` 说明在用 11r。

### 7.4 丢包测试

持续 ping 网关，边走边看：

```sh
ping -i 0.2 192.168.1.1
```

一次漫游丢 0–3 个包算正常；持续丢包说明 FT 没成功，客户端在走完整重连。

### 7.5 吞吐

```sh
iperf3 -s          # 360T7 上
iperf3 -c 192.168.1.2 -t 30 -P 4   # 电脑上
```

## 8. 排错

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 开 11r 后 5G 直接消失 | MT7981 + DFS 信道已知问题 | 换 149 信道；`ft_over_ds=0`；仍不行用 `-F` 关 11r |
| 客户端漫游后要重新输密码/断流 | 两端 PSK/加密套件不一致，或 mobility domain 不同 | 统一 `psk2+ccmp`、domain、nasid 唯一 |
| 客户端根本不漫游 | 没开 11k，或信号重叠区太小 | 开 11k；调整 AP 位置/功率，保证 -70 dBm 以上重叠 |
| iPhone 漫游失败 | `ft_over_ds=1` 或 deadline 太小 | 改 `0` + `20000` |
| DAWN 频繁踢人 | kicking 太激进 | 降 `kicking` 或先关掉 |
| `wpad-basic` 下开 11k 接口起不来 | basic 版没有 RRM/WNM | 换 `wpad-openssl` / `wpad-mbedtls` |

## 9. 参考

- [OpenWrt Wi-Fi roaming 指南](https://openwrt.org/docs/guide-user/network/wifi/roaming)
- [OpenWrt 25.12.6 release notes（SAE/GCMP-256 调整）](https://openwrt.org/releases/25.12/notes-25.12.6)
- [openwrt#22308：MT7981 11r 导致 5G phy 消失](https://github.com/openwrt/openwrt/issues/22308)
- [openwrt#22200：25.12 SAE+FT 漫游失败](https://github.com/openwrt/openwrt/issues/22200)
- [DAWN 项目](https://github.com/berlin-open-wireless-lab/DAWN)
