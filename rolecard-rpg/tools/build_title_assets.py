"""Build official Godot title-screen assets from user-adopted falling girl & r6 title layers."""
from __future__ import annotations

import hashlib
import json
import math
import pathlib
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

TOOLS_DIR = pathlib.Path(__file__).resolve().parent
PROJECT_ROOT = TOOLS_DIR.parent
MYSTIC_DIR = PROJECT_ROOT / "assets" / "ui" / "mystic"
WORK_DIR = PROJECT_ROOT / "workspaces" / "frontend-ui" / "materials" / "ui-title-falling-girl-20261115"
STAR_MAT_DIR = PROJECT_ROOT / "workspaces" / "frontend-ui" / "materials" / "ui-title-main-star-20261114"
ARTIFACT_DIR = pathlib.Path(
    r"C:\Users\whz07\.gemini\antigravity\brain\ef8082d6-ac96-4063-bceb-b343c2c3c362"
)

USER_GIRL_SRC = ARTIFACT_DIR / ".user_uploaded" / "media_1794794844234_dc012d8d.png"
LOGO_CROP = (185, 67, 1486, 905)  # 1301 x 838 matching title_logo_mask.receipt.json

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\NotoSerifSC-Regular.otf",
    r"C:\Windows\Fonts\simsun.ttc",
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\STSONG.TTF",
]


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for fp in FONT_CANDIDATES:
        if pathlib.Path(fp).exists():
            try:
                return ImageFont.truetype(fp, size)
            except Exception:
                pass
    return ImageFont.load_default()


def sha256_file(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def dilate_time_field(mask: np.ndarray, t_vals: np.ndarray, radius_steps: int = 8) -> np.ndarray:
    """Propagate valid stroke timestamps into transparent neighbors so bilinear filtering never bleeds t=0."""
    valid = mask > 8
    out = np.where(valid, t_vals, 0.0)
    cur_valid = valid.copy()
    for _ in range(radius_steps):
        padded_v = np.pad(cur_valid, 1, mode="constant", constant_values=False)
        padded_t = np.pad(out, 1, mode="edge")
        acc_t = np.zeros_like(out)
        acc_c = np.zeros_like(out)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                nv = padded_v[1 + dy : 1 + dy + out.shape[0], 1 + dx : 1 + dx + out.shape[1]]
                nt = padded_t[1 + dy : 1 + dy + out.shape[0], 1 + dx : 1 + dx + out.shape[1]]
                acc_t += np.where(nv, nt, 0.0)
                acc_c += nv.astype(np.float32)
        fill = (~cur_valid) & (acc_c > 0)
        out = np.where(fill, acc_t / np.maximum(acc_c, 1.0), out)
        cur_valid = cur_valid | fill
    return np.where(cur_valid, out, 1.0)


def assign_stroke_time(
    xx: np.ndarray,
    yy: np.ndarray,
    eng_alpha: np.ndarray,
    zh_alpha: np.ndarray,
) -> np.ndarray:
    """Build simultaneous multi-letter stroke-order timestamps t in [0.0, 1.0] across AETHERA + 艾瑟拉."""
    h, w = xx.shape
    t = np.zeros((h, w), dtype=np.float32)

    def lerp_seg(val: np.ndarray, v0: float, v1: float, t0: float, t1: float) -> np.ndarray:
        p = np.clip((val - v0) / (v1 - v0), 0.0, 1.0) if abs(v1 - v0) > 1e-4 else np.full_like(val, 0.5)
        return t0 + p * (t1 - t0)

    # All letters draw concurrently by stroke wave (with subtle left-to-right grace stagger):
    # Wave 1 (~0.00..0.42): primary left stems / top bars across A-E-T-H-E-R-A
    # Wave 2 (~0.36..0.76): secondary right stems / bowls / middle bars
    # Wave 3 (~0.66..1.00): crossbars, base horizontals & R's sweeping flourish tail

    # 1) Letter A1: left flourish leg (0.00..0.42) -> right slant (0.38..0.72) -> crossbar (0.68..0.94)
    m_a1 = xx < 336.5
    leg_slope_mid_x = 214.0 + (yy - 234.0) * 0.16
    is_a1_bar = (yy >= 371.0) & (yy <= 387.0) & (xx >= 150.0) & (xx <= 267.0)
    is_a1_right = (xx >= leg_slope_mid_x) & (~is_a1_bar)
    t_a1 = np.where(
        is_a1_bar,
        lerp_seg(xx, 150.0, 267.0, 0.68, 0.94),
        np.where(
            is_a1_right,
            lerp_seg(yy, 234.0, 472.0, 0.38, 0.72),
            lerp_seg(yy, 234.0, 610.0, 0.00, 0.42),
        ),
    )
    t = np.where(m_a1, t_a1, t)

    # 2) Letter E1: vertical stem (0.02..0.38) -> top bar (0.36..0.62) -> mid bar (0.50..0.74) -> bottom bar (0.68..0.94)
    m_e1 = (xx >= 336.5) & (xx < 463.0)
    t_e1 = np.where(
        xx <= 368.0,
        lerp_seg(yy, 287.0, 473.0, 0.02, 0.38),
        np.where(
            yy <= 325.0,
            lerp_seg(xx, 368.0, 461.0, 0.36, 0.62),
            np.where(
                yy <= 415.0,
                lerp_seg(xx, 368.0, 446.0, 0.50, 0.74),
                lerp_seg(xx, 368.0, 461.0, 0.68, 0.94),
            ),
        ),
    )
    is_t_top_in_overlap = (xx >= 450.0) & (yy <= 305.0)
    m_e1_clean = m_e1 & (~is_t_top_in_overlap)
    t = np.where(m_e1_clean, t_e1, t)

    # 3) Letter T: top bar (0.03..0.37) -> center vertical stem (0.36..0.82)
    m_t = ((xx >= 463.0) & (xx < 622.0)) | is_t_top_in_overlap
    t_t = np.where(
        yy <= 308.0,
        lerp_seg(xx, 450.0, 602.0, 0.03, 0.37),
        lerp_seg(yy, 290.0, 473.0, 0.36, 0.82),
    )
    t = np.where(m_t, t_t, t)

    # 4) Letter H: left stem (0.04..0.39) -> right stem (0.38..0.74) -> crossbar (0.70..0.96)
    m_h = (xx >= 622.0) & (xx < 802.0)
    t_h = np.where(
        xx <= 670.0,
        lerp_seg(yy, 287.0, 473.0, 0.04, 0.39),
        np.where(
            xx >= 756.0,
            lerp_seg(yy, 287.0, 473.0, 0.38, 0.74),
            lerp_seg(xx, 670.0, 756.0, 0.70, 0.96),
        ),
    )
    t = np.where(m_h, t_h, t)

    # 5) Letter E2: stem (0.05..0.41) -> top bar (0.38..0.64) -> mid bar (0.52..0.76) -> bottom bar (0.70..0.96)
    m_e2 = (xx >= 802.0) & (xx < 944.0)
    t_e2 = np.where(
        xx <= 845.0,
        lerp_seg(yy, 287.0, 473.0, 0.05, 0.41),
        np.where(
            yy <= 325.0,
            lerp_seg(xx, 845.0, 938.0, 0.38, 0.64),
            np.where(
                yy <= 415.0,
                lerp_seg(xx, 845.0, 924.0, 0.52, 0.76),
                lerp_seg(xx, 845.0, 938.0, 0.70, 0.96),
            ),
        ),
    )
    t = np.where(m_e2, t_e2, t)

    # 6) Letter R: left stem (0.06..0.42) -> upper bowl (0.40..0.70) -> sweeping flourish tail (0.66..1.00)
    is_r_tail_under_a2 = (xx >= 1080.0) & (yy >= 475.5)
    m_r = ((xx >= 944.0) & (xx < 1088.0)) | is_r_tail_under_a2
    tail_p = np.clip((xx - 1000.0) / 276.0, 0.0, 1.0)
    ang_r = np.arctan2(yy - 344.0, xx - 990.0)
    bowl_p = np.clip((ang_r + math.pi * 0.55) / (math.pi * 1.15), 0.0, 1.0)
    t_r = np.where(
        (xx <= 986.0) & (yy <= 478.0),
        lerp_seg(yy, 287.0, 473.0, 0.06, 0.42),
        np.where(
            yy <= 406.0,
            0.40 + bowl_p * 0.30,
            0.66 + tail_p * 0.34,
        ),
    )
    t = np.where(m_r, t_r, t)

    # 7) Letter A2: left leg (0.07..0.43) -> right leg (0.42..0.76) -> crossbar (0.72..0.98)
    m_a2 = (xx >= 1088.0) & (yy < 475.5)
    is_a2_bar = (yy >= 394.0) & (yy <= 410.0) & (xx >= 1131.0) & (xx <= 1219.0)
    is_a2_right = (xx >= 1175.0) & (~is_a2_bar)
    t_a2 = np.where(
        is_a2_bar,
        lerp_seg(xx, 1131.0, 1219.0, 0.72, 0.98),
        np.where(
            is_a2_right,
            lerp_seg(yy, 287.0, 474.0, 0.42, 0.76),
            lerp_seg(yy, 287.0, 474.0, 0.07, 0.43),
        ),
    )
    t = np.where(m_a2, t_a2, t)

    # 8) Chinese subtitle 艾 瑟 拉 writing simultaneously by calligraphic radical waves across [0.06..1.00]
    zh_mask = zh_alpha > 4
    in_zh_box = (xx >= 518.0) & (xx <= 784.0) & (yy >= 615.0) & (yy <= 685.0)

    def box_uv(x0: float, x1: float, y0: float, y1: float) -> tuple[np.ndarray, np.ndarray]:
        return np.clip((xx - x0) / (x1 - x0), 0.0, 1.0), np.clip((yy - y0) / (y1 - y0), 0.0, 1.0)

    ax, ay = box_uv(530.0, 576.0, 622.0, 676.0)
    t_ai = np.where(
        ay <= 0.36,
        0.06 + ax * 0.32,
        np.where(ax <= 0.56, 0.38 + (ay - 0.36) / 0.64 * 0.34, 0.68 + (ay - 0.36) / 0.64 * 0.28),
    )

    sx, sy = box_uv(626.0, 676.0, 622.0, 676.0)
    t_se = np.where(
        sy <= 0.54,
        np.where(sx <= 0.50, 0.08 + (sy * 0.55 + sx * 0.45) * 0.34, 0.36 + (sy * 0.55 + (sx - 0.5) * 0.9) * 0.34),
        0.66 + ((sy - 0.54) / 0.46 * 0.6 + sx * 0.4) * 0.32,
    )

    lx, ly = box_uv(722.0, 772.0, 622.0, 676.0)
    t_la = np.where(
        lx <= 0.40,
        0.10 + (ly * 0.72 + lx * 0.28) * 0.32,
        np.where(ly <= 0.45, 0.40 + ((lx - 0.4) / 0.6 * 0.5 + ly) * 0.32, 0.68 + ((ly - 0.45) / 0.55 * 0.55 + (lx - 0.4) / 0.6 * 0.45) * 0.32),
    )

    t_zh = np.where(xx < 595.0, t_ai, np.where(xx < 692.0, t_se, t_la))
    t = np.where(in_zh_box | zh_mask, t_zh, t)

    combined_alpha = np.maximum(eng_alpha, zh_alpha)
    return dilate_time_field(combined_alpha, np.clip(t, 0.004, 1.0), radius_steps=10)


def build_cradle_halo_texture(size: int = 1024) -> Image.Image:
    """Build white-tinted luminance RGBA texture for the ( U ) cradle halo behind Xiao Ai."""
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = (size - 1) * 0.5
    dx = xx - cx
    dy = yy - cy
    dist = np.sqrt((dx * 0.96) ** 2 + (dy * 1.04) ** 2)
    theta = np.arctan2(dy, dx)  # +pi/2 is bottom U vertex

    # Broad atmospheric inner bloom + double cradle arc + symmetrical (  ) bracket wings
    nebula = np.exp(-((dist / (size * 0.34)) ** 2)) * 0.36 + np.exp(-((dist / (size * 0.21)) ** 2)) * 0.24

    u_weight = np.clip((np.sin(theta) + 0.35) / 1.35, 0.0, 1.0) ** 0.75
    r_main = size * 0.29
    d_main = np.abs(dist - r_main)
    main_glow = np.exp(-((d_main / (size * 0.028)) ** 2)) * (0.28 + 0.72 * u_weight)
    main_core = np.exp(-((d_main / (size * 0.0048)) ** 2)) * (0.25 + 0.75 * u_weight)

    u_in = np.clip((np.sin(theta) + 0.12) / 1.12, 0.0, 1.0) ** 0.85
    d_in = np.abs(dist - size * 0.255)
    in_core = np.exp(-((d_in / (size * 0.0028)) ** 2)) * u_in * 0.76
    in_glow = np.exp(-((d_in / (size * 0.014)) ** 2)) * u_in * 0.34

    lr_weight = (np.abs(np.cos(theta)) ** 1.75) * np.clip(1.0 - np.abs(np.sin(theta)) * 0.62, 0.0, 1.0)
    d_wing = np.abs(dist - size * 0.385)
    wing_glow = np.exp(-((d_wing / (size * 0.022)) ** 2)) * lr_weight * 0.85
    wing_core = np.exp(-((d_wing / (size * 0.0042)) ** 2)) * lr_weight * 0.92

    d_wing2 = np.abs(dist - size * 0.42)
    wing2_core = np.exp(-((d_wing2 / (size * 0.0024)) ** 2)) * (np.abs(np.cos(theta)) ** 2.5) * 0.62

    bloom = np.clip(nebula * 0.55 + main_glow * 0.88 + in_glow + wing_glow, 0.0, 0.90)
    core = np.clip(main_core + in_core + wing_core + wing2_core, 0.0, 1.0)
    # Smoothly fade radial extent to strict zero well inside texture bounds (prevents any subtle square box edge)
    edge_dist = np.sqrt((dx / (size * 0.48)) ** 2 + (dy / (size * 0.48)) ** 2)
    radial_fade = np.clip((1.0 - edge_dist) / 0.24, 0.0, 1.0) ** 1.8
    alpha = np.clip(core + bloom * (1.0 - core), 0.0, 1.0) * radial_fade

    rgba = np.zeros((size, size, 4), dtype=np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.clip(alpha * 255.0, 0, 255).astype(np.uint8)
    halo_img = Image.fromarray(rgba, mode="RGBA")
    hd = ImageDraw.Draw(halo_img, "RGBA")

    def draw_star4(sx: float, sy: float, sr: float) -> None:
        ri = sr * 0.24
        hd.polygon(
            [(sx, sy - sr), (sx + ri, sy - ri), (sx + sr, sy), (sx + ri, sy + ri),
             (sx, sy + sr), (sx - ri, sy + ri), (sx - sr, sy), (sx - ri, sy - ri)],
            fill=(255, 255, 255, 240),
        )

    for deg, rf, sr in [(90, 0.29, 13.0), (38, 0.29, 8.0), (142, 0.29, 8.0), (180, 0.385, 10.0), (0, 0.385, 10.0)]:
        ang = math.radians(deg)
        draw_star4(cx + math.cos(ang) * size * rf * 1.04, cy + math.sin(ang) * size * rf * 0.96, sr)

    return halo_img


def draw_preview_star4(draw: ImageDraw.ImageDraw, cx: float, cy: float, r: float, col: tuple[int, int, int, int]) -> None:
    ri = r * 0.24
    draw.polygon(
        [(cx, cy - r), (cx + ri, cy - ri), (cx + r, cy), (cx + ri, cy + ri),
         (cx, cy + r), (cx - ri, cy + ri), (cx - r, cy), (cx - ri, cy - ri)],
        fill=col,
    )


def render_wordmark_at(
    text_mask: np.ndarray,
    star_mask: np.ndarray,
    text_prog: float,
    star_prog: float,
    ink_rgb: tuple[int, int, int],
    star_rgb: tuple[int, int, int],
    accent_rgb: tuple[int, int, int],
) -> Image.Image:
    h, w, _ = text_mask.shape
    t_stroke = text_mask[..., 0].astype(np.float32) / 255.0
    t_a = text_mask[..., 3].astype(np.float32) / 255.0
    s_rad = star_mask[..., 0].astype(np.float32) / 255.0
    s_a = star_mask[..., 3].astype(np.float32) / 255.0

    # Smooth pen stroke reveal + subtle accent tip glow at active stroke edge
    stroke_vis = np.clip((text_prog - (t_stroke - 0.025)) / 0.028, 0.0, 1.0)
    stroke_vis = np.where(text_prog >= 0.999, 1.0, stroke_vis)
    pen_glow = np.clip(1.0 - np.abs(text_prog - t_stroke) / 0.024, 0.0, 1.0) * (1.0 if text_prog < 0.999 else 0.0)
    vis_ta = t_a * stroke_vis

    star_vis = np.clip((star_prog - (s_rad - 0.12)) / 0.13, 0.0, 1.0) if star_prog > 0.001 else np.zeros_like(s_a)
    vis_sa = s_a * star_vis

    out = np.zeros((h, w, 4), dtype=np.float32)
    # Draw star layer behind text layer
    for ch in range(3):
        text_col = ink_rgb[ch] * (1.0 - pen_glow * 0.65) + accent_rgb[ch] * (pen_glow * 0.65)
        premul = text_col * vis_ta + star_rgb[ch] * vis_sa * (1.0 - vis_ta)
        tot_a = np.clip(vis_ta + vis_sa * (1.0 - vis_ta), 0.0, 1.0)
        out[..., ch] = np.clip(premul / np.maximum(tot_a, 1e-4), 0.0, 255.0)
    out[..., 3] = np.clip((vis_ta + vis_sa * (1.0 - vis_ta)) * 255.0, 0.0, 255.0)
    return Image.fromarray(out.astype(np.uint8), mode="RGBA")


def build_previews(
    girl_rgba: Image.Image,
    halo_white: Image.Image,
    text_mask_arr: np.ndarray,
    star_mask_arr: np.ndarray,
) -> tuple[pathlib.Path, pathlib.Path, pathlib.Path]:
    W, H = 1920, 1080
    font_big = load_font(34)
    font_med = load_font(30)
    font_small = load_font(16)

    def render_theme(theme: str) -> Image.Image:
        if theme == "day":
            bg = (244, 241, 236)
            ink = (34, 30, 32)
            star_col = (156, 152, 148)
            acc = (219, 38, 46)       # vivid Day red
            muted = (128, 120, 118)
        else:
            bg = (18, 18, 22)
            ink = (240, 236, 228)
            star_col = (182, 168, 134)
            acc = (255, 209, 61)      # vivid Night yellow
            muted = (145, 140, 132)

        canvas = Image.new("RGBA", (W, H), bg + (255,))

        # 1) Tint white-alpha halo texture into Day-Red / Night-Yellow & paste centered behind girl's oval
        ha = np.asarray(halo_white).copy()
        ha[..., 0], ha[..., 1], ha[..., 2] = acc
        ha[..., 3] = np.clip(ha[..., 3].astype(np.float32) * 0.92, 0, 255).astype(np.uint8)
        halo_sz = int(round(H * 0.48))
        halo_tinted = Image.fromarray(ha, mode="RGBA").resize((halo_sz, halo_sz), Image.Resampling.LANCZOS)
        halo_cx, halo_cy = int(round(W * 0.679)), int(round(H * 0.555))
        canvas.alpha_composite(halo_tinted, (halo_cx - halo_sz // 2, halo_cy - halo_sz // 2))

        # 2) Falling girl placed at crisp 0.90x native size (no pixel upscaling), aligned to user oval center
        gs = (int(round(girl_rgba.width * 0.90)), int(round(girl_rgba.height * 0.90)))
        girl_scaled = girl_rgba.resize(gs, Image.Resampling.LANCZOS)
        gx = int(round(halo_cx - gs[0] * 0.6738))
        gy = int(round(halo_cy - gs[1] * 0.5035))
        girl_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        girl_layer.alpha_composite(girl_scaled, (gx, gy))
        if theme == "day":
            sh = Image.new("RGBA", (W, H), (88, 60, 66, 0))
            sh.putalpha(girl_layer.getchannel("A").point(lambda v: int(v * 0.14)))
            sh = sh.filter(ImageFilter.GaussianBlur(radius=2.5))
            canvas = Image.alpha_composite(canvas, sh)
        canvas = Image.alpha_composite(canvas, girl_layer)

        # 3) Left hairline rules + wordmark + menu
        ui = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ud = ImageDraw.Draw(ui, "RGBA")
        ud.line([(60, int(H * 0.495)), (int(W * 0.36), int(H * 0.495))], fill=muted + (140,), width=1)
        ud.line([(int(W * 0.06), int(H * 0.98)), (int(W * 0.36), int(H * 0.02))], fill=muted + (90,), width=1)

        wm = render_wordmark_at(text_mask_arr, star_mask_arr, 1.0, 1.0, ink, star_col, acc).resize(
            (640, 412), Image.Resampling.LANCZOS
        )
        ui.alpha_composite(wm, (70, 70))
        draw_preview_star4(ud, 70 + 320, 70 + 185, 9.0, acc + (210,))

        menu_items = ["新的开始", "读取进度", "重播开场", "艾瑟拉的忠告", "设置", "退出"]
        for i, label in enumerate(menu_items):
            y = 560 + i * 64
            x = 150 + (14 if i == 0 else 0)
            if i == 0:
                draw_preview_star4(ud, 126, y + 24, 9.0, acc + (245,))
                ud.text((x, y), label, font=font_big, fill=ink + (245,))
                ud.line([(x - 6, y + 54), (x + 250, y + 54)], fill=acc + (225,), width=2)
            else:
                ud.text((x, y), label, font=font_med, fill=ink + (185,))
                ud.line([(x - 6, y + 50), (x + 80, y + 50)], fill=ink + (85,), width=1)

        ud.rounded_rectangle([W - 228, 34, W - 38, 92], radius=28, outline=acc + (190,), width=2, fill=bg + (195,))
        ud.text((W - 178, 49), "昼 · 红环" if theme == "day" else "夜 · 黄环", font=load_font(22), fill=ink + (235,))
        ud.text((56, 1028), "采用主视觉 · 笔画书写标题 + 后现十字星 + 鼠标视差（昼红 / 夜黄光圈）", font=font_small, fill=muted + (210,))
        canvas = Image.alpha_composite(canvas, ui)
        return canvas.convert("RGB")

    day_out = WORK_DIR / "adopted-preview-day-red.png"
    night_out = WORK_DIR / "adopted-preview-night-yellow.png"
    render_theme("day").save(day_out, "PNG")
    render_theme("night").save(night_out, "PNG")

    # 4-step stroke animation sheet showing text strokes completing BEFORE star opens
    pw, ph = 640, 412
    sheet = Image.new("RGB", (pw * 2 + 30, ph * 2 + 80), (244, 241, 236))
    sd = ImageDraw.Draw(sheet)
    tf = load_font(20)
    stages = [
        ("1. t=0.25 全体主干首笔同步齐写...", 0.25, 0.0),
        ("2. t=0.55 全体第二笔与中横同期舒展...", 0.55, 0.0),
        ("3. t=0.85 全部字形横画与R长尾共同收笔...", 0.85, 0.0),
        ("4. t=1.00+star 文字全部落笔后，最后慢现背后十字星", 1.0, 1.0),
    ]
    for idx, (cap, tp, sp) in enumerate(stages):
        col, row = idx % 2, idx // 2
        ox = 10 + col * (pw + 10)
        oy = 10 + row * (ph + 36)
        sd.text((ox, oy), cap, font=tf, fill=(34, 30, 32))
        cell = Image.new("RGBA", (pw, ph), (244, 241, 236, 255))
        wm = render_wordmark_at(text_mask_arr, star_mask_arr, tp, sp, (34, 30, 32), (156, 152, 148), (219, 38, 46)).resize(
            (pw, ph), Image.Resampling.LANCZOS
        )
        cell = Image.alpha_composite(cell, wm).convert("RGB")
        sheet.paste(cell, (ox, oy + 28))
    stages_out = WORK_DIR / "adopted-stroke-stages-sheet.png"
    sheet.save(stages_out, "PNG")
    return day_out, night_out, stages_out


def main() -> None:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    MYSTIC_DIR.mkdir(parents=True, exist_ok=True)
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

    # 1) Copy user-adopted falling girl PNG verbatim to runtime & archive
    if not USER_GIRL_SRC.exists():
        raise FileNotFoundError(USER_GIRL_SRC)
    girl_runtime = MYSTIC_DIR / "title_falling_girl.png"
    girl_archive = WORK_DIR / "adopted-user-falling-girl.png"
    shutil.copyfile(USER_GIRL_SRC, girl_runtime)
    shutil.copyfile(USER_GIRL_SRC, girl_archive)
    girl_rgba = Image.open(girl_runtime).convert("RGBA")

    # 2) Load r6 layers and build cropped (1301x838) text-stroke & radial-star masks
    eng_full = np.asarray(Image.open(STAR_MAT_DIR / "exact-r5" / "english-layer.png").convert("RGBA"))
    star_full = np.asarray(Image.open(STAR_MAT_DIR / "exact-r5" / "star-masked-layer.png").convert("RGBA"))
    zh_crop = np.asarray(Image.open(STAR_MAT_DIR / "chinese-crop" / "aethera-chinese-transparent.png").convert("RGBA"))

    x0, y0, x1, y1 = LOGO_CROP
    eng_c = eng_full[y0:y1, x0:x1, 3]
    star_c = star_full[y0:y1, x0:x1, 3]

    zh_layer = np.zeros_like(eng_c)
    zx0, zy0 = 708 - x0, 687 - y0
    zh_layer[zy0 : zy0 + zh_crop.shape[0], zx0 : zx0 + zh_crop.shape[1]] = zh_crop[..., 3]

    h, w = eng_c.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)

    stroke_t = assign_stroke_time(xx, yy, eng_c, zh_layer)
    text_alpha = np.maximum(eng_c, zh_layer)
    stroke_u8 = np.clip(np.round(stroke_t * 254.0) + 1.0, 1, 255).astype(np.uint8)
    text_mask_arr = np.dstack([stroke_u8, stroke_u8, stroke_u8, text_alpha])
    text_mask_path = MYSTIC_DIR / "title_logo_text_mask.png"
    Image.fromarray(text_mask_arr, mode="RGBA").save(text_mask_path, "PNG")

    # Star radial field centered at exact r5/r6 star axis inside cropped rect: (835.5-185, 452-67) = (650.5, 385.0)
    scx, scy = 835.5 - x0, 452.0 - y0
    dx = (xx - scx) / 465.0
    dy = (yy - scy) / 435.0
    star_rad = np.clip(np.sqrt(dx * dx + dy * dy), 0.0, 1.0)
    star_u8 = np.clip(np.round(star_rad * 254.0) + 1.0, 1, 255).astype(np.uint8)
    star_mask_arr = np.dstack([star_u8, star_u8, star_u8, star_c])
    star_mask_path = MYSTIC_DIR / "title_logo_star_mask.png"
    Image.fromarray(star_mask_arr, mode="RGBA").save(star_mask_path, "PNG")

    # 3) White-tinted ( U ) cradle halo texture
    halo_img = build_cradle_halo_texture(1024)
    halo_path = MYSTIC_DIR / "title_cradle_halo.png"
    halo_img.save(halo_path, "PNG")

    # 4) Build Day/Night & stroke-stages inspection sheets
    day_out, night_out, stages_out = build_previews(girl_rgba, halo_img, text_mask_arr, star_mask_arr)
    for fp in (day_out, night_out, stages_out):
        (ARTIFACT_DIR / fp.name).write_bytes(fp.read_bytes())

    receipt = {
        "task": "title-falling-girl-adopted-and-stroke-star-assets",
        "source_girl": str(USER_GIRL_SRC),
        "runtime_assets": {
            fp.name: {
                "path": str(fp),
                "size": list(Image.open(fp).size),
                "mode": Image.open(fp).mode,
                "sha256": sha256_file(fp),
            }
            for fp in (girl_runtime, text_mask_path, star_mask_path, halo_path)
        },
        "previews": {
            fp.name: {
                "path": str(fp),
                "size": list(Image.open(fp).size),
                "sha256": sha256_file(fp),
            }
            for fp in (girl_archive, day_out, night_out, stages_out)
        },
    }
    (WORK_DIR / "adopted-manifest.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2), "utf-8")
    print(json.dumps(receipt, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
