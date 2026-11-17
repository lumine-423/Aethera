extends Node
## Autoload "Game": the only door between the UI and the back end (前端设计/04_前后端接口清单.md).
## The UI reads snapshots from here and sends requests through here. A back-end adapter does the
## real work; the bundled DemoBackend never touches the network and labels its replies as demo.

signal changed(part: String)
signal error_reported(kind: String, message: String)
signal notice(message: String)
signal action_rejected(text: String, source: String)

const DemoBackend = preload("res://scripts/game/demo_backend.gd")
const DesktopBackend = preload("res://scripts/game/desktop_backend.gd")
const GameDatabase = preload("res://scripts/game/game_database.gd")
const PORT_VERSION := "game-port/1"

var messages: Array = []
var stat: Dictionary = {}
var persona: Dictionary = {}
var connection: Dictionary = {"format": "openai", "mode": "chat", "url": "", "model": "", "has_key": false, "status": "none", "message": ""}
var saves: Array = []
var presets: Array = []
var generation: Dictionary = {"busy": false, "kind": "", "stream": ""}
var recap: Dictionary = {"text": "", "summary_count": 0, "source_count": 0, "updated_at": ""}
var db: Dictionary = {}
var backend: Object
var demo := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	db = GameDatabase.new().snapshot()
	if is_instance_valid(UiHub) and not UiHub.action_requested.is_connected(_on_ui_action):
		UiHub.action_requested.connect(_on_ui_action)
	if OS.has_feature("web") and JavaScriptBridge.get_interface("aetheraBackend") != null:
		use_backend(DesktopBackend.new())
	else:
		use_backend(DemoBackend.new(), true)

func _on_ui_action(action: String, payload: Dictionary) -> void:
	if action == "character.chat":
		var cid := String(payload.get("character", ""))
		var txt := String(payload.get("text", "")).strip_edges()
		if cid != "" and txt != "":
			send_bridge_chat(cid, txt)

## Swap the adapter. A real back end calls this once at start-up.
func use_backend(b: Object, is_demo := false) -> void:
	backend = b; demo = is_demo
	if backend.has_method("attach"): backend.attach(self)
	changed.emit("backend")

## ---------- back end -> UI ----------
func apply_snapshot(part: String, value) -> void:
	match part:
		"messages": messages = value
		"stat": stat = value
		"persona": persona = value
		"connection": connection = value
		"saves": saves = value
		"presets": presets = value
		"generation": generation = value
		"recap": recap = value
		"db": db = value
		_: push_warning("unknown snapshot part " + part); return
	changed.emit(part)

func report_error(kind: String, message: String) -> void:
	error_reported.emit(kind, message)

## Short status line for the player (a toast), e.g. "已导出到 …".
func notify(message: String) -> void:
	notice.emit(message)

## ---------- UI -> back end ----------
func _call(method: String, args := []) -> void:
	if backend == null or not backend.has_method(method):
		report_error("resource", "后端没有实现 " + method); return
	backend.callv(method, args)

func new_game(p: Dictionary, origin_key: String) -> void: _call("new_game", [p, origin_key])
func retry_custom_opening() -> void:
	if not generation.get("busy", false) and ensure_generation_ready():
		_call("begin_custom_opening")
func send_action(text: String, source := "free") -> void:
	if generation.get("busy", false) or text.strip_edges() == "": return
	if not ensure_generation_ready(): return
	_call("send_action", [text.strip_edges(), source])
func stop_generation() -> void: _call("stop_generation")
func regenerate(id: int) -> void:
	if not generation.get("busy", false) and ensure_generation_ready(): _call("regenerate", [id])
func continue_reply(id: int) -> void:
	if not generation.get("busy", false) and ensure_generation_ready(): _call("continue_reply", [id])

func generate_macro_summary() -> void:
	if not generation.get("busy", false) and ensure_generation_ready(): _call("generate_macro_summary")

func save_macro_summary(text: String) -> void:
	_call("save_macro_summary", [text])

## True when an actual endpoint + model (or connected key) is configured, ignoring offline test bypass.
func has_configured_api() -> bool:
	if backend != null and backend.has_method("is_api_configured"):
		return bool(backend.is_api_configured())
	if bool(connection.get("has_key", false)): return true
	var endpoint := String(connection.get("url", "")).strip_edges()
	if not (endpoint.begins_with("https://") or endpoint.begins_with("http://")): return false
	if endpoint.get_slice("://", 1).get_slice("/", 0) == "": return false
	return String(connection.get("model", "")).strip_edges() != ""

## A saved connection need not have been tested this session. Custom ST endpoints may be keyless.
func ensure_generation_ready() -> bool:
	if demo and backend != null and bool(backend.get("test_replies_enabled")): return true
	var endpoint := String(connection.get("url", "")).strip_edges()
	if not (endpoint.begins_with("https://") or endpoint.begins_with("http://")) or endpoint.get_slice("://", 1).get_slice("/", 0) == "" or String(connection.get("model", "")).strip_edges() == "":
		report_error("api_configuration", "尚未配置完整的 API。请填写有效的接口地址和模型名称后再发送。")
		return false
	if demo and OS.has_feature("web"):
		report_error("api_configuration", "当前浏览器预览尚未连接真实 AI。请使用桌面版配置 API 后继续。")
		return false
	return true
func set_swipe(id: int, index: int) -> void: _call("set_swipe", [id, index])
func append_swipe(id: int, text: String) -> bool:
	if backend != null and backend.has_method("append_swipe"):
		return bool(backend.append_swipe(id, text))
	return false
func oracle_apply_stat_patch(ops: Array, label := "故事神谕修正") -> String:
	if backend != null and backend.has_method("oracle_apply_stat_patch"):
		return String(backend.oracle_apply_stat_patch(ops, label))
	return ""
func oracle_undo_stat_patch(patch_id: String) -> bool:
	if backend != null and backend.has_method("oracle_undo_stat_patch"):
		return bool(backend.oracle_undo_stat_patch(patch_id))
	return false
func edit_message(id: int, text: String) -> void: _call("edit_message", [id, text])
func delete_message(id: int) -> void: _call("delete_message", [id])
func rewind_to(id: int) -> void: _call("rewind_to", [id])
func branch_from(id: int) -> void: _call("branch_from", [id])
func save_slot(slot: int, title := "") -> void: _call("save_slot", [slot, title])
func rename_slot(slot: int, title: String) -> void: _call("rename_slot", [slot, title])
func load_slot(slot: int) -> void: _call("load_slot", [slot])
func delete_slot(slot: int) -> void: _call("delete_slot", [slot])
func export_save() -> void: _call("export_save")
func import_save(path: String) -> void: _call("import_save", [path])
func set_connection(cfg: Dictionary) -> void: _call("set_connection", [cfg])
func select_connection_profile(profile_id: String) -> void: _call("select_connection_profile", [profile_id])
func delete_connection_profile(profile_id: String) -> void: _call("delete_connection_profile", [profile_id])
func test_connection() -> void: _call("test_connection")
func list_models() -> void: _call("list_models")
func import_preset(path: String) -> void: _call("import_preset", [path])
func use_preset(id: String) -> void: _call("use_preset", [id])
func preset_entries() -> Array:
	if backend != null and backend.has_method("get_preset_entries"):
		return backend.get_preset_entries()
	return []
func set_preset_entry(identifier: String, patch: Dictionary) -> void: _call("set_preset_entry", [identifier, patch])
func reset_preset_overrides() -> void: _call("reset_preset_overrides")
func update_persona(p: Dictionary) -> void: _call("update_persona", [p])

## ---------- built-in database & 1-on-1 isolated bridge chat ----------
func send_bridge_chat(cid: String, text: String) -> void:
	var clean := text.strip_edges()
	if cid == "" or clean == "": return
	if not ensure_generation_ready(): return
	_call("send_bridge_chat", [cid, clean])

func db_add_fact(cid: String, content: String, fact_type := "manual") -> void:
	_call("db_add_fact", [cid, content, fact_type])

func db_delete_fact(fact_id: String) -> void:
	_call("db_delete_fact", [fact_id])

func db_save_summary(entry: Dictionary) -> void:
	_call("db_save_summary", [entry])

func db_delete_summary(sum_id: String) -> void:
	_call("db_delete_summary", [sum_id])

func db_update_char_memo(cid: String, patch: Dictionary) -> void:
	_call("db_update_char_memo", [cid, patch])

func db_clear_bridge(cid: String) -> void:
	_call("db_clear_bridge", [cid])

func db_compress_bridge(cid: String) -> void:
	_call("db_compress_bridge", [cid])

func db_summaries() -> Array:
	return db.get("timeline_summaries", [])

func db_char_state(cid: String) -> Dictionary:
	return db.get("character_states", {}).get(cid, {})

func db_char_facts(cid: String) -> Array:
	var out: Array = []
	for f in db.get("character_knowledge_facts", []):
		if f is Dictionary and String(f.get("character_id", "")) == cid:
			out.append(f)
	return out

func db_bridge_log(cid: String) -> Dictionary:
	return db.get("bridge_dialogues", {}).get(cid, {"summary": "", "messages": []})

func db_summaries_for_char(cid: String) -> Dictionary:
	var visible: Array = []
	var hidden_count := 0
	for s in db_summaries():
		if not s is Dictionary: continue
		var vis := String(s.get("visibility", "present_only"))
		var parts: Array = s.get("participants", [])
		if vis == "world_public" or cid in parts:
			visible.append(s)
		else:
			hidden_count += 1
	return {"visible": visible, "hidden_private_count": hidden_count}

func preview_bridge_context(cid: String, draft_text := "") -> Dictionary:
	if backend != null and backend.has_method("preview_bridge_context"):
		return backend.preview_bridge_context(cid, draft_text)
	var tmp := GameDatabase.new()
	tmp.deserialize(db)
	tmp.sync_from_game("main", messages, stat, persona)
	return tmp.build_bridge_context(cid, draft_text)

## ---------- read helpers for screens ----------
func has_story() -> bool:
	return not messages.is_empty()

func message(id: int) -> Dictionary:
	for m in messages:
		if int(m.id) == id: return m
	return {}

func text_of(m: Dictionary) -> String:
	var sw: Array = m.get("swipes", [""])
	return String(sw[clampi(int(m.get("swipe", 0)), 0, maxi(sw.size() - 1, 0))]) if not sw.is_empty() else ""

func last_assistant_id() -> int:
	for i in range(messages.size() - 1, -1, -1):
		if messages[i].role == "assistant": return int(messages[i].id)
	return -1

func hero() -> Dictionary:
	return stat.get("主角组", {})

func known() -> Dictionary:
	return stat.get("角色组", {})

## Ordered character IDs actually unlocked/encountered in the current story/save
## (present in stat_data["角色组"] or marked met in GameDatabase). Empty until met.
func unlocked_ids(include_npcs := true) -> Array:
	const D = preload("res://scripts/ui/ui_data.gd")
	var k: Dictionary = known()
	var cs: Dictionary = db.get("character_states", {})
	var out: Array = []
	for cid_raw in D.roster(include_npcs):
		var cid := String(cid_raw)
		var cname := D.name_of(cid)
		var in_known := k.has(cname) and k[cname] is Dictionary
		var is_met := cs.has(cid) and cs[cid] is Dictionary and bool(cs[cid].get("met", false))
		if in_known or is_met:
			out.append(cid)
	return out

func unlocked_cgs() -> Array:
	var list = db.get("unlocked_illustrations", [])
	return list.duplicate() if list is Array else []

func is_cg_unlocked(cg_id: String) -> bool:
	var clean := cg_id.strip_edges()
	return clean != "" and clean in unlocked_cgs()

func unlock_cg(cg_id: String) -> void:
	var clean := cg_id.strip_edges()
	if clean == "": return
	if backend != null and backend.has_method("unlock_cg"):
		backend.unlock_cg(clean)
		return
	var list: Array = unlocked_cgs()
	if not clean in list:
		list.append(clean)
		db["unlocked_illustrations"] = list
		changed.emit("db")

func events() -> Dictionary:
	return stat.get("剧情事件", {})

func connected() -> bool:
	return connection.get("status", "none") == "ok"
