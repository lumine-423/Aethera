extends Button
## Fully code-drawn button (mystic geometry pass, 2026-11-14).
## Soft pill outline in a hairline, thin serif caption, icon | divider | caption, accent bead on the
## top edge and a short accent underline under the icon. Primary calls carry a crimson/gold crescent
## emblem with a four-point star. Motion: hover lifts 3px and an accent stroke traces the outline
## while a light bead runs along it; press sinks 2px; clicks ring out with a thin circle and a star.
## Hit area follows the outline (touch friendly).

const Kit = preload("res://scripts/ui/ui_kit.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const PlateS = preload("res://scripts/ui/ui_plate.gd")
var variant := "secondary"   # primary | secondary | tab | segment | row | icon | chip | ghost | danger
var icon_name := ""
var caption := ""
var sub := ""
var selected := false: set = set_selected
var slant := 16.0
var font_px := 28
var center_text := false
var arrow := false
var divider := true
var hatch := false
var badge := ""
var stacked := false        # icon above caption (skill buttons)
var emblem := false         # force the crescent emblem (primary gets it automatically when tall)
var press_sfx := ""         # "" = pick by variant, "none" = silent (the action plays its own cue)
var hover_pitch := 1.0
var fill_mult := 1.0        # <1 = see-through glass (home page over the room picture)
var glass_tint := Color(0, 0, 0, 0)   # a > 0: pull the fill colour toward this tint (night glass over bright light)
var shake := 0.0
var reveal := 1.0: set = _set_reveal
var glow_pos := Vector2(-999, -999)
var ripple := -1.0
var ripple_pos := Vector2.ZERO
var pulse := false
var _clock := 0.0
const IDLE_STEP := 1.0 / 30.0
var _idle_acc := 0.0
var _ripple_tween: Tween
var hover := 0.0
var press := 0.0
var _hover_tween: Tween
var _press_tween: Tween

func _ready() -> void:
	flat = true; text = ""; clip_contents = false
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	UiHub.palette_changed.connect(queue_redraw)
	UiHub.options_changed.connect(queue_redraw)
	mouse_entered.connect(func(): _set_hover(true))
	mouse_exited.connect(func(): _set_hover(false))
	focus_entered.connect(func():
		_set_hover(true, false)
		if not is_hovered() and UiHub.focus_sound_ok(): UiHub.sfx("focus"))
	focus_exited.connect(func(): _set_hover(false))
	button_down.connect(func(): _set_press(true))
	button_up.connect(func(): _set_press(false))
	pressed.connect(_press_sound)
	resized.connect(queue_redraw)
	gui_input.connect(_track)

func _press_sound() -> void:
	UiHub.haptic(10 if variant != "primary" else 18)
	if press_sfx == "none": return
	var cue := press_sfx
	if cue == "":
		cue = {
			"primary": "confirm_big",
			"danger": "confirm_big",
			"tab": "tab",
			"row": "select",
			"chip": "chip",
			"ghost": "ghost",
			"icon": "icon_btn",
		}.get(variant, "confirm")
		if variant == "segment":
			cue = "toggle_off" if selected else "toggle_on"
		elif variant == "secondary":
			if icon_name in ["book", "docs", "bookmark", "archive", "log"]: cue = "paper"
			elif icon_name in ["save", "database", "upload", "download"]: cue = "save"
			elif icon_name in ["pin", "globe"]: cue = "map_open"
			elif icon_name in ["dome", "item_cube"]: cue = "bag_open"
			elif icon_name in ["person", "people"]: cue = "char_open"
			elif icon_name == "seal": cue = "recipe"
			elif icon_name == "gear": cue = "swap"
		if icon_name in ["back", "tri_left"] and caption in ["", "返回", "上一页"]:
			cue = "back" if caption in ["", "返回"] else "page"
		elif icon_name in ["next", "tri_right"] and caption in ["", "下一页"]:
			cue = "page"
		elif icon_name == "close":
			cue = "close"
		elif icon_name == "music":
			cue = "music_open"
	UiHub.sfx(cue)

func _deny() -> void:
	UiHub.sfx("deny"); UiHub.haptic(25)
	if UiHub.reduced_motion: return
	var t := create_tween()
	t.tween_method(func(v): shake = sin(v * TAU * 3.0) * 6.0 * (1.0 - v); queue_redraw(), 0.0, 1.0, 0.32)

func _set_reveal(v: float) -> void:
	reveal = v; queue_redraw()

func _track(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		glow_pos = e.position; queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and disabled:
		_deny()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not disabled:
		ripple_pos = e.position
		if UiHub.reduced_motion: return
		if _ripple_tween: _ripple_tween.kill()
		_ripple_tween = create_tween()
		_ripple_tween.tween_method(func(v): ripple = v; queue_redraw(), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_ripple_tween.tween_callback(func(): ripple = -1.0; queue_redraw())

func _process(delta: float) -> void:
	if UiHub.reduced_motion or not is_visible_in_tree(): return
	_clock += delta
	# the pulse halo / emblem star only drift slowly: 30 redraws a second look the same and cost far less
	if pulse or _has_emblem():
		_idle_acc += delta
		if _idle_acc >= IDLE_STEP:
			_idle_acc = fmod(_idle_acc, IDLE_STEP); queue_redraw()

func setup(cap: String, ic := "", kind := "secondary", px := 28) -> Button:
	caption = cap; icon_name = ic; variant = kind; font_px = px; queue_redraw(); return self

func set_selected(v: bool) -> void:
	selected = v; queue_redraw()

func _set_hover(on: bool, sweep := true) -> void:
	if disabled and on: return
	if _hover_tween: _hover_tween.kill()
	if UiHub.reduced_motion:
		hover = 1.0 if on else 0.0; queue_redraw(); return
	_hover_tween = create_tween()
	_hover_tween.tween_method(func(v): hover = v; queue_redraw(), hover, 1.0 if on else 0.0, 0.26 if on else 0.2)
	if on and sweep:
		var hcue := "hover_soft" if variant in ["tab", "row"] else ("hover_card" if variant in ["chip", "segment"] else "hover")
		UiHub.sfx(hcue, hover_pitch)

func _set_press(on: bool) -> void:
	if _press_tween: _press_tween.kill()
	if UiHub.reduced_motion:
		press = 1.0 if on else 0.0; queue_redraw(); return
	_press_tween = create_tween()
	_press_tween.tween_method(func(v): press = v; queue_redraw(), press, 1.0 if on else 0.0, 0.08 if on else 0.18)

func _round() -> Vector2:
	var h := size.y
	match variant:
		"segment": return Vector2(minf(10.0, h * 0.3), minf(10.0, h * 0.3))
		"row": return Vector2(minf(14.0, h * 0.3), minf(14.0, h * 0.3))
		"ghost": return Vector2(6, 6)
		"icon":
			return Vector2(h * 0.5, h * 0.5)
		"primary", "danger":
			return Vector2(h * 0.5, minf(h * 0.5, 64.0))
		_:
			return Vector2(h * 0.5, minf(h * 0.5, 40.0))

func outline() -> PackedVector2Array:
	var k := _round()
	return Kit.plate_poly(Rect2(Vector2.ZERO, size), k.x, k.y, 12)

func _has_point(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, outline())

func _has_emblem() -> bool:
	return (emblem or (variant in ["primary", "danger"] and size.y >= 96.0 and size.x >= 380.0 and icon_name != "")) and not stacked

func _colors() -> Dictionary:
	var on := selected
	var out := {"fill": UiHub.c("surface", 0.9), "text": UiHub.c("ink"), "icon": UiHub.c("ink"), "border": UiHub.c("line"), "hole": UiHub.c("surface"), "tint": 0.0}
	match variant:
		"primary", "danger":
			out.border = UiHub.c("accent", 0.75); out.tint = 0.035
		"tab", "row":
			if on:
				out.border = UiHub.c("accent", 0.8); out.tint = 0.07; out.text = UiHub.c("on_accent"); out.icon = UiHub.c("on_accent")
			else:
				out.fill = UiHub.c("surface" if variant == "tab" else "surface2", 0.75)
				out.border = Color(0, 0, 0, 0) if variant == "row" else UiHub.c("line", 0.8)
		"segment":
			out.fill = UiHub.c("surface", 0.9); out.border = UiHub.c("accent" if on else "line")
			if on: out.tint = 0.06; out.text = UiHub.c("on_accent")
		"ghost":
			out.fill = Color(0, 0, 0, 0); out.border = Color(0, 0, 0, 0)
		_:
			if on: out.border = UiHub.c("accent"); out.tint = 0.06
	if disabled:
		out.fill = UiHub.c("surface2", 0.6); out.text = UiHub.c("muted"); out.icon = UiHub.c("muted"); out.border = UiHub.c("line", 0.5); out.tint = 0.0
	return out

func _draw() -> void:
	if size.x < 4: return
	mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if disabled else Control.CURSOR_POINTING_HAND
	var lift := 0.0 if disabled else (-3.0 * hover + 2.0 * press)
	var sc := 1.0 - 0.02 * press
	draw_set_transform(size * 0.5 * (1.0 - sc) + Vector2(shake, lift), 0.0, Vector2(sc, sc))
	var col := _colors()
	var shape := outline()
	var k := _round()
	var acc := UiHub.c("accent")
	var show := clampf(reveal, 0.0, 1.0)
	var big := size.x > 170.0 and size.y >= 56.0
	# ghost hairline behind (叠片), drifts a little on hover
	if variant in ["primary", "secondary", "danger", "chip"] and not disabled and show > 0.4:
		var gh := PackedVector2Array()
		var drift := Vector2(5, 5) + Vector2(4, 2) * hover
		for p in shape: gh.append(p + drift)
		draw_polyline(Kit.closed(gh), UiHub.c("line", (0.45 + 0.25 * hover) * show), 1.0, true)
	# fill + tint
	var fill_rgb: Color = col.fill.lerp(Color(glass_tint, col.fill.a), glass_tint.a) if glass_tint.a > 0.0 else col.fill
	draw_colored_polygon(shape, Color(fill_rgb, col.fill.a * show * lerpf(fill_mult, 1.0, 0.35 * hover)))
	var tint: float = col.tint + (0.045 * hover if not disabled and variant != "ghost" else 0.0) + 0.05 * press
	if tint > 0.0: draw_colored_polygon(shape, Color(acc, tint * show))
	# cursor-follow glow (soft accent light inside the outline)
	if hover > 0.01 and glow_pos.x > -900 and not disabled and variant != "ghost":
		for j in range(3):
			var rr := size.y * (0.7 + j * 0.5)
			Kit.fill_all(self, Geometry2D.intersect_polygons(shape, Kit.circle_poly(glow_pos, rr, 28)), Color(acc, 0.025 * hover))
	# outline: base hairline, then calm full perimeter highlight on hover
	if col.border.a > 0.0:
		if show < 1.0:
			var head := PlateS.trace(self, shape, show, col.border, 1.2)
			draw_circle(head, 2.4, Color(acc, 1.0 - show))
		else:
			draw_polyline(Kit.closed(shape), col.border, 1.6 if selected or variant in ["primary", "danger"] else 1.2, true)
			if hover > 0.01 and not disabled and not variant in ["ghost", "row"]:
				draw_colored_polygon(shape, Color(acc.r, acc.g, acc.b, 0.045 * hover))
				draw_polyline(Kit.closed(shape), col.border.lerp(Color(acc.r, acc.g, acc.b, 0.78), hover), 1.6, true)
	if show < 0.8:
		draw_set_transform(Vector2.ZERO); return
	var a := clampf((show - 0.8) / 0.2, 0.0, 1.0)
	# bead on the top edge + underline under the icon area
	if big and variant in ["primary", "secondary", "danger", "chip"] and not disabled:
		draw_circle(Vector2(k.x + 12.0, 0), 2.6, Color(acc, a))
	# click ring + star
	if ripple >= 0.0:
		var rad := size.y * (0.3 + 1.4 * ripple)
		Kit.fill_all(self, Geometry2D.intersect_polygons(shape, Kit.circle_poly(ripple_pos, rad, 40)), Color(acc, 0.07 * (1.0 - ripple)))
		draw_arc(ripple_pos, rad, 0, TAU, 40, Color(acc, 0.5 * (1.0 - ripple)), 1.2, true)
		Kit.star4(self, ripple_pos, 10.0 * (1.0 - ripple) + 2.0, Color(acc, 0.9 * (1.0 - ripple)), 0.16, ripple * 0.8)
	if pulse and not disabled:
		var pa := 0.3 + 0.3 * sin(_clock * 3.6)
		var halo := PackedVector2Array()
		for p in shape: halo.append(p + (p - size * 0.5).normalized() * 5.0)
		draw_polyline(Kit.closed(halo), Color(acc, pa), 1.4, true)
	# selection marks
	if variant == "row" and selected:
		Kit.crescent(self, Vector2(10, size.y * 0.5), size.y * 0.32, PI * 0.6, PI * 1.4, 3.0, acc)
	if variant == "tab" and selected:
		draw_line(Vector2(size.x * 0.5 - 22, size.y - 1), Vector2(size.x * 0.5 + 22, size.y - 1), acc, 2.0, true)
		draw_circle(Vector2(k.x + 10.0, 0), 2.4, acc)
	if variant == "segment" and selected:
		Kit.star4(self, Vector2(size.x - 12, 12), 6.0, acc, 0.18)
	# content
	var narrow := size.x <= 170.0
	var pad := (clampf(size.y * 0.14, 8.0, 16.0) + k.x * 0.08) if narrow else (clampf(size.y * 0.22, 12.0, 28.0) + k.x * 0.16)
	var x := pad
	var fpx := UiHub.fs(font_px)
	var cap_w := 700 if font_px >= 30 else 600
	if stacked:
		var sk := minf(size.y * 0.42, 52.0 if size.y < 160 else 72.0)
		var th := float(fpx) * 1.4
		var top := size.y * 0.12 if size.y < 160 else (size.y - sk - 18.0 - th) * 0.5
		var ty := size.y * 0.6 if size.y < 160 else top + sk + 18.0
		Icon.paint(self, icon_name, Rect2(Vector2((size.x - sk) * 0.5, top - 2.0 * hover), Vector2(sk, sk)), col.icon, acc, col.hole)
		var fit_s := _fit_text(caption, maxf(24.0, size.x - 8.0), fpx, cap_w, 1)
		Kit.text(self, Rect2(4, ty, size.x - 8, size.y * 0.32 if size.y < 160 else th), fit_s.text, fit_s.px, col.text, HORIZONTAL_ALIGNMENT_CENTER, cap_w, fit_s.sp)
		if size.y >= 160: draw_line(Vector2(size.x * 0.5 - 18, ty + th + 12), Vector2(size.x * 0.5 + 18, ty + th + 12), Color(acc, a), 2.0, true)
	elif _has_emblem():
		# crescent emblem: thin full ring, thick crescent on the right, four-point star at the centre
		var er := size.y * 0.32
		var ec := Vector2(pad + er * 0.7, size.y * 0.5)
		var spin := 0.0 if UiHub.reduced_motion else _clock * 0.25
		draw_arc(ec, er, 0, TAU, 48, Color(acc, 0.55 * a), 1.2, true)
		Kit.crescent(self, ec + Vector2(er * 0.08, 0), er * 0.98, -PI * 0.42 + spin * 0.0, PI * 0.42, er * 0.26, Color(acc, a))
		Kit.star4(self, ec, er * 0.34 * (1.0 + 0.08 * hover), Color(acc, a), 0.17, sin(spin) * 0.12)
		Kit.line_fade(self, ec + Vector2(-er * 1.1, er * 1.1), ec + Vector2(er * 1.25, -er * 1.25), Color(acc, 0.6 * a), 1.0)
		draw_line(Vector2(ec.x - er * 0.6, size.y - 1), Vector2(ec.x + er * 0.6 + 30.0 * hover, size.y - 1), Color(acc, a), 2.2, true)
		x = ec.x + er * 1.45
		if divider:
			draw_line(Vector2(x, size.y * 0.28), Vector2(x, size.y * 0.72), Color(col.text, 0.35), 1.2, true)
			x += 24
	elif icon_name != "":
		var ik := minf(size.y * (0.38 if narrow else 0.46), 34.0 if narrow else 50.0)
		if caption == "":
			Icon.paint(self, icon_name, Rect2((size - Vector2(ik, ik)) * 0.5 + Vector2(0, -1.5 * hover), Vector2(ik, ik)), col.icon, acc, col.hole)
		else:
			var ir := Rect2(Vector2(x + 2.0 * hover, (size.y - ik) * 0.5), Vector2(ik, ik))
			Icon.paint(self, icon_name, ir, col.icon, acc, col.hole)
			if big and variant in ["primary", "secondary", "danger"]:
				draw_line(Vector2(ir.position.x - 4, size.y - 1), Vector2(ir.end.x + 4 + 18.0 * hover, size.y - 1), Color(acc, a), 2.0, true)
			x += ik + (8.0 if narrow else 14.0)
			if divider and variant in ["primary", "secondary", "danger", "chip"]:
				draw_line(Vector2(x, size.y * 0.3), Vector2(x, size.y * 0.7), Color(acc if variant == "chip" else col.text, 0.5 if variant == "chip" else 0.32), 1.2, true)
				x += (8.0 if narrow else 16.0)
	if caption != "" and not stacked:
		var badge_pad := (Kit.text_width(badge, UiHub.fs(18)) + 26.0) if (badge != "" and variant == "row") else 0.0
		var right_pad := (8.0 if narrow else pad) + (26.0 if arrow else 0.0) + badge_pad
		var area := Rect2(Vector2(x, 0), Vector2(maxf(20.0, size.x - x - right_pad), size.y))
		var align := HORIZONTAL_ALIGNMENT_CENTER if center_text else HORIZONTAL_ALIGNMENT_LEFT
		if center_text and icon_name == "": area = Rect2(Vector2(pad * 0.5, 0), Vector2(maxf(20.0, size.x - pad - badge_pad), size.y))
		var sp := 0 if narrow else (2 if fpx >= 30 else 1)
		if sub != "":
			var fit_main := _fit_text(caption, area.size.x, fpx, cap_w, sp + 2)
			var fit_sub := _fit_text(sub, area.size.x, UiHub.fs(font_px * 0.56), 500, 1)
			Kit.text(self, Rect2(area.position + Vector2(0, size.y * 0.06), Vector2(area.size.x, size.y * 0.52)), fit_main.text, fit_main.px, col.text, align, cap_w, fit_main.sp)
			Kit.text(self, Rect2(area.position + Vector2(0, size.y * 0.52), Vector2(area.size.x, size.y * 0.34)), fit_sub.text, fit_sub.px, Color(col.text, 0.72), align, 500, fit_sub.sp)
		else:
			var fit_cap := _fit_text(caption, area.size.x, fpx, cap_w, sp)
			Kit.text(self, area, fit_cap.text, fit_cap.px, col.text, align, cap_w, fit_cap.sp)
	if arrow:
		Kit.tri(self, Vector2(size.x - k.y * 0.5 - 22 + 4.0 * hover, size.y * 0.5), 9, 1, acc)
	if hatch:
		Kit.hatch(self, Vector2(size.x - k.y - 70, size.y - 16), 4, 0, Color(acc, 0.6))
	if badge != "":
		var bw := Kit.text_width(badge, UiHub.fs(18)) + 22
		var br := Rect2(Vector2(size.x - k.y * 0.4 - bw, -12), Vector2(bw, 26))
		var bp := Kit.pill(br)
		draw_colored_polygon(bp, UiHub.c("surface"))
		draw_polyline(Kit.closed(bp), acc, 1.2, true)
		Kit.text(self, br, badge, UiHub.fs(18), acc, HORIZONTAL_ALIGNMENT_CENTER, 600)
	if has_focus() and hover > 0.0 and not is_hovered():
		var ring := PackedVector2Array()
		for p in shape: ring.append(p + (p - size * 0.5).normalized() * 4.0)
		draw_polyline(Kit.closed(ring), Color(acc, 0.8), 1.4, true)
	draw_set_transform(Vector2.ZERO)

func _fit_text(txt: String, avail_w: float, px: int, weight: int, sp: int) -> Dictionary:
	var f0 := Kit.font(weight, sp)
	if f0.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= avail_w:
		return {"text": txt, "px": px, "sp": sp}
	var sp_cur := 0
	var f1 := Kit.font(weight, sp_cur)
	var w1 := f1.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	if w1 <= avail_w:
		return {"text": txt, "px": px, "sp": sp_cur}
	var px_cur := clampi(int(floor(float(px) * avail_w / maxf(w1, 1.0))), 13, px)
	while px_cur > 13 and f1.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px_cur).x > avail_w:
		px_cur -= 1
	if f1.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px_cur).x <= avail_w:
		return {"text": txt, "px": px_cur, "sp": sp_cur}
	var trimmed := txt
	while trimmed.length() > 1 and f1.get_string_size(trimmed + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, px_cur).x > avail_w:
		trimmed = trimmed.substr(0, trimmed.length() - 1)
	return {"text": trimmed + "…", "px": px_cur, "sp": sp_cur}
