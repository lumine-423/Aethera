# -*- coding: utf-8 -*-
"""
红线自查：预设里不许出现任何角色卡专属数据。
只读，不改文件。跑法：python F:/sigil-circuit/preset/check_leak.py [预设路径]
报告写 F:/sigil-circuit/preset/_leak.log，命中就 exit 1。

为什么要有这个脚本：
    用户立过红线——预设是独立产品，角色卡（含世界书）只是参考。
    预设里一旦混进某张卡的人名、曲名、术语、变量路径，这套预设就绑死在那张卡上，
    换一张卡就会拿着一张卡的数据去污染另一张卡。
    
为什么不能简单子串匹配：
    角色「暧」是单字，会命中常用词「暧昧」。
    所以单字名要检查"它是否作为独立词出现"，不是纯子串。
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PRESET = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "白描回廊 v1.0.json")
LOG = os.path.join(HERE, "_leak.log")

# ---- 专属数据清单 ----
# 1) 角色卡的人名（13 人正册）
NAMES = ["凛零", "梅林", "墨华", "冰糖", "安克", "茧", "卡斯特",
         "明空", "叶", "艾利丝", "路西法", "暧", "瓦尔基里"]
# 2) 卡名本身
CARD = ["艾瑟拉", "埃德加"]
# 3) 卡专属 BGM 曲名（14 条）
TRACKS = ["Main Theme", "Frozen World", "degree45", "luminous", "Harmonious",
          "Humidity", "皇家萌卫", "Everlasting Dirge", "Seaside Town",
          "Combat Beneath the Waves", "Windborne Hymn", "Cabrito Park",
          "Goat Chill", "Good Morning"]
# 4) 卡的世界观术语
TERMS = ["刻印", "核纹", "缀纹", "外纹", "纹章", "载体", "魔力", "同调",
         "塞蕾特", "中央学院", "公纪", "七十二柱", "魔物图鉴", "异危",
         "奇美拉", "巴蛇", "塔阿贝特", "海坊主"]
# 5) 变量路径与字段名
PATHS = ["stat_data", "主角组", "角色组", "剧情事件", "当前BGM", "当前形态",
         "已解锁性癖", "好感度", "色情值", "当前在场角色", "持有物品",
         "已讨伐异危", "已完成事件", "当前触发事件", "UpdateVariable", "JSONPatch"]

# 单字名/单字词会被常用词误命中，这里给白名单：命中这些词时不算
FALSE_POSITIVES = {
    "暧": ["暧昧"],
    "叶": ["叶子", "树叶", "叶片", "一叶", "中叶", "末叶", "叶脉"],
    "茧": ["蚕茧", "茧子", "作茧"],  # 「茧」本身通常就是角色名，但先留着
}

lines = []
hits = []

raw = open(PRESET, encoding="utf-8").read()
try:
    d = json.loads(raw)
except Exception as e:
    open(LOG, "w", encoding="utf-8").write("[FAIL] JSON 解析失败: %s\n" % e)
    raise SystemExit(1)

prompts = d.get("prompts") or []
lines.append("预设文件: %s" % PRESET)
lines.append("检查条目: %d 条" % len(prompts))


def scan(term, kind):
    """扫一个词。单字词走白名单规避。"""
    allow = FALSE_POSITIVES.get(term, [])
    for p in prompts:
        c = p.get("content") or ""
        if term not in c:
            continue
        if not allow:
            for m in re.finditer(re.escape(term), c):
                ctx = c[max(0, m.start() - 10): m.start() + len(term) + 10].replace("\n", " ")
                hits.append((p.get("identifier"), kind, term, ctx))
            continue
        # 单字：逐个命中点检查是否落在白名单词里
        for m in re.finditer(re.escape(term), c):
            s, e = m.start(), m.end()
            covered = False
            for w in allow:
                idx = w.find(term)
                if idx < 0:
                    continue
                ws = s - idx
                we = ws + len(w)
                if ws >= 0 and we <= len(c) and c[ws:we] == w:
                    covered = True
                    break
            if covered:
                continue
            ctx = c[max(0, s - 10): e + 10].replace("\n", " ")
            hits.append((p.get("identifier"), kind, term, ctx))


for t in NAMES:
    scan(t, "角色名")
for t in CARD:
    scan(t, "卡名")
for t in TRACKS:
    scan(t, "BGM曲名")
for t in TERMS:
    scan(t, "世界观术语")
for t in PATHS:
    scan(t, "变量路径/字段")

lines.append("")
if hits:
    lines.append("[LEAK] 命中 %d 处：" % len(hits))
    for ident, kind, term, ctx in hits:
        lines.append("  - [%s] %s 在 %s：…%s…" % (kind, term, ident, ctx))
    lines.append("")
    lines.append("结论：红线被破，必须删除这些内容")
    code = 1
else:
    lines.append("OK 红线自查通过：%d 个角色名 + %d 个卡名 + %d 个曲名 + %d 个术语 + %d 个字段名，全部 0 命中"
                 % (len(NAMES), len(CARD), len(TRACKS), len(TERMS), len(PATHS)))
    lines.append("")
    lines.append("结论：通过")
    code = 0

open(LOG, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("leak check: %d hits" % len(hits))
raise SystemExit(code)
