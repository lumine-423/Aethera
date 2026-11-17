# -*- coding: utf-8 -*-
"""《艾瑟拉》2分19秒开场PV 离线逐帧渲染器 v2（1920x1080 / 30fps）。

v2 按 2026-11-17 用户逐段意见重做：
  - 故障风只用黑白色，只出现在画面边缘或指定位置（约占 20~40%），五种：
    扫描线抖动 gx_scan、波动抖动 gx_wave、模拟噪点 analog、错位图块 gx_block、数字条纹 gx_stripe
  - 五以太多面体改为程序建模的 3D 实体缓慢旋转（render_poly）
  - 字体参考游戏 UI：细长、玲珑的 Noto Serif SC 细体（slim）
  - 地区段改为世界地图光柱 + 游戏内地区背景；角色段只给名字；NPC 段改为问号/报错 + 打码小艾
  - 动画段大量抽帧；文字段信息过载；倒放紧接终句消失、黑白 + 噪点

素材先由 build_assets.py 生成到 materials/opening-pv-20261116/cache/。
  python render.py --pass 1           # 除倒放段外的全部帧
  python render.py --pass 2           # 倒放段（读取第1遍的帧）
  python render.py --preview 1.5,8,50 # 只渲染指定秒数到预览拼图
节拍以 crystar.ogg 实测：200BPM 网格 g(k)=41.366+0.3k。
"""
import os, sys, json, math, zlib, functools, argparse
from itertools import combinations
import numpy as np
import cv2
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.abspath(os.path.join(HERE, "..", ".."))
MAT = os.path.join(PROJ, "workspaces", "frontend-ui", "materials", "opening-pv-20261116")
CACHE = os.path.join(MAT, "cache")
FRAMES = os.environ.get("OPV_FRAMES", os.path.join(MAT, "_frames"))
W, H, FPS = 1920, 1080, 30
DUR = 139.2
NF = int(round(DUR * FPS))
BG = (11, 10, 14)
SERIF = os.path.join(PROJ, "assets", "fonts", "NotoSerifSC.ttf")
KAI = r"C:\Windows\Fonts\STKAITI.TTF"
SONG = r"C:\Windows\Fonts\simsun.ttc"
HEI = r"C:\Windows\Fonts\simhei.ttf"
MONO = r"C:\Windows\Fonts\consola.ttf"
if not os.path.exists(MONO):
    MONO = HEI
WHITE = (240, 236, 228)
RED = (204, 34, 52)
GOLD = (214, 178, 108)

A = json.load(open(os.path.join(CACHE, "assets.json"), encoding="utf-8"))
CONTENT = json.load(open(os.path.join(PROJ, "data", "content", "contest_content.json"), encoding="utf-8"))
OP = CONTENT["opening"]
CAST = {e["name"]: e for e in CONTENT["cast"]}
CAST["叶子"] = CAST["叶"]


def g(k):
    return 41.366 + 0.3 * k


# ---------------- 时间轴 ----------------
# v3：按实测强拍重新卡点（见 docs/opening-pv-v3 节拍表；网格 g(k) 相位误差 <10ms）
T_HIT = 2.94
POLY_T = [3.566, 5.366, 7.466, 9.716, 11.216]   # 五段发条琶音的乐句起点
T_P0 = POLY_T[0]
T_ORB = 12.551
T_CONV = 20.516
T_CRACK = 21.721
T2 = 22.166
T2E = 41.366
T3 = 41.966
T_Q = 73.466
T_XA = 77.816
T_FACE = 79.316
T_SMILE = 81.644
T_XOUT = 82.466
T4 = 82.766
T_ROLL = 100.766
T5 = 102.566
T_PLEASE = 116.966
T_FINAL = 119.666
T_FMID = 120.416
T_FBIG = 121.166
T_DIS = 121.916
T6 = 122.516
T_GAZE = 131.0
T_CLOSE = 135.566
REV_S0 = T6 - 1.0 / FPS
REV_S1 = 2.70

# 用户指定的出场顺序（2026-11-17）
CHARS = ["凛零", "梅林", "墨华", "叶子", "卡斯特", "瓦尔基里", "冰糖", "安克", "茧", "阿兰雅", "筏摩娜",
         "明空", "路西法", "暧", "焰渊", "轩辕", "拉伦提娅", "露珐", "阳向", "瓦沙克", "艾利丝"]
EYES = ["eye/eye_01_closed.png", "eye/eye_02_slit.png", "eye/eye_03_open20.png",
        "eye/eye_04_open40.png", "eye/eye_05_open60.png", "eye/eye_06_open100.png"]
MEMBERS = [["凛零", "梅林", "墨华"], ["瓦尔基里", "卡斯特", "叶子"], ["安克", "冰糖", "阳向"],
           ["路西法", "暧", "明空"], ["焰渊", "轩辕"], ["茧", "阿兰雅", "筏摩娜"], ["露珐", "拉伦提娅"],
           ["艾利丝", "瓦沙克"]]
# 地区段：(地区名, 所属国家, 游戏内背景, 世界地图坐标[1600x900])
PLACES = [("中央学院", "塞蕾特公国", "ACA01-day-v1", (905, 256)),
          ("卡米洛特宫", "塞蕾特公国", "PAL01-day-v1", (918, 242)),
          ("尼德霍格区", "塞蕾特公国", "NID01-day-v1", (963.5, 362.4)),
          ("奥马努特", "奥马努特", "ART00-day-v1", (862, 300)),
          ("地下市场", "奥马努特", "MKT01-day-v1", (876, 288)),
          ("齐哈特大沙漠", "奥马努特", "DES03-day-v1", (765, 336)),
          ("紫宸宫", "龙渊帝国", "LON02-day-v1", (1442.3, 435.6)),
          ("灵山", "龙渊帝国", "LIN03-day-v1", (1339.2, 479.3)),
          ("须弥王庭", "吉万沙克蒂", "JIV00-day-v1", (616, 463)),
          ("梵音林", "吉万沙克蒂", "JIV08-day-v1", (662.4, 528.6)),
          ("库利亚", "格洛里亚", "GLO00-day-v1", (394, 605.5)),
          ("堤丰之喉", "格洛里亚", "GLO06-day-v1", (322.5, 466.6)),
          ("云樱", "秋津国", "AKI00-day-v1", (288.3, 153.7)),
          ("基捷日", "哥塔薇亚帝国", "GOT01-day-v1", (1432.3, 133.2)),
          ("阿拉提尔", "哥塔薇亚帝国", "ICE01-day-v1", (1410.2, 57.4)),
          ("天国岛", "塞蕾特公国", "ISL04-day-v1", (1116.2, 100.8))]
# 人格化系统的报错（用户 2026-11-17 指定风格：【存在错误】【异常】【需要修正】……）
QMSG = ["【存在错误】", "【异常】", "【需要修正】", "【无法识别】", "【观测失败】", "【记录缺失】",
        "【禁止访问】", "【此处不应存在】", "【你看见了吗】", "【不可以】", "【未知个体】",
        "【错误·错误·错误】", "【请勿注视】", "【修正中……】", "【权限不足】", "【世界线偏移】",
        "【她不在名册上】", "【检测到异常存在】", "【无法命名】", "【不要靠近】", "【回收失败】",
        "【再确认一次】", "【为什么会在这里】", "【请忘记】"]


# ---------------- 小工具 ----------------
def cl(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def eo(x):
    x = cl(x)
    return 1 - (1 - x) ** 3


def ei(x):
    x = cl(x)
    return x ** 3


def eio(x):
    x = cl(x)
    return x * x * (3 - 2 * x)


def lerp(a, b, t):
    return a + (b - a) * t


def R(*k):
    return np.random.default_rng(zlib.crc32(repr(k).encode("utf-8")))


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def fidx(t):
    return int(round(t * FPS))


def lf(t, t0):
    return int(math.floor((t - t0) * FPS + 1e-4))


@functools.lru_cache(maxsize=28)
def img(rel, mode="RGB"):
    p = rel if os.path.isabs(rel) else os.path.join(CACHE, rel)
    return Image.open(p).convert(mode)


def cover(im, size, z=1.0, px=0.0, py=0.0):
    tw, th = int(size[0]), int(size[1])
    iw, ih = im.size
    s = max(tw / iw, th / ih) * max(z, 1.0)
    cw, ch = tw / s, th / s
    cx = iw / 2 + cl(px, -1, 1) * (iw - cw) / 2
    cy = ih / 2 + cl(py, -1, 1) * (ih - ch) / 2
    x0 = cl(cx - cw / 2, 0, iw - cw)
    y0 = cl(cy - ch / 2, 0, ih - ch)
    return im.resize((tw, th), Image.BILINEAR, box=(max(0.0, x0), max(0.0, y0), min(iw, x0 + cw), min(ih, y0 + ch)))


@functools.lru_cache(maxsize=48)
def _flash_parts(rel):
    im = img(rel)
    base = cover(im, (W // 4, H // 4), 1.2).filter(ImageFilter.GaussianBlur(10)).resize((W, H), Image.BILINEAR)
    base = base.point(lambda v: int(v * 0.38))
    return im, base


def flash_img(rel, z=1.0, px=0.0):
    """闪回插图：横图铺满；竖图/方图整张放进画面（不只截到身体中段），底下垫一层模糊压暗的同图。"""
    im, base = _flash_parts(rel)
    iw, ih = im.size
    if iw / ih >= 1.5:
        return cover(im, (W, H), z, px, 0)
    F = base.copy()
    s = H / ih * z
    fg = im.resize((max(1, int(iw * s)), max(1, int(ih * s))), Image.BILINEAR)
    F.paste(fg, (int(W / 2 - fg.width / 2 + px * 60), int(H / 2 - fg.height / 2)))
    return F


def zf(F, z, cx=W / 2, cy=H / 2):
    if abs(z - 1) < 1e-4:
        return F
    return F.resize((W, H), Image.BILINEAR, box=(max(0.0, cx - cx / z), max(0.0, cy - cy / z),
                                                 min(W, cx + (W - cx) / z), min(H, cy + (H - cy) / z)))


def amul(im, a):
    if a >= 0.999:
        return im
    r = im.copy()
    r.putalpha(r.getchannel("A").point(lambda v: int(v * a)))
    return r


def put(F, im, cx, cy, a=1.0, s=1.0, rot=0.0, sx=1.0):
    if a <= 0.003 or s <= 0.002:
        return
    if abs(s - 1) > 1e-3 or abs(sx - 1) > 1e-3:
        im = im.resize((max(1, int(im.width * s * sx)), max(1, int(im.height * s))), Image.BILINEAR)
    if rot:
        im = im.rotate(rot, Image.BILINEAR, expand=True)
    im = amul(im, a)
    F.paste(im, (int(round(cx - im.width / 2)), int(round(cy - im.height / 2))), im)


def put_tl(F, im, x, y, a=1.0):
    if a <= 0.003:
        return
    im = amul(im, a)
    F.paste(im, (int(round(x)), int(round(y))), im)


@functools.lru_cache(maxsize=64)
def font(path, size, wt=0):
    f = ImageFont.truetype(path, int(size))
    if wt:
        try:
            f.set_variation_by_axes([wt])
        except Exception:
            pass
    return f


@functools.lru_cache(maxsize=900)
def timg(s, path=SERIF, size=40, wt=400, fill=WHITE, stroke=0, sfill=(0, 0, 0), track=0, vertical=False):
    f = font(path, size, wt)
    pad = stroke + 6
    fl = tuple(fill) + (255,) if len(fill) == 3 else tuple(fill)
    sf = tuple(sfill) + (255,) if len(sfill) == 3 else tuple(sfill)
    if vertical:
        cell = size + track
        w = size + 2 * pad
        h = int(cell * len(s) - track + 2 * pad)
        im = Image.new("RGBA", (int(w), max(h, 4)), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        for i, c in enumerate(s):
            d.text((w / 2, pad + i * cell + size / 2), c, font=f, fill=fl, anchor="mm", stroke_width=stroke, stroke_fill=sf)
        return im
    asc, desc = f.getmetrics()
    ws = [f.getlength(c) for c in s]
    w = int(sum(ws) + track * max(0, len(s) - 1) + 2 * pad)
    h = int(asc + desc + 2 * pad)
    im = Image.new("RGBA", (max(w, 4), h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x = pad
    for c, cw in zip(s, ws):
        d.text((x, pad), c, font=f, fill=fl, stroke_width=stroke, stroke_fill=sf)
        x += cw + track
    return im


@functools.lru_cache(maxsize=800)
def slim(s, size, wt=260, fill=WHITE, squeeze=0.80, track=0, vertical=False, shadow=0.55):
    """参考游戏UI字标的细长玲珑字：Noto Serif SC 细体 + 横向收窄 + 柔和暗影托底。"""
    f = font(SERIF, size, wt)
    pad = int(size * 0.18) + 8
    if vertical:
        cell = size * 1.06 + track
        w = int(size * 1.3) + 2 * pad
        h = int(cell * len(s)) + 2 * pad
        L = Image.new("L", (w, max(h, 4)), 0)
        d = ImageDraw.Draw(L)
        for i, c in enumerate(s):
            d.text((w / 2, pad + cell * i + cell / 2), c, font=f, fill=255, anchor="mm")
    else:
        ws = [f.getlength(c) for c in s]
        asc, desc = f.getmetrics()
        w = int(sum(ws) + track * max(0, len(s) - 1)) + 2 * pad
        h = asc + desc + 2 * pad
        L = Image.new("L", (max(w, 4), h), 0)
        d = ImageDraw.Draw(L)
        x = pad
        for c, cw in zip(s, ws):
            d.text((x, pad), c, font=f, fill=255)
            x += cw + track
    L = L.resize((max(1, int(L.width * squeeze)), L.height), Image.LANCZOS)
    out = Image.new("RGBA", L.size, (0, 0, 0, 0))
    if shadow:
        sh = L.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(max(2, size / 16))).point(lambda v: int(min(255, v * 1.6) * shadow))
        out.paste(Image.new("RGBA", L.size, (0, 0, 0, 255)), (0, 0), sh)
    fl = tuple(fill) + (255,) if len(fill) == 3 else tuple(fill)
    out.paste(Image.new("RGBA", L.size, fl), (0, 0), L)
    return out


def mask():
    return np.zeros((H, W), np.uint8)


def _p(p):
    return (int(p[0] * 16), int(p[1] * 16))


def ln(m, p0, p1, th=1):
    cv2.line(m, _p(p0), _p(p1), 255, th, cv2.LINE_AA, 4)


def circ(m, c, r, th=1):
    if r > 0:
        cv2.circle(m, _p(c), int(r * 16), 255, th, cv2.LINE_AA, 4)


def arc(m, c, ax, ang, a0, a1, th=1):
    cv2.ellipse(m, _p(c), (int(ax[0] * 16), int(ax[1] * 16)), ang, a0, a1, 255, th, cv2.LINE_AA, 4)


def pl(m, pts, closed=True, th=1, fill=False):
    arr = [np.int32(np.array(pts) * 16)]
    if fill:
        cv2.fillPoly(m, arr, 255, cv2.LINE_AA, 4)
    else:
        cv2.polylines(m, arr, closed, 255, th, cv2.LINE_AA, 4)


def star_pts(c, Rr, w, rot=0.0):
    pts = []
    for k in range(8):
        ang = rot + k * math.pi / 4
        rr = Rr if k % 2 == 0 else w
        pts.append((c[0] + rr * math.cos(ang), c[1] + rr * math.sin(ang)))
    return pts


def star4(m, c, Rr, w, rot=0.0):
    pl(m, star_pts(c, Rr, w, rot), fill=True)


def ink(F, m, color, a=1.0):
    if a <= 0.003:
        return
    mi = Image.fromarray(m)
    if a < 0.999:
        mi = mi.point(lambda v: int(v * a))
    F.paste(Image.new("RGB", (W, H), color), (0, 0), mi)


@functools.lru_cache(maxsize=1)
def _gs():
    y, x = np.mgrid[-1:1:256j, -1:1:256j]
    return Image.fromarray((np.exp(-(x * x + y * y) * 4.2) * 255).astype(np.uint8))


def glow(F, c, r, color, a):
    r = int(r)
    if r < 2 or a <= 0.003:
        return
    m = _gs().resize((2 * r, 2 * r), Image.BILINEAR)
    if a < 0.999:
        m = m.point(lambda v: int(v * a))
    F.paste(Image.new("RGB", (2 * r, 2 * r), color), (int(c[0] - r), int(c[1] - r)), m)


# ================= 黑白故障效果库（作用在 HxWx3 float32 数组上） =================
_G = {}


def _noise(k):
    if "n" not in _G:
        r = np.random.default_rng(11)
        _G["n"] = [r.standard_normal((H, W)).astype(np.float32) for _ in range(5)]
    return _G["n"][k % 5]


def _rad():
    if "r" not in _G:
        yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
        nx = (xx - W / 2) / (W / 2)
        ny = (yy - H / 2) / (H / 2)
        r = np.sqrt(nx * nx + ny * ny)
        _G["r"] = r
        _G["edge"] = (np.clip((r - 0.62) / 0.5, 0, 1) ** 1.3)
        _G["edge2"] = (np.clip((r - 0.40) / 0.7, 0, 1) ** 1.2)
        _G["vig"] = (1 - 0.5 * np.clip((r - 0.45) / 0.95, 0, 1) ** 1.6)[..., None]
    return _G


def _gray(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def _feather(n, f):
    y = np.arange(n, dtype=np.float32)
    return np.clip(np.minimum(y + 1, n - y) / max(1.0, f), 0, 1)


def _clip_box(x0, y0, x1, y1):
    return int(cl(x0, 0, W)), int(cl(y0, 0, H)), int(cl(x1, 0, W)), int(cl(y1, 0, H))


def gx_scan(a, y0, y1, amp, fi, x0=0, x1=W, seed=0, k=1.0, smear=31, bright=1.2):
    """扫描线抖动：带内各行随机横移 + 横向拖影，黑白。"""
    x0, y0, x1, y1 = _clip_box(x0, y0, x1, y1)
    if y1 - y0 < 3 or x1 - x0 < 8 or k <= 0.01 or amp < 1:
        return a
    sub = a[y0:y1, x0:x1]
    h, w = sub.shape[:2]
    g = _gray(sub)
    r = R("scan", fi, seed)
    n = h // 2 + 2
    sh = r.integers(-int(amp), int(amp) + 1, size=n) * (r.random(n) < 0.8)
    big = r.random(n) < 0.08
    sh = np.where(big, sh * 3, sh)
    sh = np.repeat(sh, 2)[:h]
    idx = (np.arange(w)[None, :] - sh[:, None]) % w
    out = g[np.arange(h)[:, None], idx]
    if smear > 1:
        out = out * 0.4 + cv2.blur(out, (int(smear), 1)) * 0.6
    out = np.clip(out * bright, 0, 255)
    m = _feather(h, 10)[:, None] * k
    if x0 > 0 or x1 < W:
        m = m * _feather(w, 40)[None, :]
    sub[:] = sub * (1 - m[..., None]) + out[..., None] * m[..., None]
    return a


def gx_wave(a, y0, y1, amp, fi, x0=0, x1=W, seed=0, k=1.0, freq=0.035):
    """波动抖动：带内按正弦波横向扭曲，黑白。"""
    x0, y0, x1, y1 = _clip_box(x0, y0, x1, y1)
    if y1 - y0 < 3 or x1 - x0 < 8 or k <= 0.01 or amp < 0.5:
        return a
    sub = a[y0:y1, x0:x1]
    h, w = sub.shape[:2]
    g = _gray(sub)
    yy = np.arange(h, dtype=np.float32) + y0
    ph = fi * 0.9 + seed
    sh = amp * np.sin(yy * freq + ph) + amp * 0.35 * np.sin(yy * freq * 3.3 - ph * 1.7)
    sh = sh.astype(np.int32)
    idx = (np.arange(w)[None, :] - sh[:, None]) % w
    out = g[np.arange(h)[:, None], idx]
    out = out * 0.6 + cv2.blur(out, (9, 1)) * 0.4
    m = _feather(h, 18)[:, None] * k
    if x0 > 0 or x1 < W:
        m = m * _feather(w, 50)[None, :]
    sub[:] = sub * (1 - m[..., None]) + out[..., None] * m[..., None]
    return a


def gx_block(a, x0, y0, x1, y1, n, fi, seed=0, bw=(40, 280), bh=(10, 90), disp=140):
    """错位图块：区域内随机矩形块错位/反相/纯色/马赛克，黑白。"""
    x0, y0, x1, y1 = _clip_box(x0, y0, x1, y1)
    if x1 - x0 < 20 or y1 - y0 < 10 or n <= 0:
        return a
    r = R("blk", fi, seed)
    for _ in range(int(n)):
        w = int(min(r.integers(bw[0], bw[1] + 1), x1 - x0))
        h = int(min(r.integers(bh[0], bh[1] + 1), y1 - y0))
        bx = int(r.integers(x0, max(x0 + 1, x1 - w)))
        by = int(r.integers(y0, max(y0 + 1, y1 - h)))
        sx = int(cl(bx + r.integers(-disp, disp + 1), 0, W - w))
        sy = int(cl(by + r.integers(-disp // 4, disp // 4 + 1), 0, H - h))
        src = _gray(a[sy:sy + h, sx:sx + w])
        mode = r.random()
        if mode < 0.48:
            blk = src * 1.1
        elif mode < 0.68:
            blk = 255 - src
        elif mode < 0.80:
            blk = np.full_like(src, 236)
        elif mode < 0.90:
            blk = np.full_like(src, 6)
        else:
            q = max(1, w // 10)
            blk = cv2.resize(cv2.resize(src, (max(1, w // q), max(1, h // q)), interpolation=cv2.INTER_AREA),
                             (w, h), interpolation=cv2.INTER_NEAREST)
        a[by:by + h, bx:bx + w] = np.clip(blk, 0, 255)[..., None]
    return a


def gx_stripe(a, y0, y1, n, fi, x0=0, x1=W, seed=0):
    """数字条纹：横向细条（白/黑/反相/错行），可整行或片段，黑白。"""
    x0, y0, x1, y1 = _clip_box(x0, y0, x1, y1)
    if y1 - y0 < 2 or n <= 0:
        return a
    r = R("str", fi, seed)
    for _ in range(int(n)):
        y = int(r.integers(y0, max(y0 + 1, y1)))
        h = int(r.choice([1, 1, 2, 2, 3, 4, 6, 9, 14, 20]))
        y2 = min(H, y + h)
        if r.random() < 0.55:
            sx0, sx1 = x0, x1
        else:
            L = int(r.integers(80, max(81, (x1 - x0))))
            sx0 = int(r.integers(x0, max(x0 + 1, x1 - L)))
            sx1 = min(x1, sx0 + L)
        seg = a[y:y2, sx0:sx1]
        if seg.size == 0:
            continue
        mode = r.random()
        g = _gray(seg)
        if mode < 0.35:
            v = np.full_like(g, 238 * r.uniform(0.7, 1.0))
        elif mode < 0.55:
            v = np.full_like(g, 8)
        elif mode < 0.8:
            v = 255 - g
        else:
            v = np.roll(g, int(r.integers(-300, 300)), 1)
        al = r.uniform(0.6, 1.0)
        seg[:] = seg * (1 - al) + v[..., None] * al
        if r.random() < 0.18:  # 梳状细线组
            for j in range(1, 4):
                yy = y2 + j * 4
                if yy < H:
                    a[yy, sx0:sx1] = a[yy, sx0:sx1] * 0.4 + 230 * 0.6
    return a


def analog(a, k, fi, lines=True, flick=False):
    """模拟噪点：颗粒 + 偶发横向噪线 + 轻微亮度闪烁（可选偶发褪色帧）。"""
    if k <= 0.01:
        return a
    h, w = a.shape[:2]
    n = np.roll(_noise(fi // 2 + fi % 2 * 3), (fi * 53) % W, 1)[:h, :w]
    a += n[..., None] * 13 * k
    r = R("an", fi)
    if lines:
        for _ in range(int(1 + 3 * k)):
            y = int(r.integers(0, h))
            hh = int(r.integers(1, 3))
            a[y:y + hh] = a[y:y + hh] * 0.6 + 255 * 0.4 * r.random() * min(1.0, k)
    a *= 1 + (r.random() - 0.5) * 0.07 * k
    if flick and r.random() < 0.10:
        gg = a.mean(2, keepdims=True)
        a[:] = a * 0.3 + gg * 0.7
    return a


def fade_arr(a, k):
    """褪色：降饱和、抬黑、压对比，略偏暖。"""
    if k <= 0.01:
        return a
    gg = _gray(a)[..., None]
    a[:] = a * (1 - 0.72 * k) + gg * 0.72 * k
    a[:] = a * (1 - 0.24 * k) + 34 * k
    a += np.array([6, 2, -5], np.float32) * k
    return a


def post(F, fi, vig=1.0, flash=0.0, invert=False, shake=(0, 0), dim=1.0, mem=0.0, sat=1.0, bw=0.0,
         noise=0.0, noise_edge=0.0, fade=0.0, flick=False, fx=None, noise_red=0.0):
    if shake[0] or shake[1]:
        dx, dy = cl(shake[0], -30, 30), cl(shake[1], -17, 17)
        F = F.resize((W, H), Image.BILINEAR, box=(30 + dx, 17 + dy, W - 30 + dx, H - 17 + dy))
    a = np.asarray(F, dtype=np.float32).copy()
    G = _rad()
    if mem:
        small = F.resize((W // 4, H // 4), Image.BILINEAR).filter(ImageFilter.GaussianBlur(7)).resize((W, H), Image.BILINEAR)
        b = np.asarray(small, dtype=np.float32)
        a = 255 - (255 - a) * (255 - b * 0.30 * mem) / 255
        gray = a.mean(2, keepdims=True)
        a = a * (1 - 0.16 * mem) + gray * 0.16 * mem
        a = a * (1 - 0.06 * mem) + 10 * mem
        a += np.array([9, 3, -6], np.float32) * mem
    if sat != 1.0:
        gray = _gray(a)[..., None]
        a = gray + (a - gray) * sat
    if fade:
        fade_arr(a, fade)
    if bw:
        m = (G["edge2"] * bw * 0.6)[..., None]
        a = a * (1 - m) + np.array([248, 240, 228], np.float32) * m
    for f in (fx or []):
        f(a)
    if invert:
        a = 255 - a
    if dim != 1.0:
        a *= dim
    if vig:
        a *= G["vig"] ** vig
    if noise:
        analog(a, noise, fi, flick=flick)
    if noise_edge:
        a += np.roll(_noise(fi // 2 + 2), (fi * 37) % W, 1)[..., None] * (14 * noise_edge) * G["edge"][..., None]
    if noise_red:
        nr = np.abs(np.roll(_noise(fi // 2 + 1), (fi * 71) % W, 1))
        a[..., 0] += nr * 70 * noise_red
        a[..., 1] += nr * 3 * noise_red
        a[..., 2] += nr * 6 * noise_red
    if flash:
        a = a * (1 - flash) + 255 * flash
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


# ================= 五以太多面体 3D 建模 =================
PHI = (1 + 5 ** 0.5) / 2


def _verts(kind):
    if kind == 0:
        return [(1, 1, 1), (1, -1, -1), (-1, 1, -1), (-1, -1, 1)]
    if kind == 1:
        return [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    if kind == 2:
        return [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
    if kind == 3:
        v = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
        for a in (-1, 1):
            for b in (-1, 1):
                v += [(0, a / PHI, b * PHI), (a / PHI, b * PHI, 0), (b * PHI, 0, a / PHI)]
        return v
    v = []
    for a in (-1, 1):
        for b in (-1, 1):
            v += [(0, a, b * PHI), (a, b * PHI, 0), (b * PHI, 0, a)]
    return v


@functools.lru_cache(maxsize=5)
def poly_geo(kind):
    V = np.array(_verts(kind), np.float64)
    V /= np.linalg.norm(V, axis=1).max()
    faces, seen = [], set()
    for i, j, k in combinations(range(len(V)), 3):
        nrm = np.cross(V[j] - V[i], V[k] - V[i])
        L = np.linalg.norm(nrm)
        if L < 1e-9:
            continue
        nrm /= L
        d = nrm @ V[i]
        s = V @ nrm - d
        if s.max() > 1e-6 and s.min() < -1e-6:
            continue
        if s.max() > 1e-6:
            nrm, d = -nrm, -d
        on = tuple(sorted(np.where(np.abs(V @ nrm - d) < 1e-6)[0].tolist()))
        if on in seen:
            continue
        seen.add(on)
        c = V[list(on)].mean(0)
        u = V[on[0]] - c
        u /= np.linalg.norm(u)
        w = np.cross(nrm, u)
        ang = [math.atan2((V[p] - c) @ w, (V[p] - c) @ u) for p in on]
        faces.append(([on[q] for q in np.argsort(ang)], nrm))
    edges = {}
    for fi_, (vs, _) in enumerate(faces):
        for q in range(len(vs)):
            e = tuple(sorted((vs[q], vs[(q + 1) % len(vs)])))
            edges.setdefault(e, []).append(fi_)
    return V, faces, edges


def rotm(ax, ay, az):
    cx, sx = math.cos(ax), math.sin(ax)
    cy, sy = math.cos(ay), math.sin(ay)
    cz, sz = math.cos(az), math.sin(az)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Rx @ Ry


LIGHT = np.array([-0.45, 0.55, 0.70])
LIGHT /= np.linalg.norm(LIGHT)
PEARL = np.array([238, 232, 226], np.float32)
GOLDF = np.array(GOLD, np.float32)
REDF = np.array(RED, np.float32)


POLY_ART = os.path.join(PROJ, "workspaces", "frontend-ui", "materials", "opening-art-20261116", "package-b",
                        "v01-static-bases")
POLY_FILES = ["poly_01_tetra.png", "poly_02_hexa.png", "poly_03_octa.png", "poly_04_dodeca.png", "poly_05_icosa.png"]
# 原画里各取一个正面的晶面（1024 坐标，屏幕顺时针、从上方顶点起）
POLY_SRC_FACE = [[(520, 572), (815, 722), (188, 760)],
                 [(184, 310), (512, 445), (512, 870), (188, 708)],
                 [(500, 135), (718, 575), (318, 578)],
                 [(512, 262), (746, 438), (655, 690), (365, 690), (272, 440)],
                 [(512, 288), (708, 600), (318, 600)]]
TILE = 512


def _tpl(n):
    a0 = -math.pi * 3 / 4 if n == 4 else -math.pi / 2
    return np.float32([(TILE / 2 + 236 * math.cos(a0 + 2 * math.pi * k / n),
                        TILE / 2 + 236 * math.sin(a0 + 2 * math.pi * k / n)) for k in range(n)])


@functools.lru_cache(maxsize=5)
def poly_tile(kind):
    """把原画里的一个晶面拉正成标准正多边形贴图（每个面都贴同一张）。"""
    art = cv2.imread(os.path.join(POLY_ART, POLY_FILES[kind]), cv2.IMREAD_UNCHANGED)
    art = cv2.cvtColor(art, cv2.COLOR_BGRA2RGBA).astype(np.float32)
    src = np.float32(POLY_SRC_FACE[kind])
    src = src.mean(0) + (src - src.mean(0)) * 0.95   # 略向内收，避开原画外轮廓的透明边
    dst = _tpl(len(src))
    if len(src) == 3:
        M = cv2.getAffineTransform(src, dst)
        t = cv2.warpAffine(art, M, (TILE, TILE), flags=cv2.INTER_LINEAR)
    else:
        Hm, _ = cv2.findHomography(src, dst)
        t = cv2.warpPerspective(art, Hm, (TILE, TILE), flags=cv2.INTER_LINEAR)
    m = np.zeros((TILE, TILE), np.uint8)
    cv2.fillPoly(m, [np.int32(dst * 16)], 255, cv2.LINE_AA, 4)
    t[..., 3] = np.minimum(t[..., 3], m.astype(np.float32)) / 255.0
    t[..., 3] = np.maximum(t[..., 3], (m > 0) * 0.85)   # 晶面半透明处也给足覆盖，避免露底
    return t


def render_poly(kind, Rm, rad, t=0.0):
    """3D 正多面体：每个可见面都贴原画晶面贴图，按朝向打光；背面淡淡透出。返回 RGBA。"""
    V, faces, edges = poly_geo(kind)
    P = V @ Rm.T
    S = int(rad * 2.5) + 40
    c = S / 2
    fd = 6.0
    kz = fd / (fd - P[:, 2])
    xy = np.stack([c + P[:, 0] * rad * kz, c - P[:, 1] * rad * kz], 1).astype(np.float32)
    C = np.zeros((S, S, 3), np.float32)
    Aa = np.zeros((S, S), np.float32)

    def blend_k(kk, col):
        C[:] = C * (1 - kk[..., None]) + kk[..., None] * col
        Aa[:] = Aa * (1 - kk) + kk

    def fpoly(pts):
        m = np.zeros((S, S), np.uint8)
        cv2.fillPoly(m, [np.int32(np.array(pts) * 16)], 255, cv2.LINE_AA, 4)
        return m

    def segs(ss, th):
        m = np.zeros((S, S), np.uint8)
        for p, q in ss:
            cv2.line(m, (int(p[0] * 16), int(p[1] * 16)), (int(q[0] * 16), int(q[1] * 16)), 255, th, cv2.LINE_AA, 4)
        return m

    tile = poly_tile(kind)
    n = len(POLY_SRC_FACE[kind])
    tpl = _tpl(n)
    fn = [Rm @ nn for _, nn in faces]
    order = sorted(range(len(faces)), key=lambda i: P[faces[i][0]].mean(0)[2])
    for i in order:
        if fn[i][2] > 0:
            continue
        lam = max(0.0, -fn[i] @ LIGHT)
        blend_k(fpoly(xy[faces[i][0]]).astype(np.float32) / 255 * 0.30, PEARL * (0.62 + 0.2 * lam))
    for i in order:
        if fn[i][2] <= 0:
            continue
        pts = xy[faces[i][0]]
        area = 0.0
        for q in range(len(pts)):
            x1, y1 = pts[q]
            x2, y2 = pts[(q + 1) % len(pts)]
            area += x1 * y2 - x2 * y1
        if area < 0:   # 屏幕上要顺时针，与贴图模板一致
            pts = pts[::-1]
            pts = np.roll(pts, 1, 0)
        if n == 3:
            M = cv2.getAffineTransform(tpl, np.float32(pts))
            w = cv2.warpAffine(tile, M, (S, S), flags=cv2.INTER_LINEAR)
        else:
            Hm, _ = cv2.findHomography(tpl, np.float32(pts))
            w = cv2.warpPerspective(tile, Hm, (S, S), flags=cv2.INTER_LINEAR)
        lam = max(0.0, fn[i] @ LIGHT)
        shade = 0.80 + 0.26 * lam
        kk = w[..., 3] * (fpoly(pts).astype(np.float32) / 255) * 0.96
        blend_k(kk, np.clip(w[..., :3] * shade, 0, 255))
    if kind == 4:  # 悸动：内部红光搏动
        pulse = 0.5 + 0.5 * max(0.0, math.sin(t * 5.2)) ** 2
        yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
        gm = np.exp(-(((xx - c) ** 2 + (yy - c) ** 2) / (rad * 0.22) ** 2))
        blend_k(gm * 0.35 * pulse, REDF * 1.15)
    fe = [(xy[a], xy[b]) for (a, b), fs in edges.items() if any(fn[f][2] > 0 for f in fs)]
    blend_k(segs(fe, max(2, int(rad / 120))).astype(np.float32) / 255 * 0.85, GOLDF * 0.95)
    rgb = C / np.maximum(Aa, 1e-4)[..., None]
    out = np.dstack([np.clip(rgb, 0, 255), np.clip(Aa * 255, 0, 255)]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def poly_rot(i, t):
    return rotm(0.42 + 0.16 * math.sin(t * 0.5 + i), t * 0.42 + i * 1.3, 0.12 * math.sin(t * 0.31 + i * 2))


# ================= 第一段：红眼 + 五多面体 =================
def eye_layer(o):
    o = cl(o, 0, 5)
    i = min(int(o), 4)
    f = o - i
    a = img(EYES[i], "RGBA")
    if f < 0.02:
        return a
    return Image.blend(a, img(EYES[i + 1], "RGBA"), f)


def eye_scene(t, o, z=1.0, alpha=1.0):
    F = Image.new("RGB", (W, H), BG)
    m = mask()
    for k, r0 in enumerate([300, 440, 580]):
        ang = t * (5 + 3 * k) * (1 if k % 2 else -1)
        arc(m, (960, 560), (r0 * 1.85, r0 * 0.6), 0, ang, ang + 250)
    ink(F, m, (120, 36, 48), 0.16 * alpha)
    e = eye_layer(o)
    if alpha < 1:
        e = amul(e, alpha)
    F.paste(e, (0, 0), e)
    if z != 1.0:
        F = zf(F, z)
    return F


def eye_z(t):
    return 1.0 + 0.035 * cl(t / 2.94)


def s1_eye(t, fi):
    a = eo((t - 0.12) / 0.9)
    o = 5 * eio((t - 0.7) / 1.95)
    return post(eye_scene(t, o, eye_z(t), alpha=a), fi, vig=1.2, noise=0.95, flick=True)


@functools.lru_cache(maxsize=1)
def poly_ghost():
    gw = cover(img("world/艾瑟拉.jpg"), (W, H), 1.1, 0, -0.2).convert("L")
    return Image.merge("RGB", [gw.point(lambda v: int(v * 0.10) + BG[0])] * 3)


def poly_bg(t):
    F = poly_ghost().copy()
    m = mask()
    for k, r0 in enumerate([300, 420, 560]):
        ang = t * (8 - 2 * k) * (1 if k % 2 else -1)
        arc(m, (960, 520), (r0, r0), 0, ang, ang + 290)
    ink(F, m, (150, 128, 110), 0.12)
    return F


def poly_bg_fx(fi, seed=0):
    """多面体段背景：上下边缘的扫描线抖动 + 数字条纹（只占边缘约25%）。"""
    on = (fi // 5) % 3 != 1
    fx = []
    if on:
        fx.append(lambda a: gx_scan(a, 0, 150, 70, fi, seed=seed, bright=2.2))
        fx.append(lambda a: gx_scan(a, H - 130, H, 60, fi, seed=seed + 1, bright=2.2))
    fx.append(lambda a: gx_stripe(a, 0, 170, 2 + fi % 3, fi, seed=seed))
    fx.append(lambda a: gx_stripe(a, H - 150, H, 2 + (fi + 1) % 3, fi, seed=seed + 5))
    return fx


def poly_frame(i, t):
    F = poly_bg(t)
    glow(F, (960, 520), 520, (240, 222, 205), 0.10)
    P = render_poly(i, poly_rot(i, t), 330, t)
    put(F, P, 960, 520 + 10 * math.sin(t * 1.6))
    return F


def s1_dive(t, fi):
    """睁眼后的转场：错位图块 + 数字条纹，不放大眼睛。"""
    u = (t - T_HIT) / (T_P0 - T_HIT)
    f = lf(t, T_HIT)
    if f < 10:
        F = eye_scene(t, 5, eye_z(T_HIT))
        nz = 0.95
    else:
        F = poly_frame(0, T_P0)
        nz = 0.3
    c = math.sin(math.pi * cl(u))
    fx = [lambda a: gx_block(a, 0, 330, W, 760, int(4 + 30 * c), fi, bw=(60, 420), bh=(8, 70), disp=260),
          lambda a: gx_stripe(a, 280, 820, int(3 + 18 * c), fi)]
    if f in (9, 10):
        fx.append(lambda a: gx_stripe(a, 0, H, 26, fi, seed=9))
    return post(F, fi, vig=1.1, noise=nz, fx=fx, flash=0.35 if f == 0 else 0.0)


def s1_poly(t, fi):
    i = max(k for k in range(5) if POLY_T[k] <= t + 1e-6)
    t0 = POLY_T[i]
    t1 = POLY_T[i + 1] if i < 4 else T_ORB
    f = lf(t, t0)
    F = poly_frame(i, t)
    fx = poly_bg_fx(fi, i)
    nf = int(round((t1 - t0) * FPS))
    if (f < 3 and i > 0) or f >= nf - 2:
        ramp = (1 - f / 3) if f < 3 else (f - (nf - 3)) / 2
        fx.append(lambda a: gx_wave(a, 300, 760, 46 * cl(ramp) + 8, fi, seed=i, freq=0.03))
    return post(F, fi, vig=1.0, noise=0.3, fx=fx)


def orbit_base(t, u):
    F = Image.new("RGB", (W, H), BG)
    wimg = img("world/艾瑟拉.jpg")
    gw = cover(wimg, (W, H), 1.05 + 0.12 * u, 0, -0.2).convert("L").convert("RGB")
    F = Image.blend(F, gw, 0.08 + 0.14 * u)
    c = (960, 540)
    m = mask()
    for r0, sp in ((360, 18), (500, -11), (650, 7)):
        ang = t * sp
        circ(m, c, r0)
        for d in range(0, 360, 6):
            aa = math.radians(d + ang)
            l2 = 16 if d % 30 == 0 else 7
            ln(m, (c[0] + r0 * math.cos(aa), c[1] + r0 * math.sin(aa)), (c[0] + (r0 + l2) * math.cos(aa), c[1] + (r0 + l2) * math.sin(aa)))
    for k in range(3):
        ang = t * (20 + 9 * k)
        arc(m, c, (820 + 90 * k, 280 + 30 * k), -12 + 12 * k, ang, ang + 220)
    ink(F, m, (190, 160, 150), 0.18 + 0.12 * u)
    return F


_FLASHES = [15.266 + 0.6 * k for k in range(5)] + [18.266 + 0.3 * k for k in range(7)]


def flash_fx(k, fi):
    """多面体闪回帧上的故障：轮换四种，只占画面约 20~40%。"""
    r = R("ffx", k)
    y0 = int(r.uniform(0.1, 0.55) * H)
    hh = int(r.uniform(0.22, 0.36) * H)
    kind = k % 4
    if kind == 0:
        return [lambda a: gx_block(a, 0, y0, W, y0 + hh, 18, fi, seed=k, bw=(80, 420), disp=240)]
    if kind == 1:
        return [lambda a: gx_stripe(a, y0, y0 + hh, 22, fi, seed=k)]
    if kind == 2:
        return [lambda a: gx_scan(a, y0, y0 + hh, 110, fi, seed=k, bright=1.4)]
    return [lambda a: gx_wave(a, y0, y0 + hh, 60, fi, seed=k)]


def s1_orbit(t, fi):
    tau = t - T_ORB
    u = tau / (T_CONV - T_ORB)
    for k, tf in enumerate(_FLASHES):
        if 0 <= t - tf < 2 / FPS:
            light = k % 2 == 1
            F = Image.new("RGB", (W, H), (226, 220, 212) if light else (30, 8, 12))
            P = render_poly(k % 5, poly_rot(k, t), 360, t)
            put(F, P, 960, 540)
            return post(F, fi, vig=0.9, noise=0.4, fx=flash_fx(k, fi))
    F = orbit_base(t, u)
    th = 2 * math.pi * (0.12 * tau + 0.025 * tau ** 2.3)
    Rr = 640 * (1 - u ** 1.6)
    c = (960, 540)
    glow(F, c, 140 + 320 * u, (255, 214, 196), 0.10 + 0.5 * u)
    items = sorted(((math.sin(th + 2 * math.pi * k / 5), k, th + 2 * math.pi * k / 5) for k in range(5)))
    for d, k, ph in items:
        rad = 100 * (1 + 0.25 * d) * (1 - 0.35 * u)
        P = render_poly(k, poly_rot(k, t * 1.8), max(30, rad), t)
        for gg, aa in ((0.22, 0.16), (0.11, 0.32)):
            p2 = ph - gg
            put(F, P, c[0] + Rr * math.cos(p2), c[1] + Rr * 0.36 * math.sin(p2), aa)
        put(F, P, c[0] + Rr * math.cos(ph), c[1] + Rr * 0.36 * d, 1.0)
    fx = []
    if (fi // 7) % 4 == 0:
        fx.append(lambda a: gx_scan(a, H - 140, H, 60, fi, bright=1.8))
    return post(F, fi, vig=1.0, noise=0.3, fx=fx)


def s1_burst(t, fi):
    """合体瞬间：黑白闪，闪的同时已经是黑白定格画面，不在彩色画面停留。"""
    f = lf(t, T_CONV)
    F = freeze_img()
    inv = f in (0, 2)
    fl = {0: 0.75, 1: 0.0, 2: 0.45, 3: 0.0}.get(f, 0.0)
    if f < 4:
        fx = [lambda a: gx_stripe(a, 300, 780, 18, fi),
              lambda a: gx_block(a, 0, 360, W, 720, 14, fi, bw=(80, 420), disp=260)]
    else:
        fx = [lambda a: gx_scan(a, 0, 150, 70, fi, bright=1.3), lambda a: gx_block(a, 1350, 760, W, H, 5, fi)]
    return post(F, fi, vig=0.8, noise=0.5, invert=inv, flash=fl, fx=fx)


@functools.lru_cache(maxsize=1)
def freeze_img():
    F = orbit_base(21.5, 1.0)
    c = (960, 540)
    for k in range(5):
        ph = -math.pi / 2 + 2 * math.pi * k / 5
        put(F, render_poly(k, poly_rot(k, 21.5), 130, 21.5), c[0] + 430 * math.cos(ph), c[1] + 360 * math.sin(ph))
    gray = F.convert("L")
    e = gray.filter(ImageFilter.FIND_EDGES).point(lambda v: 255 if v > 26 else 0)
    hi = gray.point(lambda v: 255 if v > 200 else 0)
    L = np.maximum(np.asarray(e), np.asarray(hi)).astype(np.uint8)
    out = Image.new("RGB", (W, H), (6, 6, 8))
    out.paste(Image.new("RGB", (W, H), (236, 236, 240)), (0, 0), Image.fromarray(L))
    m = mask()
    rr = R("crack")
    for k in range(14):
        ang = rr.uniform(0, 2 * math.pi)
        p = c
        for j in range(6):
            ang += rr.uniform(-0.4, 0.4)
            q = (p[0] + math.cos(ang) * rr.uniform(60, 160), p[1] + math.sin(ang) * rr.uniform(60, 160))
            ln(m, p, q, 2 if j < 2 else 1)
            p = q
    ink(out, m, (236, 236, 240), 0.9)
    return out


def s1_freeze(t, fi):
    """黑白定格 + 故障转场进地图。"""
    f = lf(t, T_CRACK)
    F = freeze_img()
    n = int(round((T2 - T_CRACK) * FPS))
    fx = [lambda a: gx_scan(a, 0, 170, 90, fi, bright=1.3), lambda a: gx_block(a, 1300, 700, W, H, 8, fi)]
    if f >= n - 7:
        k = (f - (n - 7)) / 6
        fx += [lambda a: gx_block(a, 0, 260, W, 820, int(10 + 30 * k), fi, seed=3, bw=(100, 520), disp=300),
               lambda a: gx_stripe(a, 200, 880, int(6 + 20 * k), fi, seed=4)]
    return post(F, fi, vig=0.8, noise=0.5, flash=0.5 if f == 0 else 0.0, shake=(0, 0) if (f // 4) % 2 == 0 else (4, -2), fx=fx)


# ================= 第二段：世界地图光柱 + 地区背景 =================
MAPK = 3


@functools.lru_cache(maxsize=1)
def map_canvas():
    d = json.load(open(os.path.join(PROJ, "data", "map", "world_lines.json"), encoding="utf-8"))
    Wm, Hm = 1600 * MAPK, 900 * MAPK
    base = np.zeros((Hm, Wm, 3), np.float32) + np.array([14, 12, 18], np.float32)

    def comp(m, col, al):
        k = (m.astype(np.float32) / 255.0 * al)[..., None]
        base[:] = base * (1 - k) + np.array(col, np.float32) * k

    def lines(name, th, dashed=False):
        m = np.zeros((Hm, Wm), np.uint8)
        arrs = []
        for flat in d["layers"].get(name, []):
            pts = np.int32(np.array(flat, np.float64).reshape(-1, 2) * MAPK * 16)
            if len(pts) < 2:
                continue
            if dashed:
                for q in range(0, len(pts) - 1, 2):
                    arrs.append(pts[q:q + 2])
            else:
                arrs.append(pts)
        cv2.polylines(m, arrs, False, 255, th, cv2.LINE_AA, 4)
        return m

    g = np.zeros((Hm, Wm), np.uint8)
    cc = (800 * MAPK * 16, 450 * MAPK * 16)
    for i in range(4):
        cv2.circle(g, cc, int((230 + 150 * i) * MAPK * 16), 255, 2, cv2.LINE_AA, 4)
    for i in range(12):
        an = 2 * math.pi * i / 12
        cv2.line(g, (int(cc[0] + math.cos(an) * 120 * MAPK * 16), int(cc[1] + math.sin(an) * 120 * MAPK * 16)),
                 (int(cc[0] + math.cos(an) * 860 * MAPK * 16), int(cc[1] + math.sin(an) * 860 * MAPK * 16)), 255, 1, cv2.LINE_AA, 4)
    comp(g, (120, 110, 120), 0.18)
    comp(lines("river", 1), (150, 150, 170), 0.30)
    comp(lines("relief", 1), (130, 116, 110), 0.32)
    comp(lines("route", 2, True), RED, 0.42)
    cg = cv2.GaussianBlur(lines("coast", 10), (0, 0), 8)
    comp(cg, RED, 0.16)
    comp(lines("coast", 3), (236, 232, 226), 0.85)
    comp(lines("border", 2), RED, 0.62)
    dots = np.zeros((Hm, Wm), np.uint8)
    for _, _, _, (mx, my) in PLACES:
        cv2.circle(dots, (int(mx * MAPK * 16), int(my * MAPK * 16)), 5 * 16, 255, -1, cv2.LINE_AA, 4)
        cv2.circle(dots, (int(mx * MAPK * 16), int(my * MAPK * 16)), 11 * 16, 255, 1, cv2.LINE_AA, 4)
    comp(dots, GOLD, 0.8)
    return Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))


def map_view(mp, lt):
    z = 2.6 - 1.0 * (1 - eo(lt / 0.16))
    vw, vh = 1600 / z, 900 / z
    cx = cl(mp[0], vw / 2, 1600 - vw / 2)
    cy = cl(mp[1], vh / 2, 900 - vh / 2)
    x0, y0 = cx - vw / 2, cy - vh / 2
    F = map_canvas().resize((W, H), Image.BILINEAR, box=(x0 * MAPK, y0 * MAPK, (x0 + vw) * MAPK, (y0 + vh) * MAPK))
    sx = (mp[0] - x0) / vw * W
    sy = (mp[1] - y0) / vh * H
    return F, sx, sy


def pillar(a, sx, sy, lt, fi):
    hgt = 1150 * eo((lt - 0.03) / 0.2)
    if hgt < 4:
        return a
    fl = 0.9 + 0.1 * math.sin(fi * 1.7)
    x0, x1 = int(max(0, sx - 280)), int(min(W, sx + 280))
    y1 = int(min(H, sy + 40))
    if x1 <= x0 or y1 <= 0:
        return a
    xs = np.arange(x0, x1, dtype=np.float32) - sx
    ys = np.arange(0, y1, dtype=np.float32)
    top = sy - hgt
    vert = np.clip((ys - top) / 240, 0, 1) * np.clip((sy + 40 - ys) / 50, 0, 1)
    wa = np.clip(vert[:, None] * (np.exp(-(xs / 3.5) ** 2) * 0.95 + np.exp(-(xs / 22) ** 2) * 0.45)[None, :] * fl, 0, 1)
    wr = vert[:, None] * (np.exp(-(xs / 100) ** 2) * 0.30)[None, :]
    sub = a[0:y1, x0:x1]
    sub[:] = sub * (1 - wr[..., None]) + np.array([200, 40, 56], np.float32) * wr[..., None]
    sub[:] = sub * (1 - wa[..., None]) + np.array([255, 242, 224], np.float32) * wa[..., None]
    return a


@functools.lru_cache(maxsize=1)
def text_shade():
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    k = np.clip((yy / H - 0.45) / 0.55, 0, 1) ** 1.4 * np.clip(1.3 - xx / W, 0, 1)
    return Image.fromarray((k * 190).astype(np.uint8))


def region_img(pi, v):
    bid = PLACES[pi][2]
    d = 1 if pi % 2 == 0 else -1
    return cover(img("bgx/%s.jpg" % bid), (W, H), 1.06 + 0.10 * v, d * (-0.6 + 1.2 * v), 0.1 * math.sin(pi))


def s2(t, fi):
    pi = min(int((t - T2) / 1.2), len(PLACES) - 1)
    t0 = T2 + 1.2 * pi
    lt = t - t0
    ff = lf(t, t0)
    area, country, bid, mp = PLACES[pi]
    r = R("wv", pi)
    yc = H * (0.32 + 0.36 * r.random())
    fx = []
    if lt < 0.6:   # 2 拍地图光柱
        F, sx, sy = map_view(mp, lt)
        m = mask()
        rx = 30 + 170 * eo(lt / 0.4)
        arc(m, (sx, sy), (rx, rx * 0.32), 0, 0, 360, 2)
        ink(F, m, GOLD, 0.9 * (1 - cl(lt / 0.6)))
        glow(F, (sx, sy), 120, (255, 200, 170), 0.5)
        fx.append(lambda a: pillar(a, sx, sy, lt, fi))
        if ff < 3:
            fx.append(lambda a: gx_wave(a, yc - 0.2 * H, yc + 0.2 * H, 60 * (1 - ff / 3) + 10, fi, seed=pi))
        return post(F, fi, vig=1.1, noise=0.25, fx=fx)
    v = (lt - 0.6) / 0.6   # 2 拍地区背景
    F = region_img(pi, v)
    F.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), text_shade())
    f2 = ff - 18
    ta = eo(f2 / 4)
    nm = slim(area, 150, 330, WHITE, squeeze=0.80, track=10, shadow=0.7)
    cn = slim(country, 46, 450, (232, 222, 206), squeeze=0.86, track=16, shadow=0.7)
    nb = nm.getchannel("A").point(lambda q: 255 if q > 120 else 0).getbbox() or (0, 0, nm.width, nm.height)
    cb = cn.getchannel("A").point(lambda q: 255 if q > 120 else 0).getbbox() or (0, 0, cn.width, cn.height)
    x0 = 120 - 30 * (1 - ta)
    name_bottom = H - 120          # 地区名字形底边
    yb = name_bottom - nb[3]
    cy_top = yb + nb[1] - 26 - (cb[3] - cb[1])   # 国家名放在地区名上方，整行完整可见
    put_tl(F, cn, x0 + 6 - cb[0], cy_top - cb[1], ta * eo((f2 - 1) / 4))
    put_tl(F, nm, x0 - nb[0], yb, ta)
    m = mask()
    ly = name_bottom + 22
    lw = (nb[2] - nb[0] + 160) * eo(f2 / 7)
    ln(m, (x0, ly), (x0 + lw, ly))
    star4(m, (x0 + lw, ly), 9, 1.6)
    ink(F, m, GOLD, 0.85 * ta)
    if f2 < 3:
        fx.append(lambda a: gx_wave(a, yc - 0.2 * H, yc + 0.2 * H, 54 * (1 - f2 / 3) + 8, fi, seed=pi + 50))
    elif ff >= 34:
        fx.append(lambda a: gx_wave(a, yc - 0.18 * H, yc + 0.18 * H, 18 + 30 * (ff - 33), fi, seed=pi + 90))
    return post(F, fi, vig=1.0, noise=0.2, fx=fx)


def s2_end(t, fi):
    """地区→角色：扫描线抖动（上）、数字条纹（中）、错位图块（右下）分区同时出现，互不糊在一起。"""
    f = lf(t, T2E)
    if f < 10:
        F = region_img(len(PLACES) - 1, 1.0)
        F.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), text_shade())
    else:
        F = s3(T3, fi, raw=True)
    k = math.sin(math.pi * cl((f + 1) / 19))
    fx = [lambda a: gx_scan(a, 0, int(H * (0.12 + 0.18 * k)), 60 + 140 * k, fi, bright=1.3),
          lambda a: gx_stripe(a, int(H * 0.44), int(H * 0.58), int(4 + 12 * k), fi),
          lambda a: gx_block(a, int(W * 0.55), int(H * 0.68), W, H, int(4 + 14 * k), fi, bw=(60, 300), bh=(12, 80))]
    return post(F, fi, vig=1.0, noise=0.3, fx=fx, flash=0.45 if f in (0, 10) else 0.0)


# ================= 第三段：群星邂逅 =================
SLANT = math.tan(math.radians(18)) * H
XL = 806
XR = W - 806


@functools.lru_cache(maxsize=2)
def side_mask(left):
    m = mask()
    if left:
        pts = [(0, 0), (XL + SLANT / 2, 0), (XL - SLANT / 2, H), (0, H)]
    else:
        pts = [(XR + SLANT / 2, 0), (W, 0), (W, H), (XR - SLANT / 2, H)]
    pl(m, pts, fill=True)
    return Image.fromarray(m)


@functools.lru_cache(maxsize=4)
def cut_scaled(c):
    im = img(A["cut"][c], "RGBA")
    s = H * 1.16 / im.height
    return im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS)


@functools.lru_cache(maxsize=6)
def silhouette(c, color):
    im = cut_scaled(c)
    s = Image.new("RGBA", im.size, color + (255,))
    s.putalpha(im.getchannel("A"))
    return s


@functools.lru_cache(maxsize=4)
def portrait_bg(c, left):
    e = CAST[c]
    c0, c1 = hexrgb(e["colors"][0]), hexrgb(e["colors"][1])
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    k = np.clip((xx / W * (1 if left else -1) + (0 if left else 1)) * 0.6 + yy / H * 0.4, 0, 1)[..., None]
    a = np.array(c0, np.float32) * 0.55 * (1 - k) + np.array(c1, np.float32) * 0.28 * k
    cx = 403 if left else W - 403
    r = np.sqrt(((xx - cx) / 700) ** 2 + ((yy - 420) / 700) ** 2)[..., None]
    a = a + np.array(c0, np.float32) * 0.35 * np.clip(1 - r, 0, 1) ** 2
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def illus_order(c):
    L = A["illus"][c]
    idx = list(range(len(L)))
    R("ord", c).shuffle(idx)
    return [L[i] for i in idx]


def s3(t, fi, raw=False):
    k = min(int((t - T3) / 1.5), 20)
    t0 = T3 + 1.5 * k
    lt = t - t0
    f = lf(t, t0)
    c = CHARS[k]
    left = k % 2 == 0
    beat = min(int(lt / 0.3 + 1e-6), 4)
    bt = lt - 0.3 * beat
    bf = lf(t, t0 + 0.3 * beat)
    # 插图侧：模拟噪点打底 + 褪色
    I = Image.new("RGB", (W, H), BG)
    pw = int(W - XL + SLANT / 2 + 40)
    order = illus_order(c)
    neg = False
    if beat == 4 and c in A["lib"]:
        ib = cover(img(A["lib"][c]), (pw, H), 1.05 + 0.10 * bt / 0.3, 0, -0.55)
        neg = bf < 2
    else:
        ent = order[beat % len(order)]
        z = 1.0 + 0.12 * bt / 0.3 + (0.05 if bf < 2 else 0)
        ib = cover(img(ent["file"]), (pw, H), z, (0.3 if beat % 2 else -0.3) * (1 - 2 * bt / 0.3), 0)
    if neg:
        ib = ImageOps.colorize(ImageOps.invert(ib.convert("L")), (20, 4, 8), (250, 240, 236))
    ia = np.asarray(ib, dtype=np.float32).copy()
    fade_arr(ia, 0.55)
    analog(ia, 0.9, fi)
    ib = Image.fromarray(np.clip(ia, 0, 255).astype(np.uint8))
    I.paste(ib, (int(XL - SLANT / 2 - 40) if left else 0, 0))
    if bf == 0 and beat > 0:
        I = Image.blend(I, Image.new("RGB", (W, H), (255, 255, 255)), 0.22)
    # 立绘侧
    P = portrait_bg(c, left).copy()
    m = mask()
    pcx = 403 if left else W - 403
    for j, r0 in enumerate((260, 360, 470)):
        ang = t * (16 - 5 * j) * (1 if j % 2 else -1)
        arc(m, (pcx, 430), (r0, r0), 0, ang, ang + 280)
    ink(P, m, (255, 245, 235), 0.20)
    cut = cut_scaled(c)
    sign = -1 if left else 1

    def cpos(ff):
        dx = (1 - eo(ff / 9)) * 240 * sign
        drift = (ff / FPS) * 22 * (-sign)
        return pcx + dx + drift + 30 * sign, 28 + cut.height / 2

    sil_col = [(238, 232, 222), (196, 28, 48), (206, 164, 92)][k % 3]
    sx, sy = cpos(max(0, f - 3))
    put(P, silhouette(c, sil_col), sx - 34 * sign, sy + 16, 0.9 * cl(f / 3))
    x, y = cpos(f)
    put(P, cut, x, y, cl(f / 2 + 0.3))
    # 名字：细长玲珑竖排 + 细金线 + 小星
    nm = "叶" if c == "叶子" else c
    nx = 150 if left else W - 150
    cell = 158
    ytop = 120
    m = mask()
    lh = eo((f - 2) / 10) * (len(nm) * cell + 140)
    ln(m, (nx, ytop - 60), (nx, ytop - 60 + lh))
    if lh > 10:
        star4(m, (nx, ytop - 70), 16, 2)
        ln(m, (nx - 14, ytop - 60 + lh - 24), (nx + 14, ytop - 60 + lh - 24))
    ink(P, m, GOLD, 0.8)
    for i2, ch in enumerate(nm):
        ff = f - 3 - 2 * i2
        if ff < 0:
            continue
        e2 = eo(ff / 7)
        cy = ytop + cell / 2 + i2 * cell - 30 * (1 - e2)
        put(P, slim(ch, 150, 300, WHITE, squeeze=0.78, shadow=0.65), nx, cy, e2)
    F = Image.composite(P, I, side_mask(left))
    xc = XL if left else XR
    m = mask()
    ln(m, (xc + SLANT / 2, 0), (xc - SLANT / 2, H), 3)
    ink(F, m, (255, 250, 244), 0.95)
    m = mask()
    o2 = 16 if left else -16
    ln(m, (xc + SLANT / 2 + o2, 0), (xc - SLANT / 2 + o2, H), 1)
    ink(F, m, RED, 0.9)
    m = mask()
    pp = (lt * 0.8) % 1
    star4(m, (xc + SLANT / 2 - SLANT * pp, H * pp), 22, 3)
    ink(F, m, (255, 255, 255), 0.9)
    if raw:
        return F
    fx = []
    if f < 2 and k > 0:
        fx.append(lambda a: gx_block(a, xc - 260, 0, xc + 260, H, 9, fi, bw=(40, 220), bh=(10, 60)))
    strong = k in (4, 12)
    return post(F, fi, vig=0.8, fx=fx, flash=(0.6 if strong and f < 2 else (0.28 if f == 0 else 0.0)))


# ---------- 未知：问号 / 报错 / 打码小艾 ----------
@functools.lru_cache(maxsize=1)
def q_grid():
    m = mask()
    for x in range(0, W, 96):
        ln(m, (x, 0), (x, H))
    for y in range(0, H, 96):
        ln(m, (0, y), (W, y))
    return m


def s3_q(t, fi):
    """未知：问号 → 满屏问号 + 人格化系统报错在整个画面各处闪烁 → 扫描线抖动转场。"""
    lt = t - T_Q
    f = lf(t, T_Q)
    F = Image.new("RGB", (W, H), (10, 9, 12))
    ink(F, q_grid(), (90, 90, 96), 0.06)
    fx = []
    qa = 0.9 if (f // 3) % 5 else 0.45
    put(F, slim("？", 420, 220, WHITE, squeeze=0.85, shadow=0), W / 2, H / 2, qa, 1.0 + 0.04 * lt)
    if lt < 0.9:
        if f % 9 < 3:
            fx.append(lambda a: gx_wave(a, H / 2 - 160, H / 2 + 160, 24, fi, seed=1))
    else:
        u = (lt - 0.9) / 2.4
        n = int(2 + 150 * cl(u) ** 1.5)
        r = R("qm")
        fonts = [(SERIF, 300), (SERIF, 900), (SONG, 0), (HEI, 0)]
        for i in range(n):
            s = "?" if r.random() < 0.5 else "？"
            sz = int(r.choice([28, 40, 56, 80, 120, 180, 260]))
            x, y = r.uniform(0, W), r.uniform(0, H)
            fp, wt = fonts[int(r.integers(0, len(fonts)))]
            col = [WHITE, (150, 146, 150), RED][int(r.integers(0, 3))]
            a = 0.85 if (fi + i) % 7 else 0.25
            put(F, timg(s, fp, sz, wt, col), x, y, a)
        # 报错：每 2~5 帧换一批，随机散在整个画面，越往后越多越大
        nm = int(cl((lt - 1.0) / 0.1, 0, 26))
        for i in range(nm):
            rr = R("qmsg", i, f // int(2 + i % 4))
            s = QMSG[int(rr.integers(0, len(QMSG)))]
            sz = int(rr.choice([30, 40, 52, 66, 84, 110] if lt < 2.4 else [40, 56, 72, 96, 130, 170]))
            kind = int(rr.integers(0, 4))
            col = RED if rr.random() < 0.38 else (WHITE if rr.random() < 0.7 else (170, 166, 170))
            if kind == 0:
                im = slim(s, sz, 300, col, squeeze=0.82, shadow=0.5)
            elif kind == 1:
                im = timg(s, SERIF, sz, 900, col)
            elif kind == 2:
                im = timg(s, HEI, sz, 0, col)
            else:
                im = slim(s, sz, 300, col, squeeze=0.82, vertical=True, shadow=0.5)
            if rr.random() < 0.78:
                x, y = rr.uniform(0.05, 0.95) * W, rr.uniform(0.06, 0.94) * H
                put(F, im, x, y, 0.95 if rr.random() < 0.8 else 0.45)
                if rr.random() < 0.22:
                    hw, hh = im.width / 2 + 20, im.height / 2 + 6
                    fx.append(lambda a, x=x, y=y, hw=hw, hh=hh, sd=i: gx_scan(a, y - hh, y + hh, 30, fi, x - hw, x + hw, seed=sd))
        r2 = R("qfx", f // 3)
        y0 = r2.uniform(0, 0.7) * H
        fx.append(lambda a: gx_wave(a, y0, y0 + 0.28 * H, 40, fi, seed=f // 3))
        bx = r2.uniform(0, 0.6) * W
        fx.append(lambda a: gx_block(a, bx, 0, bx + 0.4 * W, H, int(6 + 16 * cl(u)), fi, bw=(50, 300)))
    if lt > 3.15:
        v = cl((lt - 3.15) / (T_XA - T_Q - 3.15))
        hh = (0.2 + 0.5 * v) * H
        fx.append(lambda a: gx_scan(a, H / 2 - hh / 2, H / 2 + hh / 2, 60 + 160 * v, fi, bright=1.2))
    return post(F, fi, vig=1.0, noise=0.6, fx=fx)


@functools.lru_cache(maxsize=6)
def xa_img(expr, blur=0):
    """小艾正面立绘：黑白、压暗 + 眼睛以上厚重黑影 + 大幅模糊，像黑暗中眯着眼看到的人影。"""
    im = Image.open(os.path.join(PROJ, "assets", "characters", "xiaoai", "daily_front_b", expr + ".webp")).convert("RGBA")
    w, h = im.size
    alpha = np.asarray(im.getchannel("A"), np.float32) / 255
    g = np.asarray(ImageOps.autocontrast(im.convert("L"), cutoff=1), np.float32)
    if blur:   # 先把线稿加粗，模糊后五官（嘴角）仍能看出轮廓
        kz = min(int(blur * 1.4), 7) | 1
        g = cv2.erode(g, np.ones((kz, kz), np.uint8))
    g = g * 0.42 + 26
    m = np.zeros((h, w), np.float32)
    cv2.ellipse(m, (int(0.485 * w), int(0.085 * h)), (int(0.27 * w), int(0.10 * h)), 0, 0, 360, 1.0, -1)
    cv2.rectangle(m, (int(0.24 * w), 0), (int(0.73 * w), int(0.181 * h)), 1.0, -1)
    nz = cv2.resize(np.random.default_rng(3).random((h // 28, w // 28)).astype(np.float32), (w, h))
    m = cv2.GaussianBlur(m, (0, 0), w * 0.006)
    m = np.clip(m * (0.8 + 0.4 * nz) * 1.35, 0, 1)
    ga = g * (1 - 0.97 * m)
    al = np.maximum(alpha, m * 0.92)
    if blur:
        k = blur * w / 1024.0
        pre = np.dstack([ga * al, al])
        pre = cv2.GaussianBlur(pre, (0, 0), k)
        al = pre[..., 1]
        ga = pre[..., 0] / np.maximum(al, 1e-3)
        al = np.clip(al * 0.85, 0, 1)
    out = np.dstack([ga, ga, ga, al * 255]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def xa_face(expr, ch, blur):
    im = xa_img(expr, blur)
    w, h = im.size
    cx, cy = 0.485 * w, 0.205 * h
    hh = ch * h
    ww = hh * 16 / 9
    box = (cx - ww / 2, cy - hh / 2, cx + ww / 2, cy + hh / 2)
    F = Image.new("RGB", (W, H), (14, 13, 16))
    crop = im.resize((W, H), Image.BILINEAR, box=box)
    F.paste(crop, (0, 0), crop)
    return F


def s3_xiaoai(t, fi):
    lt = t - T_XA
    f = lf(t, T_XA)
    r = R("xafx", f // 4)
    fx = []
    if t < T_FACE:
        F = Image.new("RGB", (W, H), (12, 11, 14))
        im = xa_img("neutral", 26)
        put(F, im, W / 2, H * 0.53, 1, H * 0.98 / im.height * (1 + 0.03 * lt))
        fx += [lambda a: gx_scan(a, 0, H * 0.2, 90, fi, bright=1.4),
               lambda a: gx_scan(a, H * 0.8, H, 70, fi, seed=2, bright=1.4),
               lambda a: gx_stripe(a, 0, H, 6 + fi % 5, fi)]
        if t > T_FACE - 0.13:
            fx.append(lambda a: gx_scan(a, H * 0.2, H * 0.8, 200, fi, seed=7))
        if f < 4:
            fx.append(lambda a: gx_scan(a, H * 0.25, H * 0.75, 180 * (1 - f / 4), fi, seed=8))
        return post(F, fi, vig=1.1, noise=1.3, fx=fx)
    if t < T_SMILE:
        u = (t - T_FACE) / (T_SMILE - T_FACE)
        F = xa_face("neutral", 0.22 - 0.02 * u, 9)
        fb = lf(t, T_FACE)
        y0 = r.uniform(0.05, 0.6) * H
        mode = (f // 4) % 3
        if mode == 0:
            fx.append(lambda a: gx_scan(a, y0, y0 + 0.38 * H, 150, fi, bright=1.2))
        elif mode == 1:
            fx.append(lambda a: gx_stripe(a, y0, y0 + 0.4 * H, 20, fi))
        else:
            fx.append(lambda a: gx_block(a, 0, y0, W, y0 + 0.4 * H, 16, fi, bw=(80, 420), disp=260))
        fx.append(lambda a: gx_stripe(a, 0, H, 5, fi, seed=3))
        if fb < 3:
            fx.append(lambda a: gx_scan(a, 0, H, 220 * (1 - fb / 3), fi, seed=9))
        return post(F, fi, vig=1.1, noise=1.4, fx=fx, flash=0.3 if fb == 0 else 0.0)
    fs = lf(t, T_SMILE)
    F = xa_face("smile", 0.2, 4)
    if t < T_XOUT:
        if fs < 2:
            fx.append(lambda a: gx_block(a, 0, H * 0.3, W, H * 0.7, 14, fi))
        fx.append(lambda a: gx_scan(a, 0, H * 0.14, 80, fi, bright=1.3))
        fx.append(lambda a: gx_stripe(a, H * 0.86, H, 5, fi))
        return post(F, fi, vig=1.1, noise=1.0, fx=fx)
    v = (t - T_XOUT) / (T4 - T_XOUT)
    fx += [lambda a: gx_block(a, 0, H * (0.4 - 0.35 * v), W, H * (0.6 + 0.35 * v), int(10 + 40 * v), fi, bw=(80, 500), disp=300),
           lambda a: gx_stripe(a, 0, H, int(8 + 26 * v), fi, seed=5)]
    return post(F, fi, vig=1.1, noise=1.2, fx=fx, flash=cl((v - 0.6) / 0.4) ** 2)


# ================= 第四段：回忆闪回（大量抽帧） =================
HOLDS = [5, 4, 6, 5, 4, 6, 5, 5, 4, 6, 5, 5]


def corner_hud(F, n):
    m = mask()
    L = 46
    for (x, y, sx, sy) in ((70, 70, 1, 1), (W - 70, 70, -1, 1), (70, H - 70, 1, -1), (W - 70, H - 70, -1, -1)):
        ln(m, (x, y), (x + L * sx, y))
        ln(m, (x, y), (x, y + L * sy))
    ink(F, m, (250, 248, 240), 0.55)


def trans_fx(kind, fi, k, seed=0):
    """通用故障转场：带宽约占画面 35%，强度 k∈[0,1]。"""
    r = R("tfx", seed)
    y0 = r.uniform(0.15, 0.5) * H
    y1 = y0 + 0.35 * H
    kind %= 4
    if kind == 0:
        return lambda a: gx_block(a, 0, y0, W, y1, int(6 + 26 * k), fi, seed=seed, bw=(80, 460), disp=280)
    if kind == 1:
        return lambda a: gx_stripe(a, y0, y1, int(5 + 24 * k), fi, seed=seed)
    if kind == 2:
        return lambda a: gx_scan(a, y0, y1, 40 + 160 * k, fi, seed=seed, bright=1.2)
    return lambda a: gx_wave(a, y0, y1, 20 + 60 * k, fi, seed=seed)


G4 = [8, 7, 8, 7, 8, 7, 8, 7]                       # 每组拍数（200BPM，一拍 0.3s），共 60 拍
G4T = [T4 + 0.3 * sum(G4[:k]) for k in range(8)]


def g4_pool(k):
    """该组成员的插图：脸部截图与整张图交替，素材加倍。"""
    out = []
    for mem in MEMBERS[k]:
        for e in illus_order(mem):
            out.append(e["file"])
            out.append(e.get("full", e["file"]))
    R("g4pool", k).shuffle(out)
    return out


def s4(t, fi):
    """回忆闪回：前 4 拍是抽帧后加速播放的组动画（约 10 张/秒、2.2 倍速），
    后 3~4 拍按半拍（0.15s）卡点快切插图。"""
    k = max(i for i in range(8) if G4T[i] <= t + 1e-6)
    t0 = G4T[k]
    lt = t - t0
    f = lf(t, t0)
    grp = A["grp"][k]
    fx = []
    fl = 0.0
    if lt < 1.2:
        step = f // 3
        src = 0.5 + step * 0.1 * 2.2
        n = int(cl(round(24 * src), 1, grp["frames"]))
        F = cover(img(os.path.join(grp["dir"], "f_%04d.jpg" % n)), (W, H), 1.03 + 0.04 * f / 36)
        if f < 3:
            fx.append(trans_fx(k, fi, 1 - f / 3, seed=k))
            fl = 0.3 if f == 0 else 0.0
        if f in (18, 19):  # 第 3 拍：轻微闪拍
            fl = 0.12 if f == 18 else 0.0
    else:
        j = int((lt - 1.2) / 0.15 + 1e-6)
        pool = g4_pool(k)
        F = flash_img(pool[j % len(pool)], 1.0 + 0.06 * ((lt - 1.2) % 0.15) / 0.15, (0.4 if j % 2 else -0.4))
        jf = lf(t, t0 + 1.2 + 0.15 * j)
        if jf == 0:
            fl = 0.22 if j % 2 == 0 else 0.1
            if j % 2 == 1:
                fx.append(trans_fx(k + j, fi, 0.45, seed=k * 10 + j))
    lx = W * (0.15 + 0.7 * ((t * 0.11 + k * 0.37) % 1))
    glow(F, (lx, H * 0.2), 700, (255, 176, 120), 0.20)
    corner_hud(F, k)
    return post(F, fi, vig=0.9, mem=1.0, bw=0.9, noise_edge=1.0, fx=fx, flash=fl)


def s4_roll(t, fi):
    """军鼓滚奏：每 2 帧换一张插图，故障越来越密，冲进文字段。"""
    f = lf(t, T_ROLL)
    rr = R("roll", f // 2)
    c = CHARS[int(rr.integers(0, 21))]
    L = A["illus"][c]
    ent = L[int(rr.integers(0, len(L)))]
    F = flash_img(ent["full"] if rr.random() < 0.5 else ent["file"], 1.05)
    v = f / ((T5 - T_ROLL) * FPS)
    hh = (0.25 + 0.35 * v) * H
    fx = [lambda a: gx_block(a, 0, H / 2 - hh / 2, W, H / 2 + hh / 2, int(6 + 30 * v), fi, bw=(80, 420), disp=260),
          lambda a: gx_stripe(a, 0, H, int(3 + 14 * v), fi)]
    return post(F, fi, mem=1.0, fade=0.5 * v, noise=0.6, fx=fx, flash=(0.25 if f % 9 == 0 else 0.0) + cl((v - 0.85) / 0.15) ** 1.3 * 0.7)


# ================= 第五段：誓言回响（信息过载） =================
PH = OP["callPhrases"]
BIG = OP["bigLines"]
FINAL = OP["finalLine"]
FONTS5 = [(SERIF, 300), (SERIF, 900), (SONG, 0), (HEI, 0), (KAI, 0), (SERIF, 600)]


def _events():
    r = np.random.default_rng(2027)
    ev = []
    t = T5 + 0.05
    i = 0
    while t < T_PLEASE - 0.1:
        B = t >= g(228)
        step = 0.08 if B else 0.12
        cnt = int(r.integers(5, 9)) if B else int(r.integers(3, 6))
        for _ in range(cnt):
            if r.random() < 0.8:
                s = PH[i % 14] if B else PH[i % 6]
            else:
                ln_ = BIG[int(r.integers(0, 4))]
                a0 = int(r.integers(0, max(1, len(ln_) - 3)))
                s = ln_[a0:a0 + int(r.integers(3, 7))]
            i += 1
            giant = r.random() < 0.09
            vert = (not giant) and r.random() < 0.28
            if giant:
                a0 = int(r.integers(0, max(1, len(s) - 2)))
                s = s[a0:a0 + int(r.integers(2, 4))]
                size = 150
                scale = r.uniform(3.0, 4.6)
                x = r.choice([r.uniform(-0.05, 0.12), r.uniform(0.88, 1.05)]) * W
                y = r.uniform(0.2, 0.8) * H
                dur = r.uniform(0.06, 0.11)
            else:
                size = int(r.choice([26, 32, 40, 52, 66, 84, 110, 150]))
                scale = 1.0
                x, y = r.uniform(0.03, 0.97) * W, r.uniform(0.05, 0.95) * H
                dur = r.uniform(0.10, 0.35) if B else r.uniform(0.15, 0.5)
            col = [WHITE, WHITE, RED, GOLD, (150, 146, 150)][int(r.integers(0, 5))]
            fp, wt = FONTS5[int(r.integers(0, len(FONTS5)))]
            t0q = T5 + round((t + r.uniform(0, step) - T5) / 0.075) * 0.075   # 卡在 1/4 拍网格上
            ev.append(dict(t0=t0q, dur=dur, s=s, x=x, y=y, size=size, scale=scale,
                           vert=bool(vert), col=col, fp=fp, wt=wt, giant=giant, vx=r.uniform(-60, 60),
                           style=["type", "slam", "scan", "wave", "block", "plain"][int(r.integers(0, 6))],
                           seed=int(r.integers(0, 1 << 30))))
        t += step
    return ev


EV = _events()


def ev_draw(F, e, tt, fxl, a_mul=1.0, push=0.0):
    lt = tt - e["t0"]
    if lt < 0 or lt > e["dur"]:
        return
    s = e["s"]
    fr = int(lt * FPS)
    sc = e["scale"]
    if e["style"] == "type" and not e["giant"]:
        s = s[:max(1, int(math.ceil(len(s) * cl(lt / 0.12))))]
    elif e["style"] == "slam":
        sc *= 1.4 - 0.4 * eo(lt / 0.08)
    a = cl(lt / 0.04) * cl((e["dur"] - lt) / 0.06) * a_mul
    if e["fp"] == SERIF and e["wt"] <= 300:
        im = slim(s, e["size"], 280, e["col"], squeeze=0.8, vertical=e["vert"], shadow=0.4)
    else:
        im = timg(s, e["fp"], e["size"], e["wt"], e["col"], track=2 if not e["vert"] else 0, vertical=e["vert"])
    x = e["x"] + e["vx"] * lt
    y = e["y"]
    if push:
        x += (x - W / 2) * push
        y += (y - H / 2) * push
    put(F, im, x, y, a, sc)
    if fr <= 2 and a_mul > 0.5 and e["style"] in ("scan", "wave", "block"):
        hw, hh = im.width * sc / 2 + 30, im.height * sc / 2 + 10
        if e["style"] == "scan":
            fxl.append(lambda a_, fi_: gx_scan(a_, y - hh, y + hh, 40, fi_, x - hw, x + hw, seed=e["seed"]))
        elif e["style"] == "wave":
            fxl.append(lambda a_, fi_: gx_wave(a_, y - hh, y + hh, 16, fi_, x - hw, x + hw, seed=e["seed"]))
        else:
            fxl.append(lambda a_, fi_: gx_block(a_, x - hw, y - hh, x + hw, y + hh, 4, fi_, seed=e["seed"], bw=(20, 140), bh=(6, 40), disp=60))


def _plans():
    kinds = ["full", "none", "close", "full2", "none", "close", "vert", "none", "full", "close", "full2", "none"]
    out = []
    for j in range(4):
        r = np.random.default_rng(300 + j)
        out.append([dict(k=kd, n=int(r.integers(2, 4)), font=int(r.integers(0, 4)), x=r.uniform(-1, 1), y=r.uniform(-1, 1),
                         N=int(r.integers(3, 6)), side=int(r.integers(0, 2)), sc=r.uniform(4.2, 6.0)) for kd in kinds])
    return out


PLANS = _plans()


@functools.lru_cache(maxsize=1)
def band_mask():
    m = mask()
    cv2.rectangle(m, (0, int(H / 2 - 110)), (W, int(H / 2 + 110)), 255, -1)
    return Image.fromarray(m).filter(ImageFilter.GaussianBlur(40))


@functools.lru_cache(maxsize=1)
def grid_mask():
    m = mask()
    for x in range(0, W, 120):
        ln(m, (x, 0), (x, H))
    for y in range(0, H, 120):
        ln(m, (0, y), (W, y))
    return m


def s5_bg(t, a):
    b = int((t - T5) / 0.3)
    rr = R("s5bg", b)
    c = CHARS[int(rr.integers(0, 21))]
    L = A["illus"][c]
    ent = L[int(rr.integers(0, len(L)))]
    gh = cover(img(ent["file"]), (W, H), 1.05 + 0.04 * ((t - T5) % 0.3) / 0.3)
    gh = ImageOps.invert(gh.convert("L")).convert("RGB")
    F = Image.blend(Image.new("RGB", (W, H), BG), gh, a)
    ink(F, grid_mask(), (120, 110, 120), 0.07)
    return F


def big_line(F, j, t, fi, fx):
    t0 = T5 + 3.6 * j
    lt = t - t0
    b = min(int(lt / 0.3 + 1e-6), 11)
    bf = lf(t, t0 + 0.3 * b)
    P = PLANS[j][b]
    if P["k"] == "none" or bf >= P["n"]:
        return 0.0
    line = BIG[j]
    fl = 0.0
    if P["k"] == "full":
        im = timg(line, SERIF, 104, 900, WHITE, stroke=2, sfill=(10, 8, 12), track=6)
        put(F, im, W / 2, H / 2, 1.0, 1.15 - 0.15 * bf / 2)
        if bf == 0:
            fx.append(lambda a: gx_scan(a, H / 2 - 30, H / 2 + 50, 26, fi, x0=W / 2 - im.width / 2 - 60, x1=W / 2 + im.width / 2 + 60))
            fl = 0.12
    elif P["k"] == "full2":
        im = [slim(line, 118, 260, WHITE, squeeze=0.8), timg(line, HEI, 96, 0, WHITE),
              timg(line, SONG, 100, 0, WHITE), timg(line, KAI, 104, 0, RED)][P["font"]]
        x, y = W / 2 + P["x"] * 240, H / 2 + P["y"] * 200
        put(F, im, x, y, 1.0)
        fx.append(lambda a: gx_wave(a, y - 80, y + 80, 10, fi, seed=j * 7 + b))
    elif P["k"] == "close":
        seg = line[-P["N"]:] if P["side"] == 0 else line[:P["N"]]
        im = timg(seg, SERIF, 120, 900, WHITE)
        sc = P["sc"]
        w2 = im.width * sc
        x = w2 / 2 - w2 * 0.35 if P["side"] == 0 else W - w2 / 2 + w2 * 0.35
        y = H / 2 + P["y"] * 140
        put(F, im, x, y, 1.0, sc)
        fx.append(lambda a: gx_wave(a, y - 260, y + 260, 22, fi, seed=j * 11 + b))
        fx.append(lambda a: gx_block(a, 0, y - 300, W, y + 300, 6, fi, seed=b))
    elif P["k"] == "vert":
        im = slim(line, 80, 320, WHITE, squeeze=0.82, vertical=True)
        x = W * (0.10 if P["side"] == 0 else 0.90)
        put(F, im, x, H / 2, 1.0, min(1.0, H * 0.94 / im.height))
        fx.append(lambda a: gx_scan(a, 0, H, 20, fi, x0=x - 90, x1=x + 90))
    if j == 2:
        fx.append(lambda a: gx_wave(a, H / 2 - 140, H / 2 + 140, 18, fi, seed=33))
    return fl


def s5(t, fi):
    please = t >= T_PLEASE
    B = t >= g(228)
    F = s5_bg(t, 0.07 if please else (0.20 if B else 0.14))
    tt = min(t, T_PLEASE)
    fxl = []
    for e in EV:
        ev_draw(F, e, tt, fxl, 0.25 if please else 1.0)
    fx = [(lambda a, f_=f_: f_(a, fi)) for f_ in fxl] if not please else []
    shake = (0, 0)
    fl = 0.0
    if not please:
        F.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), band_mask().point(lambda v: int(v * 0.35)))
        j = min(int((t - T5) / 3.6), 3)
        fl = big_line(F, j, t, fi, fx)
        if fl:
            shake = (10 if fi % 2 else -10, 4)
        fx.append(lambda a: gx_stripe(a, 0, 120, 2, fi))
        fx.append(lambda a: gx_stripe(a, H - 120, H, 2, fi, seed=1))
    else:
        F.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), band_mask().point(lambda v: int(v * 0.55)))
        lt = t - T_PLEASE
        im = timg("请你", SERIF, 150, 800, WHITE, stroke=2, sfill=(10, 8, 12), track=40)
        put(F, im, W / 2, H / 2, cl(lt / 0.12), 1.12 - 0.12 * eo(lt / 0.3) + 0.01 * math.sin(lt * 6))
        fp = lf(t, T_PLEASE)
        if fp % 18 < 2 and fp > 4:
            fx.append(lambda a: gx_scan(a, H / 2 - 110, H / 2 + 110, 50, fi, x0=W / 2 - 400, x1=W / 2 + 400))
        fl = 0.3 if fp == 0 else 0.0
    return post(F, fi, vig=1.0, noise=0.45, fx=fx, shake=shake, flash=fl)


PURE_RED = (226, 16, 30)


@functools.lru_cache(maxsize=1)
def final_img():
    """终句：纯红大字。"""
    return timg(FINAL, SERIF, 196, 900, PURE_RED, track=14)


def final_bg(t):
    """终句背景：只有纯红噪点（在 post 里用 noise_red 叠），不要线条装饰。"""
    return Image.new("RGB", (W, H), (8, 2, 3))


def s5_final(t, fi):
    """终句：纯红小字闪回 → 中字 → 大字砸下，带浓重黑白故障。"""
    lt = t - T_FINAL
    f = lf(t, T_FINAL)
    F = final_bg(t)
    fx = []
    shake = (0, 0)
    fl = 0.0
    if t < T_FMID:
        r = R("fsm", f // 2)
        for q in range(3):
            sz = int(round((30 + 70 * lt / (T_FMID - T_FINAL) * r.uniform(0.6, 1.4)) / 6) * 6)
            fp, wt = FONTS5[int(r.integers(0, len(FONTS5)))]
            x, y = r.uniform(0.15, 0.85) * W, r.uniform(0.15, 0.85) * H
            put(F, timg(FINAL, fp, sz, wt, PURE_RED), x, y, 1.0)
            if q == 0:
                fx.append(lambda a, x=x, y=y, sz=sz: gx_block(a, x - sz * 4, y - sz, x + sz * 4, y + sz, 5, fi, bw=(20, 160), bh=(6, 40)))
        eb = (0, H * 0.22) if (fi // 3) % 2 else (H * 0.78, H)   # 条纹只在上/下边缘轮换，不铺满全屏
        fx.append(lambda a: gx_stripe(a, eb[0], eb[1], 6, fi))
    elif t < T_FBIG:
        r = R("fmid", f // 3)
        sz = int(r.choice([150, 180, 220, 260]))
        fp, wt = FONTS5[int(r.integers(0, len(FONTS5)))]
        y = r.uniform(0.3, 0.7) * H
        put(F, timg(FINAL, fp, sz, wt, PURE_RED), W / 2 + r.uniform(-200, 200), y, 1.0)
        if f % 3 == 0:   # 每次换字号的第一帧抖一下，其余帧字要看得清
            fx.append(lambda a: gx_scan(a, y - sz * 0.7, y + sz * 0.7, 60, fi, bright=1.1))
        fx.append(lambda a: gx_stripe(a, y - sz, y + sz, 10, fi))
        if lf(t, T_FMID + 0.3 * int((t - T_FMID) / 0.3)) == 0:
            fl = 0.15
    else:
        lt2 = t - T_FBIG
        f2 = lf(t, T_FBIG)
        im = final_img()
        put(F, im, W / 2, H / 2, cl(lt2 / 0.04), 1.6 - 0.6 * eo(lt2 / 0.12))
        amp = 30 * (1 - eo(lt2 / 0.6)) + 3
        shake = (amp * (1 if f2 % 2 else -1), amp * 0.5 * (1 if f2 % 3 else -1))
        fl = 0.9 if f2 == 0 else (0.45 if f2 == 1 else 0.0)
        if f2 % 6 < 2:
            fx.append(lambda a: gx_scan(a, H / 2 - 90, H / 2 + 60, 120, fi, bright=1.0))
        fx.append(lambda a: gx_block(a, 0, 0, W * 0.3, H, 6, fi))
        fx.append(lambda a: gx_block(a, W * 0.7, 0, W, H, 6, fi, seed=2))
        fx.append(lambda a: gx_stripe(a, 0, H * 0.2, 4, fi))
        fx.append(lambda a: gx_stripe(a, H * 0.8, H, 4, fi, seed=3))
    return post(F, fi, vig=1.0, fx=fx, shake=shake, flash=fl, noise_red=1.0)


@functools.lru_cache(maxsize=1)
def vanish_bands():
    im = final_img()
    h = im.height
    r = np.random.default_rng(91)
    out = []
    y = 0
    while y < h:
        hh = int(r.integers(3, 26))
        out.append((y, min(h, y + hh), r.uniform(0.0, 0.82), int(r.choice([-1, 1])), r.uniform(900, 2600)))
        y += hh
    return out


def s5_vanish(t, fi):
    """终句消失：数字条纹 + 错位图块把文字一条条抽走；最后一帧之后立刻进倒放。"""
    v = (t - T_DIS) / (T6 - T_DIS)
    F = final_bg(t)
    im = final_img()
    x0, y0 = int(W / 2 - im.width / 2), int(H / 2 - im.height / 2)
    for (a0, a1, th, sg, sp) in vanish_bands():
        band = im.crop((0, a0, im.width, a1))
        if v < th:
            F.paste(band, (x0, y0 + a0), band)
            continue
        q = v - th
        al = cl(1 - q / 0.22)
        if al <= 0:
            continue
        F.paste(amul(band, al), (int(x0 + sg * sp * q), y0 + a0), amul(band, al))
    fx = [lambda a: gx_stripe(a, y0 - 40, y0 + im.height + 40, int(6 + 30 * v), fi),
          lambda a: gx_block(a, x0 - 100, y0 - 60, x0 + im.width + 100, y0 + im.height + 60, int(4 + 24 * v), fi, bw=(30, 260), bh=(8, 60), disp=200)]
    return post(F, fi, vig=1.0, fx=fx, flash=0.35 if lf(t, T_DIS) == 0 else 0.0, noise_red=1.0)


# ================= 第六段：因果逆流 + 闭眼 =================
def rev_s(t):
    u = (t - T6) / (T_GAZE - T6)
    return REV_S0 - (REV_S0 - REV_S1) * eio(u), u


def read_frame(i):
    i = int(cl(i, 0, fidx(T6) - 1))
    return np.asarray(Image.open(os.path.join(FRAMES, "f_%05d.jpg" % i)), dtype=np.float32)


def s6_rev(t, fi):
    """紧接终句消失的超高速倒放：全程黑白 + 模拟噪点打底。"""
    s, u = rev_s(t)
    s_prev, _ = rev_s(t - 1 / FPS)
    d = max(0.0, s_prev - s)
    n = 3 if d > 2 / FPS else 1
    acc = None
    for j in range(n):
        a = read_frame(round((s + d * j / n) * FPS))
        acc = a if acc is None else acc + a
    acc /= n
    F = Image.fromarray(np.clip(acc, 0, 255).astype(np.uint8))
    k = 1 - cl((u - 0.92) / 0.08)
    return post(F, fi, vig=0.8, sat=1 - k, noise=1.2 * k + 0.3)


def s6_gaze(t, fi):
    if t < 131.4:
        o = 5.0
    elif t < 135.0:
        o = 5 - 1.7 * eio((t - 131.4) / 3.6)
    elif t < T_CLOSE:
        o = 3.3 * (1 - ei((t - 135.0) / (T_CLOSE - 135.0)) ** 0.6)
    else:
        o = 0.0
    z = eye_z(REV_S1) + 0.03 * eio((t - T_GAZE) / (T_CLOSE - T_GAZE))
    al = 1.0 if t < 135.9 else 1 - eio((t - 135.9) / 1.9)
    F = eye_scene(t, o, z, alpha=al)
    return post(F, fi, vig=1.2, noise=0.95 * (1 - cl((t - 135.9) / 1.9)))


# ================= 调度 =================
def render(fi):
    t = fi / FPS
    if t < T_HIT:
        return s1_eye(t, fi)
    if t < T_P0:
        return s1_dive(t, fi)
    if t < T_ORB:
        return s1_poly(t, fi)
    if t < T_CONV:
        return s1_orbit(t, fi)
    if t < T_CRACK:
        return s1_burst(t, fi)
    if t < T2:
        return s1_freeze(t, fi)
    if t < T2E:
        return s2(t, fi)
    if t < T3:
        return s2_end(t, fi)
    if t < T_Q:
        return s3(t, fi)
    if t < T_XA:
        return s3_q(t, fi)
    if t < T4:
        return s3_xiaoai(t, fi)
    if t < T_ROLL:
        return s4(t, fi)
    if t < T5:
        return s4_roll(t, fi)
    if t < T_FINAL:
        return s5(t, fi)
    if t < T_DIS:
        return s5_final(t, fi)
    if t < T6:
        return s5_vanish(t, fi)
    if t < T_GAZE:
        return s6_rev(t, fi)
    return s6_gaze(t, fi)


def work(chunk):
    a, b, force = chunk
    done = 0
    for i in range(a, b):
        p = os.path.join(FRAMES, "f_%05d.jpg" % i)
        if os.path.exists(p) and not force:
            continue
        render(i).save(p, quality=94)
        done += 1
    return a, b, done


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pass", dest="ps", type=int, default=0)
    ap.add_argument("--range", default="")
    ap.add_argument("--preview", default="")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--out", default="")
    args = ap.parse_args()
    os.makedirs(FRAMES, exist_ok=True)
    if args.preview:
        ts = [float(x) for x in args.preview.split(",")]
        out = args.out or os.path.join(MAT, "_preview")
        os.makedirs(out, exist_ok=True)
        thumbs = []
        for tsec in ts:
            im = render(fidx(tsec))
            im.save(os.path.join(out, "t_%07.2f.jpg" % tsec), quality=90)
            thumbs.append(im.resize((480, 270)))
        cols = 4
        rows = (len(thumbs) + cols - 1) // cols
        sh = Image.new("RGB", (cols * 480, rows * 290), (30, 30, 30))
        d = ImageDraw.Draw(sh)
        for k, (tsec, th) in enumerate(zip(ts, thumbs)):
            sh.paste(th, ((k % cols) * 480, (k // cols) * 290))
            d.text(((k % cols) * 480 + 4, (k // cols) * 290 + 272), "%.2f" % tsec, fill=(255, 255, 0))
        sh.save(os.path.join(out, "sheet.jpg"), quality=88)
        print("preview", os.path.join(out, "sheet.jpg"))
        return
    if args.range:
        a, b = [float(x) for x in args.range.split(":")]
        idx = list(range(fidx(a), min(NF, fidx(b))))
    elif args.ps == 1:
        idx = [i for i in range(NF) if not (fidx(T6) <= i < fidx(T_GAZE))]
    elif args.ps == 2:
        idx = list(range(fidx(T6), fidx(T_GAZE)))
    else:
        idx = list(range(NF))
    chunks = []
    i = 0
    while i < len(idx):
        j = i
        while j + 1 < len(idx) and idx[j + 1] == idx[j] + 1 and j - i < 29:
            j += 1
        chunks.append((idx[i], idx[j] + 1, args.force))
        i = j + 1
    from multiprocessing import Pool
    import time
    st = time.time()
    tot = 0
    with Pool(args.workers) as pool:
        for a, b, dn in pool.imap_unordered(work, chunks):
            tot += b - a
            print("frames %d-%d (%d new)  %d/%d  %.0fs" % (a, b, dn, tot, len(idx), time.time() - st), flush=True)
    print("done", len(idx))


if __name__ == "__main__":
    main()
