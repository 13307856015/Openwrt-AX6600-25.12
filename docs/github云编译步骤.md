# GitHub 云编译操作步骤（零基础版）

目标：把本套件传到你的 GitHub 仓库，让 GitHub 的免费服务器帮你编译出 25.12.2 固件。
全程只需要浏览器，不用装编译环境、不用敲命令。

---

## 第 0 步：准备

1. 一个 GitHub 账号（没有就注册：https://github.com/signup ，邮箱要能收验证邮件）。
2. 把 `AX6600-25.12-backport.zip` **解压**到一个文件夹，里面应该是：
   ```
   .github/       ← 关键！里面是工作流
   configs/
   patches/
   tools/
   README.md
   ```
   > Windows 资源管理器默认可能不显示 `.github`：点「查看」→ 勾选「隐藏的项目」。
   > **注意：不要直接把 zip 上传给 GitHub，GitHub 不会解压。**

---

## 第 1 步：新建仓库

1. 登录 GitHub，点右上角 **+** → **New repository**。
2. 填写：
   - **Repository name**：`ax6600-immortalwrt-2512`（随便起，别用中文）
   - **Description**：可留空
   - 选择 **Public**（公开仓库的 Actions 免费且不限分钟数；Private 会消耗每月 2000 分钟额度）
   - 下面的 Add a README / .gitignore / license **都不要勾**
3. 点绿色 **Create repository**。

---

## 第 2 步：上传文件（网页上传，推荐）

1. 新建完仓库后，页面上有一行小字链接：
   **"uploading an existing file"**（中文界面：「上传现有文件」），点它。
   > 如果没看到，就在仓库页点 **Add file** → **Upload files**。
2. 打开你解压出来的文件夹，**全选里面的所有内容**（Ctrl+A：`.github`、`configs`、`patches`、`tools`、`README.md`），
   直接**拖进**网页中间的虚线上传区域。
   > 拖文件夹是可以的，浏览器会自动保留目录结构；请用 Chrome / Edge。
3. 等文件列表全部出现，确认能看到类似：
   ```
   .github/workflows/build-ax6600-25.12.yml
   configs/ax6600-25.12.seed
   patches/0001-...patch  ...  0006-...patch
   README.md
   ```
4. 页面下方 **Commit changes**（提交更改）→ 再点一次确认。

> 上传完检查：仓库首页应该能看到 `patches`、`configs` 文件夹；点进 `.github/workflows/` 能看到 `build-ax6600-25.12.yml`。
> 如果 `.github` 没传上去（拖拽时被系统隐藏了），用第 6 步的「补救办法」。

---

## 第 3 步：启用 Actions

1. 点仓库顶部的 **Actions** 标签。
2. 如果是第一次用，会出现提示：
   **"Workflows aren't being run on this repository"** → 点 **I understand my workflows, go ahead and enable them**。
3. 左侧列表里应该出现 **Build ImmortalWrt 25.12 for AX6600**，点它。
   > 看不到工作流 = `.github/workflows/build-ax6600-25.12.yml` 没上传成功，见第 6 步。

---

## 第 4 步：开始编译

1. 在 **Build ImmortalWrt 25.12 for AX6600** 页面，右侧有 **Run workflow** 按钮，点开：
   - **Use workflow from**：`main`
   - **ref**：保持 `v25.12.2`
   - **extra_packages**：留空（想加插件再填，例如 `luci-app-ttyd luci-app-upnp`，空格隔开）
   - **create_release**：保持勾选
2. 点绿色 **Run workflow**。
3. 刷新页面，列表里会出现一条黄色圆点的运行记录，点进去可以看到实时日志。

---

## 第 5 步：等结果、下载固件

- 大约 **2～3 小时**（可以在后台跑，关掉网页也没关系）。
- 状态：🟡 运行中 → 🟢 成功 / 🔴 失败。
- **成功后**，两种下载方式：
  1. 仓库首页右侧 **Releases** → 点最新一条 → 下载：
     - `*sysupgrade.bin`：系统内升级 / U-Boot 刷写
     - `*initramfs-uImage.itb`：原厂首刷、TFTP 救砖
  2. 或者在那次运行页面最下方 **Artifacts** 里下载 `immortalwrt-25.12-ax6600-*` 压缩包。
- **失败**：点开红色 ❌ 的那一步，把日志最后 50 行左右复制发我，我改补丁。

---

## 第 6 步：补救——`.github` 没上传成功怎么办

用网页直接新建这个文件（不用命令行）：

1. 仓库页 **Add file** → **Create new file**。
2. 文件名输入框里输入（输入 `/` 会自动建目录）：
   ```
   .github/workflows/build-ax6600-25.12.yml
   ```
3. 打开你本地的 `build-ax6600-25.12.yml`，**全选复制**内容，粘贴到网页编辑区。
4. 下方 **Commit changes**。

这样工作流就补上了，回到第 3 步。

---

## 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| Actions 里没有工作流 | `.github/workflows/*.yml` 没上传；用第 6 步补 |
| Run workflow 按钮是灰的 | 当前看的是别的分支；确认 "Use workflow from" 选 `main`，或先启用 Actions |
| 运行几秒就红 | 多半是 YAML 粘贴时缩进被破坏；重新上传 yml，或把报错发我 |
| 私有仓库提示分钟数不足 | 把仓库改成 Public（Settings → 最下方 Change visibility），公开仓库 Actions 免费 |
| 编译到一半失败 | 看红色步骤日志；常见是某个包下载 404，重跑一次（Re-run jobs）通常就好 |
| 想加插件 | 编辑 `configs/ax6600-25.12.seed` 加 `CONFIG_PACKAGE_xxx=y`，或在 Run workflow 的 `extra_packages` 填包名 |
| 想改版本 | 把 `ref` 改成 `openwrt-25.12`（跟分支最新）；注意补丁是为 `v25.12.2` 生成的，换版本可能要在日志里看补丁是否还能打上 |

---

## 附：命令行方式（有 Git 的话）

```bash
cd AX6600-25.12-backport
git init
git add -A
git commit -m "AX6600 ImmortalWrt 25.12 backport"
git branch -M main
git remote add origin https://github.com/<你的用户名>/ax6600-immortalwrt-2512.git
git push -u origin main
```

推送完直接跳到第 3 步。
