# 艾瑟拉 · 行动室

2026-10-28用户紧急转向：重心为游戏机制/框架/UI与完整玩家体验。旧连续生图动画路线已停用；美术改成每动作横排五关键帧→用户外部视频模型→透明抽帧/图集。旧说明从下方“历史样片说明”起保留追溯，旧art_pipeline构建命令现在会明确拒绝。

当前玩家入口 `http://127.0.0.1:8765/`：Godot行动室→任务→队伍/准备→逐人回合/目标确认→胜负/撤退结算→战报→再次进入；设置和本机检查点恢复。`/probe`保留旧双入口/旧协议诊断，`/game/`为旧包，`/play/`为新包，不能混用。真实酒馆宿主接入仍待验证，新玩法不会伪造已写回角色卡。

新规则在`data/gameplay_08.json`与`scripts/combat_rules.gd`，页面控制在`scripts/game_shell.gd`。凛零/明空/叶是当前机制候选，技能名称和数值非正式设定；不新增内置故事/商店/经营等未采用内容。当前无正式角色动画，完整场景美化与图集接入仍待后续。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/export_web.ps1 -Target Game
python tools/serve_probe.py
& 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --log-file evidence/combat-08-tests.log --script res://tests/test_combat_rules.gd
python tools/video_assets.py doctor
```

独立素材目录：`F:\艾瑟拉_关键帧与视频素材`。已建17角色/223条五关键帧待绘制清单，图片实际0，不能按清单条目报图已完成。工具已复制在其中，使用说明和官方工具来源见`docs/video-art-strategy.md`；机制合同见`docs/gameplay-08-contract.md`。接手始终先读根`角色卡RPG开发交接单.md`。

## 历史样片说明（新策略和上方入口优先）

Godot 4 网页战斗技术样片，依附艾瑟拉角色卡。玩家在游戏板块主动进入，或剧情指令指定任务，共用战斗与结果回传。游戏当前不负责讲故事；剧情、对话和探索留在角色卡。

唯一续接：`F:\sigil-circuit\角色卡RPG开发交接单.md`。当前决定`docs/decisions.md`；接入边界`docs/host-integration-contract.md`。本轮已验证和未通过项分别见`evidence/probe-05.md`、`evidence/art-review-05.md`。

## 当前能力与边界

- `data/actors.json`声明17名来源角色、24种形态的九动作合同，含所有人的待机。数据登记不等于17人都已可选参战。
- `technical-fixture-02`当前只用凛零测试base/released、解放、飞星、资源、一次提交和重载；旧01存档继续原规则。具体消耗与伤害是测试值，未冻结正式平衡。降神/辅助实际玩法尚未制作。
- 每形态九类：待机、普攻/基础援护、技能1、技能2、大招、受击、防御、倒地、结算。七罪还需解放过渡与第二套九类，共133条必需动作；正式接受数仍为0。
- 当前游戏使用新4帧待机候选与旧6帧攻击草稿；新12帧攻击因约12px脚滑被拒收，只用于检查页。鸟羽美术缺失时明确显示诊断占位，未冒充第二套资产。
- 动作须体现世界书人设；自然动力学、性格符合、资产结构和运行行为分别验收，详见`docs/personality-animation-direction.md`和`docs/art-direction-and-acceptance.md`。
- 已有42项Godot规则检查、19组Node测试、实际浏览器双入口/解放中重载/结果刷新去重证据；真实SillyTavern、完整角色/数值/正式场景和动作仍未验收。

## 从已有产物继续，不重复生图

模块化操作说明：`docs/asset-production-workflow.md`。任务合同`art-source/jobs/rin-motion-05.json`；17角色性格来源和动作方向`art-source/personality-profiles.json`。原调用完整提示词在`art-source/rin-motion-v2/PROMPT.txt`。

```powershell
python tools/art_pipeline.py status --job rin-motion-05
python tools/art_pipeline.py profile --actor rin
python tools/art_pipeline.py prompt --job rin-motion-05
python tools/art_pipeline.py analyze --job rin-motion-05
python tools/art_pipeline.py build --job rin-motion-05
python tools/art_pipeline.py check --job rin-motion-05
```

按当前模块选择一条命令，不机械全部重跑。`build`使用本机Aseprite并等待退出，内部已做结构检查；人工精修另存源，自动生成目标只限`.generated.aseprite`。以上命令不调用生图、不联网、不安装工具，不会自动标记动作已接受。

## 本地运行与验证

有效Godot：`D:\Godot\Godot_v4.7.2-stable_win64_console.exe`，4.7.2.stable.official.ed1daf0bf；不使用全局PATH中的空godot.exe。Aseprite：`D:\Aseprite\aseprite.exe`，1.3.18.6-dev。官方Web模板已在项目`.tools`校验，不重复下载/改全局PATH。

1. `& .\tools\export_web.ps1`导出rolecard-probe-05，文件指纹在`evidence/latest-build.json`。沙箱编辑器缓存报权限错误时，需本机引擎正常运行环境，不能只看退出码假报成功。
2. `python tools/serve_probe.py`只监听127.0.0.1:8765，只服务指定开发页/模块/研究图集和Web包，不服务工具缓存、旧卡或聊天。
3. 打开`http://127.0.0.1:8765/`，主动开始新02任务，解放后重载应恢复鸟羽、能量80、行动1、己7/10；继续飞星后能量20、敌1/9、己4/10；再攻击完成。重发结果不新增。
4. C开发上下文可测新版剧情任务；完成后整页刷新、再选C并点相同剧情，应保持原结果。A/B/C是人工开发身份，不是真实酒馆分支解析。
5. `http://127.0.0.1:8765/art-study`切换待机/失败攻击/旧攻击，正常速、0.25×和逐帧查看。它是检查工具，能播放不等于美术通过。

规则/协议改变时才跑对应回归：

```powershell
node --test tests/protocol.test.mjs tests/host-coordinator.test.mjs
& 'D:\Godot\Godot_v4.7.2-stable_win64_console.exe' --headless --log-file "$PWD/evidence/rules-test-05.log" --path $PWD --script res://tests/test_battle_session.gd
python tools/check_party_animation_manifest.py --verify-sources
```

游戏专属改编按`docs/gameplay-adaptations.md`：飞星已允许，降神可按游戏代价改编，明空等可作辅助。世界书会继续变化，源快照仅保留历史事实，不能否决用户后续批准。

当前仍有来源未定位的MutationObserver控制台错误；未观察到它阻断已测流程，不能说已修复。移动端/低帧率/长期性能/真实音频与宿主写回等仍待测。没有改活卡、写正式MVU/奖励、调用剧情模型、Git提交/推送或发布。
