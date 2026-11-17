"""Compares what the game really played during the activation (evidence/.../heard_day.wav, recorded
by tools/capture_workshop_activation.gd from the Master bus) with the intended placement of the four
clips (data/workshop/activation_cues.json "sequence"). Prints the lag of each part.
Usage: python tools/check_activation_recording.py
"""
import json
import os
import subprocess

import numpy as np

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 22050
H = 220


def load(p):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", p, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def envl(x):
    m = len(x) // H
    return np.log(np.sqrt((x[:m * H].reshape(m, H) ** 2).mean(1) + 1e-12) + 1e-5)


def main():
    sheet = json.load(open(os.path.join(PROJ, "data", "workshop", "activation_cues.json"), encoding="utf-8"))
    st = sheet["sequence"]["start"]
    d = os.path.join(PROJ, "assets", "audio", "ui", "workshop_activation")
    clips = {r: load(os.path.join(d, "activate_%s.ogg" % r)) for r in st}
    n = int(max(st[r] * SR + len(clips[r]) for r in st)) + SR
    exp = np.zeros(n)
    for r in st:
        s = int(st[r] * SR)
        exp[s:s + len(clips[r])] += clips[r]
    rec = load(os.path.join(PROJ, "evidence", "workshop-activation-20261117", "heard_day.wav"))
    E, R = envl(exp), envl(rec)
    fs = SR / H
    print("recorded %.2fs, intended %.2fs" % (len(rec) / SR, n / SR - 1))
    A0, T = st["loop_a"], st["done"]
    for name, t0, t1 in [("1", 0.05, A0 - 0.3), ("2+3", A0 + 0.2, A0 + 5.0), ("2 alone", A0 + 5.6, T - 0.2), ("4", T + 0.02, T + 3.5)]:
        e = E[int(t0 * fs):int(t1 * fs)]; e = e - e.mean()
        best = (0, -2)
        for L in range(-int(fs), int(fs)):
            s = int(t0 * fs) + L
            if s < 0 or s + len(e) > len(R): continue
            r = R[s:s + len(e)]; r = r - r.mean()
            v = (e * r).sum() / np.sqrt((e * e).sum() * (r * r).sum() + 1e-9)
            if v > best[1]: best = (L / fs, v)
        print("%-8s lag %+4.0f ms  match %.2f" % (name, best[0] * 1000, best[1]))


if __name__ == "__main__":
    main()
