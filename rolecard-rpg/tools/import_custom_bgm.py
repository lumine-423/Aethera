"""Transcode, loudness-normalize (-16 LUFS), trim workshop cues, and import custom BGM.

Reads:
  rolecard-rpg/workspaces/frontend-ui/materials/bgm-matcher-inbox/bgm_assignments.json
  rolecard-rpg/data/content/music_manifest.json (preserves all 14 orig-* tracks)

Outputs:
  rolecard-rpg/assets/audio/bgm/custom/*.ogg       (36 active + 1 reserved Crystar)
  rolecard-rpg/assets/audio/ui/workshop_activation/*.ogg (trimmed 03/04/05/06)
  rolecard-rpg/data/content/music_manifest.json    (format aethera-music/3)
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

TOOLS_DIR = Path(__file__).resolve().parent
ROLECARD_DIR = TOOLS_DIR.parent
REPO_ROOT = ROLECARD_DIR.parent
INBOX_DIR = ROLECARD_DIR / "workspaces" / "frontend-ui" / "materials" / "bgm-matcher-inbox"
INBOX_FILES_DIR = INBOX_DIR / "files"
ASSIGNMENTS_PATH = INBOX_DIR / "bgm_assignments.json"
MANIFEST_PATH = ROLECARD_DIR / "data" / "content" / "music_manifest.json"
CUSTOM_BGM_DIR = ROLECARD_DIR / "assets" / "audio" / "bgm" / "custom"
WORKSHOP_ACT_DIR = ROLECARD_DIR / "assets" / "audio" / "ui" / "workshop_activation"

FFMPEG = (
    r"C:\ffmpeg\bin\ffmpeg.exe"
    if Path(r"C:\ffmpeg\bin\ffmpeg.exe").is_file()
    else (shutil.which("ffmpeg") or "ffmpeg")
)
FFPROBE = (
    r"C:\ffmpeg\bin\ffprobe.exe"
    if Path(r"C:\ffmpeg\bin\ffprobe.exe").is_file()
    else (shutil.which("ffprobe") or "ffprobe")
)

CREATION_FLAGS = getattr(subprocess, "CREATE_NO_WINDOW", 0)

# Canonical import specs keyed by inbox file_id (SHA-256[:10] -> metadata).
# Titles intentionally omit artist prefixes per user instruction.
CUSTOM_BGM_SPECS: list[dict] = [
    # --- UI & Home / Workshop ---
    {
        "file_id": "trk_a4827916b6",
        "id": "cust-ui01-opening",
        "slug": "crystar",
        "title": "Crystar",
        "original_title": "Crystar",
        "artist": "削除",
        "role": "开场手书预留曲（UI-01，交由后续完整开场动画合片接入）",
        "category": "reserved",
        "slots": ["UI-01"],
        "aliases": ["削除 - Crystar"],
    },
    {
        "file_id": "trk_c46b8ba094",
        "id": "cust-ui03-day",
        "slug": "ui03_home_day",
        "title": "白昼天晴",
        "original_title": "白昼天晴 单曲版",
        "artist": "",
        "role": "室内交互主页 · 白昼模式（UI-03）",
        "category": "ui",
        "slots": ["UI-03"],
        "aliases": ["白昼天晴 单曲版"],
    },
    {
        "file_id": "trk_cf6ad8d6d6",
        "id": "cust-ui03-night",
        "slug": "ui03_home_night",
        "title": "温柔夜色",
        "original_title": "温柔夜色 单曲版",
        "artist": "",
        "role": "室内交互主页 · 夜间模式（UI-03）",
        "category": "ui",
        "slots": ["UI-03"],
        "aliases": ["温柔夜色 单曲版"],
    },
    {
        "file_id": "trk_7bed0e8ec0",
        "id": "cust-ui04-workshop",
        "slug": "ui04_workshop_idle",
        "title": "人工梦游",
        "original_title": "人工梦游",
        "artist": "The 1999",
        "role": "刻印工坊 · 常驻思考背景曲（UI-04）",
        "category": "ui",
        "slots": ["UI-04"],
        "aliases": ["The 1999 - 人工梦游"],
    },
    # --- Factions / Countries (FAC-01..FAC-08) ---
    {
        "file_id": "trk_a96ca6eb20",
        "id": "cust-fac01",
        "slug": "fac01_sereth",
        "title": "にぎやかな街",
        "original_title": "にぎやかな街",
        "artist": "高梨康治",
        "role": "塞蕾特公国 · 势力主曲（FAC-01）",
        "category": "world",
        "slots": ["FAC-01"],
        "aliases": ["高梨康治 - にぎやかな街"],
    },
    {
        "file_id": "trk_be10b95c85",
        "id": "cust-fac02",
        "slug": "fac02_longyuan",
        "title": "紫禁城里的端庄猫",
        "original_title": "紫禁城里的端庄猫",
        "artist": "花飞飞",
        "role": "龙渊帝国 · 势力主曲（FAC-02）",
        "category": "world",
        "slots": ["FAC-02"],
        "aliases": ["花飞飞 - 紫禁城里的端庄猫"],
    },
    {
        "file_id": "trk_370cda4584",
        "id": "cust-fac03",
        "slug": "fac03_gotavia",
        "title": "Old Marple",
        "original_title": "Old Marple",
        "artist": "Francis Goya",
        "role": "哥塔薇亚帝国 · 势力主曲（FAC-03）",
        "category": "world",
        "slots": ["FAC-03"],
        "aliases": ["Francis Goya - Old Marple"],
    },
    {
        "file_id": "trk_545ef50f2e",
        "id": "cust-fac04",
        "slug": "fac04_akitsu",
        "title": "神狐的祝福",
        "original_title": "神狐的祝福 Hakushin's Lullaby",
        "artist": "陈致逸 / HOYO-MiX",
        "role": "秋津国 · 势力主曲（FAC-04）",
        "category": "world",
        "slots": ["FAC-04"],
        "aliases": ["Hakushin's Lullaby", "神狐的祝福 Hakushin's Lullaby"],
    },
    {
        "file_id": "trk_d7e86d9f3e",
        "id": "cust-fac05",
        "slug": "fac05_jwanshakti",
        "title": "The Mountain",
        "original_title": "The Mountain",
        "artist": "Chinmaya Dunster",
        "role": "吉万沙克蒂 · 势力主曲（FAC-05）",
        "category": "world",
        "slots": ["FAC-05"],
        "aliases": ["Chinmaya Dunster - The Mountain"],
    },
    {
        "file_id": "trk_03a9d36c6b",
        "id": "cust-fac06",
        "slug": "fac06_gloria",
        "title": "Rome",
        "original_title": "Rome (The Medieval Era)",
        "artist": "Roland Rizzo",
        "role": "格洛里亚 · 势力主曲（FAC-06）",
        "category": "world",
        "slots": ["FAC-06"],
        "aliases": ["Rome (The Medieval Era)", "Roland Rizzo - Rome (The Medieval Era)"],
    },
    {
        "file_id": "trk_1f52f1517e",
        "id": "cust-fac07",
        "slug": "fac07_omanut",
        "title": "Santa Lucia",
        "original_title": "Santa Lucia (Romance In Venice Album Version)",
        "artist": "Jack Jezzro",
        "role": "奥马努特 · 势力主曲（FAC-07）",
        "category": "world",
        "slots": ["FAC-07"],
        "aliases": ["Santa Lucia (Romance In Venice Album Version)"],
    },
    {
        "file_id": "trk_eb142ad6eb",
        "id": "cust-fac08",
        "slug": "fac08_serpent_staff",
        "title": "L",
        "original_title": "Ｌ",
        "artist": "タニウチヒデキ",
        "role": "蛇杖 · 跨国禁忌组织（FAC-08）",
        "category": "world",
        "slots": ["FAC-08"],
        "aliases": ["Ｌ", "タニウチヒデキ - Ｌ"],
    },
    # --- Specific Locations (LOC-01, 03..16; LOC-02 uses orig Windborne Hymn) ---
    {
        "file_id": "trk_c96cb901bd",
        "id": "cust-loc01",
        "slug": "loc01_academy",
        "title": "誠に遺憾ながら、知り合い",
        "original_title": "誠に遺憾ながら、知り合い",
        "artist": "高橋邦幸",
        "role": "塞蕾特·中央学院（LOC-01） / 日常治愈轮换（CHAR-01）",
        "category": "world",
        "slots": ["LOC-01", "CHAR-01"],
        "aliases": ["高橋邦幸 - 誠に遺憾ながら、知り合い"],
    },
    {
        "file_id": "trk_294b4ff2e2",
        "id": "cust-loc03-a",
        "slug": "loc03_nidhogg_respite",
        "title": "Old City ~ Respite",
        "original_title": "Old City ~ Respite",
        "artist": "Mili",
        "role": "塞蕾特·尼德霍格区（首选，LOC-03）",
        "category": "world",
        "slots": ["LOC-03"],
        "aliases": ["Old City Respite", "Mili - Old City ~ Respite"],
    },
    {
        "file_id": "trk_c7cec70f01",
        "id": "cust-loc03-b",
        "slug": "loc03_nidhogg_market",
        "title": "Old City Market",
        "original_title": "Old City Market",
        "artist": "Mili",
        "role": "塞蕾特·尼德霍格区集市/暗巷（LOC-03）",
        "category": "world",
        "slots": ["LOC-03"],
        "aliases": ["Mili - Old City Market"],
    },
    {
        "file_id": "trk_16c297f725",
        "id": "cust-loc04",
        "slug": "loc04_zichen",
        "title": "北国的宝库",
        "original_title": "北国的宝库 Treasury From the Northland",
        "artist": "陈致逸 / HOYO-MiX",
        "role": "龙渊·紫宸宫（LOC-04）",
        "category": "world",
        "slots": ["LOC-04"],
        "aliases": ["Treasury From the Northland", "北国的宝库 Treasury From the Northland"],
    },
    {
        "file_id": "trk_121829098c",
        "id": "cust-loc05",
        "slug": "loc05_lingshan",
        "title": "倦飞之鸟",
        "original_title": "倦飞之鸟 Wandering Flight",
        "artist": "陈致逸 / HOYO-MiX",
        "role": "龙渊·灵山（LOC-05）",
        "category": "world",
        "slots": ["LOC-05"],
        "aliases": ["Wandering Flight", "倦飞之鸟 Wandering Flight"],
    },
    {
        "file_id": "trk_954a5f243b",
        "id": "cust-loc06",
        "slug": "loc06_kitezh",
        "title": "Song for Alexandra",
        "original_title": "Song for Alexandra",
        "artist": "Francis Goya",
        "role": "哥塔薇亚·基捷日（LOC-06）",
        "category": "world",
        "slots": ["LOC-06"],
        "aliases": ["Francis Goya - Song for Alexandra"],
    },
    {
        "file_id": "trk_8218acbfd4",
        "id": "cust-loc07",
        "slug": "loc07_alatyr",
        "title": "Beloved Forest",
        "original_title": "Beloved Forest",
        "artist": "Francis Goya",
        "role": "哥塔薇亚·阿拉提尔（LOC-07）",
        "category": "world",
        "slots": ["LOC-07"],
        "aliases": ["Francis Goya - Beloved Forest"],
    },
    {
        "file_id": "trk_f9f2f0f6ba",
        "id": "cust-loc08",
        "slug": "loc08_sumeru_court",
        "title": "葳蕤林野间",
        "original_title": "葳蕤林野间 Village Surrounded by Green",
        "artist": "HOYO-MiX",
        "role": "吉万沙克蒂·须弥王庭（LOC-08）",
        "category": "world",
        "slots": ["LOC-08"],
        "aliases": ["Village Surrounded by Green", "葳蕤林野间 Village Surrounded by Green"],
    },
    {
        "file_id": "trk_fcb46204c0",
        "id": "cust-loc09",
        "slug": "loc09_skanda_fort",
        "title": "灼燃的残光",
        "original_title": "灼燃的残光 Smoldering Glow",
        "artist": "HOYO-MiX",
        "role": "吉万沙克蒂·塞建陀砦（LOC-09）",
        "category": "world",
        "slots": ["LOC-09"],
        "aliases": ["Smoldering Glow", "灼燃的残光 Smoldering Glow"],
    },
    {
        "file_id": "trk_204c8c3948",
        "id": "cust-loc10",
        "slug": "loc10_typhon",
        "title": "嵾峨之冠",
        "original_title": "嵾峨之冠 Skyfire Circlet",
        "artist": "HOYO-MiX",
        "role": "格洛里亚·堤丰之喉（LOC-10）",
        "category": "world",
        "slots": ["LOC-10"],
        "aliases": ["Skyfire Circlet", "嵾峨之冠 Skyfire Circlet"],
    },
    {
        "file_id": "trk_53b7989989",
        "id": "cust-loc11",
        "slug": "loc11_curia",
        "title": "边地的守望者",
        "original_title": "边地的守望者 The Watcher by the Edge",
        "artist": "HOYO-MiX",
        "role": "格洛里亚·库利亚（LOC-11）",
        "category": "world",
        "slots": ["LOC-11"],
        "aliases": ["The Watcher by the Edge", "边地的守望者 The Watcher by the Edge"],
    },
    {
        "file_id": "trk_970b075c42",
        "id": "cust-loc12",
        "slug": "loc12_kumosakura",
        "title": "恒静之梦",
        "original_title": "恒静之梦 Blue Dream",
        "artist": "陈致逸 / HOYO-MiX",
        "role": "秋津国·云樱（LOC-12）",
        "category": "world",
        "slots": ["LOC-12"],
        "aliases": ["Blue Dream", "恒静之梦 Blue Dream"],
    },
    {
        "file_id": "trk_58b030bf34",
        "id": "cust-loc13",
        "slug": "loc13_black_market",
        "title": "The Witch's Breath",
        "original_title": "The Witch's Breath",
        "artist": "Binary Haze Interactive / Mili",
        "role": "奥马努特·地下市场（LOC-13）",
        "category": "world",
        "slots": ["LOC-13"],
        "aliases": ["Binary Haze Interactive,Mili - The Witch's Breath"],
    },
    {
        "file_id": "trk_a48856227c",
        "id": "cust-loc14",
        "slug": "loc14_zihad_desert",
        "title": "孤客之旅",
        "original_title": "孤客之旅 Lonesome Road",
        "artist": "HOYO-MiX",
        "role": "奥马努特西·齐哈特大沙漠（LOC-14）",
        "category": "world",
        "slots": ["LOC-14"],
        "aliases": ["Lonesome Road", "孤客之旅 Lonesome Road"],
    },
    {
        "file_id": "trk_75d2effa6c",
        "id": "cust-loc15",
        "slug": "loc15_brahma_forest",
        "title": "远行的思愿",
        "original_title": "远行的思愿 Distant Yearning",
        "artist": "HOYO-MiX",
        "role": "吉万沙克蒂深处·梵音林（LOC-15）",
        "category": "world",
        "slots": ["LOC-15"],
        "aliases": ["Distant Yearning", "远行的思愿 Distant Yearning"],
    },
    {
        "file_id": "trk_4d498c3f3f",
        "id": "cust-loc16",
        "slug": "loc16_heaven_island",
        "title": "瑞尼尔雪山的丧钟",
        "original_title": "瑞尼尔雪山的丧钟",
        "artist": "The 1999",
        "role": "塞蕾特海域·天国岛（LOC-16）",
        "category": "world",
        "slots": ["LOC-16"],
        "aliases": ["The 1999 - 瑞尼尔雪山的丧钟"],
    },
    # --- Singularity Bosses (BOSS-03, BOSS-04; BOSS-01/02 use orig Combat Beneath the Waves) ---
    {
        "file_id": "trk_64c7667d8b",
        "id": "cust-boss03",
        "slug": "boss03_sarabha",
        "title": "Orby",
        "original_title": "Orby",
        "artist": "Cosmo Sheldrake / Andrea Vargas",
        "role": "远古神兽试炼 · 舍罗婆（BOSS-03）",
        "category": "story",
        "slots": ["BOSS-03"],
        "aliases": ["Cosmo Sheldrake,Andrea Vargas - Orby"],
    },
    {
        "file_id": "trk_566fb3db89",
        "id": "cust-boss04",
        "slug": "boss04_apocalypse",
        "title": "蚀形的灾祲",
        "original_title": "蚀形的灾祲 Vitas Corrodens Pestis",
        "artist": "HOYO-MiX",
        "role": "熔岩巨人与狂龙天灾决战 · 苏尔特尔/赤龙（BOSS-04）",
        "category": "story",
        "slots": ["BOSS-04"],
        "aliases": ["Vitas Corrodens Pestis", "蚀形的灾祲 Vitas Corrodens Pestis"],
    },
    # --- Character & Mood Tracks (CHAR-01, CHAR-03, CHAR-04, CHAR-05) ---
    {
        "file_id": "trk_2b3ba185b9",
        "id": "cust-char01-a",
        "slug": "char01_daily_monaca",
        "title": "いつもの風景から始まる物語",
        "original_title": "いつもの風景から始まる物語",
        "artist": "神前暁 / 髙田龍一（MONACA)",
        "role": "日常治愈 · 下午茶/闲聊首选（CHAR-01）",
        "category": "story",
        "slots": ["CHAR-01"],
        "aliases": ["神前暁,髙田龍一（MONACA) - いつもの風景から始まる物語"],
    },
    {
        "file_id": "trk_05b1d487e6",
        "id": "cust-char01-b",
        "slug": "char01_daily_puwapuwari",
        "title": "ぷわぷわり",
        "original_title": "ぷわぷわり",
        "artist": "中山真斗",
        "role": "日常治愈 · 轻松逛街/温馨陪伴（CHAR-01）",
        "category": "story",
        "slots": ["CHAR-01"],
        "aliases": ["中山真斗 - ぷわぷわり"],
    },
    {
        "file_id": "trk_4eebf60f7c",
        "id": "cust-char03-a",
        "slug": "char03_chaine_signifiante",
        "title": "能指链条",
        "original_title": "能指链条 Chaîne Signifiante",
        "artist": "HOYO-MiX",
        "role": "黑化/真相崩溃/高压对峙首选（CHAR-03）",
        "category": "story",
        "slots": ["CHAR-03"],
        "aliases": ["Chaîne Signifiante", "Chaine Signifiante", "能指链条 Chaîne Signifiante"],
    },
    {
        "file_id": "trk_abc8695c67",
        "id": "cust-char03-b",
        "slug": "char03_whispers_immensity",
        "title": "细语回萦",
        "original_title": "细语回萦 Whispers of Immensity",
        "artist": "HOYO-MiX",
        "role": "黑化/精神侵蚀/深度压迫备选（CHAR-03）",
        "category": "story",
        "slots": ["CHAR-03"],
        "aliases": ["Whispers of Immensity", "细语回萦 Whispers of Immensity"],
    },
    {
        "file_id": "trk_228d4500e9",
        "id": "cust-char04-a",
        "slug": "char04_night_purr",
        "title": "Purr",
        "original_title": "Purr",
        "artist": "Pandrezz",
        "role": "温柔夜谈与亲密悸动首选（CHAR-04）",
        "category": "story",
        "slots": ["CHAR-04"],
        "aliases": ["Pandrezz - Purr"],
    },
    {
        "file_id": "trk_229042fe96",
        "id": "cust-char04-b",
        "slug": "char04_night_better_together",
        "title": "Better, Together, Forever",
        "original_title": "Better, Together, Forever",
        "artist": "Team Astro",
        "role": "温柔夜谈与亲密悸动备选一（CHAR-04）",
        "category": "story",
        "slots": ["CHAR-04"],
        "aliases": ["Better Together Forever", "Team Astro - Better, Together, Forever"],
    },
    {
        "file_id": "trk_6350c2b52e",
        "id": "cust-char04-c",
        "slug": "char04_night_tomorrows",
        "title": "Tomorrows That Follow",
        "original_title": "Tomorrows That Follow",
        "artist": "ENRA / sleepermane",
        "role": "温柔夜谈与亲密悸动备选二（CHAR-04）",
        "category": "story",
        "slots": ["CHAR-04"],
        "aliases": ["ENRA,sleepermane - Tomorrows That Follow"],
    },
    {
        "file_id": "trk_f70c845771",
        "id": "cust-char05",
        "slug": "char05_maplecamp",
        "title": "Maplecamp☆",
        "original_title": "Maplecamp☆",
        "artist": "Shiroi-Ice",
        "role": "凯旋 / 新章启程鼓舞曲（CHAR-05）",
        "category": "story",
        "slots": ["CHAR-05"],
        "aliases": ["Maplecamp", "Shiroi-Ice - Maplecamp☆"],
    },
]

WORKSHOP_SFX_SPECS: list[dict] = [
    {
        "file_id": "trk_97ce1b1582",
        "out_name": "activate_click.ogg",
        "role": "click",
        "trim_silence": True,
        "desc": "03 点击激活后触发音效（已去尾静音）",
    },
    {
        "file_id": "trk_e51be27142",
        "out_name": "activate_loop_a.ogg",
        "role": "loop_a",
        "trim_silence": True,
        "desc": "04 激活中音乐其一（已去首尾静音）",
    },
    {
        "file_id": "trk_8b11a627b8",
        "out_name": "activate_loop_b.ogg",
        "role": "loop_b",
        "trim_silence": True,
        "desc": "05 激活中音乐其二",
    },
    {
        "file_id": "trk_d9fbdd80cf",
        "out_name": "activate_done.ogg",
        "role": "done",
        "trim_silence": True,
        "desc": "06 激活完成音效（已去尾静音）",
    },
]

# Location keyword -> clean track title fallback (ordered most specific first).
LOCATION_TRACK_RULES: list[dict] = [
    {"keyword": "中央学院", "title": "誠に遺憾ながら、知り合い"},
    {"keyword": "卡米洛特", "title": "Windborne Hymn"},
    {"keyword": "尼德霍格", "title": "Old City ~ Respite"},
    {"keyword": "天国岛", "title": "瑞尼尔雪山的丧钟"},
    {"keyword": "紫宸宫", "title": "北国的宝库"},
    {"keyword": "灵山", "title": "倦飞之鸟"},
    {"keyword": "基捷日", "title": "Song for Alexandra"},
    {"keyword": "阿拉提尔", "title": "Beloved Forest"},
    {"keyword": "须弥王庭", "title": "葳蕤林野间"},
    {"keyword": "塞建陀", "title": "灼燃的残光"},
    {"keyword": "梵音林", "title": "远行的思愿"},
    {"keyword": "堤丰之喉", "title": "嵾峨之冠"},
    {"keyword": "库利亚", "title": "边地的守望者"},
    {"keyword": "云樱", "title": "恒静之梦"},
    {"keyword": "地下市场", "title": "The Witch's Breath"},
    {"keyword": "齐哈特", "title": "孤客之旅"},
    {"keyword": "蛇杖", "title": "L"},
    {"keyword": "塞蕾特", "title": "にぎやかな街"},
    {"keyword": "龙渊", "title": "紫禁城里的端庄猫"},
    {"keyword": "哥塔薇亚", "title": "Old Marple"},
    {"keyword": "秋津", "title": "神狐的祝福"},
    {"keyword": "吉万沙克蒂", "title": "The Mountain"},
    {"keyword": "格洛里亚", "title": "Rome"},
    {"keyword": "奥马努特", "title": "Santa Lucia"},
]


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def probe_ogg(path: Path) -> tuple[float, int]:
    proc = subprocess.run(
        [
            FFPROBE,
            "-v",
            "quiet",
            "-print_format",
            "json",
            "-show_format",
            "-show_streams",
            str(path),
        ],
        capture_output=True,
        text=True,
        check=True,
        creationflags=CREATION_FLAGS,
    )
    payload = json.loads(proc.stdout)
    fmt = payload.get("format", {})
    streams = [s for s in payload.get("streams", []) if s.get("codec_type") == "audio"]
    dur = round(float(fmt.get("duration") or streams[0].get("duration") or 0.0), 3)
    sr = int(streams[0].get("sample_rate") or 44100)
    return dur, sr


def transcode_to_ogg(src: Path, dest: Path, trim_silence: bool = False) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    filters = []
    if trim_silence:
        # Remove leading & trailing dead silence (-55dB >= 50ms) cleanly without clipping attack transients.
        filters.append(
            "silenceremove=start_periods=1:start_threshold=-55dB:start_duration=0.04,"
            "areverse,"
            "silenceremove=start_periods=1:start_threshold=-55dB:start_duration=0.04,"
            "areverse"
        )
    filters.append("loudnorm=I=-16:TP=-1.5:LRA=11")
    tmp = dest.with_suffix(".tmp.ogg")
    cmd = [
        FFMPEG,
        "-y",
        "-i",
        str(src),
        "-vn",
        "-map_metadata",
        "-1",
        "-af",
        ",".join(filters),
        "-ar",
        "44100",
        "-ac",
        "2",
        "-c:a",
        "libvorbis",
        "-q:a",
        "5",
        "-f",
        "ogg",
        str(tmp),
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, creationflags=CREATION_FLAGS)
    if proc.returncode != 0 or not tmp.is_file():
        tmp.unlink(missing_ok=True)
        raise RuntimeError(f"ffmpeg failed on {src.name}: {proc.stderr[-400:]}")
    tmp.replace(dest)


def main() -> int:
    parser = argparse.ArgumentParser(description="Import matched BGM and workshop activation audio.")
    parser.add_argument("--force", action="store_true", help="Force re-transcoding even if cached sha matches.")
    args = parser.parse_args()

    assignments = json.loads(ASSIGNMENTS_PATH.read_text(encoding="utf-8"))
    inbox_files = assignments.get("files", {})
    old_manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    # Preserve all 14 original tracks cleanly; record existing custom hashes for cache hit checks.
    orig_tracks = []
    prev_custom_by_id = {}
    for t in old_manifest.get("tracks", []) + old_manifest.get("reserved_tracks", []):
        tid = str(t.get("id", ""))
        if tid.startswith("orig-"):
            rec = dict(t)
            rec["category"] = "original"
            orig_tracks.append(rec)
        else:
            prev_custom_by_id[tid] = t
    assert len(orig_tracks) == 14, f"Expected 14 original tracks, got {len(orig_tracks)}"

    CUSTOM_BGM_DIR.mkdir(parents=True, exist_ok=True)
    WORKSHOP_ACT_DIR.mkdir(parents=True, exist_ok=True)

    # Pre-flight: verify every spec resolves before transcoding.
    jobs: list[tuple[Path, Path, bool, str]] = []
    for spec in CUSTOM_BGM_SPECS:
        fid = spec["file_id"]
        meta = inbox_files.get(fid)
        if not meta:
            raise KeyError(f"Missing file_id {fid} in bgm_assignments.json")
        src_path = INBOX_FILES_DIR / meta["stored_name"]
        if not src_path.is_file():
            raise FileNotFoundError(f"Missing audio file: {src_path}")
        dest_path = CUSTOM_BGM_DIR / f"{spec['slug']}.ogg"
        src_sha = meta.get("sha256") or file_sha256(src_path)
        prev = prev_custom_by_id.get(spec["id"], {})
        cached = (
            not args.force
            and dest_path.is_file()
            and (prev.get("source_sha256") == src_sha or prev == {})
        )
        # Re-transcode whenever manifest has no previous entry for it OR sha differs.
        if prev and prev.get("source_sha256") == src_sha and prev.get("lufs_target") == -16 and dest_path.is_file() and not args.force:
            continue
        if dest_path.is_file() and not args.force and not prev:
            # Reuse partial output from an interrupted first run only if valid OGG
            try:
                probe_ogg(dest_path)
                continue
            except Exception:
                pass
        jobs.append((src_path, dest_path, False, f"[BGM] {dest_path.name} ({spec['title']})"))

    prev_ws = {w.get("role"): w for w in old_manifest.get("workshop_activation", [])}
    for wspec in WORKSHOP_SFX_SPECS:
        fid = wspec["file_id"]
        meta = inbox_files.get(fid)
        if not meta:
            raise KeyError(f"Missing workshop file_id {fid}")
        src_path = INBOX_FILES_DIR / meta["stored_name"]
        if not src_path.is_file():
            raise FileNotFoundError(f"Missing workshop audio file: {src_path}")
        dest_path = WORKSHOP_ACT_DIR / wspec["out_name"]
        src_sha = meta.get("sha256") or file_sha256(src_path)
        old_w = prev_ws.get(wspec["role"], {})
        if not args.force and dest_path.is_file() and old_w.get("source_sha256") == src_sha and old_w.get("trimmed") is True:
            continue
        jobs.append((src_path, dest_path, wspec["trim_silence"], f"[Workshop] {dest_path.name}"))

    if jobs:
        print(f"Transcoding {len(jobs)} audio file(s) with 4 workers...", flush=True)
        with ThreadPoolExecutor(max_workers=4) as pool:
            futs = [(lbl, pool.submit(transcode_to_ogg, s, d, tr)) for s, d, tr, lbl in jobs]
            for lbl, fut in futs:
                fut.result()
                print(f"  OK {lbl}", flush=True)

    custom_tracks: list[dict] = []
    reserved_tracks: list[dict] = []

    for spec in CUSTOM_BGM_SPECS:
        meta = inbox_files[spec["file_id"]]
        src_path = INBOX_FILES_DIR / meta["stored_name"]
        src_sha = meta.get("sha256") or file_sha256(src_path)
        dest_path = CUSTOM_BGM_DIR / f"{spec['slug']}.ogg"
        dur, sr = probe_ogg(dest_path)
        entry = {
            "id": spec["id"],
            "title": spec["title"],
            "original_title": spec["original_title"],
            "artist": spec["artist"],
            "role": spec["role"],
            "category": spec["category"],
            "slots": spec["slots"],
            "aliases": spec["aliases"],
            "res": f"res://assets/audio/bgm/custom/{dest_path.name}",
            "source_inbox": meta["rel_path"],
            "source_sha256": src_sha,
            "sha256": file_sha256(dest_path),
            "bytes": dest_path.stat().st_size,
            "duration_seconds": dur,
            "sample_rate": sr,
            "lufs_target": -16,
            "loop_offset_seconds": 0.0,
            "gain_db": -10.0,
        }
        if spec["category"] == "reserved":
            reserved_tracks.append(entry)
        else:
            custom_tracks.append(entry)

    workshop_entries: list[dict] = []
    for wspec in WORKSHOP_SFX_SPECS:
        meta = inbox_files[wspec["file_id"]]
        src_path = INBOX_FILES_DIR / meta["stored_name"]
        src_sha = meta.get("sha256") or file_sha256(src_path)
        dest_path = WORKSHOP_ACT_DIR / wspec["out_name"]
        dur, sr = probe_ogg(dest_path)
        workshop_entries.append(
            {
                "role": wspec["role"],
                "desc": wspec["desc"],
                "res": f"res://assets/audio/ui/workshop_activation/{dest_path.name}",
                "source_inbox": meta["rel_path"],
                "source_sha256": src_sha,
                "sha256": file_sha256(dest_path),
                "trimmed": True,
                "duration_seconds": dur,
                "sample_rate": sr,
                "bytes": dest_path.stat().st_size,
            }
        )

    all_playable = orig_tracks + custom_tracks
    story_tracks = [
        t["title"]
        for t in all_playable
        if t["title"] != "Main Theme" and t.get("category") != "ui"
    ]

    manifest_out = {
        "format": "aethera-music/3",
        "edition": "full-expanded",
        "source": (
            "SillyTavern 艾瑟拉原卡保留 14 首 + 用户严选扩充曲库（势力/地点/工坊/主页/日常/夜谈/危机，共 36 首入库 + 1 首开场预留）"
        ),
        "usage_note": (
            "非商用个人独立项目使用：全部新曲均已转码为 44.1kHz 立体声 -16 LUFS Ogg Vorbis 写入 assets/audio/bgm/custom/；"
            "原卡 14 首保留在 assets/audio/bgm/original/。工坊激活 4 段新音频保存在 assets/audio/ui/workshop_activation/。"
        ),
        "title_track": "Main Theme",
        "ui_screen_tracks": {
            "home_day": "白昼天晴",
            "home_night": "温柔夜色",
            "workshop": "人工梦游",
        },
        "story_tracks": story_tracks,
        "location_tracks": LOCATION_TRACK_RULES,
        "tracks": all_playable,
        "reserved_tracks": reserved_tracks,
        "workshop_activation": workshop_entries,
    }

    tmp_json = MANIFEST_PATH.with_suffix(".json.tmp")
    tmp_json.write_text(json.dumps(manifest_out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    tmp_json.replace(MANIFEST_PATH)

    print(
        f"Done! manifest tracks={len(all_playable)} (14 orig + {len(custom_tracks)} custom), "
        f"reserved={len(reserved_tracks)}, story_tracks={len(story_tracks)}, workshop_sfx={len(workshop_entries)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
