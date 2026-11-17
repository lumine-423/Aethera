# addons · 第三方特效插件

本目录存放从外部引入的 Godot 插件，均为 MIT（各自原创美术另按仓库声明）。
两个插件都已在 `project.godot` 的 `[editor_plugins]` 里启用；如被关掉，去
**项目 → 项目设置 → 插件** 重新勾选即可。

## fx_forge — Jeff FX 1.1

- 来源：https://github.com/jeffstudio-dev/Jeff-FX-forge（作者 Smidle / Jeff Studio）
- 本地原始包：`F:\sigil-circuit\Jeff-FX\`（zip + 解压副本 + 导入日志）
- 内容：129 款效果 = 像素工坊 63（含 25 款按 pixelfx 方法重做的「升级版」、16 款烟花、4 款飞弹命中）+ 三维效果库 66（经典 44 / 多风格 18 / 追踪飞弹 4）
- 用法：编辑器顶部 **Jeff FX** 菜单 → 选效果 → 调参数/时间轴 → 另存为个人配方（默认 `res://fx_forge_presets/`）→ 导出精灵图/SpriteFrames/场景（默认 `res://fx_exports/`）→ 放置到 Node2D/Node3D 场景
- 内置配方在 `addons/fx_forge/legacy/presets/`（48 个）与 `addons/fx_forge/library/recipes/`（21 个）
- 注意：上游只在 Godot 4.7.2 / macOS / M4 / Compatibility 实测；3D 效果导出的是录好的二维帧；部分爆炸/烟末帧截断

## pixelfx — 0.3.0

- 来源：https://github.com/winkidney/pixelfx-godot（原库 patch-gg/pixelfx，Godot 移植 winkidney）
- 本地仓库：`F:\sigil-circuit\pixelfx-godot\`（JS 源码 + Godot addon + gallery）
- 内容：244 个纯代码绘制的像素特效，节点 `PixelFx2D` / `PixelFxAct2D`，可烘焙成 SpriteFrames
- 用法：把节点挂到场景，设 `effect`（特效 id）、`palette`、`light`、`actor` 等参数；带 `act` 的特效由 `PixelFxAct2D` 演出
- 注意：JS 库与本插件同源，配方参数可对照 `pixelfx-godot/src/fx/` 阅读

## 验证

- `godot --headless --path rolecard-rpg --import`：导入 170 步完成，无插件/脚本报错（日志 `F:\sigil-circuit\Jeff-FX\godot-import.log`）
- 实例化自检：`PixelFx2D`、`PixelFxAct2D`、`SpriteEffect2D`、`fx_forge` 配方均加载成功（脚本 `.tmp/verify_addons.gd`，PASS）
- 改动前的工程配置备份：`project.godot.<时间戳>.bak`
