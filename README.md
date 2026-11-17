# 《艾瑟拉》（Aethera）

> 《艾瑟拉》又名《艾瑟拉世界》是由明星荧荧Hotaru制作的一款不知道什么类型的游戏，总之就是实现了超进化后变成了现在这样的游戏，嗯。

## 本仓库只托管「当前发布版本」的源码

- 仓库内源码 = 线上已发布版本 **v1.0.0**（tag `v1.0.0`）的完整工程快照。
- **开发中的源码不入库**：开发分支、素材草稿、交接文档与旁支工具工程都只在本机开发目录保存；每次正式发版时，才把当版源码同步进本仓库并打新 tag。
- 想跑最新版请直接下载 **Releases** 里的安装包；想读源码请按 tag / 版本号取对应快照。

## 版权与使用声明（重要）

- **严禁二次传播 · 严禁商业用途**，作者 **明星荧荧Hotaru** 免费发布，详见 [LICENSE](LICENSE)。
- 内置提示词预设二改自 **创世回廊** 与 **kunlun**，音乐/音效与第三方开源组件分别保留其原著作权及许可协议。

## 下载安装（Releases）

请前往右侧 **Releases** 页面下载对应平台安装包：

- **手机版（Android）**：`Aethera-vX.Y.Z.apk`
- **电脑版（Windows 64位单文件免安装）**：`Aethera-vX.Y.Z-win64.exe`
- 同页提供 `checksums.txt`（两个包的 SHA256）

游戏内置 **检查更新 / 拉取更新 / 下载更新** 功能（位于标题画面左下角与设置页底部）：打开后可自动检查本仓库最新版 Release 并下载对应平台更新包；Windows 端支持下载后覆盖重启，手机端支持下载或唤起系统浏览器直链安装。

## 仓库目录结构

- `rolecard-rpg/`：Godot 4.7.2 主工程源码（界面、状态引擎、MVU 联动、内置 7 表记忆数据库、创意工坊客户端、故事神谕适配、GitHub 更新器与双端打包脚本）。
  - `assets/monsters/`：**魔物图鉴插图**——8 尊异危魔物（1024×1536）+ 八地区 106 种常规魔物（768×768），全部透明 PNG，一尊一机位；各地区目录内附 `README.md` 列该区魔物危险等级与外形摘要。
- `preset/`、`worldbook/`、`regex/`、`文案/`、`开场白/`：原卡预设、世界书、正则与文稿设定源码。

## 本地开发与双端打包

需要 **Godot 4.7.2**。在 `rolecard-rpg/` 目录下执行：

- 全套无头校验：`tools/check_mystic_ui.gd -- --ui-review`
- 导出 Android APK：`rolecard-rpg/tools/export_android.ps1`
- 导出 Windows EXE：`rolecard-rpg/tools/export_windows.ps1`
- 统一构建与上传 Release：`rolecard-rpg/tools/release_github.ps1`（从本机未入库的 `.env` 读取 `GITHUB_TOKEN`）
