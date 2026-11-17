extends RefCounted
## Standalone / Demo back end with integrated Hotaru V8 preset + 7-table GameDatabase
## and isolated Single-Character Bridge Chat assembly.
## Uses deterministic offline fixtures when test_replies_enabled == true, or native HTTPRequest
## OpenAI-compatible calls when the user configures an API URL & model on desktop.

const SAVE_DIR := "user://demo_saves/"
const CONN_PATH := "user://demo_connection.cfg"
const CONNS_JSON_PATH := "user://demo_connections.json"
const PRESET_OVERRIDES_PATH := "user://preset_overrides.json"
const CONTENT := "res://data/content/contest_content.json"
const PRESET_PATH := "res://data/hotaru_preset_v1.json"
const GameDatabase = preload("res://scripts/game/game_database.gd")
const Parser = preload("res://scripts/game/reply_parser.gd")
const Data = preload("res://scripts/ui/ui_data.gd")

var g: Node
var content: Dictionary = {}
var chat: Array = []
var persona: Dictionary = {}
var origin := ""
var next_id := 0
var slot := 0
var turn := 0
var busy := false
var cancel := false
var macro_recap: Dictionary = {}
var base_stat_override: Dictionary = {}
var oracle_patches: Array = []
var gdb := GameDatabase.new()
var active_preset: Dictionary = {}
var active_preset_id := PRESET_PATH
var active_preset_name := "【Hotaru预设】v1.0"
var _preset_overrides: Dictionary = {}
var _conn_profiles: Array = []
var _active_conn_id := ""
var _active_http: HTTPRequest = null

## Automated fixtures explicitly set this true for deterministic offline generation.
var test_replies_enabled := false
## Optional headless test override: Callable(messages: Array, kind: String, on_done: Callable)
var mock_story_transport: Callable = Callable()

func attach(game: Node) -> void:
	g = game
	content = JSON.parse_string(FileAccess.get_file_as_string(CONTENT))
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_conn_profiles()
	_load_preset_overrides()
	_load_bundled_preset()
	gdb.reset_all()
	_push_saves(); _push_connection(); _push_presets()
	_push_gen()
	_push_db()

func _load_bundled_preset(path := PRESET_PATH) -> void:
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			active_preset = parsed
			active_preset_id = path
			active_preset_name = path.get_file().get_basename()
			if path == PRESET_PATH:
				active_preset_name = "【Hotaru预设】v1.0（已联动数据库）"

# ---------- snapshots ----------
func _branch_id() -> String:
	return "slot_%d" % slot if slot > 0 else "main"

func _push_db() -> void:
	if is_instance_valid(g):
		g.apply_snapshot("db", gdb.snapshot())

func _push_messages() -> void:
	g.apply_snapshot("messages", chat.duplicate(true))
	_push_recap()

func _push_gen(kind := "", stream := "") -> void:
	g.apply_snapshot("generation", {"busy": busy, "kind": kind, "stream": stream})

func _push_recap() -> void:
	var txt := String(macro_recap.get("text", "")).strip_edges()
	g.apply_snapshot("recap", {
		"text": txt,
		"summary_count": _count_micro_summaries(),
		"source_count": int(macro_recap.get("source_count", 0)) if txt != "" else 0,
		"updated_at": String(macro_recap.get("updated_at", "")) if txt != "" else "",
	})

func _sync_and_push_state() -> void:
	var st := _replay()
	gdb.sync_from_game(_branch_id(), chat, st, persona)
	g.apply_snapshot("stat", st)
	_push_db()

func _push_all() -> void:
	g.apply_snapshot("persona", persona.duplicate(true))
	_push_messages()
	_sync_and_push_state()

func _count_micro_summaries() -> int:
	var details_re := RegEx.new()
	details_re.compile("(?is)<details\\b[^>]*>[\\s\\S]*?</details\\s*>")
	var sum_re := RegEx.new()
	sum_re.compile("(?is)<(?:sumUp|summary)(?:\\s[^>]*)?>([\\s\\S]*?)</(?:sumUp|summary)\\s*>")
	var total := 0
	for m in chat:
		var cleaned := details_re.sub(_text(m), "", true)
		for hit in sum_re.search_all(cleaned):
			if hit.get_string(1).strip_edges() != "": total += 1
	for ms in gdb.timeline_summaries:
		if ms is Dictionary and bool(ms.get("manual", false)):
			total += 1
	return total

func _origin_data(k: String) -> Dictionary:
	for o in content.get("origins", []):
		if String(o.get("key", "")) == k: return o
	return content.origins[0] if not content.get("origins", []).is_empty() else {}

func _lead_companion_for_origin(k: String) -> String:
	var roles: Variant = _origin_data(k).get("init_stat", {}).get("角色组", {})
	if roles is Dictionary and not roles.is_empty():
		return String(roles.keys()[0])
	var fallback := {"sereth": "凛零", "staff": "冰糖", "omanut": "明空", "jwanshakti": "阿兰雅", "longyuan": "焰渊", "gloria": "艾利丝", "akitsu": "阳向", "custom": "叶子"}
	return String(fallback.get(k, "凛零"))

func _initial_stat() -> Dictionary:
	if not base_stat_override.is_empty():
		var ov: Dictionary = base_stat_override.duplicate(true)
		if not ov.has("主角组") or not ov["主角组"] is Dictionary: ov["主角组"] = {}
		if not ov.has("角色组") or not ov["角色组"] is Dictionary: ov["角色组"] = {}
		if not ov.has("剧情事件") or not ov["剧情事件"] is Dictionary: ov["剧情事件"] = {"当前触发事件": {}, "已完成事件": []}
		return ov
	if origin == "custom":
		return {
			"主角组": {
				"简介": "待初始化",
				"当前地点": "",
				"时间": "1015年·2月1日",
				"当前BGM": "Main Theme",
				"持有物品": {},
				"当前在场角色": [],
				"魔力上限": "待初始化",
				"魔力": "待初始化",
				"魔法": {},
				"已讨伐异危": [],
			},
			"角色组": {},
			"剧情事件": {"当前触发事件": {}, "已完成事件": []},
		}
	var orig := _origin_data(origin)
	var init_stat: Dictionary = orig.get("init_stat", {})
	if not init_stat.is_empty():
		var st: Dictionary = init_stat.duplicate(true)
		var lead: Dictionary = st.get("主角组", {}).duplicate(true)
		lead["简介"] = lead.get("简介", "待初始化")
		lead["当前地点"] = lead.get("当前地点", "塞蕾特公国·中央学院")
		lead["时间"] = lead.get("时间", String(content.archive.nowFallback) + " 08:00")
		lead["当前BGM"] = lead.get("当前BGM", "Main Theme")
		lead["持有物品"] = lead.get("持有物品", {})
		lead["魔力上限"] = lead.get("魔力上限", "待初始化")
		lead["魔力"] = lead.get("魔力", "待初始化")
		lead["魔法"] = lead.get("魔法", {})
		lead["当前在场角色"] = lead.get("当前在场角色", [])
		lead["已讨伐异危"] = lead.get("已讨伐异危", [])
		st["主角组"] = lead
		if not st.has("角色组"): st["角色组"] = {}
		if not st.has("剧情事件"): st["剧情事件"] = {"当前触发事件": {}, "已完成事件": []}
		return st
	var place := "塞蕾特公国·中央学院" if origin == "sereth" else "塞蕾特公国·蛇杖分部"
	return {"主角组": {"简介": "待初始化", "当前地点": place, "时间": String(content.archive.nowFallback) + " 08:00", "当前BGM": "Main Theme",
		"持有物品": {}, "当前在场角色": [], "魔力上限": "待初始化", "魔力": "待初始化", "魔法": {}, "已讨伐异危": []},
		"角色组": {}, "剧情事件": {"当前触发事件": {}, "已完成事件": []}}

## Stat = initial state + every active swipe's JSON Patch + active Oracle patches, in order.
func _replay() -> Dictionary:
	var s := _initial_stat()
	for m in chat:
		if m.role != "assistant": continue
		var r: Dictionary = Parser.parse(_text(m))
		if r.patch == "": continue
		var ops = JSON.parse_string(r.patch)
		if ops is Array:
			for op in ops: _apply(s, op)
	for batch in oracle_patches:
		if not batch is Dictionary: continue
		for op in batch.get("ops", []):
			_apply(s, op)
	return s

func _text(m: Dictionary) -> String:
	return String(m.swipes[int(m.swipe)])

func _apply(root: Dictionary, op) -> void:
	if not op is Dictionary or not op.has("path"): return
	var keys: PackedStringArray = String(op.path).trim_prefix("/").split("/")
	var parent = root
	for i in range(keys.size() - 1):
		if parent is Dictionary:
			if not parent.has(keys[i]): parent[keys[i]] = {}
			parent = parent[keys[i]]
		elif parent is Array and keys[i].is_valid_int() and int(keys[i]) < parent.size(): parent = parent[int(keys[i])]
		else: return
	var last := keys[keys.size() - 1]
	match String(op.get("op", "")):
		"replace", "insert":
			if parent is Array:
				if last == "-": parent.append(op.value)
				elif op.op == "insert" and last.is_valid_int(): parent.insert(int(last), op.value)
			elif parent is Dictionary: parent[last] = op.value
		"delta":
			if parent is Dictionary and parent.has(last) and (typeof(parent[last]) in [TYPE_INT, TYPE_FLOAT]):
				parent[last] = clampf(float(parent[last]) + float(op.value), 0.0, 100.0) if last in ["好感度", "色情值"] else float(parent[last]) + float(op.value)
		"remove":
			if parent is Dictionary: parent.erase(last)
			elif parent is Array and last.is_valid_int() and int(last) < parent.size(): parent.remove_at(int(last))
		"move":
			var from_p := String(op.get("from", "")).trim_prefix("/").split("/")
			var f_parent: Variant = root
			for fi in range(from_p.size() - 1):
				if f_parent is Dictionary and f_parent.has(from_p[fi]): f_parent = f_parent[from_p[fi]]
				else: f_parent = null; break
			var flast := from_p[from_p.size() - 1] if not from_p.is_empty() else ""
			if f_parent is Dictionary and flast != "" and f_parent.has(flast) and parent is Dictionary:
				parent[last] = f_parent[flast]
				f_parent.erase(flast)

# ---------- story ----------
func new_game(p: Dictionary, origin_key: String) -> void:
	persona = p.duplicate(); persona["origin"] = origin_key; origin = origin_key
	chat.clear(); next_id = 0; turn = 0; slot = 0; macro_recap = {}; base_stat_override = {}; oracle_patches = []
	gdb.reset_all()
	if origin_key == "custom":
		_push_all(); _autosave()
		begin_custom_opening()
		return
	var orig := _origin_data(origin_key)
	var greeting := String(orig.get("greeting", ""))
	var tag := String(orig.get("opening_scene_tag", ""))
	var opening_scene := ("<场景>%s</场景>\n" % tag) if tag != "" else ("<场景>中央学院·校舍长廊</场景>\n" if origin_key == "sereth" else "<场景>公国蛇杖分部·资料禁区入口／走廊</场景>\n")
	chat.append(_msg("assistant", "艾瑟拉", opening_scene + greeting))
	_push_all(); _autosave()

func begin_custom_opening() -> void:
	if origin != "custom" or busy or not chat.is_empty(): return
	if not test_replies_enabled and not mock_story_transport.is_valid() and not is_api_configured():
		g.report_error("api_configuration", "「自定义」出身必须先配置 API，请先填写接口地址与模型后再开始。")
		return
	_generate("custom_open", func(reply):
		chat.append(_msg("assistant", "艾瑟拉", reply)))

func _msg(role: String, name: String, text: String) -> Dictionary:
	var m := {"id": next_id, "role": role, "name": name, "swipes": [text], "swipe": 0, "data": {}}
	next_id += 1
	return m

func send_action(text: String, _source: String) -> void:
	if not _can_generate(): return
	chat.append(_msg("user", String(persona.get("name", "你")), text)); _push_messages()
	_generate("send", func(reply): chat.append(_msg("assistant", "艾瑟拉", reply)))

func regenerate(id: int) -> void:
	if not _can_generate(): return
	var m := _find(id)
	if m.is_empty(): return
	_generate("regenerate", func(reply): m.swipes.append(reply); m.swipe = m.swipes.size() - 1)

func continue_reply(id: int) -> void:
	if not _can_generate(): return
	var m := _find(id)
	if m.is_empty(): return
	_generate("continue", func(_r): m.swipes[int(m.swipe)] = _text(m).replace("<UpdateVariable>", "（演示续写：接入AI后这里会接着写完。）\n<UpdateVariable>") if "<UpdateVariable>" in _text(m) else _text(m) + "\n（演示续写：接入AI后这里会接着写完。）", true)

func _load_conn_profiles() -> void:
	_conn_profiles.clear()
	_active_conn_id = ""
	if FileAccess.file_exists(CONNS_JSON_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONNS_JSON_PATH))
		if parsed is Dictionary:
			_active_conn_id = String(parsed.get("active_id", ""))
			for item in parsed.get("profiles", []):
				if item is Dictionary and String(item.get("id", "")) != "":
					_conn_profiles.append(item.duplicate())
	if _conn_profiles.is_empty():
		var cfg := ConfigFile.new()
		if cfg.load(CONN_PATH) == OK:
			var url_s := String(cfg.get_value("api", "url", "")).strip_edges()
			var model_s := String(cfg.get_value("api", "model", "")).strip_edges()
			_conn_profiles.append({
				"id": "default",
				"name": String(cfg.get_value("api", "name", model_s if model_s != "" else "默认连接")),
				"format": String(cfg.get_value("api", "format", "openai")),
				"mode": String(cfg.get_value("api", "mode", "chat")),
				"url": url_s,
				"model": model_s,
				"key": String(cfg.get_value("api", "key", "")).strip_edges(),
			})
			_active_conn_id = "default"
	if _conn_profiles.is_empty():
		_conn_profiles.append({
			"id": "default",
			"name": "默认连接",
			"format": "openai",
			"mode": "chat",
			"url": "",
			"model": "",
			"key": "",
		})
		_active_conn_id = "default"
	if _active_conn_idx() < 0:
		_active_conn_id = String(_conn_profiles[0].get("id", "default"))
	_sync_legacy_conn_cfg()

func _active_conn_idx() -> int:
	for i in range(_conn_profiles.size()):
		if String(_conn_profiles[i].get("id", "")) == _active_conn_id:
			return i
	return -1 if _conn_profiles.is_empty() else 0

func _sync_legacy_conn_cfg() -> void:
	var idx := _active_conn_idx()
	var cur: Dictionary = _conn_profiles[idx] if idx >= 0 else {"format": "openai", "mode": "chat", "url": "", "model": "", "key": ""}
	var cfg := ConfigFile.new()
	cfg.set_value("api", "name", String(cur.get("name", "默认连接")))
	cfg.set_value("api", "format", String(cur.get("format", "openai")))
	cfg.set_value("api", "mode", String(cur.get("mode", "chat")))
	cfg.set_value("api", "url", String(cur.get("url", "")))
	cfg.set_value("api", "model", String(cur.get("model", "")))
	cfg.set_value("api", "key", String(cur.get("key", "")))
	cfg.save(CONN_PATH)

func _save_conn_profiles() -> void:
	var f := FileAccess.open(CONNS_JSON_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"active_id": _active_conn_id, "profiles": _conn_profiles}, "\t"))
		f.close()
	_sync_legacy_conn_cfg()

func _conn_cfg() -> Dictionary:
	if _conn_profiles.is_empty():
		_load_conn_profiles()
	var idx := _active_conn_idx()
	var cur: Dictionary = _conn_profiles[idx] if idx >= 0 else {}
	return {
		"id": String(cur.get("id", "default")),
		"name": String(cur.get("name", "默认连接")),
		"format": String(cur.get("format", "openai")),
		"mode": String(cur.get("mode", "chat")),
		"url": String(cur.get("url", "")).strip_edges(),
		"model": String(cur.get("model", "")).strip_edges(),
		"key": String(cur.get("key", "")).strip_edges(),
	}

func is_api_configured() -> bool:
	if OS.has_feature("web"): return false
	var c := _conn_cfg()
	var endpoint := String(c.get("url", "")).strip_edges()
	if not (endpoint.begins_with("https://") or endpoint.begins_with("http://")): return false
	if endpoint.get_slice("://", 1).get_slice("/", 0) == "": return false
	return String(c.get("model", "")).strip_edges() != ""

func _has_live_api() -> bool:
	if mock_story_transport.is_valid(): return true
	if test_replies_enabled or OS.has_feature("web"): return false
	return is_api_configured()

func _can_generate() -> bool:
	if test_replies_enabled or _has_live_api(): return true
	g.report_error("api_configuration", "尚未连接真实 AI，行动未发送。请填写 API 地址与模型后再试。")
	return false

func _generate(kind: String, finish: Callable, short := false) -> void:
	if not _can_generate(): return
	if busy: return
	busy = true; cancel = false; turn += 1
	if _has_live_api():
		_generate_live_story(kind, finish)
		return
	var reply := _demo_custom_opening_reply() if kind == "custom_open" else _demo_reply()
	var steps := 6 if not short else 2
	for i in range(steps):
		var t: SceneTreeTimer = g.get_tree().create_timer(0.18 * (i + 1))
		var part := reply.substr(0, int(reply.length() * (i + 1) / float(steps + 2)))
		t.timeout.connect(func(): if busy and not cancel: _push_gen(kind, part))
	var done: SceneTreeTimer = g.get_tree().create_timer(0.18 * (steps + 1))
	done.timeout.connect(func():
		if cancel: return
		if is_instance_valid(UiHub): UiHub.story_oracle().check_beat_completion(reply)
		finish.call(reply); busy = false
		_push_gen(); _push_messages(); _sync_and_push_state(); _autosave())
	_push_gen(kind, "")

func _resolve_preset_macros(raw_txt: String, pname: String, cname: String) -> String:
	var txt := raw_txt.replace("{{user}}", pname).replace("{{char}}", cname)
	var vars := {}
	var set_rx := RegEx.new()
	set_rx.compile("\\{\\{setvar::([^:}]+)::([\\s\\S]*?)\\}\\}")
	for m in set_rx.search_all(txt):
		vars[m.get_string(1).strip_edges()] = m.get_string(2)
	txt = set_rx.sub(txt, "", true)
	var get_rx := RegEx.new()
	get_rx.compile("\\{\\{getvar::([^}]+)\\}\\}")
	for _pass in range(2):
		var next_txt := ""
		var cursor := 0
		for gm in get_rx.search_all(txt):
			next_txt += txt.substr(cursor, gm.get_start() - cursor)
			var k := gm.get_string(1).strip_edges()
			next_txt += String(vars.get(k, ""))
			cursor = gm.get_end()
		next_txt += txt.substr(cursor)
		txt = next_txt
	return txt.strip_edges()

func _load_preset_overrides() -> void:
	_preset_overrides = {}
	if FileAccess.file_exists(PRESET_OVERRIDES_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PRESET_OVERRIDES_PATH))
		if parsed is Dictionary:
			_preset_overrides = parsed

func _save_preset_overrides() -> void:
	var f := FileAccess.open(PRESET_OVERRIDES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_preset_overrides, "\t"))
		f.close()

func _active_preset_ov() -> Dictionary:
	if not _preset_overrides.has(active_preset_id) or not _preset_overrides[active_preset_id] is Dictionary:
		return {}
	return _preset_overrides[active_preset_id]

func get_preset_entries() -> Array:
	var prompts: Array = active_preset.get("prompts", [])
	if prompts.is_empty(): return []
	var by_id := {}
	var ordered_ids: Array = []
	for pr in prompts:
		if not pr is Dictionary: continue
		var pid := String(pr.get("identifier", ""))
		if pid == "": continue
		by_id[pid] = pr
	var def_enabled := {}
	var order_arr: Array = active_preset.get("prompt_order", [])
	if not order_arr.is_empty() and order_arr[0] is Dictionary:
		for item in order_arr[0].get("order", []):
			if not item is Dictionary: continue
			var iid := String(item.get("identifier", ""))
			if iid == "" or not by_id.has(iid): continue
			if not (iid in ordered_ids): ordered_ids.append(iid)
			def_enabled[iid] = bool(item.get("enabled", false))
	for pr in prompts:
		if not pr is Dictionary: continue
		var pid := String(pr.get("identifier", ""))
		if pid != "" and not (pid in ordered_ids):
			ordered_ids.append(pid)
			def_enabled[pid] = bool(pr.get("enabled", false))

	var ov: Dictionary = _active_preset_ov()
	var ov_en: Dictionary = ov.get("enabled", {}) if ov.get("enabled") is Dictionary else {}
	var ov_cnt: Dictionary = ov.get("content", {}) if ov.get("content") is Dictionary else {}

	var out: Array = []
	for idx in range(ordered_ids.size()):
		var pid := String(ordered_ids[idx])
		var pr: Dictionary = by_id[pid]
		var base_en := bool(def_enabled.get(pid, bool(pr.get("enabled", false))))
		if pid == "hotaru_opt_format_vn" and not def_enabled.get(pid, false):
			base_en = true
		var eff_en := bool(ov_en[pid]) if ov_en.has(pid) else base_en
		var base_content := String(pr.get("content", ""))
		var eff_content := String(ov_cnt[pid]) if ov_cnt.has(pid) else base_content
		var is_mod := ov_en.has(pid) or ov_cnt.has(pid)
		out.append({
			"index": idx,
			"identifier": pid,
			"name": String(pr.get("name", pid)),
			"role": String(pr.get("role", "system")),
			"marker": bool(pr.get("marker", false)),
			"enabled": eff_en,
			"default_enabled": base_en,
			"content": eff_content,
			"default_content": base_content,
			"modified": is_mod,
		})
	return out

func set_preset_entry(pid: String, patch: Dictionary) -> void:
	var clean := pid.strip_edges()
	if clean == "": return
	if not _preset_overrides.has(active_preset_id) or not _preset_overrides[active_preset_id] is Dictionary:
		_preset_overrides[active_preset_id] = {"enabled": {}, "content": {}}
	var ov: Dictionary = _preset_overrides[active_preset_id]
	if not ov.get("enabled") is Dictionary: ov["enabled"] = {}
	if not ov.get("content") is Dictionary: ov["content"] = {}
	if bool(patch.get("reset", false)):
		ov["enabled"].erase(clean)
		ov["content"].erase(clean)
	else:
		if patch.has("enabled"):
			ov["enabled"][clean] = bool(patch.get("enabled", false))
		if patch.has("content"):
			ov["content"][clean] = String(patch.get("content", ""))
	if ov["enabled"].is_empty() and ov["content"].is_empty():
		_preset_overrides.erase(active_preset_id)
	_save_preset_overrides()
	_push_presets()
	g.notify("已更新预设条目：" + clean)

func reset_preset_overrides() -> void:
	_preset_overrides.erase(active_preset_id)
	_save_preset_overrides()
	_push_presets()
	g.notify("已恢复当前预设全部条目为默认状态")

func _preset_system_prompt(bridge_mode := false, char_name := "艾瑟拉") -> String:
	var parts := PackedStringArray()
	var entries := get_preset_entries()
	if entries.is_empty():
		return "你是 Aethera 奇幻轻小说视觉小说引擎的叙述者，遵循设定，保持自然生动的描写。"
	for e in entries:
		var pid := String(e.get("identifier", ""))
		if bool(e.get("marker", false)): continue
		var content_s := String(e.get("content", "")).strip_edges()
		if content_s == "": continue
		if bridge_mode:
			if pid in ["hotaru_lang_chinese", "hotaru_banned_patterns", "hotaru_opt_bridge_chat", "jailbreak"]:
				if bool(e.get("enabled", true)) or pid == "hotaru_opt_bridge_chat":
					parts.append(content_s)
		else:
			if pid == "hotaru_opt_bridge_chat": continue
			if bool(e.get("enabled", false)):
				parts.append(content_s)
	var pname := String(persona.get("name", "你"))
	return _resolve_preset_macros("\n\n".join(parts), pname, char_name if char_name != "" else "艾瑟拉")

func _build_story_api_messages() -> Array:
	var api_msgs: Array = []
	var start := maxi(0, chat.size() - 12)
	var recent_blob := PackedStringArray()
	for i in range(start, chat.size()):
		recent_blob.append(_text(chat[i]))
	var sys := _preset_system_prompt(false)
	var world_ctx := gdb.build_main_story_world_context(_replay(), persona, "\n".join(recent_blob))
	if world_ctx != "":
		sys += "\n\n" + world_ctx
	var recap_txt := String(macro_recap.get("text", "")).strip_edges()
	if recap_txt != "":
		sys += "\n\n[阶段大总结记忆]\n" + recap_txt
	if not gdb.timeline_summaries.is_empty():
		var slines := PackedStringArray()
		var lo := maxi(0, gdb.timeline_summaries.size() - 6)
		for idx in range(lo, gdb.timeline_summaries.size()):
			var su: Dictionary = gdb.timeline_summaries[idx]
			slines.append("- [%s｜%s｜%s] %s" % [String(su.get("game_time", "")), String(su.get("location", "")), String(su.get("visibility_label", "")), String(su.get("event", ""))])
		sys += "\n\n[近期时间线小总结]\n" + "\n".join(slines)
	api_msgs.append({"role": "system", "content": sys})
	var oracle_guide := ""
	if is_instance_valid(UiHub):
		oracle_guide = String(UiHub.story_oracle().active_guidance_injection())
	for i in range(start, chat.size()):
		var m: Dictionary = chat[i]
		api_msgs.append({"role": String(m.get("role", "user")), "content": _text(m)})
	if oracle_guide != "":
		var inj_depth := int(UiHub.story_oracle().settings.get("advisor_depth", 2))
		var insert_idx := maxi(1, api_msgs.size() - maxi(0, inj_depth))
		api_msgs.insert(insert_idx, {"role": "system", "content": oracle_guide})
	return api_msgs

func _http_chat_completion(messages: Array, on_done: Callable) -> void:
	var c := _conn_cfg()
	var fmt := String(c.get("format", "openai")).to_lower()
	var base: String = String(c.get("url", "")).trim_suffix("/")
	var temp := float(active_preset.get("temperature", 0.9))
	var headers := PackedStringArray(["Content-Type: application/json"])
	var endpoint := ""
	var payload := {}

	var sys_parts := PackedStringArray()
	var non_sys: Array = []
	for msg in messages:
		if not msg is Dictionary: continue
		var r := String(msg.get("role", "user"))
		var txt := String(msg.get("content", ""))
		if r == "system":
			if txt != "": sys_parts.append(txt)
		else:
			non_sys.append({"role": r, "content": txt})

	if fmt == "claude":
		endpoint = base if base.ends_with("/messages") else (base + "/messages" if base.ends_with("/v1") else base + "/v1/messages")
		headers.append("anthropic-version: 2023-06-01")
		if c.key != "": headers.append("x-api-key: " + c.key)
		payload = {"model": c.model, "max_tokens": 4096, "system": "\n\n".join(sys_parts), "messages": non_sys, "temperature": temp}
	elif fmt == "google":
		var api_root := base if ("/v1" in base) else (base + "/v1beta")
		endpoint = base if ":generateContent" in base else ("%s/models/%s:generateContent?key=%s" % [api_root, c.model.uri_encode(), c.key.uri_encode()])
		var g_contents: Array = []
		for item in non_sys:
			g_contents.append({"role": "model" if String(item.role) == "assistant" else "user", "parts": [{"text": String(item.content)}]})
		payload = {"systemInstruction": {"parts": [{"text": "\n\n".join(sys_parts)}]}, "contents": g_contents, "generationConfig": {"temperature": temp}}
	else:
		endpoint = base if base.ends_with("/chat/completions") else (base + "/chat/completions")
		if c.key != "": headers.append("Authorization: Bearer " + c.key)
		payload = {"model": c.model, "messages": messages, "temperature": temp, "stream": false}

	var req := HTTPRequest.new()
	req.timeout = 90.0
	g.add_child(req)
	_active_http = req
	req.request_completed.connect(func(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray):
		_active_http = null
		req.queue_free()
		if cancel: return
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			on_done.call(false, "HTTP %d (result %d)" % [code, result])
			return
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if fmt == "claude" and parsed is Dictionary and parsed.get("content") is Array:
			var out_parts := PackedStringArray()
			for blk in parsed.content:
				if blk is Dictionary and blk.has("text"): out_parts.append(String(blk.text))
			on_done.call(true, "\n".join(out_parts))
		elif fmt == "google" and parsed is Dictionary and parsed.get("candidates") is Array and not parsed.candidates.is_empty():
			var cand: Dictionary = parsed.candidates[0]
			var out_g := PackedStringArray()
			for pt in cand.get("content", {}).get("parts", []):
				if pt is Dictionary and pt.has("text"): out_g.append(String(pt.text))
			on_done.call(true, "\n".join(out_g))
		elif parsed is Dictionary and parsed.get("choices") is Array and not parsed.choices.is_empty():
			var choice: Dictionary = parsed.choices[0]
			var txt := String(choice.get("message", {}).get("content", choice.get("text", "")))
			on_done.call(true, txt)
		else:
			on_done.call(false, "响应格式无法解析")
	, CONNECT_ONE_SHOT)
	var err := req.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_active_http = null
		req.queue_free()
		on_done.call(false, "请求发起失败 (err %d)" % err)

func _build_custom_opening_messages() -> Array:
	var api_msgs := _build_story_api_messages()
	var pname := String(persona.get("name", "旅者")).strip_edges()
	if pname == "": pname = "旅者"
	var prace := String(persona.get("race", "")).strip_edges()
	var pappear := String(persona.get("appearance", "")).strip_edges()
	var pbio := String(persona.get("bio", "")).strip_edges()
	var pre_prompt := "\n".join([
		"[自定义随机开局前置语]",
		"当前模式为【自定义出身（随机动态开局）】。",
		"预设约束：不设定固定开局地点，仅预设当前开局时间为【1015年·2月1日】。",
		"请完全根据下方玩家填写的角色档案信息，从艾瑟拉世界中合理挑选或构思最契合该角色的起始地点、即时时段/天气、背景音乐与正在发生的开场事件，并生成一段沉浸式第一幕开局剧情（不要沿用其他固定出身的开场白）：",
		"- 玩家姓名：%s" % pname,
		"- 玩家种族：%s" % (prace if prace != "" else "未填写"),
		"- 外貌特征：%s" % (pappear if pappear != "" else "未填写"),
		"- 个人背景与特质：%s" % (pbio if pbio != "" else "未填写"),
		"",
		"输出要求：",
		"1. 遵循系统提示与 Hotaru V8 输出结构（包含 `<场景>地点·分场景</场景>`、`<在场>`、`<pose>`、`<content>`、`<sumUp>`、`<choices>`）。",
		"2. 必须附带 `<UpdateVariable><JSONPatch>`，将你选定的开局地点写入 `/主角组/当前地点`，将包含 `1015年·2月1日` 的具体开局时段写入 `/主角组/时间`，并初始化 `/主角组/简介`、`/主角组/当前BGM`、`/主角组/当前在场角色` 及必要角色数据。",
		"3. 这是开局第一幕，需给予玩家自然的探索切入点与 2-4 个 `<choices>` 行动选项。",
	])
	api_msgs.append({"role": "user", "content": pre_prompt})
	return api_msgs

func _generate_live_story(kind: String, finish: Callable) -> void:
	_push_gen(kind, "")
	var msgs := _build_custom_opening_messages() if kind == "custom_open" else _build_story_api_messages()
	var on_complete := func(ok_flag: bool, text_or_err: String):
		if cancel: return
		busy = false
		_push_gen()
		if ok_flag and text_or_err.strip_edges() != "":
			if is_instance_valid(UiHub): UiHub.story_oracle().check_beat_completion(text_or_err)
			finish.call(text_or_err)
			_push_messages(); _sync_and_push_state(); _autosave()
		else:
			g.report_error("network", "模型请求失败：" + text_or_err)
	if mock_story_transport.is_valid():
		mock_story_transport.call(msgs, kind, on_complete)
		return
	_http_chat_completion(msgs, on_complete)

func stop_generation() -> void:
	if not busy: return
	cancel = true; busy = false
	if is_instance_valid(_active_http):
		_active_http.cancel_request()
		_active_http.queue_free()
		_active_http = null
	_push_gen(); g.notify("已停止生成，你的行动已保留")

func generate_macro_summary() -> void:
	if not _can_generate(): return
	if busy: return
	var count := _count_micro_summaries()
	if count == 0:
		g.report_error("recap", "当前对话尚无可用的 <sumUp>/<summary> 小总结，请先推进剧情后再手动生成阶段大总结。")
		return
	busy = true; cancel = false
	_push_gen("macro_summary", "")
	if _has_live_api():
		var sum_lines := PackedStringArray()
		for su in gdb.timeline_summaries:
			sum_lines.append("[%s｜%s｜%s] %s | 线索：%s | 变动：%s" % [
				String(su.get("game_time", "")), String(su.get("location", "")),
				String(su.get("visibility_label", "")), String(su.get("event", "")),
				String(su.get("clues", "")), String(su.get("changes", ""))
			])
		var msgs := [
			{"role": "system", "content": "请将以下全部小总结汇总成清晰的阶段大总结，分【主线演进】【人物关系与态度变化】【未解伏笔与当前落点】三段。"},
			{"role": "user", "content": "\n".join(sum_lines)},
		]
		_http_chat_completion(msgs, func(ok_flag: bool, txt: String):
			busy = false; _push_gen()
			if ok_flag:
				macro_recap = {"text": txt.strip_edges(), "source_count": count, "updated_at": Time.get_datetime_string_from_system(false, true)}
				_push_recap(); _autosave(); g.notify("阶段大总结已生成并保存")
			else:
				g.report_error("network", "阶段大总结生成失败：" + txt))
		return
	var done: SceneTreeTimer = g.get_tree().create_timer(0.25)
	done.timeout.connect(func():
		if cancel: return
		busy = false
		macro_recap = {
			"text": "【主线演进】\n（演示汇总）已基于当前 %d 条小总结整理前史脉络。\n\n【人物关系与态度变化】\n已自动同步至内置角色态度库。\n\n【未解伏笔与当前落点】\n等待接入真实 AI 后按实况继续推演。" % count,
			"source_count": count,
			"updated_at": Time.get_datetime_string_from_system(false, true),
		}
		_push_gen(); _push_recap(); _autosave(); g.notify("阶段大总结已生成并保存"))

func save_macro_summary(text: String) -> void:
	var clean := text.strip_edges()
	var tag_re := RegEx.new()
	tag_re.compile("(?is)^\\s*<recap(?:\\s[^>]*)?>\\s*|\\s*</recap\\s*>\\s*$")
	clean = tag_re.sub(clean, "", true).strip_edges()
	if clean == "":
		macro_recap = {}
	else:
		macro_recap = {
			"text": clean,
			"source_count": _count_micro_summaries(),
			"updated_at": Time.get_datetime_string_from_system(false, true),
		}
	_push_recap(); _autosave(); g.notify("阶段大总结已保存")

func _demo_custom_opening_reply() -> String:
	var pname := String(persona.get("name", "旅者")).strip_edges()
	if pname == "": pname = "旅者"
	var prace := String(persona.get("race", "人类")).strip_edges()
	var pbio := String(persona.get("bio", "")).strip_edges()
	var loc := "塞蕾特公国·旧城区旅舍二楼"
	var bgm := "Main Theme"
	if "龙" in prace or "龙" in pbio or "东" in pbio:
		loc = "龙渊境域·云海栈道驿站"
		bgm = "龙渊"
	elif "海" in pbio or "船" in pbio or "商" in pbio:
		loc = "自由联邦·潮汐港贸易栈桥"
	elif "学" in pbio or "魔" in pbio or "书" in pbio:
		loc = "塞蕾特公国·外城图书馆长廊"
	var t := "1015年·2月1日 09:00"
	var patch := [
		{"op": "replace", "path": "/主角组/当前地点", "value": loc},
		{"op": "replace", "path": "/主角组/时间", "value": t},
		{"op": "replace", "path": "/主角组/当前BGM", "value": bgm},
		{"op": "replace", "path": "/主角组/简介", "value": "%s（%s）。%s" % [pname, prace, pbio if pbio != "" else "独自踏入艾瑟拉世界的旅人。"]},
	]
	return "\n".join([
		"<场景>%s</场景>" % loc,
		"<content>",
		"%s，清晨的微光落在你肩头，这座陌生的%s渐渐苏醒。" % [t, loc.get_slice("·", 1)],
		"作为%s的%s，你整了整行装。远处的回路塔正发出微弱的共鸣声，街角传来的低语似乎与你的过去隐隐相连。" % [prace, pname],
		"</content>",
		"<sumUp>",
		"时间: %s" % t,
		"地点: %s" % loc,
		"角色: %s" % pname,
		"可见: 在场私密",
		"何事: 自定义开局：根据人物设定随机降临于%s" % loc,
		"线索: 远方回路塔与街角风声中蕴含着初次异动",
		"变动: 确认初始地点为%s" % loc,
		"</sumUp>",
		"<choices>",
		"1. 【观察】：推开窗沿或走近街角，确认周围的势力与动静",
		"2. 【打听】：向最近的驻足者打听今日%s的传闻" % loc.get_slice("·", 0),
		"3. 【自省】：检查随身魔力波动与携带的物品",
		"</choices>",
		"<UpdateVariable>", "<Analysis>custom random opening</Analysis>", "<JSONPatch>", JSON.stringify(patch), "</JSONPatch>", "</UpdateVariable>",
	])

## Format sample (V8 Hotaru standard): emits <pose>, <content>, <sumUp>, <choices>, <UpdateVariable>.
func _demo_reply() -> String:
	var who := _lead_companion_for_origin(origin)
	var cid := Data.id_of(who)
	var body := ""
	for c in content.cast:
		if c.name == who: body = c.body
	var exprs := ["疑惑", "微笑", "惊讶", "害羞", "说话"]
	var ex: String = exprs[turn % exprs.size()]
	var st := _replay()
	var known: bool = st["角色组"].has(who)
	var cur_loc := String(st.get("主角组", {}).get("当前地点", "塞蕾特公国·中央学院"))
	var day_num := maxi(1, turn)
	var cur_time := "1015年2月%d日 09:%02d" % [day_num, (turn * 10) % 60]
	var patch: Array = []
	if not known:
		patch.append({"op": "insert", "path": "/角色组/" + who, "value": {"简介": body, "当前形态": "日常", "好感度": 0, "色情值": 0, "已解锁性癖": []}})
	patch.append({"op": "delta", "path": "/角色组/%s/好感度" % who, "value": 2})
	patch.append({"op": "replace", "path": "/主角组/当前在场角色", "value": [who]})
	patch.append({"op": "replace", "path": "/主角组/时间", "value": cur_time})
	if turn == 1:
		patch.append({"op": "insert", "path": "/主角组/持有物品/演算银币", "value": {"描述": "（演示）学院配发的回路校准币，可随剧情流转。", "数量": 1}})
	return "\n".join([
		"<在场>%s</在场>" % who,
		"<pose>",
		"人物: %s" % who,
		"姿势: 侧身面向你，指尖轻点袖口回路",
		"状态: 常态（%s）" % ex,
		"</pose>",
		"<content>",
		"（演示模式第 %d 轮：已按 Hotaru V8 规范同步时间线小总结至内置数据库。）" % turn,
		"【%s|%s】：“刚才钟楼回廊的风声停了。接下来你打算先去哪里？”" % [who, ex],
		"%s抬起眼帘望向你身后的石阶。（演示旁白）" % who,
		"【%s|平静】：“如果有需要核对的情报，随时在交谈界面里再喊我就好。”" % who,
		"</content>",
		"<sumUp>",
		"时间: %s" % cur_time,
		"地点: %s" % cur_loc,
		"角色: %s、主角" % who,
		"可见: 在场私密",
		"何事: 主角与%s（%s）在%s碰面并约定后续调查动向（第%d幕）" % [who, cid, cur_loc, turn],
		"线索: 钟楼下层的旧回路印记仍留有微弱魔力波动",
		"变动: %s对主角的印象+2；%s" % [who, "获得【演算银币】" if turn == 1 else "无物品变动"],
		"</sumUp>",
		"<choices>",
		"1. 【试探】：继续追问%s关于旧回路印记的事" % who,
		"2. 【稳妥】：暂且告别，前往档案与记忆库查看目前记录",
		"3. 【调停】：先检查随身物品与魔力状态",
		"</choices>",
		"<UpdateVariable>", "<Analysis>demo V8 turn %d</Analysis>" % turn, "<JSONPatch>", JSON.stringify(patch), "</JSONPatch>", "</UpdateVariable>"])

# ---------- 1-on-1 isolated Bridge Chat & Database commands ----------
func preview_bridge_context(cid: String, draft_text := "") -> Dictionary:
	return gdb.build_bridge_context(cid, draft_text)

func send_bridge_chat(cid: String, text: String) -> void:
	var clean := text.strip_edges()
	if cid == "" or clean == "": return
	if busy:
		g.notify("当前还有生成任务在进行，请稍候")
		return
	if not _can_generate(): return
	var ctx := gdb.build_bridge_context(cid, clean)
	var cname := String(ctx.get("character_name", Data.name_of(cid)))
	if _has_live_api():
		# Push the user's bubble right away so the DM screen shows it while waiting for HTTP reply
		gdb.append_bridge_user(cid, clean)
		_push_db()
		busy = true; cancel = false
		_push_gen("bridge_chat", "")
		var sys_full := _preset_system_prompt(true, cname) + "\n\n" + String(ctx.get("assembled_prompt_preview", ""))
		var msgs: Array = [{"role": "system", "content": sys_full}]
		var api_arr: Array = ctx.get("api_messages", [])
		for i in range(1, api_arr.size()):
			msgs.append(api_arr[i])
		_http_chat_completion(msgs, func(ok_flag: bool, reply_txt: String):
			busy = false; _push_gen()
			if ok_flag and reply_txt.strip_edges() != "":
				gdb.append_bridge_reply(cid, reply_txt)
				_push_db(); _autosave()
			else:
				g.report_error("network", "角色单独对话失败：" + reply_txt))
		return

	# Offline deterministic pure-dialogue (1-5 <msg> bubbles) bridge reply referencing ONLY ctx.visible_summaries & ctx.character_facts
	var vis_sums: Array = ctx.get("visible_summaries", [])
	var facts: Array = ctx.get("character_facts", [])
	var ref_line := ""
	if not vis_sums.is_empty():
		var last_sum: Dictionary = vis_sums[vis_sums.size() - 1]
		ref_line = "说起「%s」那会儿……那件事我一直都有留心记着。" % String(last_sum.get("event", "")).substr(0, 32)
	elif not facts.is_empty():
		ref_line = "我当然还记得上次聊到的「%s」。" % String(facts[facts.size() - 1].get("content", "")).substr(0, 28)
	else:
		ref_line = "这段时间我一直在这边单独忙着，主线那边倒还没和你一起经历太多波折呢。"
	var iso_cnt := int(ctx.get("isolated_private_summaries_count", 0))
	var sec_list: Array = ctx.get("worldbook_filtered_secrets", [])
	var sec_cnt: int = sec_list.size()
	var reply_raw := "<content>\n<msg>嗯，我收到你发来的「%s」了。</msg>\n<msg>%s</msg>\n<msg>放心吧，这边私聊频道（已隔离 %d 件不在场私密与 %d 条未解锁秘密）只有我一个人在回你，有什么想单聊的尽管接着说。</msg>\n</content>\n<dbNote>\n态度: 认真倾听你的话语，语气比初见时柔和了些\n记忆: 玩家在单独对话中提到：%s\n</dbNote>" % [
		clean, ref_line, iso_cnt, sec_cnt, clean.substr(0, 48)
	]
	_commit_bridge_reply(cid, clean, reply_raw)

func _commit_bridge_reply(cid: String, user_text: String, raw_ai_reply: String) -> void:
	gdb.record_bridge_turn(cid, user_text, raw_ai_reply)
	_push_db()
	_autosave()

func db_add_fact(cid: String, content_txt: String, fact_type := "manual") -> void:
	gdb.add_character_fact(cid, content_txt, fact_type)
	_push_db(); _autosave(); g.notify("已写入角色知情记忆")

func db_delete_fact(fact_id: String) -> void:
	gdb.delete_character_fact(fact_id)
	_push_db(); _autosave(); g.notify("已删除知情条目")

func db_save_summary(entry: Dictionary) -> void:
	gdb.save_manual_summary(entry)
	_push_recap(); _push_db(); _autosave(); g.notify("已保存时间线小总结")

func db_delete_summary(sum_id: String) -> void:
	gdb.delete_summary(sum_id)
	_push_recap(); _push_db(); _autosave(); g.notify("已移除该条时间线总结")

func db_update_char_memo(cid: String, patch: Dictionary) -> void:
	gdb.update_character_state(cid, patch)
	_push_db(); _autosave(); g.notify("已更新角色数据库状态")

func db_clear_bridge(cid: String) -> void:
	gdb.clear_bridge_history(cid)
	_push_db(); _autosave(); g.notify("已清空该角色的独立单聊记录")

func db_compress_bridge(cid: String) -> void:
	gdb.compress_bridge_history(cid)
	_push_db(); _autosave(); g.notify("已将该角色早先单聊归纳为摘要")

func unlock_cg(cg_id: String) -> void:
	if gdb.unlock_illustration(cg_id):
		_push_db(); _autosave()

# ---------- floor operations ----------
func _find(id: int) -> Dictionary:
	for m in chat:
		if int(m.id) == id: return m
	return {}

func set_swipe(id: int, index: int) -> void:
	var m := _find(id)
	if m.is_empty(): return
	m.swipe = clampi(index, 0, m.swipes.size() - 1); _push_messages(); _sync_and_push_state(); _autosave()

func append_swipe(id: int, text: String) -> bool:
	var m := _find(id)
	if m.is_empty(): return false
	m.swipes.append(text)
	m.swipe = m.swipes.size() - 1
	_push_messages(); _sync_and_push_state(); _autosave()
	return true

func oracle_apply_stat_patch(ops: Array, label := "故事神谕修正") -> String:
	if ops.is_empty() or chat.is_empty(): return ""
	var clean_ops: Array = []
	for op in ops:
		if op is Dictionary and op.has("path") and op.has("op"):
			clean_ops.append(op.duplicate(true))
	if clean_ops.is_empty(): return ""
	var pid := "op_%d_%d" % [Time.get_unix_time_from_system(), oracle_patches.size() + 1]
	oracle_patches.append({"id": pid, "label": label, "ops": clean_ops, "time": Time.get_datetime_string_from_system(false, true)})
	_sync_and_push_state(); _autosave()
	g.notify("已应用：%s（%d 项）" % [label, clean_ops.size()])
	return pid

func oracle_undo_stat_patch(patch_id: String) -> bool:
	var before := oracle_patches.size()
	oracle_patches = oracle_patches.filter(func(b): return not (b is Dictionary and String(b.get("id", "")) == patch_id))
	if oracle_patches.size() == before: return false
	_sync_and_push_state(); _autosave()
	g.notify("已撤销神谕变量修正")
	return true

func edit_message(id: int, text: String) -> void:
	var m := _find(id)
	if m.is_empty(): return
	m.swipes[int(m.swipe)] = text; _push_messages(); _sync_and_push_state(); _autosave()
	g.notify("已保存修改并重新同步数据库")

func delete_message(id: int) -> void:
	chat = chat.filter(func(m): return int(m.id) != id); _push_messages(); _sync_and_push_state(); _autosave()

func rewind_to(id: int) -> void:
	chat = chat.filter(func(m): return int(m.id) <= id); _push_messages(); _sync_and_push_state(); _autosave()
	g.notify("已回到这一条并同步回溯数据库")

func branch_from(id: int) -> void:
	var keep := chat.filter(func(m): return int(m.id) <= id)
	var free := 1
	while FileAccess.file_exists(SAVE_DIR + "slot_%d.json" % free): free += 1
	_write(free, keep, slot)
	_push_saves(); g.notify("已从这一条另开分支，存进存档位 %d" % free)

func update_persona(p: Dictionary) -> void:
	for k in p: persona[k] = p[k]
	g.apply_snapshot("persona", persona.duplicate(true)); _sync_and_push_state(); _autosave(); g.notify("个人档案已更新")

# ---------- saves ----------
func _write(n: int, messages: Array, parent := -1, custom_title := "") -> void:
	var orig_name := String(_origin_data(origin).get("name", "未定出身"))
	var def_title := "%s · %s" % [persona.get("name", "未署名"), orig_name]
	var title := custom_title if custom_title.strip_edges() != "" else def_title
	var data := {
		"title": title, "time": Time.get_datetime_string_from_system(false, true),
		"persona": persona, "origin": origin, "chat": messages, "next_id": next_id,
		"parent": parent, "macro_recap": macro_recap, "db": gdb.serialize(),
		"base_stat": base_stat_override, "oracle_patches": oracle_patches,
		"format": "demo-save/2",
	}
	var f := FileAccess.open(SAVE_DIR + "slot_%d.json" % n, FileAccess.WRITE)
	if f == null: g.report_error("save", "无法写入存档"); return
	f.store_string(JSON.stringify(data)); f.close()

func _autosave() -> void:
	if UiHub.review_mode or chat.is_empty(): return
	_write(0, chat); _push_saves()

func save_slot(n: int, custom_title := "") -> void:
	_write(n, chat, slot, custom_title); _push_saves(); g.notify("已保存到存档位 %02d（含内置数据库）" % n)

func rename_slot(n: int, new_title: String) -> void:
	var path := SAVE_DIR + "slot_%d.json" % n
	if not FileAccess.file_exists(path): return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		d["title"] = new_title
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f: f.store_string(JSON.stringify(d)); f.close()
		_push_saves(); g.notify("已将存档 %02d 改名为：%s" % [n, new_title])

func load_slot(n: int) -> void:
	var raw := FileAccess.get_file_as_string(SAVE_DIR + "slot_%d.json" % n)
	var d = JSON.parse_string(raw) if raw != "" else null
	if not d is Dictionary: g.report_error("save", "存档无法读取"); return
	slot = n
	_load_dict(d)

func _load_dict(d: Dictionary) -> void:
	persona = d.get("persona", {}); origin = d.get("origin", "sereth"); chat = d.get("chat", [])
	for m in chat: m.id = int(m.id); m.swipe = int(m.swipe)
	next_id = int(d.get("next_id", chat.size())); turn = chat.size() / 2
	var raw_recap = d.get("macro_recap", {})
	macro_recap = raw_recap.duplicate() if raw_recap is Dictionary else {}
	var raw_base = d.get("base_stat", {})
	base_stat_override = raw_base.duplicate(true) if raw_base is Dictionary else {}
	var raw_op = d.get("oracle_patches", [])
	oracle_patches = raw_op.duplicate(true) if raw_op is Array else []
	var raw_db = d.get("db", {})
	if raw_db is Dictionary and not raw_db.is_empty():
		gdb.deserialize(raw_db)
	else:
		gdb.reset_all()
	_push_all()

func delete_slot(n: int) -> void:
	DirAccess.remove_absolute(SAVE_DIR + "slot_%d.json" % n); _push_saves()

func _push_saves() -> void:
	var out: Array = []
	for n in range(0, 9):
		var path := SAVE_DIR + "slot_%d.json" % n
		var d = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if d is Dictionary:
			out.append({"slot": n, "title": d.title, "time": d.time, "used": true, "parent": int(d.get("parent", -1)), "count": d.chat.size()})
		else: out.append({"slot": n, "title": "", "time": "", "used": false, "parent": -1, "count": 0})
	g.apply_snapshot("saves", out)

func export_save() -> void:
	if chat.is_empty(): g.notify("还没有进度可以导出"); return
	DirAccess.make_dir_recursive_absolute("user://exports")
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path := "user://exports/艾瑟拉存档_%s.json" % stamp
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"persona": persona, "origin": origin, "chat": chat, "next_id": next_id,
		"macro_recap": macro_recap, "db": gdb.serialize(),
		"base_stat": base_stat_override, "oracle_patches": oracle_patches,
		"format": "demo-save/2",
	})); f.close()
	g.notify("已导出到 " + ProjectSettings.globalize_path(path))

func import_save(path: String) -> void:
	var raw := FileAccess.get_file_as_string(path)
	if raw.strip_edges() == "":
		g.report_error("save", "文件为空或无法读取"); return
	var clean_raw := raw.strip_edges()
	if clean_raw.begins_with(String.chr(0xFEFF)):
		clean_raw = clean_raw.substr(1).strip_edges()
	var parsed: Variant = null
	var is_jsonl := path.to_lower().ends_with(".jsonl") or ".jsonl." in path.to_lower()
	if not is_jsonl:
		var jp := JSON.new()
		if jp.parse(clean_raw) == OK:
			parsed = jp.data
	if parsed is Dictionary and parsed.has("chat"):
		_load_dict(parsed); _autosave(); g.notify("存档与内置数据库已导入"); return
	var st_dict := _parse_sillytavern_save(clean_raw, parsed)
	if st_dict.is_empty() or not st_dict.has("chat"):
		g.report_error("save", "这个文件不是可用的游戏存档或酒馆 .jsonl 聊天记录")
		return
	_load_dict(st_dict)
	_autosave()
	var cnt := (st_dict.get("chat", []) as Array).size()
	var loc := String(st_dict.get("base_stat", {}).get("主角组", {}).get("当前地点", "艾瑟拉"))
	g.notify("已导入酒馆存档（%d 条消息 · %s），已同步至内置数据库与当前进度" % [cnt, loc])

func _parse_sillytavern_save(clean_raw: String, pre_parsed) -> Dictionary:
	var rows: Array = []
	if pre_parsed is Array:
		rows = pre_parsed
	else:
		for line in clean_raw.replace("\r\n", "\n").split("\n"):
			var l := line.strip_edges()
			if l == "": continue
			var obj = JSON.parse_string(l)
			if obj is Dictionary: rows.append(obj)
	if rows.is_empty(): return {}

	var header: Dictionary = {}
	var start_idx := 0
	var first_r: Dictionary = rows[0] if rows[0] is Dictionary else {}
	if first_r.has("chat_metadata") or (first_r.has("character_name") and not first_r.has("mes")):
		header = first_r
		start_idx = 1

	var chat_meta: Dictionary = header.get("chat_metadata", {}) if header.get("chat_metadata") is Dictionary else {}
	var meta_vars: Dictionary = chat_meta.get("variables", {}) if chat_meta.get("variables") is Dictionary else {}
	var first_sd: Dictionary = {}
	var last_sd: Dictionary = {}
	if meta_vars.get("stat_data") is Dictionary:
		first_sd = meta_vars.stat_data.duplicate(true)
		last_sd = meta_vars.stat_data.duplicate(true)

	var raw_user := String(header.get("user_name", "")).strip_edges()
	if raw_user in ["", "unused", "{{user}}"]: raw_user = "主角"

	var conv_chat: Array = []
	var cid_seq := 0
	for i in range(start_idx, rows.size()):
		var r = rows[i]
		if not r is Dictionary: continue
		var vars_arr = r.get("variables", [])
		if vars_arr is Array and not vars_arr.is_empty():
			var sw_v := clampi(int(r.get("swipe_id", 0)) if r.get("swipe_id") != null else 0, 0, vars_arr.size() - 1)
			var vslot = vars_arr[sw_v] if vars_arr[sw_v] is Dictionary else vars_arr[0]
			if vslot is Dictionary and vslot.get("stat_data") is Dictionary:
				var sd: Dictionary = vslot.stat_data
				if first_sd.is_empty(): first_sd = sd.duplicate(true)
				last_sd = sd.duplicate(true)
		if bool(r.get("is_system", false)):
			continue
		var is_u := bool(r.get("is_user", false))
		var role_s := "user" if is_u else "assistant"
		var sender := String(r.get("name", raw_user if is_u else "艾瑟拉")).strip_edges()
		if sender in ["", "{{user}}"]: sender = raw_user
		elif sender == "{{char}}": sender = "艾瑟拉"

		var swipes_out: Array = []
		if r.get("swipes") is Array:
			for sw in r.swipes:
				swipes_out.append(String(sw))
		var active_mes := String(r.get("mes", ""))
		var sw_idx := int(r.get("swipe_id", 0)) if r.get("swipe_id") != null else 0
		if swipes_out.is_empty():
			if active_mes == "" and i > start_idx: continue
			swipes_out = [active_mes]
			sw_idx = 0
		else:
			sw_idx = clampi(sw_idx, 0, swipes_out.size() - 1)
			if active_mes != "" and String(swipes_out[sw_idx]) != active_mes:
				swipes_out[sw_idx] = active_mes
		conv_chat.append({
			"id": cid_seq,
			"role": role_s,
			"name": sender,
			"swipes": swipes_out,
			"swipe": sw_idx,
			"data": {"st_send_date": String(r.get("send_date", ""))},
		})
		cid_seq += 1

	if conv_chat.is_empty(): return {}

	var inferred_origin := _infer_origin_from_stat(last_sd if not last_sd.is_empty() else first_sd)
	var rec_hero: Dictionary = (last_sd if not last_sd.is_empty() else first_sd).get("主角组", {})
	var bio_txt := String(rec_hero.get("简介", ""))
	var st_persona := {"name": raw_user, "race": "未定", "origin": inferred_origin, "appearance": "", "bio": bio_txt}

	# Check whether patch replay from first_sd produces last_sd; if not, emit an alignment patch
	var sim_stat: Dictionary = first_sd.duplicate(true)
	for cm in conv_chat:
		if String(cm.get("role", "")) != "assistant": continue
		var act := String(cm.swipes[int(cm.swipe)])
		var rp: Dictionary = Parser.parse(act)
		if String(rp.get("patch", "")) == "": continue
		var p_ops = JSON.parse_string(String(rp.patch))
		if p_ops is Array:
			for op in p_ops: _apply(sim_stat, op)
	var align_patches: Array = []
	if not last_sd.is_empty():
		var diff_ops: Array = []
		_diff_stat_dict(sim_stat, last_sd, "", diff_ops)
		if not diff_ops.is_empty():
			align_patches.append({
				"id": "st_import_align",
				"label": "酒馆存档最终状态对齐",
				"ops": diff_ops,
				"time": Time.get_datetime_string_from_system(false, true),
			})

	return {
		"format": "demo-save/2",
		"title": "%s · 酒馆记录导入" % raw_user,
		"time": Time.get_datetime_string_from_system(false, true),
		"persona": st_persona,
		"origin": inferred_origin,
		"chat": conv_chat,
		"next_id": cid_seq,
		"macro_recap": {},
		"base_stat": first_sd,
		"oracle_patches": align_patches,
		"db": {},
	}

func _infer_origin_from_stat(sd: Dictionary) -> String:
	var h: Dictionary = sd.get("主角组", {}) if sd.get("主角组") is Dictionary else {}
	var loc := String(h.get("当前地点", ""))
	var roles: Dictionary = sd.get("角色组", {}) if sd.get("角色组") is Dictionary else {}
	if "蛇杖" in loc or roles.has("冰糖"): return "staff"
	if "奥马努特" in loc or roles.has("明空"): return "omanut"
	if "龙渊" in loc or roles.has("焰渊"): return "longyuan"
	if "格洛里亚" in loc or roles.has("艾利丝"): return "gloria"
	if "秋津" in loc or roles.has("阳向"): return "akitsu"
	if "吉万沙克蒂" in loc or roles.has("阿兰雅"): return "jwanshakti"
	return "sereth"

func _diff_stat_dict(cur: Dictionary, want: Dictionary, prefix: String, out_ops: Array) -> void:
	for k in want:
		var path := prefix + "/" + String(k)
		var wv = want[k]
		if not cur.has(k):
			out_ops.append({"op": "insert", "path": path, "value": wv})
		elif cur[k] is Dictionary and wv is Dictionary:
			_diff_stat_dict(cur[k], wv, path, out_ops)
		elif (typeof(cur[k]) in [TYPE_INT, TYPE_FLOAT]) and (typeof(wv) in [TYPE_INT, TYPE_FLOAT]):
			if not is_equal_approx(float(cur[k]), float(wv)):
				out_ops.append({"op": "replace", "path": path, "value": wv})
		elif typeof(cur[k]) != typeof(wv) or cur[k] != wv:
			out_ops.append({"op": "replace", "path": path, "value": wv})
	for k in cur:
		if not want.has(k):
			out_ops.append({"op": "remove", "path": prefix + "/" + String(k)})

# ---------- connection & presets ----------
func _sanitized_profiles() -> Array:
	var out: Array = []
	for p in _conn_profiles:
		if not p is Dictionary: continue
		out.append({
			"id": String(p.get("id", "")),
			"name": String(p.get("name", "未命名配置")),
			"format": String(p.get("format", "openai")),
			"mode": String(p.get("mode", "chat")),
			"url": String(p.get("url", "")),
			"model": String(p.get("model", "")),
			"has_key": String(p.get("key", "")).strip_edges() != "",
		})
	return out

func _push_connection(status := "none", message := "", models: Array = []) -> void:
	var c := _conn_cfg()
	g.apply_snapshot("connection", {
		"profile_id": c.id,
		"profile_name": c.name,
		"profiles": _sanitized_profiles(),
		"format": c.format,
		"mode": c.mode,
		"url": c.url,
		"model": c.model,
		"has_key": String(c.key) != "",
		"status": status,
		"message": message,
		"models": models,
	})

func _infer_profile_name(c: Dictionary, fallback_idx: int) -> String:
	var raw_name := String(c.get("name", "")).strip_edges()
	if raw_name != "": return raw_name
	var mod_s := String(c.get("model", "")).strip_edges()
	if mod_s != "": return mod_s
	var url_s := String(c.get("url", "")).strip_edges()
	if "://" in url_s:
		var host := url_s.get_slice("://", 1).get_slice("/", 0)
		if host != "": return host
	return "API 配置 %d" % fallback_idx

func set_connection(c: Dictionary) -> void:
	if _conn_profiles.is_empty(): _load_conn_profiles()
	var as_new := bool(c.get("as_new", false))
	var target_id := String(c.get("id", "")).strip_edges()
	var idx := -1
	if not as_new:
		var want_id := target_id if target_id != "" else _active_conn_id
		for i in range(_conn_profiles.size()):
			if String(_conn_profiles[i].get("id", "")) == want_id:
				idx = i; break
	if as_new or idx < 0:
		var seq := _conn_profiles.size() + 1
		var new_id := "api_%d_%d" % [Time.get_unix_time_from_system(), seq]
		while _conn_profiles.any(func(p): return String(p.get("id", "")) == new_id):
			seq += 1
			new_id = "api_%d_%d" % [Time.get_unix_time_from_system(), seq]
		var entry := {
			"id": new_id,
			"name": _infer_profile_name(c, seq),
			"format": String(c.get("format", "openai")),
			"mode": String(c.get("mode", "chat")),
			"url": String(c.get("url", "")).strip_edges(),
			"model": String(c.get("model", "")).strip_edges(),
			"key": String(c.get("key", "")).strip_edges(),
		}
		_conn_profiles.append(entry)
		_active_conn_id = new_id
	else:
		var cur: Dictionary = _conn_profiles[idx].duplicate()
		for k in ["format", "mode", "url", "model"]:
			if c.has(k): cur[k] = String(c[k]).strip_edges() if k in ["url", "model"] else c[k]
		if c.has("name"):
			var nm := String(c.get("name", "")).strip_edges()
			cur["name"] = nm if nm != "" else _infer_profile_name(cur, idx + 1)
		elif String(cur.get("name", "")) in ["", "默认连接"]:
			cur["name"] = _infer_profile_name(cur, idx + 1)
		if String(c.get("key", "")).strip_edges() != "":
			cur["key"] = String(c.key).strip_edges()
		_conn_profiles[idx] = cur
		_active_conn_id = String(cur.get("id", "default"))
	_save_conn_profiles()
	_push_connection("none", "已保存在本机。")

func select_connection_profile(profile_id: String) -> void:
	if _conn_profiles.is_empty(): _load_conn_profiles()
	var clean := profile_id.strip_edges()
	var found := false
	for p in _conn_profiles:
		if String(p.get("id", "")) == clean:
			found = true; break
	if not found: return
	_active_conn_id = clean
	_save_conn_profiles()
	var c := _conn_cfg()
	_push_connection("none", "已切换到：" + c.name)
	g.notify("已切换 API 配置：" + c.name)

func delete_connection_profile(profile_id: String) -> void:
	if _conn_profiles.is_empty(): _load_conn_profiles()
	var clean := profile_id.strip_edges()
	if _conn_profiles.size() <= 1:
		_conn_profiles = [{"id": "default", "name": "默认连接", "format": "openai", "mode": "chat", "url": "", "model": "", "key": ""}]
		_active_conn_id = "default"
	else:
		_conn_profiles = _conn_profiles.filter(func(p): return String(p.get("id", "")) != clean)
		if _active_conn_idx() < 0 or _active_conn_id == clean:
			_active_conn_id = String(_conn_profiles[0].get("id", "default"))
	_save_conn_profiles()
	_push_connection("none", "已移除该 API 配置。")
	g.notify("已移除所选 API 配置")

func test_connection() -> void:
	var c := _conn_cfg()
	if (String(c.get("url", "")).begins_with("http://") or String(c.get("url", "")).begins_with("https://")) and not OS.has_feature("web") and not test_replies_enabled:
		_push_connection("testing", "正在向服务商校验模型接口…")
		var base: String = String(c.get("url", "")).trim_suffix("/")
		var req := HTTPRequest.new(); req.timeout = 15.0; g.add_child(req)
		var headers := PackedStringArray()
		if c.key != "": headers.append("Authorization: Bearer " + c.key)
		req.request_completed.connect(func(result: int, code: int, _hdrs: PackedStringArray, _body: PackedByteArray):
			req.queue_free()
			if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
				_push_connection("ok", "服务商连通正常（HTTP %d）" % code)
			else:
				_push_connection("fail", "连接失败：HTTP %d (result %d)" % [code, result])
		, CONNECT_ONE_SHOT)
		if req.request(base + "/models", headers, HTTPClient.METHOD_GET) != OK:
			req.queue_free()
			_push_connection("fail", "无法发起网络请求")
		return
	_push_connection("testing", "正在检查…")
	var t: SceneTreeTimer = g.get_tree().create_timer(0.4)
	t.timeout.connect(func(): _push_connection("pending", "请填写 API 地址后点击测试连接（浏览器预览不发外网请求）。"))

func list_models() -> void:
	var c := _conn_cfg()
	if (String(c.get("url", "")).begins_with("http://") or String(c.get("url", "")).begins_with("https://")) and not OS.has_feature("web") and not test_replies_enabled:
		_push_connection("testing", "正在拉取模型列表…")
		var base: String = String(c.get("url", "")).trim_suffix("/")
		var req := HTTPRequest.new(); req.timeout = 20.0; g.add_child(req)
		var headers := PackedStringArray()
		if c.key != "": headers.append("Authorization: Bearer " + c.key)
		req.request_completed.connect(func(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray):
			req.queue_free()
			if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
				var d = JSON.parse_string(body.get_string_from_utf8())
				var mlist: Array = []
				if d is Dictionary and d.get("data") is Array:
					for item in d.data:
						if item is Dictionary and item.has("id"): mlist.append(String(item.id))
				_push_connection("ok", "已获取 %d 个可用模型" % mlist.size(), mlist)
			else:
				_push_connection("fail", "拉取模型失败：HTTP %d" % code)
		, CONNECT_ONE_SHOT)
		if req.request(base + "/models", headers, HTTPClient.METHOD_GET) != OK:
			req.queue_free()
			_push_connection("fail", "无法连接模型端点")
		return
	if not _can_generate(): return
	_push_connection("none", "已读取模型列表（演示模式示例列表）", [
		"deepseek-chat", "deepseek-reasoner", "gpt-4o", "gpt-4o-mini", "claude-3-5-sonnet-20241022", "qwen-plus", "qwen-max"
	])

func _push_presets() -> void:
	var entries := get_preset_entries()
	var en_cnt := 0
	var mod_cnt := 0
	for e in entries:
		if bool(e.get("enabled", false)): en_cnt += 1
		if bool(e.get("modified", false)): mod_cnt += 1
	g.apply_snapshot("presets", [{
		"id": active_preset_id,
		"name": active_preset_name,
		"active": true,
		"entry_count": entries.size(),
		"enabled_count": en_cnt,
		"modified_count": mod_cnt,
	}])

func import_preset(path: String) -> void:
	_load_bundled_preset(path)
	_push_presets()
	g.notify("已加载预设：" + active_preset_name)

func use_preset(_id: String) -> void: pass
