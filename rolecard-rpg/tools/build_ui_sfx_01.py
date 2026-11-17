"""Build the UI sound kit.
1) "aic" pack: picked AIC reference sounds -> trimmed, faded, loudness-matched mono OGG.
2) "original" pack: every cue synthesized from scratch (numpy), so the game can ship without AIC files.
Writes assets/audio/ui/<pack>/<cue>.ogg and workspaces/frontend-ui/materials/ui-sfx-01/manifest.json.
Usage: python tools/build_ui_sfx_01.py
"""
import hashlib, json, os, shutil, subprocess, tempfile, wave
import numpy as np

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AIC = r"F:\AIC_extract\out"
OUT = os.path.join(PROJ, "assets", "audio", "ui")
REC = os.path.join(PROJ, "workspaces", "frontend-ui", "materials", "ui-sfx-01")
FFMPEG = r"C:\ffmpeg\bin\ffmpeg.exe" if os.path.exists(r"C:\ffmpeg\bin\ffmpeg.exe") else (shutil.which("ffmpeg") or "ffmpeg")
SR = 44100

# cue -> (aic relative path, max seconds kept)
PICKS = {
    "hover": ("ui/25_cursor_gear", 0.08), "focus": ("ui/24_cursor", 0.14), "confirm": ("ui/30_enter_small", 0.2),
    "confirm_big": ("ui/29_enter", 0.55), "back": ("ui/22_cancel", 0.16), "close": ("ui/23_close_ui", 0.26),
    "popup": ("ui/13_quest_popup_1", 0.4), "toast": ("ui/12_quest_popup_0", 0.2), "tab": ("ui/03_book_next", 0.12),
    "deny": ("ui/32_locked", 0.22), "error": ("ui/43_sys_wrong", 0.5), "type": ("ui/44_talk_progress", 0.06),
    "toggle": ("ui/16_quest_tracking", 0.18), "tick": ("ui/46_toggle_button_limit", 0.03), "reset": ("ui/38_reset_var", 0.36),
    "save": ("ui/17_saved_0", 0.5), "reward": ("ui/08_item_get_fanfare", 0.55), "count": ("ui/05_adding_coin", 0.12),
    "recipe": ("ui/35_recipe_drop", 0.3), "ready": ("ui/36_recipe_fullfill", 0.42), "craft": ("ui/37_recipe_success", 0.75),
    "aim": ("ui/33_pr_aim_set", 0.08), "lockon": ("ui/34_pr_lockon", 0.2), "wipe": ("ui/09_map_wa_zoomin", 0.46),
    "slide": ("ui/10_map_wa_zoomout", 0.36), "loaded": ("ui/21_ui_show_currentmap", 0.18), "open_book": ("ui/04_book_open", 0.85),
    "close_book": ("ui/02_book_close", 0.55), "paper": ("ui/11_paper", 0.34), "select": ("mgm_ttr/16_grid_select", 0.2),
    "assign": ("item/02_cane_assign_equip", 0.45), "card": ("mgm_ttr/12_cointoss", 0.18), "start": ("ev_basic/09_memoryback", 0.55),
    "theme": ("ui/26_cursor_gear_reset", 0.42), "expand": ("ui/48_value_assign", 0.28), "collapse": ("ui/45_close_ui", 0.14),
    "send": ("mg_whitearrow/05_mg_whitearrow_shot0", 0.3), "victory": ("minigame/06_mgm_highscore", 2.6),
    "defeat": ("minigame/01_mg_bell_bad", 0.3), "retreat": ("m2d_puzzle/04_door_warp_out", 0.85),
    "battle_enter": ("mgm_ttr/03_attack_prepare_init", 0.95), "turn": ("mgm_ttr/24_ttr_enter", 0.55),
    "round": ("mgm_ttr/23_ttr_countdown", 0.2), "hit": ("magic_basic/55_wheel_hit", 0.14), "hit_heavy": ("mg_whitearrow/01_hit_arrow_enemy", 0.48),
    "hit_ally": ("mgm_ttr/06_attacked_pr", 0.36), "guard": ("magic_basic/07_hit_guard", 0.16), "heal": ("item/18_item_cure", 0.66),
    "slam": ("mgm_ttr/09_bosskilled_hitstop", 0.9), "pop": ("minigame/04_mg_score_add_counter", 0.13), "advance": ("minigame/08_minigame_count", 0.1),
    "delete": ("ui/27_discard_water", 0.6), "unlock": ("m2d_puzzle/26_worpdoor_open", 0.5), "scan": ("magic_basic/43_mana_targetting", 0.08),
    # Dedicated AIC cues & newly expanded UI variety
    "attach": ("item/01_cane_assign_equip", 0.38), "place": ("for_editor/16_tool_lpoint", 0.28),
    "pick": ("for_editor/07_tool_drag_init", 0.16), "detach": ("for_editor/08_tool_drag_quit", 0.16),
    "erase": ("for_editor/09_tool_eraser", 0.35), "ignite": ("ui/28_enhancer_act", 0.65),
    "craft_charge": ("item/12_magicdevice_beat", 0.65), "craft_done": ("item/25_slot_obtain", 0.85),
    "swap": ("for_editor/05_tool_changegear", 0.38), "page": ("mgm_ttr/28_ttr_paper", 0.32),
    "theme_day": ("for_editor/34_toggle_button_open", 0.35), "theme_night": ("m2d_house/15_home_bell_turned_off", 0.55),
    "hover_soft": ("for_editor/15_tool_laysel", 0.08), "hover_card": ("item/03__clock_needle_one", 0.06),
    "chip": ("for_editor/06_tool_chip_select", 0.25), "ghost": ("for_editor/13_tool_hand_init", 0.20),
    "icon_btn": ("for_editor/30_tool_eyescope; tool_submap", 0.22),
    "toggle_on": ("for_editor/34_toggle_button_open", 0.24), "toggle_off": ("for_editor/33_toggle_button_close", 0.20),
    "map_open": ("for_editor/17_tool_mapchange", 0.48), "bag_open": ("m2d/45_itembox_open_0", 0.52),
    "char_open": ("ui/18_ser_init", 0.26), "music_open": ("m2d/62_huurin", 0.65),
    "music_pick": ("minigame/02_mg_bell_good", 0.45),
}

def read_wav(path):
    w = wave.open(path)
    n, sr, ch, sw = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
    dt = {1: np.int8, 2: np.int16, 4: np.int32}[sw]
    a = np.frombuffer(w.readframes(n), dtype=dt).astype(np.float32) / float(2 ** (8 * sw - 1))
    if ch > 1: a = a.reshape(-1, ch).mean(axis=1)
    if sr != SR:
        x = np.linspace(0, len(a) - 1, int(len(a) * SR / sr)); a = np.interp(x, np.arange(len(a)), a).astype(np.float32)
    return a

def shape(a, keep, target_db=-18.0):
    env = np.abs(a); thr = env.max() * 0.03
    idx = np.where(env > thr)[0]
    if len(idx): a = a[max(0, idx[0] - int(SR * 0.002)):]
    a = a[: int(SR * keep)]
    fade = min(len(a) // 3, int(SR * 0.04))
    if fade > 0: a[-fade:] *= np.linspace(1, 0, fade) ** 2
    a[: int(SR * 0.002)] *= np.linspace(0, 1, int(SR * 0.002))
    act = a[np.abs(a) > np.abs(a).max() * 0.05]
    rms = np.sqrt(np.mean(act ** 2)) if len(act) else 1e-6
    a = a * (10 ** (target_db / 20) / max(rms, 1e-6))
    pk = np.abs(a).max()
    if pk > 0.89: a = a * (0.89 / pk)
    return a.astype(np.float32)

def write_ogg(a, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False); tmp.close()
    with wave.open(tmp.name, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes())
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
    os.remove(tmp.name)

# ---------- original synthesis ----------
def t(sec): return np.arange(int(SR * sec)) / SR
def env_ad(n, attack=0.002, decay=0.08):
    x = np.arange(n) / SR
    return np.minimum(1, x / max(attack, 1e-4)) * np.exp(-x / max(decay, 1e-4))
def tone(freq, sec, decay, harm=(1.0, 0.0, 0.0), attack=0.002, glide=0.0):
    x = t(sec); f = freq * (1 + glide * x / sec)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = sum(h * np.sin(ph * (k + 1)) for k, h in enumerate(harm))
    return (s * env_ad(len(x), attack, decay)).astype(np.float32)
def noise(sec, lo, hi, decay, attack=0.002, sweep=0.0):
    n = int(SR * sec); spec = np.fft.rfft(np.random.default_rng(7).standard_normal(n))
    fr = np.fft.rfftfreq(n, 1 / SR); spec[(fr < lo) | (fr > hi)] = 0
    s = np.fft.irfft(spec, n).astype(np.float32); s /= np.abs(s).max() + 1e-9
    e = env_ad(n, attack, decay)
    if sweep: e = np.sin(np.linspace(0, np.pi, n)) ** 1.5
    return s * e
def mix(*parts):
    n = max(len(p) for p in parts); out = np.zeros(n, np.float32)
    for p in parts: out[: len(p)] += p
    return out
def seq(notes, gap, sec=0.35, decay=0.12, harm=(1, 0.35, 0.12)):
    out = np.zeros(int(SR * (gap * len(notes) + sec)), np.float32)
    for i, f in enumerate(notes):
        s = tone(f, sec, decay, harm); o = int(SR * gap * i); out[o:o + len(s)] += s
    return out
N = lambda m: 440.0 * 2 ** ((m - 69) / 12)   # midi -> Hz

def originals():
    glass = (1.0, 0.0, 0.25, 0.0, 0.08)
    return {
        "hover": tone(N(96), 0.05, 0.012, (1, 0, 0.2)) * 0.5, "focus": tone(N(88), 0.08, 0.02, glass),
        "confirm": mix(tone(N(84), 0.16, 0.05, glass), tone(N(91), 0.16, 0.04, glass) * 0.6),
        "confirm_big": mix(seq([N(79), N(86), N(91)], 0.045, 0.4, 0.14, glass), noise(0.3, 3000, 9000, 0.05) * 0.08),
        "back": tone(N(81), 0.14, 0.04, glass, glide=-0.2), "close": mix(tone(N(86), 0.2, 0.05, glass, glide=-0.35), noise(0.2, 2000, 6000, 0.04) * 0.15),
        "popup": seq([N(84), N(91)], 0.05, 0.3, 0.1, glass), "toast": seq([N(91), N(96)], 0.04, 0.2, 0.06, glass),
        "tab": mix(noise(0.08, 2500, 7000, 0.015) * 0.6, tone(N(90), 0.08, 0.02) * 0.4),
        "deny": mix(tone(N(52), 0.18, 0.06, (1, 0.6, 0.3)), tone(N(53), 0.18, 0.06, (1, 0.6, 0.3))) * 0.7,
        "error": seq([N(64), N(58)], 0.09, 0.3, 0.1, (1, 0.5, 0.25)), "type": tone(N(86), 0.04, 0.012, (1, 0.3)) * 0.6,
        "toggle": seq([N(84), N(88)], 0.03, 0.12, 0.04, glass), "tick": noise(0.02, 3000, 9000, 0.004) * 0.7,
        "reset": seq([N(91), N(86), N(79)], 0.04, 0.25, 0.08, glass), "save": seq([N(79), N(84), N(88), N(91)], 0.06, 0.5, 0.18, glass),
        "reward": seq([N(84), N(88), N(91), N(96)], 0.05, 0.5, 0.2, glass), "count": tone(N(98), 0.06, 0.02, glass) * 0.6,
        "recipe": mix(tone(N(72), 0.2, 0.06, (1, 0.5, 0.2)), noise(0.1, 1500, 5000, 0.02) * 0.2),
        "ready": seq([N(86), N(91)], 0.06, 0.35, 0.12, glass), "craft": mix(seq([N(79), N(83), N(86), N(91), N(95)], 0.05, 0.6, 0.22, glass), noise(0.6, 4000, 12000, 0.3, sweep=1) * 0.12),
        "aim": tone(N(93), 0.06, 0.02, glass), "lockon": seq([N(93), N(100)], 0.035, 0.12, 0.04, glass),
        "wipe": noise(0.46, 300, 4000, 0.2, sweep=1) * 0.9, "slide": noise(0.34, 600, 6000, 0.15, sweep=1) * 0.7,
        "loaded": seq([N(88), N(95)], 0.04, 0.2, 0.06, glass), "open_book": noise(0.5, 800, 5000, 0.1, sweep=1) * 0.6,
        "close_book": mix(noise(0.3, 400, 3000, 0.05) * 0.6, tone(N(55), 0.2, 0.05) * 0.4), "paper": noise(0.3, 2000, 9000, 0.08, sweep=1) * 0.6,
        "select": tone(N(89), 0.12, 0.03, glass), "assign": mix(tone(N(67), 0.4, 0.12, (1, 0.4, 0.2)), seq([N(86), N(91)], 0.05, 0.3, 0.1, glass) * 0.7),
        "card": mix(noise(0.12, 2000, 8000, 0.02) * 0.5, tone(N(91), 0.12, 0.03, glass) * 0.6),
        "start": mix(noise(0.55, 400, 6000, 0.3, sweep=1) * 0.5, seq([N(79), N(86), N(91)], 0.08, 0.5, 0.2, glass) * 0.8),
        "theme": tone(N(91), 0.5, 0.16, glass), "expand": mix(tone(N(84), 0.2, 0.06, glass, glide=0.25), noise(0.15, 2000, 7000, 0.03) * 0.2),
        "collapse": tone(N(88), 0.12, 0.04, glass, glide=-0.25), "send": mix(noise(0.3, 1500, 9000, 0.12, sweep=1) * 0.7, tone(N(91), 0.25, 0.08, glass, glide=0.5) * 0.5),
        "victory": seq([N(72), N(76), N(79), N(84), N(88), N(91), N(96)], 0.09, 1.4, 0.5, glass),
        "defeat": seq([N(67), N(63), N(58)], 0.14, 0.5, 0.2, (1, 0.5, 0.2)), "retreat": noise(0.8, 200, 2500, 0.4, sweep=1) * 0.8,
        "battle_enter": mix(noise(0.9, 80, 1500, 0.4, sweep=1), tone(N(43), 0.9, 0.35, (1, 0.5, 0.25)) * 0.6),
        "turn": mix(tone(N(79), 0.5, 0.18, glass), noise(0.4, 2000, 8000, 0.1) * 0.15), "round": tone(N(84), 0.18, 0.06, glass),
        "hit": mix(noise(0.14, 400, 6000, 0.03), tone(N(50), 0.12, 0.04) * 0.6), "hit_heavy": mix(noise(0.45, 150, 5000, 0.12), tone(N(38), 0.4, 0.15, (1, 0.5)) * 0.9),
        "hit_ally": mix(noise(0.3, 300, 4000, 0.06), tone(N(45), 0.3, 0.08) * 0.6), "guard": mix(tone(N(76), 0.16, 0.05, (1, 0.7, 0.5, 0.3)), noise(0.1, 2000, 7000, 0.02) * 0.3),
        "heal": seq([N(84), N(88), N(91), N(96)], 0.07, 0.4, 0.16, glass) * 0.8, "slam": mix(noise(0.6, 60, 2000, 0.2), tone(N(36), 0.6, 0.25, (1, 0.5)) * 0.9),
        "pop": tone(N(93), 0.1, 0.03, glass), "advance": tone(N(84), 0.08, 0.025, glass) * 0.8,
        "delete": noise(0.5, 300, 3000, 0.15, sweep=1), "unlock": seq([N(76), N(83), N(88)], 0.06, 0.4, 0.14, glass), "scan": tone(N(100), 0.06, 0.02, glass) * 0.4,
        "attach": seq([N(81), N(88)], 0.04, 0.18, 0.06, glass), "place": tone(N(79), 0.14, 0.04, glass),
        "pick": tone(N(88), 0.08, 0.02, glass), "detach": tone(N(84), 0.1, 0.03, glass, glide=-0.2),
        "erase": noise(0.25, 1000, 4500, 0.08, sweep=1) * 0.7, "ignite": seq([N(76), N(83), N(88), N(93)], 0.04, 0.35, 0.1, glass),
        "craft_charge": tone(N(72), 0.45, 0.18, glass, glide=0.4), "craft_done": seq([N(79), N(84), N(88), N(96)], 0.05, 0.6, 0.2, glass),
        "swap": seq([N(83), N(88)], 0.05, 0.18, 0.05, glass), "page": mix(noise(0.18, 2200, 8500, 0.05, sweep=1) * 0.55, tone(N(89), 0.12, 0.03, glass) * 0.4),
        "theme_day": seq([N(84), N(91)], 0.045, 0.28, 0.08, glass), "theme_night": seq([N(91), N(83)], 0.055, 0.35, 0.1, glass),
        "hover_soft": tone(N(93), 0.04, 0.01, (1, 0, 0.15)) * 0.45, "hover_card": tone(N(98), 0.04, 0.01, (1, 0, 0.2)) * 0.5,
        "chip": tone(N(88), 0.1, 0.03, glass), "ghost": tone(N(86), 0.08, 0.02, glass) * 0.7,
        "icon_btn": tone(N(91), 0.09, 0.025, glass),
        "toggle_on": seq([N(84), N(89)], 0.03, 0.14, 0.04, glass), "toggle_off": seq([N(89), N(84)], 0.03, 0.14, 0.04, glass),
        "map_open": mix(noise(0.25, 1500, 7000, 0.07, sweep=1) * 0.5, tone(N(86), 0.25, 0.08, glass) * 0.6),
        "bag_open": seq([N(79), N(84)], 0.05, 0.25, 0.08, glass), "char_open": seq([N(84), N(88)], 0.045, 0.22, 0.07, glass),
        "music_open": seq([N(88), N(95), N(100)], 0.05, 0.45, 0.16, glass), "music_pick": seq([N(84), N(91), N(96)], 0.04, 0.3, 0.1, glass),
    }

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f: h.update(f.read())
    return h.hexdigest()

def main():
    os.makedirs(REC, exist_ok=True)
    man = {"_note": "UI sound kit. aic = reference sounds from F:/AIC_extract/out (third-party game; distribution rights NOT confirmed, keep out of public builds until cleared). original = synthesized by tools/build_ui_sfx_01.py, owned by this project.", "aic": {}, "original": {}}
    for cue, (rel, keep) in PICKS.items():
        src = os.path.join(AIC, rel + ".wav")
        a = shape(read_wav(src), keep)
        dst = os.path.join(OUT, "aic", cue + ".ogg"); write_ogg(a, dst)
        man["aic"][cue] = {"source": rel + ".wav", "source_sha256": sha(src), "kept_s": round(len(a) / SR, 3), "file": "res://assets/audio/ui/aic/%s.ogg" % cue}
    for cue, a in originals().items():
        a = shape(a.astype(np.float32), 3.0)
        dst = os.path.join(OUT, "original", cue + ".ogg"); write_ogg(a, dst)
        man["original"][cue] = {"kept_s": round(len(a) / SR, 3), "file": "res://assets/audio/ui/original/%s.ogg" % cue}
    missing = sorted(set(PICKS) ^ set(man["original"]))
    man["cue_mismatch"] = missing
    with open(os.path.join(REC, "manifest.json"), "w", encoding="utf8") as f: json.dump(man, f, ensure_ascii=False, indent=1)
    print("aic", len(man["aic"]), "original", len(man["original"]), "mismatch", missing)

if __name__ == "__main__":
    main()
