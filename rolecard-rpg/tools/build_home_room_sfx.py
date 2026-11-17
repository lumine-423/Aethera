"""Synthesize the home-room object sounds (2026-11-17), one per object, light and airy.

Every sound is made from scratch with numpy (glass partials, bells, filtered air, sparkles) using the
helpers of build_ui_sfx_mystic.py; no third-party samples. Output: assets/audio/ui/room/*.ogg.
They are pack-independent: data/ui/ui_sounds.json points each room_* cue at its file directly.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_ui_sfx_mystic as M  # noqa: E402

from build_ui_sfx_mystic import (SR, air, arp, bandnoise, bell, env, finish, gliss, glass, mix, note,  # noqa: E402
                                 sparkle, t_axis, write_ogg)

OUT = os.path.join(M.PROJ, "assets", "audio", "ui", "room")
rng = np.random.default_rng(20261117)

E6, A6, B6, C7, E7, G7, A7 = (note(n) for n in (19, 24, 26, 27, 31, 34, 36))
C6, G6, D7 = note(15), note(22), note(29)


def knock(f, d=0.12, amp=1.0):
    """Light wooden tap: two quick-decaying partials plus a click of air."""
    t = t_axis(d)
    y = np.sin(2 * np.pi * f * t) * np.exp(-t * 55) + 0.5 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 80)
    y += bandnoise(d, 2500, 9000) * np.exp(-t * 160) * 0.35
    return amp * y


def crackle(d=0.9, n=26, amp=0.5):
    """Fire crackle: tiny bright pops scattered over time, thinning out."""
    out = np.zeros(int(SR * d))
    for _ in range(n):
        s = int((rng.random() ** 1.7) * d * 0.9 * SR)
        L = int(SR * 0.012)
        pop = bandnoise(0.012, 2500, 12000) * np.exp(-np.arange(L) / SR * 420)
        e = min(len(out), s + L)
        out[s:e] += pop[: e - s] * (0.3 + rng.random() * 0.7)
    return amp * out


def whoosh(d, lo, hi, rise, amp):
    return air(d, lo, hi, rise, amp)


CUES = {
    # hover over any object: a tiny glass breath
    "room_hover": lambda: finish(mix((0, glass(3900, 0.12, 30, 0.45)), (0, air(0.1, 7000, 14000, 0.2, 0.08))), 0.5, 0.2, 0.32),
    # window opens: wind breathes in, light chimes rise
    "room_window_open": lambda: finish(mix((0, whoosh(1.1, 1800, 12000, 0.35, 0.5)),
                                           (0.12, arp([E6, A6, E7, A7], 0.09, 1.3, bell, 0.42)),
                                           (0.2, sparkle(1.2, 30, 4000, 11000, 0.65, True))), 1.5, 0.4, 0.72),
    # window closes: air falls away, soft latch
    "room_window_close": lambda: finish(mix((0, whoosh(0.7, 1800, 10000, 0.15, 0.42)),
                                            (0.08, gliss(E7, A6, 0.5, 0.25, 4)),
                                            (0.55, knock(1500, 0.1, 0.5)), (0.56, glass(C7, 0.3, 14, 0.4))), 1.0, 0.32, 0.66),
    # fireplace flare: a bright "fwoom", crackling sparks, a warm bell underneath
    "room_fire": lambda: finish(mix((0, bandnoise(0.9, 700, 7000) * (np.minimum(t_axis(0.9) / 0.06, 1.0) * np.exp(-t_axis(0.9) * 3.4)) * 0.55),
                                    (0.03, crackle(1.3, 34, 0.55)),
                                    (0.0, gliss(note(10), note(22), 0.5, 0.22, 3, harm=False)),
                                    (0.05, bell(C6, 1.2, 2.6, 0.32)), (0.1, sparkle(0.9, 18, 3000, 9000, 0.5))), 1.2, 0.34, 0.74, 220),
    # star ornament: crystal shimmer climbing up
    "room_star": lambda: finish(mix((0, arp([E7, G7, D7, A7], 0.05, 1.0, glass, 0.55)),
                                    (0.04, sparkle(1.1, 34, 5000, 13000, 0.75, True)),
                                    (0, bell(A6, 1.4, 2.4, 0.25))), 1.5, 0.42, 0.7),
    # gold frame: a fast bright line of light running round
    "room_panel": lambda: finish(mix((0, gliss(C7, A7, 0.7, 0.22, 1.6, harm=False)),
                                     (0, air(0.75, 6000, 14000, 0.6, 0.22)),
                                     (0.65, glass(A7, 0.4, 10, 0.45))), 1.1, 0.36, 0.6),
    # sofa: a soft springy bounce with a puff of fabric air
    "room_sofa": lambda: finish(mix((0, gliss(420, 760, 0.16, 0.6, 9, harm=False)),
                                    (0.13, gliss(640, 900, 0.12, 0.35, 12, harm=False)),
                                    (0, air(0.3, 1500, 7000, 0.15, 0.2)),
                                    (0.06, sparkle(0.5, 10, 4000, 10000, 0.4))), 0.8, 0.26, 0.6, 180),
    # chair: two light wooden taps as it rocks on its legs
    "room_chair": lambda: finish(mix((0, knock(820, 0.14, 0.8)), (0.13, knock(980, 0.12, 0.55)), (0.23, knock(900, 0.1, 0.3))), 0.6, 0.22, 0.6, 240),
    # book: pages flutter, a soft chime
    "room_book": lambda: finish(mix((0, air(0.14, 2500, 11000, 0.3, 0.45)), (0.12, air(0.14, 2800, 12000, 0.3, 0.38)),
                                    (0.24, air(0.16, 3000, 12000, 0.3, 0.3)), (0.1, glass(B6, 0.5, 9, 0.35))), 0.8, 0.26, 0.6),
    # cup: porcelain clink, a smaller echo, faint steam hiss
    "room_cup": lambda: finish(mix((0, glass(2950, 0.5, 9, 0.8)), (0, glass(4420, 0.4, 12, 0.45)),
                                   (0.11, glass(3300, 0.3, 14, 0.35)), (0.1, air(0.8, 5000, 13000, 0.3, 0.12))), 0.9, 0.3, 0.64),
    # table: one wooden tap, then the cup on it rings
    "room_table": lambda: finish(mix((0, knock(700, 0.16, 0.8)), (0.06, glass(2950, 0.4, 11, 0.4)), (0.1, air(0.12, 2500, 11000, 0.3, 0.25))), 0.8, 0.26, 0.62, 220),
    # hide / show UI
    "room_ui_hide": lambda: finish(mix((0, whoosh(0.45, 3000, 13000, 0.3, 0.35)), (0.02, gliss(A7, E7, 0.35, 0.25, 6, harm=False))), 0.8, 0.28, 0.55),
    "room_ui_show": lambda: finish(mix((0, whoosh(0.45, 3000, 13000, 0.6, 0.35)), (0.1, gliss(E7, A7, 0.3, 0.25, 6, harm=False)), (0.2, sparkle(0.4, 10, amp=0.35))), 0.8, 0.28, 0.55),
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for cue, fn in CUES.items():
        st = fn()
        write_ogg(st, os.path.join(OUT, cue + ".ogg"))
        print("%-20s %.2fs" % (cue, len(st) / SR))


if __name__ == "__main__":
    main()
