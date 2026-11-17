# 完整版 神秘学UI 全面翻新（MYSTIC-FULL-01，2026-11-14）

完整版（rolecard-rpg，非参赛版）的界面风格、动效和音效统一换成神秘学几何方向：白底细灰线＋红色点缀（昼）、黑底暖灰线＋金色点缀（夜）。参赛版（F:/魔塔比赛/game）已封包，本轮只读、未改。

## 做了什么

| 部分 | 内容 | 位置 |
|---|---|---|
| 页面并集 | 参赛版界面（公告、连接AI、出身、角色创建、剧情、改原文、事件档案、地图、存档、设置…）与原版独有界面（地点作战、编队、战斗、结算、战报、总览）合并到同一个界面根 | `scripts/ui/ui_root.gd` SCREENS |
| 前端服务门面 | 参赛版 `Game` 门面与本地演示后端一并带入（只是界面取数/发请求的入口，不是新后端） | `scripts/game/` 自动加载 `Game` |
| 组件风格 | 细衬线字（Noto Serif SC，OFL），圆润外框＋细线、叠片双线、红/金小圆点、短下划线、月牙徽记、四芒星；旧的实心色块全部改为浅色描边 | `scripts/ui/ui_kit.gd` `ui_plate.gd` `ui_button.gd` `ui_widgets.gd` `ui_icon.gd` |
| 背景 | 全代码绘制：纸色、缓转的大构造圆、长斜线、巨型四芒星轮廓、星尘，随鼠标轻微视差 | `scripts/ui/ui_backdrop.gd` |
| 转场 | 主转场改为“圆形展开＋月牙扫过＋四芒星闪光＋圆环退开”；子页滑动改成细线扫过；点击处出现圆环＋星 | `ui_root.gd` |
| 标题页 | 经典 galgame 版式：场景图铺底、看板角色站右、左侧薄纱上放 r6 定版字标（从母稿按亮度取透明，不重画）＋竖排菜单；悬停出现四芒星、字右移、下划线画出；星尘飘落 | `scripts/ui/screens/title_screen.gd`，字标 `assets/ui/mystic/title_logo_mask.png`（`tools/build_title_logo_mystic.py`） |
| 开场 | 占位：昼夜选择 → 用卡里原有开场文案的短演出 → 下一页；左下角标“开场动画 · 占位”，可跳过 | `scripts/ui/screens/opening_screen.gd` |
| 主页 | 按概念07：剧情（月牙徽记）/资料库/作战/仓库＋角色·地图·刻印·事件档案；左侧看板立绘与好感卡；电源回标题 | `scripts/ui/screens/home_screen.gd` |
| 看板交谈 | 概念16：聊天气泡、切换角色、发送只发 `character.chat` 请求，不编回复 | `scripts/ui/screens/talk_screen.gd` |
| 刻印工坊 | 移植原卡工坊：同一套22枚纹章（从卡源码提取）、同一接口几何、同一图纸文字和耗用算法；拖拽连接、旋转、断开、拆除、图鉴、激活点亮、已保存、导出/导入、上传请求 | `scripts/ui/screens/workshop_screen.gd`，数据 `data/workshop/patterns.json`（`tools/extract_workshop_parts.js`） |
| 世界地图 | 照卡里矢量舆图描出：海岸线、国界、航路、山形、河流，加经纬圆、罗盘星；地名随缩放分级；当前位置月牙脉冲；落针标记沿用 | `scripts/ui/screens/map_screen.gd`，数据 `data/map/world_lines.json`（`tools/build_mystic_map.py`） |
| 音效 | 新“空灵水晶”包64个提示音，全部本地合成（玻璃泛音、铃、星点闪烁、气声扫过、明亮混响，统一高通去闷响）；设为默认，设置里可切回旧包 | `assets/audio/ui/mystic/`（`tools/build_ui_sfx_mystic.py`），表 `data/ui/ui_sounds.json` |

## 检查

- `tools/check_mystic_ui.gd`（headless）：所有页面脚本编译、在真实界面根里逐页建出、工坊吸附/连链/图纸文字/耗用、地图数据、字标与音效资源，共80项通过。
- `tools/capture_mystic_ui.gd`（真实GPU）：26页白天＋8页夜间截图、工坊激活结果、转场中帧，在 `evidence/mystic-ui-20261114/`。

## 未做 / 未验

- 没有在安卓真机、导出的 exe 或 Web 导出里跑；`export_presets.cfg` 的资源白名单未更新。
- 音效只做了波形生成，没有人耳试听调音。
- 开场动画只是占位；剧情回放、高级管理等沿用参赛版页面结构只换了风格，未逐页按45组概念重排版。
- 卡片、立绘之外的全身图沿用参赛版已有素材；完整版其他角色立绘未接入。
- 美术未获用户接受。
