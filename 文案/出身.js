/* 文案 · 出身（**只喂「出身选择」这一页**）
   ─────────────────────────────────────────────────────────────────
   ★★★ 0926b2：**一个显示点 = 一个字段，绝不共用**。
     以前「转盘卡上的名字 / 卡下方那行名字 / 弹窗标题」共用 `name`，
     「卡下方简介 / 弹窗简介」共用 `desc` —— 那就是**捆绑文案**：
     你在弹窗里改简介，转盘下面那行跟着一起变；想「卡上写短的、弹窗写长的」根本做不到。
     现在每个显示点都有自己的字段（**默认值都填成一样的**，所以看上去没变化，
     但改哪个就只动哪个）。下面这张表就是「哪个字段出现在哪」：
   ─────────────────────────────────────────────────────────────────
   字段          出现在哪
   ───────────  ────────────────────────────────────────────────────
   key          **内部标识**（写进世界书档案、切开场白用）。⚠ 别改
   name         **正式名**：写进世界书档案的那份、降临提示语里那个名字。
                不是任何画面上的字 —— 画面上的字看下面几个字段
   wheelName    转盘**卡片上**的名字（大号那个）
   wheelSeal    转盘**卡片上**的水印大字
   accent       转盘卡片描边/光晕 + 弹窗标签色的**配色**（十六进制）
                ⚠ 这是**设计变量**不是文案：卡和弹窗共用一个主题色才好看
   listName     转盘**下方**那行名字
   listDesc     转盘**下方**那行简介（空间小，建议短句）
   popName      详情弹窗的**标题**
   popSeal      详情弹窗的**占位印章**（没填 img 时显示的那个大字）
   popTag       详情弹窗名字下面那行**小标签**
   popDesc      详情弹窗的**简介**（空间大，可以写长）
   img          详情弹窗的**大图**：网链 https://… 或本地相对路径
                `文案/引导图/xx.png`；**留空 = 显示占位印章 + 「图片待补」**
   formName     个人信息页「出身 · X」那一行用的名字
   ─────────────────────────────────────────────────────────────────
   · 数组顺序 = **出身顺序** = 开场白 swipe 顺序（第 1 条 → swipe1）。
     想调顺序用「文案修改器」里每项右上角的 ↑ / ↓，别手改数字。
   · ⚠ 这一页**只喂出身页**。忠告「一点谜语人」有它自己的文案，在 `文案/忠告.js` 里。
   · 改完在仓库根目录跑一次：  python tools/pack-tavern-script.py
   · 也可以用「文案修改器」图形化改： python -m http.server 8777
     → 浏览器打开 http://127.0.0.1:8777/tools/文案修改器.html
   · 下面是 JSON：语法写错时打包会直接报错并给出行号，不会产出坏包
   ───────────────────────────────────────────────────────────────── */
window.SIGIL_TEXT = window.SIGIL_TEXT || {};
window.SIGIL_TEXT.origins = [
  {
    "key": "sereth",
    "name": "塞蕾特公国",
    "wheelName": "塞蕾特公国",
    "wheelSeal": "塞",
    "accent": "#9a6b35",
    "listName": "塞蕾特公国",
    "listDesc": "拥有最先进，最全面的刻印产品，最一流的学术研究场所，或许也是一切故事的发源地。",
    "popName": "塞蕾特公国",
    "popSeal": "塞",
    "popTag": "一切起源之地",
    "popDesc": "你将作为中央学院二年级学生，从学院开启你的邂逅之旅，试着从一切的起点开始探索这个世界吧。",
    "img": "https://i.postimg.cc/kgVfqwRb/sai-lei-te-gong-guo.png",
    "formName": "塞蕾特公国"
  },
  {
    "key": "staff",
    "name": "蛇杖",
    "wheelName": "蛇杖",
    "wheelSeal": "秘",
    "accent": "#46605c",
    "listName": "蛇杖",
    "listDesc": "足迹遍布世界、目的不明的庞大组织。你将作为其塞蕾特公国分部的一员，逐步发掘这个组织的秘密...",
    "popName": "蛇杖",
    "popSeal": "杖",
    "popTag": "处处是谜的组织",
    "popDesc": "你将作为塞蕾特公国蛇杖分部的成员，从这个组织的内部探究它的秘密，或许你能从不一样的角度看到与众不同的秘密。",
    "img": "https://i.postimg.cc/CMBd0CCm/she-zhang.png",
    "formName": "蛇杖"
  },
  {
    "key": "omanut",
    "name": "奥马努特",
    "wheelName": "奥马努特",
    "wheelSeal": "艺",
    "accent": "#c8a8e8",
    "listName": "奥马努特",
    "listDesc": "你将作为一位旅客参观这个艺术圣地，但或许，这样一处歌舞升平之地也潜藏着危机......",
    "popName": "奥马努特",
    "popSeal": "艺",
    "popTag": "艺术辉煌之国",
    "popDesc": "你将作为一位旅客参观这个艺术圣地，但或许，这样一处歌舞升平之地也潜藏着危机......",
    "img": "https://i.postimg.cc/tTb5djSf/ao-ma-nu-te.png",
    "formName": "奥马努特"
  },
  {
    "key": "jwanshakti",
    "name": "吉万沙克蒂",
    "wheelName": "吉万沙克蒂",
    "wheelSeal": "吉",
    "accent": "#3f7a5a",
    "listName": "吉万沙克蒂",
    "listDesc": "你将作为新到来访客，暂居到须弥王庭的城镇上，这个千年来几乎不曾大变样的国家，或许能因为你的到来而有新的生机。",
    "popName": "吉万沙克蒂",
    "popSeal": "吉",
    "popTag": "雨林中的王国",
    "popDesc": "你将作为新到来访客，暂居到须弥王庭的城镇上，这个千年来几乎不曾大变样的国家，或许能因为你的到来而有新的生机。",
    "img": "https://i.postimg.cc/x1ktngNM/xu-mi-wang-ting.png",
    "formName": "吉万沙克蒂"
  },
  {
    "key": "longyuan",
    "name": "龙渊帝国",
    "wheelName": "龙渊帝国",
    "wheelSeal": "龙",
    "accent": "#7a3f3f",
    "listName": "龙渊帝国",
    "listDesc": "你是新进入紫宸宫的奇才，四大家系的人为此都在抢夺你，不过你倒不必慌张，因为你的选择还很多嘛。",
    "popName": "龙渊帝国",
    "popSeal": "龙",
    "popTag": "武道盛行之国",
    "popDesc": "你是新进入紫宸宫的奇才，四大家系的人为此都在抢夺你，不过你倒不必慌张，因为你的选择还很多嘛。",
    "img": "https://i.postimg.cc/xjRsRXSc/long-yuan-di-guo.png",
    "formName": "龙渊帝国"
  },
  {
    "key": "gloria",
    "name": "格洛里亚",
    "wheelName": "格洛里亚",
    "wheelSeal": "格",
    "accent": "#b5512f",
    "listName": "格洛里亚",
    "listDesc": "你将作为误入灼热战场的旅者，在魔物肆虐的险境中见证百年抗战的铁与火。",
    "popName": "格洛里亚",
    "popSeal": "格",
    "popTag": "战火与熔岩之国",
    "popDesc": "与发狂赤龙交战逾百年的铁血之邦。你将从险象环生的堤丰之喉战场踏入这个国家，在时空列车撕裂虚空的轰鸣中开启旅程，结识坚韧的战士与古老的守护者。",
    "img": "https://i.postimg.cc/sxwwDNJQ/ge-luo-li-ya.png",
    "formName": "格洛里亚"
  },
  {
    "key": "akitsu",
    "name": "秋津国",
    "wheelName": "秋津国",
    "wheelSeal": "秋",
    "accent": "#8f4a6a",
    "listName": "秋津国",
    "listDesc": "你将作为初涉云樱的异乡旅人，因一场啼笑皆非的街头误会踏上前往佐藤家首府的道路。",
    "popName": "秋津国",
    "popSeal": "秋",
    "popTag": "樱花与剑道之岛",
    "popDesc": "依山面海、幕府掌政的武艺之邦。你将漫步于繁樱盛开的云樱城下町，在与某位心高气傲的剑道少年发生意外冲突后，卷入世家权力与剑道宿命的漩涡。",
    "img": "https://i.postimg.cc/RVpXk2hf/qiu-jin-guo.png",
    "formName": "秋津国"
  },
  {
    "key": "custom",
    "name": "自定义",
    "wheelName": "自定义",
    "wheelSeal": "自",
    "accent": "#24919f",
    "listName": "自定义",
    "listDesc": "据说神明喜爱自由的流星，因为它们不受规则的束缚。",
    "popName": "自定义",
    "popSeal": "自",
    "popTag": "众星璀璨之时",
    "popDesc": "自由的你可以在这个世界的任何地方探索，或许会因此错过一些羁绊，但至少你有了自由，不是吗？",
    "img": "https://i.postimg.cc/6qyktM5c/ai-se-la.png",
    "formName": "自定义"
  }
];
