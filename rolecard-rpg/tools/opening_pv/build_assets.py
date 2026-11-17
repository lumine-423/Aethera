# -*- coding: utf-8 -*-
"""开场PV素材预处理：把白名单素材转成渲染用缓存（不进Godot运行时）。

输出：workspaces/frontend-ui/materials/opening-pv-20261116/cache/
  - illus/<角色>_<序号>.jpg   竖图按动漫人脸检测截取脸部，横图整张缩放
  - cut/<角色>.png            21人透明抠图，裁到不透明边界
  - lib/<角色>.png            有解放立绘的角色，留作剪影闪切
  - npc/<id>.png              8名NPC 1536p正式立绘
  - region/<名>.jpg           24张国家地区图
  - bgx/<文件>.jpg            游戏内正式背景（按国家补闪）
  - eye/ poly/ world/         包A、包B、艾瑟拉.png
  - grp/<组>/f_0001.jpg..     8组OP动画抽帧
  - assets.json               全部条目与人脸框
运行：python build_assets.py   （可重复运行；已存在的文件跳过）
"""
import os, re, json, sys, glob
import numpy as np
from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")
HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = r"F:\艾瑟拉"
OUT = os.path.join(PROJ, "workspaces", "frontend-ui", "materials", "opening-pv-20261116", "cache")
MAT = os.path.join(PROJ, "workspaces", "frontend-ui", "materials", "opening-art-20261116")
CUTS = os.path.join(PROJ, "workspaces", "frontend-ui", "incoming", "opening-character-cutouts", "characters")
OPM = r"F:\sigil-circuit\_out\op-multi"
CASCADE = os.environ.get("ANIMEFACE_XML", os.path.join(HERE, "lbpcascade_animeface.xml"))

CHARS = ["凛零", "梅林", "瓦尔基里", "冰糖", "安克", "卡斯特", "暧", "焰渊", "墨华", "轩辕", "明空",
         "路西法", "阿兰雅", "筏摩娜", "艾利丝", "拉伦提娅", "瓦沙克", "阳向", "茧", "露珐", "叶子"]
NPCS = ["drago", "solanu", "edgar", "tiya", "varsha", "victor", "satou", "xiaoai"]
BANNED = ("色图", "原裸图", "_discarded", ".gif")


def banned(p):
    return any(b in p for b in BANNED)


def key(n):
    m = re.findall(r"\d+", n)
    return ("SeedVR" in n, int(m[0]) if m else 0, n)


def illus_list(c):
    d = os.path.join(SRC, c)
    fs = [f for f in os.listdir(d) if f.endswith(".png") and not banned(f)
          and f not in (c + ".png", c + "解放.png", "叶.png")]
    fs.sort(key=key)
    return [os.path.join(d, f) for f in fs]


def mk(*p):
    path = os.path.join(OUT, *p)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    return path


def save_rgb(im, path, q=92):
    im.convert("RGB").save(path, quality=q)


def face_box(im, det):
    g = np.array(im.convert("L"))
    s = 900.0 / max(g.shape)
    small = np.array(Image.fromarray(g).resize((int(g.shape[1] * s), int(g.shape[0] * s))))
    import cv2
    small = cv2.equalizeHist(small)
    faces = det.detectMultiScale(small, scaleFactor=1.05, minNeighbors=4, minSize=(48, 48))
    # 竖图人脸几乎都在上半部；落在下半部的多为误检（手臂、灯笼、水果）
    faces = [f for f in faces if (f[1] + f[3] / 2) < small.shape[0] * 0.52]
    if len(faces) == 0:
        return None
    x, y, w, h = max(faces, key=lambda f: f[2] * f[3])
    return [int(x / s), int(y / s), int(w / s), int(h / s)]


def crop_face(im, fb, aspect=1.12):
    W, H = im.size
    if fb is None:  # 兜底：上部居中
        ch = int(min(H * 0.46, W / aspect))
        cx, cy = W / 2, H * 0.27
    else:
        x, y, w, h = fb
        ch = int(min(H, max(h * 3.1, W / aspect * 0.55)))
        cx, cy = x + w / 2, y + h * 0.62
    cw = int(min(W, ch * aspect))
    ch = int(cw / aspect)
    l = int(min(max(cx - cw / 2, 0), W - cw))
    t = int(min(max(cy - ch * 0.42, 0), H - ch))
    return im.crop((l, t, l + cw, t + ch)), [l, t, cw, ch]


def main():
    sel = json.load(open(os.path.join(HERE, "selection.json"), encoding="utf-8"))
    import cv2
    det = cv2.CascadeClassifier(CASCADE)
    if det.empty():
        raise SystemExit("缺少动漫人脸模型 " + CASCADE)
    A = {"illus": {}, "cut": {}, "lib": {}, "npc": {}, "region": {}, "bgx": {}, "grp": []}

    for c in CHARS:
        files = illus_list(c)
        A["illus"][c] = []
        for i in sel["illustrations"][c]:
            src = files[i]
            assert not banned(src)
            im = Image.open(src).convert("RGB")
            W, H = im.size
            out = mk("illus", "%s_%02d.jpg" % (c, i))
            ent = {"src": os.path.basename(src), "w": W, "h": H, "file": os.path.relpath(out, OUT)}
            if H > W:
                ov = sel.get("face_override", {}).get(c + "/" + os.path.basename(src))
                if ov:
                    fh = ov[2] * H
                    fb = [int(ov[0] * W - fh / 2), int(ov[1] * H - fh / 2), int(fh), int(fh)]
                else:
                    fb = face_box(im, det)
                cr, box = crop_face(im, fb)
                ent.update(kind="face", face=fb, crop=box)
                if not os.path.exists(out):
                    cr.thumbnail((1500, 1500), Image.LANCZOS)
                    save_rgb(cr, out)
                full = mk("illusf", "%s_%02d.jpg" % (c, i))
                if not os.path.exists(full):
                    fim = im.copy()
                    fim.thumbnail((1800, 1800), Image.LANCZOS)
                    save_rgb(fim, full)
                ent["full"] = os.path.relpath(full, OUT)
            else:
                ent.update(kind="wide")
                ent["full"] = ent["file"]
                if not os.path.exists(out):
                    im.thumbnail((2000, 2000), Image.LANCZOS)
                    save_rgb(im, out)
            A["illus"][c].append(ent)
        # 抠图
        cp = os.path.join(CUTS, c + ".png")
        out = mk("cut", c + ".png")
        if not os.path.exists(out):
            im = Image.open(cp).convert("RGBA")
            bb = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
            im = im.crop(bb)
            s = 1500.0 / im.size[1]
            im = im.resize((int(im.size[0] * s), 1500), Image.LANCZOS)
            im.save(out)
        A["cut"][c] = os.path.relpath(out, OUT)
        lp = os.path.join(SRC, c, c + "解放.png")
        if os.path.exists(lp):
            out = mk("lib", c + ".png")
            if not os.path.exists(out):
                im = Image.open(lp).convert("RGBA")
                im.thumbnail((1400, 1400), Image.LANCZOS)
                im.save(out)
            A["lib"][c] = os.path.relpath(out, OUT)
        print("char", c, len(A["illus"][c]))

    for n in NPCS:
        out = mk("npc", n + ".png")
        if not os.path.exists(out):
            im = Image.open(os.path.join(PROJ, "assets", "characters", n, "daily", "neutral.webp")).convert("RGBA")
            bb = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
            im = im.crop(bb)
            im.thumbnail((1500, 1500), Image.LANCZOS)
            im.save(out)
        A["npc"][n] = os.path.relpath(out, OUT)

    for p in sorted(glob.glob(os.path.join(SRC, "国家及地区", "*.png"))):
        nm = os.path.splitext(os.path.basename(p))[0]
        out = mk("region", nm + ".jpg")
        if not os.path.exists(out):
            im = Image.open(p).convert("RGB")
            im.thumbnail((2400, 2400), Image.LANCZOS)
            save_rgb(im, out)
        A["region"][nm] = os.path.relpath(out, OUT)

    ai = json.load(open(os.path.join(PROJ, "data", "content", "art_index.json"), encoding="utf-8"))
    for b in ai["backgrounds"]:
        if b["kind"] != "base":
            continue
        fn = os.path.basename(b["res"])
        out = mk("bgx", os.path.splitext(fn)[0] + ".jpg")
        if not os.path.exists(out):
            im = Image.open(os.path.join(PROJ, "assets", "backgrounds", fn)).convert("RGB")
            im.thumbnail((2000, 2000), Image.LANCZOS)
            save_rgb(im, out, 88)
        A["bgx"].setdefault(b["country"], []).append({"file": os.path.relpath(out, OUT), "area": b["area"], "name": b["name"]})

    for f in sorted(glob.glob(os.path.join(MAT, "package-a", "v01", "*.png"))):
        out = mk("eye", os.path.basename(f))
        if not os.path.exists(out):
            Image.open(f).save(out)
    for f in sorted(glob.glob(os.path.join(MAT, "package-b", "v01-static-bases", "*.png"))):
        out = mk("poly", os.path.basename(f))
        if not os.path.exists(out):
            im = Image.open(f).convert("RGBA")
            im.thumbnail((900, 900), Image.LANCZOS)
            im.save(out)
    for nm in ("艾瑟拉.png", "艾瑟拉2.png"):
        out = mk("world", nm.replace(".png", ".jpg"))
        if not os.path.exists(out):
            im = Image.open(os.path.join(SRC, nm)).convert("RGB")
            im.thumbnail((2400, 2400), Image.LANCZOS)
            save_rgb(im, out)

    for g in sel["group_clips"]:
        assert not banned(g)
        name = os.path.basename(g)
        frames = sorted(glob.glob(os.path.join(OPM, g, "f_*.png")))
        for f in frames:
            out = mk("grp", name, os.path.basename(f).replace(".png", ".jpg"))
            if not os.path.exists(out):
                save_rgb(Image.open(f), out, 93)
        A["grp"].append({"name": name, "frames": len(frames), "dir": os.path.join("grp", name)})
        print("group", name, len(frames))

    json.dump(A, open(os.path.join(OUT, "assets.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("done", OUT)


if __name__ == "__main__":
    main()
