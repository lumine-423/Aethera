"""Trace the card's world map vectors into a light Godot data file for the mystic map.

Source (read-only): F:/sigil-circuit/sigil-workbench.html -> SIG_BASE_INNER (the card's 1600x900
vector map: 17 stroked path layers over map-base.jpg). Only the strokes are reused; the parchment
photo is not. Layers kept (by original stroke):
  coast   #232E38  coastlines
  border  #9C3C6E / #816161 / #9B4F46 (2.1px)  inland country borders
  route   #BDAA7E dashed   dashed region / route lines
  relief  #595753  mountain marks
  river   #039499  rivers
The dense province-cell layer (#94855F 0.7px) and the per-country coast duplicates are dropped.
Polylines are simplified with Ramer-Douglas-Peucker (tolerance below) so the file stays small.
Output: data/map/world_lines.json
"""
import json
import re
from pathlib import Path

SRC = Path("F:/sigil-circuit/sigil-workbench.html")
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data/map/world_lines.json"
KEEP = {"#232E38": ("coast", 0.45), "#9C3C6E|2.1": ("border", 0.5), "#816161|2.1": ("border", 0.5),
        "#9B4F46|2.1": ("border", 0.5), "#BDAA7E": ("route", 0.6), "#595753": ("relief", 0.25), "#039499": ("river", 0.8)}

t = SRC.read_text(encoding="utf-8")
i = t.index("SIG_BASE_INNER =")
j = t.index('";', i)
svg = json.loads(t[i + len("SIG_BASE_INNER ="):j + 1].strip())


def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    (x0, y0), (x1, y1) = pts[0], pts[-1]
    dx, dy = x1 - x0, y1 - y0
    n = (dx * dx + dy * dy) ** 0.5 or 1e-9
    best, idx = -1.0, 0
    for k in range(1, len(pts) - 1):
        px, py = pts[k]
        d = abs(dy * px - dx * py + x1 * y0 - y1 * x0) / n if n > 1e-6 else ((px - x0) ** 2 + (py - y0) ** 2) ** 0.5
        if d > best:
            best, idx = d, k
    if best <= eps:
        return [pts[0], pts[-1]]
    return rdp(pts[: idx + 1], eps)[:-1] + rdp(pts[idx:], eps)


layers = {}
stats = {}
for m in re.finditer(r'<path([^>]*?)d="([^"]*)"([^>]*)>', svg):
    at = m.group(1) + m.group(3)
    stroke = re.search(r'stroke="([^"]+)"', at).group(1)
    width = re.search(r'stroke-width="([^"]+)"', at).group(1)
    key = stroke if stroke in KEEP else f"{stroke}|{width}"
    if key not in KEEP:
        continue
    name, eps = KEEP[key]
    toks = re.findall(r"[MLZ]|-?\d*\.?\d+", m.group(2))
    lines, cur, k, cmd = [], None, 0, ""
    while k < len(toks):
        tk = toks[k]
        if tk in "MLZ":
            cmd = tk
            k += 1
            if tk == "Z" and cur:
                cur.append(cur[0])
            continue
        x, y = float(toks[k]), float(toks[k + 1])
        k += 2
        if cmd == "M":
            cur = [(x, y)]
            lines.append(cur)
            cmd = "L"
        else:
            cur.append((x, y))
    for ln in lines:
        s = rdp(ln, eps)
        if len(s) >= 2:
            flat = []
            for x, y in s:
                flat += [round(x, 1), round(y, 1)]
            layers.setdefault(name, []).append(flat)
    stats[name] = stats.get(name, 0) + sum(len(l) for l in lines)

OUT.parent.mkdir(parents=True, exist_ok=True)
data = {"_note": "Traced from the card's SIG_BASE_INNER vector map by tools/build_mystic_map.py; 1600x900 frame. Do not hand-edit.",
        "view": [1600, 900], "layers": layers}
OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print({k: (len(v), sum(len(x) // 2 for x in v), stats.get(k)) for k, v in layers.items()}, OUT.stat().st_size)
