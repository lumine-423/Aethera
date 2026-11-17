#!/usr/bin/env python3
"""从艾瑟拉原卡文案、8个开场白与完整世界书构建游戏完整版数据 JSON。

用法：
    python f:/sigil-circuit/rolecard-rpg/tools/build_full_content.py
输出：
    - f:/sigil-circuit/rolecard-rpg/data/content/contest_content.json  (edition="full")
    - f:/sigil-circuit/rolecard-rpg/data/content/worldbook_full.json
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]  # f:\sigil-circuit
RPG = Path(__file__).resolve().parents[1]   # f:\sigil-circuit\rolecard-rpg
WENAN = ROOT / "文案"
OPENINGS = ROOT / "开场白"
WORLDBOOK = ROOT / "worldbook"
REGEX_RX0 = ROOT / "_live-card" / "regex" / "RX0-普通版·开局界面（请勿和艾瑟拉前端同时开启）.replaceString.txt"
OUT = RPG / "data" / "content"

# 完整版 21 名主要角色（按角色库顺序，id -> 中文名）
CAST = {
    "rin": "凛零",
    "merlin": "梅林",
    "mohua": "墨华",
    "bingtang": "冰糖",
    "anke": "安克",
    "castor": "卡斯特",
    "jian": "茧",
    "mingkong": "明空",
    "alice": "艾利丝",
    "lucifer": "路西法",
    "ai": "暧",
    "ye": "叶",
    "valkyrie": "瓦尔基里",
    "alanya": "阿兰雅",
    "vamana": "筏摩娜",
    "xuanyuan": "轩辕",
    "yanyuan": "焰渊",
    "larentia": "拉伦提娅",
    "yangxiang": "阳向",
    "lufa": "露珐",
    "washake": "瓦沙克",
}

# 8 名重要 NPC 中文名 -> id
NPC_IDS = {
    "埃德加·考文垂": "edgar",
    "维克托": "victor",
    "德拉戈": "drago",
    "缇雅": "tiya",
    "小艾": "xiaoai",
    "瓦尔莎": "varsha",
    "佐藤澄": "satou",
    "索拉努": "solanu",
}

# 出身 key -> (开场白编号 1..8, 预览场景ID, 初始开场<场景>标签)
ORIGIN_MAP = {
    "sereth": (1, "ACA01", "中央学院·校舍长廊"),
    "staff": (2, "SER01", "公国蛇杖分部·资料禁区入口／走廊"),
    "omanut": (3, "ART00", "首府奥马努特·主城海滨水城全景"),
    "jwanshakti": (4, "JIV00", "须弥王庭·树冠主城全景"),
    "longyuan": (5, "LON00", "帝都紫宸·主城宫阙与放射大道全景"),
    "gloria": (6, "GLO00", "堤丰之喉·琉璃山体登山道"),
    "akitsu": (7, "AKI00", "云樱·石阶樱树与城下町"),
    "custom": (8, "PAL01", "卡米洛特宫·白石宫门与外庭"),
}

EXPRESSIONS = [
    ["neutral", "平静"],
    ["smile", "微笑"],
    ["speaking", "说话"],
    ["puzzled", "疑惑"],
    ["surprised", "惊讶"],
    ["bashful", "害羞"],
    ["angry", "生气"],
    ["sad", "难过"],
    ["disgust", "嫌弃"],
    ["star-eyes", "星星眼"],
]

EXTRA_EVENTS_ORDER = [
    ("剑与秤的盟约", "postwar", "org", "1015年", "龙渊帝国 · 紫宸宫"),
    ("止水与烈风", "postwar", "person", "1015年·4月1日之前", "格洛里亚"),
    ("自灰烬中归来", "postwar", "dragon", "不限", "格洛里亚 · 堤丰之喉"),
    ("落樱与锈刃", "postwar", "person", "不限", "秋津国 · 云樱"),
    ("衔尾之蛇", "postwar", "org", "不限", "塞蕾特公国（千年前）"),
    ("钟摆停驻之日", "postwar", "awaken", "不限", "不限（当前剧情所在地点）"),
]


def load_js(name: str) -> dict:
    t = (WENAN / f"{name}.js").read_text("utf8")
    out = {}
    for m in re.finditer(r"window\.SIGIL_TEXT\.(\w+)\s*=\s*", t):
        val, _ = json.JSONDecoder().raw_decode(t[m.end():])
        out[m.group(1)] = val
    return out


def parse_initvar(raw: str) -> dict:
    """容错解析开场白中的 <initvar> 块（兼容 `{事件名}` 这种 MVU 集合语法）。"""
    import yaml

    def normalize_braces(line: str) -> str:
        m = re.match(r"^(\s*当前触发事件)\s*:\s*\{([^}]*)\}\s*$", line)
        if m:
            inner = m.group(2).strip()
            if not inner:
                return m.group(1) + ": {}"
            items = [x.strip() for x in re.split(r"[、,，]", inner) if x.strip()]
            return m.group(1) + ": " + json.dumps({x: "进行中" for x in items}, ensure_ascii=False)
        return line

    cleaned_lines = []
    for ln in raw.splitlines():
        if not ln.strip():
            continue
        cleaned_lines.append(normalize_braces(ln))
    data = yaml.safe_load("\n".join(cleaned_lines)) or {}
    # 保证 剧情事件.当前触发事件 是 Dictionary
    ev = data.setdefault("剧情事件", {})
    if not isinstance(ev, dict):
        data["剧情事件"] = {"当前触发事件": {}, "已完成事件": []}
    else:
        cur = ev.get("当前触发事件")
        if cur is None:
            ev["当前触发事件"] = {}
        elif isinstance(cur, set):
            ev["当前触发事件"] = {str(k): "进行中" for k in cur}
        elif isinstance(cur, list):
            ev["当前触发事件"] = {str(k): "进行中" for k in cur}
        if not isinstance(ev.get("已完成事件"), list):
            ev["已完成事件"] = []
    # 确保角色组是字典
    if not isinstance(data.get("角色组"), dict):
        data["角色组"] = {}
    return data


def parse_npcs() -> list[dict]:
    txt = (WORLDBOOK / "NPC角色速览.txt").read_text("utf8")
    m = re.search(r"<NPC角色速览>\s*(.*?)\s*</NPC角色速览>", txt, flags=re.S)
    inner = m.group(1) if m else txt
    blocks = [b.strip() for b in re.split(r"\n\s*\n", inner) if b.strip()]
    npcs = []
    for blk in blocks:
        lines = blk.splitlines()
        name = lines[0].rstrip(":： ").strip()
        nid = NPC_IDS.get(name, f"npc_{len(npcs)+1}")
        where = ""
        intro = ""
        look = ""
        figure = ""
        special = ""
        mode = ""
        for ln in lines[1:]:
            s = ln.strip()
            if s.startswith("邂逅条件:"):
                where = s.split(":", 1)[1].strip(); mode = ""
            elif s.startswith("简介:"):
                intro = s.split(":", 1)[1].strip(); mode = ""
            elif s.startswith("形态:"):
                mode = "look"
            elif s.startswith("身材:"):
                figure = s.split(":", 1)[1].strip(); mode = ""
            elif s.startswith("特殊要求"):
                special = s.split("：", 1)[-1].split(":", 1)[-1].strip(); mode = ""
            elif mode == "look" and s.startswith("-"):
                look += ("" if not look else "\n") + s.lstrip("- ").strip()
        fields = [
            ["定位", "重要 NPC"],
            ["邂逅条件", where or "随剧情探索偶遇"],
        ]
        if figure:
            fields.append(["身材", figure])
        body_parts = [p for p in [intro, f"【外貌服饰】\n{look}" if look else "", f"【演绎备注】\n{special}" if special else ""] if p]
        npcs.append({
            "id": nid,
            "type": "character",
            "imgKind": "figure",
            "is_npc": True,
            "title": name,
            "name": name,
            "colors": ["#7e7a8a", "#3f3c4a"],
            "fields": fields,
            "body": "\n\n".join(body_parts),
        })
    return npcs


def parse_extra_event(name: str, era: str, cat: str, date_str: str, place: str, idx: int) -> dict:
    raw = (WORLDBOOK / "剧情事件" / f"{name}.txt").read_text("utf8").strip()
    def extract_field(label: str) -> str:
        pat = rf"^\s*{re.escape(label)}\s*[:：]\s*(.+)$"
        hit = re.search(pat, raw, flags=re.M)
        return hit.group(1).strip() if hit else ""

    who_str = extract_field("相关角色")
    who = []
    if who_str:
        for w in re.split(r"[、,，]", who_str):
            w = re.sub(r"[（(][^）)]*[）)]", "", w).strip()
            if w and w not in who:
                who.append(w)

    brief = extract_field("事件概况")
    opening = extract_field("开局事件")
    cond_place = extract_field("当前地点")
    cond_plot = extract_field("剧情条件")
    cond_time = extract_field("时间条件")

    impact_parts = []
    if cond_place:
        impact_parts.append(cond_place)
    if cond_plot:
        impact_parts.append(cond_plot)
    if cond_time and cond_time != "无":
        impact_parts.append("时间：" + cond_time)
    impact = "；".join(impact_parts) if impact_parts else "详见剧情事件规则"

    # 提取完成条件和关键情节段
    comp_m = re.search(r"事件完成条件\s*[:：]\s*\n((?:\s*[-·].*\n?)+)", raw)
    comp_txt = ""
    if comp_m:
        comp_txt = "\n".join("· " + x.strip().lstrip("-· ") for x in comp_m.group(1).splitlines() if x.strip())

    detail_parts = []
    if brief:
        detail_parts.append(brief)
    if opening:
        detail_parts.append("【开局事件】\n" + opening)
    if comp_txt:
        detail_parts.append("【完成条件】\n" + comp_txt)

    return {
        "id": str(idx),
        "era": era,
        "cat": cat,
        "date": date_str,
        "status": "soon",
        "title": name,
        "place": place,
        "who": who or ["无"],
        "brief": brief or opening,
        "detail": "\n\n".join(detail_parts) or raw,
        "impact": impact,
        "links": [],
    }


def load_worldbook_full() -> dict:
    """将 f:/sigil-circuit/worldbook 下的全量条目按 9 大类整理为可检索结构。"""
    cat_rules = [
        ("世界设定", lambda rel: rel.startswith("世界/")),
        ("国家与组织", lambda rel: rel.startswith("国家/") or rel.startswith("组织/") or rel in ("国家速览.txt", "国家控制器.txt")),
        ("地点设定", lambda rel: rel.startswith("地点/") or rel in ("地区速览.txt", "地点条目控制器.txt")),
        ("角色人设", lambda rel: rel.startswith("角色/") or rel in ("角色速览.txt", "角色阶段控制器.txt")),
        ("NPC速览", lambda rel: rel in ("NPC角色速览.txt", "USER档案.txt")),
        ("剧情事件", lambda rel: rel.startswith("剧情事件/") or rel in ("剧情事件控制器.txt", "[mvu_plot]剧情事件规则.txt")),
        ("后剧情动态", lambda rel: rel.startswith("后剧情条目/") or rel == "后剧情控制器.txt"),
        ("异危与魔物", lambda rel: rel.startswith("魔物/") or rel in ("异危魔物控制器.txt", "魔物图鉴控制器.txt")),
        ("系统与叙事规则", lambda rel: True),
    ]
    entries = []
    for p in sorted(WORLDBOOK.rglob("*.txt")):
        rel = str(p.relative_to(WORLDBOOK)).replace("\\", "/")
        content = p.read_text("utf8").strip()
        if not content:
            continue
        cat = next(c for c, fn in cat_rules if fn(rel))
        title = rel.removesuffix(".txt")
        if "/" in title:
            title = title.replace("/", " · ")
        first_line = next((ln.strip() for ln in content.splitlines() if ln.strip() and not ln.strip().startswith("<")), "")
        entries.append({
            "id": rel.removesuffix(".txt"),
            "title": title,
            "category": cat,
            "path": rel,
            "summary": first_line[:90],
            "body": content,
        })
    categories = [c for c, _ in cat_rules]
    return {
        "format": "aethera-worldbook/1",
        "count": len(entries),
        "categories": categories,
        "entries": entries,
    }


def main() -> None:
    music = json.loads((OUT / "music_manifest.json").read_text("utf8"))
    bgm = music["story_tracks"]
    art = json.loads((OUT / "art_index.json").read_text("utf8"))

    # 1. 8 个出身（含各自的完整开场白文本 + init_stat）
    origins_src = load_js("出身")["origins"]
    origins = []
    for o in origins_src:
        key = o["key"]
        idx, preview_scene_id, scene_tag = ORIGIN_MAP[key]
        raw_txt = (OPENINGS / f"{idx}.txt").read_text("utf8")
        m_uv = re.search(r"<initvar>\s*(.*?)\s*</initvar>", raw_txt, flags=re.S)
        init_stat = parse_initvar(m_uv.group(1)) if m_uv else {}
        greeting = re.sub(r"<UpdateVariable>.*?</UpdateVariable>", "", raw_txt, flags=re.S)
        greeting = re.sub(r"<StatusPlaceHolderImpl\s*/>", "", greeting).strip()
        rec = {
            k: o[k]
            for k in ("key", "name", "wheelName", "wheelSeal", "accent", "listName", "listDesc", "popName", "popSeal", "popTag", "popDesc", "formName")
            if k in o
        }
        rec["available"] = True
        rec["locked"] = False
        rec["opening_index"] = idx
        rec["preview_scene_id"] = preview_scene_id
        rec["opening_scene_tag"] = scene_tag
        rec["init_stat"] = init_stat
        rec["greeting"] = greeting
        origins.append(rec)

    opening = load_js("开场")["opening"]

    # 2. 资料库全量（21主角色 + 8 NPC + 7国 + 蛇杖组织 + 16地点 + 9世界观 + 17魔物/特异点）
    lib_src = load_js("资料库")["library"]
    items = []
    for it in lib_src["items"]:
        entry = dict(it)
        t = entry["type"]
        title = entry["title"]
        if t == "country":
            wb_c = WORLDBOOK / "国家" / f"{title}.txt"
            if wb_c.exists():
                entry["body"] = entry["body"] + "\n\n【世界书国情档案】\n" + wb_c.read_text("utf8").strip()
        elif t == "region":
            wb_r = WORLDBOOK / "地点" / f"{title}.txt"
            if wb_r.exists():
                entry["body"] = entry["body"] + "\n\n【区域详细设定】\n" + wb_r.read_text("utf8").strip()
        items.append(entry)

    # 追加「蛇杖」跨国组织到 country 组
    org_txt = (WORLDBOOK / "组织" / "蛇杖.txt").read_text("utf8").strip()
    items.append({
        "type": "country",
        "imgKind": "crest",
        "title": "蛇杖",
        "colors": ["#46605c", "#1e2c29"],
        "body": org_txt,
    })

    # 追加世界书深度世界观条目（总纲、刻印魔法、神明）到 world 组
    for w_name, w_title in [("总纲", "艾瑟拉世界总纲"), ("刻印魔法", "刻印魔法与结构"), ("神明", "神明与天理")]:
        wb_w = WORLDBOOK / "世界" / f"{w_name}.txt"
        if wb_w.exists():
            items.append({
                "type": "world",
                "imgKind": "rune",
                "title": w_title,
                "colors": ["#6b7c96", "#2c3648"],
                "body": wb_w.read_text("utf8").strip(),
            })

    # 解析 8 名重要 NPC 并加入 character 组 + 单独保留 npcs
    npcs = parse_npcs()
    items.extend(npcs)

    # 构建 cast (21 名主要角色，附带世界书阶段细节)
    lib_by_name = {i["title"]: i for i in lib_src["items"] if i["type"] == "character"}
    characters = []
    for cid, zh in CAST.items():
        it = lib_by_name.get(zh, {})
        stage_files = sorted((WORLDBOOK / "角色" / zh / "变身阶段").glob("*.txt")) if (WORLDBOOK / "角色" / zh / "变身阶段").exists() else []
        stages = {sf.stem: sf.read_text("utf8").strip() for sf in stage_files}
        characters.append({
            "id": cid,
            "name": zh,
            "fields": it.get("fields", []),
            "body": it.get("body", ""),
            "colors": it.get("colors", ["#8fa3b8", "#3f5670"]),
            "stages": stages,
        })

    # 3. 魔物与特异点图鉴（1 总纲 + 8 地域 + 8 特异点 = 17 条）
    monsters = []
    m_root = WORLDBOOK / "魔物"
    monsters.append({"title": "图鉴总纲", "body": (m_root / "图鉴总纲.txt").read_text("utf8").strip()})
    for c in ["塞蕾特公国", "龙渊帝国", "哥塔薇亚帝国", "秋津国", "吉万沙克蒂", "格洛里亚", "奥马努特", "齐哈特大沙漠"]:
        p = m_root / f"{c}.txt"
        if p.exists():
            monsters.append({"title": c + "魔物", "body": p.read_text("utf8").strip()})
    for sp in sorted((m_root / "特异点").glob("*.txt")):
        monsters.append({"title": "【特异点】" + sp.stem, "body": sp.read_text("utf8").strip()})

    # 4. 事件档案（19 原档案馆事件 + 6 世界书补充事件 = 25 个）
    archive_src = load_js("档案馆")["archive"]
    events = [dict(e) for e in archive_src["events"]]
    existing_titles = {e["title"] for e in events}
    next_idx = 120
    for ename, era, cat, dstr, place in EXTRA_EVENTS_ORDER:
        if ename not in existing_titles:
            events.append(parse_extra_event(ename, era, cat, dstr, place, next_idx))
            next_idx += 1

    # 5. 艾瑟拉的忠告完整版（保留 world + factions + about，再附 credits）
    man_src = load_js("忠告")["manual"]
    manual = {
        "tabs": list(man_src["tabs"]) + [{"id": "credits", "label": "音乐来源"}],
        "world": man_src["world"],
        "factions": man_src["factions"],
        "about": man_src["about"],
        "credits": [
            {
                "h": "音乐来源与署名",
                "p": [
                    music.get("credit") or music.get("source", "艾瑟拉原卡保留曲目"),
                    music.get("usage_note") or "完整版曲库扩展清单见 rolecard-rpg/docs/bgm-requirements-full.md。",
                    "音乐权利归原作者所有，当前游戏仅作非商用同人开发使用。",
                ],
            },
            {
                "h": "当前曲库收录（%d首）" % len(music.get("tracks", [])),
                "p": [
                    t["title"]
                    + ((" · " + t["artist"]) if t.get("artist") else "")
                    + " · "
                    + t["role"]
                    for t in music.get("tracks", [])
                ],
            },
        ],
    }

    # 6. 世界地图 24 处标点（来自原卡正则 RX0）
    rx_txt = REGEX_RX0.read_text("utf8")
    seg = rx_txt[rx_txt.find("SIG_LABELS"):]
    labels, _ = json.JSONDecoder().raw_decode(seg[seg.find("["):])

    # 7. 场景与服饰
    scenes = [
        {
            "id": b["id"],
            "scene": b["sceneId"],
            "kind": b["kind"],
            "name": b["name"],
            "country": b["country"],
            "area": b["area"],
            "res": b["res"],
        }
        for b in art["backgrounds"]
    ]
    order = ["daily", "casual", "liberate", "nude"]
    outfits = {
        cid: [o for o in order if o in e.get("outfit_categories", e.get("outfits", {}))]
        for cid, e in art["characters"].items()
    }
    pose_groups = {cid: e.get("pose_groups", []) for cid, e in art["characters"].items()}

    content = {
        "_note": "完整版内容。取自原卡最新文案（f:/sigil-circuit/文案）、8份开场白（开场白/1..8.txt）与全量世界书（worldbook/）。由 tools/build_full_content.py 生成。",
        "edition": "full",
        "cast": characters,
        "npcs": npcs,
        "outfits": outfits,
        "pose_groups": pose_groups,
        "expressions": EXPRESSIONS,
        "bgm": bgm,
        "origins": origins,
        "create": opening["create"],
        "hub": opening["hub"],
        "opening": {
            "modeTitle": opening["modeTitle"],
            "modeDay": opening["modeDay"],
            "modeNight": opening["modeNight"],
            "callPhrases": opening["callPhrases"],
            "bigLines": opening["bigLines"],
            "bigLinesReduced": opening["bigLinesReduced"],
            "finalLine": opening["finalLine"],
            "toasts": opening["toasts"],
        },
        "library": {
            "groups": lib_src["groups"] + [{"type": "monster", "name": "魔物与特异点", "icon": "monster"}],
            "items": items,
            "monsters": monsters,
        },
        "archive": {k: archive_src[k] for k in ("nowFallback", "eras", "cats", "views")} | {"events": events},
        "manual": manual,
        "scenes": scenes,
        "map": {"image": "res://assets/ui/map/world.webp", "view": [1600, 900], "labels": labels},
    }
    (OUT / "contest_content.json").write_text(json.dumps(content, ensure_ascii=False, indent=1), "utf8")

    wb_full = load_worldbook_full()
    (OUT / "worldbook_full.json").write_text(json.dumps(wb_full, ensure_ascii=False, indent=1), "utf8")

    print(
        f"BUILT FULL CONTENT: origins={len(origins)}, cast={len(characters)}, npcs={len(npcs)}, "
        f"library_items={len(items)}, monsters={len(monsters)}, events={len(events)}, "
        f"manual_tabs={len(manual['tabs'])}, scenes={len(scenes)}, map_labels={len(labels)}, "
        f"worldbook_entries={wb_full['count']}"
    )


if __name__ == "__main__":
    main()
