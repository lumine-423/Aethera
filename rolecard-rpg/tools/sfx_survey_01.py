"""Survey candidate UI sounds: loudness, brightness, attack, tail, plus a spectrogram sheet per group.
Usage: python sfx_survey_01.py <out_dir>
The script cannot "listen"; it gives measurable traits so picks are not blind.
"""
import json, os, sys, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = r"F:\AIC_extract\out"
GROUPS = {
    "ui": ["ui/24_cursor", "ui/25_cursor_gear", "ui/30_enter_small", "ui/29_enter", "ui/22_cancel", "ui/23_close_ui",
           "ui/45_close_ui", "ui/12_quest_popup_0", "ui/13_quest_popup_1", "ui/03_book_next", "ui/04_book_open", "ui/02_book_close",
           "ui/11_paper", "ui/32_locked", "ui/43_sys_wrong", "ui/44_talk_progress", "ui/46_toggle_button_limit", "ui/48_value_assign",
           "ui/16_quest_tracking", "ui/14_quest_track_completed", "ui/17_saved_0", "ui/39_saved", "ui/05_adding_coin",
           "ui/07_item_get_fanfare", "ui/08_item_get_fanfare", "ui/35_recipe_drop", "ui/36_recipe_fullfill", "ui/37_recipe_success",
           "ui/33_pr_aim_set", "ui/34_pr_lockon", "ui/21_ui_show_currentmap", "ui/09_map_wa_zoomin", "ui/10_map_wa_zoomout",
           "ui/38_reset_var", "ui/26_cursor_gear_reset", "ui/40_store_cart_in", "ui/42_store_checkout", "ui/18_ser_init"],
    "game": ["minigame/02_mg_bell_good", "minigame/03_mg_bell_great", "minigame/01_mg_bell_bad", "minigame/04_mg_score_add_counter",
             "minigame/08_minigame_count", "minigame/06_mgm_highscore", "minigame/05_mgm_applause", "minigame/10_minigame_init",
             "mgm_ttr/16_grid_select", "mgm_ttr/24_ttr_enter", "mgm_ttr/21_ttr_cancel", "mgm_ttr/29_ttr_rank_updated",
             "mgm_ttr/12_cointoss", "mgm_ttr/02_alignment", "mgm_ttr/09_bosskilled_hitstop", "mgm_ttr/23_ttr_countdown",
             "ev_basic/05_ping", "ev_basic/06_puni", "ev_basic/07_small_hit", "ev_basic/09_memoryback", "ev_basic/01_flashback_noise",
             "item/10_slot_decided", "item/09_getitem_mbox", "item/26_slot_stop", "item/01_cane_assign_equip", "item/02_cane_assign_equip",
             "item/03__clock_needle_one", "item/12_magicdevice_beat", "item/18_item_cure", "item/11_item_cure_mp", "item/25_slot_obtain"],
    "battle": ["magic_basic/07_hit_guard", "magic_basic/08_hit_parry", "magic_basic/09_hit_shield_attack", "magic_basic/46_shield_activate",
               "magic_basic/47_shield_appear", "magic_basic/43_mana_targetting", "magic_basic/36_magic_erase", "magic_basic/51_swing_wheel",
               "magic_basic/55_wheel_hit", "magic_basic/04_frozenbullet_hit", "magic_basic/41_magic_thunder_explode_s; thunderball_explode",
               "magic_basic/29_magic_casting_pr", "magic_basic/31_magic_casting_pr_o0", "magic_basic/19_mag_overcharge_use_0",
               "mg_whitearrow/01_hit_arrow_enemy", "mg_whitearrow/05_mg_whitearrow_shot0", "mg_whitearrow/03_mg_whitearrow_appear",
               "mg_watershard/03_mgwater_shot", "mg_pr_burst/05_pr_burst_charge", "mg_pr_burst/04_pr_burst",
               "mgm_ttr/05_attacked_en", "mgm_ttr/06_attacked_pr", "mgm_ttr/03_attack_prepare_init", "mgm_ttr/11_charged_pr",
               "m2d_puzzle/01_checkpoint_registered", "m2d_puzzle/03_door_warp", "m2d_puzzle/04_door_warp_out", "m2d_puzzle/26_worpdoor_open",
               "m2d_puzzle/25_worpdoor_close", "m2d_puzzle/15_puzz_foot_switch_on", "m2d_puzzle/14_puzz_foot_switch_off", "m2d_puzzle/20_steel_door_open"],
}

def load(rel):
    p = os.path.join(ROOT, rel + ".wav")
    w = wave.open(p)
    n, sr, ch, sw = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
    raw = w.readframes(n)
    dt = {1: np.int8, 2: np.int16, 4: np.int32}[sw]
    a = np.frombuffer(raw, dtype=dt).astype(np.float32) / float(2 ** (8 * sw - 1))
    if ch > 1: a = a.reshape(-1, ch).mean(axis=1)
    return a, sr

def traits(a, sr):
    peak = float(np.max(np.abs(a)) + 1e-9)
    env = np.abs(a)
    win = max(1, sr // 200)
    env = np.convolve(env, np.ones(win) / win, mode="same")
    i_peak = int(np.argmax(env))
    above = np.where(env > peak * 0.05)[0]
    start = int(above[0]) if len(above) else 0
    end = int(above[-1]) if len(above) else len(a)
    spec = np.abs(np.fft.rfft(a[start:end] if end > start else a))
    freqs = np.fft.rfftfreq(len(a[start:end]) if end > start else len(a), 1 / sr)
    centroid = float((spec * freqs).sum() / (spec.sum() + 1e-9))
    rms = float(np.sqrt(np.mean(a[start:end] ** 2)) if end > start else 0.0)
    return {"dur": round(len(a) / sr, 3), "sound_dur": round((end - start) / sr, 3), "lead_silence": round(start / sr, 3),
            "attack_ms": round((i_peak - start) / sr * 1000, 1), "peak_db": round(20 * np.log10(peak), 1),
            "rms_db": round(20 * np.log10(rms + 1e-9), 1), "brightness_hz": int(centroid)}

def spectro(a, sr, w=300, h=90):
    n = 512; hop = max(64, len(a) // w)
    frames = [a[i:i + n] * np.hanning(min(n, len(a) - i)) for i in range(0, max(1, len(a) - n), hop)]
    if not frames: frames = [a]
    m = np.array([np.abs(np.fft.rfft(f, n))[: n // 2] for f in frames]).T
    m = 20 * np.log10(m + 1e-6); m = np.clip((m + 60) / 60, 0, 1)
    img = Image.fromarray((255 * (1 - m[::-1])).astype(np.uint8)).resize((w, h))
    return img

def main(out):
    os.makedirs(out, exist_ok=True)
    report = {}
    font = ImageFont.load_default()
    for g, items in GROUPS.items():
        cols = 4; tile = (320, 120)
        rows = (len(items) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * tile[0], rows * tile[1]), "white")
        d = ImageDraw.Draw(sheet)
        for i, rel in enumerate(items):
            try:
                a, sr = load(rel)
            except Exception as e:
                report[rel] = {"error": str(e)}; continue
            t = traits(a, sr); report[rel] = t
            x, y = (i % cols) * tile[0], (i // cols) * tile[1]
            sheet.paste(spectro(a, sr), (x + 10, y + 24))
            d.text((x + 10, y + 4), "%d %s" % (i, rel.split("/")[-1][:34]), fill="black", font=font)
            d.text((x + 10, y + 108), "%.2fs  %ddB  %dHz  atk%dms" % (t["sound_dur"], t["rms_db"], t["brightness_hz"], t["attack_ms"]), fill="#c00", font=font)
        sheet.save(os.path.join(out, "survey-%s.png" % g))
    with open(os.path.join(out, "survey.json"), "w", encoding="utf8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    print("ok", len(report))

if __name__ == "__main__":
    main(sys.argv[1])
