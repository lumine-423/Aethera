extends "res://scripts/ui/ui_screen.gd"
## 世界地图: original card base map + place labels (1600×900 frame), every region kept. Shows where
## the player is (主角组.当前地点) and lets the player pin their own notes (user://map_notes.json).

const NOTES := "user://map_notes.json"
var map_rect := Rect2(60, 130, 1400, 787.5)
var map_viewport: Control
var map_img: Control

## Vector world map in the mystic style. Draws in its own rect (size = map size * zoom), so the
## screen's existing pan / zoom code moves it like the old picture. Redraws only on resize / palette.
class MapLines extends Control:
	const K = preload("res://scripts/ui/ui_kit.gd")
	static var data: Dictionary = {}
	func _ready() -> void:
		if data.is_empty():
			data = JSON.parse_string(FileAccess.get_file_as_string("res://data/map/world_lines.json"))
		UiHub.palette_changed.connect(queue_redraw)
		resized.connect(queue_redraw)
	func _layer(name: String, s: float, col: Color, w: float, dashed := false) -> void:
		for flat in data.layers.get(name, []):
			var pts := PackedVector2Array()
			for i in range(0, flat.size(), 2): pts.append(Vector2(flat[i], flat[i + 1]) * s)
			if pts.size() < 2: continue
			if dashed:
				for i in range(0, pts.size() - 1, 2): draw_line(pts[i], pts[i + 1], col, w, true)
			else:
				draw_polyline(pts, col, w, true)
	func _draw() -> void:
		var s := size.x / 1600.0
		var acc := UiHub.c("accent"); var ink := UiHub.c("ink"); var hair := UiHub.c("hair")
		draw_rect(Rect2(Vector2.ZERO, size), UiHub.c("surface", 0.6))
		# graticule: faint construction arcs and meridians
		var c := Vector2(800, 450) * s
		for i in range(4):
			draw_arc(c, (230.0 + i * 150.0) * s, 0, TAU, 96, Color(hair, 0.28), 1.0, true)
		for i in range(12):
			var a := TAU * i / 12.0
			K.line_fade(self, c + Vector2.from_angle(a) * 120.0 * s, c + Vector2.from_angle(a) * 860.0 * s, Color(hair, 0.18), 1.0, 8)
		var z := clampf(s / 0.875, 1.0, 3.5)
		_layer("river", s, Color(hair, 0.5), 0.8)
		_layer("relief", s, Color(UiHub.c("muted"), 0.55), 0.8)
		_layer("route", s, Color(acc, 0.38), 1.0, true)
		_layer("coast", s, Color(acc, 0.08), 6.0 * minf(z, 1.6))
		_layer("coast", s, Color(ink, 0.85), 1.3)
		_layer("border", s, Color(acc, 0.55), 1.2)
		# compass star (bottom-left sea)
		var cp := Vector2(120, 760) * s
		draw_arc(cp, 46 * s, 0, TAU, 48, Color(hair, 0.8), 1.0, true)
		draw_arc(cp, 58 * s, 0, TAU, 48, Color(hair, 0.45), 1.0, true)
		K.star4(self, cp, 54 * s, Color(acc, 0.85), 0.12)
		K.star4(self, cp, 30 * s, Color(ink, 0.5), 0.14, PI * 0.25)
		K.text(self, Rect2(cp + Vector2(-20, -92) * s, Vector2(40, 30) * s), "N", int(20 * s), Color(ink, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 600)

var layer: Control
var zoom_label: Label
var picked_label := -1
var picked_note := -1
var drop_mode := false
var notes: Array = []
var notes_loaded := false
var clock := 0.0
var zoom := 1.0
var pan := Vector2.ZERO
var _dragging := false
var _drag_moved := false
var _drag_start := Vector2.ZERO
var _pan_start := Vector2.ZERO

func build() -> void:
	chrome("世界地图")
	if not notes_loaded:
		notes = _load_notes()
		notes_loaded = true
	var frame := plate(Rect2(map_rect.position - Vector2(16, 16), map_rect.size + Vector2(32, 32)), {"shape": "rect", "corner": "tr", "corner_size": 22, "layered": true}, "c", 0.05)
	frame.name = "MapFrame"
	map_viewport = Control.new(); map_viewport.name = "MapViewport"; map_viewport.clip_contents = true
	put(map_viewport, map_rect, "c")
	map_viewport.mouse_filter = Control.MOUSE_FILTER_PASS
	# mystic pass: the card's own map vectors (coast / borders / routes / relief / rivers), traced into
	# data/map/world_lines.json by tools/build_mystic_map.py and drawn as hairlines on paper.
	map_img = MapLines.new(); map_img.name = "MapImage"
	map_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_viewport.add_child(map_img)
	layer = Control.new(); layer.name = "MapLayer"
	layer.position = Vector2.ZERO; layer.size = map_rect.size
	layer.draw.connect(_paint)
	layer.gui_input.connect(_map_input)
	map_viewport.add_child(layer)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.mouse_default_cursor_shape = Control.CURSOR_CROSS if drop_mode else Control.CURSOR_POINTING_HAND
	_apply_map_transform()
	var add := btn("＋ 标记" if not drop_mode else "退出落针", "pin", "chip", Rect2(60, 950, 220, 66), func(): drop_mode = not drop_mode; refresh(false), "c", -1.0, null, 20)
	add.selected = drop_mode; add.name = "AddMarker"
	text("落针模式：点击地图落点记笔记（滚轮缩放，按住拖拽平移）" if drop_mode else "滚轮缩放 · 按住拖拽 · 点地名查资料 · 点“＋标记”落针", Rect2(292, 950, 704, 66), 18, "muted", 600)
	var z_out := btn("－", "", "chip", Rect2(1008, 950, 80, 66), func(): _zoom_at(zoom / 1.25, map_rect.size * 0.5), "c", -1.0, null, 24)
	z_out.name = "ZoomOut"; z_out.center_text = true
	zoom_label = text("%d%%" % int(round(zoom * 100.0)), Rect2(1092, 950, 92, 66), 21, "ink", 750, "c", null, HORIZONTAL_ALIGNMENT_CENTER)
	zoom_label.name = "ZoomLabel"
	var z_in := btn("＋", "", "chip", Rect2(1188, 950, 80, 66), func(): _zoom_at(zoom * 1.25, map_rect.size * 0.5), "c", -1.0, null, 24)
	z_in.name = "ZoomIn"; z_in.center_text = true
	var z_reset := btn("重置视图", "refresh", "chip", Rect2(1278, 950, 186, 66), func(): zoom = 1.0; pan = Vector2.ZERO; _apply_map_transform(), "c", -1.0, null, 19)
	z_reset.name = "ZoomReset"
	_side()

func _clamp_pan(p: Vector2, z: float) -> Vector2:
	var min_pan := map_rect.size * (1.0 - z)
	return Vector2(clampf(p.x, min_pan.x, 0.0), clampf(p.y, min_pan.y, 0.0))

func _apply_map_transform() -> void:
	zoom = clampf(zoom, 1.0, 3.5)
	pan = _clamp_pan(pan, zoom)
	if is_instance_valid(map_img):
		map_img.position = pan
		map_img.size = map_rect.size * zoom
	if is_instance_valid(zoom_label):
		zoom_label.text = "%d%%" % int(round(zoom * 100.0))
	if is_instance_valid(layer):
		layer.queue_redraw()

func _zoom_at(new_zoom: float, pivot: Vector2) -> void:
	var target := clampf(new_zoom, 1.0, 3.5)
	if is_equal_approx(target, zoom): return
	var map_pt := (pivot - pan) / zoom
	zoom = target
	pan = _clamp_pan(pivot - map_pt * zoom, zoom)
	_apply_map_transform()

func _map_to_view(p_1600: Vector2) -> Vector2:
	return pan + p_1600 * _scale() * zoom

func _view_to_map(v_local: Vector2) -> Vector2:
	return (v_local - pan) / (_scale() * zoom)

func _process(d: float) -> void:
	if UiHub.reduced_motion or not is_instance_valid(layer): return
	clock += d; layer.queue_redraw()

func _scale() -> float: return map_rect.size.x / 1600.0

func _here() -> int:
	var place: String = Game.hero().get("当前地点", "")
	var area := place.split("·")[-1] if place != "" else ""
	var labels: Array = Data.content().map.labels
	if area == "": return -1
	for i in range(labels.size()):
		var L: Dictionary = labels[i]
		if L.t == "point" and (area in String(L.text) or area in String(L.get("sub", ""))): return i
	for i in range(labels.size()):
		if area in String(labels[i].text): return i
	return -1

func _paint() -> void:
	var labels: Array = Data.content().map.labels
	var halo := UiHub.c("surface", 0.92)
	var here := _here()
	var acc := UiHub.c("accent"); var ink := UiHub.c("ink")
	# place names fade with zoom like the card: countries far, places near
	var far := clampf((1.9 - zoom) / 0.6, 0.0, 1.0)
	var near := clampf((zoom - 1.0) / 0.5, 0.25, 1.0)
	for i in range(labels.size()):
		var L: Dictionary = labels[i]
		var p := _map_to_view(Vector2(L.x, L.y))
		var on := i == picked_label
		if L.t == "region":
			var small: bool = L.get("small", false)
			var fs := 15 if small else 30
			var a := (0.8 if small else maxf(far, 0.35)) * (1.0 if not on else 1.0)
			var col := Color(acc if on else ink, a)
			_halo_text(Rect2(p.x - 200, p.y - fs, 400, fs * 1.4), L.text, fs, col, halo, HORIZONTAL_ALIGNMENT_CENTER, 4 if not small else 1)
			if not small:
				var tw: float = Kit.text_width(String(L.text), UiHub.fs(fs), 600) + String(L.text).length() * 4
				Kit.line_fade(layer, Vector2(p.x - tw * 0.6, p.y + fs * 0.42), Vector2(p.x + tw * 0.6, p.y + fs * 0.42), Color(acc, 0.5 * a), 1.0)
		else:
			var a2 := near if not on else 1.0
			layer.draw_circle(p, 6.0 if on else 3.6, Color(acc, a2))
			layer.draw_arc(p, 9.0 if on else 6.5, 0, TAU, 20, Color(ink, 0.55 * a2), 1.0, true)
			if on: Kit.star4(layer, p + Vector2(0, -20), 7.0, acc, 0.16)
			_halo_text(Rect2(p.x + 12, p.y - 22, 300, 22), L.text, 16, Color(ink, a2), halo)
			if L.has("sub"): _halo_text(Rect2(p.x + 12, p.y - 2, 300, 18), L.sub, 12, Color(UiHub.c("muted"), a2), halo)
		if i == here:
			var ph := fmod(clock, 2.0) / 2.0
			layer.draw_arc(p, 12.0 + 18.0 * ph, 0, TAU, 40, Color(acc, 1.0 - ph), 1.4, true)
			Kit.crescent(layer, p, 16.0, clock * 1.2, clock * 1.2 + PI * 0.9, 3.0, acc)
			Kit.star4(layer, p + Vector2(0, -26), 9.0, acc, 0.15)
			_halo_text(Rect2(p.x - 60, p.y + 14, 120, 20), "你在这里", 13, acc, halo, HORIZONTAL_ALIGNMENT_CENTER)
	for j in range(notes.size()):
		var n: Dictionary = notes[j]
		var q := _map_to_view(Vector2(float(n.get("x", 800.0)), float(n.get("y", 450.0))))
		var sel := j == picked_note
		if sel:
			layer.draw_arc(q, 15.0, 0, TAU, 24, UiHub.c("accent", 0.85), 1.4, true)
		layer.draw_line(q, q + Vector2(0, -22), acc, 1.2, true)
		Kit.star4(layer, q + Vector2(0, -26), 9.0 if sel else 7.0, acc, 0.17)
		layer.draw_circle(q, 2.6, acc)
		_halo_text(Rect2(q.x + 13, q.y - 34, 260, 22), str(n.get("label", "标记")), 15 if sel else 14, acc if sel else ink, halo)

func _halo_text(r: Rect2, s: String, px: int, col: Color, halo: Color, align := HORIZONTAL_ALIGNMENT_LEFT, spacing := 0) -> void:
	for o in [Vector2(-1.5, 0), Vector2(1.5, 0), Vector2(0, -1.5), Vector2(0, 1.5)]:
		Kit.text(layer, Rect2(r.position + o, r.size), s, UiHub.fs(px), Color(halo, halo.a * col.a), align, 600, spacing)
	Kit.text(layer, r, s, UiHub.fs(px), col, align, 600, spacing)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
		_drag_moved = false

func _map_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(zoom * 1.18, e.position); layer.accept_event(); return
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(zoom / 1.18, e.position); layer.accept_event(); return
		elif e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				if drop_mode:
					var pos := _view_to_map(e.position)
					pos.x = clampf(pos.x, 16.0, 1584.0); pos.y = clampf(pos.y, 16.0, 884.0)
					notes.append({"x": snappedf(pos.x, 0.5), "y": snappedf(pos.y, 0.5), "label": "标记 %d" % (notes.size() + 1), "note": ""})
					picked_note = notes.size() - 1; picked_label = -1; drop_mode = false
					_dragging = false; _drag_moved = false
					_save_notes(); UiHub.sfx("pop"); layer.accept_event(); refresh(false); return
				var hit := _pick_at(e.position)
				if hit:
					_dragging = false
					_drag_moved = false
				else:
					_dragging = true
					_drag_moved = false
					_drag_start = e.position
					_pan_start = pan
				layer.accept_event()
			else:
				_dragging = false
				_drag_moved = false
				layer.accept_event()
	elif e is InputEventMouseMotion and _dragging:
		var delta: Vector2 = e.position - _drag_start
		if delta.length() > 4.0: _drag_moved = true
		if _drag_moved and zoom > 1.001:
			pan = _clamp_pan(_pan_start + delta, zoom)
			_apply_map_transform()
		layer.accept_event()

func _pick_at(view_pos: Vector2) -> bool:
	var pos := _view_to_map(view_pos)
	var hit_radius := 22.0 / maxf(zoom, 1.0)
	for j in range(notes.size()):
		var np := Vector2(float(notes[j].get("x", 0.0)), float(notes[j].get("y", 0.0)))
		if np.distance_to(pos) < hit_radius:
			picked_note = j; picked_label = -1; UiHub.sfx("select")
			_refresh_side()
			return true
	var labels: Array = Data.content().map.labels
	var best := -1; var dist := 42.0 / maxf(zoom * 0.75, 1.0)
	for i in range(labels.size()):
		var d := Vector2(labels[i].x, labels[i].y).distance_to(pos)
		if d < dist: dist = d; best = i
	if best >= 0:
		picked_label = best; picked_note = -1; UiHub.sfx("select")
		_refresh_side()
		return true
	return false

func _refresh_side() -> void:
	var old = find_child("MapSide", true, false)
	if old: old.free()
	_side()
	if is_instance_valid(layer): layer.queue_redraw()

func _side() -> void:
	var p := plate(Rect2(1500, 130, 390, 880), {"shape": "cut", "slant": 30, "corner": "tr", "hatch": true}, "c", 0.12)
	p.name = "MapSide"
	if picked_note >= 0 and picked_note < notes.size():
		var idx := picked_note
		var n: Dictionary = notes[idx]
		header("我的标记", Rect2(24, 20, 340, 56), 28, "c", p)
		text("标记名称", Rect2(24, 82, 340, 28), 18, "muted", 700, "c", p)
		var le := LineEdit.new(); le.text = str(n.get("label", "")); le.name = "MarkerName"; le.placeholder_text = "输入标记名称"
		le.text_changed.connect(func(t):
			if idx >= 0 and idx < notes.size():
				notes[idx]["label"] = t; _save_notes()
				if is_instance_valid(layer): layer.queue_redraw())
		put(le, Rect2(24, 114, 340, 58), "c", -1.0, p)
		text("标记备注", Rect2(24, 184, 340, 28), 18, "muted", 700, "c", p)
		var te := TextEdit.new(); te.name = "MarkerNote"; te.text = str(n.get("note", "")); te.placeholder_text = "写下地点线索、人物去向或备注…"
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.text_changed.connect(func():
			if idx >= 0 and idx < notes.size():
				notes[idx]["note"] = te.text; _save_notes())
		put(te, Rect2(24, 216, 340, 440), "c", -1.0, p)
		var del_b := btn("删除标记", "trash", "secondary", Rect2(24, 676, 340, 72), func():
			if idx >= 0 and idx < notes.size():
				notes.remove_at(idx); picked_note = -1; _save_notes(); _refresh_side(), "c", -1.0, p, 22)
		del_b.name = "DeleteMarker"
		var back_b := btn("返回位置概览", "tri_left", "chip", Rect2(24, 764, 340, 64), func(): picked_note = -1; _refresh_side(), "c", -1.0, p, 20)
		back_b.name = "CloseMarker"
		return
	if picked_label < 0:
		header("当前位置", Rect2(24, 20, 340, 56), 28, "c", p)
		text(String(Game.hero().get("当前地点", "尚未开始故事")), Rect2(24, 92, 340, 74), 25, "ink", 800, "c", p)
		text("所有地区都保留在地图上。点任意地名查看资料，或用左下角“＋标记”在地图上落针记录。", Rect2(24, 172, 340, 96), 19, "muted", 600, "c", p)
		header("我的标记 (%d)" % notes.size(), Rect2(24, 284, 340, 52), 24, "c", p)
		if notes.is_empty():
			text("还没有放置标记。点击左下角“＋标记”后再点地图任意位置即可落针。", Rect2(24, 350, 340, 90), 19, "muted", 600, "c", p)
		else:
			var mscroll := ScrollContainer.new(); p.add_child(mscroll); mscroll.position = Vector2(24, 348); mscroll.size = Vector2(342, 490)
			mscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; mscroll.name = "MarkerListScroll"
			var mcol := VBoxContainer.new(); mcol.add_theme_constant_override("separation", 10); mcol.custom_minimum_size.x = 326; mscroll.add_child(mcol)
			for j in range(notes.size()):
				var idx := j
				var item: Dictionary = notes[idx]
				var mb := Btn.new(); mb.setup(str(item.get("label", "标记 %d" % (idx + 1))), "pin", "row", 21)
				mb.custom_minimum_size = Vector2(326, 62); mb.arrow = true; mb.name = "MarkerItem_%d" % idx
				mb.pressed.connect(func():
					picked_note = idx; picked_label = -1; UiHub.sfx("select"); _refresh_side())
				mcol.add_child(mb)
		return
	var L: Dictionary = Data.content().map.labels[picked_label]
	var title := String(L.text).split("（")[0]
	header(title, Rect2(24, 20, 340, 56), 28, "c", p)
	var body := ""
	for it in Data.content().library.items:
		if it.type in ["country", "region"] and (it.title == title or it.title in title or title in it.title): body = it.body; break
	var scroll := ScrollContainer.new(); p.add_child(scroll); scroll.position = Vector2(24, 96); scroll.size = Vector2(346, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var l := Lbl.new(); l.setup(body if body != "" else "资料库里没有这一处的单独条目。", 21, "ink", 600)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 330; scroll.add_child(l)
	if body != "":
		btn("在资料库中打开", "archive", "secondary", Rect2(24, 712, 340, 68), func(): root.go("archive", {"group": "region" if L.t == "point" or L.get("small", false) else "country"}), "c", -1.0, p, 20)
	btn("返回位置概览", "tri_left", "chip", Rect2(24, 792, 340, 60), func(): picked_label = -1; _refresh_side(), "c", -1.0, p, 19)

func _load_notes() -> Array:
	if not FileAccess.file_exists(NOTES): return []
	var v = JSON.parse_string(FileAccess.get_file_as_string(NOTES))
	return v if v is Array else []

func _save_notes() -> void:
	var f := FileAccess.open(NOTES, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(notes)); f.close()
