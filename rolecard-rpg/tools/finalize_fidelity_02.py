from pathlib import Path
import json, hashlib, shutil, re
from PIL import Image

project=Path(__file__).resolve().parents[1]; root=project.parent
art=project/'art-source/fidelity-rework-02'; evidence=project/'evidence/fidelity-02'
def write(path,text): path.write_text(text,encoding='utf-8')
def save(path,data): write(path,json.dumps(data,ensure_ascii=False,indent=2))
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
calls=json.loads((art/'generation-calls.json').read_text(encoding='utf-8'))
calls['calls']+=json.loads((art/'generation-followup.json').read_text(encoding='utf-8')); calls['call_count']=4
save(art/'all-generation-calls.json',calls)
assets=[]
for name in ['home.png','panel.png','panel-backing.png','home-glyph-source.png','panel-glyph-source.png']:
    p=project/'assets/ui/fidelity-v2'/name
    with Image.open(p) as im: mode,size=im.mode,list(im.size)
    source=next((Path(c['source']) for c in calls['calls'] if (c['key']+'.png')==name),None)
    if name=='home-glyph-source.png': source=project/'art-source/ui-revision-01/home-day-r1.png'
    if name=='panel-glyph-source.png': source=Path(calls['calls'][0]['reference'])
    assert source and sha(source)==sha(p)
    assets.append(dict(file=str(p),source=str(source),size=size,mode=mode,bytes=p.stat().st_size,sha256=sha(p)))
save(art/'manifest.json',dict(date='2026-10-29',call_count=4,night_texture_copies=0,assets=assets,
    note='3 generated production sheets, 2 exact concept references used only for glyph/lettering/outline cuts; full-height attempt retained but not used.'))
html=Path('F:/艾瑟拉界面.html').read_text(encoding='utf-8-sig')
css=re.search(r'<style>(.*?)</style>',html,re.S).group(1)
write(art/'reference-motion.css.txt',css)
lines=html.splitlines(); write(art/'reference-navigation.js.txt','\n'.join(f'{i+1}: {lines[i]}' for i in range(990,1030)))
save(art/'reference-source.json',dict(file='F:/艾瑟拉界面.html',sha256=sha(Path('F:/艾瑟拉界面.html')),
    keyframes=re.findall(r'@keyframes\s+(\w+)',css),evidence='Read-only source analysis; original HTML was not executed in browser.'))

report='''# 主页与看板：按概念图还原的返工记录

本项目视觉优先级：用户明确指令 → 采用概念图的视觉效果 → 实现习惯。用户要求“百分百还原，内容和细节都不能省”；这是制作及验收目标，不是自动通过声明。不得用技术检查或“风格相似”抵消遗漏。

基准是ui-revision-01/home-day-r1.png及用户指定exec-9a004b6f看板详情。看板的通用背景、两个底部操作区删除、左侧立绘预留、共享RGB昼夜按用户指令优先。之前擅自缩短底板已撤销；保留完整高度，并用生图补成连续底板。

| 对照项 | 发现的问题 | 本轮修正 |
|---|---|---|
| 主页图标 | 简化成单色，形状及大小有变化 | 重取参考造型；保留黑红分色、纸飞机和星芒、仓库红底菱形、齿轮红分隔。 |
| 按钮细节 | 竖线、短斜纹、角标、细线、灰色叠片缺失或变形 | 新透明源保留这些细节，各按钮按原位切开；修了作战切片带入相邻区域而遮字的问题。 |
| 主菜单字形 | 原生字形与概念字形不同 | 剧情／资料库／作战／仓库／设置用原母图的独立字形贴片；Label保留、改名自动切回原生文字，字号滑杆同步缩放。 |
| 看板状态 | 头像框、切换底片、分隔线和轨道缺失 | 补原造型；无真实好感数据时保持空灰轨道，悬停说明未知，不伪造红色填充值。 |
| 昼夜开关 | 原来只有孤立图标 | 胶囊边框、中央分隔、原图标及选中转入动画；共用同一源和RGB。 |
| 看板主体 | 放大居中、缩短底板、多层重复标题条 | 回到1672×941母图坐标，右侧原位；重建完整底板，删除两个按钮且补全遮挡区。 |
| 看板细节 | 交谈气泡、切换符号、细边框、原发送箭头、斜纹欠缺 | 使用参考图标及分块前景，输入箭头改回简单箭头；文字、好感、输入及关闭仍是独立控件。 |
| 背景及状态 | 用户明确共享背景，AI／好感未接 | 共用现有背景实例；空立绘区不塞假人物，不伪造数据或AI回复。 |

## 动画源码到引擎的对应

原HTML只读，未载入旧布局／旧角色／外链字体或其游戏逻辑。完整CSS、导航时序与源指纹在本目录；不声称看过原文件在浏览器实际播放。

| 原代码位置与参数 | 当前实现 |
|---|---|
| L87–88 rise：46px、.62s、cubic-bezier(.2,.8,.2,1)、backwards | motion.gd解贝塞尔横坐标再算纵坐标；主页错峰入场，EntranceLayer与悬停层独立。 |
| L129–150 按钮：悬停-3px、按下+2px、.2s；扫光-60%到120%、.55s、白色峰值.45 | art_button.gd及palette.gdshader；看板状态和发送部件也有反馈。 |
| L90–99、L1004–1029 wipe：斜15°，三层宽150/130/115%，.84s，延迟0/.05/.10，-170%到140%，420ms换页，1000ms解锁 | 连续穿屏，去掉旧实现的中央停顿；motion.gd使用(.75,0,.25,1)，实际截图验证遮挡时切页。 |
| L121–127 切色选中：旋转-90°起、scale .6起、.6s；选中1.08 | 昼夜图标独立变换，色彩约.4s过渡，不加载第二套美术。 |
| L448–460 窗口：透明.3s，位移30px/.4s，关闭可见性延后.35s，关闭图标旋转90°/.2s | 开关窗口按这组时序，Esc与焦点恢复配合关闭完成；修掉初次文字取错动画起点和X被底片遮住。 |
| L232 名称替换：.55s rise | 看板切角色，名字／问候语独立入场；连续切换会取消旧动画。 |
| L78–81 背景 blink3.6s / drift9s，幅度8px | 调色器只对相应小装饰区域做周期透明和轻移；减弱动态时停止。周期节奏沿用，周期插值使用平滑函数，非逐帧复制CSS。 |

其余已读动画：float(8s)、artIn(.75s)/artOut(.42s)、streak(2.6s)/glow(3.2s)/scan(2.4s)/spark、pulse(2.4s)、tab-body rise(.45s)、shake(.4s)、pickPulse(1.2s)、rot(.6s)、bump(.45s)、tip/toast显隐，以及sortie的fadeIn/slabIn/slabIn2/cardIn/popIn/stamp/行动记录。它们对应未实施的立绘、角色档案、编队和出击页，保留源码参数，待这些页面实施时采用；本轮没有伪造对应页面或新增角色特效。

## 证据和仍未接受的部分

原生主页26项、看板25项通过；新增22项动效检查通过。evidence/fidelity-02/motion.mp4是当前实现的GPU实际录制，12.6秒、60fps、1152×648。录制过程约17秒，离线写帧速度不代表实时设备帧率。工具record_fidelity_02.gd可复现。原生宽窄截图保留，Web另外实际操作。

不能称为逐像素100%通过：生成前景的纹理、局部边缘／层叠、透明边缘处理与概念仍有微差；动态角色名、交谈和看板文字使用原生字体。共享背景、空好感轨道、删除按钮及遮挡区补底按用户要求改变；这些不应和擅自省略混为一谈。继续以对照页和用户批注逐点修正，不自行给美术完成度打分或标driver-accepted。

本轮内置image_gen共4次：主页透明源、首版透明部件源、完整高度候选、底部去空按钮并补底。候选仍残留两个空按钮底片，已用最后一次定点编辑消除；仅3张生成源进入运行。源PNG只复制未重绘；两张原母图运行时只取字形、图标和细线，未显示整图背景或用整张截图当按钮热区。昼夜美术副本0。提示词及指纹见all-generation-calls.json和manifest.json。
'''
write(art/'RESTORATION.md',report)

readme=project/'docs/home-ui-01.md'; old=readme.read_text(encoding='utf-8-sig')
authority='''
## 当前版本：概念还原返工 v2（2026-10-29，优先于下文早期样板说明）

视觉制作按用户明确指令优先、概念效果其次，主体与细节不能省。当前美术和动效对照记录见art-source/fidelity-rework-02/RESTORATION.md；唯一进度仍是根交接单。

- 运行前景：assets/ui/fidelity-v2/home.png（主页各按键／状态／胶囊）、panel.png（详情无字部件）、panel-backing.png（恢复完整高度、去掉两空按钮后的背板）。昼夜均复用这些图。home-v1背景／装饰继续共用。
- home-glyph-source.png／panel-glyph-source.png是原母图的精确副本，只用于独立字形、图标和边线切片；不把旧背景画出来。regions.json为主页切片，panel-polygons.json为详情不规则部件轮廓。
- home_layout.json／character_panel_layout.json控制位置大小。宽屏详情恢复母图1672×941坐标；art_piece.gd按UV多边形切片保留细节，各片仍可移动。原sourcePNG未经本地重绘。
- 当前五个主页标题使用独立母图字形贴片以保持原貌；修改名称会自动回到独立Label，字号滑杆也影响贴片。其余动态字仍是原生控件。
- motion.gd对应原HTML的贝塞尔曲线；art_button.gd和home.gd分别处理按键、入场、窗体和换页。原HTML完整CSS／关键JS摘录及SHA256在返工来源目录。
- 当前证据：evidence/fidelity-02（动效22项、截图与12.6秒实录），主页26项与详情25项仍在原证据目录。网页对照页为http://127.0.0.1:8771/review/ ，交互入口为同端口根路径。
- AI、真实好感及聊天持久化未接；IAB批量输入／中文IME缺口仍保留。生成纹理与局部边缘尚有微差，不将本轮技术通过称为百分百美术验收。

以下是v1及首次详情的历史实现说明，涉及旧4张主页源／两张详情源、旧路径或旧动画参数的，以本节和RESTORATION.md为准。

'''
write(readme,old.split('\n',1)[0]+'\n'+authority+old.split('\n',1)[1])
plan=root/'独立网页像素RPG_完整开发执行计划.md'; s=plan.read_text(encoding='utf-8-sig')
s=s.replace('版本：2.3／看板角色详情模块修订','版本：2.4／概念严格还原与动画源码返工',1)
s=s.replace('技术核查资料（规划候选，不等于已选依赖）：','''### 0.10 严格还原与动画源码返工（2026-10-29）

用户再次明确：自己的指定修改优先，其次概念图视觉效果；必须以百分百还原为目标，主体和细节不能省，不能再以“风格接近”交付。已在0.4写成长期要求，后续模型必须沿用。

本轮授权返工主页与看板：修复图标造型／黑红分色、分隔线、斜纹、细边、角标、头像框、主题胶囊、看板原位和完整底板、交谈气泡与发送箭头；删除两指定入口后补成连续底板，不擅自缩短主体。标题字形独立取原图，改名仍可用Label。透明分块和单套RGB昼夜继续有效。

用户HTML作为代码级动效来源：rise／按钮上浮按下扫光／三层wipe／窗体透明位移／图标转入和关闭旋转已对应实现；其余角色、编队和出击动画已记录，待相应板块采用，不引入旧玩法。完整源码参数、差异和证据见rolecard-rpg/art-source/fidelity-rework-02/RESTORATION.md。原生26＋24及动效22项通过，当前Web与实际画面另验；不代表用户美术接受，也不宣称无差异逐像素100%。

技术核查资料（规划候选，不等于已选依赖）：''',1)
write(plan,s)
dec=project/'docs/decisions.md'; s=dec.read_text(encoding='utf-8-sig'); pos=s.index('\n',s.index('| E43 |'))
s=s[:pos]+'''
| E44 | confirmed-by-driver | 用户明确项目视觉优先级：用户指定修改优先，其次采用概念图视觉效果；以百分百还原为目标，主体及细节不得省略。主页／看板授权返工；朋友HTML须代码级学习全部动画，已定布局／色系不重做。 |
| E45 | implemented-rework / awaiting-driver-review | 前景细节、参考字形、完整看板背板和HTML相关动效已返工，3张生成前景＋2张参考切片源，运行夜间美术副本0；主页26／详情25／动效22项通过。具体差异及未落地的其他页动画见RESTORATION.md；不自评100%或driver-accepted。 |'''+s[pos:]; write(dec,s)
handoff=root/'角色卡RPG开发交接单.md'; s=handoff.read_text(encoding='utf-8-sig'); recent,history=s.split('## 过往简要概述',1)
steps=[x for x in recent.split('\n\n') if x.startswith(('1. **','2. **','3. **'))]; assert len(steps)==3
latest='''1. **2026-10-29｜按“用户指令优先、概念视觉其次，百分百还原为目标、主体细节不能省”返工主页及看板；此要求须后续每轮沿用，当前仍待美术复核。** 用户否定把概念仅当风格灵感，要求逐项还原并代码级学习F:/艾瑟拉界面.html全部相关动效。总计划2.4／0.4已写长期硬要求，0.10和decisions E44–E45记录本轮范围。返工前home脚本／两布局／调色／交接备份在art-source/fidelity-rework-02/before。共4次内置image_gen，all-generation-calls.json保留精确提示词与来源：主页细节透明源、详情部件透明源、完整高度候选、删除候选残留空按钮并补连续底板；3张生成图进入assets/ui/fidelity-v2/home.png、panel.png、panel-backing.png，另两张原母图副本只取字形／图标／细线，均指纹一致未本地重绘，无夜间美术副本。主页补黑红图标、竖分隔、灰斜纹、红细线、边框／角标／灰叠片、头像框、切换灰片和主题胶囊；五个标题使用独立母图字形贴片，改名自动回Label，字号滑杆同步。regions.json与panel-polygons.json切独立部件，art_piece.gd按UV多边形保留细节；看板恢复母图1672×941原位和完整高度，左空、共用背景，底部两入口完全删除并补遮挡底板，交谈图标、切换符号、简单发送箭头、细边斜纹均补回。未知好感保持灰轨道／—，不伪造填充值。motion.gd数值求解CSS贝塞尔；按钮-3px悬停／+2px按下／.55秒扫光，rise46px/.62秒(.2,.8,.2,1)，三层wipe宽150/130/115%、.84秒(.75,0,.25,1)、延迟0/.05/.10、.42秒换页／1秒解锁；窗体透明.3／位移30px .4／关闭.35、主题转入.6、关闭旋转90°/.2、切角色.55和小装饰周期已实现。reference-motion.css.txt／reference-navigation.js.txt／reference-source.json保存原CSS、JS关键时序及原文件指纹；其余角色／编队／出击动画参数已读并在RESTORATION.md记后续归属，不伪造对应页，不声称浏览器播放过原HTML。修了遮字的相邻切片、原生轨道高度、X被层遮、初次文字动画起点与悬停结束状态。主页26项、详情25项、动效22项原生通过；新evidence/fidelity-02/motion.mp4为12.6秒60fps、1152×648 GPU实际录制，离线写帧速度不代表实时性能。Web Home已同步；对照页/review/与主预览同端口8771，网页证据在本证据目录。生成纹理／局部边缘层叠和动态原生字仍有微差，不能标“100%验收”；用户要求的是不省略并继续逐点修正，自动检查不等于美术接受。AI／好感／持久聊天及中文IME旧缺口仍未完成；不自动扩其他页或Galgame出文协议。下一步按本轮实际预览和对照图继续收用户批注，先核对RESTORATION.md与实际产物再改，禁止回到“风格像就行”或擅自简化。'''
history_entry='- 较早主页样板记录已由最近步骤覆盖：2026-10-29首次4张主页生成源、26项检查与旧7.63秒录制在art-source/home-build-01及evidence/home-build-01；其旧图标／分隔／字体和窗体动效已被本轮严格还原返工替代。旧HTML仅源码分析，未绕过file://拦截；原AI／游戏数据／其他页面缺口保留。\n\n'
write(handoff,'## 最近详细三步\n\n'+latest+'\n\n2.'+steps[0][2:]+'\n\n3.'+steps[1][2:]+'\n\n## 过往简要概述\n\n'+history_entry+history.lstrip())

# User-facing comparison is separate from game UI; no extra runtime art palette.
review=project/'build/home/review'; review.mkdir(exist_ok=True)
copy={
 'master-home.png':project/'art-source/ui-revision-01/home-day-r1.png',
 'master-panel.png':Path(calls['calls'][0]['reference']),
 'home-day.png':project/'evidence/home-build-01/home-day.png',
 'home-night.png':project/'evidence/home-build-01/home-night.png',
 'panel-day.png':project/'evidence/character-panel-01/detail-day.png',
 'panel-night.png':project/'evidence/character-panel-01/detail-night.png',
 'motion.mp4':evidence/'motion.mp4'}
for name,p in copy.items(): shutil.copy2(p,review/name)
write(review/'index.html','''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>主页与看板 · 还原对照</title><style>
body{margin:0;background:#f0f1f3;color:#30353d;font:16px/1.7 system-ui,sans-serif}main{max-width:1500px;margin:auto;padding:28px}h1{font-size:26px}h2{margin-top:40px;font-size:22px}a{color:#b71d36}figure{margin:0}img,video{width:100%;display:block}figcaption{padding:8px 0}section{display:grid;grid-template-columns:1fr 1fr;gap:16px}.overlay{position:relative;display:block;aspect-ratio:1672/941}.overlay figure{position:absolute;inset:0}.overlay figure:last-child{opacity:var(--opacity,.5)}.overlay figcaption{display:none}button{padding:8px 16px;border:1px solid #bcc0c8;background:white;cursor:pointer}label{margin-left:15px}small{color:#707782}@media(max-width:800px){section{grid-template-columns:1fr}main{padding:18px}}</style><main>
<h1>主页与看板 · 概念图／当前运行对照</h1><p>用户指定修改优先，其次概念视觉。主体和细节不能省；此页没有给美术完成度打分。<a href="/">进入可操作主页</a></p>
<p><button id="mode">切换叠加对照</button><label>当前稿透明度 <input id="opacity" type="range" min="0" max="100" value="50"></label></p>
<h2>主页 · 日间</h2><section><figure><img src="master-home.png"><figcaption>采用概念图</figcaption></figure><figure><img src="home-day.png"><figcaption>当前Godot实际运行</figcaption></figure></section>
<h2>看板角色详情 · 日间</h2><p>按用户要求，共用现有背景，删除下方两个操作入口，保留主体完整高度；好感数据未接，立绘区留空。</p><section><figure><img src="master-panel.png"><figcaption>用户指定参考（包含应删除的两个按钮）</figcaption></figure><figure><img src="panel-day.png"><figcaption>当前Godot实际运行</figcaption></figure></section>
<h2>同一组素材 · 夜间运行截图</h2><section><figure><img src="home-night.png"><figcaption>主页</figcaption></figure><figure><img src="panel-night.png"><figcaption>看板详情</figcaption></figure></section><small>以上夜图是验收截图，游戏运行没有另装一套夜间美术。</small>
<h2>当前动效 · 引擎实录</h2><video controls preload="metadata" src="motion.mp4"></video><p>12.6秒／60fps；按钮悬停与扫光、昼夜切换、窗口开关、角色切换、斜片换页。生成纹理、局部边缘与动态文字仍需继续逐点核对，不自称百分百验收。</p></main>
<script>let on=false;document.querySelector('#mode').onclick=()=>{on=!on;document.querySelectorAll('section').forEach((s,i)=>{if(i<2)s.classList.toggle('overlay',on)});document.querySelector('#mode').textContent=on?'切换左右对照':'切换叠加对照'};document.querySelector('#opacity').oninput=e=>document.documentElement.style.setProperty('--opacity',e.target.value/100);</script></html>''')
print('Plan 2.4, restoration rule, 4 generation receipts, motion source audit and three-step handoff saved.')
