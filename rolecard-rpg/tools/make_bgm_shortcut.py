"""Create a Project Mystic icon (.ico) and Windows Desktop shortcut for the BGM workbench."""

from __future__ import annotations

import math
from pathlib import Path
import subprocess
import sys

from PIL import Image, ImageDraw

TOOLS_DIR = Path(__file__).resolve().parent
REPO_ROOT = TOOLS_DIR.parent.parent
UI_DIR = TOOLS_DIR / "bgm_workbench"
ICO_PATH = UI_DIR / "workbench.ico"
BAT_PATH = REPO_ROOT / "打开BGM配乐匹配工作台.bat"
SHORTCUT_NAME = "AETHERA 配乐匹配工作台.lnk"


def render_workbench_icon(size: int = 512) -> Image.Image:
    """Draw a high-contrast dark obsidian + gold cross-star + music emblem."""
    ss = size * 2
    img = Image.new("RGBA", (ss, ss), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = int(ss * 0.06)
    r = int(ss * 0.22)
    bg_box = (pad, pad, ss - pad, ss - pad)
    draw.rounded_rectangle(
        bg_box,
        radius=r,
        fill=(18, 18, 24, 255),
        outline=(216, 179, 106, 255),
        width=max(6, ss // 32),
    )

    cx = ss / 2.0
    cy = ss / 2.0

    # Inner crimson alchemy ring
    ring_r = ss * 0.35
    draw.ellipse(
        (cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r),
        outline=(194, 53, 56, 225),
        width=max(4, ss // 54),
    )

    # Four-point cross-star rays in translucent gold behind note
    long_arm = ss * 0.38
    waist = ss * 0.055
    star_pts = [
        (cx, cy - long_arm),
        (cx + waist, cy - waist),
        (cx + long_arm, cy),
        (cx + waist, cy + waist),
        (cx, cy + long_arm),
        (cx - waist, cy + waist),
        (cx - long_arm, cy),
        (cx - waist, cy - waist),
    ]
    draw.polygon(star_pts, fill=(216, 179, 106, 55), outline=(216, 179, 106, 210))

    # Crisp dark halo behind eighth-note so it separates cleanly from the star
    halo_color = (18, 18, 24, 240)
    note_color = (247, 239, 222, 255)
    head_rx = ss * 0.095
    head_ry = ss * 0.072
    head_cx = cx - ss * 0.055
    head_cy = cy + ss * 0.135
    stem_w = max(6, int(ss * 0.048))
    stem_x = head_cx + head_rx - stem_w * 0.5
    stem_top = cy - ss * 0.205
    halo_pad = ss * 0.022

    draw.ellipse(
        (head_cx - head_rx - halo_pad, head_cy - head_ry - halo_pad, head_cx + head_rx + halo_pad, head_cy + head_ry + halo_pad),
        fill=halo_color,
    )
    draw.rectangle(
        (stem_x - stem_w * 0.5 - halo_pad, stem_top - halo_pad, stem_x + stem_w * 0.5 + halo_pad, head_cy + halo_pad),
        fill=halo_color,
    )

    # Actual bright eighth-note body + warm gold flag
    draw.ellipse(
        (head_cx - head_rx, head_cy - head_ry, head_cx + head_rx, head_cy + head_ry),
        fill=note_color,
    )
    draw.rectangle((stem_x - stem_w * 0.5, stem_top, stem_x + stem_w * 0.5, head_cy), fill=note_color)

    flag_pts = [
        (stem_x, stem_top),
        (stem_x + ss * 0.165, stem_top + ss * 0.088),
        (stem_x + ss * 0.145, stem_top + ss * 0.175),
        (stem_x, stem_top + ss * 0.095),
    ]
    draw.polygon(flag_pts, fill=(216, 179, 106, 255))

    return img.resize((size, size), Image.Resampling.LANCZOS)


def build_ico() -> Path:
    base = render_workbench_icon(512)
    ICO_PATH.parent.mkdir(parents=True, exist_ok=True)
    base.save(
        ICO_PATH,
        format="ICO",
        sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)],
    )
    return ICO_PATH


def ensure_launcher_bat() -> Path:
    """Write the root launcher batch file using strict ASCII + Windows CRLF."""
    lines = [
        "@echo off",
        'cd /d "%~dp0"',
        'if exist "C:\\Python314\\pythonw.exe" (',
        '  start "" "C:\\Python314\\pythonw.exe" "%~dp0rolecard-rpg\\tools\\bgm_workbench.py" --open',
        "  exit /b 0",
        ")",
        'where pythonw >nul 2>nul && (start "" pythonw "%~dp0rolecard-rpg\\tools\\bgm_workbench.py" --open & exit /b 0)',
        'python "%~dp0rolecard-rpg\\tools\\bgm_workbench.py" --open',
        "if errorlevel 1 pause",
    ]
    payload = ("\r\n".join(lines) + "\r\n").encode("ascii")
    BAT_PATH.write_bytes(payload)
    return BAT_PATH


def resolve_python_launcher() -> tuple[Path, str]:
    """Prefer pythonw.exe (no console window) directly; fall back to the ASCII CRLF batch launcher."""
    pyw = Path(sys.executable).with_name("pythonw.exe")
    wb_script = TOOLS_DIR / "bgm_workbench.py"
    if pyw.is_file() and wb_script.is_file():
        return pyw, f'"{wb_script}" --open'
    if not BAT_PATH.is_file():
        raise FileNotFoundError(f"Missing launcher batch file: {BAT_PATH}")
    return BAT_PATH, ""


def create_desktop_shortcut() -> Path:
    if sys.platform != "win32":
        raise RuntimeError("Desktop shortcut creation is only supported on Windows.")

    ico_path = build_ico()
    ensure_launcher_bat()
    target_path, target_args = resolve_python_launcher()
    args_escaped = target_args.replace("'", "''")
    ps_script = (
        "$desktop = [Environment]::GetFolderPath('Desktop'); "
        f"$lnkPath = Join-Path $desktop '{SHORTCUT_NAME}'; "
        "$ws = New-Object -ComObject WScript.Shell; "
        "$sc = $ws.CreateShortcut($lnkPath); "
        f"$sc.TargetPath = '{str(target_path)}'; "
        f"$sc.Arguments = '{args_escaped}'; "
        f"$sc.WorkingDirectory = '{str(REPO_ROOT)}'; "
        "$sc.WindowStyle = 1; "
        f"$sc.IconLocation = '{str(ico_path)},0'; "
        "$sc.Description = '一键启动 AETHERA BGM 配乐匹配工作台并用浏览器打开'; "
        "$sc.Save(); "
        "Write-Output $lnkPath"
    )
    proc = subprocess.run(
        ["powershell", "-NoProfile", "-Command", ps_script],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(proc.stdout.strip())


def main() -> int:
    lnk = create_desktop_shortcut()
    print(f"Icon created: {ICO_PATH}", flush=True)
    print(f"Desktop shortcut created: {lnk}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
