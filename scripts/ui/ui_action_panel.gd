extends Control
## Galgame 行动框. Left: option rows that collapse to one line and expand to the full 2-3 sentence
## text (accordion, one open at a time); last row is 自由输入 (multi-line). Right: tall 确认发送 button.
## The panel grows upward from its bottom edge, rows glide to their new places while one expands.
## Signal confirmed(kind, index, text): kind = "choice" | "free".

signal confirmed(kind: String, index: int, text: String)
signal closed

const Kit = preload("res://scripts/ui/ui_kit.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const Btn = preload("res://scripts/ui/ui_button.gd")
const Lbl = preload("res://scripts/ui/ui_label.gd")
const Plate = preload("res://scripts/ui/ui_plate.gd")

signal draft_changed(text: String)

var options: Array = []           # full option texts
var allow_free := true
var readonly := false             # replay: show the picked option only
var before_confirm: Callable     # Reject before emitting, closing, or losing the draft.
var picked_text := ""
var bottom_y := 700.0             # panel bottom edge in parent coordinates
var width := 1180.0
const CONFIRM_W := 230.0
const HEAD_H := 56.0
const ROW_MIN := 76.0

var rows: Array = []              # {node, label, cur, target, kind, index}
var selected := -1
var expanded := -1
var confirm: Button
var free_edit: TextEdit
var expand_btn: Button
var portrait_btn: Button
var composer_overlay: Control
var head: Control
var backing: Control
var _settled := false
var _suppress_auto_portrait := false
var initial_free_text := ""

func _row_gap() -> float:
	return lerpf(6.0, 14.0, UiHub.spacing)

func _pad_x() -> float:
	return lerpf(78.0, 102.0, UiHub.spacing)

class Row extends Control:
	const K = preload("res://scripts/ui/ui_kit.gd")
	const I = preload("res://scripts/ui/ui_icon.gd")
	signal tapped
	var badge := "A"
	var on := false
	var open := false
	var hover := 0.0
	var spin := 0.0
	var free := false
	var _t: Tween
	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_filter = Control.MOUSE_FILTER_STOP
		clip_contents = true
		UiHub.palette_changed.connect(queue_redraw)
		mouse_entered.connect(func(): _hover(true); UiHub.sfx("hover"))
		mouse_exited.connect(func(): _hover(false))
		resized.connect(queue_redraw)
	func _hover(v: bool) -> void:
		if _t: _t.kill()
		if UiHub.reduced_motion: hover = 1.0 if v else 0.0; queue_redraw(); return
		_t = create_tween(); _t.tween_method(func(x): hover = x; queue_redraw(), hover, 1.0 if v else 0.0, 0.18)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			tapped.emit(); accept_event()
	func _draw() -> void:
		var s := 18.0
		var r := Rect2(Vector2(-3.0 * hover, 0), size)
		var poly := K.slant(r, s)
		draw_colored_polygon(poly, UiHub.c("surface", 0.96 if on else 0.9))
		if on:
			draw_colored_polygon(poly, UiHub.c("accent", 0.06))
			K.stripes(self, poly, UiHub.c("accent", 0.22), 12.0, 0.0, 0.72, 1.5)
		draw_polyline(K.closed(poly), UiHub.c("accent" if on else "line", 1.0 if on else 0.8), 2.0 if on else 1.4, true)
		# badge block
		var bh := minf(size.y, 76.0)
		var blk := K.slant(Rect2(r.position.x, 0, 66, bh), s * bh / maxf(size.y, 1.0))
		K.ornate(self, blk, UiHub.c("accent" if on else "block", 1.0 if on else 0.9))
		if free:
			I.paint(self, "chat", Rect2(r.position.x + 18, bh * 0.5 - 16, 32, 32), UiHub.c("on_accent" if on else "on_block"), UiHub.c("accent"), UiHub.c("accent" if on else "block"))
		else:
			K.text(self, Rect2(r.position.x + 4, 0, 62, bh), badge, UiHub.fs(30), UiHub.c("on_accent" if on else "on_block"), HORIZONTAL_ALIGNMENT_CENTER, 900)
		# chevron
		var c := Vector2(size.x - 40, minf(size.y, 76.0) * 0.5)
		draw_set_transform(c, PI * spin)
		draw_polyline(PackedVector2Array([Vector2(-9, -4), Vector2(0, 5), Vector2(9, -4)]), UiHub.c("accent" if on else "muted"), 3.0, true)
		draw_set_transform(Vector2.ZERO)
		if open:
			K.hatch(self, Vector2(size.x - 92, size.y - 18), 5, 10, UiHub.c("muted", 0.6))
		if hover > 0.01:
			draw_rect(Rect2(r.position + Vector2(66, 0), Vector2(5, minf(size.y, 76.0))), UiHub.c("accent", 0.8 * hover))

## Tall 发送 key. Not a plain block: chamfered parallelogram, accent charge that fills from the
## bottom when a choice becomes valid, two counter-rotating diamond rings around the paper plane,
## marching stripes, corner brackets on hover, and a fly-out of the plane on press.
class SendKey extends Button:
	const K = preload("res://scripts/ui/ui_kit.gd")
	const I = preload("res://scripts/ui/ui_icon.gd")
	var charge := 0.0
	var hover := 0.0
	var reveal := 1.0
	var pulse := false
	var clock := 0.0
	var fly := -1.0
	var hint := ""
	var _ct: Tween
	var _ht: Tween
	func _ready() -> void:
		flat = true; text = ""; focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]: add_theme_stylebox_override(st, StyleBoxEmpty.new())
		mouse_entered.connect(func(): _hov(true); UiHub.sfx("hover", 0.9))
		gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and disabled: UiHub.sfx("deny"))
		mouse_exited.connect(func(): _hov(false))
		UiHub.palette_changed.connect(queue_redraw)
	func set_ready(on: bool) -> void:
		disabled = not on
		if _ct: _ct.kill()
		if UiHub.reduced_motion: charge = 1.0 if on else 0.0; queue_redraw(); return
		_ct = create_tween(); _ct.tween_method(func(v): charge = v; queue_redraw(), charge, 1.0 if on else 0.0, 0.42 if on else 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	func _hov(on: bool) -> void:
		if _ht: _ht.kill()
		_ht = create_tween(); _ht.tween_method(func(v): hover = v; queue_redraw(), hover, 1.0 if on and not disabled else 0.0, 0.2)
	func launch() -> void:
		if UiHub.reduced_motion: return
		var t := create_tween(); t.tween_method(func(v): fly = v; queue_redraw(), 0.0, 1.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	func _process(d: float) -> void:
		if UiHub.reduced_motion or not is_visible_in_tree(): return
		clock += d * (1.0 + 2.5 * hover); queue_redraw()
	func shape() -> PackedVector2Array:
		var w := size.x; var h := size.y; var s := 26.0; var c := 22.0
		return PackedVector2Array([Vector2(s, 0), Vector2(w - c, 0), Vector2(w, c), Vector2(w - s, h), Vector2(c, h), Vector2(0, h - c)])
	func _has_point(p: Vector2) -> bool: return Geometry2D.is_point_in_polygon(p, shape())
	func _draw() -> void:
		var poly := shape(); var w := size.x; var h := size.y
		var ghost := PackedVector2Array()
		for p in poly: ghost.append(p + Vector2(10, 8) + Vector2(6, 2) * hover)
		draw_colored_polygon(ghost, UiHub.c("plane", 0.4))
		draw_colored_polygon(poly, UiHub.c("surface", 0.94))
		K.stripes(self, poly, UiHub.c("line", 0.9), 11.0, 0.0, 0.0, 1.0, false)
		draw_polyline(K.closed(poly), UiHub.c("line"), 1.5, true)
		if charge > 0.001:
			var top := h * (1.0 - charge)
			var cut := Geometry2D.intersect_polygons(poly, PackedVector2Array([Vector2(-10, top), Vector2(w + 10, top - 30.0 * (1.0 - charge)), Vector2(w + 10, h + 10), Vector2(-10, h + 10)]))
			for part in cut: K.ornate(self, part, UiHub.c("accent"), clock * 16.0, 0.0)
			if charge < 1.0: draw_line(Vector2(0, top), Vector2(w, top - 30.0 * (1.0 - charge)), Color(1, 1, 1, 0.8), 2.0, true)
		var on := charge > 0.5
		var ink := UiHub.c("on_accent") if on else UiHub.c("muted")
		var c := Vector2(w * 0.5, h * 0.42)
		var rr := 54.0 * (0.8 + 0.2 * charge) + 4.0 * hover
		K.diamond_rot(self, c, rr, clock * 0.6, Color(ink, 0.55), 1.5)
		K.diamond_rot(self, c, rr * 0.74, -clock * 0.9 + 0.4, Color(ink, 0.9), 2.0)
		for j in range(4):
			K.diamond(self, c + Vector2.from_angle(clock * 0.6 + PI * 0.5 * j) * rr, 3.5, Color(ink, 0.9))
		var plane_off := Vector2(5.0 * hover, -3.0 * hover)
		var plane_a := 1.0
		if fly >= 0.0:
			plane_off = Vector2(1, -1) * 260.0 * fly; plane_a = 1.0 - fly
			for k in range(4):
				var tp := c + plane_off * (1.0 - 0.18 * (k + 1))
				K.diamond(self, tp, 4.0 - k * 0.7, Color(ink, 0.6 * (1.0 - fly) * (1.0 - k * 0.2)))
		I.paint(self, "send", Rect2(c - Vector2(26, 26) + plane_off, Vector2(52, 52)), Color(ink, plane_a), Color(ink, plane_a), UiHub.c("accent") if on else UiHub.c("surface"))
		K.text(self, Rect2(0, h * 0.62, w, 50), "发送", UiHub.fs(36), ink, HORIZONTAL_ALIGNMENT_CENTER, 900)
		K.text(self, Rect2(0, h * 0.62 + 46, w, 24), "S  E  N  D", UiHub.fs(15), Color(ink, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 800)
		if hint != "":
			K.text(self, Rect2(0, h - 44, w - 20, 26), hint, UiHub.fs(17), Color(ink, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 700)
		if hover > 0.01:
			var a := Color(ink if on else UiHub.c("accent"), 0.9 * hover)
			K.bracket(self, Vector2(26, 0), Vector2.RIGHT, Vector2(-26, h).normalized(), a, 18.0, 8.0)
			K.bracket(self, Vector2(w - 26, h), Vector2.LEFT, Vector2(26, -h).normalized(), a, 18.0, 8.0)
		if pulse and not UiHub.reduced_motion:
			var halo := Geometry2D.offset_polygon(poly, 5.0 + 2.0 * sin(clock * 3.0))
			if not halo.is_empty(): draw_polyline(K.closed(halo[0]), UiHub.c("accent", 0.35 + 0.25 * sin(clock * 3.0)), 2.0, true)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiHub.options_changed.connect(_remeasure)
	backing = Control.new(); backing.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(backing)
	var paint_back := func() -> void:
		var r := Rect2(Vector2(-40, HEAD_H - 14), backing.size - Vector2(-60, HEAD_H - 34))
		backing.draw_colored_polygon(Kit.slant(r, 60), UiHub.c("surface", 0.42))
		backing.draw_polyline(Kit.closed(Kit.slant(r, 60)), UiHub.c("line", 0.5), 1.0, true)
		Kit.dots(backing, Vector2(backing.size.x - 120, backing.size.y + 2), 5, 2, 12, 3, UiHub.c("accent", 0.45))
	backing.draw.connect(paint_back)
	UiHub.palette_changed.connect(backing.queue_redraw)
	head = Control.new(); head.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(head)
	var paint_head := func() -> void:
		head.draw_colored_polygon(PackedVector2Array([Vector2(8, 10), Vector2(16, 10), Vector2(10, 46), Vector2(2, 46)]), UiHub.c("accent"))
		Kit.text(head, Rect2(30, 0, 300, 56), "回看选择" if readonly else "行动", UiHub.fs(30), UiHub.c("ink"), HORIZONTAL_ALIGNMENT_LEFT, 900)
		var tip := "当时的选择" if readonly else "点开选项查看完整内容，选好后发送"
		Kit.text(head, Rect2(150, 4, 600, 52), tip, UiHub.fs(19), UiHub.c("muted"), HORIZONTAL_ALIGNMENT_LEFT, 600)
		head.draw_line(Vector2(150 + Kit.text_width(tip, UiHub.fs(19), 600) + 20, 30), Vector2(head.size.x - 60, 30), UiHub.c("line"), 1.5)
		Kit.hatch(head, Vector2(head.size.x - 50, 22), 4, 12, UiHub.c("muted", 0.8))
	head.draw.connect(paint_head)
	UiHub.palette_changed.connect(head.queue_redraw)
	var list: Array = [picked_text] if readonly else options
	for i in range(list.size()):
		_add_row("choice", i, list[i])
	if allow_free and not readonly: _add_row("free", options.size(), "")
	if not readonly:
		confirm = SendKey.new(); confirm.disabled = true; confirm.hint = "请先选择"; add_child(confirm)
		confirm.pressed.connect(_confirm)
	if readonly:
		selected = 0; expanded = 0; rows[0].node.on = true
	elif allow_free and options.is_empty() and not rows.is_empty():
		selected = 0; expanded = 0; rows[0].node.on = true; rows[0].node.open = true; rows[0].node.spin = 1.0
	_remeasure()
	if allow_free and options.is_empty() and not rows.is_empty():
		rows[0].cur = rows[0].target
	_layout(true)
	_enter()

func _add_row(kind: String, index: int, value: String) -> void:
	var r := Row.new(); r.free = kind == "free"; r.badge = String.chr(65 + index)
	add_child(r)
	var l := Label.new(); l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = value if kind == "choice" else "自由输入 · 写下你想说或想做的事"
	l.add_theme_font_override("font", Kit.font(650))
	l.add_theme_constant_override("line_spacing", 8)
	r.add_child(l)
	var entry := {"node": r, "label": l, "cur": ROW_MIN, "target": ROW_MIN, "kind": kind, "index": index, "text": value}
	rows.append(entry)
	r.tapped.connect(func(): _tap(rows.find(entry)))
	if kind == "free":
		free_edit = TextEdit.new(); free_edit.name = "FreeInput"
		free_edit.placeholder_text = "例如：问问她接下来的安排，再决定要去哪里。"
		free_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		free_edit.visible = false
		if initial_free_text != "":
			free_edit.text = initial_free_text
		r.add_child(free_edit)
		free_edit.text_changed.connect(func():
			draft_changed.emit(free_edit.text)
			_refresh_confirm()
		)
		free_edit.focus_entered.connect(func():
			if OS.has_feature("mobile") and not _suppress_auto_portrait and not is_instance_valid(composer_overlay):
				call_deferred("open_composer", true)
			_suppress_auto_portrait = false
		)
		# TextEdit may consume Ctrl+Enter before _unhandled_key_input runs.
		# Handle the send shortcut on the focused editor itself.
		free_edit.gui_input.connect(_on_free_key)
		free_edit.caret_blink = true
		expand_btn = Btn.new(); expand_btn.name = "ExpandInputBtn"
		expand_btn.setup("悬浮窗", "docs", "chip", 16)
		expand_btn.tooltip_text = "把输入框放大成悬浮编辑窗，方便查看完整输入"
		expand_btn.visible = false
		expand_btn.pressed.connect(func(): open_composer(false))
		r.add_child(expand_btn)
		portrait_btn = Btn.new(); portrait_btn.name = "PortraitInputBtn"
		portrait_btn.setup("竖屏输入", "swap", "chip", 16)
		portrait_btn.tooltip_text = "切换到手机竖屏全屏输入模式，确认后自动填充"
		portrait_btn.visible = false
		portrait_btn.pressed.connect(func(): open_composer(true))
		r.add_child(portrait_btn)

func _exit_tree() -> void:
	# Do NOT tear down composer_overlay if a parent rebuild is happening mid-portrait-typing;
	# StoryScreen cleanup or explicit close_composer() resets portrait mode cleanly.
	pass

func _on_free_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ENTER and event.ctrl_pressed:
		free_edit.accept_event()
		if _valid(): _confirm()

func _line_h(px: int) -> float:
	var f := Kit.font(650); return f.get_height(px) + 8.0

func _remeasure() -> void:
	var pad_x := _pad_x()
	var tw := _row_w() - pad_x - 80.0
	for i in range(rows.size()):
		var e: Dictionary = rows[i]
		var l: Label = e.label
		var px := UiHub.fs(26)
		l.add_theme_font_size_override("font_size", px)
		l.add_theme_color_override("font_color", UiHub.c("ink" if e.kind == "choice" else "muted"))
		var open := i == expanded
		if e.kind == "free":
			e.target = (ROW_MIN + 150.0) if open else ROW_MIN
		else:
			var full := Kit.font(650).get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, tw, px)
			var lines := maxi(1, int(round(full.y / Kit.font(650).get_height(px))))
			e.target = maxf(ROW_MIN, 26.0 + lines * _line_h(px) + 22.0) if open else ROW_MIN
	queue_layout()

func _row_w() -> float:
	return width - (0.0 if readonly else CONFIRM_W + 22.0)

func queue_layout() -> void:
	set_process(true)

func _process(delta: float) -> void:
	var moving := false
	var k := 1.0 if UiHub.reduced_motion else 1.0 - exp(-delta * 13.0)
	for e in rows:
		var d: float = e.target - e.cur
		if absf(d) > 0.5: e.cur += d * k; moving = true
		else: e.cur = e.target
	_layout(false)
	if not moving: set_process(false)

func _layout(_snap: bool) -> void:
	var rw := _row_w()
	var gap := _row_gap()
	var pad_x := _pad_x()
	var total := HEAD_H
	for e in rows: total += e.cur + gap
	total -= gap
	size = Vector2(width, total)
	position.y = bottom_y - total
	head.position = Vector2.ZERO; head.size = Vector2(rw, HEAD_H); head.queue_redraw()
	backing.position = Vector2.ZERO; backing.size = Vector2(width, total); backing.queue_redraw()
	var y := HEAD_H
	for i in range(rows.size()):
		var e: Dictionary = rows[i]
		var r: Row = e.node
		r.position = Vector2(-i * 10.0, y); r.size = Vector2(rw, e.cur)
		var l: Label = e.label
		var open := i == expanded
		var hdr_reserve := 340.0 if (e.kind == "free" and open) else 80.0
		l.position = Vector2(pad_x, 0 if not open else 22); l.size = Vector2(maxf(120.0, rw - pad_x - hdr_reserve), ROW_MIN if not open else (42.0 if e.kind == "free" else e.cur - 30.0))
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if (not open or e.kind == "free") else VERTICAL_ALIGNMENT_TOP
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if (open and e.kind != "free") else TextServer.AUTOWRAP_OFF
		l.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if (open and e.kind != "free") else TextServer.OVERRUN_TRIM_ELLIPSIS
		if e.kind == "free" and is_instance_valid(free_edit):
			var show_tools: bool = open and e.cur > ROW_MIN + 40
			free_edit.position = Vector2(pad_x, ROW_MIN - 4); free_edit.size = Vector2(rw - pad_x - 60, maxf(e.cur - ROW_MIN - 10, 0))
			free_edit.visible = show_tools
			if is_instance_valid(expand_btn):
				expand_btn.position = Vector2(rw - 332.0, 16.0); expand_btn.size = Vector2(126.0, 42.0)
				expand_btn.visible = show_tools
			if is_instance_valid(portrait_btn):
				portrait_btn.position = Vector2(rw - 198.0, 16.0); portrait_btn.size = Vector2(138.0, 42.0)
				portrait_btn.visible = show_tools
		y += e.cur + gap
	if is_instance_valid(confirm):
		var ch := maxf(total - HEAD_H, 280.0)
		confirm.position = Vector2(rw + 22, total - ch); confirm.size = Vector2(CONFIRM_W, ch)

func _tap(i: int) -> void:
	if readonly or i < 0: return
	if expanded == i and rows[i].kind == "choice":
		expanded = -1; UiHub.sfx("collapse")
	else:
		expanded = i; UiHub.sfx("expand", 1.0 + i * 0.05)
	UiHub.haptic(8)
	select(i)

func select(i: int) -> void:
	selected = i
	for k in range(rows.size()):
		var r: Row = rows[k].node
		r.on = k == selected; r.open = k == expanded
		_spin(r, 1.0 if r.open else 0.0)
		r.queue_redraw()
	if expanded == i and not UiHub.reduced_motion:
		var lbl: Label = rows[i].label
		lbl.modulate.a = 0.0
		lbl.create_tween().tween_property(lbl, "modulate:a", 1.0, 0.35).set_delay(0.08)
	if rows[i].kind == "free" and expanded == i and is_instance_valid(free_edit):
		if not OS.has_feature("mobile"):
			free_edit.call_deferred("grab_focus")
	_remeasure(); _refresh_confirm()

func _find_ui_root() -> Node:
	var n: Node = self
	while n != null:
		if n.get("overlay_layer") != null and n.get("logical") != null:
			return n
		n = n.get_parent()
	return null

func open_composer(portrait_mode := false) -> void:
	if readonly or not is_instance_valid(free_edit): return
	close_composer(true)
	var host := _find_ui_root()
	var layer: Node = host.overlay_layer if host != null and is_instance_valid(host.overlay_layer) else get_parent()
	var UiOverlayCls := preload("res://scripts/ui/ui_overlay.gd")
	composer_overlay = UiOverlayCls.open_text_composer(layer, {
		"title": "手机竖屏输入（确认后填回）" if portrait_mode else "自由输入 · 悬浮大窗（随时可修改）",
		"tip": "先在这里舒舒服服写下长段行动或对话；点右下角「确认并填入」后会自动写回行动输入框，发送前仍可继续微调。",
		"placeholder": "请在此输入想说的话或做出的行动…",
		"text": free_edit.text,
		"portrait_mode": portrait_mode,
	}, func(val: String) -> void:
		if is_instance_valid(self):
			apply_composer_text(val)
		elif host != null and host.has_method("current"):
			var cur_s: Node = host.current()
			if cur_s != null:
				if "draft_action_text" in cur_s: cur_s.set("draft_action_text", val)
				var cur_p: Node = cur_s.get("panel")
				if is_instance_valid(cur_p) and cur_p.has_method("apply_composer_text"):
					cur_p.apply_composer_text(val)
	, func() -> void:
		if is_instance_valid(self): composer_overlay = null
	)

func apply_composer_text(val: String) -> void:
	var target_panel: Node = self
	var host := _find_ui_root()
	if not is_instance_valid(free_edit) and host != null and host.has_method("current"):
		var cur_scr: Node = host.current()
		if cur_scr != null and cur_scr.get("panel") != null and is_instance_valid(cur_scr.get("panel")):
			target_panel = cur_scr.get("panel")
	if target_panel != null and target_panel.get("free_edit") != null and is_instance_valid(target_panel.get("free_edit")):
		target_panel.set("_suppress_auto_portrait", true)
		target_panel.get("free_edit").text = val
		target_panel.emit_signal("draft_changed", val)
		var rws: Array = target_panel.get("rows")
		if not rws.is_empty():
			var fidx := rws.size() - 1
			if rws[fidx].kind == "free":
				target_panel.set("expanded", fidx)
				target_panel.call("select", fidx)
		target_panel.call("_refresh_confirm")
	elif host != null and host.has_method("current"):
		var cur_scr: Node = host.current()
		if cur_scr != null and "draft_action_text" in cur_scr:
			cur_scr.set("draft_action_text", val)
	close_composer(false)
	UiHub.sfx("confirm")

func close_composer(silent := false) -> void:
	var was_open := is_instance_valid(composer_overlay)
	if was_open:
		composer_overlay.queue_free()
	composer_overlay = null
	if UiHub.mobile_portrait_input:
		UiHub.set_mobile_portrait(false)
	if was_open and not silent:
		UiHub.sfx("collapse")

func _spin(r: Row, to: float) -> void:
	if UiHub.reduced_motion: r.spin = to; r.queue_redraw(); return
	var t := r.create_tween(); t.tween_method(func(v): r.spin = v; r.queue_redraw(), r.spin, to, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _valid() -> bool:
	if selected < 0: return false
	if rows[selected].kind == "free": return is_instance_valid(free_edit) and free_edit.text.strip_edges() != ""
	return true

func _refresh_confirm() -> void:
	if not is_instance_valid(confirm): return
	var ok := _valid()
	if ok == confirm.disabled:
		confirm.set_ready(ok)
		if ok: UiHub.sfx("ready")
	confirm.pulse = ok
	if selected < 0: confirm.hint = "请先选择"
	elif rows[selected].kind == "free": confirm.hint = "自由输入" if ok else "请输入内容"
	else: confirm.hint = "选项 " + String.chr(65 + selected)
	confirm.queue_redraw()

func _confirm() -> void:
	if not _valid(): return
	if before_confirm.is_valid() and not before_confirm.call(): return
	var e: Dictionary = rows[selected]
	var value: String = free_edit.text.strip_edges() if e.kind == "free" else e.text
	confirmed.emit(e.kind, e.index, value)
	UiHub.sfx("send"); UiHub.haptic(20)
	if is_instance_valid(confirm): confirm.launch()
	leave()

func leave() -> void:
	if UiHub.reduced_motion:
		closed.emit(); queue_free(); return
	set_process(false)
	var t := create_tween().set_parallel(true)
	for i in range(rows.size()):
		var r: Control = rows[i].node
		var keep := i == selected
		t.tween_property(r, "position:x", r.position.x + (0.0 if keep else 60.0), 0.28).set_delay(0.0 if not keep else 0.12)
		t.tween_property(r, "modulate:a", 0.0, 0.25).set_delay(0.0 if not keep else 0.18)
	if is_instance_valid(confirm): t.tween_property(confirm, "modulate:a", 0.0, 0.2).set_delay(0.32)
	t.tween_property(head, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(func(): closed.emit(); queue_free())

func _enter() -> void:
	if UiHub.reduced_motion: return
	var items: Array = [head]
	for e in rows: items.append(e.node)
	for i in range(items.size()):
		var n: Control = items[i]
		var x := n.position.x
		n.modulate.a = 0.0; n.position.x = x + 70.0
		var t := n.create_tween().set_parallel(true)
		t.tween_property(n, "modulate:a", 1.0, 0.3).set_delay(0.05 * i)
		t.tween_property(n, "position:x", x, 0.45).set_delay(0.05 * i).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if is_instance_valid(confirm):
		var cy := confirm.position.y
		confirm.modulate.a = 0.0; confirm.position.y = cy + 60.0
		var t2 := confirm.create_tween().set_parallel(true)
		t2.tween_property(confirm, "modulate:a", 1.0, 0.3).set_delay(0.16)
		t2.tween_property(confirm, "position:y", cy, 0.5).set_delay(0.16).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

## Keyboard: up/down moves and opens, Enter sends (when not typing in the free field).
func _unhandled_key_input(e: InputEvent) -> void:
	if readonly or not e.pressed: return
	if is_instance_valid(free_edit) and free_edit.has_focus():
		if e is InputEventKey and e.keycode == KEY_ENTER and e.ctrl_pressed:
			_confirm(); get_viewport().set_input_as_handled()
		return
	if e.is_action("ui_down"):
		expanded = (selected + 1) % rows.size(); select(expanded); get_viewport().set_input_as_handled()
	elif e.is_action("ui_up"):
		expanded = (selected - 1 + rows.size()) % rows.size(); select(expanded); get_viewport().set_input_as_handled()
	elif e.is_action("ui_accept") and _valid():
		_confirm(); get_viewport().set_input_as_handled()
