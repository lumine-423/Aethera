/* 文案 · 开场（昼夜选择 / 呼唤乐章 / 菜单 / 出身转盘铬文案 / 降临表单）
   ─────────────────────────────────────────────────────────────────
   · 这里只有文字，没有任何标签；想加粗就用 **两个星号** 包住
   · callPhrases / bigLines / bigLinesReduced 是数组：可直接增删改条目；
     bigLines 的最后一条会用小字号渲染（现在的「请你」）。
   · 换行：文本里直接回车即可（渲染成换行）。
   · 改完在仓库根目录跑一次：  python tools/pack-tavern-script.py
   · 也可以用「文案修改器」图形化改： python tools/文案服务.py
     → 浏览器打开 http://127.0.0.1:8777/tools/文案修改器.html
   · 下面是 JSON：语法写错时打包会直接报错并给出行号，不会产出坏包
   ───────────────────────────────────────────────────────────────── */
window.SIGIL_TEXT = window.SIGIL_TEXT || {};
window.SIGIL_TEXT.opening = {
  "modeTitle": "请选择昼夜模式\n（后续可随时更改）",
  "modeDay": "昼",
  "modeNight": "夜",
  "callPhrases": [
    "去拯救吧",
    "我始终相信你是英雄",
    "献上你的觉悟",
    "你愿意见证吗",
    "来向我证明你做得到啊",
    "我一直相信着你",
    "这是你的觉悟吗",
    "见证这一切吧",
    "别再犹豫了",
    "那种事情我办不到",
    "回答我",
    "还来得及吗",
    "以艾瑟拉之名",
    "觉悟的时刻到了"
  ],
  "bigLines": [
    "没想到会以这样的方式与你相见",
    "这次你又会带来怎样的故事呢",
    "看起来，时间不够了",
    "这次，我依然祝你一路顺风",
    "请你"
  ],
  "bigLinesReduced": [
    "没想到会以这样的方式与你相见",
    "这次你又会带来怎样的故事呢",
    "看起来，时间不够了",
    "这次，我依然祝你一路顺风",
    "请你"
  ],
  "finalLine": "拯救艾瑟拉吧",
  "hub": {
    "start": "开始游戏",
    "manual": "艾瑟拉的忠告",
    "manualTitle": "艾瑟拉的忠告",
    "replay": "重播开场动画",
    "music": "♪ 乐章",
    "musicTitle": "音乐",
    "dayNightTitle": "日夜切换",
    "back": "返回",
    "skip": "跳过",
    "descend": "降临",
    "wheelPrev": "上一个",
    "wheelNext": "下一个",
    "wheelOk": "确认出身",
    "createTitle": "个人信息",
    "portraitCap": "立绘 · 占位",
    "popHint": "点击查看",
    "imgPending": "图片待补",
    "originLabel": "出身",
    "close": "关闭"
  },
  "create": {
    "name": "姓名",
    "namePh": "写下的角色名会自动创建user角色哦",
    "race": "种族与性别",
    "racePh": "例如：人类 / 女性",
    "appearance": "外貌设定",
    "appearancePh": "模样、气质、穿着等等……随你喜欢",
    "bio": "身世设定",
    "bioPh": "出身、来历、隐藏的过去……想填什么填什么",
    "commit": "降临"
  },
  "toasts": {
    "skipped": "已跳过开场",
    "unnamed": "未署名",
    "originPrefix": "出身",
    "descendPrefix": "已降临",
    "descending": "正在降临…",
    "profileSaved": "档案已写入世界书",
    "profileFailed": "档案写入世界书失败",
    "personaCreated": "已创建并切换用户设定",
    "personaReused": "已切换到已有用户设定",
    "personaFailed": "用户设定创建失败",
    "personaSwitchFailed": "用户设定已就绪，但自动切换失败",
    "bridgeMissing": "没找到酒馆助手桥：请开启卡内脚本「学院·API 桥」"
  }
};
