"""Build the "mystic" UI sound pack (2026-11-14): ethereal, crisp, glassy, magical, never thuddy.

Every cue is synthesized from scratch with numpy (no third-party samples), so the pack is original
and safe to ship. Building blocks:
  glass(f)   inharmonic glass / crystal partials (1, 2.32, 4.25, 6.63) with fast exponential decay
  bell(f)    soft bell (1, 2, 3, 4.2 with slight detune) - longer tail
  sparkle()  cloud of tiny high sine grains (3-9 kHz) for shimmer
  air()      high-passed breathy noise swell (whoosh / page / veil)
  gliss()    sine glissando with harmonics (rise / fall)
A bright stereo room (FFT convolution with a decaying, high-passed noise impulse) adds space, and
every cue is finally high-passed at ~200 Hz so nothing reads as a dull thump.
Writes assets/audio/ui/mystic/<cue>.ogg and a manifest beside the pack.
Usage: python tools/build_ui_sfx_mystic.py
"""
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import wave

import numpy as np

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(PROJ, "assets", "audio", "ui", "mystic")
FFMPEG = r"C:\ffmpeg\bin\ffmpeg.exe" if os.path.exists(r"C:\ffmpeg\bin\ffmpeg.exe") else (shutil.which("ffmpeg") or "ffmpeg")
SR = 44100
rng = np.random.default_rng(20261114)


def t_axis(d):
    return np.arange(int(SR * d)) / SR


def env(d, a=0.004, decay=6.0):
    t = t_axis(d)
    e = np.exp(-t * decay)
    na = max(1, int(SR * a))
    e[:na] *= np.linspace(0, 1, na) ** 0.6
    return e


def note(n):  # semitones from A4
    return 440.0 * 2 ** (n / 12.0)


def glass(f, d=0.5, decay=9.0, amp=1.0, a=0.002):
    t = t_axis(d)
    out = np.zeros_like(t)
    for r, g, k in ((1.0, 1.0, 1.0), (2.32, 0.5, 1.6), (4.25, 0.25, 2.4), (6.63, 0.12, 3.4)):
        if f * r > 16000:
            continue
        out += g * np.sin(2 * np.pi * f * r * t + rng.random() * 6.28) * np.exp(-t * decay * k)
    na = max(1, int(SR * a))
    out[:na] *= np.linspace(0, 1, na)
    return amp * out


def bell(f, d=1.2, decay=3.2, amp=1.0, a=0.003):
    t = t_axis(d)
    out = np.zeros_like(t)
    for r, g, k in ((1.0, 1.0, 1.0), (2.0, 0.42, 1.4), (3.0, 0.22, 2.0), (4.2, 0.14, 2.8), (5.43, 0.07, 3.6)):
        if f * r > 16000:
            continue
        det = 1.0 + (rng.random() - 0.5) * 0.002
        out += g * np.sin(2 * np.pi * f * r * det * t) * np.exp(-t * decay * k)
    na = max(1, int(SR * a))
    out[:na] *= np.linspace(0, 1, na)
    return amp * out


def sparkle(d=0.6, n=18, lo=3000, hi=9000, amp=0.3, grow=False):
    out = np.zeros(int(SR * d))
    for i in range(n):
        start = rng.random() ** (0.6 if not grow else 1.6) * d * 0.85
        f = lo + rng.random() * (hi - lo)
        g = glass(f, 0.12, 40.0, 1.0)
        s = int(start * SR)
        e = min(len(out), s + len(g))
        out[s:e] += g[: e - s] * (0.4 + rng.random() * 0.6)
    return amp * out / max(1.0, n ** 0.5)


def hp(x, fc=200.0):
    X = np.fft.rfft(x)
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1.0 / np.sqrt(1.0 + (fc / np.maximum(fr, 1e-3)) ** 4)
    return np.fft.irfft(X, len(x))


def bandnoise(d, lo, hi):
    n = rng.standard_normal(int(SR * d))
    X = np.fft.rfft(n)
    fr = np.fft.rfftfreq(len(n), 1 / SR)
    X[(fr < lo) | (fr > hi)] = 0
    y = np.fft.irfft(X, len(n))
    return y / (np.max(np.abs(y)) + 1e-9)


def air(d=0.5, lo=2500, hi=12000, rise=0.5, amp=0.5):
    n = bandnoise(d, lo, hi)
    t = t_axis(d) / d
    shape = np.where(t < rise, (t / max(rise, 1e-3)) ** 1.6, ((1 - t) / max(1 - rise, 1e-3)) ** 1.4)
    return amp * n * shape


def gliss(f0, f1, d=0.3, amp=1.0, decay=4.0, harm=True):
    t = t_axis(d)
    f = f0 * (f1 / f0) ** (t / d)
    ph = 2 * np.pi * np.cumsum(f) / SR
    y = np.sin(ph) + (0.3 * np.sin(2 * ph) + 0.12 * np.sin(3.01 * ph) if harm else 0)
    e = np.exp(-t * decay)
    e[: int(SR * 0.004)] *= np.linspace(0, 1, int(SR * 0.004))
    return amp * y * e


def mix(*parts):
    n = max(len(p[1]) + int(p[0] * SR) for p in parts)
    out = np.zeros(n)
    for start, x in parts:
        s = int(start * SR)
        out[s:s + len(x)] += x
    return out


_IR = {}


def room(x, size=1.0, wet=0.28):
    key = round(size, 2)
    if key not in _IR:
        d = 0.35 + 1.1 * size
        irs = []
        for ch in range(2):
            n = bandnoise(d, 900, 14000) * np.exp(-t_axis(d) * (6.5 / size))
            n[: int(SR * 0.008)] = 0
            irs.append(n / np.sqrt(np.sum(n ** 2)))
        _IR[key] = irs
    out = []
    for ir in _IR[key]:
        L = len(x) + len(ir)
        y = np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(ir, L), L)
        out.append(np.concatenate([x, np.zeros(len(ir))]) * (1 - wet * 0.4) + y * wet)
    return np.stack(out, 1)


def finish(x, size=1.0, wet=0.28, peak=0.85, fc=200.0):
    x = hp(x, fc)
    st = room(x, size, wet)
    for ch in range(2):
        st[:, ch] = hp(st[:, ch], fc)
    # trim tail silence
    mag = np.max(np.abs(st), 1)
    idx = np.nonzero(mag > 1e-4 * np.max(mag))[0]
    st = st[: idx[-1] + 1 if len(idx) else len(st)]
    fade = min(len(st), int(SR * 0.03))
    st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    return st / (np.max(np.abs(st)) + 1e-9) * peak


C6, D6, E6, G6, A6, B6, C7, E7, G7 = (note(n) for n in (15, 17, 19, 22, 24, 26, 27, 31, 34))
C5, E5, G5, A5, B5 = (note(n) for n in (3, 7, 10, 12, 14))


def arp(freqs, gap=0.07, d=0.9, kind=bell, amp=0.7):
    return mix(*[(i * gap, kind(f, d, amp=amp * (1 - i * 0.08))) for i, f in enumerate(freqs)])


CUES = {
    "hover": lambda: finish(glass(3200, 0.12, 30, 0.6), 0.5, 0.18, 0.5),
    "focus": lambda: finish(glass(2600, 0.14, 26, 0.6), 0.5, 0.2, 0.45),
    "tick": lambda: finish(glass(4200, 0.05, 70, 0.6), 0.3, 0.1, 0.4),
    "type": lambda: finish(mix((0, glass(3600, 0.05, 60, 0.6)), (0, air(0.04, 6000, 12000, 0.2, 0.15))), 0.3, 0.1, 0.35),
    "select": lambda: finish(mix((0, glass(E6, 0.3, 12)), (0.045, glass(B6, 0.35, 11, 0.8))), 0.7, 0.25),
    "confirm": lambda: finish(mix((0, bell(C6, 0.8, 5, 0.7)), (0.0, bell(G6, 0.8, 5.5, 0.45)), (0.03, sparkle(0.5, 10, amp=0.5))), 0.9, 0.3),
    "confirm_big": lambda: finish(mix((0, arp([C6, E6, G6, C7], 0.06, 1.2)), (0.02, sparkle(1.0, 26, amp=0.7, grow=True)), (0, air(0.9, 3000, 12000, 0.2, 0.18))), 1.3, 0.34),
    "back": lambda: finish(mix((0, glass(G6, 0.3, 12, 0.8)), (0.06, glass(C6, 0.4, 10, 0.7))), 0.7, 0.25, 0.7),
    "close": lambda: finish(mix((0, gliss(E7, A6, 0.28, 0.4, 8)), (0, air(0.28, 3000, 11000, 0.1, 0.3))), 0.6, 0.22, 0.7),
    "popup": lambda: finish(mix((0, gliss(A6, E7, 0.3, 0.45, 5)), (0.12, sparkle(0.4, 12, amp=0.55))), 0.9, 0.3, 0.75),
    "toast": lambda: finish(mix((0, bell(1760, 0.9, 4.2, 0.6)), (0.05, sparkle(0.4, 8, amp=0.4))), 0.9, 0.3, 0.6),
    "tab": lambda: finish(mix((0, glass(1600, 0.25, 12, 0.7)), (0, glass(2400, 0.25, 14, 0.5))), 0.6, 0.22, 0.6),
    "toggle": lambda: finish(mix((0, glass(2800, 0.08, 40)), (0.05, glass(3600, 0.1, 36, 0.8))), 0.4, 0.15, 0.55),
    "deny": lambda: finish(mix((0, glass(A5, 0.18, 18, 0.8)), (0.07, glass(note(11), 0.22, 16, 0.8))), 0.5, 0.18, 0.6, 300),
    "error": lambda: finish(mix((0, bell(E6, 0.7, 5, 0.7)), (0.14, bell(note(16), 0.8, 4.5, 0.7))), 0.9, 0.3, 0.7, 260),
    "reset": lambda: finish(mix((0, air(0.35, 2000, 10000, 0.9, 0.4)), (0.33, glass(C7, 0.4, 9, 0.7))), 0.8, 0.28, 0.7),
    "save": lambda: finish(mix((0, glass(E7, 0.5, 8, 0.7)), (0.04, glass(B6, 0.5, 9, 0.5)), (0.06, sparkle(0.6, 14, amp=0.6, grow=True))), 1.0, 0.3, 0.75),
    "reward": lambda: finish(mix((0, arp([G6, B6, E7, G7], 0.07, 1.4)), (0, sparkle(1.3, 34, amp=0.8, grow=True)), (0, air(1.0, 4000, 13000, 0.15, 0.15))), 1.5, 0.36),
    "count": lambda: finish(glass(note(30), 0.15, 22, 0.7), 0.4, 0.15, 0.45),
    "recipe": lambda: finish(mix((0, gliss(C6, G6, 0.25, 0.5, 4)), (0.1, glass(G6, 0.4, 10, 0.6))), 0.8, 0.28, 0.7),
    "ready": lambda: finish(mix((0, arp([E6, A6, E7], 0.08, 0.9)), (0.05, sparkle(0.6, 14, amp=0.5))), 1.0, 0.3),
    "craft": lambda: finish(mix((0, air(0.6, 3000, 12000, 0.85, 0.3)), (0.5, arp([C6, G6, C7, E7], 0.05, 1.3)), (0.5, sparkle(1.0, 30, amp=0.8))), 1.4, 0.36),
    "aim": lambda: finish(glass(4400, 0.1, 30, 0.6), 0.4, 0.15, 0.5),
    "lockon": lambda: finish(mix((0, glass(3000, 0.2, 14, 0.7)), (0.06, glass(4500, 0.25, 14, 0.6))), 0.5, 0.2, 0.65),
    "wipe": lambda: finish(mix((0, air(0.75, 2200, 12000, 0.55, 0.6)), (0.38, bell(E7, 0.7, 4.0, 0.35)), (0.38, sparkle(0.5, 14, amp=0.45))), 1.2, 0.34, 0.7),
    "slide": lambda: finish(air(0.32, 3500, 13000, 0.35, 0.6), 0.6, 0.22, 0.5),
    "loaded": lambda: finish(mix((0, bell(C6, 0.8, 4, 0.5)), (0.0, bell(E6, 0.8, 4, 0.4)), (0.0, bell(G6, 0.8, 4, 0.35))), 1.0, 0.3, 0.6),
    "open_book": lambda: finish(mix((0, air(0.45, 1800, 9000, 0.3, 0.6)), (0.25, glass(A6, 0.5, 8, 0.4))), 0.8, 0.26, 0.65),
    "close_book": lambda: finish(mix((0, air(0.3, 1800, 9000, 0.6, 0.55)), (0.22, glass(E6, 0.35, 12, 0.35))), 0.7, 0.24, 0.6),
    "paper": lambda: finish(air(0.28, 2500, 11000, 0.3, 0.6), 0.5, 0.18, 0.5),
    "assign": lambda: finish(mix((0, glass(1800, 0.3, 14, 0.7)), (0.04, sparkle(0.45, 12, amp=0.5))), 0.8, 0.28, 0.7),
    "card": lambda: finish(mix((0, glass(2900, 0.15, 24)), (0, air(0.12, 4000, 12000, 0.2, 0.3))), 0.5, 0.2, 0.6),
    "start": lambda: finish(mix((0, air(1.4, 2500, 12000, 0.6, 0.35)), (0.5, arp([C6, G6, C7, E7, G7], 0.09, 1.6)), (0.4, sparkle(1.6, 40, amp=0.8, grow=True))), 1.8, 0.4),
    "theme": lambda: finish(mix((0, gliss(C7, G7, 0.4, 0.35, 3)), (0.02, bell(G6, 1.0, 3.2, 0.6)), (0.1, sparkle(0.8, 20, amp=0.6))), 1.3, 0.34, 0.7),
    "expand": lambda: finish(gliss(A6, E7, 0.18, 0.6, 8), 0.5, 0.2, 0.55),
    "collapse": lambda: finish(gliss(E7, A6, 0.18, 0.6, 8), 0.5, 0.2, 0.55),
    "send": lambda: finish(mix((0, air(0.3, 3000, 13000, 0.7, 0.5)), (0.24, glass(B6, 0.5, 9, 0.7)), (0.26, sparkle(0.4, 12, amp=0.5))), 1.0, 0.3, 0.75),
    "victory": lambda: finish(mix((0, arp([C6, E6, G6, C7, E7, G7], 0.11, 2.0)), (0.3, sparkle(1.8, 50, amp=0.9, grow=True)), (0.66, bell(C7, 1.8, 2.0, 0.5))), 2.0, 0.42),
    "defeat": lambda: finish(mix((0, bell(E6, 1.4, 2.2, 0.6)), (0.3, bell(C6, 1.4, 2.2, 0.6)), (0.6, bell(A5, 1.6, 2.0, 0.6)), (0, air(1.6, 2000, 8000, 0.5, 0.12))), 1.8, 0.42, 0.7, 260),
    "retreat": lambda: finish(mix((0, air(0.5, 2500, 11000, 0.2, 0.5)), (0.1, gliss(E7, C6, 0.45, 0.35, 4))), 1.0, 0.3, 0.65),
    "battle_enter": lambda: finish(mix((0, air(0.45, 3000, 13000, 0.9, 0.5)), (0.4, glass(note(28), 0.6, 6, 0.8)), (0.4, glass(note(21), 0.6, 6, 0.6)), (0.42, sparkle(0.6, 22, amp=0.7))), 1.2, 0.34),
    "turn": lambda: finish(mix((0, bell(A6, 0.6, 5, 0.6)), (0.09, bell(E7, 0.6, 5, 0.5))), 0.9, 0.3, 0.65),
    "round": lambda: finish(mix((0, bell(E6, 0.9, 3.6, 0.6)), (0.0, bell(B6, 0.9, 3.6, 0.4)), (0.05, sparkle(0.5, 12, amp=0.4))), 1.1, 0.32, 0.7),
    "hit": lambda: finish(mix((0, bandnoise(0.12, 2500, 12000) * env(0.12, 0.001, 30) * 0.6), (0, glass(2200, 0.25, 16, 0.6))), 0.6, 0.22, 0.8, 320),
    "hit_heavy": lambda: finish(mix((0, bandnoise(0.25, 1800, 13000) * env(0.25, 0.001, 16) * 0.7), (0, glass(1500, 0.5, 9, 0.7)), (0.02, sparkle(0.4, 20, amp=0.6)), (0, gliss(note(27), note(15), 0.25, 0.3, 8))), 0.9, 0.3, 0.85, 260),
    "hit_ally": lambda: finish(mix((0, bandnoise(0.12, 2000, 9000) * env(0.12, 0.001, 28) * 0.5), (0, glass(1300, 0.3, 14, 0.6))), 0.6, 0.22, 0.7, 300),
    "guard": lambda: finish(mix((0, glass(1250, 0.7, 5, 0.7) * (1 + 0.25 * np.sin(2 * np.pi * 18 * t_axis(0.7)))), (0, glass(1900, 0.5, 7, 0.4))), 1.0, 0.3, 0.75),
    "heal": lambda: finish(mix((0, sparkle(1.0, 30, 2500, 8000, 0.7, True)), (0.1, arp([E6, A6, C7], 0.12, 1.1, amp=0.5))), 1.3, 0.36, 0.7),
    "slam": lambda: finish(mix((0, air(0.18, 2500, 12000, 0.95, 0.6)), (0.17, bandnoise(0.3, 1500, 13000) * env(0.3, 0.001, 14) * 0.7), (0.17, glass(1100, 0.6, 7, 0.7)), (0.18, sparkle(0.5, 24, amp=0.6))), 1.0, 0.32, 0.85, 240),
    "pop": lambda: finish(gliss(1400, 2600, 0.12, 0.8, 18, harm=False), 0.5, 0.2, 0.55),
    "advance": lambda: finish(mix((0, air(0.2, 3000, 12000, 0.3, 0.3)), (0.04, glass(G6, 0.3, 12, 0.5))), 0.6, 0.22, 0.55),
    "delete": lambda: finish(mix((0, gliss(E7, E6, 0.4, 0.4, 5)), (0, sparkle(0.45, 16, 2500, 7000, 0.5))), 0.9, 0.3, 0.65),
    "unlock": lambda: finish(mix((0, arp([E6, G6, B6, E7], 0.05, 0.8, glass, 0.7)), (0.15, sparkle(0.7, 18, amp=0.6, grow=True))), 1.1, 0.32),
    "scan": lambda: finish(air(0.5, 5000, 14000, 0.5, 0.35), 0.6, 0.22, 0.32),
    # workshop + misc (new)
    "attach": lambda: finish(mix((0, glass(A6, 0.35, 12, 0.7)), (0.03, glass(E7, 0.35, 12, 0.6)), (0.02, sparkle(0.25, 8, amp=0.4))), 0.8, 0.26, 0.7),
    "place": lambda: finish(glass(1500, 0.3, 12, 0.7), 0.6, 0.22, 0.6),
    "pick": lambda: finish(gliss(2000, 3000, 0.1, 0.6, 16, harm=False), 0.4, 0.15, 0.5),
    "detach": lambda: finish(gliss(3000, 1700, 0.18, 0.6, 10), 0.6, 0.22, 0.6),
    "erase": lambda: finish(mix((0, sparkle(0.5, 18, 2500, 8000, 0.7)), (0, gliss(C7, C6, 0.4, 0.3, 5))), 0.8, 0.28, 0.65),
    "ignite": lambda: finish(mix((0, glass(note(26), 0.4, 10, 0.7)), (0, sparkle(0.3, 10, amp=0.4))), 0.8, 0.26, 0.6),
    "craft_charge": lambda: finish(mix((0, air(1.1, 2500, 13000, 0.9, 0.45)), (0, gliss(C6, C7, 1.1, 0.25, 0.8)), (0.2, sparkle(0.9, 30, amp=0.6, grow=True))), 1.2, 0.34, 0.7),
    "craft_done": lambda: finish(mix((0, arp([C6, G6, C7, E7, G7], 0.06, 1.6)), (0, sparkle(1.4, 40, amp=0.9, grow=True)), (0.05, bell(C6, 1.6, 2.0, 0.4))), 1.8, 0.4),
    "swap": lambda: finish(mix((0, glass(B6, 0.2, 18, 0.7)), (0.06, glass(E7, 0.25, 16, 0.6))), 0.6, 0.22, 0.6),
    "page": lambda: finish(mix((0, air(0.3, 2500, 11000, 0.35, 0.5)), (0.12, glass(C7, 0.35, 12, 0.4))), 0.7, 0.24, 0.6),
    "theme_day": lambda: finish(mix((0, gliss(A6, E7, 0.28, 0.4, 5)), (0.04, bell(E7, 0.6, 5.0, 0.5)), (0.08, sparkle(0.4, 14, amp=0.5))), 0.9, 0.28, 0.7),
    "theme_night": lambda: finish(mix((0, gliss(E7, A6, 0.32, 0.4, 4)), (0.04, bell(A6, 0.7, 4.2, 0.55)), (0.1, sparkle(0.5, 12, 2200, 6500, 0.45))), 1.0, 0.3, 0.7),
    "hover_soft": lambda: finish(glass(2700, 0.1, 32, 0.5), 0.4, 0.15, 0.45),
    "hover_card": lambda: finish(glass(3500, 0.09, 34, 0.55), 0.45, 0.16, 0.48),
    "chip": lambda: finish(mix((0, glass(E6, 0.22, 16, 0.65)), (0.02, glass(B6, 0.22, 16, 0.45))), 0.5, 0.2, 0.55),
    "ghost": lambda: finish(glass(2950, 0.14, 24, 0.5), 0.45, 0.18, 0.48),
    "icon_btn": lambda: finish(glass(3150, 0.16, 22, 0.6), 0.5, 0.2, 0.55),
    "toggle_on": lambda: finish(mix((0, glass(2800, 0.08, 36)), (0.045, glass(3700, 0.12, 30, 0.8))), 0.45, 0.18, 0.58),
    "toggle_off": lambda: finish(mix((0, glass(3600, 0.08, 36)), (0.045, glass(2600, 0.12, 30, 0.75))), 0.45, 0.18, 0.55),
    "map_open": lambda: finish(mix((0, air(0.4, 2000, 9500, 0.35, 0.55)), (0.18, bell(E6, 0.6, 5.5, 0.5))), 0.8, 0.26, 0.65),
    "bag_open": lambda: finish(mix((0, glass(C6, 0.25, 14, 0.6)), (0.06, glass(G6, 0.35, 11, 0.7))), 0.7, 0.24, 0.65),
    "char_open": lambda: finish(mix((0, glass(E6, 0.28, 13, 0.65)), (0.04, sparkle(0.3, 10, amp=0.45))), 0.7, 0.24, 0.65),
    "music_open": lambda: finish(mix((0, arp([E6, B6, E7], 0.06, 0.9, bell, 0.55)), (0.08, sparkle(0.6, 16, amp=0.5))), 1.0, 0.3, 0.7),
    "music_pick": lambda: finish(mix((0, bell(G6, 0.6, 6.0, 0.6)), (0.05, bell(C7, 0.7, 5.0, 0.5))), 0.8, 0.28, 0.65),
}


def write_ogg(st, path):
    pcm = (np.clip(st, -1, 1) * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        tmp = tf.name
    with wave.open(tmp, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
    os.remove(tmp)


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {"pack": "mystic", "note": "Synthesized from scratch by tools/build_ui_sfx_mystic.py; no samples.", "cues": {}}
    for name, fn in CUES.items():
        st = fn()
        path = os.path.join(OUT, name + ".ogg")
        write_ogg(st, path)
        manifest["cues"][name] = {"seconds": round(len(st) / SR, 3), "sha256": hashlib.sha256(open(path, "rb").read()).hexdigest()}
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    print(len(CUES), "cues ->", OUT)


if __name__ == "__main__":
    main()
