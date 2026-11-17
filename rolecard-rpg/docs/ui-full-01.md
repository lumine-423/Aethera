# 全套界面 UI-FULL-01：结构、接口与验证

本批由前端UI工位完成。所有界面和动画都是 Godot 原生节点与代码绘制，没有网页专用接口，同一套代码用于桌面 exe、安卓 apk 和 Web。

## 怎么打开

| 用途 | 方式 |
|---|---|
| 正常启动 | 工程默认场景已改为 `res://scenes/ui_root.tscn`：标题 → 主页 → 各板块 |
| 逐页审阅 | 标题菜单「界面总览」，可直接跳到每个界面和弹窗 |
| 指定起始页 | 运行参数 `-- --ui-start=battle`（任意页面名） |
| 旧主页样板 | `res://scenes/home.tscn` 仍可单独运行，旧检查脚本不受影响 |

## 文件

| 位置 | 作用 |
|---|---|
| `scripts/ui/ui_hub.gd` | 自动加载 `UiHub`：昼夜调色、显示/声音选项、对外接口信号 |
| `scripts/ui/ui_root.gd` | 1920×1080 设计画布缩放、页面栈、过场、弹窗、提示、返回键（含安卓返回） |
| `scripts/ui/ui_screen.gd` | 页面基类：锚点布局、自动切入动画、标题打字、滑动光标 |
| `scripts/ui/ui_kit.gd` `ui_plate.gd` `ui_button.gd` `ui_label.gd` `ui_icon.gd` `ui_widgets.gd` `ui_overlay.gd` | 组件库：斜切底板、按钮、约 80 个矢量图标、滑杆、进度条、立绘位、粒子、碎片爆发、光线、弹窗 |
| `scripts/ui/reveal.gdshader` `frost.gdshader` | 昼夜圆形揭幕、弹窗毛玻璃 |
| `scripts/ui/screens/*.gd` | 17 个页面 |
| `data/ui/portrait_registry.json` | 立绘 / 头像 / 场景 / CG 唯一接入点 |
| `data/ui/ui_demo_content.json` | 预览数据，全部是占位，不是设定或数值 |
| `data/ui/ui_palette_extra.json` | 组件额外色位；基础色仍在 `data/home_palette.json` |

## 页面清单

标题（含解锁）、载入、主页（原样板，接入路由）、存档/读档、剧情目录、剧情事件（Galgame）、剧情回放、资料库、角色档案、插画鉴赏、地点、编队与准备、战斗（含角色详情）、行动胜利/失利/撤退、本局战报、刻印制作、仓库、设置（显示/声音/API连接/世界书/存档与恢复）、界面总览。弹窗：行动暂停、确认撤退、导入备份、清除恢复点、覆盖/删除存档、离开剧情、退出游戏、连接中断、资源未能载入、未能保存、获得物品、提示条。

## 动效

| 动效 | 位置 |
|---|---|
| 三层斜切擦屏 0.84 秒（沿用参考 HTML 参数） | 页面切换 |
| 双楔合拢 + 斩线 | 进入战斗 |
| 斜切切入 + 亮边 | 每页每块底板和按钮按位置依次切入 |
| 悬停上浮 3px / 按下下沉 2px 并微缩 / 扫光 / 跟随光标的光斑 / 点击波纹 | 所有按钮 |
| 滑动选择光标 | 标题菜单、设置页签、剧情目录页签、剧情选项 |
| 圆形揭幕 + 光环 | 昼夜切换（从点击处扩散） |
| 毛玻璃 | 弹窗、获得物品、回看 |
| 视差粒子、漂浮几何、背景缓移 | 各页背景 |
| 锁定准星、碎片爆发、重击震屏、伤害数字弹出、回合横幅 | 战斗 |
| 光线旋转、标题砸落、奖励数字递增 | 胜利结算 |
| 打字机文字、立绘进出、说话者轻跳、选项切入 | 剧情 |

「减弱动态效果」会关闭以上全部运动。

## 2026-11-05 细化（第二轮）

- 剧情行动框 `scripts/ui/ui_action_panel.gd`：左侧选项一行收起、点开展开整段（两三句），最后一行是多行自由输入；右侧整高「发送」，没选或自由输入为空时不可点。上下键切换、回车发送（自由输入里 Ctrl+回车）。普通台词时对话框右上「自由行动」只打开自由输入；点空白或返回键关闭。
- 子页面之间改为「旧画面快照滑走 + 新页滑入 + 一道强调色斜边」，0.42 秒；主页、标题之间仍用三层擦屏。返回方向相反。
- 主要按钮每 3.6 秒自动扫一道光。
- 战斗：名牌移到脚下，不再挡住后排；占位小人改为几何人形，会轻微呼吸；回合牌字对齐。
- 胜利页左侧加转动徽记；地点页右栏加场景图位。
- 检查增至 42 项；动效视频 `evidence/ui-full-01/ui-motion-02.mp4`（48 秒）。

## 2026-11-05 第三轮：几何装饰与动效细节

- 纯色块统一走 `Kit.ornate()`：主按钮、选中页签、强调色/深色底板都带光影、细斜纹、暗角、内描线。
- 主按钮右端有斜缝端片；悬停时斜纹流动、次要按钮出现角括号。
- 发送键 `SendKey`：倒角外形、选好后从下往上充能、双菱形环反向旋转、按下纸飞机飞出。
- 滑杆菱形旋钮；进度条有刻度并在出现时填满；分区标题细线画出；新页到达有一道光带扫过。
- 视频 `evidence/ui-full-01/ui-motion-03.mp4`。

## 2026-11-05 音效（UI-SFX-01）

- 调用：`UiHub.sfx(提示音名, 音高, 增益dB)`；`UiHub.haptic(毫秒)` 手机震动。
- 表：`data/ui/ui_sounds.json`（54个提示音，含音量、随机音高、冷却、总线）。
- 文件：`assets/audio/ui/aic/` 与 `assets/audio/ui/original/`，同名可互换；设置→声音→音效风格切换。
- 重建：`python tools/build_ui_sfx_01.py`，之后 Godot `--headless --import`。
- AIC 包只用于开发试听，分发权未确认；公开版本用原创包或授权素材。
- 按钮默认按类型出声；需要专用音时设 `press_sfx`，静音设 `"none"`；菜单可设 `hover_pitch`。

## 留给其他工位的接口

- 立绘：在 `data/ui/portrait_registry.json` 填 `res://` 路径即可，`full` 档案/剧情全身，`bust` 半身，`card` 名单卡，`avatar` 头像。空值显示「立绘待接入」。
- 战斗动画：`battle.unit_view(i).mount_actor(节点)` 放角色待机/动作场景；`battle.mount_presentation(节点)` 放大招演出层；`show_damage(i, 数值, 类型)`、`set_phase()`、`set_round()`、`set_active()`、`finish()` 由战斗服务驱动。
- 剧情：`story.push_line({...})` 追加一句，`set_scene_texture()`、`show_choices(选项数组, 是否允许自由输入)`；确认后发 `story.choice` 或 `story.free_input`。这里的行格式只是界面侧临时格式，不是 AI 出文格式。
- 服务请求统一走 `UiHub.action_requested(action, payload)`：`story.advance/choice/free_input`、`battle.start/use_skill/pause/finished`、`craft.make`、`save.load/write/delete`、`backup.export/import/restore/clear_recovery`、`ai.connect/test`、`character.chat`、`party.changed`、`inventory.select`、`access.unlock`、`app.quit` 等。
- 界面不扣材料、不发奖、不存密钥、不判定密码；这些都只发请求。

## 验证

- `res://tools/capture_ui_full_01.tscn -- --ui-review --checks`：39 项交互检查（每页可建、真实点击、返回栈、主页路由、战斗选技能→选目标→扣血、剧情推进/选项/自由输入/回看、回放无输入、昼夜、布局滑杆、弹窗返回、20:9 与 4:3 屏幕）。
- 同场景不带 `--checks`：每页昼夜截图到 `evidence/ui-full-01/`。
- `res://tools/demo_ui_motion_01.tscn` 配合 `--write-movie` 录制动效演示，成片 `evidence/ui-full-01/ui-motion-01.mp4`（42 秒，1280×720，30fps，离线逐帧，不代表实时帧率）。

## 未验证 / 未完成

- 没有在真机安卓或导出的 exe 上运行过；Web 导出预设未加入新文件。
- 中文输入法、粘贴、手柄未测。
- 毛玻璃在部分安卓 GPU 上可能只显示为暗色遮罩（模糊依赖屏幕纹理 mipmap）。
- 大部分页面没有对应的新概念切片，是按已接受风格用代码绘制；用户美术接受未取得。
- 预览数据（敌人、物品、配方、章节、战报比例）全部是占位。
