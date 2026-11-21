# 刷机指南（360T7）

> 这份文档只描述流程与判断依据，具体命令以对应教程为准。刷机有变砖风险，尤其是写 `preloader.bin` / `bl31-uboot.fip` 时。

## 0. 准备

1. **备份**：能进系统时，先备份全部分区。

```sh
cat /proc/mtd
# 对每个 mtdN 执行，输出到 U 盘或 scp 回电脑
dd if=/dev/mtdN of=/tmp/mtdN.bin
```

2. **电源**：接稳压电源或满电 UPS，刷 bootloader 时断电基本等于变砖。
3. **校验**：下载后先核对 `sha256sums.txt`。

```sh
sha256sum -c sha256sums.txt
```

4. **别混刷**：标准布局和 UBI 布局的分区表不同，刷错起不来。本仓库只产出**标准布局**镜像。

## 1. 判断当前状态

```sh
ubus call system board | grep board_name
cat /etc/openwrt_release 2>/dev/null
```

- 输出 `qihoo,360t7` → 标准布局 OpenWrt
- 输出 `qihoo,360t7-ubi` → UBI 布局
- 没有 `/etc/openwrt_release` → 还是原厂固件

## 2. 情况 A：已运行 OpenWrt / ImmortalWrt（标准布局）

最安全，直接 sysupgrade：

```sh
sysupgrade -n /tmp/immortalwrt-25.12.2-mediatek-filogic-qihoo_360t7-squashfs-sysupgrade.itb
```

或 LuCI → 系统 → 备份/升级 → 不保留配置。跨大版本（24.10 → 25.12）务必不保留配置。

## 3. 情况 B：原厂固件

官方**没有 factory 镜像**，必须先有可用的 U-Boot。两条常见路线：

### B1. 临时 U-Boot（mtk_uartboot）

用串口 + `mtk_uartboot` 把 U-Boot 载入内存，再从 U-Boot 的 Web/TFTP 刷入 `preloader.bin`、`bl31-uboot.fip` 和 `initramfs-recovery.itb`，进系统后 sysupgrade。

参考：

- [OpenWrt 添加 360T7 支持的 commit（含流程说明）](https://github.com/openwrt/openwrt/commit/dc2d4d73939c)
- [恩山：360T7 刷机 / 救砖 / mtk_uartboot 保姆级教程](https://www.right.com.cn/forum/thread-8436865-1-1.html)

### B2. 先刷第三方 U-Boot

国内更常见的做法：先刷 360T7 的不死 U-Boot，之后在 `http://192.168.1.1/uboot.html` 直接上传 `sysupgrade.itb`。

注意：第三方 U-Boot 的分区表与官方标准布局一致才能直刷；不一致时会出现"刷完不启动"，需要换回官方 U-Boot 再用 TFTP recovery。

参考：[恩山：不死 U-Boot 刷官方 OpenWrt 的坑](https://www.right.com.cn/forum/thread-8392181-1-1.html)

## 4. 情况 C：迁移到 UBI 布局（可选，本仓库不产出）

> 本仓库只编标准布局。如果你确实需要 UBI 布局，请使用 ImmortalWrt 官方 25.12.2 的 `qihoo_360t7-ubi` 镜像，流程如下。

UBI 布局多约 20 MB 空间、factory/fip 放进 UBI，更可靠，但**只能从已运行标准布局 OpenWrt 的机器迁移**。

1. 在标准布局 OpenWrt 上，用 installer initramfs 升级（不保留配置），安装器会重建 factory、格式化 UBI、写入新 fip/bl2。
2. 重启进入安装器后，再刷 `qihoo_360t7-ubi-squashfs-sysupgrade.itb`。

安装器与脚本：

- [csharper2005/owrt-ubi-installer（qihoo 分支）](https://github.com/csharper2005/owrt-ubi-installer/tree/qihoo/bin)
- [OpenWrt UBI 支持 commit](https://github.com/openwrt/openwrt/commit/b7af9b49f892)

迁移过程中断电阻断风险高于普通 sysupgrade，建议先不动，除非确实需要那 20 MB。

## 5. 首次启动

- 地址：`http://192.168.5.1`
- 默认无密码（root 空密码），进 LuCI 第一件事设置密码
- 默认 Wi-Fi：`immortalwrt-360t7`，开放网络，2.4G/5G 都已开启
- 有线中继配置见 [README](../README.md) 或直接跑 `360t7-ap-setup`

## 6. 救砖

按成功率从高到低：

1. **U-Boot Web recovery**：按住 reset 上电，网线接 LAN，访问 `http://192.168.1.1/uboot.html` 重新上传固件。
2. **TFTP recovery**：U-Boot 启动时从 `192.168.1.1` 的 TFTP 服务器拉取镜像。
3. **mtk_uartboot**：串口 + `mtk_uartboot` 临时载入 U-Boot，再重刷 bootloader。
4. **编程器**：最后手段，拆 SPI-NAND。

## 7. 刷完检查

```sh
ubus call system board
iw dev
dmesg | grep -i mt7981
```

确认：型号正确、两个 radio 都在、没有 `ieee80211` 相关报错。然后跑 `360t7-ap-setup` 配置中继。
