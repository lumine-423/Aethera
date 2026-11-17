"""Parse rolecard-rpg/docs/bgm-requirements-full.md deterministically into tools/bgm_slots.json."""

from __future__ import annotations

import json
from pathlib import Path
import re

TOOLS_DIR = Path(__file__).resolve().parent
ROLECARD_DIR = TOOLS_DIR.parent
DOCS_PATH = ROLECARD_DIR / "docs" / "bgm-requirements-full.md"
OUT_PATH = TOOLS_DIR / "bgm_slots.json"

BATCH1_IDS = {
    "UI-01",
    "UI-02",
    "UI-03",
    "UI-04",
    "FAC-01",
    "FAC-02",
    "FAC-03",
    "FAC-04",
    "FAC-05",
    "FAC-06",
    "FAC-07",
    "FAC-08",
    "LOC-03",
    "LOC-05",
    "LOC-14",
    "LOC-16",
    "EVT-01",
    "EVT-08",
    "EVT-11",
    "BOSS-04",
    "CHAR-01",
}

CATEGORIES = [
    {
        "id": "A",
        "name": "A. 界面与核心玩法专曲",
        "short_name": "界面与核心玩法",
        "count": 4,
        "description": "开场手书、坠湖标题页、1999风室内主页、刻印工坊",
    },
    {
        "id": "B1",
        "name": "B1. 国家与核心组织主题曲",
        "short_name": "国家与核心组织",
        "count": 8,
        "description": "7 大国（塞蕾特、龙渊、哥塔薇亚、秋津、吉万沙克蒂、格洛里亚、奥马努特）＋ 蛇杖组织",
    },
    {
        "id": "B2",
        "name": "B2. 16 个具体地点场景曲",
        "short_name": "具体地点场景",
        "count": 16,
        "description": "中央学院、卡米洛特宫、尼德霍格区、紫宸宫、灵山、基捷日、须弥王庭等 16 处重点地点",
    },
    {
        "id": "C1",
        "name": "C1. 重头剧情事件专曲",
        "short_name": "重头剧情事件",
        "count": 11,
        "description": "archive.events 中 11 个最需要专属配乐的重头事件",
    },
    {
        "id": "D",
        "name": "D. 8 大特异点危机演出曲",
        "short_name": "特异点危机",
        "count": 4,
        "description": "塔阿贝特/海坊主、奇美拉/巴蛇/腾蛇、舍罗婆、苏尔特尔/赤龙",
    },
    {
        "id": "E",
        "name": "E. 角色印象与情绪补位曲",
        "short_name": "角色与情绪补位",
        "count": 5,
        "description": "日常下午茶、双女主羁绊、高压对峙、温柔夜谈、凯旋启程",
    },
]


def clean_md(text: str) -> str:
    text = text.strip()
    text = text.replace(r"\_", "_").replace(r"\*", "*").replace(r"\[", "[").replace(r"\]", "]")
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)
    text = text.replace("`", "")
    return text.strip()


def split_row(line: str) -> list[str]:
    stripped = line.strip()
    if stripped.startswith("|"):
        stripped = stripped[1:]
    if stripped.endswith("|"):
        stripped = stripped[:-1]
    return [clean_md(cell) for cell in stripped.split("|")]


def parse_bgm_markdown() -> dict:
    lines = DOCS_PATH.read_text(encoding="utf-8").splitlines()
    slots: list[dict] = []
    c2_items: list[dict] = []
    section = ""
    in_c2 = False

    for line in lines:
        s = line.strip()
        if s.startswith("### A."):
            section = "A"
            in_c2 = False
            continue
        if s.startswith("#### B1."):
            section = "B1"
            in_c2 = False
            continue
        if s.startswith("#### B2."):
            section = "B2"
            in_c2 = False
            continue
        if s.startswith("#### C1."):
            section = "C1"
            in_c2 = False
            continue
        if s.startswith("#### C2."):
            section = ""
            in_c2 = True
            continue
        if s.startswith("### D."):
            section = "D"
            in_c2 = False
            continue
        if s.startswith("### E."):
            section = "E"
            in_c2 = False
            continue
        if s.startswith("## 三、"):
            section = ""
            in_c2 = False
            break

        if in_c2 and s.startswith("* "):
            body = clean_md(s[2:])
            if "：" in body:
                evt, rule = body.split("：", 1)
                c2_items.append({"event": evt.strip(), "track_title": rule.strip()})
            continue

        if not section or not s.startswith("|"):
            continue
        cols = split_row(s)
        if len(cols) < 5:
            continue
        slot_id = cols[1]
        if not re.match(r"^(UI|FAC|LOC|EVT|BOSS|CHAR)-\d{2}$", slot_id):
            continue

        is_batch1 = slot_id in BATCH1_IDS
        rec_fallback = ""

        if section == "A":
            # [tick, id, name, why_insufficient, style_hint, loop_req]
            name = cols[2]
            scene_desc = cols[3]
            style_hint = cols[4]
            loop_req = cols[5] if len(cols) > 5 else "无缝循环"
            priority = "高（第一批必找）"
        elif section == "B1":
            # [tick, id, name, world_lore, instruments, mood]
            name = cols[2]
            scene_desc = cols[3]
            style_hint = f"{cols[4]}｜情绪：{cols[5]}" if len(cols) > 5 else cols[4]
            loop_req = "无缝循环"
            priority = "高（第一批必找）"
        elif section == "B2":
            # [tick, id, name, feature, style_hint, priority]
            name = cols[2]
            scene_desc = cols[3]
            style_hint = cols[4]
            loop_req = "无缝循环"
            raw_prio = cols[5] if len(cols) > 5 else "中"
            priority = f"{raw_prio}（第一批精选）" if is_batch1 else raw_prio
            if "Windborne Hymn" in style_hint:
                rec_fallback = "orig-plgpzp"
        elif section == "C1":
            # [tick, id, evt_name, loc_chars, reason, style_hint]
            name = cols[2]
            scene_desc = f"{cols[3]}｜{cols[4]}"
            style_hint = cols[5] if len(cols) > 5 else cols[4]
            loop_req = "按剧情段落循环或单次推进"
            priority = "高（第一批精选）" if is_batch1 else "中高"
        elif section == "D":
            # [tick, id, style_title, bosses, imagery, style_hint]
            name = f"{cols[2]}（{cols[3]}）"
            scene_desc = cols[4]
            style_hint = cols[5] if len(cols) > 5 else cols[4]
            loop_req = "危机演出循环"
            priority = "极高（第一批精选）" if is_batch1 else "中高"
        elif section == "E":
            # [tick, id, label, chars_scene, advice]
            name = cols[2]
            scene_desc = cols[3]
            style_hint = cols[4]
            loop_req = "无缝循环"
            priority = "高（第一批精选）" if is_batch1 else "中高"
        else:
            continue

        slots.append(
            {
                "id": slot_id,
                "category": section,
                "name": name,
                "priority": priority,
                "batch1": is_batch1,
                "scene_desc": scene_desc,
                "style_hint": style_hint,
                "loop_req": loop_req,
                "recommended_original_fallback": rec_fallback,
            }
        )

    return {
        "schema": "aethera-bgm-slots/1",
        "source_doc": "rolecard-rpg/docs/bgm-requirements-full.md",
        "categories": CATEGORIES,
        "slots": slots,
        "covered_events_c2": c2_items,
    }


def main() -> int:
    data = parse_bgm_markdown()
    assert len(data["slots"]) == 48, f"Expected 48 slots, got {len(data['slots'])}"
    b1 = sum(1 for s in data["slots"] if s["batch1"])
    assert b1 == 21, f"Expected 21 batch1 slots, got {b1}"
    OUT_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generated {OUT_PATH}: {len(data['slots'])} slots, {b1} batch1, {len(data['covered_events_c2'])} C2 entries")
    for s in data["slots"]:
        print(f"  {s['id']} | {s['name']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
