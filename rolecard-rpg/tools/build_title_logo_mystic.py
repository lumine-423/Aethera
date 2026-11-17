"""Build the transparent title wordmark from the accepted r6 title master.

Source (unchanged): workspaces/frontend-ui/materials/ui-title-main-star-20261114/exact-r6/
title-aethera-original-chinese-r6.png (1672x941, dark ink on white).
Output: assets/ui/mystic/title_logo_mask.png - white RGB with alpha = ink coverage, cropped to the
ink bounds plus a margin, so Godot can tint it per theme (day ink / night ink) without a second file.
No redraw, no scaling: alpha is read straight from the master's luminance.
"""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "workspaces/frontend-ui/materials/ui-title-main-star-20261114/exact-r6/title-aethera-original-chinese-r6.png"
OUT_DIR = ROOT / "assets/ui/mystic"
OUT = OUT_DIR / "title_logo_mask.png"

img = Image.open(SRC).convert("RGB")
a = np.asarray(img).astype(np.float32) / 255.0
lum = a @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
paper = float(np.percentile(lum, 90))           # paper white level
ink = float(np.percentile(lum, 0.2))            # darkest stroke level
alpha = np.clip((paper - lum) / max(paper - ink, 1e-3), 0.0, 1.0)
alpha[alpha < 0.03] = 0.0
ys, xs = np.nonzero(alpha > 0.03)
m = 24
y0, y1 = max(0, ys.min() - m), min(alpha.shape[0], ys.max() + m + 1)
x0, x1 = max(0, xs.min() - m), min(alpha.shape[1], xs.max() + m + 1)
crop = alpha[y0:y1, x0:x1]
rgba = np.zeros((crop.shape[0], crop.shape[1], 4), dtype=np.uint8)
rgba[..., :3] = 255
rgba[..., 3] = np.round(crop * 255).astype(np.uint8)
OUT_DIR.mkdir(parents=True, exist_ok=True)
Image.fromarray(rgba, "RGBA").save(OUT)
receipt = {
    "source": str(SRC.relative_to(ROOT)).replace("\\", "/"),
    "source_sha256": hashlib.sha256(SRC.read_bytes()).hexdigest(),
    "crop_box_xyxy": [int(x0), int(y0), int(x1), int(y1)],
    "paper_level": round(paper, 4), "ink_level": round(ink, 4),
    "output": str(OUT.relative_to(ROOT)).replace("\\", "/"),
    "output_size": [int(crop.shape[1]), int(crop.shape[0])],
    "output_sha256": hashlib.sha256(OUT.read_bytes()).hexdigest(),
}
(OUT_DIR / "title_logo_mask.receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(receipt, ensure_ascii=False))
