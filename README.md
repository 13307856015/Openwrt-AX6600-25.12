# ImmortalWrt 25.12 backport for JDCloud RE-CS-02 (京东云雅典娜 AX6600)

把 **JDCloud RE-CS-02 / AX6600** 的机型支持 backport 到 **ImmortalWrt 25.12.2** 的可复现补丁集 + GitHub Actions 云编译工作流。

## 为什么需要这个

ImmortalWrt 的 `openwrt-25.12` 分支（含 25.12.0 / 25.12.1 / 25.12.2 / 25.12-SNAPSHOT）**根本没有 jdcloud 机型**：

- `releases/25.12.2/targets/qualcommax/ipq60xx/` 只有 15 个机型，没有 RE-CS-02 / RE-SS-01；
- 25.12 分支源码 `target/linux/qualcommax/image/ipq60xx.mk` 中没有 `jdcloud_re-cs-02`；
- 该机型是 2026-01 才随上游 PR 进入 OpenWrt/ImmortalWrt 主线的，晚于 25.12 分支切出时间。

所以“别人编译好的 25.12 雅典娜固件”不存在——不是没人编，是 25.12 源码里没有这个机型，编不出来。本套件把上游设备支持补丁（DTS + 镜像定义 + 网络 / caldata / eMMC 升级）移植到 25.12.2 上，再由 GitHub Actions 编译。

## 目录

```
patches/
  0001-ipq-wifi-register-jdcloud_re-cs-02-board.patch    # ipq-wifi 板级 BDF 包
  0002-qualcommax-add-jdcloud-re-cs-02-dts.patch         # DTS + dtsi（新增文件）
  0003-qualcommax-image-add-jdcloud_re-cs-02-device.patch# 设备定义（eMMC / FIT）
  0004-qualcommax-02_network-add-jdcloud_re-cs-02.patch  # 网口映射 lan1-4 / wan
  0005-qualcommax-caldata-add-jdcloud_re-cs-02.patch    # 从 eMMC ART 分区取 WiFi 校准
  0006-qualcommax-upgrade-emmc-for-jdcloud_re-cs-02.patch# eMMC 双分区 sysupgrade 支持
configs/ax6600-25.12.seed                                # 编译种子配置
.github/workflows/build-ax6600-25.12.yml                 # 云编译工作流
tools/make-patches.ps1                                   # 重新生成补丁（可选）
```

## 用法：GitHub Actions 云编译（推荐）

> 第一次用 GitHub、不会操作？看 **[docs/github云编译步骤.md](<docs/github云编译步骤.md>)**（从建仓库到下载固件的零基础步骤）。

1. 在 GitHub 新建一个仓库（**public 或 private 都行**，private 的 Actions 分钟数会消耗额度），把本目录内容推上去：
   ```bash
   git init
   git add -A
   git commit -m "AX6600 ImmortalWrt 25.12 backport"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```
   > `.github/workflows/` 必须一起提交，否则 Actions 里看不到工作流。
2. 仓库页面 → **Actions** → 左侧 **Build ImmortalWrt 25.12 for AX6600** → **Run workflow**
   - `ref`：默认 `v25.12.2`，也可以填 `openwrt-25.12`（跟分支最新）或其它 25.12.x tag
   - `extra_packages`：可选，空格分隔，例如 `luci-app-ttyd luci-app-upnp luci-app-ddns`
   - `create_release`：默认勾选，构建完自动建 Release
3. 约 **2～3 小时**（GitHub 免费 runner 4 核），完成后在 **Releases** 或该次 run 的 **Artifacts** 下载：
   - `*-squashfs-sysupgrade.bin`：系统内升级 / U-Boot 刷写
   - `*-initramfs-uImage.itb`：首次从原厂或救砖时走 TFTP/U-Boot 用

## 用法：本地编译（Linux / WSL2）

```bash
sudo apt update && sudo apt install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev python3-setuptools \
  rsync unzip zlib1g-dev file wget ccache libelf-dev bc patch perl python3 swig \
  qemu-utils zip libpython3-dev

git clone --depth 1 --branch v25.12.2 https://github.com/immortalwrt/immortalwrt.git openwrt
cd openwrt
for p in ../patches/*.patch; do git apply --verbose "$p"; done

cp ../configs/ax6600-25.12.seed .config
make defconfig
./scripts/feeds update -a && ./scripts/feeds install -a
make download -j"$(nproc)"
make -j"$(nproc)" V=s
```

产物在 `openwrt/bin/targets/qualcommax/ipq60xx/`。

## 刷机（重要）

本套件产出的是 **纯官方 ImmortalWrt 25.12.2 线**（无 NSS、无 PPE 硬件加速、kernel 6.12），和 `ones20250/Openwrt-AX6600` 的 snapshot + PPE + 6.18 是两个体系：

1. 已有 OpenWrt/ImmortalWrt 系统：LuCI → 系统 → 备份/升级 → 刷 `*sysupgrade.bin`（不要保留来自 6.18/PPE 固件的配置，建议不保留配置刷）。
2. 原厂固件 / 救砖：用 U-Boot + TFTP 加载 `*initramfs-uImage.itb`，进入 initramfs 后再 `sysupgrade` 刷 sysupgrade 镜像（与原厂 U-Boot 的中断方式见上游 commit 说明：固件 ≥ 4.3.0.r4211 时在 “disabled console and autoboot in 2 seconds” 处输入 `jdmt018R`）。
3. 刷完确认版本：
   ```sh
   cat /etc/openwrt_release     # 应显示 ImmortalWrt 25.12.2
   ubus call system board
   ```

## 已验证 / 未验证

已验证：
- 6 个补丁对 **immortalwrt v25.12.2 原始文件** 全部 `git apply --check` 通过（逐文件生成，上下文精确匹配），打完补丁后 `target/linux/qualcommax/image/ipq60xx.mk` 出现 `Device/jdcloud_re-cs-02`；
- 改完的 `platform.sh` 通过 `sh -n` 语法检查；
- 25.12 分支已有依赖：`emmc_do_upgrade`（`lib/upgrade/emmc.sh`，由 `do_stage2` 的 `include /lib/upgrade` 自动加载）、`caldata_extract_mmc`、`ipq6018-ess.dtsi`（`edma/switch/dp1..dp5`）、`ipq-wifi` 源版本 2026-05-18（含 2025-10-22 加入的 `board-jdcloud_re-cs-02` BDF）；
- 25.12 没有 `find_mmc_part()`（主线是随 eMMC 机型一起加的），补丁 0006 自带一个基于 `/sys/class/block/*/uevent` 的等价实现，不依赖其它包。

未验证（诚实说明）：
- **未在真机上验证编译产物**（这里没有 6GB 级 OpenWrt 构建环境）。DTS 取自上游设备支持 commit（2025-04，当时 main 就是 kernel 6.12），与 25.12 的 6.12 内核基本同龄，理论上可直接编译；若你的构建在 DTS 阶段报错，把报错贴回来即可修。
- 2.5G WAN（QCA8081）、三频 WiFi、点阵屏：官方 25.12 线没有 `luci-app-athena-led`，点阵屏不会亮/不可控；WiFi 与 2.5G 走标准驱动，功能可用但无任何加速优化。
- 补丁按 **v25.12.2** 生成；把 `ref` 换成 `openwrt-25.12` 分支或 25.12.0/25.12.1 时个别文件上下文可能已变，需要按 `tools/make-patches.ps1` 的思路重新生成。

## 常见问题

- **`make defconfig` 后没有 `CONFIG_TARGET_..._DEVICE_jdcloud_re-cs-02=y`**：说明补丁没打上或 ref 不是 25.12 线，检查 `target/linux/qualcommax/image/ipq60xx.mk` 是否含 `Device/jdcloud_re-cs-02`。
- **`make download` 个别包 404**：重跑一次或忽略，编译时会重试下载。
- **Actions 磁盘不够**：工作流已内置清理 `/usr/share/dotnet`、`/opt/ghc`、Android SDK 等步骤。
- **想加插件**：编辑 `configs/ax6600-25.12.seed` 追加 `CONFIG_PACKAGE_xxx=y`，或在 Run workflow 时填 `extra_packages`（25.12 使用 apk 包管理器，插件需在 25.12 feed 中存在）。
