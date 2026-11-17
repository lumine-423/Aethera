extends Control
## Player shell + provisional party rules. Old host probe remains separate.
const Rules = preload("res://scripts/combat_rules.gd")
const Flow = preload("res://scripts/app_flow.gd")
const Saves = preload("res://scripts/save_service.gd")
const UiTheme = preload("res://scripts/ui_theme.gd")
const Ui = preload("res://scripts/ui_components.gd")
const Art = preload("res://scripts/ui_art.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
const Lobby = preload("res://scripts/views/lobby_view.gd")
const Operations = preload("res://scripts/views/operation_views.gd")
const Roster = preload("res://scripts/views/roster_views.gd")
const Battle = preload("res://scripts/views/battle_view.gd")
const Archive = preload("res://scripts/views/archive_views.gd")
const SystemViews = preload("res://scripts/views/system_views.gd")
var rules = Rules.new()
var flow = Flow.new()
var page: String:
	get: return flow.current
	set(value): flow.open(value)
var store = Saves.new()
var presentation = Presentation.new()
var platform: Variant
var read_only := false
var selected_profile := "rin"
var selected_report := 0
var actor_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors.json"))
var personality: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/character_profiles.json"))
var battlefield: Control
var sound: AudioStreamPlayer
var pending_import: Dictionary = {}
var focus_before_modal: WeakRef
var platform_poll := 0.0
var party: Array = ["rin", "mingkong"]
var mission := "training.basic"
var selected_actor := "rin"
var selected_action := ""
var selected_target := ""
var records: Array = []
var settings := {"motion":true,"large_text":false,"sfx_volume":0.6}
var saved_battle: Dictionary = {}
var save_error := ""
var save_blocked := false
var paused := false
var busy := false
var message := ""
var body: VBoxContainer
var root_column: VBoxContainer
var compact := false
var confirmation: ConfirmationDialog
var scroll_view: ScrollContainer
var last_page := ""
var modal_shade: ColorRect


func _ready() -> void:
	var appearance := ConfigFile.new()
	if appearance.load("user://ui_appearance.cfg") == OK:
		var saved_mode: String = str(appearance.get_value("ui","mode","day"))
		if saved_mode in ["day","night"]: UiTheme.mode = saved_mode
	if OS.has_feature("web"):
		platform = JavaScriptBridge.get_interface("rolecardPlatform")
		read_only = platform == null or str(platform.writer_state()) != "writable"
	_load_save()
	sound = AudioStreamPlayer.new(); sound.stream = load("res://assets/audio/ui-confirm.wav"); add_child(sound); _apply_volume()
	resized.connect(_resize)
	_render()
	if platform != null: platform.ready()

func _resize() -> void:
	if not flow.modal.is_empty(): return
	var next: bool = size.x < 760
	if next != compact:
		compact = next
		_render()

func _box(color: String = "202a35", border: String = "3e4a57") -> StyleBoxFlat:
	return UiTheme.panel(color,border)

func _render() -> void:
	compact = size.x < 760
	var old_scroll: int = scroll_view.scroll_vertical if is_instance_valid(scroll_view) and page == last_page else 0
	last_page = page
	for child in get_children():
		if child == sound: continue
		remove_child(child); child.queue_free()
	theme = UiTheme.build(settings.large_text)
	var background := Art.new(); background.kind = "backdrop"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll_view = scroll
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	scroll.set_deferred("scroll_vertical",old_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,16 if compact else 28)
	scroll.add_child(margin)
	root_column = VBoxContainer.new()
	root_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_column.add_theme_constant_override("separation",18)
	margin.add_child(root_column)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation",12)
	var seal := Ui.art("sigil",42); seal.custom_minimum_size.x = 42; seal.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; brand.add_child(seal)
	brand.add_child(_label("艾瑟拉",24))
	var spacer := Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL; brand.add_child(spacer)
	if not compact: brand.add_child(_label("行动室 · 本地演练",14,UiTheme.color("muted")))
	var mode_button := _button("夜间" if UiTheme.mode == "day" else "日间",_toggle_appearance)
	mode_button.custom_minimum_size.x = 74; brand.add_child(mode_button)
	root_column.add_child(brand)
	var nav := HFlowContainer.new()
	nav.add_theme_constant_override("h_separation",8)
	if page not in ["home","battle"]: nav.add_child(_button("‹ 返回",_go_back))
	for entry in [["home","行动室"],["missions","作战"],["roster","角色"],["party","编队"],["records","战报"],["settings","设置"]]:
		var target_page: String = entry[0]
		var nav_button := _button(entry[1],func(): _navigate(target_page),page == "battle")
		if page == target_page: UiTheme.apply_button(nav_button,"selected")
		nav.add_child(nav_button)
	if page not in ["home","battle"]: root_column.add_child(nav)
	else: nav.queue_free()
	if read_only: root_column.add_child(_label("当前为只读窗口：请关闭另一个游戏窗口后重试。",17,Color("dac48e")))
	body = VBoxContainer.new(); body.add_theme_constant_override("separation",16); root_column.add_child(body)
	match page:
		"home": _home()
		"missions": _missions()
		"mission_detail": Operations.detail(self,body)
		"roster": Roster.roster(self,body)
		"actor_detail": Roster.detail(self,body)
		"report_detail": Archive.detail(self,body)
		"help": SystemViews.help(self,body)
		"party": _party()
		"prepare": _prepare()
		"battle": _battle()
		"result": _result()
		"records": _records()
		"settings": _settings()
	if not message.is_empty(): body.add_child(_label(message,16,Color("dac48e")))
	if not save_error.is_empty(): body.add_child(_label(save_error,16,Color("efa7a3")))
	confirmation = ConfirmationDialog.new(); confirmation.title = "开始新的行动"; confirmation.dialog_text = "当前仍有未结束行动。新行动将替换本机恢复点，是否继续？"; confirmation.ok_button_text = "开始新行动"; confirmation.cancel_button_text = "保留当前行动"; confirmation.confirmed.connect(func(): flow.close_modal(); _begin()); confirmation.canceled.connect(_close_modal); add_child(confirmation)

func _label(text_value: String, font_size: int = 18, color: Color = Color("e9e7de")) -> Label:
	var item := Label.new(); item.text = text_value; item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_theme_font_size_override("font_size",font_size + (2 if settings.large_text else 0)); item.add_theme_color_override("font_color",UiTheme.legacy(color))
	return item

func _button(text_value: String, callback: Callable, disabled: bool = false) -> Button:
	var item := Button.new(); item.text = text_value; item.custom_minimum_size = Vector2(92,48); item.disabled = disabled; item.pressed.connect(func(): _click_sound(); callback.call())
	return item

func _panel(parent: Node, heading: String, detail: String = "") -> VBoxContainer:
	var panel := PanelContainer.new(); panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; panel.add_theme_stylebox_override("panel",_box()); parent.add_child(panel)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation",10); panel.add_child(col)
	col.add_child(_label(heading,22,Color("e4d3a5")))
	if not detail.is_empty(): col.add_child(_label(detail,17,Color("afbfcc")))
	return col

func _toggle_appearance() -> void:
	UiTheme.mode = "night" if UiTheme.mode == "day" else "day"
	var appearance := ConfigFile.new(); appearance.set_value("ui","mode",UiTheme.mode)
	if appearance.save("user://ui_appearance.cfg") != OK: message = "配色已切换，但未能保存此偏好。"
	_render()

func _navigate(target_page: String) -> void:
	if not flow.open(target_page): return
	message = ""; _render()

func _home() -> void:
	Lobby.build(self,body)

func _missions() -> void:
	Operations.listing(self,body)

func _party() -> void:
	Roster.squad(self,body)

func _toggle_member(id: String) -> void:
	if read_only: return
	if id in party:
		if party.size() == 1: message = "至少保留一名出战角色。"; _render(); return
		party.erase(id)
	else: party.append(id)
	_save(); _render()

func _prepare() -> void:
	Operations.prepare(self,body)

func _request_begin() -> void:
	if read_only: return
	if not saved_battle.is_empty():
		if flow.show_modal("replace"): _shade_modal(); confirmation.popup_centered(Vector2i(440,200))
	else: _begin()

func _begin() -> void:
	if read_only: return
	var response: Dictionary = rules.start(mission,party,"local-%d-%d" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()])
	if not response.ok: message = response.error; _render(); return
	selected_actor = party[0]; selected_action = ""; selected_target = ""; paused = false; page = "battle"; message = ""; saved_battle = rules.checkpoint(); _save(); _render()

func _continue() -> void:
	var response: Dictionary = rules.restore(saved_battle)
	if not response.ok: save_error = "恢复失败："+response.error+"。原恢复点保留，可在设置中清除后重新开始。"; _render(); return
	page = "battle"
	if rules.state.status != "active": _finish(rules.state.status); return
	selected_actor = rules.state.allies[0].id
	for member in rules.state.allies:
		if member.hp > 0 and member.id not in rules.state.acted: selected_actor = member.id; break
	selected_action = ""; selected_target = ""; paused = true; page = "battle"; _render()

func _battle() -> void:
	Battle.build(self,body)

func _select_action(id: String) -> void:
	selected_action = id; selected_target = ""
	var mode: String = rules.action(selected_actor,id).target
	if mode == "self": selected_target = selected_actor
	elif mode == "all_allies": selected_target = "all_allies"
	_render()

func _commit() -> void:
	if paused or busy or read_only: return
	var response: Dictionary = rules.act(selected_actor,selected_action,selected_target,rules.state.revision)
	if not response.ok: message = response.error; _render(); return
	selected_action = ""; selected_target = ""; saved_battle = rules.checkpoint(); _save()
	presentation.begin(response,not settings.motion)
	busy = true
	_render()
	if is_instance_valid(battlefield): battlefield.attach_clip(response.actor,rules.unit(response.actor).form,response.action)
	return

func _retreat() -> void:
	if read_only or busy: return
	_confirm("retreat","撤退后结束本次行动，是否继续？",func(): _finish("retreat"))

func _finish(outcome: String) -> void:
	var record := {"request_id":rules.state.request_id,"mission":rules.state.mission,"outcome":outcome,"rounds":rules.state.round,"actions":rules.history.size(),"party":rules.setup.party.duplicate(),"log":rules.state.log.duplicate(),"version":Rules.VERSION}
	if not records.any(func(item): return item.request_id == record.request_id): records.push_front(record)
	if records.size() > 20: records.resize(20)
	saved_battle = {}; page = "result"; message = ""; _save(); _render()

func _result() -> void:
	Archive.result(self,body)

func _records() -> void:
	Archive.listing(self,body)

func _settings() -> void:
	SystemViews.settings(self,body)

func _save() -> void:
	if read_only: save_error = "只读窗口无法保存"; return
	var payload := {"schema":1,"party":party,"settings":settings,"battle":saved_battle,"records":records}
	if not store.write(payload): save_error = store.last_error
	else: save_error = ""

func _load_save() -> void:
	var response: Dictionary = store.read()
	if not response.ok: save_error = response.error+"；原文件已保留，可导出诊断或恢复上一好档。"; return
	if not response.data.is_empty(): _apply_payload(response.data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and page == "battle" and is_instance_valid(body):
		paused = true
		if flow.modal.is_empty(): call_deferred("_render")

func outcome_label(outcome: String) -> String:
	return {"victory":"胜利","defeat":"失败","retreat":"撤退","draw":"平局"}.get(outcome,"结束")

func _process(delta: float) -> void:
	if presentation.tick(delta,paused): _end_presentation()
	platform_poll -= delta
	if platform == null or platform_poll > 0: return
	platform_poll = 0.1
	var items: Variant = JSON.parse_string(str(platform.drain()))
	if not items is Array: return
	for item in items:
		if not item is Dictionary: continue
		match item.get("type",""):
			"writer_state":
				read_only = item.get("state") != "writable"
				if read_only: paused = true
				flow.close_modal()
				_render()
			"import_save":
				if not read_only: _offer_import(str(item.get("raw","")))
			"import_error": message = str(item.get("message","导入失败")); _render()

func _end_presentation() -> void:
	busy = false
	if rules.state.get("status") != "active": _finish(rules.state.status); return
	for member in rules.state.allies:
		if member.hp > 0 and member.id not in rules.state.acted: selected_actor = member.id; break
	message = ""; _render()

func _skip_presentation() -> void:
	if presentation.skip(): _end_presentation()

func _apply_payload(payload: Dictionary) -> void:
	party = payload.party.duplicate(); saved_battle = payload.battle.duplicate(true); records = payload.records.duplicate(true)
	for key in ["large_text","motion","sfx_volume"]:
		if payload.settings.has(key): settings[key] = payload.settings[key]
	if is_instance_valid(sound): _apply_volume()

func _go_back() -> void:
	if page == "battle": _pause_menu(); return
	if flow.back(): message = ""; _render()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE: return
	if not flow.modal.is_empty(): return
	get_viewport().set_input_as_handled()
	if not selected_action.is_empty() and page == "battle": selected_action = ""; selected_target = ""; _render()
	else: _go_back()

func _confirm(kind: String, text: String, callback: Callable) -> void:
	if not flow.show_modal(kind): return
	_shade_modal()
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null: focus_before_modal = weakref(owner)
	var dialog := ConfirmationDialog.new(); dialog.title = "请确认"; dialog.dialog_text = text; dialog.ok_button_text = "确认"; dialog.cancel_button_text = "取消"
	add_child(dialog)
	dialog.confirmed.connect(func(): flow.close_modal(); dialog.queue_free(); callback.call())
	dialog.canceled.connect(func(): _close_modal(); dialog.queue_free())
	dialog.popup_centered(Vector2i(440,200))

func _close_modal() -> void:
	flow.close_modal()
	if is_instance_valid(modal_shade): modal_shade.queue_free()
	if focus_before_modal != null and is_instance_valid(focus_before_modal.get_ref()): focus_before_modal.get_ref().grab_focus()
	call_deferred("_resize")

func _shade_modal() -> void:
	if is_instance_valid(modal_shade): modal_shade.queue_free()
	modal_shade = ColorRect.new(); modal_shade.color = Color(0.08,0.11,0.1,0.48)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal_shade)

func _pause_menu() -> void:
	if paused: paused = false; _render(); return
	if not flow.show_modal("pause"): return
	_shade_modal()
	paused = true
	var dialog := ConfirmationDialog.new(); dialog.title = "行动暂停"; dialog.dialog_text = "当前行动已经保存。继续后可恢复操作。"; dialog.ok_button_text = "继续行动"; dialog.cancel_button_text = "返回"
	add_child(dialog); dialog.add_button("保存并返回行动室",true,"leave")
	var resume: Callable = func(): flow.close_modal(); paused = false; dialog.queue_free(); _render()
	dialog.confirmed.connect(resume); dialog.canceled.connect(resume)
	dialog.custom_action.connect(func(id):
		if id == "leave": flow.close_modal(); dialog.queue_free(); _save_and_leave())
	dialog.popup_centered(Vector2i(460,200))

func _save_and_leave() -> void:
	if busy or read_only: return
	saved_battle = rules.checkpoint(); _save()
	if not save_error.is_empty(): _render(); return
	paused = false; _navigate("home")

func _request_clear() -> void:
	_confirm("clear","清除当前恢复点，保留已读取的战报。异常原文件会被替换，请先导出需要的备份。",func():
		saved_battle = {}
		if store.write({"schema":1,"party":party,"settings":settings,"battle":{},"records":records},true): save_error = ""; message = "恢复点已清除。"
		else: save_error = store.last_error
		_render())

func _export_save() -> void:
	if platform == null: message = "请在网页版本使用备份下载。"; _render(); return
	var raw: String = store.export_raw() if store.blocked else JSON.stringify({"schema":1,"party":party,"settings":settings,"battle":saved_battle,"records":records})
	platform.export_save(raw)

func _pick_import() -> void:
	if read_only: return
	if platform != null: platform.import_save()
	else: message = "请在网页版本选择本地备份文件。"; _render()

func _offer_import(raw: String) -> void:
	var response: Dictionary = store.decode(raw)
	if not response.ok: message = "备份未导入："+response.error; _render(); return
	pending_import = response.data
	_confirm("import","导入将替换本机编队、恢复点与战报（%d条）。确认导入？" % pending_import.records.size(),func():
		if store.write(pending_import,true): _apply_payload(pending_import); save_error = ""; flow.open("home"); message = "备份已导入。"
		else: save_error = store.last_error
		pending_import = {}; _render())

func _restore_backup() -> void:
	var response: Dictionary = store.backup_data()
	if not response.ok: message = response.error; _render(); return
	_offer_import(JSON.stringify(response.data))

func _apply_volume() -> void:
	sound.volume_db = linear_to_db(maxf(0.001,float(settings.sfx_volume)))
	sound.stream_paused = settings.sfx_volume == 0

func _set_volume(value: float) -> void:
	settings.sfx_volume = value; _apply_volume(); _save()

func _click_sound() -> void:
	if is_instance_valid(sound) and settings.sfx_volume > 0: sound.play()

func _fullscreen() -> void:
	if platform != null: platform.fullscreen()
