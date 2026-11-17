"""Local BGM matching workbench server for AETHERA (Project Mystic).

Serves a drag-and-drop web UI on 127.0.0.1 so the creator can match audio files
to the 48 canonical missing BGM slots (and audition the 14 existing tracks),
persisting dropped files and a machine-readable assignment index inside:
  rolecard-rpg/workspaces/frontend-ui/materials/bgm-matcher-inbox/
"""

from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import mimetypes
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import threading
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

TOOLS_DIR = Path(__file__).resolve().parent
ROLECARD_DIR = TOOLS_DIR.parent
REPO_ROOT = ROLECARD_DIR.parent
UI_DIR = TOOLS_DIR / "bgm_workbench"
SLOTS_PATH = TOOLS_DIR / "bgm_slots.json"
MUSIC_MANIFEST_PATH = ROLECARD_DIR / "data" / "content" / "music_manifest.json"
ORIGINAL_BGM_DIR = ROLECARD_DIR / "assets" / "audio" / "bgm" / "original"
INBOX_DIR = ROLECARD_DIR / "workspaces" / "frontend-ui" / "materials" / "bgm-matcher-inbox"
INBOX_FILES_DIR = INBOX_DIR / "files"
ASSIGNMENTS_PATH = INBOX_DIR / "bgm_assignments.json"
SUMMARY_MD_PATH = INBOX_DIR / "已匹配BGM总览.md"

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 18910
MAX_UPLOAD_BYTES = 256 * 1024 * 1024
ALLOWED_AUDIO_EXTS = {
    ".mp3",
    ".ogg",
    ".wav",
    ".flac",
    ".m4a",
    ".aac",
    ".opus",
    ".webm",
}
MIME_OVERRIDES = {
    ".ogg": "audio/ogg",
    ".opus": "audio/opus",
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".flac": "audio/flac",
    ".m4a": "audio/mp4",
    ".aac": "audio/aac",
    ".webm": "audio/webm",
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
}

STATE_LOCK = threading.Lock()


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def ensure_directories() -> None:
    INBOX_DIR.mkdir(parents=True, exist_ok=True)
    INBOX_FILES_DIR.mkdir(parents=True, exist_ok=True)
    gdignore = INBOX_DIR / ".gdignore"
    if not gdignore.exists():
        gdignore.write_text("", encoding="utf-8")


def load_slots_catalog() -> dict:
    return json.loads(SLOTS_PATH.read_text(encoding="utf-8"))


def load_original_tracks() -> list[dict]:
    if not MUSIC_MANIFEST_PATH.is_file():
        return []
    manifest = json.loads(MUSIC_MANIFEST_PATH.read_text(encoding="utf-8"))
    tracks: list[dict] = []
    for item in manifest.get("tracks", []):
        if not str(item.get("id", "")).startswith("orig-"):
            continue
        res_path = str(item.get("res", ""))
        audio_url = ""
        if res_path.startswith("res://"):
            candidate = (ROLECARD_DIR / res_path.removeprefix("res://")).resolve()
            if candidate.is_relative_to(ORIGINAL_BGM_DIR.resolve()) and candidate.is_file():
                audio_url = f"/audio/original/{urllib.parse.quote(candidate.name)}"
        tracks.append(
            {
                "id": item.get("id", ""),
                "title": item.get("title", ""),
                "original_title": item.get("original_title", ""),
                "artist": item.get("artist", ""),
                "album": item.get("album", ""),
                "role": item.get("role", ""),
                "res": res_path,
                "duration_seconds": item.get("duration_seconds"),
                "sample_rate": item.get("sample_rate"),
                "audio_url": audio_url,
            }
        )
    return tracks


def empty_assignments() -> dict:
    return {
        "schema": "aethera-bgm-assignments/1",
        "updated_at": now_iso(),
        "inbox_dir_rel": INBOX_DIR.relative_to(REPO_ROOT).as_posix(),
        "files": {},
        "slots": {},
        "custom_slots": [],
    }


def load_assignments_unlocked() -> dict:
    ensure_directories()
    if not ASSIGNMENTS_PATH.is_file():
        data = empty_assignments()
        save_assignments_unlocked(data)
        return data
    data = json.loads(ASSIGNMENTS_PATH.read_text(encoding="utf-8"))
    data.setdefault("schema", "aethera-bgm-assignments/1")
    data.setdefault("inbox_dir_rel", INBOX_DIR.relative_to(REPO_ROOT).as_posix())
    data.setdefault("files", {})
    data.setdefault("slots", {})
    data.setdefault("custom_slots", [])
    return data


def save_assignments_unlocked(data: dict) -> None:
    ensure_directories()
    data["updated_at"] = now_iso()
    tmp_path = ASSIGNMENTS_PATH.with_suffix(".json.tmp")
    tmp_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp_path, ASSIGNMENTS_PATH)
    write_markdown_summary_unlocked(data)


def write_markdown_summary_unlocked(data: dict) -> None:
    """Write a readable Markdown index so humans and AIs can scan matches fast."""
    catalog = load_slots_catalog()
    originals = {t["id"]: t for t in load_original_tracks()}
    files = data.get("files", {})
    slot_states = data.get("slots", {})
    all_slots = list(catalog.get("slots", [])) + list(data.get("custom_slots", []))

    matched_rows: list[str] = []
    fallback_rows: list[str] = []
    missing_batch1: list[str] = []

    for slot in all_slots:
        sid = slot["id"]
        st = slot_states.get(sid, {})
        mode = st.get("mode", "missing")
        file_ids = [fid for fid in st.get("file_ids", []) if fid in files]
        note = (st.get("slot_note") or "").replace("\n", " ").replace("|", "\\|")
        if mode == "matched" and file_ids:
            primary_id = st.get("primary_file_id") or file_ids[0]
            ordered_ids = [primary_id] + [fid for fid in file_ids if fid != primary_id]
            paths_desc = []
            credits_desc = []
            for fid in ordered_ids:
                meta = files[fid]
                tag = "首选" if fid == primary_id else "候选"
                paths_desc.append(f"[{tag}] `{meta['rel_path']}` ({meta.get('display_title') or meta['original_filename']})")
                if meta.get("source_credit"):
                    credits_desc.append(meta["source_credit"].replace("|", "\\|"))
            matched_rows.append(
                f"| `{sid}` | {slot['name']} | {'<br>'.join(paths_desc)} | {', '.join(credits_desc) or '—'} | {note or '—'} |"
            )
        elif mode == "fallback_original" and st.get("fallback_original_id") in originals:
            orig = originals[st["fallback_original_id"]]
            fallback_rows.append(
                f"| `{sid}` | {slot['name']} | 暂用 `{orig['id']}` ({orig['title']}) -> `{orig['res']}` | {note or '—'} |"
            )
        elif mode != "skipped" and slot.get("batch1"):
            missing_batch1.append(f"- `{sid}` {slot['name']}（{slot.get('priority', '')}）")

    matched_file_ids = {
        fid
        for st in slot_states.values()
        for fid in st.get("file_ids", [])
        if fid in files
    }
    unassigned_lines = [
        f"- `{meta['file_id']}` `{meta['rel_path']}` ({meta.get('display_title') or meta['original_filename']})"
        for fid, meta in files.items()
        if fid not in matched_file_ids
    ]

    lines = [
        "# AETHERA BGM 配乐匹配总览（自动生成）",
        "",
        f"- 更新时间：`{data.get('updated_at', '')}`",
        f"- 权威 JSON 索引：`rolecard-rpg/workspaces/frontend-ui/materials/bgm-matcher-inbox/bgm_assignments.json`",
        f"- 音频文件仓库：`rolecard-rpg/workspaces/frontend-ui/materials/bgm-matcher-inbox/files/`",
        f"- 统计：已配新曲 **{len(matched_rows)}** 条 · 暂用原卡 **{len(fallback_rows)}** 条 · 第一批仍缺 **{len(missing_batch1)}** 条",
        "",
        "## 1. 已匹配新曲列表",
        "",
    ]
    if matched_rows:
        lines.extend(
            [
                "| 编号 | 板块名称 | 已匹配音频路径 | 来源/作者备注 | 板块备注 |",
                "| --- | --- | --- | --- | --- |",
                *matched_rows,
            ]
        )
    else:
        lines.append("_暂无已匹配新曲，把音频拖进网页对应板块后会自动出现在这里。_")

    lines.extend(["", "## 2. 标注为暂用原卡 14 首的板块", ""])
    if fallback_rows:
        lines.extend(
            [
                "| 编号 | 板块名称 | 暂代原卡曲目 | 备注 |",
                "| --- | --- | --- | --- |",
                *fallback_rows,
            ]
        )
    else:
        lines.append("_暂无_")

    lines.extend(["", "## 3. 第一批优先仍待寻找", ""])
    lines.extend(missing_batch1 or ["_第一批高优板块已全部配齐或标为暂代！_"])

    if unassigned_lines:
        lines.extend(["", "## 4. 已上传但尚未分配到板块的音频池", "", *unassigned_lines])

    tmp_md = SUMMARY_MD_PATH.with_suffix(".md.tmp")
    tmp_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.replace(tmp_md, SUMMARY_MD_PATH)


def sanitize_filename_stem(raw_name: str) -> str:
    stem = Path(raw_name).stem.strip()
    stem = re.sub(r'[<>:"/\\|?*\x00-\x1f]+', "_", stem)
    stem = re.sub(r"\s+", " ", stem).strip(" ._")
    if not stem:
        stem = "bgm_track"
    return stem[:48]


def probe_audio_metadata(file_path: Path) -> dict:
    ffprobe = shutil.which("ffprobe")
    if not ffprobe:
        return {"duration_seconds": None, "sample_rate": None, "codec": None}
    try:
        proc = subprocess.run(
            [
                ffprobe,
                "-v",
                "quiet",
                "-print_format",
                "json",
                "-show_format",
                "-show_streams",
                str(file_path),
            ],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        if proc.returncode != 0 or not proc.stdout:
            return {"duration_seconds": None, "sample_rate": None, "codec": None}
        payload = json.loads(proc.stdout)
        fmt = payload.get("format", {})
        streams = [s for s in payload.get("streams", []) if s.get("codec_type") == "audio"]
        stream = streams[0] if streams else {}
        duration_raw = fmt.get("duration") or stream.get("duration")
        sr_raw = stream.get("sample_rate")
        return {
            "duration_seconds": round(float(duration_raw), 2) if duration_raw else None,
            "sample_rate": int(sr_raw) if sr_raw else None,
            "codec": stream.get("codec_name") or None,
        }
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"duration_seconds": None, "sample_rate": None, "codec": None}


def build_state_payload_unlocked(data: dict) -> dict:
    catalog = load_slots_catalog()
    originals = load_original_tracks()
    files_out = {}
    for fid, meta in data.get("files", {}).items():
        enriched = dict(meta)
        enriched["audio_url"] = f"/audio/inbox/{urllib.parse.quote(meta['stored_name'])}"
        enriched["file_exists"] = (INBOX_FILES_DIR / meta["stored_name"]).is_file()
        files_out[fid] = enriched

    canonical_slots = catalog.get("slots", [])
    custom_slots = data.get("custom_slots", [])
    slot_states = data.get("slots", {})

    matched_count = 0
    fallback_count = 0
    skipped_count = 0
    batch1_total = 0
    batch1_done = 0

    for slot in canonical_slots:
        sid = slot["id"]
        st = slot_states.get(sid, {})
        mode = st.get("mode", "missing")
        valid_fids = [fid for fid in st.get("file_ids", []) if fid in files_out]
        is_batch1 = bool(slot.get("batch1"))
        if is_batch1:
            batch1_total += 1
        if mode == "matched" and valid_fids:
            matched_count += 1
            if is_batch1:
                batch1_done += 1
        elif mode == "fallback_original" and st.get("fallback_original_id"):
            fallback_count += 1
            if is_batch1:
                batch1_done += 1
        elif mode == "skipped":
            skipped_count += 1

    return {
        "schema": "aethera-bgm-state/1",
        "updated_at": data.get("updated_at"),
        "inbox_dir_abs": str(INBOX_DIR),
        "inbox_dir_rel": data.get("inbox_dir_rel"),
        "assignments_path_rel": ASSIGNMENTS_PATH.relative_to(REPO_ROOT).as_posix(),
        "summary_md_rel": SUMMARY_MD_PATH.relative_to(REPO_ROOT).as_posix(),
        "categories": catalog.get("categories", []),
        "slots": canonical_slots,
        "custom_slots": custom_slots,
        "covered_events_c2": catalog.get("covered_events_c2", []),
        "original_tracks": originals,
        "files": files_out,
        "slot_states": slot_states,
        "stats": {
            "total_slots": len(canonical_slots),
            "matched_slots": matched_count,
            "fallback_slots": fallback_count,
            "skipped_slots": skipped_count,
            "missing_slots": max(0, len(canonical_slots) - matched_count - fallback_count - skipped_count),
            "batch1_total": batch1_total,
            "batch1_done": batch1_done,
            "uploaded_files_count": len(files_out),
        },
    }


def valid_slot_ids_unlocked(data: dict) -> set[str]:
    catalog = load_slots_catalog()
    ids = {s["id"] for s in catalog.get("slots", [])}
    ids.update(s["id"] for s in data.get("custom_slots", []))
    return ids


def assign_file_to_slot_unlocked(data: dict, slot_id: str, file_id: str, make_primary: bool = True) -> None:
    if slot_id == "__POOL__":
        return
    if slot_id not in valid_slot_ids_unlocked(data):
        raise ValueError(f"Unknown slot_id: {slot_id}")
    if file_id not in data["files"]:
        raise ValueError(f"Unknown file_id: {file_id}")

    st = data["slots"].setdefault(
        slot_id,
        {
            "slot_id": slot_id,
            "mode": "missing",
            "primary_file_id": "",
            "file_ids": [],
            "fallback_original_id": "",
            "slot_note": "",
        },
    )
    if file_id not in st["file_ids"]:
        st["file_ids"].append(file_id)
    if make_primary or not st.get("primary_file_id"):
        st["primary_file_id"] = file_id
    st["mode"] = "matched"
    st["fallback_original_id"] = ""


def ingest_upload_stream(
    stream,
    content_length: int,
    raw_filename: str,
    slot_id: str,
) -> tuple[dict, bool]:
    """Stream upload body to disk, deduplicate by SHA-256, and bind slot_id."""
    if content_length <= 0:
        raise ValueError("上传文件内容为空")
    if content_length > MAX_UPLOAD_BYTES:
        raise ValueError(f"单文件不能超过 {MAX_UPLOAD_BYTES // (1024 * 1024)} MB")

    safe_base = Path(raw_filename).name
    ext = Path(safe_base).suffix.lower()
    if ext not in ALLOWED_AUDIO_EXTS:
        raise ValueError(f"不支持的音频格式：{ext or '无后缀'}（支持 {', '.join(sorted(ALLOWED_AUDIO_EXTS))}）")

    ensure_directories()
    tmp_path = INBOX_FILES_DIR / f".upload_{os.getpid()}_{threading.get_ident()}.part"
    hasher = hashlib.sha256()
    remaining = content_length

    try:
        with tmp_path.open("wb") as handle:
            while remaining > 0:
                chunk = stream.read(min(65536, remaining))
                if not chunk:
                    raise ValueError("上传流提前中断，请重试")
                handle.write(chunk)
                hasher.update(chunk)
                remaining -= len(chunk)

        sha256 = hasher.hexdigest()
        file_id = f"trk_{sha256[:10]}"
        clean_stem = sanitize_filename_stem(safe_base)
        stored_name = f"{clean_stem}__{sha256[:8]}{ext}"
        dest_path = INBOX_FILES_DIR / stored_name

        with STATE_LOCK:
            data = load_assignments_unlocked()
            existing = data["files"].get(file_id)
            deduped = False
            if existing and (INBOX_FILES_DIR / existing["stored_name"]).is_file():
                tmp_path.unlink(missing_ok=True)
                deduped = True
                meta = existing
            else:
                os.replace(tmp_path, dest_path)
                audio_info = probe_audio_metadata(dest_path)
                meta = {
                    "file_id": file_id,
                    "stored_name": stored_name,
                    "rel_path": dest_path.relative_to(REPO_ROOT).as_posix(),
                    "original_filename": safe_base,
                    "ext": ext,
                    "bytes": content_length,
                    "sha256": sha256,
                    "duration_seconds": audio_info["duration_seconds"],
                    "sample_rate": audio_info["sample_rate"],
                    "codec": audio_info["codec"],
                    "display_title": Path(safe_base).stem,
                    "source_credit": "",
                    "notes": "",
                    "uploaded_at": now_iso(),
                }
                data["files"][file_id] = meta

            assign_file_to_slot_unlocked(data, slot_id, file_id, make_primary=True)
            save_assignments_unlocked(data)
            state = build_state_payload_unlocked(data)
            return {"ok": True, "deduped": deduped, "file": meta, "state": state}, deduped
    except Exception:
        tmp_path.unlink(missing_ok=True)
        raise


def handle_mutation(payload: dict) -> dict:
    action = payload.get("action", "")
    with STATE_LOCK:
        data = load_assignments_unlocked()
        if action == "assign":
            assign_file_to_slot_unlocked(
                data,
                str(payload.get("slot_id", "")),
                str(payload.get("file_id", "")),
                make_primary=bool(payload.get("make_primary", True)),
            )
        elif action == "unassign":
            slot_id = str(payload.get("slot_id", ""))
            file_id = str(payload.get("file_id", ""))
            st = data["slots"].get(slot_id)
            if st:
                st["file_ids"] = [fid for fid in st.get("file_ids", []) if fid != file_id]
                if st.get("primary_file_id") == file_id:
                    st["primary_file_id"] = st["file_ids"][0] if st["file_ids"] else ""
                if not st["file_ids"] and st.get("mode") == "matched":
                    st["mode"] = "missing"
        elif action == "set_primary":
            slot_id = str(payload.get("slot_id", ""))
            file_id = str(payload.get("file_id", ""))
            st = data["slots"].get(slot_id)
            if not st or file_id not in st.get("file_ids", []):
                raise ValueError("该曲目未绑定到此板块")
            st["primary_file_id"] = file_id
        elif action == "set_slot_mode":
            slot_id = str(payload.get("slot_id", ""))
            if slot_id not in valid_slot_ids_unlocked(data):
                raise ValueError(f"Unknown slot_id: {slot_id}")
            mode = str(payload.get("mode", "missing"))
            if mode not in {"missing", "matched", "fallback_original", "skipped"}:
                raise ValueError(f"Unsupported mode: {mode}")
            st = data["slots"].setdefault(
                slot_id,
                {
                    "slot_id": slot_id,
                    "mode": "missing",
                    "primary_file_id": "",
                    "file_ids": [],
                    "fallback_original_id": "",
                    "slot_note": "",
                },
            )
            st["mode"] = mode
            if mode == "fallback_original":
                st["fallback_original_id"] = str(payload.get("fallback_original_id", ""))
            elif mode != "matched":
                st["fallback_original_id"] = ""
        elif action == "update_slot_note":
            slot_id = str(payload.get("slot_id", ""))
            if slot_id not in valid_slot_ids_unlocked(data):
                raise ValueError(f"Unknown slot_id: {slot_id}")
            st = data["slots"].setdefault(
                slot_id,
                {
                    "slot_id": slot_id,
                    "mode": "missing",
                    "primary_file_id": "",
                    "file_ids": [],
                    "fallback_original_id": "",
                    "slot_note": "",
                },
            )
            st["slot_note"] = str(payload.get("slot_note", ""))[:400]
        elif action == "update_file_meta":
            file_id = str(payload.get("file_id", ""))
            meta = data["files"].get(file_id)
            if not meta:
                raise ValueError(f"Unknown file_id: {file_id}")
            if "display_title" in payload:
                meta["display_title"] = str(payload["display_title"]).strip()[:120] or Path(meta["original_filename"]).stem
            if "source_credit" in payload:
                meta["source_credit"] = str(payload["source_credit"]).strip()[:200]
            if "notes" in payload:
                meta["notes"] = str(payload["notes"]).strip()[:400]
        elif action == "delete_file":
            file_id = str(payload.get("file_id", ""))
            meta = data["files"].pop(file_id, None)
            if not meta:
                raise ValueError(f"Unknown file_id: {file_id}")
            target = INBOX_FILES_DIR / meta["stored_name"]
            if target.is_file():
                target.unlink()
            for st in data["slots"].values():
                st["file_ids"] = [fid for fid in st.get("file_ids", []) if fid != file_id]
                if st.get("primary_file_id") == file_id:
                    st["primary_file_id"] = st["file_ids"][0] if st["file_ids"] else ""
                if not st["file_ids"] and st.get("mode") == "matched":
                    st["mode"] = "missing"
        elif action == "add_custom_slot":
            name = str(payload.get("name", "")).strip()
            if not name:
                raise ValueError("请填写自定义板块名称")
            existing_ids = valid_slot_ids_unlocked(data)
            idx = len(data["custom_slots"]) + 1
            while f"CUSTOM-{idx:02d}" in existing_ids:
                idx += 1
            new_slot = {
                "id": f"CUSTOM-{idx:02d}",
                "category": "CUSTOM",
                "name": name[:80],
                "priority": "自定义",
                "batch1": False,
                "scene_desc": str(payload.get("scene_desc", "")).strip()[:200] or "自定义补充音乐板块",
                "style_hint": str(payload.get("style_hint", "")).strip()[:200] or "按你的具体场景需要匹配",
                "loop_req": "按需循环",
                "recommended_original_fallback": "",
            }
            data["custom_slots"].append(new_slot)
        elif action == "delete_custom_slot":
            slot_id = str(payload.get("slot_id", ""))
            before = len(data["custom_slots"])
            data["custom_slots"] = [s for s in data["custom_slots"] if s["id"] != slot_id]
            if len(data["custom_slots"]) == before:
                raise ValueError("只能删除自定义板块")
            data["slots"].pop(slot_id, None)
        else:
            raise ValueError(f"Unsupported action: {action}")

        save_assignments_unlocked(data)
        return {"ok": True, "state": build_state_payload_unlocked(data)}


def parse_byte_range(range_header: str, file_size: int) -> tuple[int, int] | None:
    if not range_header or not range_header.startswith("bytes="):
        return None
    spec = range_header.removeprefix("bytes=").split(",", 1)[0].strip()
    if "-" not in spec:
        return None
    start_s, end_s = spec.split("-", 1)
    if start_s == "":
        suffix = int(end_s)
        if suffix <= 0:
            return None
        start = max(0, file_size - suffix)
        end = file_size - 1
        return start, end
    start = int(start_s)
    end = int(end_s) if end_s else file_size - 1
    if start >= file_size or end < start:
        return None
    return start, min(end, file_size - 1)


def guess_mime(path: Path) -> str:
    ext = path.suffix.lower()
    if ext in MIME_OVERRIDES:
        return MIME_OVERRIDES[ext]
    guessed, _ = mimetypes.guess_type(str(path))
    return guessed or "application/octet-stream"


class WorkbenchHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args) -> None:
        # Keep console calm; only startup URL and errors are informative.
        return

    def send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def send_static_file(self, file_path: Path) -> None:
        if not file_path.is_file():
            self.send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Not found"})
            return
        body = file_path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", guess_mime(file_path))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def send_audio_file(self, base_dir: Path, encoded_name: str) -> None:
        raw_name = Path(urllib.parse.unquote(encoded_name)).name
        candidate = (base_dir / raw_name).resolve()
        if not candidate.is_relative_to(base_dir.resolve()) or not candidate.is_file():
            self.send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": "Audio file not found"})
            return

        file_size = candidate.stat().st_size
        range_hdr = self.headers.get("Range")
        mime = guess_mime(candidate)
        start, end = 0, max(0, file_size - 1)
        is_partial = False

        if range_hdr and file_size > 0:
            try:
                parsed = parse_byte_range(range_hdr, file_size)
            except ValueError:
                parsed = None
            if parsed is None:
                self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                self.send_header("Content-Range", f"bytes */{file_size}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            start, end = parsed
            is_partial = True

        length = (end - start + 1) if file_size > 0 else 0
        self.send_response(HTTPStatus.PARTIAL_CONTENT if is_partial else HTTPStatus.OK)
        self.send_header("Content-Type", mime)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(length))
        if is_partial:
            self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()

        if length == 0:
            return

        try:
            with candidate.open("rb") as handle:
                handle.seek(start)
                remaining = length
                while remaining > 0:
                    chunk = handle.read(min(65536, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
        except (BrokenPipeError, ConnectionAbortedError, ConnectionResetError):
            return

    def read_json_body(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exc:
            raise ValueError("Invalid Content-Length") from exc
        if length <= 0 or length > 2 * 1024 * 1024:
            raise ValueError("Invalid JSON body size")
        raw = self.rfile.read(length).decode("utf-8")
        return json.loads(raw)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/" or path == "/index.html":
            self.send_static_file(UI_DIR / "index.html")
            return
        if path == "/style.css":
            self.send_static_file(UI_DIR / "style.css")
            return
        if path == "/app.js":
            self.send_static_file(UI_DIR / "app.js")
            return
        if path == "/api/health":
            self.send_json(HTTPStatus.OK, {"ok": True, "service": "aethera-bgm-workbench"})
            return
        if path == "/api/state":
            with STATE_LOCK:
                data = load_assignments_unlocked()
                state = build_state_payload_unlocked(data)
            self.send_json(HTTPStatus.OK, {"ok": True, "state": state})
            return
        if path == "/api/export-md":
            with STATE_LOCK:
                data = load_assignments_unlocked()
                write_markdown_summary_unlocked(data)
                text = SUMMARY_MD_PATH.read_text(encoding="utf-8")
            self.send_json(HTTPStatus.OK, {"ok": True, "markdown": text})
            return
        if path.startswith("/audio/inbox/"):
            self.send_audio_file(INBOX_FILES_DIR, path.removeprefix("/audio/inbox/"))
            return
        if path.startswith("/audio/original/"):
            self.send_audio_file(ORIGINAL_BGM_DIR, path.removeprefix("/audio/original/"))
            return

        self.send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": f"Unknown route: {path}"})

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        try:
            if path == "/api/upload":
                try:
                    content_length = int(self.headers.get("Content-Length", "0"))
                except ValueError as exc:
                    raise ValueError("无效的 Content-Length") from exc
                raw_name = self.headers.get("X-File-Name") or (query.get("filename") or [""])[0]
                filename = urllib.parse.unquote(raw_name)
                slot_id = (query.get("slot_id") or ["__POOL__"])[0]
                if not filename:
                    raise ValueError("缺少文件名参数")
                result, _ = ingest_upload_stream(self.rfile, content_length, filename, slot_id)
                self.send_json(HTTPStatus.OK, result)
                return

            if path == "/api/mutate":
                body = self.read_json_body()
                result = handle_mutation(body)
                self.send_json(HTTPStatus.OK, result)
                return

            if path == "/api/open-inbox":
                ensure_directories()
                if sys.platform == "win32":
                    os.startfile(str(INBOX_DIR))
                self.send_json(HTTPStatus.OK, {"ok": True, "inbox_dir_abs": str(INBOX_DIR)})
                return

            if path == "/api/shutdown":
                self.send_json(HTTPStatus.OK, {"ok": True, "message": "Workbench server shutting down"})
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return

            self.send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": f"Unknown route: {path}"})
        except ValueError as exc:
            self.close_connection = True
            self.send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
        except Exception as exc:
            self.close_connection = True
            self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "error": str(exc)})


def check_existing_workbench(host: str, port: int) -> bool:
    url = f"http://{host}:{port}/api/health"
    try:
        with urllib.request.urlopen(url, timeout=0.8) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
            return payload.get("service") == "aethera-bgm-workbench"
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        return False


def choose_port(host: str, preferred_port: int) -> int:
    for candidate in range(preferred_port, preferred_port + 20):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind((host, candidate))
                return candidate
            except OSError:
                continue
    return 0


def start_server(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> ThreadingHTTPServer:
    with STATE_LOCK:
        data = load_assignments_unlocked()
        save_assignments_unlocked(data)
    return ThreadingHTTPServer((host, port), WorkbenchHandler)


def open_browser_url(url: str) -> None:
    if sys.platform == "win32":
        try:
            os.startfile(url)
            return
        except OSError:
            pass
    webbrowser.open(url)


def report_startup_error(err: Exception) -> None:
    try:
        ensure_directories()
        log_path = INBOX_DIR / "workbench_error.log"
        log_path.write_text(f"[{now_iso()}] {type(err).__name__}: {err}\n", encoding="utf-8")
    except OSError:
        pass
    if sys.platform == "win32":
        try:
            import ctypes
            ctypes.windll.user32.MessageBoxW(
                None,
                f"AETHERA BGM 配乐工作台启动失败：\n{err}\n\n请检查 rolecard-rpg/tools/bgm_workbench.py。",
                "AETHERA BGM 配乐工作台",
                0x10,
            )
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description="AETHERA BGM Matching Workbench")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="Local port (default 18910)")
    parser.add_argument("--open", action="store_true", help="Open the browser automatically")
    args = parser.parse_args()

    try:
        if check_existing_workbench(DEFAULT_HOST, args.port):
            url = f"http://{DEFAULT_HOST}:{args.port}"
            print(f"AETHERA BGM 配乐工作台已在运行：{url}", flush=True)
            if args.open:
                open_browser_url(url)
            return 0

        port = choose_port(DEFAULT_HOST, args.port)
        server = start_server(DEFAULT_HOST, port)
        actual_port = server.server_address[1]
        url = f"http://{DEFAULT_HOST}:{actual_port}"

        print("=" * 60, flush=True)
        print(f"AETHERA BGM 配乐匹配工作台已启动：{url}", flush=True)
        print(f"音频接收目录：{INBOX_DIR}", flush=True)
        print(f"AI 读取索引：{ASSIGNMENTS_PATH}", flush=True)
        print("提示：可在网页右上角点“停止后台”或在终端按 Ctrl+C 退出。", flush=True)
        print("=" * 60, flush=True)

        if args.open:
            threading.Timer(0.25, lambda: open_browser_url(url)).start()

        try:
            server.serve_forever()
        except KeyboardInterrupt:
            print("\n正在关闭工作台...", flush=True)
        finally:
            server.server_close()
        return 0
    except Exception as exc:
        report_startup_error(exc)
        raise


if __name__ == "__main__":
    raise SystemExit(main())
