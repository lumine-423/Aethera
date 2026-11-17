/* 文案 · 立绘（角色 / 国家 / 地区 的图片网链）
   ─────────────────────────────────────────────────────────────────
   · 这里**只有图片路径**，没有文字；改图 = 换一行 URL，不用碰代码。
   · 角色按**形态**分组：默认「日常」，变量 `角色组.<角色名>.当前形态` 写成「解放」
     就显示解放立绘；**没有解放形态的角色只写「日常」一项**（写了别的形态也退回日常）。
   · ★ 1004j 新增**可选**的 `色情` 键：写了它 = 这个角色有**真·色情立绘**，
     悬浮窗「色情立绘」板块的第 1 张就是它（图集里的色图跟在它后面）；
     **不写就表示还没有色情立绘** —— 那时「色情立绘」板块才会退回玫红占位图。
     例：  "凛零": { "日常": "…", "解放": "…", "色情": "https://…/lin-ling-se.png" }
     ⚠ 只要板块里有真图（真·色情立绘 **或** 图集里的色图），占位图就一定不会出现。
   · ★ 1012 新增 **`npcs` 组**：**次要角色（NPC）** —— 一个名字**只有一张图**，直接写字符串。
     没有 日常 / 解放 形态、也**没有色情立绘**（状态栏不会出「色情立绘」占位板，
     也不出 当前形态 / 好感度 / 色情值）。**只进状态栏**（角色组建档后出现）、**不进资料库**。
     例：  "npcs": { "维克托": "https://…/wei-ke-tuo.png" }
     ★ 名字必须与 **世界书 `NPC角色速览`** 里的名字逐字一致（AI 按那份写 `角色组`）。
   · 国家 / 地区是单张图，直接写字符串。
   · 对话气泡里的**头像**不在这里 —— 它在 regex/dialogue.html（那份模板会被
     tools/patch-card-mes-skin.py 同步进卡，是那条链路的唯一源头）。
   · 改完在仓库根目录跑一次：  python tools/pack-tavern-script.py
   · ⚠ 图片走网链，页面不报错但图不显示 = 网链失效。打包器会校验 URL 格式与数量。
   ───────────────────────────────────────────────────────────────── */
window.SIGIL_TEXT = window.SIGIL_TEXT || {};
window.SIGIL_TEXT.portraits = {
  "characters": {
    "凛零": {
      "日常": "https://i.postimg.cc/ZY2Hb2pd/lin-ling.png",
      "解放": "https://i.postimg.cc/VspgfpnR/lin-ling-jie-fang.png"
    },
    "梅林": {
      "日常": "https://i.postimg.cc/nVCTtpjZ/mei-lin.png",
      "解放": "https://i.postimg.cc/PfPKkTpd/mei-lin-jie-fang.png"
    },
    "墨华": {
      "日常": "https://i.postimg.cc/MXJKH9Kw/mo-hua.png",
      "解放": "https://i.postimg.cc/BtfQbmQ4/mo-hua-jie-fang.png"
    },
    "冰糖": {
      "日常": "https://i.postimg.cc/xC7dD0wL/bing-tang.png",
      "解放": "https://i.postimg.cc/j59j0spM/bing-tang-jie-fang.png"
    },
    "安克": {
      "日常": "https://i.postimg.cc/K8r4khT2/an-ke.png",
      "解放": "https://i.postimg.cc/BnctLfF8/an-ke-jie-fang.png"
    },
    "茧": {
      "日常": "https://i.postimg.cc/Qx7FDTx1/jian.png",
      "解放": "https://i.postimg.cc/4NcYG9Np/jian-jie-fang.png"
    },
    "卡斯特": {
      "日常": "https://i.postimg.cc/xCFXfGzx/ka-si-te.png",
      "解放": "https://i.postimg.cc/WzFhhDG0/ka-si-te-jie-fang.png"
    },
    "明空": {
      "日常": "https://i.postimg.cc/LX0J9k1J/ming-kong.png"
    },
    "叶": {
      "日常": "https://i.postimg.cc/RF03xpNq/ye.png"
    },
    "艾利丝": {
      "日常": "https://i.postimg.cc/rmpd2ZKL/ai-li-si.png"
    },
    "路西法": {
      "日常": "https://i.postimg.cc/pdRhqLvJ/lu-xi-fa.png"
    },
    "暧": {
      "日常": "https://i.postimg.cc/K8n3Pgdd/ai.png"
    },
    "瓦尔基里": {
      "日常": "https://i.postimg.cc/kgrtRyhD/wa-er-ji-li.png"
    },
    "阿兰雅": {
      "日常": "https://i.postimg.cc/WbxGJMSg/a-lan-ya.png"
    },
    "筏摩娜": {
      "日常": "https://i.postimg.cc/g2qxkR7Y/fa-mo-na.png"
    },
    "轩辕": {
      "日常": "https://i.postimg.cc/9MqwdfbY/xuan-yuan.png"
    },
    "焰渊": {
      "日常": "https://i.postimg.cc/XNk7TFr9/yan-yuan.png"
    },
    "拉伦提娅": {
      "日常": "https://i.postimg.cc/C5gSQRsP/la-lun-ti-ya.png"
    },
    "阳向": {
      "日常": "https://i.postimg.cc/5tzcWx0h/yang-xiang.png"
    },
    "露珐": {
      "日常": "https://i.postimg.cc/RZnpNgB0/lu-fa.png"
    },
    "瓦沙克": {
      "日常": "https://i.postimg.cc/C5zH9KMm/wa-sha-ke.png"
    }
  },
  "npcs": {
    "埃德加·考文垂": "https://i.postimg.cc/W1JPTLF1/ai-de-jia-kao-wen-chui.png",
    "维克托": "https://i.postimg.cc/9f5Hf8Z9/wei-ke-tuo.png",
    "德拉戈": "https://i.postimg.cc/8zrVNQJQ/de-la-gong.png",
    "缇雅": "https://i.postimg.cc/L8ZM2KYS/ti-ya.png",
    "小艾": "https://i.postimg.cc/13NZshnR/xiao-ai.png",
    "瓦尔莎": "https://i.postimg.cc/xT67rFfT/wa-er-sha.png",
    "佐藤澄": "https://i.postimg.cc/Jz2mW6Qp/zuo-teng-cheng.png",
    "索拉努": "https://i.postimg.cc/9fw2XdxN/suo-la-nu.png" 
  },
  "places": {
    "塞蕾特公国": "https://i.postimg.cc/kgVfqwRb/sai-lei-te-gong-guo.png",
    "卡米洛特宫": "https://i.postimg.cc/Fz9Tv40g/ka-mi-luo-te-gong.png",
    "中央学院": "https://i.postimg.cc/W1QS3r0B/zhong-yang-xue-yuan.png",
    "尼德霍格区": "https://i.postimg.cc/VsR7RJcb/ni-de-huo-ge-qu.png",
    "龙渊帝国": "https://i.postimg.cc/xjRsRXSc/long-yuan-di-guo.png",
    "紫宸宫": "https://i.postimg.cc/KYBfgzNg/zi-chen-gong.png",
    "灵山": "https://i.postimg.cc/Y23X3vwS/ling-shan.png",
    "吉万沙克蒂": "https://i.postimg.cc/x1ktngNM/xu-mi-wang-ting.png",
    "须弥王庭": "https://i.postimg.cc/7hmmYWNJ/ji-wan-sha-ke-di.png",
    "塞建陀砦": "https://i.postimg.cc/SxXDkVYY/sai-jian-tuo-zhai.png",
    "堤丰之喉": "https://i.postimg.cc/x8T37PSn/di-feng-zhi-hou.png",
    "奥马努特": "https://i.postimg.cc/tTb5djSf/ao-ma-nu-te.png",
    "地下市场": "https://i.postimg.cc/XJggQzmD/de-xia-shi-chang.png",
    "齐哈特大沙漠": "https://i.postimg.cc/bw2HKJ4T/qi-ha-te-da-sha-mo.png",
    "格洛里亚": "https://i.postimg.cc/sxwwDNJQ/ge-luo-li-ya.png",
    "库利亚": "https://i.postimg.cc/XqQQ7zgT/ku-li-ya.png",
    "哥塔薇亚帝国": "https://i.postimg.cc/90FYSBjf/ge-ta-wei-ya-di-guo.png",
    "基捷日": "https://i.postimg.cc/j2sMTbyz/ji-jie-ri.png",
    "阿拉提尔": "https://i.postimg.cc/CKk7f1NB/a-la-ti-er.png",
    "秋津国": "https://i.postimg.cc/RVpXk2hf/qiu-jin-guo.png",
    "云樱": "https://i.postimg.cc/jSWZtvnX/yun-ying.png",
    "梵音林": "https://i.postimg.cc/rmpQM5qZ/fan-yin-lin.png",
    "天国岛": "https://i.postimg.cc/pTdqRKP6/tian-guo-dao.png"
  }
};
