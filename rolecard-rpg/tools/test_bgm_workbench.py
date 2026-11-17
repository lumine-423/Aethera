"""Automated end-to-end tests for bgm_workbench.py."""

from __future__ import annotations

import json
from pathlib import Path
import shutil
import sys
import threading
import unittest
import urllib.error
import urllib.parse
import urllib.request

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

import bgm_workbench as wb  # noqa: E402


class BgmWorkbenchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.orig_inbox = wb.INBOX_DIR
        self.orig_files = wb.INBOX_FILES_DIR
        self.orig_assign = wb.ASSIGNMENTS_PATH
        self.orig_md = wb.SUMMARY_MD_PATH

        test_inbox = wb.ROLECARD_DIR / "workspaces" / "frontend-ui" / "materials" / "_tmp_test_bgm_inbox"
        self.test_inbox = test_inbox
        wb.INBOX_DIR = test_inbox
        wb.INBOX_FILES_DIR = test_inbox / "files"
        wb.ASSIGNMENTS_PATH = test_inbox / "bgm_assignments.json"
        wb.SUMMARY_MD_PATH = test_inbox / "已匹配BGM总览.md"

        self.server = wb.start_server("127.0.0.1", 0)
        self.port = self.server.server_address[1]
        self.base_url = f"http://127.0.0.1:{self.port}"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        if self.test_inbox.exists():
            shutil.rmtree(self.test_inbox, ignore_errors=True)
        wb.INBOX_DIR = self.orig_inbox
        wb.INBOX_FILES_DIR = self.orig_files
        wb.ASSIGNMENTS_PATH = self.orig_assign
        wb.SUMMARY_MD_PATH = self.orig_md

    def _get_json(self, path: str) -> tuple[int, dict]:
        with urllib.request.urlopen(self.base_url + path, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))

    def _post_json(self, path: str, payload: dict) -> tuple[int, dict]:
        req = urllib.request.Request(
            self.base_url + path,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))

    def test_full_workflow_and_streaming(self) -> None:
        # 1. Health & static assets
        code, health = self._get_json("/api/health")
        self.assertEqual(code, 200)
        self.assertEqual(health["service"], "aethera-bgm-workbench")

        for asset in ["/", "/style.css", "/app.js"]:
            with urllib.request.urlopen(self.base_url + asset, timeout=5) as resp:
                self.assertEqual(resp.status, 200)
                self.assertGreater(len(resp.read()), 200)

        # 2. Initial state integrity: 48 missing slots, 21 batch1, 14 original tracks
        code, state_resp = self._get_json("/api/state")
        self.assertEqual(code, 200)
        state = state_resp["state"]
        self.assertEqual(len(state["slots"]), 48)
        self.assertEqual(len(state["original_tracks"]), 14)
        self.assertEqual(len(state["covered_events_c2"]), 8)
        self.assertEqual(state["stats"]["batch1_total"], 21)
        self.assertEqual(state["stats"]["missing_slots"], 48)
        slot_by_id = {s["id"]: s for s in state["slots"]}
        self.assertEqual(slot_by_id["FAC-01"]["name"], "塞蕾特公国")
        self.assertEqual(slot_by_id["LOC-01"]["name"], "中央学院（塞蕾特）")
        self.assertEqual(slot_by_id["LOC-14"]["name"], "齐哈特大沙漠（奥马努特西）")
        all_names = " ".join(s["name"] for s in state["slots"])
        for bogus in ("莱因帝国", "奥斯蒙联邦", "苍穹城塞", "艾尔法圣殿"):
            self.assertNotIn(bogus, all_names)

        # 3. Upload a real OGG file with CJK filename to FAC-04
        sample_ogg = wb.ORIGINAL_BGM_DIR / "qm0aff.ogg"
        self.assertTrue(sample_ogg.is_file(), "Sample original .ogg must exist")
        raw_bytes = sample_ogg.read_bytes()
        cjk_name = "秋津神社_试听曲（日系）.ogg"
        upload_url = f"{self.base_url}/api/upload?slot_id=FAC-04&filename={urllib.parse.quote(cjk_name)}"
        req = urllib.request.Request(
            upload_url,
            data=raw_bytes,
            headers={"X-File-Name": urllib.parse.quote(cjk_name)},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            up_json = json.loads(resp.read().decode("utf-8"))

        self.assertTrue(up_json["ok"])
        self.assertFalse(up_json["deduped"])
        file_id = up_json["file"]["file_id"]
        self.assertEqual(up_json["state"]["stats"]["matched_slots"], 1)
        self.assertEqual(up_json["state"]["stats"]["batch1_done"], 1)
        self.assertIsNotNone(up_json["file"]["duration_seconds"])

        # 4. Duplicate upload of same bytes to UI-01 reuses physical file and assigns both
        dup_url = f"{self.base_url}/api/upload?slot_id=UI-01&filename={urllib.parse.quote(cjk_name)}"
        req2 = urllib.request.Request(dup_url, data=raw_bytes, method="POST")
        with urllib.request.urlopen(req2, timeout=10) as resp:
            dup_json = json.loads(resp.read().decode("utf-8"))
        self.assertTrue(dup_json["deduped"])
        self.assertEqual(dup_json["state"]["stats"]["matched_slots"], 2)
        self.assertEqual(dup_json["state"]["stats"]["uploaded_files_count"], 1)

        # 5. Range audio streaming (206 Partial Content) on uploaded & original tracks
        for audio_url in [dup_json["state"]["files"][file_id]["audio_url"], "/audio/original/qm0aff.ogg"]:
            range_req = urllib.request.Request(self.base_url + audio_url, headers={"Range": "bytes=0-1023"})
            with urllib.request.urlopen(range_req, timeout=5) as rresp:
                self.assertEqual(rresp.status, 206)
                self.assertEqual(len(rresp.read()), 1024)
                self.assertIn("bytes 0-1023/", rresp.headers.get("Content-Range", ""))

        # 6. Metadata edits, fallback, custom slot, export markdown
        self._post_json(
            "/api/mutate",
            {
                "action": "update_file_meta",
                "file_id": file_id,
                "display_title": "Sakura Shrine Theme",
                "source_credit": "Test Artist",
            },
        )
        self._post_json(
            "/api/mutate",
            {
                "action": "set_slot_mode",
                "slot_id": "LOC-01",
                "mode": "fallback_original",
                "fallback_original_id": "orig-plgpzp",
            },
        )
        _, custom_res = self._post_json(
            "/api/mutate",
            {"action": "add_custom_slot", "name": "开场手书（2:19）"},
        )
        self.assertEqual(len(custom_res["state"]["custom_slots"]), 1)

        _, export_res = self._get_json("/api/export-md")
        self.assertIn("Sakura Shrine Theme", export_res["markdown"])
        self.assertIn("orig-plgpzp", export_res["markdown"])

        # 7. Reject unsupported file extension safely
        bad_url = f"{self.base_url}/api/upload?slot_id=UI-01&filename=readme.txt"
        bad_req = urllib.request.Request(bad_url, data=b"not audio", method="POST")
        with self.assertRaises(urllib.error.HTTPError) as ctx:
            urllib.request.urlopen(bad_req, timeout=5)
        self.assertEqual(ctx.exception.code, 400)
        ctx.exception.close()

        # 8. Verify launcher bat stays pure ASCII + strict CRLF and /api/shutdown responds OK
        bat_bytes = (wb.REPO_ROOT / "打开BGM配乐匹配工作台.bat").read_bytes()
        bat_bytes.decode("ascii")
        self.assertEqual(bat_bytes.count(b"\r\n"), bat_bytes.count(b"\n"))

        code, shut_res = self._post_json("/api/shutdown", {})
        self.assertEqual(code, 200)
        self.assertTrue(shut_res["ok"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
