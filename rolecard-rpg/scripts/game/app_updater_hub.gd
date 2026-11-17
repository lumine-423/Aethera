extends Node
## Cross-platform GitHub Application Updater (Android .apk + Desktop .pck/.zip/.exe).
## Supports: Check for updates (GitHub Releases + Raw/jsDelivr fallback), Pull update metadata/manifest,
## Streaming asset download with progress, SHA256 verification, PCK patch staging, and repo config persistence.

signal changed
signal progress_changed(downloaded: int, total: int, ratio: float)

const APP_MANIFEST_RES := "res://data/app_update.json"
const CFG_PATH := "user://app_updater.cfg"
const UPDATES_DIR := "user://updates/"
const PULLED_MANIFEST_NAME := "pulled_manifest.json"
const GH_MIRROR_PREFIX := "https://ghfast.top/"

var base_manifest: Dictionary = {}
var base_version := "1.0.0"
var base_version_code := 1

var github_owner := ""
var github_repo := ""
var github_branch := "main"
var manifest_rel_path := "rolecard-rpg/data/app_update.json"
var use_mirror := false
var auto_check := false
var configured := false

var latest_version := ""
var latest_tag := ""
var release_name := ""
var release_notes := ""
var release_html_url := ""
var release_published_at := ""
var release_assets: Array = []       # [{name, size, url, content_type}]
var remote_checksums: Dictionary = {} # filename -> sha256_hex
var pulled_manifest: Dictionary = {}
var installed_patch_version := ""
var active_pck_path := ""
var last_checked_at := ""
var last_source_used := ""

var checking := false
var pulling := false
var downloading := false
var update_available := false
var status_text := "待检查更新"

var downloaded_bytes := 0
var total_bytes := 0
var downloaded_file_path := ""
var downloaded_asset_url := ""
var downloaded_sha256 := ""
var selected_asset_index := 0

var cfg_path_override := ""
var updates_dir_override := ""
var platform_override := ""
## Test hook: func(op: String, url: String, extra: Dictionary) -> Dictionary
## For GET: {"status": 200, "body": "..."} ; For DOWNLOAD: {"status": 200, "bytes": PackedByteArray(...)}
var mock_transport: Callable = Callable()

var _dl_req: HTTPRequest = null
var _active_get_req: HTTPRequest = null

func _ready() -> void:
	load_all()

func _cfg_path() -> String:
	return cfg_path_override if cfg_path_override != "" else CFG_PATH

func _updates_dir() -> String:
	var d := updates_dir_override if updates_dir_override != "" else UPDATES_DIR
	return d if d.ends_with("/") else d + "/"

func _ensure_updates_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_updates_dir()))

func detect_platform_key() -> String:
	if platform_override != "":
		return platform_override.to_lower()
	match OS.get_name():
		"Android": return "android"
		"Windows": return "windows"
		"macOS": return "macos"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD": return "linux"
		_: return "windows"

func platform_label() -> String:
	match detect_platform_key():
		"android": return "手机版 (Android)"
		"windows": return "电脑版 (Windows)"
		"macos": return "电脑版 (macOS)"
		"linux": return "电脑版 (Linux)"
		_: return "桌面端"

func local_version() -> String:
	if installed_patch_version != "" and version_newer(installed_patch_version, base_version):
		return installed_patch_version
	return base_version

func is_repo_configured() -> bool:
	return github_owner.strip_edges() != "" and github_repo.strip_edges() != ""

func repo_slug() -> String:
	if not is_repo_configured():
		return "待配置 (请填写 用户名/仓库名)"
	return "%s/%s" % [github_owner.strip_edges(), github_repo.strip_edges()]

func load_all() -> void:
	if FileAccess.file_exists(APP_MANIFEST_RES):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(APP_MANIFEST_RES))
		if parsed is Dictionary:
			base_manifest = parsed
			base_version = String(parsed.get("version", "1.0.0")).strip_edges()
			base_version_code = int(parsed.get("version_code", 1))
			github_owner = String(parsed.get("github_owner", "")).strip_edges()
			github_repo = String(parsed.get("github_repo", "")).strip_edges()
			github_branch = String(parsed.get("github_branch", "main")).strip_edges()
			manifest_rel_path = String(parsed.get("manifest_rel_path", "rolecard-rpg/data/app_update.json")).strip_edges()
			configured = bool(parsed.get("configured", false)) and is_repo_configured()
	var cfg := ConfigFile.new()
	if cfg.load(_cfg_path()) == OK:
		github_owner = String(cfg.get_value("github", "owner", github_owner)).strip_edges()
		github_repo = String(cfg.get_value("github", "repo", github_repo)).strip_edges()
		github_branch = String(cfg.get_value("github", "branch", github_branch)).strip_edges()
		use_mirror = bool(cfg.get_value("github", "use_mirror", use_mirror))
		auto_check = bool(cfg.get_value("github", "auto_check", auto_check))
		active_pck_path = String(cfg.get_value("patch", "active_pck_path", "")).strip_edges()
		installed_patch_version = String(cfg.get_value("patch", "installed_patch_version", "")).strip_edges()
		if active_pck_path != "" and not FileAccess.file_exists(active_pck_path):
			active_pck_path = ""
			installed_patch_version = ""
		last_checked_at = String(cfg.get_value("state", "last_checked_at", ""))
		latest_version = String(cfg.get_value("state", "latest_version", ""))
		downloaded_file_path = String(cfg.get_value("state", "downloaded_file_path", ""))
		if downloaded_file_path != "" and not FileAccess.file_exists(downloaded_file_path):
			downloaded_file_path = ""
		configured = is_repo_configured()
	var pm_path := _updates_dir() + PULLED_MANIFEST_NAME
	if FileAccess.file_exists(pm_path):
		var pm = JSON.parse_string(FileAccess.get_file_as_string(pm_path))
		if pm is Dictionary:
			pulled_manifest = pm
	_refresh_update_flag()
	if not is_repo_configured():
		status_text = "检查更新占位：待上传至 GitHub 并绑定仓库地址"
	elif update_available:
		status_text = "发现新版本 v%s（当前 v%s）" % [latest_version, local_version()]
	else:
		status_text = "当前版本 v%s · 就绪" % local_version()

func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("github", "owner", github_owner.strip_edges())
	cfg.set_value("github", "repo", github_repo.strip_edges())
	cfg.set_value("github", "branch", github_branch.strip_edges() if github_branch.strip_edges() != "" else "main")
	cfg.set_value("github", "use_mirror", use_mirror)
	cfg.set_value("github", "auto_check", auto_check)
	cfg.set_value("patch", "active_pck_path", active_pck_path)
	cfg.set_value("patch", "installed_patch_version", installed_patch_version)
	cfg.set_value("state", "last_checked_at", last_checked_at)
	cfg.set_value("state", "latest_version", latest_version)
	cfg.set_value("state", "downloaded_file_path", downloaded_file_path)
	cfg.save(_cfg_path())

func _cancel_active_get() -> void:
	if is_instance_valid(_active_get_req):
		_active_get_req.cancel_request()
		_active_get_req.queue_free()
	_active_get_req = null
	checking = false
	pulling = false

func set_repo_config(slug_or_owner: String, repo_name := "", branch := "main", mirror := false) -> void:
	_cancel_active_get()
	var raw := slug_or_owner.strip_edges()
	raw = raw.trim_prefix("https://github.com/").trim_prefix("http://github.com/").trim_suffix(".git").trim_suffix("/")
	if "/" in raw and repo_name.strip_edges() == "":
		var parts := raw.split("/", false)
		github_owner = String(parts[0]).strip_edges()
		github_repo = String(parts[1]).strip_edges() if parts.size() >= 2 else ""
	else:
		github_owner = raw
		github_repo = repo_name.strip_edges()
	github_branch = branch.strip_edges() if branch.strip_edges() != "" else "main"
	use_mirror = mirror
	configured = is_repo_configured()
	if not configured:
		latest_version = ""
		release_assets.clear()
		update_available = false
		status_text = "检查更新占位：请填写 GitHub 仓库（用户名/仓库名）"
	else:
		status_text = "已绑定 GitHub 仓库：%s（点击检查更新）" % repo_slug()
	save_config()
	changed.emit()

func reset_repo_config() -> void:
	_cancel_active_get()
	github_owner = String(base_manifest.get("github_owner", "")).strip_edges()
	github_repo = String(base_manifest.get("github_repo", "")).strip_edges()
	github_branch = String(base_manifest.get("github_branch", "main")).strip_edges()
	use_mirror = false
	configured = is_repo_configured()
	latest_version = ""
	latest_tag = ""
	release_notes = ""
	release_assets.clear()
	update_available = false
	selected_asset_index = 0
	status_text = "已恢复默认占位配置"
	save_config()
	changed.emit()

static func version_newer(remote_ver: String, local_ver: String) -> bool:
	var ra := _ver_tuple(remote_ver)
	var la := _ver_tuple(local_ver)
	for i in range(3):
		if ra[i] > la[i]: return true
		if ra[i] < la[i]: return false
	return false

static func _ver_tuple(v: String) -> Array[int]:
	var clean := v.strip_edges().trim_prefix("v").trim_prefix("V").split("-")[0].split("+")[0]
	var parts := clean.split(".")
	var out: Array[int] = [0, 0, 0]
	for i in range(mini(3, parts.size())):
		if parts[i].is_valid_int():
			out[i] = int(parts[i])
	return out

func _refresh_update_flag() -> void:
	update_available = latest_version != "" and version_newer(latest_version, local_version())

func _http_get_text(url: String, headers: PackedStringArray, cb: Callable) -> void:
	if mock_transport.is_valid():
		var res = mock_transport.call("GET", url, {"headers": headers})
		if res is Dictionary:
			var sc := int(res.get("status", 200))
			cb.call(sc >= 200 and sc < 300, String(res.get("body", "")), sc)
			return
	var req := HTTPRequest.new()
	req.timeout = 14.0
	add_child(req)
	_active_get_req = req
	req.request_completed.connect(func(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray):
		if _active_get_req == req: _active_get_req = null
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
			cb.call(true, body.get_string_from_utf8(), code)
		else:
			cb.call(false, "", code)
	, CONNECT_ONE_SHOT)
	var err := req.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		if _active_get_req == req: _active_get_req = null
		req.queue_free()
		cb.call(false, "", 0)

func _build_release_urls() -> Array:
	var o := github_owner.strip_edges()
	var r := github_repo.strip_edges()
	var api := "https://api.github.com/repos/%s/%s/releases/latest" % [o, r]
	var list := []
	if use_mirror:
		list.append({"name": "GHProxy Release 镜像", "url": GH_MIRROR_PREFIX + api, "kind": "release"})
		list.append({"name": "GitHub Releases API", "url": api, "kind": "release"})
	else:
		list.append({"name": "GitHub Releases API", "url": api, "kind": "release"})
		list.append({"name": "GHProxy Release 镜像", "url": GH_MIRROR_PREFIX + api, "kind": "release"})
	return list

func _build_manifest_urls() -> Array:
	var o := github_owner.strip_edges()
	var r := github_repo.strip_edges()
	var b := github_branch.strip_edges() if github_branch.strip_edges() != "" else "main"
	var p := manifest_rel_path.trim_prefix("/")
	var raw_url := "https://raw.githubusercontent.com/%s/%s/%s/%s" % [o, r, b, p]
	var cdn_url := "https://cdn.jsdelivr.net/gh/%s/%s@%s/%s" % [o, r, b, p]
	var mirror_url := GH_MIRROR_PREFIX + raw_url
	var list := []
	if use_mirror:
		list.append({"name": "GHProxy Raw", "url": mirror_url, "kind": "manifest"})
		list.append({"name": "jsDelivr CDN", "url": cdn_url, "kind": "manifest"})
		list.append({"name": "GitHub Raw", "url": raw_url, "kind": "manifest"})
	else:
		list.append({"name": "GitHub Raw", "url": raw_url, "kind": "manifest"})
		list.append({"name": "jsDelivr CDN", "url": cdn_url, "kind": "manifest"})
		list.append({"name": "GHProxy Raw", "url": mirror_url, "kind": "manifest"})
	return list

func check_for_updates(cb := Callable()) -> void:
	if checking or pulling:
		return
	if not is_repo_configured():
		status_text = "未绑定 GitHub 仓库：请在下方输入 用户名/仓库名 后重试"
		changed.emit()
		if cb.is_valid(): cb.call(false, local_version(), status_text)
		return
	checking = true
	status_text = "正在检查 GitHub 更新 (%s)…" % repo_slug()
	changed.emit()
	var rel_sources := _build_release_urls()
	_try_release_sources(rel_sources, 0, cb)

func _try_release_sources(sources: Array, idx: int, cb: Callable) -> void:
	if idx >= sources.size():
		_try_manifest_sources(_build_manifest_urls(), 0, cb)
		return
	var src: Dictionary = sources[idx]
	var hdrs := PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: Aethera-RPG-Updater/1.0"])
	_http_get_text(String(src.url), hdrs, func(ok_flag: bool, body: String, _code: int):
		if ok_flag and body.strip_edges() != "":
			var parsed = JSON.parse_string(body)
			if parsed is Dictionary and (parsed.has("tag_name") or parsed.has("name")):
				_apply_release_payload(parsed, String(src.name))
				checking = false
				last_checked_at = Time.get_datetime_string_from_system(false, true)
				save_config()
				changed.emit()
				if cb.is_valid(): cb.call(true, latest_version, status_text)
				return
		_try_release_sources(sources, idx + 1, cb)
	)

func _try_manifest_sources(sources: Array, idx: int, cb: Callable) -> void:
	if idx >= sources.size():
		checking = false
		status_text = "检查失败：未找到 Release，且无法从 GitHub / jsDelivr 读取清单"
		changed.emit()
		if cb.is_valid(): cb.call(false, local_version(), status_text)
		return
	var src: Dictionary = sources[idx]
	var hdrs := PackedStringArray(["Accept: application/json", "User-Agent: Aethera-RPG-Updater/1.0"])
	_http_get_text(String(src.url), hdrs, func(ok_flag: bool, body: String, _code: int):
		if ok_flag and body.strip_edges() != "":
			var parsed = JSON.parse_string(body)
			if parsed is Dictionary and String(parsed.get("version", "")).strip_edges() != "":
				_apply_manifest_payload(parsed, String(src.name))
				checking = false
				last_checked_at = Time.get_datetime_string_from_system(false, true)
				save_config()
				changed.emit()
				if cb.is_valid(): cb.call(true, latest_version, status_text)
				return
		_try_manifest_sources(sources, idx + 1, cb)
	)

func _apply_release_payload(d: Dictionary, source_name: String) -> void:
	latest_tag = String(d.get("tag_name", d.get("name", ""))).strip_edges()
	latest_version = latest_tag.trim_prefix("v").trim_prefix("V")
	if latest_version == "":
		latest_version = String(d.get("name", "")).strip_edges()
	release_name = String(d.get("name", latest_tag))
	release_notes = String(d.get("body", "")).strip_edges()
	release_html_url = String(d.get("html_url", "https://github.com/%s/releases" % repo_slug()))
	release_published_at = String(d.get("published_at", "")).substr(0, 10)
	last_source_used = source_name
	release_assets.clear()
	remote_checksums.clear()
	var assets = d.get("assets", [])
	if assets is Array:
		for a in assets:
			if not a is Dictionary: continue
			var aname := String(a.get("name", ""))
			var aurl := String(a.get("browser_download_url", ""))
			if aname == "" or aurl == "": continue
			release_assets.append({
				"name": aname,
				"size": int(a.get("size", 0)),
				"url": aurl,
				"content_type": String(a.get("content_type", "")),
				"platform_hint": _guess_asset_platform(aname),
			})
	selected_asset_index = _best_asset_index()
	_refresh_update_flag()
	if update_available:
		status_text = "发现新版本 v%s（来自 %s，已匹配 %s 包）" % [latest_version, source_name, platform_label()]
	else:
		status_text = "已是最新版本 v%s（远端：%s）" % [local_version(), latest_version]

func _apply_manifest_payload(d: Dictionary, source_name: String) -> void:
	latest_version = String(d.get("version", "")).strip_edges()
	latest_tag = "v" + latest_version
	release_name = "%s v%s" % [String(d.get("app_name", "艾瑟拉")), latest_version]
	release_notes = String(d.get("changelog", "")).strip_edges()
	release_html_url = "https://github.com/%s/releases" % repo_slug()
	release_published_at = ""
	last_source_used = source_name
	release_assets.clear()
	if d.get("assets") is Array:
		for a in d.get("assets", []):
			if not a is Dictionary: continue
			var aname := String(a.get("name", ""))
			var aurl := String(a.get("url", a.get("browser_download_url", "")))
			if aname != "" and aurl != "":
				release_assets.append({
					"name": aname,
					"size": int(a.get("size", 0)),
					"url": aurl,
					"content_type": String(a.get("content_type", "")),
					"platform_hint": _guess_asset_platform(aname),
				})
	selected_asset_index = _best_asset_index()
	_refresh_update_flag()
	if update_available:
		status_text = "检测到远端新版清单 v%s（来自 %s）" % [latest_version, source_name]
	else:
		status_text = "仓库清单已是最新 v%s" % local_version()

static func _guess_asset_platform(filename: String) -> String:
	var low := filename.to_lower()
	if low.ends_with(".apk") or low.ends_with(".aab"): return "android"
	if low.ends_with(".pck"): return "hotpatch"
	if "win" in low or low.ends_with(".exe") or low.ends_with(".msi"): return "windows"
	if "mac" in low or "osx" in low or low.ends_with(".dmg"): return "macos"
	if "linux" in low or low.ends_with(".appimage") or low.ends_with(".x86_64"): return "linux"
	if low.ends_with(".zip"): return "archive"
	return "other"

func _best_asset_index() -> int:
	if release_assets.is_empty():
		return -1
	var pkey := detect_platform_key()
	var pref_order: Array = []
	match pkey:
		"android": pref_order = [".apk"]
		"windows": pref_order = [".pck", ".exe", "win", ".zip"]
		"macos": pref_order = [".pck", ".dmg", "mac", ".zip"]
		"linux": pref_order = [".pck", ".appimage", ".x86_64", "linux", ".zip"]
		_: pref_order = [".zip"]
	for pat in pref_order:
		for i in range(release_assets.size()):
			var low := String(release_assets[i].get("name", "")).to_lower()
			if String(pat) in low:
				return i
	return 0

func recommended_asset() -> Dictionary:
	if release_assets.is_empty():
		return {}
	if selected_asset_index >= 0 and selected_asset_index < release_assets.size():
		return release_assets[selected_asset_index]
	var bi := _best_asset_index()
	return release_assets[bi] if bi >= 0 else {}

func pull_update(cb := Callable()) -> void:
	if pulling or checking:
		return
	if not is_repo_configured():
		status_text = "未绑定 GitHub 仓库：请先填写 用户名/仓库名"
		changed.emit()
		if cb.is_valid(): cb.call(false, status_text)
		return
	pulling = true
	status_text = "正在拉取远端版本清单、更新日志与校验信息…"
	changed.emit()
	_pull_step_manifest(func(ok_m: bool, msg_m: String):
		if not ok_m:
			pulling = false
			status_text = msg_m
			changed.emit()
			if cb.is_valid(): cb.call(false, status_text)
			return
		_try_pull_checksums(func():
			_ensure_updates_dir()
			var rec := {
				"repo": repo_slug(),
				"branch": github_branch,
				"version": latest_version,
				"tag": latest_tag,
				"notes": release_notes,
				"html_url": release_html_url,
				"assets": release_assets,
				"checksums": remote_checksums,
				"pulled_at": Time.get_datetime_string_from_system(false, true),
			}
			pulled_manifest = rec
			var f := FileAccess.open(_updates_dir() + PULLED_MANIFEST_NAME, FileAccess.WRITE)
			if f:
				f.store_string(JSON.stringify(rec, "\t"))
				f.close()
			pulling = false
			var rec_asset := recommended_asset()
			var extra := ("；推荐包 %s 已就绪，可点击「下载更新」" % String(rec_asset.get("name", ""))) if not rec_asset.is_empty() else "；清单与日志已同步"
			status_text = "已拉取远端更新数据 v%s%s" % [latest_version if latest_version != "" else local_version(), extra]
			save_config()
			changed.emit()
			if cb.is_valid(): cb.call(true, status_text)
		)
	)

func _pull_step_manifest(done: Callable) -> void:
	if latest_version != "" and not release_assets.is_empty():
		done.call(true, "")
		return
	var sources := _build_release_urls()
	_try_release_then_manifest_for_pull(sources, 0, done)

func _try_release_then_manifest_for_pull(sources: Array, idx: int, done: Callable) -> void:
	if idx >= sources.size():
		var ms := _build_manifest_urls()
		_try_manifest_for_pull(ms, 0, done)
		return
	var src: Dictionary = sources[idx]
	_http_get_text(String(src.url), PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: Aethera-RPG-Updater/1.0"]), func(ok_flag: bool, body: String, _code: int):
		if ok_flag and body.strip_edges() != "":
			var parsed = JSON.parse_string(body)
			if parsed is Dictionary and (parsed.has("tag_name") or parsed.has("name")):
				_apply_release_payload(parsed, String(src.name))
				done.call(true, "")
				return
		_try_release_then_manifest_for_pull(sources, idx + 1, done)
	)

func _try_manifest_for_pull(sources: Array, idx: int, done: Callable) -> void:
	if idx >= sources.size():
		done.call(false, "拉取失败：无法连接 GitHub / 镜像源")
		return
	var src: Dictionary = sources[idx]
	_http_get_text(String(src.url), PackedStringArray(["Accept: application/json", "User-Agent: Aethera-RPG-Updater/1.0"]), func(ok_flag: bool, body: String, _code: int):
		if ok_flag and body.strip_edges() != "":
			var parsed = JSON.parse_string(body)
			if parsed is Dictionary and String(parsed.get("version", "")).strip_edges() != "":
				_apply_manifest_payload(parsed, String(src.name))
				done.call(true, "")
				return
		_try_manifest_for_pull(sources, idx + 1, done)
	)

func _try_pull_checksums(done: Callable) -> void:
	var csum_url := ""
	for a in release_assets:
		var low := String(a.get("name", "")).to_lower()
		if low in ["checksums.txt", "sha256sums.txt", "sha256.txt"] or low.ends_with(".sha256"):
			csum_url = String(a.get("url", ""))
			break
	if csum_url == "":
		done.call()
		return
	var dl_url := _apply_mirror_to_url(csum_url) if use_mirror else csum_url
	_http_get_text(dl_url, PackedStringArray(["User-Agent: Aethera-RPG-Updater/1.0"]), func(ok_c: bool, txt: String, _code: int):
		if ok_c and txt.strip_edges() != "":
			remote_checksums = _parse_checksums(txt)
		done.call()
	)

static func _parse_checksums(txt: String) -> Dictionary:
	var out := {}
	for raw_ln in txt.split("\n"):
		var ln := raw_ln.strip_edges()
		if ln == "": continue
		var parts := ln.split(" ", false)
		if parts.size() >= 2 and String(parts[0]).length() == 64:
			var fname := String(parts[parts.size() - 1]).trim_prefix("*").get_file()
			out[fname] = String(parts[0]).to_lower()
	return out

func _apply_mirror_to_url(url: String) -> String:
	if url.begins_with(GH_MIRROR_PREFIX):
		return url
	if url.begins_with("https://github.com/") or url.begins_with("https://raw.githubusercontent.com/") or url.begins_with("https://api.github.com/"):
		return GH_MIRROR_PREFIX + url
	return url

func preferred_download_dir() -> String:
	if updates_dir_override != "":
		return _updates_dir()
	var sys_dl := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if sys_dl != "" and detect_platform_key() != "android":
		var cand := sys_dl.path_join("Aethera_Updates")
		if DirAccess.make_dir_recursive_absolute(cand) == OK:
			return cand if cand.ends_with("/") else cand + "/"
	_ensure_updates_dir()
	return _updates_dir()

func _safe_filename(name_in: String) -> String:
	var out := name_in.get_file().strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		out = out.replace(ch, "_")
	return out if out != "" else "aethera_update.bin"

func download_recommended(cb := Callable()) -> void:
	var asset := recommended_asset()
	if asset.is_empty():
		status_text = "当前 Release 未附带可下载安装包，请在 GitHub Release 上传 .apk / .zip / .pck"
		changed.emit()
		if cb.is_valid(): cb.call(false, "", status_text)
		return
	download_asset(asset, cb)

func download_asset(asset: Dictionary, cb := Callable()) -> void:
	if downloading:
		return
	var raw_url := String(asset.get("url", "")).strip_edges()
	var fname := _safe_filename(String(asset.get("name", "update.bin")))
	var expected_sz := int(asset.get("size", 0))
	if raw_url == "":
		status_text = "无效的下载地址"
		changed.emit()
		if cb.is_valid(): cb.call(false, "", status_text)
		return
	var save_dir := preferred_download_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir) if save_dir.begins_with("user://") else save_dir)
	var dest_path := save_dir.path_join(fname)
	downloading = true
	downloaded_bytes = 0
	total_bytes = expected_sz
	downloaded_file_path = ""
	downloaded_sha256 = ""
	downloaded_asset_url = _apply_mirror_to_url(raw_url) if use_mirror else raw_url
	status_text = "正在下载 %s…" % fname
	changed.emit()
	progress_changed.emit(0, maxi(expected_sz, 1), 0.0)

	if mock_transport.is_valid():
		var res = mock_transport.call("DOWNLOAD", downloaded_asset_url, {"filename": fname, "dest": dest_path})
		downloading = false
		if res is Dictionary and int(res.get("status", 200)) >= 200 and int(res.get("status", 200)) < 300:
			var data_bytes: PackedByteArray = res.get("bytes", PackedByteArray())
			var fw := FileAccess.open(dest_path, FileAccess.WRITE)
			if fw:
				fw.store_buffer(data_bytes)
				fw.close()
				downloaded_bytes = data_bytes.size()
				total_bytes = data_bytes.size()
				_finalize_download(dest_path, fname, cb)
				return
		status_text = "下载失败：测试传输异常"
		changed.emit()
		if cb.is_valid(): cb.call(false, "", status_text)
		return

	var urls := [downloaded_asset_url]
	var alt_url := raw_url if use_mirror else _apply_mirror_to_url(raw_url)
	if alt_url != downloaded_asset_url:
		urls.append(alt_url)
	_start_download_try(urls, 0, dest_path, fname, expected_sz, cb)

func _start_download_try(urls: Array, idx: int, dest_path: String, fname: String, expected_sz: int, cb: Callable) -> void:
	if idx >= urls.size():
		downloading = false
		_dl_req = null
		status_text = "下载失败：请检查网络连接或切换镜像后重试（也可点击浏览器下载）"
		changed.emit()
		if cb.is_valid(): cb.call(false, "", status_text)
		return
	var u := String(urls[idx])
	var req := HTTPRequest.new()
	req.timeout = 120.0
	req.use_threads = true
	req.download_file = ProjectSettings.globalize_path(dest_path) if dest_path.begins_with("user://") else dest_path
	add_child(req)
	_dl_req = req
	req.request_completed.connect(func(result: int, code: int, _hdrs: PackedStringArray, _body: PackedByteArray):
		var was_same := (_dl_req == req)
		if was_same:
			_dl_req = null
		req.queue_free()
		if not downloading:
			return
		if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and FileAccess.file_exists(dest_path):
			downloading = false
			downloaded_asset_url = u
			_finalize_download(dest_path, fname, cb)
		else:
			_start_download_try(urls, idx + 1, dest_path, fname, expected_sz, cb)
	, CONNECT_ONE_SHOT)
	var err := req.request(u, PackedStringArray(["User-Agent: Aethera-RPG-Updater/1.0"]), HTTPClient.METHOD_GET)
	if err != OK:
		if _dl_req == req: _dl_req = null
		req.queue_free()
		_start_download_try(urls, idx + 1, dest_path, fname, expected_sz, cb)

func _process(_d: float) -> void:
	if downloading and is_instance_valid(_dl_req):
		var got := _dl_req.get_downloaded_bytes()
		var tot := _dl_req.get_body_size()
		if tot <= 0 and total_bytes > 0:
			tot = total_bytes
		if got != downloaded_bytes or (tot > 0 and tot != total_bytes):
			downloaded_bytes = got
			if tot > 0: total_bytes = tot
			var ratio := clampf(float(got) / float(maxi(total_bytes, 1)), 0.0, 1.0)
			progress_changed.emit(got, total_bytes, ratio)

func cancel_download() -> void:
	downloading = false
	if is_instance_valid(_dl_req):
		_dl_req.cancel_request()
		_dl_req.queue_free()
	_dl_req = null
	status_text = "已取消下载"
	changed.emit()

func _finalize_download(dest_path: String, fname: String, cb: Callable) -> void:
	var f := FileAccess.open(dest_path, FileAccess.READ)
	var sz := int(f.get_length()) if f else 0
	if f: f.close()
	downloaded_bytes = sz
	if total_bytes <= 0: total_bytes = sz
	downloaded_sha256 = _file_sha256(dest_path)
	if remote_checksums.has(fname):
		var want_sha := String(remote_checksums[fname]).to_lower()
		if downloaded_sha256 != want_sha:
			downloaded_file_path = ""
			status_text = "下载文件 SHA256 校验失败，请重新下载"
			changed.emit()
			if cb.is_valid(): cb.call(false, "", status_text)
			return
	downloaded_file_path = dest_path
	var low := fname.to_lower()
	if low.ends_with(".pck") and latest_version != "":
		status_text = "已下载热更补丁 %s（%.1f MB），点击「启用补丁并重启生效」" % [fname, float(sz) / 1048576.0]
	elif low.ends_with(".apk"):
		status_text = "APK 已下载完成：%s（%.1f MB）" % [fname, float(sz) / 1048576.0]
	else:
		status_text = "更新包已下载：%s（%.1f MB）" % [fname, float(sz) / 1048576.0]
	save_config()
	progress_changed.emit(sz, maxi(sz, 1), 1.0)
	changed.emit()
	if cb.is_valid(): cb.call(true, dest_path, status_text)

static func _file_sha256(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var chunk := f.get_buffer(65536)
		if chunk.is_empty(): break
		ctx.update(chunk)
	f.close()
	return ctx.finish().hex_encode().to_lower()

func apply_downloaded_pck_patch() -> Dictionary:
	if downloaded_file_path == "" or not downloaded_file_path.to_lower().ends_with(".pck"):
		return {"ok": false, "message": "未检测到已下载的 .pck 热更补丁"}
	var udir := _updates_dir()
	_ensure_updates_dir()
	var staged := udir + "active_patch.pck"
	var src_abs := ProjectSettings.globalize_path(downloaded_file_path) if downloaded_file_path.begins_with("user://") else downloaded_file_path
	var dst_abs := ProjectSettings.globalize_path(staged)
	if src_abs != dst_abs:
		var err := DirAccess.copy_absolute(src_abs, dst_abs)
		if err != OK:
			return {"ok": false, "message": "写入补丁目录失败 (err=%d)" % err}
	active_pck_path = staged
	installed_patch_version = latest_version if latest_version != "" else local_version()
	update_available = false
	status_text = "已启用补丁 v%s（下次启动或重启游戏后自动挂载）" % installed_patch_version
	save_config()
	changed.emit()
	return {"ok": true, "path": staged, "version": installed_patch_version, "message": status_text}

func open_downloaded_package() -> bool:
	if downloaded_file_path == "" or not FileAccess.file_exists(downloaded_file_path):
		return false
	var abs_p := ProjectSettings.globalize_path(downloaded_file_path) if downloaded_file_path.begins_with("user://") else downloaded_file_path
	return OS.shell_open(abs_p) == OK

func apply_windows_exe_update() -> Dictionary:
	if OS.get_name() != "Windows":
		return {"ok": false, "message": "仅 Windows 端支持 .exe 覆盖重启更新"}
	if downloaded_file_path == "" or not downloaded_file_path.to_lower().ends_with(".exe") or not FileAccess.file_exists(downloaded_file_path):
		return {"ok": false, "message": "未检测到已下载的 .exe 安装包"}
	var src_abs := ProjectSettings.globalize_path(downloaded_file_path) if downloaded_file_path.begins_with("user://") else downloaded_file_path
	if OS.has_feature("editor"):
		var ok_open := OS.shell_open(src_abs) == OK
		return {"ok": ok_open, "message": "编辑器环境下已直接启动新版安装包"}
	var target_exe := OS.get_executable_path()
	var pid := OS.get_process_id()
	var helper_ps1 := ProjectSettings.globalize_path("user://updates/_apply_exe_update.ps1")
	var ps_body := "\r\n".join([
		"$pidToWait = %d" % pid,
		"for ($i = 0; $i -lt 40; $i++) { if (-not (Get-Process -Id $pidToWait -ErrorAction SilentlyContinue)) { break }; Start-Sleep -Milliseconds 250 }",
		"Copy-Item -LiteralPath '%s' -Destination '%s' -Force" % [src_abs.replace("'", "''"), target_exe.replace("'", "''")],
		"Start-Process -FilePath '%s'" % target_exe.replace("'", "''"),
	])
	var hf := FileAccess.open("user://updates/_apply_exe_update.ps1", FileAccess.WRITE)
	if hf == null:
		return {"ok": false, "message": "无法写入更新脚本"}
	hf.store_string(ps_body)
	hf.close()
	var launch_id := OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", helper_ps1]))
	if launch_id < 0:
		return {"ok": false, "message": "启动 Windows 自动更新器失败，请手动运行安装包"}
	get_tree().call_deferred("quit")
	return {"ok": true, "message": "正在覆盖更新并重启新版程序…"}

func open_download_folder() -> bool:
	var dir_p := downloaded_file_path.get_base_dir() if downloaded_file_path != "" else preferred_download_dir()
	var abs_d := ProjectSettings.globalize_path(dir_p) if dir_p.begins_with("user://") else dir_p
	return OS.shell_open(abs_d) == OK

func open_browser_download() -> bool:
	var target := downloaded_asset_url
	if target == "":
		var asset := recommended_asset()
		target = String(asset.get("url", ""))
		if target != "" and use_mirror:
			target = _apply_mirror_to_url(target)
	if target == "":
		target = release_html_url if release_html_url != "" else ("https://github.com/%s/releases" % repo_slug() if is_repo_configured() else "https://github.com")
	return OS.shell_open(target) == OK
