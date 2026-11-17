# 主页样板：部件与修改位置

## 当前版本：概念还原返工 v2（2026-10-29，优先于下文早期样板说明）

视觉制作按用户明确指令优先、概念效果其次，主体与细节不能省。当前美术和动效对照记录见art-source/fidelity-rework-02/RESTORATION.md；日常进度以workspaces/frontend-ui/前端UI子交接单.md为准，重大进展同步根总交接。

- 运行前景：assets/ui/fidelity-v2/home.png（主页各按键／状态／胶囊）、panel.png（详情无字部件）、panel-backing.png（恢复完整高度、去掉两空按钮后的背板）。昼夜均复用这些图。home-v1背景／装饰继续共用。
- home-glyph-source.png／panel-glyph-source.png是原母图的精确副本，只用于独立字形、图标和边线切片；不把旧背景画出来。regions.json为主页切片，panel-polygons.json为详情不规则部件轮廓。
- home_layout.json／character_panel_layout.json控制位置大小。宽屏详情恢复母图1672×941坐标；art_piece.gd按UV多边形切片保留细节，各片仍可移动。原sourcePNG未经本地重绘。
- 当前五个主页标题使用独立母图字形贴片以保持原貌；修改名称会自动回到独立Label，字号滑杆也影响贴片。其余动态字仍是原生控件。
- motion.gd对应原HTML的贝塞尔曲线；art_button.gd和home.gd分别处理按键、入场、窗体和换页。原HTML完整CSS／关键JS摘录及SHA256在返工来源目录。
- 当前证据：evidence/fidelity-02（动效22项、截图与12.6秒实录），主页26项与详情25项仍在原证据目录。网页对照页为http://127.0.0.1:8771/review/ ，交互入口为同端口根路径。
- AI、真实好感及聊天持久化未接；IAB批量输入／中文IME缺口仍保留。生成纹理与局部边缘尚有微差，不将本轮技术通过称为百分百美术验收。

以下是v1及首次详情的历史实现说明，涉及旧4张主页源／两张详情源、旧路径或旧动画参数的，以本节和RESTORATION.md为准。


本轮授权是“先做一个能操作的主页，切块、部件模块化，昼夜只改颜色”。此页说明结构与复现方式；当前进度只记根交接单。美术是否达到用户要求，仍由用户检查本样板后决定。

当前入口：`res://scenes/home.tscn`，已设为工程默认启动场景。旧game_shell源码与旧导出保留；原项目名保留以免改变既有user://目录，窗口标题由主页设为“主页”。没有修改战斗规则、真实酒馆、世界书、预设或游戏存档。

## 先看结果

- 本机浏览器预览：http://127.0.0.1:8771/ 。这是同一份Godot主页的Web导出，服务只绑定127.0.0.1、根目录限build/home。
- 原生运行：在Godot中打开工程，运行home.tscn；或双击工程根目录“打开主页.cmd”。使用本机已有Godot，不代表已制作独立发行安装包。
- 截图：`evidence/home-build-01/home-day.png`、`home-night.png`；动效录制：同目录`home-motion.mp4`。

## 如何改部件

| 要改什么 | 位置与作用 |
|---|---|
| 按钮名字、位置、大小、字级、图标位置 | `data/home_layout.json`，每个按钮独立一项；文字是Label，未烘焙进图片。 |
| 昼夜颜色 | `data/home_palette.json`，day/night两组RGB角色；不装载两套图片。 |
| 背景本体 | `assets/ui/home-v1/background.png`，灰白无文字底图。 |
| 背景色带和点线 | 同目录`decoration.png`，独立RGBA层。 |
| 按键底板 | `surfaces.png`含6种完整无字底板：主按钮、中按钮、横条、小按钮、角色状态、二级面板。 |
| 图标 | `icons.png`含12个白色透明图标，通过颜色参数着色。 |
| 切块边界 | `assets/ui/home-v1/regions.json`，按素材实际位置定义矩形；运行时构成独立AtlasTexture，不要求生成每个昼夜切片副本。 |
| 单个按钮的交互表现 | `scripts/home/art_button.gd`，底板、图标、文字各一层；EntranceLayer与HoverLayer分开，避免入场与悬停争同一位置。 |
| 颜色映射、透明边缘 | `scripts/home/palette.gdshader`；对同一纹理改RGB，按源RGBA处理透明，不修改源图像像素。 |
| 主页组装与页面交接 | `scripts/home/home.gd`；四入口发navigation_requested信号，后续模块挂接在FutureRouteSlot边界。 |

主页共4张运行美术PNG，其中3张有实际alpha通道；看板详情另外增加2张前景RGBA（见下节），昼夜共享同一批Texture实例。生成图集并未严格按提示词均分，所以regions.json采用实际测量边界。源图保留了低alpha边缘噪点，渲染时用平滑alpha门限及斜边保护处理；没有对源图做手绘修补或把整页截图当点击热区。新部件、底板尺寸和轮廓仍需用户美术验收，不能声称逐像素还原原母图。

左侧立绘层保持空位。旧三头像选择窗现已替换为看板角色详情窗，顶栏切换凛零、明空、梅林，状态区同步名字；没有接动态立绘、AI服务或实际好感数据，“—”代表缺少数据，不冒充0。四个主入口目前验证过场和返回，目标页只保留标题与返回按钮，没有冒充其他板块已经实现。

## 操作与已验证范围

- 鼠标悬停轻移、按下反馈、键盘焦点轮廓；斜切按钮角落不接受点击。
- 主页错峰入场；三层斜向遮挡过场；二级窗口渐显／轻上移与关闭；减弱动态效果可跳过过场等待。
- 昼夜颜色约0.46秒过渡，共用纹理；色彩不会因进入返回占位页变回默认日间焦点色。
- 设置有布局间距与文字大小滑杆；看板角色可选名字。界面偏好使用单独home_ui_sample.cfg，不写游戏档。代码提供保存与读取；浏览器存储的长期可靠性尚未单独验收。
- 宽屏保留左空右按键群；窄窗口将入口移到下方。原生覆盖1672×941、960×540、480×800，不代表所有设备与极端文本组合均已验收。

`tools/capture_home_01.gd`通过真实Godot输入与GPU渲染完成26项检查，结果在`evidence/home-build-01/checks.json`。本机浏览器另检查加载、昼夜、设置窗口、Escape关闭、剧情入口及返回；浏览器日志检查见browser-checks.json。它们不是审美接受、完整游戏功能或真实酒馆通过。

引擎导出命令：`tools/export_home_01.ps1`。单独Web Home预设显式列入脚本、着色器、字体、主页4张纹理与详情2张纹理；旧3头像仍保留在资源清单；初版选择资源导出曾漏预加载依赖，已补齐。只看到导出命令成功不够，须再打开浏览器检查。原生字体为NotoSansSC可变字体，需要整数轴2003265652（wght）；TextureRect入树后延后设小图标大小，避免回弹到源图尺寸。

## 动效参考与来源

只读检查用户提供的`F:/艾瑟拉界面.html`中的动效：rise为0.62秒、cubic-bezier(.2,.8,.2,1)，以延迟错峰；wipe为多层斜向遮挡、遮挡中途换页；modal采用透明与位移过渡。只参考这些衔接方法，没有引入其旧布局、配色、战斗流程、外链字体或旧人物资料。

尝试在浏览器直接打开该本地演示时，工具因不允许file://协议而拦截；没有绕过。故参考证据是源码结构分析，不能声称看过朋友演示的实际动画播放。当前主页的动效已由引擎实际渲染并另录视频。

本轮实际采用的美术母图：`art-source/ui-revision-01/home-day-r1.png`。4次内置image_gen原始提示词、源文件及指纹见`art-source/home-build-01/GENERATION.md`、`generation-calls.json`、`manifest.json`。

实现核对资料：[Godot CanvasItem着色器](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/canvas_item_shader.html)、[Godot AtlasTexture切块](https://docs.godotengine.org/en/stable/classes/class_atlastexture.html)。这些是实现能力依据，当前画面仍以实际渲染与用户验收为准。

## 看板角色详情（2026-10-29）

点击主页左下看板状态，打开用户指定图的前景面板，替换旧三头像选择窗。主入口按键暂时隐藏，背景仍为原主页通用背景；没有加载参考图背景。底部“互动”和“动态演示”两个操作区不再创建。

| 修改内容 | 文件 |
|---|---|
| 整个详情模块、角色切换、交谈输入与关闭 | scripts/home/character_panel.gd |
| 宽屏／窄屏每块位置尺寸 | data/character_panel_layout.json |
| 前景空底与六个无字部件 | assets/ui/character-panel-v1/body.png、parts.png |
| 部件切块边界 | assets/ui/character-panel-v1/regions.json |
| 昼夜配色 | 仍用data/home_palette.json和既有palette.gdshader，夜间PNG副本0 |

标题、角色名、好感条、交谈正文、输入、发送和关闭控件均可独立修改。左侧角色立绘留空，尚无真实好感值。输入只保留本次运行内的玩家文字，按角色隔离，关闭再打开仍在，退出不保存；发送发出character_message_requested信号，目前没有后端接收服务，不会生成AI回复。首次发送后明确显示“AI尚未连接”。

原生tools/capture_character_01.gd通过24项，覆盖同纹理昼夜、角色切换、原文含[b]、发送、关闭／焦点／Esc、窄屏控件在界内；主页回归26项通过。两类脚本应顺序运行，避免引擎窗口与输入争用；模拟点击先等一帧鼠标移动再按下。曾出现单次点击检查未触发，不能把一次重跑通过当作所有窗口条件稳定。

网页实际点测了切色、下拉切换、逐键输入hello和发送、Esc关闭、重开保留内容，最终警告／错误日志为空。IAB批量typeText和paste未完整送达Godot画布，原因未隔离；不能据此宣称中文输入法和粘贴通过。输入法须在实际桌面环境另验。证据在evidence/character-panel-01，日夜宽窄截图与checks.json、browser-checks.json均留档。home-motion.mp4是之前的主页动效，未代表本次新面板。

本轮内置image_gen两次，来源／提示词／指纹在art-source/character-panel-01。分层还原是按参考风格实现的样板，最终美术仍待用户检查。
