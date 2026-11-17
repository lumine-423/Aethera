extends "res://scripts/ui/ui_screen.gd"
## 出身转盘选择（复刻原卡旋转轮盘交互：两侧卡点击/滑动旋转、正面卡弹窗详情、自定义出身校验 API）。

const CARD_W := 292.0
const CARD_H := 424.0
const WHEEL_CENTER := Vector2(900.0, 256.0)
const WHEEL_RX := 630.0
const WHEEL_RY := 34.0

var picked := 0
var _visual_angle := 0.0
var _target_angle := 0.0
var _angle_tween: Tween
var _stage: Control
var _orbit_bg: Control
var _cards: Array[Control] = []
var _card_highlights: Array[Control] = []
var _card_hints: Array[Label] = []
var _dots: Array[Button] = []

var _info_name: Label
var _info_desc: Label
var _info_idx: Label
var _footer_hint: Label
var _detail_pop: Control
var _pop_idx := -1
var _api_pop: Control

var _drag_active := false
var _drag_moved := false
var _drag_start_x := 0.0
var _drag_base_angle := 0.0

func _origin_list() -> Array:
	return Data.content().get("origins", [])

func _initial_picked(origins: Array) -> int:
	if origins.is_empty(): return 0
	if params.has("origin"):
		var want_k := String(params.get("origin", ""))
		for i in range(origins.size()):
			if String(origins[i].get("key", "")) == want_k:
				return i
	if params.has("picked"):
		return clampi(int(params.get("picked", 0)), 0, origins.size() - 1)
	return clampi(picked, 0, origins.size() - 1)

func _accent_of(o: Dictionary) -> Color:
	var raw := String(o.get("accent", ""))
	if raw.is_valid_html_color():
		return Color.html(raw)
	return UiHub.c("accent")

func build() -> void:
	var hub: Dictionary = Data.content().get("hub", {})
	chrome(String(hub.get("originLabel", "出身")))
	decor(63, Rect2(Vector2.ZERO, size), 0.45)

	var origins := _origin_list()
	if origins.is_empty(): return
	picked = _initial_picked(origins)
	var step := 360.0 / float(origins.size())
	_visual_angle = -float(picked) * step
	_target_angle = _visual_angle

	_cards.clear()
	_card_highlights.clear()
	_card_hints.clear()
	_dots.clear()

	# ── 1. 顶部旋转轮盘舞台 ──────────────────────────────────────────────────
	_stage = Control.new()
	_stage.name = "WheelStage"
	_stage.clip_contents = false
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_gui_input)
	put(_stage, Rect2(60, 114, 1800, 540), "c", 0.02)

	_orbit_bg = Control.new()
	_orbit_bg.name = "WheelOrbit"
	_orbit_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	put(_orbit_bg, Rect2(Vector2.ZERO, Vector2(1800, 540)), "c", -1.0, _stage)
	_orbit_bg.draw.connect(_draw_orbit_backdrop)

	for i in range(origins.size()):
		_build_wheel_card(i, origins[i], hub)

	# ── 2. 轮盘左右切换与下方信息栏（listName / listDesc / idx / 详情入口） ──────
	var prev_btn := btn(String(hub.get("wheelPrev", "上一个")), "back", "secondary", Rect2(170, 704, 184, 78), func(): rotate_by(-1), "c", 0.08, null, 24)
	prev_btn.name = "WheelPrevBtn"
	prev_btn.center_text = true

	var info_plate := plate(Rect2(374, 668, 1172, 166), {"shape": "cut", "slant": 26, "corner": "tr", "hatch": true, "stripe": "left"}, "c", 0.1)
	info_plate.name = "WheelInfoPlate"
	_info_name = text("", Rect2(48, 18, 704, 44), 32, "ink", 900, "c", info_plate)
	_info_name.name = "WheelListName"
	_info_idx = text("", Rect2(760, 22, 150, 34), 20, "accent", 800, "c", info_plate, HORIZONTAL_ALIGNMENT_RIGHT)
	_info_idx.name = "WheelIdxLabel"
	var detail_btn := btn("详情档案", "docs", "secondary", Rect2(928, 16, 212, 48), func(): open_detail_pop(picked), "c", -1.0, info_plate, 20)
	detail_btn.name = "OpenDetailBtn"
	detail_btn.center_text = true
	_info_desc = text("", Rect2(48, 74, 1090, 76), 20, "muted", 600, "c", info_plate)
	_info_desc.name = "WheelListDesc"
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	var next_btn := btn(String(hub.get("wheelNext", "下一个")), "next", "secondary", Rect2(1566, 704, 184, 78), func(): rotate_by(1), "c", 0.08, null, 24)
	next_btn.name = "WheelNextBtn"
	next_btn.center_text = true

	# ── 3. 快捷分度条（8 出身速跳圆徽） ──────────────────────────────────────
	var n := origins.size()
	var dot_w := 102.0
	var dot_gap := 14.0
	var total_w := float(n) * dot_w + float(n - 1) * dot_gap
	var start_x := (1920.0 - total_w) * 0.5
	for i in range(n):
		var o: Dictionary = origins[i]
		var seal_txt := String(o.get("wheelSeal", String(o.get("name", "")).left(1)))
		var db := btn(seal_txt, "", "secondary", Rect2(start_x + float(i) * (dot_w + dot_gap), 854, dot_w, 46), _make_dot_cb(i), "c", 0.12 + i * 0.015, null, 19)
		db.name = "Dot_" + String(o.get("key", str(i)))
		db.center_text = true
		db.tooltip_text = String(o.get("wheelName", o.get("name", "")))
		_dots.append(db)

	# ── 4. 底部确认栏 ────────────────────────────────────────────────────────
	_footer_hint = text("", Rect2(64, 944, 1320, 68), 20, "muted", 650)
	_footer_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var ok := btn(String(hub.get("wheelOk", "确认出身")), "next", "primary", Rect2(1436, 934, 420, 96), func(): _confirm(), "c", 0.18, null, 32)
	ok.name = "ConfirmOrigin"
	ok.arrow = true

	_layout_wheel(_visual_angle)
	_sync_wheel_info()

func _make_dot_cb(idx: int) -> Callable:
	return func(): rotate_to(idx)

func _draw_orbit_backdrop() -> void:
	if not is_instance_valid(_orbit_bg): return
	var col := UiHub.c("line")
	var acc := _accent_of(_origin_list()[picked]) if not _origin_list().is_empty() else UiHub.c("accent")
	# 后层轨道椭圆弧
	var pts := PackedVector2Array()
	for i in range(65):
		var a := float(i) / 64.0 * TAU
		pts.append(Vector2(WHEEL_CENTER.x + sin(a) * (WHEEL_RX + 46.0), WHEEL_CENTER.y + 42.0 - (1.0 - cos(a)) * (WHEEL_RY + 26.0)))
	_orbit_bg.draw_polyline(pts, Color(col, 0.28), 2.0, true)
	# 正前聚焦准星底座环
	_orbit_bg.draw_arc(WHEEL_CENTER + Vector2(0, 178), 164.0, 0.0, TAU, 48, Color(acc, 0.26), 2.0, true)
	_orbit_bg.draw_arc(WHEEL_CENTER + Vector2(0, 178), 192.0, -PI * 0.25, PI * 1.25, 36, Color(col, 0.35), 1.5, true)

func _build_wheel_card(idx: int, o: Dictionary, hub: Dictionary) -> void:
	var card := Button.new()
	card.name = "Origin_" + String(o.get("key", str(idx)))
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty_sb := StyleBoxEmpty.new()
	for st_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		card.add_theme_stylebox_override(st_name, empty_sb)
	card.size = Vector2(CARD_W, CARD_H)
	card.pivot_offset = Vector2(CARD_W * 0.5, CARD_H * 0.5)
	_stage.add_child(card)
	_cards.append(card)

	var acc := _accent_of(o)
	var body := plate(Rect2(0, 0, CARD_W, CARD_H), {"shape": "cut", "slant": 26, "corner": "tr", "fill": "surface", "fill_alpha": 0.96, "hatch": true, "dots": true}, "c", -1.0, card)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 主题色光晕描边与左侧色条
	var rim := Control.new()
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.add_child(rim)
	var is_custom := String(o.get("key", "")) == "custom"
	rim.draw.connect(func():
		var is_front := (idx == picked)
		var border_col := Color(acc, 0.92 if is_front else 0.42)
		rim.draw_rect(Rect2(10, 16, 6, CARD_H - 32), border_col)
		rim.draw_line(Vector2(26, 232), Vector2(CARD_W - 26, 232), Color(acc, 0.45 if is_front else 0.2), 2.0, true)
		if is_front:
			rim.draw_rect(Rect2(2, 2, CARD_W - 4, CARD_H - 4), Color(acc, 0.28), false, 2.5)
	)
	_card_highlights.append(rim)

	# 上半视觉窗：场景微缩预览 + 水印大字
	var preview_bg := plate(Rect2(20, 18, CARD_W - 40, 200), {"slant": 18, "fill": "surface2", "fill_alpha": 0.95, "border": "", "layered": false, "glass": false}, "c", -1.0, body)
	preview_bg.clip_contents = true
	preview_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scene_tex := _find_origin_preview_tex(o)
	if scene_tex != null:
		var art := TextureRect.new()
		art.texture = scene_tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(1, 1, 1, 0.42)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		put(art, Rect2(0, 0, CARD_W - 40, 200), "c", -1.0, preview_bg)
	var wm := text(String(o.get("wheelSeal", "")), Rect2(0, 10, CARD_W - 40, 162), 112, "ink", 900, "c", preview_bg, HORIZONTAL_ALIGNMENT_CENTER)
	wm.modulate = Color(acc.r, acc.g, acc.b, 0.34 if scene_tex != null else 0.28)
	wm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	if is_custom:
		var badge := plate(Rect2(CARD_W - 40 - 160, 158, 150, 32), {"slant": 10, "fill": "accent", "fill_alpha": 0.92, "border": "", "layered": false, "glass": false}, "c", -1.0, preview_bg)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		text("随机开局 · 需API", Rect2(0, 0, 150, 32), 14, "on_accent", 800, "c", badge, HORIZONTAL_ALIGNMENT_CENTER)

	# 下半出身印章 + 卡片名字（wheelName）+ 标签
	var seal_box := plate(Rect2(24, 246, 54, 54), {"slant": 12, "fill": "accent", "fill_alpha": 0.92, "border": "", "layered": false, "glass": false}, "c", -1.0, body)
	seal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text(String(o.get("wheelSeal", "")), Rect2(0, 0, 54, 54), 28, "on_accent", 900, "c", seal_box, HORIZONTAL_ALIGNMENT_CENTER)

	var wname := text(String(o.get("wheelName", o.get("name", ""))), Rect2(88, 246, CARD_W - 108, 54), 25, "ink", 900, "c", body)
	wname.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wname.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var wtag := text(String(o.get("popTag", "")), Rect2(24, 310, CARD_W - 48, 42), 16, "accent", 700, "c", body)
	wtag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wtag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var hint_lbl := text(String(hub.get("popHint", "点击查看")), Rect2(24, 368, CARD_W - 48, 34), 16, "muted", 700, "c", body, HORIZONTAL_ALIGNMENT_CENTER)
	_card_hints.append(hint_lbl)

	card.pressed.connect(func():
		if _drag_moved: return
		_on_card_activated(idx)
	)
	card.gui_input.connect(func(ev): _on_card_or_stage_drag(ev))

func _find_origin_preview_tex(o: Dictionary) -> Texture2D:
	var scene_id := String(o.get("preview_scene_id", ""))
	if scene_id == "": return null
	for s in Data.content().get("scenes", []):
		if String(s.get("id", "")) == scene_id or String(s.get("scene", "")) == scene_id:
			var res_p := String(s.get("res", ""))
			if res_p != "" and ResourceLoader.exists(res_p):
				return load(res_p)
	return null

func _on_card_activated(idx: int) -> void:
	if idx == picked:
		open_detail_pop(idx)
	else:
		rotate_to(idx)

func _on_stage_gui_input(ev: InputEvent) -> void:
	_on_card_or_stage_drag(ev)

func _on_card_or_stage_drag(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			rotate_by(-1); get_viewport().set_input_as_handled(); return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			rotate_by(1); get_viewport().set_input_as_handled(); return
		if mb.button_index != MOUSE_BUTTON_LEFT: return
		if mb.pressed:
			_drag_active = true
			_drag_moved = false
			_drag_start_x = mb.global_position.x
			_drag_base_angle = _visual_angle
			if is_instance_valid(_angle_tween): _angle_tween.kill()
		else:
			if _drag_active and _drag_moved:
				var origins := _origin_list()
				if not origins.is_empty():
					var step := 360.0 / float(origins.size())
					var delta_x := mb.global_position.x - _drag_start_x
					if absf(delta_x) >= 42.0:
						rotate_by(-1 if delta_x > 0.0 else 1)
					else:
						rotate_to(picked)
				get_viewport().set_input_as_handled()
			_drag_active = false
			call_deferred("_clear_drag_moved")
	elif ev is InputEventMouseMotion and _drag_active:
		var mm := ev as InputEventMouseMotion
		var dx := mm.global_position.x - _drag_start_x
		if absf(dx) > 12.0:
			_drag_moved = true
			_visual_angle = _drag_base_angle + clampf(dx * 0.14, -65.0, 65.0)
			_layout_wheel(_visual_angle)

func _clear_drag_moved() -> void:
	_drag_moved = false

func rotate_by(delta: int) -> void:
	rotate_to(picked + delta)

func rotate_to(idx: int, instant := false) -> void:
	var origins := _origin_list()
	var n := origins.size()
	if n <= 0: return
	var prev := picked
	var next_idx := ((idx % n) + n) % n
	picked = next_idx
	var step := 360.0 / float(n)
	var d := float(next_idx - prev)
	if d > float(n) * 0.5: d -= float(n)
	if d < -float(n) * 0.5: d += float(n)
	_target_angle -= d * step
	if prev != next_idx:
		UiHub.sfx("card")
	if is_instance_valid(_angle_tween): _angle_tween.kill()
	if instant or UiHub.reduced_motion:
		_visual_angle = _target_angle
		_layout_wheel(_visual_angle)
	else:
		_angle_tween = create_tween()
		_angle_tween.tween_method(_layout_wheel, _visual_angle, _target_angle, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sync_wheel_info()

func _layout_wheel(angle_deg: float) -> void:
	_visual_angle = angle_deg
	var origins := _origin_list()
	var n := origins.size()
	if n <= 0 or _cards.size() != n: return
	var step := 360.0 / float(n)
	for k in range(n):
		var c: Control = _cards[k]
		if not is_instance_valid(c): continue
		var theta := deg_to_rad(float(k) * step + angle_deg)
		var cval := cos(theta)
		var sval := sin(theta)
		var depth := clampf((cval + 1.0) * 0.5, 0.0, 1.0)
		var sc := lerpf(0.56, 1.04, pow(depth, 1.12))
		var alpha := lerpf(0.28, 1.0, pow(depth, 1.15))
		var pos := Vector2(WHEEL_CENTER.x + sval * WHEEL_RX, WHEEL_CENTER.y - (1.0 - cval) * WHEEL_RY)
		c.position = pos - Vector2(CARD_W * 0.5, CARD_H * 0.5)
		c.scale = Vector2(sc, sc)
		c.modulate = Color(1, 1, 1, alpha)
		c.z_index = 20 + int(round(depth * 100.0)) + (10 if k == picked else 0)
	if is_instance_valid(_orbit_bg):
		_orbit_bg.queue_redraw()

func _sync_wheel_info() -> void:
	var origins := _origin_list()
	var n := origins.size()
	if n <= 0: return
	picked = clampi(picked, 0, n - 1)
	var o: Dictionary = origins[picked]
	var hub: Dictionary = Data.content().get("hub", {})
	if is_instance_valid(_info_name):
		_info_name.text = String(o.get("listName", o.get("name", "")))
	if is_instance_valid(_info_desc):
		_info_desc.text = String(o.get("listDesc", ""))
	if is_instance_valid(_info_idx):
		_info_idx.text = "%d / %d" % [picked + 1, n]
	for k in range(_cards.size()):
		if k < _card_highlights.size() and is_instance_valid(_card_highlights[k]):
			_card_highlights[k].queue_redraw()
		if k < _card_hints.size() and is_instance_valid(_card_hints[k]):
			_card_hints[k].text = String(hub.get("popHint", "点击查看详情")) if k == picked else "点击转至正面"
	for k in range(_dots.size()):
		if is_instance_valid(_dots[k]):
			_dots[k].selected = (k == picked)
			if _dots[k].has_method("queue_redraw"):
				_dots[k].queue_redraw()
	if is_instance_valid(_footer_hint):
		if String(o.get("key", "")) == "custom":
			if Game.has_configured_api():
				_footer_hint.text = "自定义出身：已检测到可用 API。仅设定时间为 1015年·2月1日，开局地点与首幕剧情将由 AI 根据你的资料随机生成。"
			else:
				_footer_hint.text = "注意：「自定义」出身须先配置可用 API（仅设时间 1015年·2月1日，地点不预设）。点击「确认出身」可先前往配置 API。"
		else:
			_footer_hint.text = "点击两侧卡片或方向键旋转轮盘 · 点击正面卡片查看详档 · 已开放全部 8 项出身"

# ── 出身详情弹窗（点正面卡 / 详情档案弹出） ──────────────────────────────────
func open_detail_pop(idx := picked) -> void:
	var origins := _origin_list()
	if origins.is_empty(): return
	idx = clampi(idx, 0, origins.size() - 1)
	close_detail_pop()
	_pop_idx = idx
	UiHub.sfx("card")
	var o: Dictionary = origins[idx]
	var acc := _accent_of(o)

	_detail_pop = Control.new()
	_detail_pop.name = "OriginPop"
	put(_detail_pop, Rect2(Vector2.ZERO, size), "c")
	_detail_pop.z_index = 400

	var dim := Button.new()
	dim.name = "OriginPopBackdrop"
	dim.flat = true
	dim.focus_mode = Control.FOCUS_NONE
	var esb := StyleBoxEmpty.new()
	for sname in ["normal", "hover", "pressed", "focus", "disabled"]:
		dim.add_theme_stylebox_override(sname, esb)
	put(dim, Rect2(Vector2.ZERO, size), "c", -1.0, _detail_pop)
	dim.draw.connect(func(): dim.draw_rect(Rect2(Vector2.ZERO, dim.size), Color(0.02, 0.03, 0.05, 0.68)))
	dim.pressed.connect(func(): UiHub.sfx("cancel"); close_detail_pop())

	var box := plate(Rect2(340, 108, 1240, 864), {"shape": "cut", "slant": 44, "corner": "tr", "fill": "surface", "fill_alpha": 0.99, "hatch": true, "dots": true}, "c", -1.0, _detail_pop)
	box.name = "OriginPopBox"
	var box_rim := Control.new()
	box_rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(box_rim)
	box_rim.draw.connect(func():
		box_rim.draw_rect(Rect2(0, 12, 8, 840), acc)
	)

	# 弹窗上半：预览图 + 印章
	var art := W.Portrait.new()
	art.kind = "scene"; art.frame = false
	put(art, Rect2(28, 24, 1184, 344), "c", -1.0, box)
	var tex := _find_origin_preview_tex(o)
	if tex != null:
		art.set_texture(tex, false)
	else:
		var ph := plate(Rect2(28, 24, 1184, 344), {"slant": 18, "fill": "surface2", "layered": false, "glass": false}, "c", -1.0, box)
		text(String(o.get("popSeal", o.get("wheelSeal", ""))), Rect2(0, 26, 1184, 210), 140, "accent", 900, "c", ph, HORIZONTAL_ALIGNMENT_CENTER)
		text(String(Data.content().get("hub", {}).get("imgPending", "动态随机开局（无固定场景预览）")), Rect2(0, 244, 1184, 48), 22, "muted", 650, "c", ph, HORIZONTAL_ALIGNMENT_CENTER)

	var pop_seal := plate(Rect2(44, 304, 116, 116), {"slant": 24, "fill": "accent", "fill_alpha": 1.0, "border": "", "layered": false, "glass": false}, "c", -1.0, box)
	text(String(o.get("popSeal", o.get("wheelSeal", ""))), Rect2(0, 0, 116, 116), 62, "on_accent", 900, "c", pop_seal, HORIZONTAL_ALIGNMENT_CENTER)

	var close_x := btn("×", "", "icon", Rect2(1156, 26, 56, 56), func(): UiHub.sfx("cancel"); close_detail_pop(), "c", -1.0, box, 28)
	close_x.name = "OriginPopCloseX"

	text(String(o.get("popName", o.get("name", ""))), Rect2(182, 386, 980, 62), 46, "ink", 900, "c", box)
	text(String(o.get("popTag", "")), Rect2(182, 448, 980, 36), 23, "accent", 800, "c", box)

	var pdesc := text(String(o.get("popDesc", "")), Rect2(44, 502, 1152, 166), 22, "ink", 600, "c", box)
	pdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pdesc.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	var meta_box := plate(Rect2(44, 678, 1152, 74), {"slant": 18, "fill": "surface2", "layered": false, "stripe": "left"}, "c", -1.0, box)
	if String(o.get("key", "")) == "custom":
		text("开局时间：1015年·2月1日　｜　开局地点：不预设（进入后由 AI 依你的角色设定随机选址开局，须配置 API）", Rect2(44, 0, 1082, 74), 19, "muted", 700, "c", meta_box)
	else:
		var istat: Dictionary = o.get("init_stat", {})
		var hero: Dictionary = istat.get("主角组", {}) if istat.get("主角组") is Dictionary else {}
		var allies: Dictionary = istat.get("角色组", {}) if istat.get("角色组") is Dictionary else {}
		var ally_names := PackedStringArray()
		for ak in allies: ally_names.append(str(ak))
		var ally_txt := "、".join(ally_names) if not ally_names.is_empty() else "自由探索（无固定初始同伴）"
		text("开局地点：%s　｜　初始同伴：%s" % [String(hero.get("当前地点", o.get("name", ""))), ally_txt], Rect2(44, 0, 1082, 74), 19, "muted", 700, "c", meta_box)

	var pop_close := btn("关闭详情", "back", "secondary", Rect2(44, 768, 250, 72), func(): UiHub.sfx("cancel"); close_detail_pop(), "c", -1.0, box, 22)
	pop_close.name = "OriginPopCloseBtn"
	pop_close.center_text = true
	var pop_ok := btn("选择此出身", "next", "primary", Rect2(866, 768, 330, 72), func():
		close_detail_pop()
		_confirm()
	, "c", -1.0, box, 24)
	pop_ok.name = "OriginPopConfirmBtn"
	pop_ok.arrow = true

func close_detail_pop() -> void:
	_pop_idx = -1
	if is_instance_valid(_detail_pop):
		_detail_pop.queue_free()
		_detail_pop = null

func _open_api_required_pop() -> void:
	_close_api_pop()
	UiHub.sfx("warn")
	_api_pop = Control.new()
	_api_pop.name = "CustomOriginApiPop"
	put(_api_pop, Rect2(Vector2.ZERO, size), "c")
	_api_pop.z_index = 450

	var dim := Button.new()
	dim.flat = true; dim.focus_mode = Control.FOCUS_NONE
	var esb := StyleBoxEmpty.new()
	for sname in ["normal", "hover", "pressed", "focus", "disabled"]:
		dim.add_theme_stylebox_override(sname, esb)
	put(dim, Rect2(Vector2.ZERO, size), "c", -1.0, _api_pop)
	dim.draw.connect(func(): dim.draw_rect(Rect2(Vector2.ZERO, dim.size), Color(0.02, 0.03, 0.05, 0.68)))
	dim.pressed.connect(func(): _close_api_pop())

	var box := plate(Rect2(500, 320, 920, 420), {"shape": "cut", "slant": 36, "corner": "tr", "fill": "surface", "fill_alpha": 0.99, "hatch": true}, "c", -1.0, _api_pop)
	text("「自定义」出身须先配置 API", Rect2(46, 38, 828, 50), 34, "ink", 900, "c", box)
	var msg := text("「自定义」不会使用固定地点或固定开场白：\n• 开局时间固定为：1015年·2月1日\n• 开局地点与开场事件将根据你填写的人物信息，由模型实时随机生成。\n\n请先填好可用的 AI 接口地址与模型名称，再使用「自定义」开始游戏。", Rect2(46, 108, 828, 196), 21, "muted", 600, "c", box)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var stay_btn := btn("稍后再说", "back", "secondary", Rect2(46, 320, 260, 70), func(): _close_api_pop(), "c", -1.0, box, 22)
	stay_btn.name = "ApiPopStayBtn"
	stay_btn.center_text = true
	var go_api := btn("前往配置 API", "next", "primary", Rect2(564, 320, 310, 70), func():
		_close_api_pop()
		root.go("connect", {"next": "origin", "next_params": {"picked": picked}}, "wipe")
	, "c", -1.0, box, 24)
	go_api.name = "ApiPopGoConnectBtn"
	go_api.arrow = true

func _close_api_pop() -> void:
	if is_instance_valid(_api_pop):
		_api_pop.queue_free()
		_api_pop = null

func _confirm() -> void:
	var origins := _origin_list()
	if origins.is_empty(): return
	var o: Dictionary = origins[clampi(picked, 0, origins.size() - 1)]
	if String(o.get("key", "")) == "custom" and not Game.has_configured_api():
		_open_api_required_pop()
		return
	UiHub.sfx("confirm_big")
	root.go("create", {"origin": o.key}, "slide_in")

func _unhandled_key_input(e: InputEvent) -> void:
	if not e.is_pressed(): return
	if is_instance_valid(_api_pop):
		if e.is_action("ui_cancel"):
			_close_api_pop()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_detail_pop):
		if e.is_action("ui_cancel"):
			UiHub.sfx("cancel")
			close_detail_pop()
			get_viewport().set_input_as_handled()
		return
	var n := _origin_list().size()
	if n <= 0: return
	if e.is_action("ui_left") or e.is_action("ui_up"):
		rotate_by(-1); get_viewport().set_input_as_handled()
	elif e.is_action("ui_right") or e.is_action("ui_down"):
		rotate_by(1); get_viewport().set_input_as_handled()
