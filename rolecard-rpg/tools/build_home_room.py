"""Build the interactive home room assets (2026-11-17).

Source: workspaces/frontend-ui/materials/home-dream-room-20261116/01_完整背景/room-{day,night}.png
Output: assets/ui/home_room/
  room_{m}.webp           full room, the home background (lossless webp)
  blur_{m}.webp           heavily blurred small copy for every other page's backdrop
  {prop}_{m}.png          cut-out of a movable prop (RGBA, cropped to its box)
  {prop}_under_{m}.webp   the room with that prop painted out (same box), shown only while it moves
  props.json              boxes in source-image pixels
Debug sheet: workspaces/frontend-ui/materials/home-room-interactive-20261117/masks/

Props are cut from the full room itself, so they line up with it pixel for pixel. Masks come from
GrabCut (sofa, chairs) or a hand polygon (book, cup); unders come from cv2 inpainting of the room.
"""
import json
import os

import cv2
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "workspaces", "frontend-ui", "materials", "home-dream-room-20261116", "01_完整背景")
OUT = os.path.join(ROOT, "assets", "ui", "home_room")
DBG = os.path.join(ROOT, "workspaces", "frontend-ui", "materials", "home-room-interactive-20261117", "masks")

# box = x0, y0, x1, y1 in source pixels (1672x941)
PROPS = {
    "sofa": {"box": [36, 500, 664, 826], "mode": "grabcut"},
    # trim: crop-local rects removed from the mask (table-top edge that GrabCut joins to the chair)
    "chair_l": {"box": [662, 560, 842, 818], "mode": "grabcut", "fill": False, "trim": [[92, 0, 180, 108]]},
    "chair_r": {"box": [990, 558, 1158, 822], "mode": "grabcut", "fill": False, "trim": [[0, 0, 32, 108]]},
    "book": {"box": [838, 604, 936, 644], "mode": "poly",
             "poly": [[845, 617], [852, 611], [925, 611], [931, 616], [930, 637], [893, 639], [844, 632]]},
    "cup": {"box": [934, 596, 992, 640], "mode": "poly",
            "poly": [[945, 604], [972, 602], [976, 606], [985, 606], [987, 614], [980, 624], [988, 627], [986, 632], [962, 635], [938, 632], [937, 627], [949, 624], [945, 612]]},
}


def grabcut_mask(rgb: np.ndarray, box, fill=True, trim=()) -> np.ndarray:
    x0, y0, x1, y1 = box
    crop = rgb[y0:y1, x0:x1].copy()
    h, w = crop.shape[:2]
    mask = np.zeros((h, w), np.uint8)
    bgd = np.zeros((1, 65), np.float64); fgd = np.zeros((1, 65), np.float64)
    rect = (4, 4, w - 8, h - 8)
    cv2.grabCut(crop, mask, rect, bgd, fgd, 8, cv2.GC_INIT_WITH_RECT)
    m = np.where((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD), 255, 0).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((7 if fill else 3, 7 if fill else 3), np.uint8))
    for tx0, ty0, tx1, ty1 in trim:
        m[ty0:ty1, tx0:tx1] = 0
    n, lab, stats, _ = cv2.connectedComponentsWithStats(m)
    if n > 1:
        keep = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        m = np.where(lab == keep, 255, 0).astype(np.uint8)
    if fill:
        ff = m.copy(); fm = np.zeros((h + 2, w + 2), np.uint8)
        cv2.floodFill(ff, fm, (0, 0), 255)
        m = m | cv2.bitwise_not(ff)
    return m


def poly_mask(box, poly) -> np.ndarray:
    x0, y0, x1, y1 = box
    m = np.zeros((y1 - y0, x1 - x0), np.uint8)
    pts = np.array([[p[0] - x0, p[1] - y0] for p in poly], np.int32)
    cv2.fillPoly(m, [pts], 255, lineType=cv2.LINE_AA)
    return m


def main() -> None:
    os.makedirs(OUT, exist_ok=True); os.makedirs(DBG, exist_ok=True)
    meta = {"source_size": None, "props": {}}
    masks = {}
    for mode in ["day", "night"]:
        im = Image.open(os.path.join(SRC, "room-%s.png" % mode)).convert("RGB")
        meta["source_size"] = list(im.size)
        im.save(os.path.join(OUT, "room_%s.webp" % mode), "WEBP", lossless=True, method=6)
        # backdrop for other pages: only soft colour fields remain
        small = im.resize((im.width // 4, im.height // 4), Image.LANCZOS).filter(ImageFilter.GaussianBlur(14))
        small.save(os.path.join(OUT, "blur_%s.webp" % mode), "WEBP", quality=90, method=6)
        rgb = np.asarray(im)
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        for name, spec in PROPS.items():
            box = spec["box"]; x0, y0, x1, y1 = box
            # one mask for both modes (taken from day, same layout), so day/night cut-outs match
            if name not in masks:
                masks[name] = grabcut_mask(bgr, box, spec.get("fill", True), spec.get("trim", ())) if spec["mode"] == "grabcut" else poly_mask(box, spec["poly"])
            m = masks[name]
            soft = cv2.GaussianBlur(m, (3, 3), 0)
            rgba = np.dstack([rgb[y0:y1, x0:x1], soft])
            Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "%s_%s.png" % (name, mode)), optimize=True)
            # under: paint the prop out of the room (dilated so no rim is left)
            full = np.zeros(rgb.shape[:2], np.uint8)
            full[y0:y1, x0:x1] = cv2.dilate(m, np.ones((9, 9), np.uint8))
            pad = 24
            X0, Y0, X1, Y1 = max(0, x0 - pad), max(0, y0 - pad), min(rgb.shape[1], x1 + pad), min(rgb.shape[0], y1 + pad)
            patch = cv2.inpaint(bgr[Y0:Y1, X0:X1], full[Y0:Y1, X0:X1], 9, cv2.INPAINT_TELEA)
            under = cv2.cvtColor(patch, cv2.COLOR_BGR2RGB)[y0 - Y0:y1 - Y0, x0 - X0:x1 - X0]
            Image.fromarray(under).save(os.path.join(OUT, "%s_under_%s.webp" % (name, mode)), "WEBP", quality=92, method=6)
            meta["props"][name] = {"box": box}
            if mode == "day":
                dbg = rgb[y0:y1, x0:x1].copy()
                dbg[m < 128] = (dbg[m < 128] * 0.25 + np.array([0, 160, 255]) * 0.75).astype(np.uint8)
                Image.fromarray(np.hstack([dbg, under])).save(os.path.join(DBG, "%s.png" % name))
    with open(os.path.join(OUT, "props.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("home room assets ->", OUT)


if __name__ == "__main__":
    main()
