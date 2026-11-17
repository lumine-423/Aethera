"""Workshop (刻印工坊) activation: music cue sheet (2026-11-17).

Reads the four activation clips the user picked (assets/audio/ui/workshop_activation/
activate_click / activate_loop_a / activate_loop_b / activate_done .ogg, played in that order)
and writes data/workshop/activation_cues.json: per clip its length, a 30 Hz loudness curve (0..1),
onset times (hits), the loudest moment and the "release" (where a build-up cuts off).
The Godot activation animation is timed from this sheet, so it stays locked to the music.
No sounds are made here: by user rule the four clips are the only sound of the ceremony.
Usage: python tools/build_workshop_activation.py
"""
import json
import os
import subprocess
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_ui_sfx_mystic as M  # noqa: E402

CLIPS = os.path.join(M.PROJ, "assets", "audio", "ui", "workshop_activation")
CUES_OUT = os.path.join(M.PROJ, "data", "workshop", "activation_cues.json")
ASR = 22050
FPS = 30


def load(path):
    raw = subprocess.run([M.FFMPEG, "-v", "quiet", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(ASR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def analyse(x):
    hop = ASR // FPS
    n = len(x) // hop
    rms = np.array([np.sqrt(np.mean(x[i * hop:(i + 1) * hop] ** 2) + 1e-12) for i in range(n)])
    db = 20 * np.log10(rms + 1e-9)
    top = db.max()
    env = np.clip((db - (top - 36.0)) / 36.0, 0.0, 1.0)          # 36 dB window -> 0..1
    env = np.convolve(env, np.ones(3) / 3, mode="same")
    # onsets: positive spectral flux peaks
    N, h = 1024, 256
    win = np.hanning(N)
    S = np.array([np.abs(np.fft.rfft(x[i:i + N] * win)) for i in range(0, len(x) - N, h)])
    flux = np.maximum(np.diff(np.log1p(S * 10), axis=0), 0).sum(1)
    thr = np.median(flux) + 2.0 * np.std(flux)
    onsets = []
    for i in range(1, len(flux) - 1):
        if flux[i] > thr and flux[i] >= flux[i - 1] and flux[i] >= flux[i + 1]:
            t = (i + 1) * h / ASR
            if not onsets or t - onsets[-1] > 0.11:
                onsets.append(round(t, 3))
    peak = float(np.argmax(db)) / FPS
    # release: first moment after the peak where loudness falls 8 dB below it (build-up cut-off);
    # clips that never fall release at their end
    rel = len(x) / ASR
    pi = int(np.argmax(db))
    for i in range(pi, n):
        if db[i] < db[pi] - 8.0:
            rel = i / FPS
            break
    # seal: the moment the animation stamps the sigil. A build-up that is still loud at its very end
    # (cut off) seals on its last sample; one that climaxes and dies away seals on the hit nearest its peak.
    if env[-6:].mean() > 0.7:
        seal = len(x) / ASR - 0.02
    else:
        seal = min(onsets, key=lambda t: abs(t - peak)) if onsets else peak
    return {"duration": round(len(x) / ASR, 3), "fps": FPS, "env": [round(float(v), 3) for v in env],
            "onsets": onsets, "peak": round(peak, 3), "release": round(rel, 3), "seal": round(seal, 3)}


def cue_sheet():
    out = {"_note": "Built by tools/build_workshop_activation.py from the activation clips. env = loudness 0..1 at fps; "
                    "onsets = hits (s); release = where the build-up cuts off (s). The activation animation is timed from this.",
           "clips": {}}
    for role in ("click", "loop_a", "loop_b", "done"):
        out["clips"][role] = analyse(load(os.path.join(CLIPS, "activate_%s.ogg" % role)))
        c = out["clips"][role]
        print("%-7s dur %.2fs  peak %.2fs  release %.2fs  seal %.2fs  onsets %s" % (role, c["duration"], c["peak"], c["release"], c["seal"], c["onsets"]))
    os.makedirs(os.path.dirname(CUES_OUT), exist_ok=True)
    with open(CUES_OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)


SEQ_OUT = os.path.join(CLIPS, "activate_sequence.ogg")
## settings exported from the mixer page (start seconds and dB per clip); optional
MIX_IN = os.path.join(M.PROJ, "data", "workshop", "activation_mix.json")
MIXER_DIR = os.path.join(M.PROJ, "workspaces", "frontend-ui", "materials", "workshop-activation-20261117")


def load_st(path, sr=44100):
    raw = subprocess.run([M.FFMPEG, "-v", "quiet", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(sr), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def sequence():
    """The user's layout, sample-exact, as one file: 1 click, then 2 loop_a + 3 loop_b together from
    the end of 1, then 4 done from the end of the longer of 2 / 3. Nothing is added or changed; the
    clips are only placed. One stream gives the game an exact clock and no gaps between parts."""
    sr = 44100
    roles = ("click", "loop_a", "loop_b", "done")
    clip = {r: load_st(os.path.join(CLIPS, "activate_%s.ogg" % r), sr) for r in roles}
    # default = the user's layout; the mixer page (activation_mixer.html) exports MIX_IN to override
    a0 = len(clip["click"]) / sr
    starts = {"click": 0.0, "loop_a": a0, "loop_b": a0, "done": a0 + max(len(clip["loop_a"]), len(clip["loop_b"])) / sr}
    gains = {r: 0.0 for r in roles}
    if os.path.exists(MIX_IN):
        with open(MIX_IN, encoding="utf-8") as f:
            mix_cfg = json.load(f)
        for r in roles:
            if r in mix_cfg.get("starts", {}): starts[r] = max(0.0, float(mix_cfg["starts"][r]))
            if r in mix_cfg.get("gain_db", {}): gains[r] = float(mix_cfg["gain_db"][r])
        print("mix settings from", MIX_IN)
    first = min(starts.values())
    starts = {r: v - first for r, v in starts.items()}       # the mix always begins with its first clip
    n = max(int(round(starts[r] * sr)) + len(clip[r]) for r in roles)
    out = np.zeros((n, 2))
    for r in roles:
        s = int(round(starts[r] * sr))
        out[s:s + len(clip[r])] += clip[r] * (10 ** (gains[r] / 20.0))
    peak = float(np.max(np.abs(out)))
    gain = 0.98 / peak if peak > 0.98 else 1.0     # overlapping clips may clip: scale the whole mix down evenly
    out *= gain
    pcm = (np.clip(out, -1, 1) * 32767).astype("<i2")
    subprocess.run([M.FFMPEG, "-v", "quiet", "-y", "-f", "s16le", "-ar", str(sr), "-ac", "2", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", "6", SEQ_OUT], input=pcm.tobytes(), check=True)
    info = {"file": "res://assets/audio/ui/workshop_activation/activate_sequence.ogg",
            "start": {r: round(starts[r], 4) for r in roles}, "gain_db": gains,
            "length": round(n / sr, 4), "master_gain": round(gain, 4)}
    print("sequence %.2fs  starts %s  gains %s  master %.3f" % (info["length"], info["start"], gains, gain))
    with open(CUES_OUT, encoding="utf-8") as f:
        sheet = json.load(f)
    sheet["sequence"] = info
    with open(CUES_OUT, "w", encoding="utf-8") as f:
        json.dump(sheet, f, ensure_ascii=False, indent=1)


def mixer_page():
    """Writes a self-contained mixer page (the 4 clips embedded, opens by double-click, no server)
    so the user can place / balance the clips by ear and export activation_mix.json."""
    import base64
    with open(CUES_OUT, encoding="utf-8") as f:
        sheet = json.load(f)
    clips = {}
    for r in ("click", "loop_a", "loop_b", "done"):
        with open(os.path.join(CLIPS, "activate_%s.ogg" % r), "rb") as f:
            data = base64.b64encode(f.read()).decode("ascii")
        c = sheet["clips"][r]
        clips[r] = {"b64": data, "onsets": c["onsets"], "peak": c["peak"], "duration": c["duration"]}
    seq = sheet.get("sequence", {})
    payload = {"clips": clips, "start": seq.get("start", {}), "gain_db": seq.get("gain_db", {})}
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "activation_mixer_template.html"), encoding="utf-8") as f:
        html = f.read()
    html = html.replace("/*__DATA__*/null", json.dumps(payload, ensure_ascii=False))
    os.makedirs(MIXER_DIR, exist_ok=True)
    out = os.path.join(MIXER_DIR, "activation_mixer.html")
    with open(out, "w", encoding="utf-8") as f:
        f.write(html)
    print("mixer page", out, "%.0f KB" % (len(html) / 1024))


if __name__ == "__main__":
    cue_sheet()
    sequence()
    mixer_page()
