extends Node
## game-port/1 transport only. ST owns chat, generation, MVU and persistence.
## Exposed only by the packaged desktop preload; ordinary browser/native previews stay demo.

var g: Node
var bridge: JavaScriptObject
var elapsed := 0.0

func attach(game: Node) -> void:
	g = game
	g.add_child(self)
	bridge = JavaScriptBridge.get_interface("aetheraBackend")
	_send("attach", [g.PORT_VERSION])

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.05 or bridge == null: return
	elapsed = 0.0
	var batch = JSON.parse_string(String(bridge.drain()))
	if not batch is Array: return
	for event in batch:
		if not event is Dictionary: continue
		match String(event.get("type", "")):
			"snapshot": g.apply_snapshot(String(event.part), event.value)
			"error":
				if event.kind == "api_configuration" and event.has("action"):
					g.action_rejected.emit(String(event.action.text), String(event.action.source))
				g.report_error(String(event.kind), String(event.message))
			"notice": g.notify(String(event.message))

func _send(method: String, args: Array = []) -> void:
	if bridge == null:
		g.report_error("resource", "桌面后端连接已断开，请重新启动软件")
		return
	bridge.send(JSON.stringify({"method": method, "args": args}))

func new_game(p: Dictionary, origin: String) -> void: _send("new_game", [p, origin])
func send_action(text: String, source: String) -> void: _send("send_action", [text, source])
func stop_generation() -> void: _send("stop_generation")
func regenerate(id: int) -> void: _send("regenerate", [id])
func continue_reply(id: int) -> void: _send("continue_reply", [id])
func set_swipe(id: int, index: int) -> void: _send("set_swipe", [id, index])
func append_swipe(id: int, text: String) -> bool: _send("append_swipe", [id, text]); return true
func oracle_apply_stat_patch(ops: Array, label := "故事神谕修正") -> String: _send("oracle_apply_stat_patch", [ops, label]); return "remote"
func oracle_undo_stat_patch(patch_id: String) -> bool: _send("oracle_undo_stat_patch", [patch_id]); return true
func edit_message(id: int, text: String) -> void: _send("edit_message", [id, text])
func delete_message(id: int) -> void: _send("delete_message", [id])
func rewind_to(id: int) -> void: _send("rewind_to", [id])
func branch_from(id: int) -> void: _send("branch_from", [id])
func save_slot(slot: int, title := "") -> void: _send("save_slot", [slot, title])
func rename_slot(slot: int, title: String) -> void: _send("rename_slot", [slot, title])
func load_slot(slot: int) -> void: _send("load_slot", [slot])
func delete_slot(slot: int) -> void: _send("delete_slot", [slot])
func export_save() -> void: _send("export_save")
func import_save(path: String) -> void: _send("import_save", [path])
func set_connection(cfg: Dictionary) -> void: _send("set_connection", [cfg])
func select_connection_profile(profile_id: String) -> void: _send("select_connection_profile", [profile_id])
func delete_connection_profile(profile_id: String) -> void: _send("delete_connection_profile", [profile_id])
func test_connection() -> void: _send("test_connection")
func list_models() -> void: _send("list_models")
func import_preset(path: String) -> void: _send("import_preset", [path])
func use_preset(id: String) -> void: _send("use_preset", [id])
func set_preset_entry(identifier: String, patch: Dictionary) -> void: _send("set_preset_entry", [identifier, patch])
func reset_preset_overrides() -> void: _send("reset_preset_overrides")
func update_persona(p: Dictionary) -> void: _send("update_persona", [p])
func begin_custom_opening() -> void: _send("begin_custom_opening")
func generate_macro_summary() -> void: _send("generate_macro_summary")
func save_macro_summary(text: String) -> void: _send("save_macro_summary", [text])
func send_bridge_chat(cid: String, text: String) -> void: _send("send_bridge_chat", [cid, text])
func db_add_fact(cid: String, content: String, fact_type := "manual") -> void: _send("db_add_fact", [cid, content, fact_type])
func db_delete_fact(fact_id: String) -> void: _send("db_delete_fact", [fact_id])
func db_save_summary(entry: Dictionary) -> void: _send("db_save_summary", [entry])
func db_delete_summary(sum_id: String) -> void: _send("db_delete_summary", [sum_id])
func db_update_char_memo(cid: String, patch: Dictionary) -> void: _send("db_update_char_memo", [cid, patch])
func db_clear_bridge(cid: String) -> void: _send("db_clear_bridge", [cid])
func db_compress_bridge(cid: String) -> void: _send("db_compress_bridge", [cid])
