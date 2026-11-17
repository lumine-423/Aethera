extends "res://scripts/ui/ui_screen.gd"
## 剧情（Galgame）. Driven by Game.messages (real chat floors, C5 §5–6). Each AI reply is parsed by
## reply_parser.gd (前端设计/03_AI回复格式约定.md) into beats: background, cast on stage, name plate,
## typewriter text, options. Expression changes switch the whole image directly (no fade, user rule).
## The newest AI reply plays; older floors live in the 回看 drawer with every message operation.

const Parser = preload("res://scripts/game/reply_parser.gd")
const ActionPanel = preload("res://scripts/ui/ui_action_panel.gd")

var lines: Array = []
var index := 0
var reply_start := 0
var last_sig := ""
var shown_chars := 0.0
var typing := false
var auto_mode := false
var skip_mode := false
var ui_hidden := false
var backlog_open := false
var choices_visible := false
var hold := 0.0
var cast: Dictionary = {}       # id -> Portrait node
var cast_expr: Dictionary = {}  # id -> last expression
var name_plate: Control
var name_home := Vector2.ZERO
var name_label: Label
var body: Label
var avatar: Control
var next_mark: Control
var chrome_nodes: Array = []
var choice_box: Control
var input: TextEdit
var panel: Control
var act_chip: Button
var retry_custom_btn: Button
var auto_btn: Button
var skip_btn: Button
var backlog: Control
var recap_open := false
var recap_modal: Control
var recap_status_lbl: Label
var recap_edit: TextEdit
var recap_gen_btn: Button
var recap_save_btn: Button
var recap_dirty := false
var _last_recap_snapshot_text := ""
var scene_slot: Control
var stage_layer: Control
var status_label: Label
var busy_box: Control
var busy_label: Label
var bg_path := ""
var cg_layer: Control
var cg_card: Control
var cg_art: Control
var cg_caption_lbl: Label
var cg_reopen_btn: Button
var cg_zoom: Control
var cg_id := ""
var cg_dismissed := false
var oracle_btn: Button
var _box_y := 725.0
var draft_action_text := ""
var _saved_choices_list: Array = []
var _saved_choices_free := true

func _layout_metrics() -> Dictionary:
	var sp := UiHub.spacing
	var bottom_pad := roundf(lerpf(14.0, 44.0, sp))
	var box_h := roundf(lerpf(282.0, 344.0, sp))
	var box_x := roundf(lerpf(18.0, 46.0, sp))
	var box_w := 1820.0 - box_x * 2.0
	var box_y := 1080.0 - bottom_pad - box_h
	return {
		"top_y": roundf(lerpf(18.0, 42.0, sp)),
		"top_h": roundf(lerpf(54.0, 64.0, sp)),
		"box_x": box_x,
		"box_y": box_y,
		"box_w": box_w,
		"box_h": box_h,
	}

func build() -> void:
	var resume_done := _has_built and not typing
	uses_backdrop = true
	backdrop_style = "plain"   # story page stays exactly as before (no blurred room)
	chrome_nodes.clear(); cast.clear()
	# Always clear cached scene_slot / CG IDs on rebuild so background & art reload cleanly.
	bg_path = ""; cg_id = ""
	scene_slot = W.Portrait.new(); scene_slot.kind = "scene"; scene_slot.frame = false
	put(scene_slot, Rect2(Vector2.ZERO, size), "lt")
	stage_layer = Control.new(); stage_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	put(stage_layer, Rect2(Vector2.ZERO, size), "lt")
	_build_cg_layer()
	_build_box()
	_build_top()
	_build_input()
	_build_busy()
	choice_box = Control.new(); choice_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choice_box.set_meta("layer", true)
	put(choice_box, Rect2(Vector2.ZERO, size), "lt")
	if not Game.changed.is_connected(_on_game): Game.changed.connect(_on_game)
	if not Game.action_rejected.is_connected(_restore_rejected_action): Game.action_rejected.connect(_restore_rejected_action)
	_rebuild_lines()
	if lines.is_empty():
		_empty()
		_update_status()
		_update_busy()
		return
	index = clampi(index if last_sig != "" else reply_start, 0, lines.size() - 1)
	last_sig = _signature()
	_show_line(index, false)
	if resume_done and not lines.is_empty():
		_finish_typing()
	_update_status(); _update_busy()
	if choices_visible:
		show_choices(_saved_choices_list, _saved_choices_free)

func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game): Game.changed.disconnect(_on_game)
	if Game.action_rejected.is_connected(_restore_rejected_action): Game.action_rejected.disconnect(_restore_rejected_action)
	if is_instance_valid(UiHub):
		var oh := UiHub.story_oracle()
		if oh.changed.is_connected(_sync_oracle_badge): oh.changed.disconnect(_sync_oracle_badge)
		if oh.update_status_changed.is_connected(_sync_oracle_badge): oh.update_status_changed.disconnect(_sync_oracle_badge)
	if UiHub.mobile_portrait_input and not is_instance_valid(root):
		UiHub.set_mobile_portrait(false)

func _empty() -> void:
	var is_custom := String(Game.persona.get("origin", "")) == "custom"
	var busy_now := bool(Game.generation.get("busy", false))
	if is_custom:
		if busy_now:
			body.text = "正在向模型发送你的档案，为「1015年·2月1日」随机生成专属开局地点与首幕剧情…"
		else:
			body.text = "「自定义」随机开局尚未生成正文（开局时间：1015年·2月1日，地点不预设）。可点击右下角“重试自定义开局”。"
	else:
		body.text = "还没有开始故事。回到标题选择“新的开始”。"
	body.visible_characters = -1; name_plate.visible = false; avatar.get_parent().visible = false
	if is_instance_valid(next_mark): next_mark.visible = false

# ---------- chrome ----------
func _build_top() -> void:
	var m := _layout_metrics()
	var ty := float(m.top_y)
	var th := float(m.top_h)
	var back := btn("", "back", "icon", Rect2(24, ty - 4.0, 92, th + 8.0), func(): _leave(), "lt")
	back.name = "Back"; back.tooltip_text = "返回主页"
	chrome_nodes.append(back)
	var st := plate(Rect2(126, ty - 2.0, 332, th + 4.0), {"slant": 20, "stripe": "left", "fill_alpha": 0.88}, "lt")
	status_label = text("", Rect2(20, 4, 300, th - 4.0), 15, "ink", 700, "c", st)
	status_label.autowrap_mode = TextServer.AUTOWRAP_OFF; status_label.clip_text = true
	st.name = "StatusChip"; chrome_nodes.append(st)
	var hide_b := btn("", "eye_off", "icon", Rect2(468, ty, 58, th), func(): set_hidden(true), "rt")
	hide_b.tooltip_text = "隐藏界面（右键 / H）"; chrome_nodes.append(hide_b)
	var db_b := btn("手札", "docs", "chip", Rect2(532, ty, 134, th), func(): root.go("database", {"tab": "characters"}, "slide"), "rt", -1.0, null, 19)
	db_b.name = "TopDatabase"; db_b.tooltip_text = "打开旅途手札（同伴好感/色情值、剧情大事记与隐私保密）"
	var recap_b := btn("大总结", "docs", "chip", Rect2(672, ty, 156, th), func(): open_recap(), "rt", -1.0, null, 19)
	recap_b.name = "MacroSummary"; recap_b.tooltip_text = "查看或手动生成阶段大总结（汇总全部小总结）"
	var mb := music_btn(Rect2(834, ty, 144, th), "rt", null, 19)
	var bag := btn("物品", "item_cube", "chip", Rect2(984, ty, 132, th), func(): root.go("inventory", {}, "slide"), "rt", -1.0, null, 19)
	var log_b := btn("回看", "log", "chip", Rect2(1122, ty, 132, th), func(): open_backlog(), "rt", -1.0, null, 19)
	auto_btn = btn("自动", "play", "chip", Rect2(1260, ty, 132, th), func(): set_auto(not auto_mode), "rt", -1.0, null, 19)
	skip_btn = btn("跳过", "skip", "chip", Rect2(1398, ty, 132, th), func(): set_skip(not skip_mode), "rt", -1.0, null, 19)
	auto_btn.press_sfx = "none"; skip_btn.press_sfx = "none"; log_b.press_sfx = "none"; hide_b.press_sfx = "none"; recap_b.press_sfx = "none"; db_b.press_sfx = "none"
	var set_b := btn("设置", "gear", "chip", Rect2(1536, ty, 142, th), func(): root.go("settings", {"tab": "display"}, "slide"), "rt", -1.0, null, 19)
	log_b.name = "Backlog"; bag.name = "Bag"
	var sw := W.ThemeSwitch.new(); put(sw, Rect2(1690, ty, 186, th), "rt")
	chrome_nodes.append_array([db_b, recap_b, mb, bag, log_b, auto_btn, skip_btn, set_b, sw])
	auto_btn.selected = auto_mode; skip_btn.selected = skip_mode
	oracle_btn = btn("故事神谕", "compass", "chip", Rect2(18, 444, 168, 62), func():
		if root != null and root.has_method("open_story_oracle"):
			root.open_story_oracle()
	, "l", -1.0, null, 20)
	oracle_btn.name = "StoryOracleBtn"
	oracle_btn.tooltip_text = "打开故事神谕悬浮窗（剧情参谋 / 诊断 / 世界书 / 正文校正 / 角色工坊）"
	_sync_oracle_badge()
	var oh := UiHub.story_oracle()
	if not oh.changed.is_connected(_sync_oracle_badge): oh.changed.connect(_sync_oracle_badge)
	if not oh.update_status_changed.is_connected(_sync_oracle_badge): oh.update_status_changed.connect(_sync_oracle_badge)
	chrome_nodes.append(oracle_btn)

func _sync_oracle_badge() -> void:
	if not is_instance_valid(oracle_btn): return
	var oh := UiHub.story_oracle()
	var b := ""
	if bool(oh.guidance_seq.get("beat_ready", false)): b = "●"
	elif oh.has_active_guidance(): b = "引导中"
	elif oh.update_available: b = "新"
	oracle_btn.badge = b
	oracle_btn.queue_redraw()

func _build_box() -> void:
	var m := _layout_metrics()
	var bx := float(m.box_x)
	var by := float(m.box_y)
	var bw := float(m.box_w)
	var bh := float(m.box_h)
	_box_y = by
	var box := plate(Rect2(bx, by, bw, bh), {"slant": 60, "fill_alpha": 0.9, "hatch": true, "corner": "br", "layer_offset": Vector2(-14, 14)}, "lb")
	box.name = "DialogBox"; chrome_nodes.append(box)
	var av_top := by + 30.0
	var frame := plate(Rect2(maxf(8.0, bx - 20.0), av_top, 210, minf(200.0, bh - 56.0)), {"shape": "rect", "fill": "surface2", "border": "line", "layered": false}, "lb")
	chrome_nodes.append(frame)
	avatar = W.Portrait.new(); avatar.kind = "avatar"
	put(avatar, Rect2(10, 10, 190, minf(180.0, frame.size.y - 20.0)), "c", -1.0, frame)
	name_plate = plate(Rect2(bx + 210.0, by - 15.0, 400, 66), {"slant": 30, "fill": "accent", "fill_alpha": 1.0, "border": "", "glass": false, "layer_offset": Vector2(-30, 0)}, "lb")
	chrome_nodes.append(name_plate); name_home = name_plate.position
	name_label = text("", Rect2(60, 0, 320, 66), 32, "on_accent", 800, "c", name_plate)
	var pad_top := lerpf(56.0, 82.0, UiHub.spacing)
	body = text("", Rect2(bx + 240.0, by + pad_top, bw - 380.0, bh - pad_top - lerpf(28.0, 44.0, UiHub.spacing)), 34, "ink", 600, "lb")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	body.name = "Body"; chrome_nodes.append(body)
	next_mark = icon("tri_right", Rect2(bx + bw - 130.0, by + bh - 62.0, 30, 30), "accent", "lb")
	chrome_nodes.append(next_mark)
	if not UiHub.reduced_motion:
		var t := next_mark.create_tween().set_loops()
		t.tween_property(next_mark, "position:x", next_mark.position.x + 8, 0.45).set_trans(Tween.TRANS_SINE)
		t.tween_property(next_mark, "position:x", next_mark.position.x, 0.45).set_trans(Tween.TRANS_SINE)

func _build_cg_layer() -> void:
	cg_layer = Control.new(); cg_layer.name = "CgLayer"
	cg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	put(cg_layer, Rect2(Vector2.ZERO, size), "c")
	var shade := ColorRect.new(); shade.color = Color(0.05, 0.04, 0.06, 0.36)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; shade.size = size
	cg_layer.add_child(shade)
	cg_card = plate(Rect2(410, 110, 1100, 572), {"shape": "cut", "slant": 28, "corner": "tr", "fill": "background", "fill_alpha": 1.0, "glass": false}, "c", -1.0, cg_layer)
	cg_card.name = "CgCard"; cg_card.mouse_filter = Control.MOUSE_FILTER_STOP
	cg_art = W.Portrait.new(); cg_art.kind = "cg"; cg_art.frame = false; cg_art.name = "CgArt"
	put(cg_art, Rect2(26, 18, 1048, 488), "c", -1.0, cg_card)
	cg_art.mouse_filter = Control.MOUSE_FILTER_STOP
	cg_art.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open_cg_zoom()
			cg_art.accept_event()
	)
	cg_caption_lbl = text("", Rect2(34, 514, 760, 44), 22, "ink", 800, "c", cg_card)
	cg_caption_lbl.name = "CgCaption"
	var zoom_b := btn("放大", "search", "chip", Rect2(812, 512, 120, 46), func(): _open_cg_zoom(), "c", -1.0, cg_card, 18)
	zoom_b.name = "ZoomCg"
	var close_b := btn("收起", "close", "chip", Rect2(944, 512, 128, 46), func(): _set_cg_dismissed(true), "c", -1.0, cg_card, 18)
	close_b.name = "CloseCg"
	cg_layer.visible = false

func _build_input() -> void:
	var chip_y := _box_y - 25.0
	cg_reopen_btn = btn("查看插画", "image", "chip", Rect2(1170, chip_y, 240, 62), func(): _set_cg_dismissed(false), "lb", -1.0, null, 22)
	cg_reopen_btn.name = "ShowCg"; cg_reopen_btn.tooltip_text = "重新展开本回合的插画"
	cg_reopen_btn.visible = false
	chrome_nodes.append(cg_reopen_btn)
	act_chip = btn("自由行动", "chat", "chip", Rect2(1430, chip_y, 240, 62), func(): show_choices([]), "lb", -1.0, null, 22)
	act_chip.name = "FreeAction"; act_chip.tooltip_text = "不等选项，直接写下想说或想做的事"
	chrome_nodes.append(act_chip)
	retry_custom_btn = btn("重试自定义开局", "refresh", "primary", Rect2(1370, chip_y, 300, 62), func(): Game.retry_custom_opening(), "lb", -1.0, null, 20)
	retry_custom_btn.name = "RetryCustomBtn"; retry_custom_btn.tooltip_text = "重新发送自定义随机开局前置语"
	retry_custom_btn.visible = false
	chrome_nodes.append(retry_custom_btn)

func _sync_cg_visibility() -> void:
	var has_cg := cg_id != ""
	var busy_now := bool(Game.generation.get("busy", false))
	if is_instance_valid(cg_layer):
		cg_layer.visible = has_cg and not cg_dismissed and not ui_hidden and not choices_visible
	if is_instance_valid(cg_reopen_btn):
		cg_reopen_btn.visible = has_cg and cg_dismissed and not ui_hidden and not choices_visible and not busy_now

func _set_cg_dismissed(on: bool) -> void:
	cg_dismissed = on
	_sync_cg_visibility()
	UiHub.sfx("collapse" if on else "expand")

func _update_cg(raw_cg: String, animate := true) -> void:
	var clean := raw_cg.strip_edges()
	var spec := Data.illustration_spec(clean, W.Portrait.registry.get("cg", {})) if clean != "" else {}
	var next_id := String(spec.get("id", ""))
	if next_id == "" or String(spec.get("res", "")) == "":
		cg_id = ""; cg_dismissed = false
		_close_cg_zoom(true)
		if is_instance_valid(cg_art): cg_art.set_texture(null, false)
		_sync_cg_visibility()
		return
	var changed_cg := next_id != cg_id
	if changed_cg:
		cg_id = next_id; cg_dismissed = false
		_close_cg_zoom(true)
		var tex: Texture2D = load(String(spec.res))
		if is_instance_valid(cg_art):
			cg_art.set_texture(tex, animate)
		if is_instance_valid(cg_caption_lbl):
			cg_caption_lbl.text = String(spec.get("title", cg_id))
		Game.unlock_cg(cg_id)
	_sync_cg_visibility()

func _open_cg_zoom() -> void:
	if cg_id == "" or not is_instance_valid(cg_art) or cg_art.texture == null: return
	_close_cg_zoom(true)
	UiHub.sfx("open_book")
	cg_zoom = Control.new(); cg_zoom.name = "CgZoom"; cg_zoom.mouse_filter = Control.MOUSE_FILTER_STOP
	cg_zoom.set_meta("layer", true)
	put(cg_zoom, Rect2(Vector2.ZERO, size), "c")
	var bg := ColorRect.new(); bg.color = Color(0.03, 0.03, 0.04, 0.92); bg.size = size; cg_zoom.add_child(bg)
	var big := W.Portrait.new(); big.kind = "cg"; big.frame = false; big.size = size
	cg_zoom.add_child(big); big.set_texture(cg_art.texture, false)
	var close := btn("", "close", "icon", Rect2(size.x - 130, 30, 96, 70), func(): _close_cg_zoom(), "c", -1.0, cg_zoom)
	close.name = "CloseCgZoom"
	cg_zoom.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_cg_zoom(); cg_zoom.accept_event()
	)
	Kit.pop(cg_zoom)

func _close_cg_zoom(silent := false) -> void:
	if is_instance_valid(cg_zoom):
		if not silent: UiHub.sfx("close_book")
		if cg_zoom.get_parent() != null: cg_zoom.get_parent().remove_child(cg_zoom)
		cg_zoom.queue_free()
	cg_zoom = null

## Generation state: the dialog box shows that the AI is writing, with a stop key (C5 §10).
func _build_busy() -> void:
	busy_box = plate(Rect2(1200, 620, 590, 72), {"slant": 24, "stripe": "left", "fill_alpha": 0.95}, "lb")
	busy_box.name = "Busy"
	busy_label = text("AI 正在书写…", Rect2(40, 0, 330, 72), 24, "ink", 750, "c", busy_box)
	var stop := btn("停止", "pause", "chip", Rect2(390, 6, 180, 60), func(): Game.stop_generation(), "c", -1.0, busy_box, 22)
	stop.name = "Stop"
	busy_box.visible = false

# ---------- floors -> beats ----------
func _signature() -> String:
	var id := Game.last_assistant_id()
	var m: Dictionary = Game.message(id)
	return "%d:%d:%d:%d" % [Game.messages.size(), id, int(m.get("swipe", 0)), Game.text_of(m).hash() if not m.is_empty() else 0]

func _rebuild_lines() -> void:
	lines.clear(); reply_start = 0
	var hero: Dictionary = Game.hero()
	var place: String = hero.get("当前地点", "")
	var time_text: String = hero.get("时间", "")
	var you: String = Game.persona.get("name", "你")
	var stage: Array = []
	var bg: String = String(Data.scene_for("", place, time_text).get("res", ""))
	var last_id := Game.last_assistant_id()
	for m in Game.messages:
		if m.role == "user":
			lines.append({"kind": "player", "speaker": "", "name": you, "expr": "", "text": Game.text_of(m), "msg": int(m.id), "show": stage.duplicate(true), "bg": bg, "cg": ""})
			continue
		var r: Dictionary = Parser.parse(Game.text_of(m), you)
		var msg_cg := String(r.get("cg", "")).strip_edges()
		if r.scene != "":
			var s: Dictionary = Data.scene_for(r.scene, place, time_text)
			if not s.is_empty(): bg = s.res
		if r.cast_present:
			stage = []
			for c in r.cast:
				var cid: String = Data.id_of(c.name)
				var sil_id := String(c.get("sil", ""))
				var art_id := cid if cid != "" else sil_id
				if art_id != "":
					var skey := cid if cid != "" else ("%s:%s" % [sil_id, String(c.name)])
					stage.append({"key": skey, "id": art_id, "name": String(c.name), "outfit": String(c.get("outfit", "daily"))})
		if int(m.id) == last_id: reply_start = lines.size()
		var first := lines.size()
		for b in r.beats:
			var line := {"kind": b.kind, "speaker": "", "art_id": "", "name": "", "expr": b.expr, "text": b.text, "msg": int(m.id), "bg": bg, "cg": msg_cg}
			if b.kind == "say":
				line.name = b.speaker
				var sid: String = Data.id_of(b.speaker)
				var b_sil := String(b.get("sil", ""))
				var art_id := sid if sid != "" else b_sil
				var stage_key := sid if sid != "" else (("%s:%s" % [b_sil, b.speaker]) if b_sil != "" else "")
				line.speaker = stage_key
				line.art_id = art_id
				if art_id != "" and not stage.any(func(e): return String(e.get("key", e.id)) == stage_key):
					if stage.size() >= 3: stage.pop_front()
					stage.append({"key": stage_key, "id": art_id, "name": b.speaker, "outfit": "daily"})
				if b.speaker == you: line.kind = "player"
			elif b.kind == "magic":
				line.name = "激活魔法"
			line["show"] = stage.duplicate(true)
			lines.append(line)
		if lines.size() == first:
			lines.append({"kind": "narr", "speaker": "", "name": "", "expr": "", "text": "（这一条回复没有可显示的正文）", "msg": int(m.id), "show": stage.duplicate(true), "bg": bg, "cg": msg_cg})
		if int(m.id) == last_id:
			lines.back()["choices"] = r.options
	if not lines.is_empty() and Game.messages.back().role == "user":
		reply_start = lines.size() - 1

func _on_game(part: String) -> void:
	match part:
		"messages":
			var sig := _signature()
			_rebuild_lines()
			if lines.is_empty():
				_empty(); _update_busy()
				return
			if sig != last_sig:
				last_sig = sig
				_clear_choices(true)
				index = clampi(reply_start, 0, lines.size() - 1)
				if not backlog_open: _show_line(index)
			else:
				index = clampi(index, 0, lines.size() - 1)
			_update_busy()
			if backlog_open: _fill_backlog()
			if recap_open: _refresh_recap()
		"stat": _update_status()
		"generation": _update_busy(); _refresh_recap()
		"recap": _refresh_recap()

func _update_status() -> void:
	if not is_instance_valid(status_label): return
	var h: Dictionary = Game.hero()
	var mana = h.get("魔力", null)
	var mtop = h.get("魔力上限", "—")
	var mtop_s := str(int(mtop)) if typeof(mtop) in [TYPE_INT, TYPE_FLOAT] else str(mtop)
	var mp := ("魔力 %d/%s" % [int(mana), mtop_s]) if typeof(mana) in [TYPE_INT, TYPE_FLOAT] else ""
	var bgm := UiHub.music_title(String(h.get("当前BGM", "")))
	var place_txt := String(h.get("当前地点", "")).strip_edges()
	if place_txt == "":
		place_txt = "地点待生成" if String(Game.persona.get("origin", "")) == "custom" else "—"
	status_label.text = "%s · %s\n%s  ♪ %s" % [place_txt, h.get("时间", "—"), mp, bgm]
	status_label.tooltip_text = status_label.text
	if status_label.has_method("refresh"): status_label.refresh()

func _update_busy() -> void:
	if not is_instance_valid(busy_box): return
	var gen: Dictionary = Game.generation
	var on: bool = gen.get("busy", false)
	busy_box.visible = on and not ui_hidden
	if on:
		var n: int = String(gen.get("stream", "")).length()
		busy_label.text = {"regenerate": "AI 正在重写…", "continue": "AI 正在续写…", "macro_summary": "AI 正在整理大总结…", "custom_open": "AI 正在按设定生成随机开局…"}.get(gen.get("kind", ""), "AI 正在书写…") + ("  %d 字" % n if n > 0 else "")
		_clear_choices(true)
	if is_instance_valid(act_chip): act_chip.visible = not on and not ui_hidden and not choices_visible and not lines.is_empty()
	if is_instance_valid(retry_custom_btn):
		retry_custom_btn.visible = lines.is_empty() and String(Game.persona.get("origin", "")) == "custom" and not on and not ui_hidden
	if lines.is_empty() and is_instance_valid(body): _empty()
	_sync_cg_visibility()

# ---------- line flow ----------
func _show_line(i: int, animate := true) -> void:
	if lines.is_empty(): return
	var line: Dictionary = lines[i]
	var sp: String = line.speaker
	var av_id: String = String(line.get("art_id", sp))
	var has_name: bool = line.name != ""
	name_plate.visible = has_name and not ui_hidden
	name_label.text = line.name
	avatar.show_character(av_id, "avatar", false)
	avatar.get_parent().visible = av_id != "" and not ui_hidden
	body.text = ("「%s」" % line.text) if line.kind == "player" else line.text
	body.visible_characters = 0; shown_chars = 0.0; typing = true
	next_mark.visible = false
	if line.bg != bg_path:
		bg_path = line.bg
		scene_slot.set_texture(load(bg_path) if bg_path != "" and ResourceLoader.exists(bg_path) else null, animate)
	for prev_k in cast_expr.keys():
		if prev_k != sp and sp != "" and String(cast_expr[prev_k]) == "speaking":
			cast_expr[prev_k] = "neutral"
	if sp != "" and line.expr != "": cast_expr[sp] = line.expr
	_update_cast(line.show, sp, animate)
	_update_cg(String(line.get("cg", "")), animate)
	_clear_choices(true)
	if animate and not UiHub.reduced_motion and is_instance_valid(name_plate) and name_plate.visible:
		name_plate.position = name_home; Kit.rise(name_plate, 0.0, 30.0, 0.32)
	request("story.line_shown", {"index": i, "message": line.msg})

## E4 §14: one stands centered, two or three make room; whoever is not speaking dims.
func _update_cast(entries: Array, speaker: String, animate: bool) -> void:
	var slots := {1: [960.0], 2: [580.0, 1300.0], 3: [360.0, 960.0, 1560.0]}
	var keys: Array = []
	for e in entries: keys.append(String(e.get("key", e.id)))
	for k_old in cast.keys():
		if not k_old in keys:
			var gone: Control = cast[k_old]; cast.erase(k_old)
			if animate and not UiHub.reduced_motion:
				var t := gone.create_tween(); t.tween_property(gone, "modulate:a", 0.0, 0.25); t.tween_callback(gone.queue_free)
			else: gone.queue_free()
	if keys.is_empty(): return
	var layout: Array = slots.get(clampi(keys.size(), 1, 3), slots[1])
	for k in range(entries.size()):
		var e: Dictionary = entries[k]
		var skey: String = String(e.get("key", e.id))
		var art_id: String = String(e.id)
		var center: float = layout[mini(k, layout.size() - 1)] + origin.x
		var target := Vector2(center - 600.0, 0.0)
		var p: Control
		if cast.has(skey):
			p = cast[skey]
			if p.position != target:
				if animate and not UiHub.reduced_motion: p.create_tween().tween_property(p, "position", target, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
				else: p.position = target
		else:
			p = W.Portrait.new(); p.kind = "full"; p.framing = "story"; p.show_emotion_deco = false
			stage_layer.add_child(p); p.position = target; p.size = Vector2(1200, size.y)
			p.name = "Cast_" + skey.replace(":", "_")
			cast[skey] = p
			if animate: Kit.rise(p, 0.0, 40.0, 0.45)
		p.size = Vector2(1200, size.y)
		p.show_emotion_deco = false
		p.show_art(art_id, e.get("outfit", "daily"), cast_expr.get(skey, "neutral"))
		var active := skey == speaker or speaker == ""
		p.dim = 0.0 if active else 0.45
		p.queue_redraw()

func _process(delta: float) -> void:
	if lines.is_empty() or backlog_open: return
	if typing:
		var cps := lerpf(18.0, 95.0, UiHub.dialog_speed) * (6.0 if skip_mode else 1.0)
		var before := int(shown_chars)
		shown_chars += cps * delta
		body.visible_characters = int(shown_chars)
		_type_blip(before, int(shown_chars))
		if shown_chars >= body.text.length() or UiHub.dialog_speed >= 0.99: _finish_typing()
	elif auto_mode or skip_mode:
		hold += delta
		var wait := 0.12 if skip_mode else lerpf(3.2, 0.8, UiHub.auto_speed) + body.text.length() * 0.02
		if hold >= wait and not choices_visible and index < lines.size() - 1: advance()

func _type_blip(a: int, b: int) -> void:
	if b <= a or skip_mode: return
	var t: String = body.text
	for i in range(a, mini(b, t.length())):
		if i % 2 != 0: continue
		var ch := t[i]
		if ch in " 　，。！？、…—「」『』“”,.!?~～·": continue
		var sp: String = lines[index].get("speaker", "")
		UiHub.sfx("type", 0.92 if sp == "" else 0.85 + float(abs(sp.hash()) % 40) / 100.0)
		return

func _finish_typing() -> void:
	typing = false; hold = 0.0
	body.visible_characters = -1
	var at_end := index >= lines.size() - 1
	if at_end and not Game.generation.get("busy", false) and not Game.messages.is_empty() and Game.messages.back().role == "assistant":
		if skip_mode: set_skip(false)
		var opts: Array = lines[index].get("choices", [])
		if not opts.is_empty(): show_choices(opts); return
	next_mark.visible = not ui_hidden and not at_end

func advance() -> void:
	if typing: _finish_typing(); return
	if choices_visible: return
	if index >= lines.size() - 1:
		if not Game.generation.get("busy", false): toast("写下你的行动，故事会继续", "chat")
		set_auto(false); set_skip(false)
		return
	UiHub.sfx("advance", 1.0, -4.0 if auto_mode or skip_mode else 0.0)
	index += 1
	_show_line(index)

## Test / skip helper: show the newest reply's last line at once.
func jump_to_end_for_test() -> void:
	if lines.is_empty(): return
	index = lines.size() - 1; _show_line(index, false); _finish_typing()

# ---------- choices / free input ----------
func show_choices(list: Array, free := true) -> void:
	if Game.generation.get("busy", false): return
	var prev_open := is_instance_valid(panel)
	_clear_choices(true)
	choices_visible = true
	_saved_choices_list = list.duplicate()
	_saved_choices_free = free
	panel = ActionPanel.new(); panel.options = list; panel.allow_free = free
	panel.initial_free_text = draft_action_text
	panel.before_confirm = Game.ensure_generation_ready
	panel.width = 1180.0; panel.bottom_y = _box_y - 35.0
	choice_box.add_child(panel)
	panel.position.x = size.x - 40.0 - panel.width
	input = panel.free_edit
	panel.draft_changed.connect(func(txt): draft_action_text = txt)
	panel.confirmed.connect(_on_confirm)
	if not prev_open: UiHub.sfx("popup", 0.9)
	_dim_stage(true)
	if is_instance_valid(act_chip): act_chip.visible = false
	_sync_cg_visibility()
	next_mark.visible = false

func _clear_choices(instant := false) -> void:
	if is_instance_valid(panel) and is_instance_valid(panel.free_edit):
		draft_action_text = panel.free_edit.text
	choices_visible = false
	input = null
	if is_instance_valid(panel):
		if instant: panel.queue_free()
		else: panel.leave()
	panel = null
	_dim_stage(false)
	if is_instance_valid(act_chip): act_chip.visible = not ui_hidden and not Game.generation.get("busy", false)
	_sync_cg_visibility()

func _dim_stage(on: bool) -> void:
	if not is_instance_valid(stage_layer): return
	var a := 0.55 if on else 1.0
	if UiHub.reduced_motion: stage_layer.modulate = Color(a, a, a, 1.0); return
	stage_layer.create_tween().tween_property(stage_layer, "modulate", Color(a, a, a, 1.0), 0.3)

func _on_confirm(kind: String, _i: int, value: String) -> void:
	choices_visible = false; input = null; panel = null
	draft_action_text = ""
	_dim_stage(false)
	Game.send_action(value, "free" if kind == "free" else "choice")

func _restore_rejected_action(value: String, _source: String) -> void:
	if not is_instance_valid(panel): show_choices([])
	if is_instance_valid(panel) and is_instance_valid(panel.free_edit):
		panel.free_edit.text = value
		panel.select(panel.rows.size() - 1)

func _send_free() -> void:
	if not is_instance_valid(panel) or not is_instance_valid(panel.free_edit): return
	if panel.free_edit.text.strip_edges() == "": return
	panel.select(panel.rows.size() - 1)
	panel._confirm()

# ---------- modes ----------
func set_auto(on: bool) -> void:
	if on != auto_mode: UiHub.sfx("toggle", 1.1 if on else 0.85)
	auto_mode = on; hold = 0.0
	if is_instance_valid(auto_btn): auto_btn.selected = on
	if on and skip_mode: set_skip(false)

func set_skip(on: bool) -> void:
	if on != skip_mode: UiHub.sfx("toggle", 1.2 if on else 0.8)
	skip_mode = on; hold = 0.0
	if is_instance_valid(skip_btn): skip_btn.selected = on
	if on and auto_mode: set_auto(false)

func set_hidden(on: bool) -> void:
	if on != ui_hidden: UiHub.sfx("collapse" if on else "expand")
	ui_hidden = on
	for n in chrome_nodes:
		if is_instance_valid(n):
			if UiHub.reduced_motion: n.visible = not on
			else:
				n.visible = true
				var t: Tween = n.create_tween(); t.tween_property(n, "modulate:a", 0.0 if on else 1.0, 0.22)
				if on: t.tween_callback(func(): n.visible = false)
	if is_instance_valid(choice_box): choice_box.visible = not on
	_update_busy()

# ---------- 回看 drawer with message operations (E2 / C5 §6) ----------
var log_list: VBoxContainer
var log_scroll: ScrollContainer

func open_backlog() -> void:
	if backlog_open: return
	UiHub.sfx("open_book")
	backlog_open = true
	backlog = Control.new(); backlog.mouse_filter = Control.MOUSE_FILTER_STOP; backlog.name = "BacklogDrawer"
	put(backlog, Rect2(Vector2.ZERO, size), "lt")
	var shade := ColorRect.new(); backlog.add_child(shade); shade.size = size; Kit.frost(shade)
	var p := plate(Rect2(140, 70, 1640, 950), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true}, "c", -1.0, backlog)
	header("回看", Rect2(50, 26, 160, 56), 34, "c", p)
	text("每一条都可以操作：翻看AI的其他版本、重写、续写、改原文、回到这里、另开分支、删除。", Rect2(220, 30, 1020, 50), 19, "muted", 600, "c", p)
	btn("阶段大总结", "docs", "chip", Rect2(1272, 24, 228, 58), func(): open_recap(), "c", -1.0, p, 21)
	btn("", "close", "icon", Rect2(1520, 22, 84, 64), func(): close_backlog(), "c", -1.0, p)
	log_scroll = ScrollContainer.new(); p.add_child(log_scroll); log_scroll.position = Vector2(50, 100); log_scroll.size = Vector2(1540, 820)
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_list = VBoxContainer.new(); log_list.add_theme_constant_override("separation", int(g(22))); log_scroll.add_child(log_list)
	log_list.custom_minimum_size.x = 1510
	_fill_backlog()
	Kit.pop(p)

func _fill_backlog() -> void:
	if not is_instance_valid(log_list): return
	for c in log_list.get_children(): c.queue_free()
	var you: String = Game.persona.get("name", "你")
	var last_ai := Game.last_assistant_id()
	var busy: bool = Game.generation.get("busy", false)
	for m in Game.messages:
		var id := int(m.id)
		var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 6); log_list.add_child(box)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 24); box.add_child(row)
		var who := Lbl.new(); who.setup(you if m.role == "user" else "剧情", 26, "accent" if m.role == "user" else "muted", 800)
		who.custom_minimum_size = Vector2(170, 0); row.add_child(who)
		var said := Lbl.new()
		said.setup(Game.text_of(m) if m.role == "user" else Parser.plain(Game.text_of(m), you), 24, "ink", 600)
		said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; said.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(said)
		var ops := HBoxContainer.new(); ops.add_theme_constant_override("separation", 10); box.add_child(ops)
		var pad := Control.new(); pad.custom_minimum_size = Vector2(170, 0); ops.add_child(pad)
		if m.role == "assistant":
			var n: int = m.swipes.size()
			if n > 1:
				_op(ops, "", "tri_left", func(): Game.set_swipe(id, int(m.swipe) - 1), int(m.swipe) > 0 and not busy, "上一版")
				var k := Lbl.new(); k.setup("%d / %d" % [int(m.swipe) + 1, n], 22, "ink", 800); ops.add_child(k)
				_op(ops, "", "tri_right", func(): Game.set_swipe(id, int(m.swipe) + 1), int(m.swipe) < n - 1 and not busy, "下一版")
			if id == last_ai:
				_op(ops, "重新生成", "refresh", func(): close_backlog(); Game.regenerate(id), not busy)
				_op(ops, "继续写", "next", func(): close_backlog(); Game.continue_reply(id), not busy)
			_op(ops, "改原文", "docs", func(): close_backlog(); root.go("edit", {"id": id}, "slide"), not busy)
		else:
			_op(ops, "编辑", "docs", func(): close_backlog(); root.go("edit", {"id": id}, "slide"), not busy)
		if id != int(Game.messages.back().id):
			_op(ops, "回到这里", "replay", func(): _confirm_op("回到这一条", "这一条之后的内容会被删掉。需要的话先另开分支。", func(): Game.rewind_to(id)), not busy)
		_op(ops, "另开分支", "swap", func(): Game.branch_from(id), not busy)
		if id != 0:
			_op(ops, "删除", "trash", func(): _confirm_op("删除这一条", "删除后无法恢复。", func(): Game.delete_message(id)), not busy)
	log_scroll.call_deferred("set", "scroll_vertical", 1000000)

func _op(parent: Control, caption: String, ic: String, cb: Callable, enabled := true, tip := "") -> void:
	var b := Btn.new(); b.setup(caption, ic, "chip" if caption != "" else "icon", 20)
	b.custom_minimum_size = Vector2(150 if caption != "" else 64, 48)
	if caption.length() > 3: b.custom_minimum_size.x = 170
	b.disabled = not enabled; b.tooltip_text = tip if tip != "" else caption
	b.pressed.connect(cb); parent.add_child(b)

func _confirm_op(title: String, msg: String, cb: Callable) -> void:
	var d = root.dialog({"title": title, "message": msg, "icon": "warn", "tone": "danger", "buttons": [{"id": "cancel", "text": "取消", "icon": "close"}, {"id": "ok", "text": "确定", "icon": "tri_right", "kind": "primary"}]})
	d.chosen.connect(func(id): if id == "ok": cb.call())

func close_backlog() -> void:
	if backlog_open: UiHub.sfx("close_book")
	backlog_open = false
	if is_instance_valid(backlog): backlog.queue_free()
	if not lines.is_empty(): _show_line(clampi(index, 0, lines.size() - 1), false); _finish_typing()

# ---------- 阶段大总结 modal (macro recap over all <summary> floors) ----------
func open_recap() -> void:
	if backlog_open: close_backlog()
	if recap_open: _refresh_recap(); return
	UiHub.sfx("open_book")
	recap_open = true; set_auto(false); set_skip(false); recap_dirty = false
	recap_modal = Control.new(); recap_modal.mouse_filter = Control.MOUSE_FILTER_STOP; recap_modal.name = "RecapModal"; recap_modal.set_meta("layer", true)
	put(recap_modal, Rect2(Vector2.ZERO, size), "lt")
	var shade := ColorRect.new(); recap_modal.add_child(shade); shade.size = size; Kit.frost(shade)
	var p := plate(Rect2(210, 80, 1500, 920), {"shape": "cut", "slant": 36, "corner": "tr", "hatch": true}, "c", -1.0, recap_modal)
	header("阶段大总结", Rect2(50, 26, 260, 56), 34, "c", p)
	text("手动归纳全部 <summary> 小总结为全局前史记忆，保存后将注入后续对话。", Rect2(310, 30, 1020, 50), 19, "muted", 600, "c", p)
	btn("", "close", "icon", Rect2(1380, 22, 84, 64), func(): close_recap(), "c", -1.0, p)
	recap_status_lbl = text("", Rect2(50, 96, 1400, 44), 21, "ink", 700, "c", p)
	recap_edit = TextEdit.new(); recap_edit.name = "RecapEditor"; recap_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	recap_edit.placeholder_text = "尚无阶段大总结。\n当剧情累积了 <summary> 小总结后，点击左下角“生成大总结”即可汇总全部前史；也可在此直接编辑后保存。"
	put(recap_edit, Rect2(50, 152, 1400, 628), "c", -1.0, p)
	recap_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	recap_edit.text_changed.connect(func():
		if is_instance_valid(recap_edit):
			recap_dirty = recap_edit.text.strip_edges() != _last_recap_snapshot_text
	)
	recap_edit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			var step_lines := 3.0 * maxf(1.0, e.factor)
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				recap_edit.scroll_vertical = maxf(0.0, recap_edit.scroll_vertical - step_lines)
				recap_edit.accept_event()
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				recap_edit.scroll_vertical += step_lines
				recap_edit.accept_event()
	)
	recap_gen_btn = btn("生成大总结", "refresh", "primary", Rect2(50, 804, 340, 84), func(): _trigger_macro_summary(), "c", -1.0, p, 24)
	recap_gen_btn.name = "GenerateMacroSummary"; recap_gen_btn.center_text = true
	recap_save_btn = btn("保存修改", "save", "secondary", Rect2(410, 804, 240, 84), func(): _save_macro_summary(), "c", -1.0, p, 24)
	recap_save_btn.name = "SaveMacroSummary"; recap_save_btn.center_text = true
	var view_db := btn("查看小总结数据库", "docs", "secondary", Rect2(670, 804, 320, 84), func(): close_recap(); root.go("database", {"tab": "timeline"}, "slide"), "c", -1.0, p, 22)
	view_db.name = "RecapOpenDatabase"; view_db.center_text = true
	var close_b := btn("关闭", "close", "secondary", Rect2(1190, 804, 260, 84), func(): close_recap(), "c", -1.0, p, 24)
	close_b.center_text = true
	_last_recap_snapshot_text = String(Game.recap.get("text", "")).strip_edges()
	recap_edit.text = _last_recap_snapshot_text
	_refresh_recap(true)

func _refresh_recap(force_text := false) -> void:
	if not recap_open or not is_instance_valid(recap_modal): return
	var r: Dictionary = Game.recap
	var micro_count := int(r.get("summary_count", 0))
	var src_count := int(r.get("source_count", 0))
	var saved_text := String(r.get("text", "")).strip_edges()
	var updated_at := String(r.get("updated_at", ""))
	var busy_now := bool(Game.generation.get("busy", false))
	var is_macro_busy := busy_now and String(Game.generation.get("kind", "")) == "macro_summary"
	if is_instance_valid(recap_status_lbl):
		if is_macro_busy:
			recap_status_lbl.text = "正在收集全部 %d 条小总结并请求 AI 归纳阶段大总结，请稍候…" % micro_count
		elif saved_text != "":
			var stamp := (" · 更新于 " + updated_at.substr(0, 19).replace("T", " ")) if updated_at != "" else ""
			recap_status_lbl.text = "当前共有 %d 条小总结 · 已总结 %d 条%s" % [micro_count, src_count, stamp]
		elif micro_count <= 0:
			recap_status_lbl.text = "当前对话尚无 <summary> 小总结（请先推进剧情并生成至少一条小总结，再手动总结）。"
		else:
			recap_status_lbl.text = "已收集 %d 条 <summary> 小总结 · 尚未生成阶段大总结（点击“生成大总结”即可汇总）。" % micro_count
	if is_instance_valid(recap_gen_btn):
		recap_gen_btn.caption = "整理中…" if is_macro_busy else ("重新生成大总结" if saved_text != "" else "生成大总结")
		recap_gen_btn.disabled = busy_now
		recap_gen_btn.queue_redraw()
	if is_instance_valid(recap_save_btn):
		recap_save_btn.disabled = busy_now
	if is_instance_valid(recap_edit) and (force_text or (not recap_dirty and saved_text != _last_recap_snapshot_text)):
		recap_edit.text = saved_text
		_last_recap_snapshot_text = saved_text
		recap_dirty = false

func _trigger_macro_summary() -> void:
	var micro_count := int(Game.recap.get("summary_count", 0))
	if micro_count <= 0:
		toast("当前对话尚无可用的 <summary> 小总结，请先推进剧情后再手动生成阶段大总结。", "warn")
		return
	recap_dirty = false
	Game.generate_macro_summary()

func _save_macro_summary() -> void:
	if not is_instance_valid(recap_edit): return
	recap_dirty = false
	_last_recap_snapshot_text = recap_edit.text.strip_edges()
	Game.save_macro_summary(recap_edit.text)
	UiHub.sfx("save")

func close_recap() -> void:
	if recap_open: UiHub.sfx("close_book")
	recap_open = false; recap_dirty = false
	if is_instance_valid(recap_modal): recap_modal.queue_free()

func _free_only_open() -> bool:
	return is_instance_valid(panel) and lines[index].get("choices", []).is_empty() and not panel.readonly

func on_back() -> bool:
	if is_instance_valid(cg_zoom): _close_cg_zoom(); return true
	if recap_open: close_recap(); return true
	if backlog_open: close_backlog(); return true
	if _free_only_open(): _clear_choices(); next_mark.visible = index < lines.size() - 1; return true
	if ui_hidden: set_hidden(false); return true
	_leave()
	return true

func _leave() -> void:
	if root.stack.size() > 1: root.back()
	else: root.home()

func _gui_input(e: InputEvent) -> void:
	if backlog_open or recap_open: return
	if e is InputEventMouseButton and e.pressed:
		if ui_hidden: set_hidden(false); accept_event(); return
		if _free_only_open() and e.button_index == MOUSE_BUTTON_LEFT:
			_clear_choices(); accept_event(); return
		if e.button_index == MOUSE_BUTTON_LEFT: advance(); accept_event()
		elif e.button_index == MOUSE_BUTTON_RIGHT: set_hidden(true); accept_event()
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP: open_backlog(); accept_event()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: advance(); accept_event()

func _unhandled_key_input(e: InputEvent) -> void:
	if backlog_open or recap_open or not e.pressed: return
	if is_instance_valid(input) and input.has_focus(): return
	if e.is_action("ui_accept") or (e is InputEventKey and e.keycode == KEY_SPACE):
		if ui_hidden: set_hidden(false)
		else: advance()
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.keycode == KEY_H:
		set_hidden(not ui_hidden); get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.keycode == KEY_A:
		set_auto(not auto_mode); get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.keycode == KEY_CTRL:
		set_skip(true); get_viewport().set_input_as_handled()
