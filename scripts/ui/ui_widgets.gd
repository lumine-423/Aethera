extends RefCounted
## Small self-drawing widgets (mystic geometry pass, 2026-11-14). Each is an inner class so
## screens preload one file. Hairlines, beads, crescents and four-point stars; no solid slabs.
const Kit = preload("res://scripts/ui/ui_kit.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")


## Value bar (HP, affinity, contribution): a hairline track, a thin accent fill with a bright bead
## at its head. Animates to new values; damage leaves a short pale trail.
class Bar extends Control:
	var value := 1.0
	var max_value := 1.0
	var shown := 1.0
	var trail := 1.0
	var role := "accent"
	var track := "line"
	var slant := 6.0
	var thickness := 0.0
	var _t: Tween
	var intro := true
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiHub.palette_changed.connect(queue_redraw)
		shown = ratio(); trail = shown
		if intro and not UiHub.reduced_motion and shown > 0.0:
			var target := shown; shown = 0.0; trail = 0.0
			_t = create_tween(); _t.tween_interval(0.25 + randf() * 0.15)
			_t.tween_method(func(x): shown = x; trail = x; queue_redraw(), 0.0, target, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	func ratio() -> float: return clampf(value / maxf(max_value, 0.0001), 0.0, 1.0)
	func set_value(v: float, animate := true) -> void:
		var old := shown
		value = v
		var target := ratio()
		if _t: _t.kill()
		if not animate or UiHub.reduced_motion or not is_inside_tree():
			shown = target; trail = target; queue_redraw(); return
		_t = create_tween()
		_t.tween_method(func(x): shown = x; queue_redraw(), old, target, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_t.tween_interval(0.25)
		_t.tween_method(func(x): trail = x; queue_redraw(), maxf(trail, old), target, 0.45)
	func _draw() -> void:
		var h := clampf(size.y if thickness <= 0.0 else thickness, 2.0, 6.0)
		var y := size.y * 0.5
		var w := size.x
		draw_line(Vector2(0, y), Vector2(w, y), UiHub.c(track, 0.95), maxf(1.0, h * 0.4), true)
		if trail > shown + 0.002:
			draw_line(Vector2(w * shown, y), Vector2(w * trail, y), UiHub.c("muted", 0.55), h, true)
		if shown > 0.001:
			var c0 := UiHub.c(role)
			draw_line(Vector2(0, y), Vector2(w * shown, y), c0, h, true)
			draw_circle(Vector2(w * shown, y), h * 0.9 + 1.0, c0)
			draw_circle(Vector2(w * shown, y), h * 0.4, UiHub.c("surface"))
		if size.x >= 80.0:
			for k in range(1, 10):
				var tx := w * k / 10.0
				draw_line(Vector2(tx, y - h - 3), Vector2(tx, y - h - 1), UiHub.c("muted", 0.4), 1.0)


## Section header: thin serif title, accent bead, hairline that draws itself out to a small star.
class Header extends Control:
	var title := ""
	var px := 28
	var line := true
	var icon_name := ""
	var grow := 1.0
	var intro := true
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiHub.palette_changed.connect(queue_redraw); UiHub.options_changed.connect(queue_redraw)
		if intro and not UiHub.reduced_motion:
			grow = 0.0
			var t := create_tween(); t.tween_interval(0.2)
			t.tween_method(func(v): grow = v; queue_redraw(), 0.0, 1.0, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	func _draw() -> void:
		var h := size.y
		var acc := UiHub.c("accent")
		draw_line(Vector2(2, h * 0.24), Vector2(2, h * 0.76), acc, 2.0, true)
		var x := 18.0
		if icon_name != "":
			Icon.paint(self, icon_name, Rect2(x, h * 0.2, h * 0.6, h * 0.6), UiHub.c("ink"), acc, UiHub.c("surface")); x += h * 0.6 + 12
		var f := UiHub.fs(px)
		var avail := maxf(40.0, size.x - x - 12.0)
		var sp := 2
		var tw := Kit.font(700, sp).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
		if tw > avail:
			sp = 0
			tw = Kit.font(700, 0).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
			while f > 14 and tw > avail:
				f -= 1
				tw = Kit.font(700, 0).get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
		Kit.text(self, Rect2(x, 0, avail, h), title, f, UiHub.c("ink"), HORIZONTAL_ALIGNMENT_LEFT, 700, sp)
		if line and x + tw + 30 < size.x - 40:
			var x1 := x + tw + 18; var x2 := lerpf(x1, size.x - 24, grow)
			draw_line(Vector2(x1, h * 0.55), Vector2(x2, h * 0.55), UiHub.c("line"), 1.0, true)
			draw_circle(Vector2(x1 + 6, h * 0.55), 2.2, acc)
			Kit.star4(self, Vector2(x2 + 8, h * 0.55), 6.0 * grow, Color(acc, grow), 0.18)
		draw_line(Vector2(x, h - 2), Vector2(x + minf(tw, 46.0) * grow, h - 2), acc, 1.6, true)


## Slider: hairline track, accent fill line, ring knob with a star inside. Mouse, touch, arrows.
class ValueSlider extends Control:
	signal value_changed(value: float)
	var min_value := 0.0
	var max_value := 1.0
	var value := 0.5
	var step := 0.01
	var ticks := 5
	var dragging := false
	var _knob := 0.0
	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL; mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		UiHub.palette_changed.connect(queue_redraw)
		focus_entered.connect(queue_redraw); focus_exited.connect(queue_redraw)
	func ratio() -> float: return clampf((value - min_value) / maxf(max_value - min_value, 0.0001), 0.0, 1.0)
	func set_ratio(r: float) -> void:
		var v := min_value + clampf(r, 0.0, 1.0) * (max_value - min_value)
		v = snappedf(v, step)
		if is_equal_approx(v, value): return
		var notch := int(ratio() * 20.0)
		value = v; queue_redraw(); value_changed.emit(value)
		if int(ratio() * 20.0) != notch: UiHub.sfx("tick", 0.8 + ratio() * 0.7)
	func _gui_input(e: InputEvent) -> void:
		var track_x := 14.0; var track_w := size.x - 28.0
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			dragging = e.pressed
			if e.pressed: grab_focus(); UiHub.sfx("select"); set_ratio((e.position.x - track_x) / track_w)
			else: UiHub.sfx("toggle", 0.8 + ratio() * 0.5)
			accept_event()
		elif e is InputEventMouseMotion and dragging:
			set_ratio((e.position.x - track_x) / track_w); accept_event()
		elif e is InputEventScreenDrag:
			set_ratio((e.position.x - track_x) / track_w); accept_event()
		elif e.is_action_pressed("ui_left"):
			set_ratio(ratio() - 0.05); accept_event()
		elif e.is_action_pressed("ui_right"):
			set_ratio(ratio() + 0.05); accept_event()
	func _draw() -> void:
		var cy := size.y * 0.45; var x0 := 14.0; var w := size.x - 28.0
		var acc := UiHub.c("accent")
		draw_line(Vector2(x0, cy), Vector2(x0 + w, cy), UiHub.c("line"), 1.2, true)
		var fill_w := w * ratio()
		draw_line(Vector2(x0, cy), Vector2(x0 + fill_w, cy), acc, 2.4, true)
		for i in range(ticks):
			var tx := x0 + w * i / maxf(ticks - 1, 1)
			draw_line(Vector2(tx, cy + 12), Vector2(tx, cy + 17), UiHub.c("muted", 0.6), 1.0)
		var kc := Vector2(x0 + fill_w, cy)
		_knob = lerpf(_knob, 1.0 if dragging else 0.0, 0.3)
		var rr := 11.0 + 3.0 * _knob
		draw_circle(kc, rr, UiHub.c("surface"))
		draw_arc(kc, rr, 0, TAU, 32, acc, 1.4, true)
		Kit.star4(self, kc, 6.0 + 2.0 * _knob, acc, 0.2, _knob * PI * 0.25)
		if has_focus(): draw_arc(kc, rr + 6.0, 0, TAU, 32, Color(acc, 0.5), 1.0, true)
		if dragging: queue_redraw()


## Day / night switch: ☼ | ☾ inside a hairline pill whose right end sweeps off as an arc.
class ThemeSwitch extends Control:
	var _spin := {"sun": 0.0, "moon": 0.0}
	var _t: Tween
	var _hover := 0.0
	var fill_mult := 1.0
	var glass_tint := Color(0, 0, 0, 0)
	func _ready() -> void:
		custom_minimum_size = Vector2(190, 64)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_ALL
		UiHub.palette_changed.connect(queue_redraw)
		mouse_entered.connect(func(): _hover = 1.0; queue_redraw(); UiHub.sfx("hover", 1.2))
		mouse_exited.connect(func(): _hover = 0.0; queue_redraw())
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or e.is_action_pressed("ui_accept"):
			var to_night: bool = (e.position.x > size.x * 0.5) if e is InputEventMouseButton else not UiHub.night_target
			if to_night == UiHub.night_target: to_night = not UiHub.night_target
			UiHub.set_night(to_night); _turn("moon" if to_night else "sun")
			accept_event()
	func _turn(id: String) -> void:
		if UiHub.reduced_motion: return
		if _t: _t.kill()
		_t = create_tween(); _t.tween_method(func(v): _spin[id] = v; queue_redraw(), 0.0, 1.0, 0.7)
	func _draw() -> void:
		var acc := UiHub.c("accent")
		var pill := Kit.plate_poly(Rect2(Vector2.ZERO, size), size.y * 0.5, size.y * 0.5, 12)
		var sf := UiHub.c("surface", 0.85 * fill_mult)
		if glass_tint.a > 0.0: sf = Color(sf.lerp(Color(glass_tint, sf.a), glass_tint.a), sf.a)
		draw_colored_polygon(pill, sf)
		draw_polyline(Kit.closed(pill), UiHub.c("line" if _hover < 0.5 else "hair"), 1.2, true)
		Kit.arc_fade(self, Vector2(size.x - size.y * 0.5, size.y * 0.5), size.y * 0.5 + 5.0, -PI * 0.45, PI * 0.35, acc, 1.6, 20, 0.3)
		draw_line(Vector2(size.x * 0.5, size.y * 0.3), Vector2(size.x * 0.5, size.y * 0.7), UiHub.c("muted", 0.7), 1.2, true)
		for id in ["sun", "moon"]:
			var active: bool = (id == "moon") == UiHub.night_target
			var c := Vector2(size.x * (0.28 if id == "sun" else 0.72), size.y * 0.5)
			var k := size.y * 0.46 * (1.06 if active else 0.96)
			var spin: float = _spin[id]
			var ang := lerpf(-PI / 2, 0.0, Kit.curve(spin)) if spin > 0.0 and spin < 1.0 else 0.0
			draw_set_transform(c, ang)
			Icon.paint(self, id, Rect2(-Vector2(k, k) * 0.5, Vector2(k, k)), acc if active else UiHub.c("muted"), acc, UiHub.c("surface"))
			draw_set_transform(Vector2.ZERO)
			if active: draw_circle(c + Vector2(0, size.y * 0.36), 1.8, acc)
		if has_focus(): draw_polyline(Kit.closed(pill), acc, 1.4, true)


## Ambient geometry that drifts slowly: faint construction circles, long hairlines, tiny
## four-point stars that twinkle and rise like dust. Follows the pointer a little (parallax).
class Decor extends Control:
	var seed_value := 1
	var density := 1.0
	var clock := 0.0
	var items: Array = []
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiHub.palette_changed.connect(queue_redraw)
		resized.connect(_layout)
		_layout()
	func _layout() -> void:
		items.clear()
		var rng := RandomNumberGenerator.new(); rng.seed = seed_value
		var n := int(12 * density)
		for i in range(n):
			items.append({"kind": rng.randi_range(0, 3), "p": Vector2(rng.randf() * size.x, rng.randf() * size.y), "s": rng.randf_range(5, 14),
				"phase": rng.randf() * TAU, "speed": rng.randf_range(0.12, 0.32), "accent": rng.randf() < 0.4, "r": rng.randf_range(60, 240)})
		queue_redraw()
	var look := Vector2.ZERO
	var dust: Array = []
	func _process(delta: float) -> void:
		if UiHub.reduced_motion or not is_visible_in_tree(): return
		clock += delta
		var m := get_local_mouse_position()
		var target := ((m / maxf(size.x, 1.0)) - Vector2(0.5, 0.5 * size.y / maxf(size.x, 1.0))) * 2.0
		if m.x < 0 or m.y < 0 or m.x > size.x or m.y > size.y: target = Vector2.ZERO
		look = look.lerp(target.clamp(Vector2(-1, -1), Vector2(1, 1)), minf(delta * 3.0, 1.0))
		if dust.is_empty():
			var rng := RandomNumberGenerator.new(); rng.seed = seed_value * 7 + 1
			for i in range(int(26 * density)):
				dust.append({"x": rng.randf(), "y": rng.randf(), "v": rng.randf_range(0.004, 0.014), "s": rng.randf_range(2.0, 5.5), "tw": rng.randf() * TAU, "a": rng.randf() < 0.35})
		for d in dust:
			d.y -= d.v * delta
			if d.y < -0.02: d.y = 1.02; d.x = randf()
		queue_redraw()
	func _draw() -> void:
		for d in dust:
			var tw: float = 0.25 + 0.75 * absf(sin(clock * 1.1 + d.tw))
			var p := Vector2(d.x * size.x, d.y * size.y) - look * 10.0
			if d.a: Kit.star4(self, p, d.s * (0.7 + 0.3 * tw), UiHub.c("accent", 0.55 * tw), 0.16)
			else: draw_circle(p, d.s * 0.28, UiHub.c("muted", 0.35 * tw))
		for it in items:
			var depth: float = 4.0 + it.s * 0.9
			var off := Vector2(sin(clock * it.speed + it.phase) * 8.0, cos(clock * it.speed * 0.8 + it.phase) * 6.0) - look * depth
			var p: Vector2 = it.p + off
			match it.kind:
				0: Kit.arc_fade(self, p, it.r, it.phase + clock * it.speed * 0.15, it.phase + 2.2 + clock * it.speed * 0.15, UiHub.c("hair", 0.35), 1.0, 40)
				1: Kit.star4(self, p, it.s, UiHub.c("accent", 0.55) if it.accent else UiHub.c("muted", 0.35), 0.16)
				2: Kit.line_fade(self, p, p + Vector2(it.r * 0.6, -it.r * 0.6), UiHub.c("accent", 0.35) if it.accent else UiHub.c("hair", 0.45), 1.0)
				_: draw_circle(p, 2.4, UiHub.c("accent", 0.5) if it.accent else UiHub.c("muted", 0.4))


## Character art slot. The single integration point for portrait art:
## data/ui/portrait_registry.json maps character id -> {full, bust, avatar} res:// paths.
## Missing art shows a labeled placeholder silhouette, so screens never break while art is in production.
class Portrait extends Control:
	const Silhouette = preload("res://scripts/ui/portrait_silhouette.gdshader")
	static var registry: Dictionary = {}
	var character_id := ""
	var framing := ""  # home | story; other surfaces retain their existing framing
	var outfit_id := "daily"
	var expression_id := "neutral"
	var show_emotion_deco := false  # Keep assets/emotions/*.png preserved on disk, but hide floating comic stickers on story/stage portraits
	var emotion_texture: Texture2D
	var silhouette := false
	var always_show := true     # default visible for all characters; never hide integrated art behind silhouettes
	var kind := "full"          # full | bust | avatar | cg | scene
	var circle_clip := false    # mask avatar/portrait inside an inscribed circle (no square corner spill)
	var texture: Texture2D
	var frame := true
	var dim := 0.0
	var _fade := 1.0
	var _old: Texture2D
	var _t: Tween
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		UiHub.palette_changed.connect(queue_redraw)
		Game.changed.connect(_on_snapshot)
		resized.connect(queue_redraw)
		if registry.is_empty() and FileAccess.file_exists("res://data/ui/portrait_registry.json"):
			registry = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/portrait_registry.json"))
		show_character(character_id, kind, false)
	static func lookup(id: String, want: String) -> String:
		if registry.is_empty() and FileAccess.file_exists("res://data/ui/portrait_registry.json"):
			registry = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/portrait_registry.json"))
		if want == "cg":
			var spec := preload("res://scripts/ui/ui_data.gd").illustration_spec(id, registry.get("cg", {}))
			return String(spec.get("res", ""))
		var entry = registry.get("characters", {}).get(id, {})
		if (not entry is Dictionary or entry.is_empty()) and id.begins_with("sil_"):
			entry = registry.get("silhouettes", {}).get(id, {})
		var path: String = entry.get(want, "") if entry is Dictionary else ""
		if path == "" and want == "bust" and entry is Dictionary: path = entry.get("full", "")
		return path if path != "" and ResourceLoader.exists(path) else ""
	## Swap art with a short cross-fade. Pass a Texture2D through set_texture() for runtime/AI media.
	func show_character(id: String, want := "", animate := true) -> void:
		character_id = id
		_sync_unlock()
		if want != "": kind = want
		var path := lookup(id, kind) if id != "" else ""
		set_texture(load(path) if path != "" else null, animate)
	## Galgame art: one whole image per expression and outfit, switched directly (user rule: no fade).
	## 差分走严格索引：只认登记过的 key（形态×视角×姿态），缺图不跨差分借图。
	func show_art(id: String, outfit := "daily", expr := "neutral") -> void:
		character_id = id; kind = "full"; outfit_id = outfit if outfit != "" else "daily"
		expression_id = expr
		var symbol: String = "" if id.begins_with("sil_") else registry.get("emotions", {}).get(expr, "")
		emotion_texture = load(symbol) if symbol != "" and ResourceLoader.exists(symbol) else null
		_sync_unlock()
		var D := preload("res://scripts/ui/ui_data.gd")
		var path := ""
		if id != "" and D.has_diff_key(id, outfit_id):
			path = D.art_path_diff(id, outfit_id, expr)
		else:
			path = D.art_path(id, outfit, expr)
		if path == "" and texture == null: set_texture(null, false); return
		if path != "": set_texture(load(path), false)
	func set_texture(tex: Texture2D, animate := true) -> void:
		_old = texture; texture = tex
		if _t: _t.kill()
		if not animate or UiHub.reduced_motion or not is_inside_tree():
			_fade = 1.0; queue_redraw(); return
		_fade = 0.0
		_t = create_tween(); _t.tween_method(func(v): _fade = v; queue_redraw(), 0.0, 1.0, 0.32)
	func _on_snapshot(part: String) -> void:
		if part == "stat": _sync_unlock()
	func _sync_unlock() -> void:
		var name: String = preload("res://scripts/ui/ui_data.gd").name_of(character_id)
		var locked: bool = not always_show and kind in ["full", "bust", "avatar"] and character_id != "" and registry.get("characters", {}).has(character_id) and Game.known().get(name, {}).is_empty()
		if locked == silhouette: return
		silhouette = locked
		if locked:
			var mask := ShaderMaterial.new(); mask.shader = Silhouette; material = mask
		else: material = null
		queue_redraw()
	## One uniform scale, measured from this outfit's head and knee. Head-size cap
	## keeps short-body art smaller than tall adults rather than enlarging its head.
	func framed_rect(tex: Texture2D) -> Rect2:
		var ts := tex.get_size()
		var char_rec: Dictionary = registry.get("characters", {}).get(character_id, {})
		if char_rec.is_empty() and character_id.begins_with("sil_"):
			char_rec = registry.get("silhouettes", {}).get(character_id, {})
		var framing_map: Dictionary = char_rec.get("framing", {})
		var marks: Dictionary = framing_map.get(outfit_id, framing_map.get(outfit_id.split("_")[0], framing_map.get("daily", {})))
		var top: float = marks.get("top", 0.015)
		var knee: float = marks.get("knee", 0.72)
		var chin: float = marks.get("chin", 0.19)
		var center: float = marks.get("center", 0.5)
		var height: float
		var y: float
		if framing == "home":
			height = minf((size.y - 45.0) / (knee - top), size.y * 0.25 / (chin - top))
			y = size.y - knee * height
		else:
			# Story stage clears top toolbar (~y=94px) comfortably even for tall ahoge/hair
			height = minf((size.y - 118.0) / (knee - top), 232.0 / (chin - top))
			y = maxf(114.0 - top * height, size.y - knee * height)
		var sc := height / ts.y
		return Rect2(Vector2(size.x * 0.5 - ts.x * center * sc, y), ts * sc)
	## True when a local point lands on a visible (opaque) pixel of the current full art.
	## Used by the home room so a click on the character does not hit the furniture behind her.
	var _hit_img: Image
	var _hit_tex: Texture2D
	func opaque_at(local: Vector2) -> bool:
		if texture == null or not is_visible_in_tree() or modulate.a < 0.5: return false
		var dest := framed_rect(texture) if framing != "" and kind == "full" else Rect2(Vector2.ZERO, size)
		if not dest.has_point(local): return false
		if _hit_tex != texture:
			_hit_tex = texture; _hit_img = texture.get_image()
			if _hit_img and _hit_img.is_compressed(): _hit_img.decompress()
		if _hit_img == null: return true
		var q := Vector2i((local - dest.position) / dest.size * Vector2(_hit_img.get_size()))
		q = q.clamp(Vector2i.ZERO, _hit_img.get_size() - Vector2i.ONE)
		return _hit_img.get_pixelv(q).a > 0.4
	## Position symbols relative to the outfit's measured head, not the full canvas.
	func emotion_rect(dest: Rect2) -> Rect2:
		if emotion_texture == null: return Rect2()
		var framing_map: Dictionary = registry.get("characters", {}).get(character_id, {}).get("framing", {})
		var marks: Dictionary = framing_map.get(outfit_id, framing_map.get(outfit_id.split("_")[0], framing_map.get("daily", {})))
		var top: float = marks.get("top", 0.015)
		var chin: float = marks.get("chin", 0.19)
		var center: float = marks.get("center", 0.5)
		var h := (chin - top) * dest.size.y
		var ts := emotion_texture.get_size()
		var ds := ts * (h * 0.34 / maxf(ts.x, ts.y))
		var level: float = {"disgust": 0.40, "angry": 0.22}.get(expression_id, 0.32)
		var point := dest.position + Vector2(dest.size.x * center + h * 0.65, dest.size.y * top + h * level)
		return Rect2(Vector2(clampf(point.x - ds.x * 0.5, 2.0, size.x - ds.x - 2.0), maxf(2.0, point.y - ds.y * 0.5)), ds)
	func _cover(tex: Texture2D, alpha: float) -> void:
		var ts := tex.get_size(); var sc := maxf(size.x / ts.x, size.y / ts.y)
		if kind == "cg":
			sc = minf(size.x / ts.x, size.y / ts.y)
		elif kind in ["full"] and ts.y / ts.x > size.y / size.x:
			sc = minf(size.x / ts.x, size.y / ts.y)
		var ds := ts * sc
		var pos := Vector2((size.x - ds.x) * 0.5, 0.0 if kind in ["bust", "avatar", "card"] else (size.y - ds.y) * 0.5)
		if kind == "avatar" and character_id.begins_with("sil_") and ts.y > ts.x:
			sc = maxf(size.x * 1.45 / ts.x, size.y * 1.45 / ts.y)
			ds = ts * sc
			pos = Vector2((size.x - ds.x) * 0.5, -ds.y * 0.06)
		if kind == "full": pos.y = size.y - ds.y
		var dest := framed_rect(tex) if framing != "" and kind == "full" else Rect2(pos, ds)
		var eff_alpha := lerpf(alpha, alpha * 0.55, clampf(dim, 0.0, 1.0)) if character_id.begins_with("sil_") else alpha
		var tint := Color(1, 1, 1, eff_alpha).lerp(Color(0.5, 0.5, 0.55, eff_alpha), dim)
		if circle_clip:
			_draw_circle_textured(tex, dest, tint)
		else:
			draw_texture_rect(tex, dest, false, tint)
		if kind == "full" and show_emotion_deco and not silhouette and emotion_texture != null:
			draw_texture_rect(emotion_texture, emotion_rect(dest), false, tint)
	func _draw_circle_textured(tex: Texture2D, dest: Rect2, tint: Color) -> void:
		var center := size * 0.5
		var rad := minf(size.x, size.y) * 0.5
		if rad <= 1.0:
			return
		var segs := 80
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var dx := maxf(dest.size.x, 1.0)
		var dy := maxf(dest.size.y, 1.0)
		for i in range(segs):
			var ang := TAU * float(i) / float(segs)
			var p := center + Vector2.from_angle(ang) * rad
			pts.append(p)
			uvs.append(Vector2(
				clampf((p.x - dest.position.x) / dx, 0.0, 1.0),
				clampf((p.y - dest.position.y) / dy, 0.0, 1.0)
			))
			cols.append(tint)
		draw_polygon(pts, cols, uvs, tex)
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if silhouette and kind == "avatar":
			_placeholder(r); return
		if texture == null and (_old == null or _fade >= 1.0):
			_placeholder(r); return
		if _old and _fade < 1.0: _cover(_old, 1.0 - _fade)
		elif texture == null: _placeholder(r)
		if texture: _cover(texture, _fade)
		if frame and kind == "avatar":
			if circle_clip:
				draw_arc(size * 0.5, minf(size.x, size.y) * 0.5, 0, TAU, 80, UiHub.c("line"), 1.6, true)
			else:
				draw_rect(r, UiHub.c("line"), false, 2.0)
	func _placeholder(r: Rect2) -> void:
		var big := kind in ["full", "bust", "card", "cg", "scene"]
		if kind in ["cg", "scene"]:
			draw_rect(r, UiHub.c("surface2", 0.85))
		elif kind == "avatar" and not silhouette:
			if circle_clip:
				draw_circle(size * 0.5, minf(size.x, size.y) * 0.5, UiHub.c("surface2"))
			else:
				draw_rect(r, UiHub.c("surface2"))
		var c := Vector2(size.x * 0.5, size.y * (0.38 if kind == "avatar" else 0.34))
		var s := minf(size.x, size.y * (0.9 if kind == "avatar" else 0.55))
		if kind in ["cg", "scene"]:
			Icon.paint(self, "image", Rect2(size * 0.5 - Vector2(40, 52), Vector2(80, 80)), UiHub.c("muted", 0.7), UiHub.c("accent", 0.7), UiHub.c("surface2"))
		else:
			var tone := UiHub.c("muted", 0.28 if big else 0.6)
			draw_circle(c, s * 0.2, tone)
			var body := PackedVector2Array()
			for i in range(21): body.append(c + Vector2(0, s * 0.62) + Vector2.from_angle(PI + PI * i / 20.0) * Vector2(s * 0.42, s * 0.36))
			if circle_clip:
				var rad := minf(size.x, size.y) * 0.5
				var ctr := size * 0.5
				body.append(ctr + Vector2(minf(s * 0.42, rad * 0.68), rad * 0.72))
				body.append(ctr + Vector2(-minf(s * 0.42, rad * 0.68), rad * 0.72))
			else:
				body.append(Vector2(c.x + s * 0.42, size.y)); body.append(Vector2(c.x - s * 0.42, size.y))
			draw_colored_polygon(body, tone)
		if big and size.y >= 170:
			Kit.hatch(self, Vector2(18, size.y - 40), 6, 16, UiHub.c("muted", 0.4), 10.0)
			var label := "立绘待接入" if kind in ["full", "bust", "card"] else ("场景背景待接入" if kind == "scene" else "插画 / CG 待接入")
			Kit.text(self, Rect2(0, size.y - 78 if kind != "scene" else size.y * 0.5 + 40, size.x, 30), label, UiHub.fs(20), UiHub.c("muted"), HORIZONTAL_ALIGNMENT_CENTER, 600)
			if character_id != "":
				Kit.text(self, Rect2(0, size.y - 48 if kind != "scene" else size.y * 0.5 + 70, size.x, 26), character_id, UiHub.fs(16), UiHub.c("muted", 0.7), HORIZONTAL_ALIGNMENT_CENTER, 500)


## Burst (hits, crafting success, victory): a thin ring opens, four-point stars and beads fly out.
class Burst extends Control:
	var count := 12
	var spread := 220.0
	var role := "accent"
	var life := 0.0
	var shards: Array = []
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if UiHub.reduced_motion: queue_free(); return
		for i in range(count):
			var a := TAU * i / count + randf_range(-0.25, 0.25)
			shards.append({"dir": Vector2.from_angle(a), "dist": randf_range(0.5, 1.0) * spread, "s": randf_range(5, 13), "rot": randf() * TAU, "spin": randf_range(-4, 4), "star": i % 3 != 0})
		var t := create_tween()
		t.tween_method(func(v): life = v; queue_redraw(), 0.0, 1.0, 0.7).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_callback(queue_free)
	func _draw() -> void:
		var c := size * 0.5
		var col := UiHub.c(role)
		draw_arc(c, spread * 0.55 * life, 0, TAU, 64, Color(col, 0.7 * (1.0 - life)), 1.6, true)
		draw_arc(c, spread * 0.32 * life, 0, TAU, 48, Color(col, 0.4 * (1.0 - life)), 1.0, true)
		Kit.star4(self, c, 26.0 * (1.0 - life) + 4.0, Color(col, 1.0 - life), 0.14, life * 0.6)
		for sh in shards:
			var p: Vector2 = c + sh.dir * sh.dist * life
			var k: float = sh.s * (1.0 - life * 0.6)
			if sh.star: Kit.star4(self, p, k, Color(col, 1.0 - life), 0.18, sh.rot + sh.spin * life)
			else: draw_circle(p, k * 0.3, Color(UiHub.c("ink"), 0.8 * (1.0 - life)))


## Sliding selection cursor: a hairline pill that glides between buttons with a crescent at its left
## and a small star at its right.
class Cursor extends Control:
	const KK = preload("res://scripts/ui/ui_kit.gd")
	var slant := 24.0
	var shown := 0.0
	var _t: Tween
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE; modulate.a = 0.0
		UiHub.palette_changed.connect(queue_redraw)
	func track(buttons: Array) -> void:
		for b in buttons:
			b.mouse_entered.connect(func(): glide(b))
			b.focus_entered.connect(func(): glide(b))
	func glide(b: Control) -> void:
		if not is_instance_valid(b): return
		var r := Rect2(b.position - Vector2(12, 7), b.size + Vector2(24, 14))
		if _t: _t.kill()
		if UiHub.reduced_motion or modulate.a < 0.05:
			position = r.position; size = r.size; modulate.a = 1.0; queue_redraw(); return
		_t = create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		_t.tween_property(self, "position", r.position, 0.36)
		_t.tween_property(self, "size", r.size, 0.36)
		_t.tween_property(self, "modulate:a", 1.0, 0.15)
		_t.tween_method(func(_v): queue_redraw(), 0.0, 1.0, 0.36)
	func _draw() -> void:
		var acc := UiHub.c("accent")
		var poly := KK.plate_poly(Rect2(Vector2.ZERO, size), size.y * 0.5, minf(size.y * 0.5, 44.0), 12)
		draw_colored_polygon(poly, Color(acc, 0.05))
		draw_polyline(KK.closed(poly), Color(acc, 0.45), 1.2, true)
		KK.crescent(self, Vector2(size.y * 0.5, size.y * 0.5), size.y * 0.5, PI * 0.62, PI * 1.38, 4.0, acc)
		KK.star4(self, Vector2(-10, size.y * 0.5), 8.0, acc, 0.16)


## Slowly turning construction rings behind a headline (victory, title): concentric hairlines,
## a crescent sweep and beads on the rings.
class Rays extends Control:
	var clock := 0.0
	var rays := 14
	var role := "accent"
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE; UiHub.palette_changed.connect(queue_redraw)
	func _process(d: float) -> void:
		if UiHub.reduced_motion: return
		clock += d; queue_redraw()
	func _draw() -> void:
		var c := size * 0.5; var base := minf(size.x, size.y) * 0.46
		var col := UiHub.c(role)
		for i in range(4):
			var r := base * (0.45 + i * 0.18)
			var a := clock * (0.08 + i * 0.03) * (1 if i % 2 == 0 else -1)
			Kit.arc_fade(self, c, r, a, a + TAU * 0.78, UiHub.c("hair", 0.5 - i * 0.08), 1.0, 72, 0.12)
			draw_circle(c + Vector2.from_angle(a + TAU * 0.8) * r, 2.6, Color(col, 0.7 - i * 0.12))
		Kit.crescent(self, c, base * 0.62, clock * 0.2 - 0.9, clock * 0.2 + 0.9, 7.0, Color(col, 0.6))
		for i in range(rays):
			var a2 := TAU * i / rays + clock * 0.05
			Kit.line_fade(self, c + Vector2.from_angle(a2) * base * 0.82, c + Vector2.from_angle(a2) * base * 1.05, UiHub.c("hair", 0.4), 1.0, 6)
