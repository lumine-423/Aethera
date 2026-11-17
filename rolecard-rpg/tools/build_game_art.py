"""Build character portraits, avatars, cards, emotions, art_index.json, and portrait_registry.json.

Reads all 29 character portrait manifests under:
  rolecard-rpg/workspaces/character-portraits/<dir>_立绘整理/正式立绘/manifest.json
Reads all 29 avatars under F:\\艾瑟拉\\头像\\ and card portraits under F:\\艾瑟拉\\,
plus the missing 'confident' emotion symbol from workspaces/character-portraits/通用素材/.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
from concurrent.futures import ProcessPoolExecutor
from typing import Any

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
WS_PORTRAITS = ROOT / "workspaces" / "character-portraits"
F_ROOT = pathlib.Path(r"F:\艾瑟拉")
OUT_CHARS = ROOT / "assets" / "characters"
OUT_SILHOUETTES = OUT_CHARS / "silhouettes"
OUT_PORTRAITS = ROOT / "assets" / "ui" / "portraits"
SILHOUETTE_MANIFEST = WS_PORTRAITS / "通用素材" / "默认NPC剪影" / "正式立绘" / "manifest.json"
OUT_EMOTIONS = ROOT / "assets" / "emotions"
ART_INDEX_PATH = ROOT / "data" / "content" / "art_index.json"
REGISTRY_PATH = ROOT / "data" / "ui" / "portrait_registry.json"
PROFILES_PATH = ROOT / "data" / "character_profiles.json"

SPRITE_HEIGHT = 1536
AVATAR_SIZE = 512
CARD_MAX_EDGE = 1536
EMOTION_MAX_EDGE = 256

CONFIDENT_SRC = (
    WS_PORTRAITS
    / "通用素材"
    / "漫画情绪符号"
    / "情绪模板_圆润版_20261110"
    / "10_自信笑_得意小皇冠.png"
)

EXPR_ORDER = [
    "neutral",
    "smile",
    "speaking",
    "puzzled",
    "surprised",
    "bashful",
    "disgust",
    "angry",
    "sad",
    "star-eyes",
    "confident",
]

EXPR_PREFIX = {
    "00_平静": "neutral",
    "平静": "neutral",
    "neutral": "neutral",
    "01_微笑": "smile",
    "微笑": "smile",
    "smile": "smile",
    "02_说话": "speaking",
    "说话": "speaking",
    "speaking": "speaking",
    "03_疑惑": "puzzled",
    "疑惑": "puzzled",
    "puzzled": "puzzled",
    "04_惊讶": "surprised",
    "惊讶": "surprised",
    "surprised": "surprised",
    "05_害羞": "bashful",
    "害羞": "bashful",
    "bashful": "bashful",
    "06_嫌弃": "disgust",
    "嫌弃": "disgust",
    "disgust": "disgust",
    "07_生气": "angry",
    "生气": "angry",
    "angry": "angry",
    "08_难过": "sad",
    "难过": "sad",
    "sad": "sad",
    "09_星星眼": "star-eyes",
    "星星眼": "star-eyes",
    "star-eyes": "star-eyes",
    "10_自信笑": "confident",
    "自信笑": "confident",
    "confident": "confident",
}

CAT_ORDER = ["daily", "casual", "liberate", "nude"]

# Explicit character source map: (id, ws_folder_name, avatar_stem, f_card_rel)
CHARACTER_SOURCES: list[tuple[str, str, str, str]] = [
    ("rin", "凛零_立绘整理", "凛零", r"凛零\凛零.png"),
    ("merlin", "梅林_立绘整理", "梅林", r"梅林\梅林.png"),
    ("mohua", "墨华_立绘整理", "墨华", r"墨华\墨华.png"),
    ("bingtang", "冰糖_立绘整理", "冰糖", r"冰糖\冰糖.png"),
    ("anke", "安克_立绘整理", "安克", r"安克\安克.png"),
    ("castor", "卡斯特_立绘整理", "卡斯特", r"卡斯特\卡斯特.png"),
    ("jian", "茧_立绘整理", "茧", r"茧\茧.png"),
    ("mingkong", "明空_立绘整理", "明空", r"明空\明空.png"),
    ("alice", "艾利丝_立绘整理", "艾利丝", r"艾利丝\艾利丝.png"),
    ("lucifer", "路西法_立绘整理", "路西法", r"路西法\路西法.png"),
    ("ai", "暧_立绘整理", "暧", r"暧\暧.png"),
    ("ye", "叶子_立绘整理", "叶", r"叶子\叶.png"),
    ("valkyrie", "瓦尔基里_立绘整理", "瓦尔基里", r"瓦尔基里\瓦尔基里.png"),
    ("alanya", "阿兰雅_立绘整理", "阿兰雅", r"阿兰雅\阿兰雅.png"),
    ("vamana", "筏摩娜_立绘整理", "筏摩娜", r"筏摩娜\筏摩娜.png"),
    ("xuanyuan", "轩辕_立绘整理", "轩辕", r"轩辕\轩辕.png"),
    ("yanyuan", "焰渊_立绘整理", "焰渊", r"焰渊\焰渊.png"),
    ("larentia", "拉伦提娅_立绘整理", "拉伦提娅", r"拉伦提娅\拉伦提娅.png"),
    ("yangxiang", "阳向_立绘整理", "阳向", r"阳向\阳向.png"),
    ("lufa", "露珐_立绘整理", "露珐", r"露珐\露珐.png"),
    ("washake", "瓦沙克_立绘整理", "瓦沙克", r"瓦沙克\瓦沙克.png"),
    ("edgar", "埃德加·考文垂_立绘整理", "埃德加·考文垂", r"NPC\埃德加·考文垂.png"),
    ("victor", "维克托_立绘整理", "维克托", r"NPC\维克托.png"),
    ("drago", "德拉贡_立绘整理", "德拉贡", r"NPC\德拉贡.png"),
    ("tiya", "缇雅_立绘整理", "缇雅", r"NPC\缇雅.png"),
    ("xiaoai", "小艾_立绘整理", "小艾", r"NPC\小艾.png"),
    ("varsha", "瓦尔莎_立绘整理", "瓦尔莎", r"NPC\瓦尔莎.png"),
    ("satou", "佐藤澄_立绘整理", "佐藤澄", r"NPC\佐藤澄.png"),
    ("solanu", "索拉努_立绘整理", "索拉努", r"NPC\索拉努.png"),
]


def norm_cat(outfit: str) -> str:
    if outfit == "日常服":
        return "daily"
    if outfit == "休闲服":
        return "casual"
    if outfit == "解放形态":
        return "liberate"
    if outfit in ("裸体", "用户提供原图", "用户提供裸体母图"):
        return "nude"
    raise ValueError(f"Unknown outfit: {outfit!r}")


def norm_view(view: str) -> str:
    if view == "默认":
        return "default"
    if view == "正面":
        return "front"
    if view in ("侧面", "半侧", "浅半侧"):
        return "side"
    if view == "原图":
        return "front"
    raise ValueError(f"Unknown view: {view!r}")


def short_pose_label(cat: str, view_zh: str, pose_zh: str) -> str:
    # Keep UI chips compact while preserving action/angle distinction.
    p = pose_zh.replace("动作A_", "动作A ").replace("动作B_", "动作B ")
    if len(p) > 8:
        p = p[:7] + "…"
    v = "默认" if view_zh in ("默认", "原图") else view_zh
    if cat == "liberate":
        return f"解放·{v}" if p in ("A", "B", "自然", "原图姿势") else f"解放·{p}"
    if cat == "nude":
        return "原姿" if "原图" in p or view_zh == "原图" else f"裸·{p}"
    return f"{v}·{p}" if p else v


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_manifest(ws_dir: pathlib.Path) -> list[dict[str, Any]]:
    manifest = json.loads((ws_dir / "manifest.json").read_text("utf-8"))
    by_cat: dict[str, list[dict[str, Any]]] = {c: [] for c in CAT_ORDER}

    for idx, g in enumerate(manifest["groups"]):
        cat = norm_cat(g["outfit"])
        view_zh = g["view"]
        view = norm_view(view_zh)
        pose_zh = g.get("pose") or g.get("action") or ""
        folder = g.get("folder") or g.get("path") or f"{g['outfit']}/{view_zh}/{pose_zh}".strip("/")
        items = g.get("entries") or g.get("sprites")
        files: dict[str, tuple[pathlib.Path, str]] = {}
        for item in items:
            rel = item.get("file") or item.get("path")
            expr = item.get("expression")
            if not expr:
                expr = EXPR_PREFIX[pathlib.Path(rel).stem]
            src_path = (ws_dir / rel).resolve()
            if not src_path.exists():
                raise FileNotFoundError(f"Missing sprite file: {src_path}")
            files[expr] = (src_path, item.get("sha256") or "")
        # Canonical expression order
        ordered_files = {
            e: files[e]
            for e in EXPR_ORDER
            if e in files
        }
        for e in files:
            if e not in ordered_files:
                ordered_files[e] = files[e]
        by_cat[cat].append({
            "orig_idx": idx,
            "cat": cat,
            "view": view,
            "view_zh": view_zh,
            "pose_zh": pose_zh,
            "folder": folder,
            "files": ordered_files,
        })

    # Assign canonical group keys matching existing project naming conventions
    ordered_groups: list[dict[str, Any]] = []
    for cat in CAT_ORDER:
        glist = by_cat[cat]
        if not glist:
            continue
        if cat == "daily":
            defaults = [x for x in glist if x["view"] == "default"]
            fronts = [x for x in glist if x["view"] == "front"]
            sides = [x for x in glist if x["view"] == "side"]
            if defaults:
                defaults[0]["key"] = "daily"
                for k, x in enumerate(defaults[1:], 1):
                    x["key"] = f"daily_default_{chr(ord('a') + k)}"
            for k, x in enumerate(fronts):
                suffix = chr(ord("a") + k)
                x["key"] = f"daily_front_{suffix}" if (len(fronts) > 1 or defaults) else "daily_front"
            for k, x in enumerate(sides):
                x["key"] = f"daily_side_{chr(ord('a') + k)}"
            ordered_groups.extend(defaults + fronts + sides)
        elif cat == "casual":
            glist[0]["key"] = "casual"
            for k, x in enumerate(glist[1:], 1):
                x["key"] = f"casual_{chr(ord('a') + k)}"
            ordered_groups.extend(glist)
        elif cat == "liberate":
            fronts = [x for x in glist if x["view"] != "side"]
            sides = [x for x in glist if x["view"] == "side"]
            if fronts:
                fronts[0]["key"] = "liberate"
                for k, x in enumerate(fronts[1:], 1):
                    x["key"] = f"liberate_{chr(ord('a') + k)}"
            for k, x in enumerate(sides):
                x["key"] = "liberate_side" if k == 0 else f"liberate_side_{chr(ord('a') + k)}"
            ordered_groups.extend(fronts + sides)
        elif cat == "nude":
            glist[0]["key"] = "nude"
            for k, x in enumerate(glist[1:], 1):
                x["key"] = f"nude_{chr(ord('a') + k)}"
            ordered_groups.extend(glist)

    for g in ordered_groups:
        g["label"] = short_pose_label(g["cat"], g["view_zh"], g["pose_zh"])
    return ordered_groups


def convert_sprite_task(task: tuple[str, str, str]) -> tuple[str, str]:
    src_s, dst_s, known_sha = task
    src = pathlib.Path(src_s)
    dst = pathlib.Path(dst_s)
    dst.parent.mkdir(parents=True, exist_ok=True)
    sha = known_sha or sha256_file(src)
    with Image.open(src) as im:
        im = im.convert("RGBA")
        w, h = im.size
        if h > SPRITE_HEIGHT:
            target_w = max(1, round(w * SPRITE_HEIGHT / h))
            resized = im.resize((target_w, SPRITE_HEIGHT), Image.Resampling.LANCZOS)
        else:
            resized = im
        resized.save(dst, "WEBP", quality=94, method=5)
    return dst_s, sha


def measure_framing(webp_path: pathlib.Path) -> dict[str, float]:
    with Image.open(webp_path) as im:
        rgba = im.convert("RGBA")
        w, h = rgba.size
        alpha = rgba.getchannel("A")
        mask = alpha.point(lambda v: 255 if v > 16 else 0)
        bbox = mask.getbbox()
        if not bbox:
            return {"top": 0.02, "chin": 0.19, "knee": 0.72, "center": 0.5}
        _, by0, _, by1 = bbox
        top = round(max(0.005, by0 / h), 3)
        span = max(0.2, (by1 - by0) / h)
        chin = round(min(0.45, top + span * 0.175), 3)
        knee = round(min(0.95, top + span * 0.72), 3)
        # Measure horizontal center across upper 25% of opaque character body
        head_y1 = min(h, by0 + max(1, int((by1 - by0) * 0.25)))
        head_crop = mask.crop((0, by0, w, head_y1))
        hb = head_crop.getbbox()
        if hb:
            center = round(max(0.35, min(0.65, ((hb[0] + hb[2]) * 0.5) / w)), 3)
        else:
            center = 0.5
        return {"top": top, "chin": chin, "knee": knee, "center": center}


def build_square_avatar(src: pathlib.Path, dst_chars: pathlib.Path, dst_ui: pathlib.Path) -> None:
    dst_chars.parent.mkdir(parents=True, exist_ok=True)
    dst_ui.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as im:
        w, h = im.size
        if w != h:
            side = min(w, h)
            x0 = (w - side) // 2
            y0 = max(0, (h - side) // 4)
            im = im.crop((x0, y0, x0 + side, y0 + side))
        if im.mode == "RGBA":
            ext = im.getchannel("A").getextrema()
            if ext == (255, 255):
                im = im.convert("RGB")
        elif im.mode != "RGB":
            im = im.convert("RGB")
        out = im.resize((AVATAR_SIZE, AVATAR_SIZE), Image.Resampling.LANCZOS)
        out.save(dst_chars, "WEBP", quality=92, method=5)
        out.save(dst_ui, "WEBP", quality=92, method=5)


def build_card_portrait(src: pathlib.Path, dst: pathlib.Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as im:
        if im.mode == "RGBA":
            ext = im.getchannel("A").getextrema()
            if ext == (255, 255):
                im = im.convert("RGB")
        elif im.mode != "RGB":
            im = im.convert("RGB")
        if max(im.size) > CARD_MAX_EDGE:
            im.thumbnail((CARD_MAX_EDGE, CARD_MAX_EDGE), Image.Resampling.LANCZOS)
        im.save(dst, "WEBP", quality=92, method=5)


def build_confident_emotion(src: pathlib.Path, dst: pathlib.Path) -> None:
    if not src.exists():
        raise FileNotFoundError(f"Missing confident emotion source: {src}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as im:
        im = im.convert("RGBA")
        alpha = im.getchannel("A")
        bbox = alpha.point(lambda v: 255 if v > 8 else 0).getbbox()
        if bbox:
            im = im.crop(bbox)
        im.thumbnail((EMOTION_MAX_EDGE, EMOTION_MAX_EDGE), Image.Resampling.LANCZOS)
        im.save(dst, "PNG")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="Re-encode all sprites even when sha256 matches")
    args = parser.parse_args()

    existing_art = json.loads(ART_INDEX_PATH.read_text("utf-8")) if ART_INDEX_PATH.exists() else {}
    existing_chars = existing_art.get("characters", {})
    existing_reg = json.loads(REGISTRY_PATH.read_text("utf-8")) if REGISTRY_PATH.exists() else {}
    existing_reg_chars = existing_reg.get("characters", {})

    # Index existing sha256 -> rel path cache inside art_index
    cached_sha: dict[tuple[str, str, str], str] = {}
    for cid, ce in existing_chars.items():
        for gkey, ge in ce.get("outfits", {}).items():
            for expr, fe in ge.get("files", {}).items():
                cached_sha[(cid, gkey, expr)] = fe.get("sha256", "")

    tasks: list[tuple[str, str, str]] = []
    char_plans: list[dict[str, Any]] = []
    skipped = 0

    for cid, ws_name, av_stem, card_rel in CHARACTER_SOURCES:
        ws_dir = WS_PORTRAITS / ws_name / "正式立绘"
        groups = parse_manifest(ws_dir)
        out_char_dir = OUT_CHARS / cid
        avatar_src = F_ROOT / "头像" / f"{av_stem}.png"
        card_src = F_ROOT / card_rel
        char_plans.append({
            "id": cid,
            "ws_dir": ws_dir,
            "groups": groups,
            "avatar_src": avatar_src,
            "card_src": card_src,
        })
        for g in groups:
            gkey = g["key"]
            for expr, (src_path, m_sha) in g["files"].items():
                dst_path = out_char_dir / gkey / f"{expr}.webp"
                src_sha = m_sha or sha256_file(src_path)
                prev_sha = cached_sha.get((cid, gkey, expr), "")
                if not args.force and dst_path.exists() and prev_sha and prev_sha == src_sha:
                    skipped += 1
                    g.setdefault("resolved", {})[expr] = (src_path, dst_path, src_sha)
                else:
                    tasks.append((str(src_path), str(dst_path), src_sha))
                    g.setdefault("resolved", {})[expr] = (src_path, dst_path, src_sha)

    print(f"Sprites queued: {len(tasks)}, reused via matching sha256: {skipped}")
    if tasks:
        workers = min(32, os.cpu_count() or 8)
        with ProcessPoolExecutor(max_workers=workers) as pool:
            done = 0
            for _ in pool.map(convert_sprite_task, tasks, chunksize=8):
                done += 1
                if done % 400 == 0 or done == len(tasks):
                    print(f"  converted {done}/{len(tasks)} sprites...")

    # Avatars & Cards & Emotions
    av_count = 0
    card_count = 0
    for cp in char_plans:
        cid = cp["id"]
        av_src = cp["avatar_src"]
        if av_src.exists():
            build_square_avatar(
                av_src,
                OUT_CHARS / cid / "avatar.webp",
                OUT_PORTRAITS / f"{cid}-avatar.webp",
            )
            av_count += 1
        c_src = cp["card_src"]
        c_dst = OUT_PORTRAITS / f"{cid}.webp"
        if c_src.exists() and (args.force or not c_dst.exists()):
            build_card_portrait(c_src, c_dst)
            card_count += 1

    confident_dst = OUT_EMOTIONS / "confident.png"
    build_confident_emotion(CONFIDENT_SRC, confident_dst)
    print(f"Avatars built: {av_count}, Cards converted: {card_count}, Confident emotion ready: {confident_dst.exists()}")

    # Build art_index.json (preserving backgrounds & non-character keys)
    new_chars: dict[str, Any] = {}
    new_reg_chars: dict[str, Any] = {}
    total_groups = 0
    total_sprites = 0

    for cp in char_plans:
        cid = cp["id"]
        groups = cp["groups"]
        total_groups += len(groups)
        cats_seen: list[str] = []
        pose_groups: list[dict[str, Any]] = []
        outfits_dict: dict[str, Any] = {}
        prev_framing = existing_reg_chars.get(cid, {}).get("framing", {})
        char_framing: dict[str, dict[str, float]] = {}

        for g in groups:
            gkey = g["key"]
            cat = g["cat"]
            if cat not in cats_seen:
                cats_seen.append(cat)
            exprs = list(g["resolved"].keys())
            total_sprites += len(exprs)
            pose_groups.append({
                "key": gkey,
                "category": cat,
                "label": g["label"],
                "view": g["view_zh"],
                "pose": g["pose_zh"],
                "expressions": exprs,
            })
            outfits_dict[gkey] = {
                "category": cat,
                "label": g["label"],
                "pose": g["folder"],
                "files": {
                    expr: {"src": str(src_p), "sha256": sha}
                    for expr, (src_p, _dst_p, sha) in g["resolved"].items()
                },
            }
            if gkey in prev_framing and all(k in prev_framing[gkey] for k in ("top", "chin", "knee", "center")):
                char_framing[gkey] = prev_framing[gkey]
            else:
                neutral_webp = g["resolved"].get("neutral", next(iter(g["resolved"].values())))[1]
                char_framing[gkey] = measure_framing(neutral_webp)

        new_chars[cid] = {
            "source": str(cp["ws_dir"]),
            "outfit_categories": cats_seen,
            "pose_groups": pose_groups,
            "outfits": outfits_dict,
        }

        default_webp = OUT_CHARS / cid / "daily" / "neutral.webp"
        default_res = f"res://assets/characters/{cid}/daily/neutral.webp" if default_webp.exists() else ""
        av_res = (
            f"res://assets/characters/{cid}/avatar.webp"
            if (OUT_CHARS / cid / "avatar.webp").exists()
            else f"res://assets/ui/portraits/{cid}-avatar.webp"
        )
        new_reg_chars[cid] = {
            "full": default_res,
            "bust": default_res,
            "card": f"res://assets/ui/portraits/{cid}.webp" if (OUT_PORTRAITS / f"{cid}.webp").exists() else "",
            "avatar": av_res,
            "framing": char_framing,
        }

    # Build default NPC silhouettes (child, woman, man, elder, monster) untouched in native 1024x1536 RGBA
    sil_registry: dict[str, Any] = {}
    if SILHOUETTE_MANIFEST.exists():
        sil_manifest = json.loads(SILHOUETTE_MANIFEST.read_text("utf-8"))
        sil_src_dir = SILHOUETTE_MANIFEST.parent
        OUT_SILHOUETTES.mkdir(parents=True, exist_ok=True)
        for entry in sil_manifest.get("entries", []):
            skey = str(entry.get("key", "")).strip()
            slabel = str(entry.get("label", skey)).strip()
            sfile = str(entry.get("file", "")).strip()
            src_png = sil_src_dir / sfile
            if not skey or not src_png.exists():
                continue
            dst_webp = OUT_SILHOUETTES / f"{skey}.webp"
            with Image.open(src_png) as sim:
                sim = sim.convert("RGBA")
                w, h = sim.size
                if h > SPRITE_HEIGHT:
                    target_w = max(1, round(w * SPRITE_HEIGHT / h))
                    sim = sim.resize((target_w, SPRITE_HEIGHT), Image.Resampling.LANCZOS)
                sim.save(dst_webp, "WEBP", quality=94, method=5)
            sil_id = f"sil_{skey}"
            sil_res = f"res://assets/characters/silhouettes/{skey}.webp"
            sil_registry[sil_id] = {
                "label": slabel,
                "full": sil_res,
                "bust": sil_res,
                "avatar": sil_res,
                "framing": {"daily": measure_framing(dst_webp)},
            }
        print(f"Default NPC silhouettes built: {len(sil_registry)}")

    out_art = dict(existing_art)
    out_art["characters"] = new_chars
    out_art["silhouettes"] = sil_registry
    ART_INDEX_PATH.write_text(json.dumps(out_art, ensure_ascii=False, indent=2), "utf-8")

    emotions = dict(existing_reg.get("emotions", {}))
    emotions["confident"] = "res://assets/emotions/confident.png"
    out_reg = {
        "_note": existing_reg.get(
            "_note",
            "角色立绘/半身/卡图/头像与情绪符号注册表。由 tools/build_game_art.py 维护。",
        ),
        "emotions": emotions,
        "characters": new_reg_chars,
        "silhouettes": sil_registry,
    }
    REGISTRY_PATH.write_text(json.dumps(out_reg, ensure_ascii=False, indent=2), "utf-8")
    print(f"Wrote art_index.json & portrait_registry.json: {len(new_chars)} chars, {len(sil_registry)} silhouettes, {total_groups} groups, {total_sprites} sprites")


if __name__ == "__main__":
    main()
