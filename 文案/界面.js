/* 文案 · 界面（底坞 / 工坊按钮与页签 / 状态条 / 资料库 / 地图 / 蓝图 / 存档 / 检查器 / 提示语）
   ─────────────────────────────────────────────────────────────────
   · 代码里每一处读取都带内联兜底：这条文件缺失或字段为空，页面照常。
   · 底坞按钮 / 工坊缩放钮 / 工坊页签是静态文字，改动保存后进页面即生效。
   · 提示语（msg.* / wb.*）是运行时弹出的，在「文案修改器」右树里改，不在预览里点选。
   ─────────────────────────────────────────────────────────────────
   ★★ 0926：**所有显示出来的界面文字都收进这里了**（以前有一批写死在 JS 里，
      驾驶员根本改不到）。分组按「它出现在哪」分：
        dock  底坞五个按钮          zoom  工坊右上缩放钮
        kind / kindShort  纹章三类的名字   spell / bp  蓝图与咒文条
        savedUi  工坊存档卡         insp  部件检查器
        home  状态栏               chip  状态栏那条魔力/耗用
        wb    刻印工坊             lib   资料库
        map   世界地图             rp    剧情阅读区
        msg   通用提示语           theme 昼夜按钮
   · **带 `{名字}` 的字段是模板**：`{n}` `{max}` `{c}` `{state}` `{name}` `{a}` `{b}` `{i}`
     这类占位符会被程序填上数字/名字。整句都能改（语序、标点随便），但**别把占位符删了**，
     删了那一段就会缺内容。
   · 下面是 JSON：语法写错时打包会直接报错并给出行号，不会产出坏包
   ───────────────────────────────────────────────────────────────── */
window.SIGIL_TEXT = window.SIGIL_TEXT || {};
window.SIGIL_TEXT.ui = {
  "dock": [
    {
      "page": "home",
      "label": "状态栏",
      "sub": "记载当前状态之地"
    },
    {
      "page": "workshop",
      "label": "刻印工坊",
      "sub": "拼装魔法的工作台"
    },
    {
      "page": "library",
      "label": "资料库",
      "sub": "世界档案查询"
    },
    {
      "page": "world",
      "label": "世界",
      "sub": "地图集"
    },
    {
      "page": "archive",
      "label": "档案馆",
      "sub": "大事件 · 编年史"
    }
  ],
  "wb": {
    "palette": "图案图鉴",
    "saved": "已保存",
    "effectK": "效果",
    "placing": "正在放置「{name}」：点纹章四周的菱形相连，或点空白处先放着（Esc 取消）",
    "placed": "已放在图纸上（可随时拖动）",
    "connected": "已接上",
    "portTaken": "这个连接点已经接上了",
    "noLoop": "不能连成环",
    "linked": "「{a}」已接到「{b}」",
    "linked2": "「{a}」接到「{b}」",
    "detached": "「{name}」已拖离（虚线圈=未接入，点菱形可再连）",
    "singleErase": "已单独拆除 {n} 枚",
    "scattered": "，{n} 枚延伸散落原位（可再拖去连接）",
    "lassoHint": "圈选拆除：按住鼠标，把要拆的纹章圈进去",
    "lassoDone": "已拆除圈选纹章",
    "lassoExit": "已退出圈选",
    "selected": "已选 {n} 枚",
    "blankSheet": "已铺开一张空白图纸",
    "patternCount": "{n} 个图案",
    "erasedCount": "已拆掉 {n} 个图案",
    "paletteKinds": "{n} 种",
    "metaCost": " · 耗用{n}",
    "codexCount": " · 共 {n} 种",
    "linkOtherSide": "改从这一侧出发，再点另一枚纹章四周的菱形",
    "portPicked": "已点选连接点：再点另一枚纹章四周的菱形即可连上（Esc 取消）",
    "selHint": "已选中：拖走次级纹章即可断开 · 拖顶部铜色柄旋转 · Delete 拆除",
    "dragHint": "拖到画布上松手放置「{name}」· 靠近菱形可预览连接",
    "dropConnect": "松手 → 接到「{name}」的连接点",
    "aligned": "对准了连接点 → 点击菱形即可接上",
    "acquired": "获得【{name}】",
    "skipAnywhere": "点击任意处跳过"
  },
  "zoom": {
    "burn": "激活",
    "erase": "删除",
    "in": "放大",
    "out": "缩小",
    "codex": "图鉴",
    "coach": "教程"
  },
  "kind": {
    "core": "核纹",
    "outer": "外纹",
    "micro": "缀纹"
  },
  "kindShort": {
    "core": "核",
    "outer": "外",
    "micro": "缀"
  },
  "spell": {
    "k1": "刻印",
    "k2": "载体",
    "k3": "纹章",
    "k4": "耗用",
    "none": "未指定",
    "unnamed": "未命名"
  },
  "bp": {
    "name": "【刻印】",
    "carrier": "【载体】",
    "parts": "【纹章】",
    "cost": "【耗用】",
    "countPrefix": "共 ",
    "countSuffix": " 枚",
    "noCircuit": "（未成回路）",
    "effect": "玩家编写效果：",
    "effectNone": "（未填写）"
  },
  "savedUi": {
    "edit": "编辑",
    "del": "删除",
    "delConfirm": "确认删除",
    "empty": "还没有保存的魔法",
    "noCarrier": "未指定载体"
  },
  "insp": {
    "rotL": "左转 45°",
    "rotR": "右转 45°",
    "delOne": "只拆这枚",
    "anchor": "阵眼（整座符印的中心）",
    "loose": "散件（未接入）"
  },
  "figure": {
    "upload": "上传本地图片",
    "reset": "恢复默认立绘",
    "saving": "正在压缩这张图…",
    "bad": "这不是能用的图片文件，换一张试试",
    "full": "浏览器本地空间满了，这张存不下 —— 换张小一点的图，或先给别的自建角色恢复默认",
    "blocked": "这个界面不让存本地数据（浏览器隐私设置 / 嵌入限制），立绘存不下来",
    "done": "已换上「{name}」的立绘。这张图只存在你本机，不进存档、不上传、AI 也看不见。",
    "resetOk": "已恢复「{name}」的默认立绘"
  },
  "shop": {
    "btn": "上传",
    "title": "上传到荧荧工坊",
    "sub": "刻印分享",
    "warn": "⚠ 内容公开可见，请勿上传违规或侵权内容。",
    "kTitle": "魔法名称",
    "kDesc": "效果描述",
    "kPack": "刻印数据",
    "note": "",
    "submit": "发布到工坊",
    "login": "Discord 登录",
    "logout": "退出登录",
    "loggedIn": "已登录",
    "admin": " · 管理员",
    "needLogin": "发布前请先登录 Discord 账号",
    "needLogin2": "请先登录再发布",
    "loggingIn": "正在打开授权页面…",
    "loginTimeout": "登录超时，请重试",
    "loginOk": "已登录：",
    "loginFail": "登录失败：",
    "popBlocked": "登录弹窗被浏览器拦截，请允许弹窗后重试",
    "expired": "登录已失效，请重新登录",
    "unnamed": "未命名符印",
    "packEmpty": "当前刻印为空，请先绘制符印",
    "packTail": " 枚纹章 · 耗用 ",
    "packCarrier": "载体：",
    "noTitle": "请输入魔法名称",
    "uploading": "正在发布…",
    "done": "发布成功！「",
    "doneTail": "」已分享至工坊",
    "toastDone": "发布成功",
    "fail": "发布失败：",
    "netFail": "网络连接失败，请检查网络后重试"
  },
  "home": {
    "plotHead": "当前剧情事件",
    "noMagic": "暂无可用魔法——等 AI 把魔法写进「主角组 · 魔法」变量后，这里会自动出现。",
    "noChars": "暂无角色档案——角色登场后会自动建立。",
    "figureSuffix": " · 立绘",
    "noteName": "艾瑟拉",
    "timeDefault": "院历 · 暮秋 · 夜",
    "placeDefault": "中央学院 · 刻印工坊"
  },
  "chip": {
    "line": "魔力 {n}/{max} · 耗用 {c} · {state}{loose}",
    "can": "可施放",
    "cannot": "魔力不足",
    "loose": " · 散件 {n}"
  },
  "lib": {
    "empty": "没有符合条件的资料",
    "viewBig": "点击查看大图",
    "figureWord": "立绘",
    "countSuffix": " 条"
  },
  "map": {
    "title": "艾瑟拉",
    "detailTitle": "实体详图",
    "worldTitle": "世界大图",
    "detailSuffix": "详图",
    "backWorld": "← 返回世界",
    "hintLayers": "地名与标记为独立图层 · 拖动平移 · 滚轮或双指缩放",
    "hintMarks": "点标记查看档案 · 拖动平移 · 滚轮或双指缩放",
    "dropMode": "落针模式：在地图上点击放置标记（再点按钮退出）",
    "editMark": "编辑标记",
    "storageWarn": "⚠ 浏览器标记存储不可用（隐私模式？）——请用「导出」按钮备份你的标记！",
    "zoomIn": "放大地图",
    "zoomOut": "缩小地图",
    "zoomFit": "恢复全览"
  },
  "rp": {
    "pageOf": "第 {i} 页 / 共 {n} 页",
    "next": "下一页",
    "done": "完成"
  },
  "msg": {
    "emptyDraft": "图纸是空的。先放一枚核心，别的以后再说。",
    "noCore": "没有核心的符印只是花纹。放一枚核心进来，魔力才知道从哪里出发。",
    "orphan": "孤悬的零件不成回路。点四周的菱形把纹章连起来，魔力才有路可走。",
    "dragging": "拖动中",
    "draggingLong": "拖动中…",
    "activatedPrefix": "激活完成：耗用 ",
    "savedTail": " · 已保存",
    "filledTail": " · 咒文已填入对话框",
    "cancelPlace": "已取消放置",
    "cancelLink": "已取消连接"
  },
  "theme": {
    "day": "昼",
    "night": "夜"
  }
};
