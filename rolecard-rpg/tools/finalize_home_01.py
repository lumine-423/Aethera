"""Record art provenance and the authorized home-only implementation, no image edits."""
import json,hashlib,re,shutil
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
PROJECT=ROOT/'rolecard-rpg'
ART=PROJECT/'art-source/home-build-01'
ASSETS=PROJECT/'assets/ui/home-v1'
EVIDENCE=PROJECT/'evidence/home-build-01'
def dump(path,value): path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
calls=json.loads((ART/'generation-calls.json').read_text(encoding='utf-8'))
assets=[]; notes=['# 主页分层素材生成记录','','本轮4次内置image_gen，参考修订后昼间主页；没有生成夜间副本。文件复制进入工程，源图留在默认生成目录。PNG像素未经本地手绘／重绘；切片由Godot AtlasTexture按regions.json取区域，颜色及低alpha边缘在渲染时处理。生成的排列并不严格均分，故切块用实测边界。','']
for c in calls['calls']:
    p=ASSETS/(c['key']+'.png'); source=Path(calls['source_directory'])/c['source']
    assert sha(p)==sha(source),(p,source)
    with Image.open(p) as im:
        im.verify()
    with Image.open(p) as im:
        item={'key':c['key'],'file':str(p),'source':str(source),'size':list(im.size),'mode':im.mode,'has_alpha':'A' in im.getbands(),'bytes':p.stat().st_size,'sha256':sha(p)}
    assets.append(item)
    notes += ['## '+c['key'],'','透明背景请求：'+str(c['transparent']),'','来源：`'+str(source)+'`','','```text',c['prompt'],'```','']
assert sum(a['has_alpha'] for a in assets)==3
assert len(list(ASSETS.glob('*.png')))==4
dump(ART/'manifest.json',{'finalized':'2026-10-29','reference':calls['reference'],'call_count':4,'assets':assets,'night_texture_copies':0,'runtime_regions':'assets/ui/home-v1/regions.json'})
(ART/'GENERATION.md').write_text('\n'.join(notes),encoding='utf-8')
checks=json.loads((EVIDENCE/'checks.json').read_text(encoding='utf-8'))
assert not checks['failures']
dump(EVIDENCE/'browser-checks.json',{'date':'2026-10-29','url':'http://127.0.0.1:8771/','method':'cua_repl browser screenshots and real coordinate/keyboard input','verified':['final Web build loads and paints','day/night switch','settings secondary window opens','Escape closes settings and restores focus','story entry reaches its route slot','return button restores home','night preference survives one page reload'],'final_error_warning_logs':[],'bounds':'IAB narrow viewport; native GPU captures additionally cover wide screens','not_verified':['other gameplay modules','AI/worldbook/database integration','dynamic portraits','long-term browser storage'],'reference_browser_limitation':'F:/艾瑟拉界面.html file:// opening rejected by browser protocol policy; inspected source only'})
dump(EVIDENCE/'web-build.json',[{'Name':p.name,'Bytes':p.stat().st_size,'SHA256':sha(p)} for p in sorted((PROJECT/'build/home').iterdir()) if p.is_file()])
plan=ROOT/'独立网页像素RPG_完整开发执行计划.md'
s=plan.read_text(encoding='utf-8-sig')
if '### 0.8 主页先行样板' not in s:
    s=s.replace('版本：2.1／集中批注与类 Galgame 方向修订','版本：2.2／主页先行样板与共享调色修订',1)
    block='''### 0.8 主页先行样板（2026-10-29，本轮明确授权）

用户要求先实施一个主页，验证怎样把概念拆块与装配；各部件模块化、以后能自由修改。明确要求昼夜共享素材，只修改RGB颜色。此前“只做概念、不进Godot”的当前工作限制在本轮被这一范围的授权替代；不因此启动所有板块、酒馆整合、数据库、Galgame出文格式或发行打包。

主页按修订稿采用：右侧剧情／资料库／作战／仓库及设置、左下看板状态、左侧立绘留空。运行美术只有一组4张PNG：灰白背景、RGBA装饰、6种无字底板图集、12个白色图标图集；AtlasTexture把底板／图标按实测边界切成独立资源，文字由原生Label排版。布局／名字在home_layout.json，昼夜RGB角色在home_palette.json；着色器按同一纹理调色，无夜间PNG副本。生成图不是逐像素重现母图的承诺，拆件形状与实际画面仍待用户美术检查。

先实现错峰入场、悬停／按下／键盘焦点、斜切遮挡过场与返回、角色选择二级窗、简单显示设置（布局间距／字号／减弱动态）。用户提供的F:/艾瑟拉界面.html仅作为衔接与动画方法参考；浏览器不允许其file://协议，只有只读源码分析证据，没有宣称看过该演示实际播放。当前样板动效已有Godot实际录制。

四个主入口目前进入标题＋返回的模块挂载位，后续页面尚未实现；看板选择只更新状态区角色名，立绘仍留空，好感数据以“—”表示。正式AI互动、游戏数据与完整剧情回放没有因此完成。界面偏好单独保存，原项目名与旧存档目录保持，窗口显示标题设为主页。

主页已设为工程默认启动场景，旧UI源码和旧导出保留。单独Web Home导出用于本地试用，不将旧Web包伪称同步更新。原生26项输入／渲染检查通过，浏览器已点测加载、昼夜、设置／Escape、剧情过场／返回及一次刷新保留夜色；以上不代替人工美术接受和完整应用验收。复现、修改位置与未验边界见rolecard-rpg/docs/home-ui-01.md，当前进度仍以唯一交接单为准。

'''
    s=s.replace('技术核查资料（规划候选，不等于已选依赖）：',block+'技术核查资料（规划候选，不等于已选依赖）：',1)
    plan.write_text(s,encoding='utf-8')
dec=PROJECT/'docs/decisions.md'
s=dec.read_text(encoding='utf-8-sig')
if '| E40 |' not in s:
    rows='''| E40 | confirmed-by-driver | 用户明确先实施一个模块化主页；昼夜共享同一套素材，通过RGB参数切色。仅参考朋友HTML的动效与衔接，不采用其旧图／布局；不自动进入其他板块或全部产品实现。 |
| E41 | implemented-prototype / awaiting-driver-review | home.tscn及scripts/home使用4张生成纹理、独立AtlasTexture部件与Label、共享调色；26项原生检查通过，Web Home已实际浏览器点测。看板只选名字／好感缺数据，主导航是过场与空模块位；AI、动态立绘和其他页面未实现。资料见docs/home-ui-01.md，用户美术接受仍待定。 |
'''
    s=s.replace('| E36 |',rows+'| E36 |',1); dec.write_text(s,encoding='utf-8')
handoff=ROOT/'角色卡RPG开发交接单.md'
s=handoff.read_text(encoding='utf-8-sig')
if '1. **2026-10-29｜主页模块化样板' not in s:
    shutil.copy2(handoff,ART/'handoff-before.md')
    top,history=s.split('## 过往简要概述',1)
    prior=re.findall(r'\d\. \*\*.*?(?=\n\n\d\. \*\*|\Z)',top,re.S); assert len(prior)==3
    current='''1. **2026-10-29｜主页模块化样板已进入Godot，昼夜共用一组素材，待用户实际试用及美术反馈。** 用户明确授权先做主页、各部件切块模块化，昼夜仅改RGB；朋友F:/艾瑟拉界面.html只参考动效衔接。实际4次内置image_gen生成assets/ui/home-v1/background.png（1672×941 RGB）、decoration.png（1672×941 RGBA）、surfaces.png（1671×941 RGBA，6种完整无字底板）、icons.png（1448×1086 RGBA，12图标）。art-source/home-build-01/generation-calls.json、GENERATION.md、manifest.json保留精确提示词／原始来源／尺寸／指纹，复制文件与原生成指纹一致；源PNG未本地重绘。regions.json按实际边界构建独立AtlasTexture，文字由Label独立排；data/home_layout.json改布局／名称／字级，home_palette.json改昼夜RGB，scripts/home/palette.gdshader共享调色及低alpha边缘处理，无夜间PNG副本。scripts/home/art_button.gd把入场与悬停分两层；home.gd管理主页、单独偏好、二级窗与导航边界。scenes/home.tscn已设project默认main；旧game_shell与旧Web包保留，原项目名保留以免换旧user://目录，窗口标题设主页。旧工程配置备份在art-source/home-build-01。当前内容：剧情／资料库／作战／仓库／设置按键，左下看板，左侧立绘留空；错峰入场、轻移悬停／按下、键盘焦点、斜切遮挡换页／返回、昼夜过渡、简单显示设置（间距／字号／减弱动态）、看板角色选择。选择仅更新名字，引用现有3头像，不伪造好感数据；主导航目标只放标题＋返回，真实其他板块、AI、动态立绘、游戏存档均未接。tools/capture_home_01.gd经真实鼠标／键盘输入与GPU截图26项通过，覆盖1672×941、960×540、480×800；evidence/home-build-01/checks.json与8张截图留证。同目录home-motion.mp4为约7.63秒引擎实际录制；tools/record_home_01.gd可复现。Web Home预设仅打包主页，tools/export_home_01.ps1输出build/home，浏览器预览http://127.0.0.1:8771；tools/serve_home_01.py只绑定127.0.0.1且只服务该导出目录，PID／日志在本证据目录。IAB点测加载、昼夜、设置、Escape、剧情入口／返回及一次刷新保留夜色，最终错误／警告日志为空；browser-checks.json记边界。早先Web漏预加载依赖已用显式资源清单修正；小图标入树后须延后设尺寸，字体可变轴须用整数wght标识2003265652，否则会回到源图大小／Thin字重。朋友HTML的file://打开被工具协议策略拒绝，未绕过，只有源码动效分析；真实酒馆API核查旧缺口仍未补。docs/home-ui-01.md说明怎么改；工程根打开主页.cmd可用现有本机Godot启动，未做发行包。总计划2.2／0.8、decisions E40–E41记本轮授权与限制。下一步先由用户看主页实际画面和动效、提出修改；不得把26项检查当美术接受，不自动扩大到其他界面、Galgame出文格式或重启旧失败UI路线。'''
    current_steps=[current,re.sub(r'^1\.', '2.',prior[0].strip()),re.sub(r'^2\.', '3.',prior[1].strip())]
    old='- 较早其他板块概念生产记录：'+re.sub(r'^3\. ', '',prior[2].strip())
    handoff.write_text('## 最近详细三步\n\n'+'\n\n'.join(current_steps)+'\n\n## 过往简要概述\n\n'+old+'\n'+history,encoding='utf-8')
print(json.dumps({'art_files':len(assets),'alpha_files':3,'generation_calls':4,'native_checks':len(checks['checks']),'failures':checks['failures'],'night_copies':0,'plan_version':'2.2'},ensure_ascii=False))
