/* 文案 · 纹章图鉴（key = 纹章 id，和工坊 PATTERN_DEFS 一致）
   每条可改三样：name（全称，如「核纹·傲慢【开阖】」）/ shorthand（工坊钉子上的简称）/ brief（图鉴简介，
 换行）
   ─────────────────────────────────────────────────────────────────
   · 这里只有文字，没有任何标签；想加粗就用 **两个星号** 包住
   · 改完点「文案修改器」的保存即可；命令行党也可以跑： python tools/pack-tavern-script.py
   · 下面是 JSON：语法写错时打包会直接报错并给出行号，不会产出坏包
   ───────────────────────────────────────────────────────────────── */
window.SIGIL_TEXT = window.SIGIL_TEXT || {};
window.SIGIL_TEXT.codex = {
  "core.space": {
    "name": "核纹·傲慢【开阖】",
    "shorthand": "开阖",
    "brief": "空间性质的核纹，具有【打开空间】的效果。"
  },
  "core.still": {
    "name": "核纹·嫉妒【凝封】",
    "shorthand": "凝封",
    "brief": "静止性质的核纹，具有【降低温度】的效果。"
  },
  "core.motion": {
    "name": "核纹·愤怒【进燃】",
    "shorthand": "进燃",
    "brief": "运动性质的核纹，具有【点燃事物】的效果。"
  },
  "core.life": {
    "name": "核纹·暴食【生夺】",
    "shorthand": "生夺",
    "brief": "生命性质的核纹，具有【掠夺生机】的效果。"
  },
  "core.force": {
    "name": "核纹·懒惰【坠引】",
    "shorthand": "坠引",
    "brief": "力场性质的核纹，具有【加强重力】的效果。"
  },
  "core.build": {
    "name": "核纹·贪婪【构解】",
    "shorthand": "构解",
    "brief": "构建性质的核纹，具有【解离外形】的效果。"
  },
  "core.release": {
    "name": "核纹·色欲【释雷】",
    "shorthand": "释雷",
    "brief": "输出性质的核纹，具有【释放电能】的效果。"
  },
  "core.lust": {
    "name": "核纹·特殊【情欲】",
    "shorthand": "情欲",
    "brief": "作弊般的神秘核纹，如果你有想做的什么事情的话......"
  },
  "outer.corridor": {
    "name": "外纹·傲慢【回廊】",
    "shorthand": "回廊",
    "brief": "空间性质的外纹，具有【压缩距离】的效果。"
  },
  "outer.domain": {
    "name": "外纹·嫉妒【封界】",
    "shorthand": "封界",
    "brief": "静止性质的外纹，具有【封闭结界】的效果。"
  },
  "outer.burst": {
    "name": "外纹·愤怒【迸发】",
    "shorthand": "迸发",
    "brief": "运动性质的外纹，具有【瞬间爆发】的效果。"
  },
  "outer.flow": {
    "name": "外纹·暴食【流转】",
    "shorthand": "流转",
    "brief": "生命性质的外纹，具有【扩散循环】的效果。"
  },
  "outer.suspend": {
    "name": "外纹·懒惰【悬架】",
    "shorthand": "悬架",
    "brief": "力场性质的外纹，具有【维持稳定】的效果。"
  },
  "outer.mold": {
    "name": "外纹·贪婪【铸形】",
    "shorthand": "铸形",
    "brief": "构建性质的外纹，具有【固化造物】的效果。"
  },
  "outer.beam": {
    "name": "外纹·色欲【导束】",
    "shorthand": "导束",
    "brief": "输出性质的外纹，具有【聚束导流】的效果。"
  },
  "micro.shift": {
    "name": "缀纹·傲慢【偏折】",
    "shorthand": "偏折",
    "brief": "空间性质的缀纹，具有【修正错位】的效果。"
  },
  "micro.freeze": {
    "name": "缀纹·嫉妒【驻影】",
    "shorthand": "驻影",
    "brief": "静止性质的缀纹，具有【瞬时定格】的效果。"
  },
  "micro.shock": {
    "name": "缀纹·愤怒【震芯】",
    "shorthand": "震芯",
    "brief": "运动性质的缀纹，具有【附加震荡】的效果。"
  },
  "micro.feed": {
    "name": "缀纹·暴食【反哺】",
    "shorthand": "反哺",
    "brief": "生命性质的缀纹，具有【吸血回补】的效果。"
  },
  "micro.anchor": {
    "name": "缀纹·懒惰【重锚】",
    "shorthand": "重锚",
    "brief": "力场性质的缀纹，具有【锚定增幅】的效果。"
  },
  "micro.fuse": {
    "name": "缀纹·贪婪【嵌合】",
    "shorthand": "嵌合",
    "brief": "构建性质的缀纹，具有【复制效果】的效果。"
  },
  "micro.overload": {
    "name": "缀纹·色欲【过载】",
    "shorthand": "过载",
    "brief": "输出性质的缀纹，具有【过载超频】的效果。"
  }
};
