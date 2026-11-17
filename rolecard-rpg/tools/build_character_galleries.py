#!/usr/bin/env python3
"""Import original-card dual character galleries (8 affection + 10 erotic per cast) from local PNGs.

Matches 文案/图集.js array order 1:1 (thresholds: affection [25, 50, 75, 100] x2,
erotic [20, 40, 60, 80, 100] x2) to F:\\艾瑟拉\\<角色>\\*.png without network calls
or viewing pixels. Outputs compressed WebP assets into
rolecard-rpg/assets/characters/<id>/gallery/ and builds
rolecard-rpg/data/content/character_galleries.json.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
RPG_ROOT = REPO_ROOT / "rolecard-rpg"
ATLAS_JS = REPO_ROOT / "文案" / "图集.js"
CONTENT_JSON = RPG_ROOT / "data" / "content" / "contest_content.json"
OUT_JSON = RPG_ROOT / "data" / "content" / "character_galleries.json"
LOCAL_ART_ROOT = Path(r"F:\艾瑟拉")

AFFECTION_THRESHOLDS = [25, 25, 50, 50, 75, 75, 100, 100]
EROTIC_THRESHOLDS = [20, 20, 40, 40, 60, 60, 80, 80, 100, 100]

PINYIN_MAP = {
    "艾利丝": "ai-li-si-",
    "凛零": "lin-ling-",
    "立绘图": "li-hui-tu-",
    "立绘": "li-hui-",
    "日常": "ri-chang",
    "色图": "se-tu",
    "放大": "fang-da-",
}


def to_slug(filename: str) -> str:
    s = filename
    for k, v in PINYIN_MAP.items():
        s = s.replace(k, v)
    s = s.replace("_", "-")
    s = re.sub(r"\s+", "-", s)
    s = re.sub(r"seedvr2", "seed-vr2", s, flags=re.IGNORECASE)
    s = re.sub(r"-+", "-", s).strip("-")
    s = re.sub(r"-\.png$", ".png", s, flags=re.IGNORECASE)
    return s.lower()


def parse_atlas_js(path: Path) -> dict[str, dict[str, list[str]]]:
    txt = path.read_text(encoding="utf-8")
    idx = txt.find('"characters":')
    if idx < 0:
        raise RuntimeError("Missing 'characters' section in 图集.js")
    block = txt[idx:]
    out: dict[str, dict[str, list[str]]] = {}
    cur_char: str | None = None
    cur_kind: str | None = None
    for line in block.splitlines():
        mc = re.match(r'^\s*"([^"]+)":\s*\{\s*$', line)
        if mc:
            if mc.group(1) == "characters":
                continue
            cur_char = mc.group(1)
            out[cur_char] = {"affection": [], "erotic": []}
            cur_kind = None
            continue
        mk = re.match(r'^\s*"(affection|erotic)":\s*\[\s*$', line)
        if mk and cur_char:
            cur_kind = mk.group(1)
            continue
        mu = re.match(r'^\s*"(https?://[^"]+)"', line)
        if mu and cur_char and cur_kind:
            out[cur_char][cur_kind].append(mu.group(1))
            continue
        if re.match(r"^\s*\]", line):
            cur_kind = None
    return out


def convert_png_to_webp(src: Path, dst: Path, max_dim: int = 1920, quality: int = 88) -> tuple[int, int]:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and dst.stat().st_mtime >= src.stat().st_mtime and dst.stat().st_size > 0:
        with Image.open(dst) as existing:
            return existing.size
    with Image.open(src) as img:
        if img.mode not in ("RGB", "RGBA"):
            img = img.convert("RGBA" if "A" in img.getbands() else "RGB")
        w, h = img.size
        scale = min(1.0, float(max_dim) / float(max(w, h)))
        if scale < 1.0:
            nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
            img = img.resize((nw, nh), Image.Resampling.LANCZOS)
        img.save(dst, "WEBP", quality=quality, method=4)
        return img.size


def main() -> None:
    content = json.loads(CONTENT_JSON.read_text(encoding="utf-8"))
    name_to_id = {str(c["name"]): str(c["id"]) for c in content.get("cast", [])}
    atlas = parse_atlas_js(ATLAS_JS)

    result: dict[str, dict] = {}
    total_converted = 0
    missing: list[tuple[str, str, int, str]] = []

    for cname, kinds in atlas.items():
        cid = name_to_id.get(cname)
        if not cid:
            raise RuntimeError(f"Unknown cast character name in 图集.js: {cname}")
        folder = LOCAL_ART_ROOT / ("叶子" if cname == "叶" else cname)
        if not folder.exists():
            raise RuntimeError(f"Missing local art folder: {folder}")
        local_map = {to_slug(f.name): f for f in folder.glob("*.png")}

        char_record: dict[str, list[dict]] = {"affection": [], "erotic": []}
        out_dir = RPG_ROOT / "assets" / "characters" / cid / "gallery"

        for kind, thresholds, prefix in [
            ("affection", AFFECTION_THRESHOLDS, "daily"),
            ("erotic", EROTIC_THRESHOLDS, "erotic"),
        ]:
            urls = kinds.get(kind, [])
            for slot_idx, url in enumerate(urls):
                slug = url.rsplit("/", 1)[-1].lower()
                src = local_map.get(slug)
                if src is None:
                    missing.append((cname, kind, slot_idx, slug))
                    continue
                fname = f"{prefix}_{slot_idx + 1:02d}.webp"
                dst = out_dir / fname
                w, h = convert_png_to_webp(src, dst)
                res_path = f"res://assets/characters/{cid}/gallery/{fname}"
                need = thresholds[slot_idx] if slot_idx < len(thresholds) else 100
                char_record[kind].append({
                    "slot": slot_idx + 1,
                    "need": need,
                    "res": res_path,
                    "width": w,
                    "height": h,
                    "source_name": src.name,
                })
                total_converted += 1

        result[cid] = {
            "id": cid,
            "name": cname,
            "affection": char_record["affection"],
            "erotic": char_record["erotic"],
        }

    if missing:
        raise RuntimeError(f"Unmatched gallery assets ({len(missing)}): {missing[:10]}")

    payload = {
        "format": "sigil-character-galleries/1",
        "characters": result,
        "total_images": total_converted,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"OK: built {total_converted} gallery WebPs for {len(result)} characters -> {OUT_JSON}")


if __name__ == "__main__":
    main()
