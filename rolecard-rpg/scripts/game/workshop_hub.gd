extends Node
## In-game Hotaru Workshop (艾瑟拉创意工坊 / 荧荧工坊) service:
## - REST client for https://workshop.hotaruworkshop.l.cd (cardScope=aethera)
## - Discord OAuth loopback callback listener (http://127.0.0.1:<port>/ via system browser)
## - Local & cloud download warehouse ("我的仓库" / 管理面板)
## - JSON package import/export + Aethera import pipeline (刻印 -> user://workshop.json, 角色/阵营/事件/玩法/规则 -> user://worldbook_custom.json)

const DEFAULT_GATEWAY := "https://workshop.hotaruworkshop.l.cd"
const CARD_SCOPE := "aethera"
const SERIES := "aethera"
const BASE_DIR := "user://workshop_hub/"
const WORKSHOP_STORE := "user://workshop.json"
const AETHERA_NATIVE_CHARS := ["凛零", "梅林", "墨华", "冰糖", "安克", "卡斯特", "茧", "明空", "艾利丝", "路西法", "暧", "叶", "瓦尔基里"]

const CATEGORIES := [
	{"key": "all", "label": "全部"},
	{"key": "blueprint", "label": "刻印"},
	{"key": "character", "label": "角色"},
	{"key": "faction", "label": "阵营"},
	{"key": "event", "label": "事件"},
	{"key": "gameplay", "label": "玩法"},
	{"key": "rule", "label": "规则"},
	{"key": "other", "label": "其他"},
	{"key": "cosmetic_frontend", "label": "前端美化"},
]

signal changed
signal oauth_status(state: String, message: String)

var base_dir_override := ""
var workshop_store_override := ""
var mock_transport: Callable = Callable()

var gateway := DEFAULT_GATEWAY
var token := ""
var user: Dictionary = {}
var is_admin := false

var catalog: Array = []
var cloud_downloads: Array = []
var local_packs: Array = []
var fav_ids: Array = []
var mine_packages: Array = []
var installed: Dictionary = {"packages": {}, "dlc_characters": {}}
var last_error := ""
var catalog_loading := false
var repo_loading := false

var _oauth_server: TCPServer
var _oauth_peers: Array = []
var _oauth_key_raw := PackedByteArray()
var _oauth_key_b64 := ""
var _oauth_listening := false
var _oauth_deadline_msec := 0
var _oauth_port := 0
var _thumb_cache: Dictionary = {}
var _thumb_pending: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not UiHub.review_mode:
		load_state()

func _dir() -> String:
	var d := base_dir_override if base_dir_override != "" else BASE_DIR
	if not d.ends_with("/"): d += "/"
	return d

func _workshop_store_path() -> String:
	return workshop_store_override if workshop_store_override != "" else WORKSHOP_STORE

func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir() + "exports"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir() + "cache"))

func load_state() -> void:
	_ensure_dirs()
	var acc = _read_json(_dir() + "account.json", {})
	if acc is Dictionary:
		var gw := String(acc.get("gateway", DEFAULT_GATEWAY)).strip_edges().trim_suffix("/")
		gateway = gw if gw != "" else DEFAULT_GATEWAY
		token = String(acc.get("token", ""))
		user = acc.get("user", {}) if acc.get("user") is Dictionary else {}
		is_admin = bool(acc.get("admin", false))
	var lp = _read_json(_dir() + "local_packs.json", [])
	local_packs = lp if lp is Array else []
	var inst = _read_json(_dir() + "installed.json", {})
	if inst is Dictionary:
		installed = {
			"packages": inst.get("packages", {}) if inst.get("packages") is Dictionary else {},
			"dlc_characters": inst.get("dlc_characters", {}) if inst.get("dlc_characters") is Dictionary else {},
		}
	var fav = _read_json(_dir() + "favs.json", [])
	fav_ids = fav if fav is Array else []
	var cd = _read_json(_dir() + "cloud_downloads.json", [])
	cloud_downloads = cd if cd is Array else []
	changed.emit()

func save_account() -> void:
	if UiHub.review_mode and base_dir_override == "": return
	_ensure_dirs()
	_write_json(_dir() + "account.json", {
		"gateway": gateway,
		"token": token,
		"user": user,
		"admin": is_admin,
	})

func save_local_packs() -> void:
	if UiHub.review_mode and base_dir_override == "": return
	_ensure_dirs()
	_write_json(_dir() + "local_packs.json", local_packs)

func save_installed() -> void:
	if UiHub.review_mode and base_dir_override == "": return
	_ensure_dirs()
	_write_json(_dir() + "installed.json", installed)

func _save_favs() -> void:
	if UiHub.review_mode and base_dir_override == "": return
	_ensure_dirs()
	_write_json(_dir() + "favs.json", fav_ids)

func _save_cloud_downloads() -> void:
	if UiHub.review_mode and base_dir_override == "": return
	_ensure_dirs()
	_write_json(_dir() + "cloud_downloads.json", cloud_downloads)

func _read_json(path: String, fallback):
	if not FileAccess.file_exists(path): return fallback
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed != null else fallback

func _write_json(path: String, data) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func is_logged_in() -> bool:
	return token != "" and not user.is_empty()

func display_name() -> String:
	if user.is_empty(): return ""
	var dn := String(user.get("displayName", "")).strip_edges()
	return dn if dn != "" else String(user.get("username", ""))

static func category_label(key: String) -> String:
	var k := key.strip_edges()
	for it in CATEGORIES:
		if String(it.key) == k: return String(it.label)
	if k == "world_factor": return "世界因子"
	if k == "cosmetic_dialogue": return "对话美化"
	return k if k != "" else "其他"

static func cover_url_of(pkg: Dictionary) -> String:
	var u := String(pkg.get("imageUrl", "")).strip_edges()
	if u != "": return u
	var payload: Dictionary = pkg.get("payload", {}) if pkg.get("payload") is Dictionary else {}
	var extra: Dictionary = payload.get("extra", {}) if payload.get("extra") is Dictionary else {}
	u = String(extra.get("imageDailyUrl", "")).strip_edges()
	if u != "": return u
	return String(extra.get("imageFormUrl", "")).strip_edges()

static func summary_of(pkg: Dictionary) -> String:
	var s := String(pkg.get("summary", "")).strip_edges()
	if s != "": return s
	var payload: Dictionary = pkg.get("payload", {}) if pkg.get("payload") is Dictionary else {}
	var extra: Dictionary = payload.get("extra", {}) if payload.get("extra") is Dictionary else {}
	for k in ["desc", "overview", "content", "archive", "summary"]:
		var val := String(extra.get(k, "")).strip_edges()
		if val != "": return val.substr(0, 160)
	return String(pkg.get("title", ""))

# ---------------- HTTP transport ----------------
func _api(method: int, path: String, body = null, use_auth := true, cb := Callable()) -> void:
	var clean_path := path if path.begins_with("/") else ("/" + path)
	var url := gateway.trim_suffix("/") + clean_path
	var body_str := JSON.stringify(body) if body != null else ""
	if mock_transport.is_valid():
		var res: Variant = mock_transport.call(method, clean_path, body, token if use_auth else "")
		if res is Dictionary:
			var status := int(res.get("status", 200))
			var data: Variant = res.get("body", {})
			var ok_flag := status >= 200 and status < 300
			var err_msg := "" if ok_flag else _extract_err(data, status)
			if cb.is_valid(): cb.call(ok_flag, data, status, err_msg)
			return
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	var hdrs := PackedStringArray(["Accept: application/json"])
	if body != null: hdrs.append("Content-Type: application/json")
	if use_auth and token != "": hdrs.append("Authorization: Bearer " + token)
	req.request_completed.connect(func(result: int, code: int, _rh: PackedStringArray, raw_body: PackedByteArray):
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			var msg := "无法连接荧荧工坊服务器（请检查网络或代理设置）"
			if cb.is_valid(): cb.call(false, {}, 0, msg)
			return
		var txt := raw_body.get_string_from_utf8()
		var parsed = JSON.parse_string(txt) if txt.strip_edges() != "" else {}
		if parsed == null: parsed = {}
		var ok_flag := code >= 200 and code < 300
		var err_msg := "" if ok_flag else _extract_err(parsed, code)
		if (code == 401 or code == 403) and use_auth and token != "":
			if code == 401:
				token = ""; user = {}; is_admin = false; save_account(); changed.emit()
		if cb.is_valid(): cb.call(ok_flag, parsed, code, err_msg)
	, CONNECT_ONE_SHOT)
	var err := req.request(url, hdrs, method, body_str)
	if err != OK:
		req.queue_free()
		if cb.is_valid(): cb.call(false, {}, 0, "网络请求发起失败 (%d)" % err)

func _extract_err(parsed, code: int) -> String:
	if parsed is Dictionary:
		var errs = parsed.get("errors", [])
		if errs is Array and not errs.is_empty(): return String(errs[0])
		if parsed.has("error"): return String(parsed.get("error", ""))
	return "HTTP %d" % code

# ---------------- Cloud Workshop API ----------------
func refresh_catalog(cb := Callable()) -> void:
	catalog_loading = true
	last_error = ""
	changed.emit()
	_api(HTTPClient.METHOD_GET, "/api/workshop/packages?cardScope=" + CARD_SCOPE, null, true, func(ok_flag: bool, data, _code: int, err: String):
		catalog_loading = false
		if ok_flag and data is Dictionary and data.get("packages") is Array:
			var out: Array = []
			for p in data.packages:
				if p is Dictionary: out.append(p)
			catalog = out
			last_error = ""
		else:
			last_error = err if err != "" else "加载创意工坊列表失败"
		changed.emit()
		if cb.is_valid(): cb.call(ok_flag, err)
	)

func fetch_package_detail(pkg_id: String, cb: Callable) -> void:
	_api(HTTPClient.METHOD_GET, "/api/workshop/packages/" + pkg_id.uri_encode(), null, true, func(ok_flag: bool, data, _code: int, err: String):
		if ok_flag and data is Dictionary and data.get("package") is Dictionary:
			var pkg: Dictionary = data.package
			_update_catalog_cache(pkg)
			cb.call(true, pkg, "")
		else:
			cb.call(false, {}, err if err != "" else "读取作品详情失败")
	)

func _update_catalog_cache(pkg: Dictionary) -> void:
	var pid := String(pkg.get("id", ""))
	if pid == "": return
	for i in range(catalog.size()):
		if catalog[i] is Dictionary and String(catalog[i].get("id", "")) == pid:
			catalog[i] = pkg
			return

func download_package(pkg_or_id, cb := Callable()) -> void:
	var pkg: Dictionary = pkg_or_id if pkg_or_id is Dictionary else {}
	var pid := String(pkg.get("id", pkg_or_id if pkg_or_id is String else ""))
	if pid == "":
		if cb.is_valid(): cb.call(false, {}, "无效的作品 ID")
		return
	var has_payload: bool = pkg.get("payload") is Dictionary and not pkg.payload.is_empty()
	var after_detail := func(ok_d: bool, full_pkg: Dictionary, err_d: String) -> void:
		if not ok_d or full_pkg.is_empty():
			if cb.is_valid(): cb.call(false, {}, err_d if err_d != "" else "下载作品数据失败")
			return
		upsert_local_packs([full_pkg])
		if is_logged_in():
			_api(HTTPClient.METHOD_POST, "/api/workshop/me/downloads", {"packageId": pid}, true, func(ok_c: bool, d_c, _c: int, _e: String):
				if ok_c:
					_upsert_cloud_dl(full_pkg)
					if d_c is Dictionary and bool(d_c.get("added", false)):
						full_pkg["downloads"] = int(full_pkg.get("downloads", 0)) + 1
						_update_catalog_cache(full_pkg)
				changed.emit()
				if cb.is_valid(): cb.call(true, full_pkg, "")
			)
		else:
			changed.emit()
			if cb.is_valid(): cb.call(true, full_pkg, "")
	if has_payload:
		after_detail.call(true, pkg, "")
	else:
		fetch_package_detail(pid, after_detail)

func _upsert_cloud_dl(pkg: Dictionary) -> void:
	var pid := String(pkg.get("id", ""))
	for i in range(cloud_downloads.size()):
		if cloud_downloads[i] is Dictionary and String(cloud_downloads[i].get("id", "")) == pid:
			cloud_downloads[i] = pkg; _save_cloud_downloads(); return
	cloud_downloads.push_front(pkg)
	_save_cloud_downloads()

func sync_cloud_downloads(cb := Callable()) -> void:
	if not is_logged_in():
		if cb.is_valid(): cb.call(false, "请先登录 Discord 账号")
		return
	repo_loading = true
	changed.emit()
	_api(HTTPClient.METHOD_GET, "/api/workshop/me/downloads", null, true, func(ok_flag: bool, data, _code: int, err: String):
		repo_loading = false
		if ok_flag and data is Dictionary and data.get("downloads") is Array:
			var out: Array = []
			for p in data.downloads:
				if p is Dictionary and String(p.get("cardScope", "magic-fairy")) == CARD_SCOPE:
					out.append(p)
			cloud_downloads = out
			_save_cloud_downloads()
			# Cache full downloadable packages locally too so they work offline later
			if not out.is_empty(): upsert_local_packs(out)
		changed.emit()
		if cb.is_valid(): cb.call(ok_flag, err)
	)

func refresh_favorites(cb := Callable()) -> void:
	if not is_logged_in(): return
	_api(HTTPClient.METHOD_GET, "/api/workshop/me/favs", null, true, func(ok_flag: bool, data, _code: int, err: String):
		if ok_flag and data is Dictionary and data.get("favs") is Array:
			var next: Array = []
			for p in data.favs:
				if p is Dictionary and String(p.get("cardScope", "magic-fairy")) == CARD_SCOPE:
					next.append(String(p.get("id", "")))
			fav_ids = next
			_save_favs()
			changed.emit()
		if cb.is_valid(): cb.call(ok_flag, err)
	)

func toggle_favorite(pkg_id: String, cb := Callable()) -> void:
	if not is_logged_in():
		if cb.is_valid(): cb.call(false, false, "收藏需要先登录 Discord 账号")
		return
	var on := not (pkg_id in fav_ids)
	var method := HTTPClient.METHOD_POST if on else HTTPClient.METHOD_DELETE
	var path := "/api/workshop/me/favs" if on else ("/api/workshop/me/favs/" + pkg_id.uri_encode())
	var body = {"packageId": pkg_id} if on else null
	_api(method, path, body, true, func(ok_flag: bool, _d, _c: int, err: String):
		if ok_flag:
			if on and not (pkg_id in fav_ids): fav_ids.append(pkg_id)
			elif not on: fav_ids = fav_ids.filter(func(x): return String(x) != pkg_id)
			_save_favs()
			changed.emit()
		if cb.is_valid(): cb.call(ok_flag, on, err)
	)

func refresh_mine(cb := Callable()) -> void:
	if not is_logged_in(): return
	_api(HTTPClient.METHOD_GET, "/api/workshop/packages?mine=1&cardScope=" + CARD_SCOPE, null, true, func(ok_flag: bool, data, _code: int, err: String):
		if ok_flag and data is Dictionary and data.get("packages") is Array:
			var out: Array = []
			for p in data.packages:
				if p is Dictionary: out.append(p)
			mine_packages = out
			changed.emit()
		if cb.is_valid(): cb.call(ok_flag, err)
	)

func publish_package(pkg_body: Dictionary, cb := Callable()) -> void:
	if not is_logged_in():
		if cb.is_valid(): cb.call(false, {}, "上传作品需要先登录 Discord 账号")
		return
	var body := pkg_body.duplicate(true)
	body["packageVersion"] = "1.0.0"
	body["series"] = SERIES
	body["cardScope"] = CARD_SCOPE
	_api(HTTPClient.METHOD_POST, "/api/workshop/packages", body, true, func(ok_flag: bool, data, _code: int, err: String):
		if ok_flag and data is Dictionary and data.get("package") is Dictionary:
			var created: Dictionary = data.package
			catalog.push_front(created)
			mine_packages.push_front(created)
			changed.emit()
			if cb.is_valid(): cb.call(true, created, "")
		else:
			if cb.is_valid(): cb.call(false, {}, err if err != "" else "发布失败")
	)

func delete_cloud_package(pkg_id: String, cb := Callable()) -> void:
	if not is_logged_in():
		if cb.is_valid(): cb.call(false, "需要先登录")
		return
	_api(HTTPClient.METHOD_DELETE, "/api/workshop/packages/" + pkg_id.uri_encode(), null, true, func(ok_flag: bool, _d, _c: int, err: String):
		if ok_flag:
			catalog = catalog.filter(func(p): return String(p.get("id", "")) != pkg_id)
			mine_packages = mine_packages.filter(func(p): return String(p.get("id", "")) != pkg_id)
			changed.emit()
		if cb.is_valid(): cb.call(ok_flag, err)
	)

func remove_repo_package(pkg_id: String, cb := Callable()) -> void:
	local_packs = local_packs.filter(func(p): return String(p.get("id", "")) != pkg_id)
	save_local_packs()
	var was_cloud := cloud_downloads.any(func(p): return p is Dictionary and String(p.get("id", "")) == pkg_id)
	cloud_downloads = cloud_downloads.filter(func(p): return String(p.get("id", "")) != pkg_id)
	_save_cloud_downloads()
	if was_cloud and is_logged_in():
		_api(HTTPClient.METHOD_DELETE, "/api/workshop/me/downloads/" + pkg_id.uri_encode(), null, true, func(_ok: bool, _d, _c: int, _e: String):
			changed.emit()
			if cb.is_valid(): cb.call(true)
		)
	else:
		changed.emit()
		if cb.is_valid(): cb.call(true)

func set_manual_token(raw_token: String, cb := Callable()) -> void:
	var clean := raw_token.strip_edges()
	if clean == "":
		if cb.is_valid(): cb.call(false, "令牌不能为空")
		return
	token = clean
	_api(HTTPClient.METHOD_GET, "/api/workshop/me", null, true, func(ok_flag: bool, data, _code: int, err: String):
		if ok_flag and data is Dictionary and bool(data.get("loggedIn", false)):
			user = data.get("user", {}) if data.get("user") is Dictionary else {}
			is_admin = bool(data.get("admin", false))
			save_account()
			sync_cloud_downloads()
			refresh_favorites()
			changed.emit()
			if cb.is_valid(): cb.call(true, "")
		else:
			token = ""; user = {}; is_admin = false
			save_account(); changed.emit()
			if cb.is_valid(): cb.call(false, err if err != "" else "会话令牌无效或已过期")
	)

func logout() -> void:
	var old_t := token
	token = ""; user = {}; is_admin = false
	cloud_downloads.clear(); fav_ids.clear(); mine_packages.clear()
	save_account(); _save_cloud_downloads(); _save_favs()
	changed.emit()
	if old_t != "":
		var req := HTTPRequest.new(); req.timeout = 8.0; add_child(req)
		req.request_completed.connect(func(_r, _c, _h, _b): req.queue_free(), CONNECT_ONE_SHOT)
		req.request(gateway.trim_suffix("/") + "/api/workshop/discord/logout", PackedStringArray(["Authorization: Bearer " + old_t, "Content-Type: application/json"]), HTTPClient.METHOD_POST, "{}")

# ---------------- Loopback Discord OAuth ----------------
func cancel_login() -> void:
	_stop_oauth_server()
	oauth_status.emit("idle", "")

func begin_discord_login() -> void:
	if _oauth_listening: cancel_login()
	oauth_status.emit("pending", "正在连接工坊获取 Discord 登录入口…")
	_api(HTTPClient.METHOD_GET, "/api/workshop/health", null, false, func(ok_flag: bool, data, _code: int, err: String):
		if not ok_flag or not (data is Dictionary):
			oauth_status.emit("error", err if err != "" else "无法读取工坊登录配置")
			return
		var oa: Dictionary = data.get("oauth", {}) if data.get("oauth") is Dictionary else {}
		var start_url := String(oa.get("startUrl", "")).strip_edges()
		if not bool(oa.get("configured", false)) or start_url == "":
			oauth_status.emit("error", "云端工坊尚未配置 Discord 登录入口")
			return
		var started := _start_oauth_loopback()
		if not started.ok:
			oauth_status.emit("error", String(started.error))
			return
		var origin_url := "http://127.0.0.1:%d" % _oauth_port
		var full_url := "%s?origin=%s&return=%s&k=%s" % [start_url, origin_url.uri_encode(), "/".uri_encode(), _oauth_key_b64.uri_encode()]
		OS.shell_open(full_url)
		oauth_status.emit("waiting", "已打开系统浏览器前往 Discord 授权，完成后将自动传回游戏…")
	)

func _b64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

func _start_oauth_loopback() -> Dictionary:
	_stop_oauth_server()
	_oauth_server = TCPServer.new()
	var err := _oauth_server.listen(0, "127.0.0.1")
	if err != OK:
		_oauth_server = null
		return {"ok": false, "error": "本地回调端口启动失败 (%d)，可使用手动令牌或文件导入" % err}
	_oauth_port = _oauth_server.get_local_port()
	var cr := Crypto.new()
	_oauth_key_raw = cr.generate_random_bytes(32)
	_oauth_key_b64 = _b64url(_oauth_key_raw)
	_oauth_listening = true
	_oauth_deadline_msec = Time.get_ticks_msec() + 180000
	return {"ok": true, "port": _oauth_port}

func _stop_oauth_server() -> void:
	_oauth_listening = false
	for item in _oauth_peers:
		var peer: StreamPeerTCP = item.get("peer")
		if peer != null: peer.disconnect_from_host()
	_oauth_peers.clear()
	if _oauth_server != null:
		_oauth_server.stop()
		_oauth_server = null
	_oauth_key_raw = PackedByteArray()
	_oauth_key_b64 = ""

func _process(_delta: float) -> void:
	if not _oauth_listening or _oauth_server == null: return
	if Time.get_ticks_msec() > _oauth_deadline_msec:
		_stop_oauth_server()
		oauth_status.emit("error", "Discord 登录超时，请重试")
		return
	while _oauth_server.is_connection_available():
		var peer := _oauth_server.take_connection()
		if peer != null:
			_oauth_peers.append({"peer": peer, "buf": PackedByteArray()})
	var keep: Array = []
	for item in _oauth_peers:
		var peer: StreamPeerTCP = item.peer
		peer.poll()
		var st := peer.get_status()
		if st == StreamPeerTCP.STATUS_ERROR or st == StreamPeerTCP.STATUS_NONE:
			continue
		var avail := peer.get_available_bytes()
		if avail > 0:
			var chunk: Array = peer.get_data(avail)
			if int(chunk[0]) == OK and chunk[1] is PackedByteArray:
				var buf: PackedByteArray = item.buf
				buf.append_array(chunk[1])
				item.buf = buf
		if _try_handle_oauth_http(item):
			peer.disconnect_from_host()
		else:
			keep.append(item)
	_oauth_peers = keep

func _try_handle_oauth_http(item: Dictionary) -> bool:
	var raw: String = (item.buf as PackedByteArray).get_string_from_utf8()
	var hdr_end := raw.find("\r\n\r\n")
	if hdr_end < 0: return false
	var hdr_block := raw.substr(0, hdr_end)
	var first_line := hdr_block.get_slice("\r\n", 0)
	var method := first_line.get_slice(" ", 0).to_upper()
	var target := first_line.get_slice(" ", 1).get_slice("?", 0)
	var clen := 0
	for ln in hdr_block.split("\r\n"):
		if ln.to_lower().begins_with("content-length:"):
			clen = int(ln.substr(15).strip_edges())
	var body_start_bytes := raw.substr(0, hdr_end + 4).to_utf8_buffer().size()
	var total_bytes := (item.buf as PackedByteArray).size()
	if method == "POST" and total_bytes < body_start_bytes + clen:
		return false
	var peer: StreamPeerTCP = item.peer
	if method == "POST" and target == "/cb":
		var body_bytes := (item.buf as PackedByteArray).slice(body_start_bytes, body_start_bytes + clen)
		var parsed = JSON.parse_string(body_bytes.get_string_from_utf8())
		_send_http_resp(peer, "200 OK", "application/json; charset=utf-8", "{\"ok\":true}")
		var ticket := String(parsed.get("ticket", "")) if parsed is Dictionary else ""
		var err_txt := String(parsed.get("error", "")) if parsed is Dictionary else ""
		call_deferred("_finish_loopback_oauth", ticket, err_txt)
		return true
	if target == "/" or target == "/index.html":
		_send_http_resp(peer, "200 OK", "text/html; charset=utf-8", _oauth_callback_html())
		return true
	_send_http_resp(peer, "204 No Content", "text/plain; charset=utf-8", "")
	return true

func _send_http_resp(peer: StreamPeerTCP, status: String, ctype: String, body: String) -> void:
	var b := body.to_utf8_buffer()
	var head := "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [status, ctype, b.size()]
	peer.put_data(head.to_utf8_buffer())
	if not b.is_empty(): peer.put_data(b)

func _oauth_callback_html() -> String:
	var key_b64 := _oauth_key_b64
	return """<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><title>艾瑟拉 · 荧荧工坊授权</title>
<style>body{font-family:system-ui,-apple-system,sans-serif;background:#0d1322;color:#ece5d2;display:grid;place-items:center;min-height:100vh;margin:0}
.box{max-width:460px;padding:28px;border:1px solid rgba(224,186,100,.4);border-radius:16px;background:#182238;text-align:center}
h2{margin:0 0 12px;color:#e0ba64}p{margin:0;line-height:1.7;color:#b3aa93}</style></head>
<body><div class="box"><h2 id="t">正在完成授权…</h2><p id="m">请稍候，正在将登录凭据传回《艾瑟拉》游戏客户端。</p></div>
<script>(async function(){
const tEl=document.getElementById('t'),mEl=document.getElementById('m');
function ub64(s){const b=s.replace(/-/g,'+').replace(/_/g,'/');const bin=atob(b);const u=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);return u;}
try{
  const h=location.hash||'';
  if(h.includes('mf-auth-error=')){
    const err=decodeURIComponent(h.split('mf-auth-error=')[1]||'登录失败');
    await fetch('/cb',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({error:err})});
    tEl.textContent='授权已取消或失败';mEl.textContent=err;return;
  }
  if(!h.includes('mf-auth=')){
    await fetch('/cb',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({error:'未收到授权回执'})});
    tEl.textContent='未收到回执';mEl.textContent='请回到游戏重试登录。';return;
  }
  const cipher=h.split('mf-auth=')[1];
  const k=ub64('%s');
  const rk=await crypto.subtle.importKey('raw',k,{name:'AES-GCM'},false,['decrypt']);
  const buf=ub64(cipher),iv=buf.subarray(0,12),data=buf.subarray(12,buf.length-16),tag=buf.subarray(buf.length-16);
  const comb=new Uint8Array(data.length+tag.length);comb.set(data,0);comb.set(tag,data.length);
  const plain=await crypto.subtle.decrypt({name:'AES-GCM',iv:iv,tagLength:128},rk,comb);
  const payload=JSON.parse(new TextDecoder().decode(plain));
  await fetch('/cb',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ticket:payload.ticket||''})});
  tEl.textContent='登录成功';mEl.textContent='授权已安全传回《艾瑟拉》，请切回游戏窗口，本页面可关闭。';
  setTimeout(()=>{try{window.close();}catch(e){}},600);
}catch(e){
  await fetch('/cb',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({error:String(e&&e.message||e)})});
  tEl.textContent='授权解析失败';mEl.textContent=String(e&&e.message||e);
}})();</script></body></html>""" % key_b64

func _finish_loopback_oauth(ticket: String, err_txt: String) -> void:
	_stop_oauth_server()
	if err_txt != "":
		oauth_status.emit("error", err_txt)
		return
	if ticket == "":
		oauth_status.emit("error", "未获取到有效的登录票据")
		return
	oauth_status.emit("claiming", "正在向荧荧工坊换取会话…")
	_api(HTTPClient.METHOD_POST, "/api/workshop/discord/claim", {"ticket": ticket}, false, func(ok_flag: bool, data, _code: int, err: String):
		if ok_flag and data is Dictionary and String(data.get("token", "")) != "":
			token = String(data.token)
			user = data.get("user", {}) if data.get("user") is Dictionary else {}
			is_admin = bool(data.get("admin", false))
			save_account()
			sync_cloud_downloads()
			refresh_favorites()
			changed.emit()
			oauth_status.emit("ok", "登录成功 · 欢迎 " + display_name())
		else:
			oauth_status.emit("error", err if err != "" else "会话换取失败")
	)

# ---------------- Warehouse (Local + Cloud merge) & File Import/Export ----------------
func repo_packages() -> Array:
	# Merge cloud downloads + local packs (filtered to aethera)
	var by_id := {}
	var order: Array = []
	for p in local_packs:
		if not p is Dictionary: continue
		var pid := String(p.get("id", ""))
		if pid == "": continue
		var item: Dictionary = p.duplicate(true)
		item["_in_local"] = true
		item["_in_cloud"] = false
		by_id[pid] = item
		order.append(pid)
	for p in cloud_downloads:
		if not p is Dictionary: continue
		if String(p.get("cardScope", "magic-fairy")) != CARD_SCOPE: continue
		var pid := String(p.get("id", ""))
		if pid == "": continue
		if by_id.has(pid):
			by_id[pid]["_in_cloud"] = true
			if not (by_id[pid].get("payload") is Dictionary) or by_id[pid].payload.is_empty():
				by_id[pid]["payload"] = p.get("payload", {})
		else:
			var item: Dictionary = p.duplicate(true)
			item["_in_local"] = false
			item["_in_cloud"] = true
			by_id[pid] = item
			order.append(pid)
	var out: Array = []
	for pid in order: out.append(by_id[pid])
	return out

func upsert_local_packs(incoming: Array) -> int:
	var added_or_updated := 0
	for raw_p in incoming:
		if not raw_p is Dictionary: continue
		var p: Dictionary = raw_p.duplicate(true)
		var pid := String(p.get("id", "")).strip_edges()
		if pid == "":
			pid = "local.%d.%s" % [Time.get_unix_time_from_system(), str(randi() % 100000)]
			p["id"] = pid
		if not p.has("cardScope") or String(p.get("cardScope", "")) == "":
			p["cardScope"] = CARD_SCOPE
		var hit := -1
		for i in range(local_packs.size()):
			if local_packs[i] is Dictionary and String(local_packs[i].get("id", "")) == pid:
				hit = i; break
		if hit >= 0: local_packs[hit] = p
		else: local_packs.append(p)
		added_or_updated += 1
	save_local_packs()
	return added_or_updated

func parse_import_json(raw_text: String) -> Dictionary:
	var data = JSON.parse_string(raw_text)
	if data == null:
		return {"ok": false, "packages": [], "error": "不是合法的 JSON 文件"}
	var packs: Array = []
	if data is Dictionary and String(data.get("kind", "")) == "hotaru-workshop-package" and data.get("package") is Dictionary:
		packs.append(data.package)
	elif data is Dictionary and String(data.get("format", "")) == "academy-sigil-archive" and data.get("saved") is Array:
		var saved_arr: Array = data.saved
		if saved_arr.is_empty():
			return {"ok": false, "packages": [], "error": "刻印存档文件里没有已保存的魔法"}
		var first_s: Dictionary = saved_arr[0] if saved_arr[0] is Dictionary else {}
		var title := String(first_s.get("name", data.get("draft", {}).get("name", "导入刻印"))).strip_edges()
		if title == "": title = "导入刻印"
		var sig := ("local.sigil." + JSON.stringify(saved_arr).sha256_text().substr(0, 12))
		packs.append({
			"packageVersion": "1.0.0",
			"id": sig,
			"series": SERIES,
			"cardScope": CARD_SCOPE,
			"category": "blueprint",
			"type": "blueprint",
			"title": title,
			"publisher": {"displayName": "本地刻印存档"},
			"payload": {"extra": {"desc": String(first_s.get("effect", "")), "sigilArchive": data}},
			"revision": 1,
		})
	elif data is Array:
		for x in data:
			if x is Dictionary and (x.has("title") or x.has("payload")): packs.append(x)
	elif data is Dictionary and data.get("packages") is Array:
		for x in data.packages:
			if x is Dictionary and (x.has("title") or x.has("payload")): packs.append(x)
	elif data is Dictionary and data.get("package") is Dictionary:
		packs.append(data.package)
	elif data is Dictionary and (data.has("title") or data.has("payload")):
		packs.append(data)
	if packs.is_empty():
		return {"ok": false, "packages": [], "error": "文件里没有可识别的创意工坊作品或刻印存档"}
	return {"ok": true, "packages": packs, "error": ""}

func import_local_file(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {"ok": false, "added": 0, "error": "找不到文件：" + file_path}
	var res := parse_import_json(FileAccess.get_file_as_string(file_path))
	if not bool(res.ok):
		return {"ok": false, "added": 0, "error": String(res.error)}
	var count := upsert_local_packs(res.packages)
	changed.emit()
	return {"ok": true, "added": count, "packages": res.packages, "error": ""}

func export_package_file(pkg: Dictionary) -> String:
	_ensure_dirs()
	var title := String(pkg.get("title", "workshop")).strip_edges()
	for ch in ["\\", "/", ":", "*", "?", "\"", "<", ">", "|", " "]:
		title = title.replace(ch, "_")
	if title == "": title = "package"
	title = title.substr(0, 40)
	var out_path := _dir() + "exports/hotaru-%s.json" % title
	var payload := {
		"kind": "hotaru-workshop-package",
		"version": 1,
		"exportedAt": Time.get_datetime_string_from_system(false, true),
		"package": pkg,
	}
	_write_json(out_path, payload)
	return ProjectSettings.globalize_path(out_path)

# ---------------- Aethera Game Import Pipeline ----------------
func is_installed(pkg_id: String) -> bool:
	return installed.get("packages", {}).has(pkg_id)

func import_packages_into_game(pkgs: Array) -> Dictionary:
	var DataCls = preload("res://scripts/ui/ui_data.gd")
	var WorkshopCls = preload("res://scripts/ui/screens/workshop_screen.gd")
	var wb_custom: Array = DataCls.custom_worldbook_entries().duplicate(true)
	var inst_pkgs: Dictionary = installed.get("packages", {})
	var dlc_chars: Dictionary = installed.get("dlc_characters", {})
	var skipped: Array = []
	var sigil_added := 0
	var wb_added := 0
	var ok_titles: Array = []

	for raw_pkg in pkgs:
		if not raw_pkg is Dictionary: continue
		var pkg: Dictionary = raw_pkg
		var pid := String(pkg.get("id", ""))
		var title := String(pkg.get("title", pid)).strip_edges()
		var cat := String(pkg.get("category", pkg.get("type", "")))
		var payload: Dictionary = pkg.get("payload", {}) if pkg.get("payload") is Dictionary else {}
		var extra: Dictionary = payload.get("extra", {}) if payload.get("extra") is Dictionary else {}

		if cat == "blueprint":
			var arch: Variant = extra.get("sigilArchive", payload.get("sigilArchive", null))
			if not (arch is Dictionary) or String(arch.get("format", "")) != "academy-sigil-archive" or int(arch.get("version", 0)) != 3 or not (arch.get("saved") is Array):
				skipped.append("%s：作品里没有有效的 v3 刻印存档" % title); continue
			var incoming: Array = []
			for m in arch.saved:
				if m is Dictionary and m.get("parts") is Array and not m.parts.is_empty():
					incoming.append(m)
			if incoming.is_empty():
				skipped.append("%s：刻印存档为空" % title); continue
			var cur_store = _read_json(_workshop_store_path(), {"draft": {"name": "", "carrier": "", "effect": "", "parts": []}, "saved": []})
			if not cur_store is Dictionary: cur_store = {"draft": {"name": "", "carrier": "", "effect": "", "parts": []}, "saved": []}
			var cur_saved: Array = cur_store.get("saved", []).duplicate(true) if cur_store.get("saved") is Array else []
			var imported_ids: Array = []
			for raw_m in incoming:
				var cleaned: Dictionary = WorkshopCls.clean_sigil_record(raw_m)
				var mid := String(cleaned.get("id", ""))
				if mid == "":
					mid = "ws_%s" % str(cleaned.get("name", title)).sha256_text().substr(0, 10)
					cleaned["id"] = mid
				imported_ids.append(mid)
				var rep := -1
				for i in range(cur_saved.size()):
					if cur_saved[i] is Dictionary and (String(cur_saved[i].get("id", "")) == mid or (mid == "" and String(cur_saved[i].get("name", "")) == String(cleaned.get("name", "")))):
						rep = i; break
				if rep >= 0: cur_saved[rep] = cleaned
				else: cur_saved.push_front(cleaned)
				sigil_added += 1
			var cur_draft: Dictionary = cur_store.get("draft", {}) if cur_store.get("draft") is Dictionary else {}
			if (not (cur_draft.get("parts") is Array) or cur_draft.parts.is_empty()) and arch.get("draft") is Dictionary:
				cur_store["draft"] = WorkshopCls.clean_sigil_record(arch.draft)
			cur_store["saved"] = cur_saved
			_write_json(_workshop_store_path(), cur_store)
			inst_pkgs[pid] = {
				"id": pid, "title": title, "category": cat, "revision": int(pkg.get("revision", 1)),
				"sigil_ids": imported_ids, "imported_at": Time.get_datetime_string_from_system(false, true),
			}
			ok_titles.append(title)

		elif cat == "character":
			var rns: Array = extra.get("roleNames", []) if extra.get("roleNames") is Array else []
			if rns.is_empty():
				skipped.append("%s：缺少角色名（控制器），无法导入" % title); continue
			var clash := false
			for rn_raw in rns:
				var rn := String(rn_raw).strip_edges()
				if rn in AETHERA_NATIVE_CHARS or DataCls.id_of(rn) != "":
					skipped.append("%s：「%s」为原生角色名，不能覆盖" % [title, rn]); clash = true; break
			if clash: continue
			var overview := String(extra.get("overview", extra.get("intro", ""))).strip_edges()
			var archive_txt := String(extra.get("archive", extra.get("daily", extra.get("content", extra.get("summary", ""))))).strip_edges()
			var body_txt := archive_txt if archive_txt != "" else overview
			var wrapped := body_txt if body_txt.contains("<DLC_") else ""
			var char_list: Array = []
			for rn_raw in rns:
				var rn := String(rn_raw).strip_edges()
				if rn == "": continue
				char_list.append(rn)
				var final_body := wrapped if wrapped != "" else ("<DLC_%s>\n%s\n</DLC_%s>" % [rn, body_txt, rn])
				var eid := "workshop_dlc_char_" + rn
				wb_custom = _upsert_wb_entry(wb_custom, {
					"id": eid,
					"title": "DLC/" + rn,
					"category": "创意工坊DLC",
					"path": "workshop/" + pid,
					"summary": overview.substr(0, 120) if overview != "" else title,
					"body": final_body,
					"constant": false,
					"_workshop": true,
					"_workshop_pkg_id": pid,
					"_workshop_type": "character",
				})
				dlc_chars[rn] = {
					"name": rn,
					"title": title,
					"overview": overview,
					"summary": String(extra.get("summary", overview)),
					"imageDailyUrl": String(extra.get("imageDailyUrl", "")),
					"imageFormUrl": String(extra.get("imageFormUrl", "")),
					"imageAvatarUrl": String(extra.get("imageAvatarUrl", "")),
					"pkg_id": pid,
				}
				wb_added += 1
			inst_pkgs[pid] = {
				"id": pid, "title": title, "category": cat, "revision": int(pkg.get("revision", 1)),
				"dlc_chars": char_list, "imported_at": Time.get_datetime_string_from_system(false, true),
			}
			ok_titles.append(title)

		elif cat in ["faction", "gameplay", "rule", "other", "event", "world_factor"]:
			var entries_to_add := _convert_lore_pkg_entries(pkg, cat, extra, payload)
			if entries_to_add.is_empty():
				skipped.append("%s：条目正文为空" % title); continue
			var eid_list: Array = []
			for ne in entries_to_add:
				wb_custom = _upsert_wb_entry(wb_custom, ne)
				eid_list.append(String(ne.id))
				wb_added += 1
			inst_pkgs[pid] = {
				"id": pid, "title": title, "category": cat, "revision": int(pkg.get("revision", 1)),
				"wb_ids": eid_list, "imported_at": Time.get_datetime_string_from_system(false, true),
			}
			ok_titles.append(title)
		else:
			skipped.append("%s：暂不支持导入类型 %s" % [title, cat])

	wb_custom = _rebuild_dlc_shared_entries(wb_custom, dlc_chars)
	DataCls.save_custom_worldbook_entries(wb_custom)
	installed["packages"] = inst_pkgs
	installed["dlc_characters"] = dlc_chars
	save_installed()
	changed.emit()
	return {
		"ok": not ok_titles.is_empty(),
		"imported_count": ok_titles.size(),
		"sigil_added": sigil_added,
		"wb_added": wb_added,
		"titles": ok_titles,
		"skipped": skipped,
	}

func uninstall_package(pkg_id: String) -> Dictionary:
	var DataCls = preload("res://scripts/ui/ui_data.gd")
	var inst_pkgs: Dictionary = installed.get("packages", {})
	var rec: Dictionary = inst_pkgs.get(pkg_id, {}) if inst_pkgs.get(pkg_id) is Dictionary else {}
	if rec.is_empty(): return {"ok": false, "error": "该作品尚未导入"}
	# Remove worldbook entries belonging to this pkg
	var wb_custom: Array = DataCls.custom_worldbook_entries().filter(func(e): return not (e is Dictionary and String(e.get("_workshop_pkg_id", "")) == pkg_id))
	var dlc_chars: Dictionary = installed.get("dlc_characters", {})
	for rn in dlc_chars.keys():
		if dlc_chars[rn] is Dictionary and String(dlc_chars[rn].get("pkg_id", "")) == pkg_id:
			dlc_chars.erase(rn)
	wb_custom = _rebuild_dlc_shared_entries(wb_custom, dlc_chars)
	DataCls.save_custom_worldbook_entries(wb_custom)
	# Remove imported blueprint sigils from user://workshop.json
	var sigil_ids: Array = rec.get("sigil_ids", []) if rec.get("sigil_ids") is Array else []
	if not sigil_ids.is_empty() and FileAccess.file_exists(_workshop_store_path()):
		var cur_store = _read_json(_workshop_store_path(), {})
		if cur_store is Dictionary and cur_store.get("saved") is Array:
			cur_store["saved"] = cur_store.saved.filter(func(m): return not (m is Dictionary and String(m.get("id", "")) in sigil_ids))
			_write_json(_workshop_store_path(), cur_store)
	inst_pkgs.erase(pkg_id)
	installed["packages"] = inst_pkgs
	installed["dlc_characters"] = dlc_chars
	save_installed()
	changed.emit()
	return {"ok": true}

func _convert_lore_pkg_entries(pkg: Dictionary, cat: String, extra: Dictionary, payload: Dictionary) -> Array:
	var pid := String(pkg.get("id", ""))
	var title := String(pkg.get("title", pid)).strip_edges()
	var out: Array = []
	if cat == "world_factor":
		var factors: Array = payload.get("worldFactors", []) if payload.get("worldFactors") is Array else []
		for i in range(factors.size()):
			var f: Variant = factors[i]
			if not f is Dictionary: continue
			var content := String(f.get("content", "")).strip_edges()
			if content == "": continue
			var ft := String(f.get("title", title)).strip_edges()
			out.append({
				"id": "workshop_wf_%s_%d" % [pid, i],
				"title": "DLC/" + ft,
				"category": "创意工坊DLC",
				"path": "workshop/" + pid,
				"summary": ft,
				"body": content,
				"constant": true,
				"_workshop": true,
				"_workshop_pkg_id": pid,
				"_workshop_type": "world_factor",
			})
		return out
	if cat == "event":
		var content := String(extra.get("content", "")).strip_edges()
		if content == "": return []
		var enames: Array = extra.get("eventNames", []) if extra.get("eventNames") is Array else []
		if enames.is_empty(): enames = [title]
		var rns: Array = extra.get("roleNames", []) if extra.get("roleNames") is Array else []
		for en_raw in enames:
			var en := String(en_raw).strip_edges()
			if en == "": continue
			out.append({
				"id": "workshop_ev_%s_%s" % [pid, en],
				"title": "剧情事件/" + en,
				"category": "创意工坊DLC",
				"path": "workshop/" + pid,
				"summary": "绑定角色：" + ("、".join(PackedStringArray(rns)) if not rns.is_empty() else "通用"),
				"body": content,
				"constant": false,
				"role_names": rns,
				"_workshop": true,
				"_workshop_pkg_id": pid,
				"_workshop_type": "event",
			})
		return out
	var txt := String(extra.get("content", "")).strip_edges()
	if txt == "": return []
	var kws: Array = extra.get("keywords", []) if extra.get("keywords") is Array else []
	if cat == "faction" and kws.is_empty(): kws = [title]
	out.append({
		"id": "workshop_%s_%s" % [cat, pid],
		"title": "DLC/" + title,
		"category": "创意工坊DLC",
		"path": "workshop/" + pid,
		"summary": "%s · %s" % [category_label(cat), title],
		"body": txt,
		"constant": cat in ["gameplay", "rule", "other"],
		"keywords": kws,
		"_workshop": true,
		"_workshop_pkg_id": pid,
		"_workshop_type": cat,
	})
	return out

func _upsert_wb_entry(list: Array, entry: Dictionary) -> Array:
	var eid := String(entry.get("id", ""))
	for i in range(list.size()):
		if list[i] is Dictionary and String(list[i].get("id", "")) == eid:
			list[i] = entry
			return list
	list.append(entry)
	return list

func _rebuild_dlc_shared_entries(wb_custom: Array, dlc_chars: Dictionary) -> Array:
	var out: Array = wb_custom.filter(func(e):
		return not (e is Dictionary and String(e.get("id", "")) in ["workshop_aethera_dlc_overview", "workshop_aethera_dlc_ctrl"])
	)
	if dlc_chars.is_empty():
		return out
	var names: Array = dlc_chars.keys()
	var blocks := PackedStringArray([
		"DLC角色速览:",
		"  角色初始变量设置: 当工坊 DLC 角色初次登场后，按照「角色组更新规则」建档写入 stat_data/角色组/<角色名>/（简介/当前形态/好感度/色情值/已解锁性癖）",
	])
	for rn in names:
		var rec: Dictionary = dlc_chars[rn]
		var ov := String(rec.get("overview", "")).strip_edges()
		if ov != "": blocks.append("\n" + ov)
		else: blocks.append("\n  %s:\n    简介: %s\n    形态:\n      - 日常" % [rn, String(rec.get("title", rn))])
	out.push_front({
		"id": "workshop_aethera_dlc_ctrl",
		"title": "DLC控制器",
		"category": "创意工坊DLC",
		"path": "workshop/shared",
		"summary": "已启用 %d 名工坊 DLC 角色：%s" % [names.size(), "、".join(PackedStringArray(names))],
		"body": "已激活的艾瑟拉工坊 DLC 角色名册：" + "、".join(PackedStringArray(names)) + "。\n当上述角色进入 stat_data.角色组 或在场对话时，自动加载对应的 DLC/<角色名> 档案。",
		"constant": false,
		"_workshop": true,
		"_workshop_type": "controller",
	})
	out.push_front({
		"id": "workshop_aethera_dlc_overview",
		"title": "DLC角色速览",
		"category": "创意工坊DLC",
		"path": "workshop/shared",
		"summary": "工坊 DLC 角色登场规则与名册",
		"body": "<DLC角色速览>\n" + "\n".join(blocks) + "\n</DLC角色速览>",
		"constant": true,
		"_workshop": true,
		"_workshop_type": "overview",
	})
	return out

# ---------------- Thumbnail loader ----------------
func cached_thumb(url: String, on_loaded := Callable()) -> Texture2D:
	var u := url.strip_edges()
	if u == "" or not (u.begins_with("https://") or u.begins_with("http://")):
		return null
	if _thumb_cache.has(u):
		return _thumb_cache[u]
	var h := u.sha256_text().substr(0, 20)
	var disk := _dir() + "cache/" + h + ".bin"
	if FileAccess.file_exists(disk):
		var tex := _decode_image_bytes(FileAccess.get_file_as_bytes(disk))
		if tex != null:
			_thumb_cache[u] = tex
			return tex
	if not _thumb_pending.has(u) and not UiHub.review_mode:
		_thumb_pending[u] = true
		var req := HTTPRequest.new(); req.timeout = 12.0; add_child(req)
		req.request_completed.connect(func(res: int, code: int, _rh: PackedStringArray, body: PackedByteArray):
			req.queue_free()
			_thumb_pending.erase(u)
			if res == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and body.size() > 64 and body.size() < 4 * 1024 * 1024:
				var tex := _decode_image_bytes(body)
				if tex != null:
					_ensure_dirs()
					var f := FileAccess.open(disk, FileAccess.WRITE)
					if f: f.store_buffer(body); f.close()
					_thumb_cache[u] = tex
					if on_loaded.is_valid(): on_loaded.call(tex)
					changed.emit()
		, CONNECT_ONE_SHOT)
		if req.request(u) != OK:
			req.queue_free()
			_thumb_pending.erase(u)
	return null

func _decode_image_bytes(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 16: return null
	var img := Image.new()
	var err := ERR_INVALID_DATA
	if bytes[0] == 0x89 and bytes[1] == 0x50: err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8: err = img.load_jpg_from_buffer(bytes)
	elif bytes[0] == 0x52 and bytes[1] == 0x49: err = img.load_webp_from_buffer(bytes)
	if err != OK:
		err = img.load_png_from_buffer(bytes)
		if err != OK: err = img.load_webp_from_buffer(bytes)
		if err != OK: err = img.load_jpg_from_buffer(bytes)
	if err != OK or img.is_empty(): return null
	return ImageTexture.create_from_image(img)
