extends Control
## Interactive dream room behind the home page (2026-11-17).
## The full room picture (assets/ui/home_room/room_{day,night}.webp, built by tools/build_home_room.py)
## covers the screen and stays still (only the UI floats with the pointer). Every object lives on and answers a click:
##   落地窗 window   casement leaves swing outward, white light and mist pour in, then they close
##   壁炉 fireplace  idle flicker + embers; click: a big burst of fire light that warms the room
##   星饰 star       idle twinkle; click: the star flares and spins
##   金框 panels     a light bead walks the gold line; click: a fast golden trace
##   沙发 sofa       click: squash-and-stretch bounce with soft sparkles
##   椅子 chairs     click: a wobble on the legs
##   圆桌/旧书/茶杯 table, book, cup   idle steam; click: the book hops, the cup clinks and steams
## Movable props are cut from the same room picture, so they sit pixel-exact; while one moves, its
## painted-out "under" patch fills the gap. All coordinates below are source pixels (1672x941).
## Hover: the object brightens softly and the cursor becomes a hand (no name tag, user rule 2026-11-17).

signal object_clicked(id: String)

const Kit = preload("res://scripts/ui/ui_kit.gd")
const DIR := "res://assets/ui/home_room/"
const SRC := Vector2(1672, 941)
const PROPS := {
	"sofa": Rect2(36, 500, 628, 326),
	"chair_l": Rect2(662, 560, 180, 258),
	"chair_r": Rect2(990, 558, 168, 264),
	"book": Rect2(838, 604, 98, 40),
	"cup": Rect2(934, 596, 58, 44),
}
## Object ids and their names (reference for docs/checks only; never drawn on screen).
const NAMES := {"window": "落地窗", "fireplace": "壁炉", "star": "星饰", "sofa": "沙发", "chair_l": "椅子", "chair_r": "椅子",
	"table": "圆桌", "book": "旧书", "cup": "茶杯", "panel_l": "金框", "panel_r": "金框"}
## One synthesized sound per object (tools/build_home_room_sfx.py -> assets/audio/ui/room/).
const CUES := {"fireplace": "room_fire", "star": "room_star", "sofa": "room_sofa", "chair_l": "room_chair", "chair_r": "room_chair",
	"table": "room_table", "book": "room_book", "cup": "room_cup", "panel_l": "room_panel", "panel_r": "room_panel"}
const PIVOTS := {"sofa": Vector2(350, 818), "chair_l": Vector2(748, 812), "chair_r": Vector2(1072, 818), "book": Vector2(887, 638), "cup": Vector2(962, 634)}
const DURATION := {"sofa": 0.8, "chair_l": 0.9, "chair_r": 0.9, "book": 0.75, "cup": 0.7, "fireplace": 1.9, "star": 1.2, "panel_l": 1.3, "panel_r": 1.3, "table": 0.9}
const FIRE := Vector2(726, 580)
const FIRE_BOX := Rect2(623, 448, 202, 150)
const MANTEL := Rect2(497, 338, 430, 262)
const STAR := Vector2(729, 386)
const PANELS := {"panel_l": Rect2(353, 85, 105, 557), "panel_r": Rect2(898, 127, 97, 501)}
const TABLE_POLY := [Vector2(810, 636), Vector2(850, 626), Vector2(975, 626), Vector2(1016, 638), Vector2(1000, 652), Vector2(925, 662),
	Vector2(930, 790), Vector2(995, 812), Vector2(912, 838), Vector2(838, 812), Vector2(895, 790), Vector2(900, 662), Vector2(824, 652)]
const WINDOW_POLY := [Vector2(1098, 124), Vector2(1672, -14), Vector2(1672, 714), Vector2(1098, 636)]
## Casement leaves: [hinge x, free-edge x]. Two meet on the post at 1267, one swings from the right post.
const LEAVES := [[1104.0, 1267.0], [1463.0, 1267.0], [1630.0, 1465.0]]

var room := {}
var cut := {}
var under := {}
var alpha_img := {}
var blockers: Array = []
var clock := 0.0
var hover_id := ""
var hover_k := 0.0
var _hover_tween: Tween
var tag_id := ""
var anim := {}
var win := 0.0
var win_open := false
var _win_tween: Tween
var _win_close_at := -1.0
var embers: Array = []
var motes: Array = []
var mist: Array = []
var steam: Array = []
var sparks: Array = []
var fx: Control
var sc := 1.0
var off := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for m in ["day", "night"]:
		room[m] = _tex(DIR + "room_%s.webp" % m)
		for p in PROPS:
			cut[p + "_" + m] = _tex(DIR + "%s_%s.png" % [p, m])
			under[p + "_" + m] = _tex(DIR + "%s_under_%s.webp" % [p, m])
	for p in PROPS:
		var t: Texture2D = cut.get(p + "_day")
		if t: alpha_img[p] = t.get_image()
	var rng := RandomNumberGenerator.new(); rng.seed = 1117
	for i in range(34):
		motes.append({"p": Vector2(rng.randf_range(300, 1600), rng.randf_range(60, 860)), "v": rng.randf_range(4, 12), "w": rng.randf() * TAU, "s": rng.randf_range(1.0, 2.6)})
	for i in range(14):
		embers.append(_ember(rng, false))
	fx = FxLayer.new(); fx.room_ref = self; fx.name = "RoomFx"
	add_child(fx)
	resized.connect(func(): fx.size = size)
	fx.size = size
	UiHub.palette_changed.connect(queue_redraw)
	mouse_exited.connect(func(): _set_hover(""))

func _tex(p: String) -> Texture2D:
	return load(p) if ResourceLoader.exists(p) else null

## Smooth round light (radial gradient texture, built once) - no banding rings.
static var _glow_tex: GradientTexture2D
func glow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.5 or col.a <= 0.002: return
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0)])
		_glow_tex = GradientTexture2D.new(); _glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5); _glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128; _glow_tex.height = 128
	ci.draw_texture_rect(_glow_tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)

func _ember(rng: RandomNumberGenerator, burst: bool) -> Dictionary:
	var x := rng.randf_range(FIRE_BOX.position.x + 40, FIRE_BOX.end.x - 40)
	return {"p": Vector2(x, FIRE.y + rng.randf_range(-6, 8)), "v": Vector2(rng.randf_range(-14, 14) * (3.0 if burst else 1.0), -rng.randf_range(16, 40) * (3.2 if burst else 1.0)),
		"life": rng.randf_range(0.8, 2.2), "age": rng.randf() * (0.0 if burst else 2.0), "s": rng.randf_range(0.8, 2.0), "burst": burst}

# ---------- mapping ----------
func _mode() -> String:
	return "night" if UiHub.night >= 0.5 else "day"

func _layout() -> void:
	# the room never follows the pointer (user rule 2026-11-17: only UI floats)
	sc = maxf(size.x / SRC.x, size.y / SRC.y)
	off = (size - SRC * sc) * 0.5

func to_src(p: Vector2) -> Vector2:
	return (p - off) / sc

func to_screen(p: Vector2) -> Vector2:
	return off + p * sc

# ---------- hit testing ----------
func _alpha_hit(p_src: Vector2, id: String) -> bool:
	var box: Rect2 = PROPS[id]
	if not box.has_point(p_src): return false
	var im: Image = alpha_img.get(id)
	if im == null: return true
	var q := Vector2i(p_src - box.position)
	if q.x < 0 or q.y < 0 or q.x >= im.get_width() or q.y >= im.get_height(): return false
	return im.get_pixelv(q).a > 0.35

func hit(p_screen: Vector2) -> String:
	for b in blockers:
		if b is Callable and b.is_valid() and b.call(p_screen): return ""
	var p := to_src(p_screen)
	for id in ["cup", "book", "chair_l", "chair_r"]:
		if _alpha_hit(p, id): return id
	if Geometry2D.is_point_in_polygon(p, PackedVector2Array(TABLE_POLY)): return "table"
	if _alpha_hit(p, "sofa"): return "sofa"
	if p.distance_to(STAR) < 22.0: return "star"
	if MANTEL.has_point(p): return "fireplace"
	for k in PANELS:
		if PANELS[k].grow(10).has_point(p): return k
	if Geometry2D.is_point_in_polygon(p, PackedVector2Array(WINDOW_POLY)): return "window"
	return ""

func _has_point(p: Vector2) -> bool:
	return hit(p) != ""

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_set_hover(hit(e.position))
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var id := hit(e.position)
		if id != "":
			interact(id); accept_event()

func _set_hover(id: String) -> void:
	if id == hover_id: return
	hover_id = id
	if id != "":
		tag_id = id
		UiHub.sfx("room_hover", 1.0 + randf() * 0.12)
	if _hover_tween: _hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "hover_k", 1.0 if id != "" else 0.0, 0.22 if id != "" else 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Play one object's reaction (also used by checks and touch).
func interact(id: String) -> void:
	UiHub.haptic(14)
	object_clicked.emit(id)
	if id == "window":
		_toggle_window(); return
	UiHub.sfx(CUES.get(id, "tick"))
	anim[id] = clock
	if id == "table":
		anim["book"] = clock; anim["cup"] = clock + 0.12
	if id in ["cup", "table"]:
		for i in range(6): steam.append({"p": Vector2(958 + randf_range(-6, 6), 602), "age": -i * 0.08, "life": 1.6, "w": randf() * TAU, "big": true})
	if id == "fireplace":
		var rng := RandomNumberGenerator.new(); rng.randomize()
		for i in range(42): embers.append(_ember(rng, true))
	if id in ["sofa", "book", "star", "chair_l", "chair_r"]:
		var c: Vector2 = STAR if id == "star" else PROPS[id].get_center() + Vector2(0, -PROPS[id].size.y * 0.25)
		for i in range(10 if id == "star" else 7):
			var a := randf() * TAU
			sparks.append({"p": c, "v": Vector2.from_angle(a) * randf_range(30, 90) + Vector2(0, -30), "age": 0.0, "life": randf_range(0.6, 1.0), "page": id == "book"})

func _toggle_window() -> void:
	win_open = not win_open
	UiHub.sfx("room_window_open" if win_open else "room_window_close")
	if _win_tween: _win_tween.kill()
	if UiHub.reduced_motion:
		win = 1.0 if win_open else 0.0
	else:
		_win_tween = create_tween()
		if win_open:
			_win_tween.tween_property(self, "win", 1.0, 1.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		else:
			_win_tween.tween_property(self, "win", 0.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_win_close_at = clock + 4.2 if win_open else -1.0
	if win_open:
		for i in range(16):
			mist.append({"p": Vector2(randf_range(1120, 1600), randf_range(180, 640)), "v": Vector2(-randf_range(30, 90), randf_range(-6, 10)), "age": -randf() * 0.8, "life": randf_range(2.6, 4.0), "r": randf_range(50, 120)})

func _k(id: String) -> float:
	## seconds since this object's reaction began, or -1 when idle
	if not anim.has(id): return -1.0
	var t: float = clock - anim[id]
	if t > float(DURATION.get(id, 1.0)): anim.erase(id); return -1.0
	return maxf(t, 0.0) if t >= 0.0 else -1.0

# ---------- frame ----------
## Idle life (fire flicker, motes, steam) is slow, so at rest the room updates 60 times a second at
## most; while something reacts (click, window, hover fade) it runs every frame. Keeps the UI float
## smooth on high-refresh screens without the room eating the frame.
const IDLE_STEP := 1.0 / 60.0
var _acc := 0.0
func _busy() -> bool:
	return not anim.is_empty() or not sparks.is_empty() or not mist.is_empty() or (win > 0.002 and win < 0.998) \
		or (hover_k > 0.001 and hover_k < 0.999) or embers.any(func(e): return e.burst)

func _process(frame_d: float) -> void:
	if not is_visible_in_tree(): return
	_acc += frame_d
	if _acc < IDLE_STEP and not _busy(): return
	var d := minf(_acc, 0.1); _acc = 0.0
	clock += d
	if _win_close_at > 0.0 and clock > _win_close_at and win_open: _toggle_window()
	var still := UiHub.reduced_motion
	for e in embers:
		e.age += d
		if e.age >= 0.0 and not still:
			e.p += e.v * d; e.v.x += sin(clock * 3.0 + e.p.y * 0.05) * 6.0 * d
	embers = embers.filter(func(e): return not (e.burst and e.age > e.life))
	for e in embers:
		if e.age > e.life and not e.burst:
			var rng := RandomNumberGenerator.new(); rng.randomize()
			var n := _ember(rng, false); e.p = n.p; e.v = n.v; e.age = 0.0; e.life = n.life
	for o in motes:
		if still: break
		o.p.y -= o.v * d * 0.4; o.p.x += sin(clock * 0.3 + o.w) * 3.0 * d - o.v * d * 0.2
		if o.p.y < 40: o.p.y = 880; o.p.x = randf_range(300, 1600)
	for s in mist: s.age += d; s.p += s.v * d * (1.0 if s.age > 0 else 0.0)
	mist = mist.filter(func(s): return s.age < s.life)
	for s in sparks: s.age += d; s.p += s.v * d; s.v *= 0.94; s.v.y += 30 * d
	sparks = sparks.filter(func(s): return s.age < s.life)
	# idle steam: one wisp every ~0.5s
	if not still and fmod(clock, 0.5) < d and steam.size() < 14:
		steam.append({"p": Vector2(958 + randf_range(-4, 4), 603), "age": 0.0, "life": 2.2, "w": randf() * TAU, "big": false})
	for s in steam: s.age += d
	steam = steam.filter(func(s): return s.age < s.life)
	_layout()
	queue_redraw(); fx.queue_redraw()

func _draw() -> void:
	if size.x < 2: return
	_layout()
	var mode := _mode()
	draw_set_transform(off, 0.0, Vector2(sc, sc))
	var day_t: Texture2D = room.get("day"); var night_t: Texture2D = room.get("night")
	if day_t: draw_texture_rect(day_t, Rect2(Vector2.ZERO, SRC), false)
	if night_t and UiHub.night > 0.001: draw_texture_rect(night_t, Rect2(Vector2.ZERO, SRC), false, Color(1, 1, 1, UiHub.night))
	_draw_window(mode)
	_draw_props(mode)
	# mist pouring through the open window (normal blend, white)
	for s in mist:
		if s.age < 0: continue
		var a: float = sin(clampf(s.age / s.life, 0.0, 1.0) * PI) * 0.16
		glow(self, s.p, s.r * 1.6, Color(1, 1, 1, a * 2.2))
	# steam
	for s in steam:
		if s.age < 0: continue
		var q: float = s.age / s.life
		var a2: float = (0.32 if s.big else 0.16) * sin(q * PI)
		var pts := PackedVector2Array()
		for j in range(8):
			var yy := float(j) * (5.0 if s.big else 3.5)
			pts.append(s.p + Vector2(sin(s.w + q * 5.0 + j * 0.7) * (3.0 + j * 0.9), -q * 46.0 - yy))
		draw_polyline(pts, Color(1, 1, 1, a2), 2.2 if s.big else 1.5, true)
	draw_set_transform(Vector2.ZERO)

## Window: pure white opening behind, leaves projected as strips rotating outward.
func _draw_window(mode: String) -> void:
	if win <= 0.002: return
	var tex: Texture2D = room.get(mode)
	var hole := PackedVector2Array()
	for x in [1104.0, 1630.0]: hole.append(Vector2(x, _top(x) - 3))
	for x in [1630.0, 1104.0]: hole.append(Vector2(x, _bot(x) + 4))
	var white := Color(1, 1, 1).lerp(Color(0.95, 0.97, 1.0), UiHub.night)
	draw_colored_polygon(hole, white)
	var ang := win * deg_to_rad(78.0)
	for L in LEAVES:
		var h: float = L[0]; var f: float = L[1]
		# a fine grid keeps straight bars straight (each cell is mapped flat)
		var n := 18; var rows := 8
		for i in range(n):
			var u0 := float(i) / n; var u1 := float(i + 1) / n
			var shade := lerpf(1.0, 0.84, win) - 0.06 * win * u0
			var sc4 := PackedColorArray([Color(shade, shade, shade, 1), Color(shade, shade, shade, 1), Color(shade, shade, shade, 1), Color(shade, shade, shade, 1)])
			for r in range(rows):
				var v0 := float(r) / rows; var v1 := float(r + 1) / rows
				var q := PackedVector2Array(); var uv := PackedVector2Array()
				for corner in [[u0, v0], [u1, v0], [u1, v1], [u0, v1]]:
					var x := lerpf(h, f, corner[0])
					var y := lerpf(_top(x) - 3.0, _bot(x) + 4.0, corner[1])
					uv.append(Vector2(x, y) / SRC)
					q.append(_project(h, x, y, ang))
				draw_polygon(q, sc4, uv, tex)
	# keep the right chair in front of the swung leaves
	var c2: Texture2D = cut.get("chair_r_" + mode)
	if c2 and _k("chair_r") < 0.0: draw_texture_rect(c2, PROPS.chair_r, false)

func _top(x: float) -> float:
	return 105.0 - 0.26 * (x - 1200.0)

func _bot(x: float) -> float:
	return 642.0 + 0.095 * (x - 1200.0)

func _project(h: float, x: float, y: float, ang: float) -> Vector2:
	# outward swing: the free edge folds toward the hinge and recedes (gets shorter), staying in the frame
	var dx := x - h
	var depth := absf(dx) * sin(ang)
	var s := 700.0 / (700.0 + depth)
	var yc := (_top(h) + _bot(h)) * 0.5
	return Vector2(h + dx * cos(ang), yc + (y - yc) * s)

func _draw_props(mode: String) -> void:
	for id in ["sofa", "chair_l", "chair_r", "book", "cup"]:
		var t := _k(id)
		if t < 0.0: continue
		var box: Rect2 = PROPS[id]
		var u: Texture2D = under.get(id + "_" + mode); var c: Texture2D = cut.get(id + "_" + mode)
		if u: draw_texture_rect(u, box, false)
		if c == null: continue
		var pv: Vector2 = PIVOTS[id]
		var scl := Vector2.ONE; var rot := 0.0; var lift := 0.0
		var dur: float = DURATION[id]
		var damp := exp(-5.0 * t / dur)
		if UiHub.reduced_motion: damp = 0.0
		match id:
			"sofa":
				var w := sin(t * 17.0) * damp
				scl = Vector2(1.0 + 0.035 * w, 1.0 - 0.05 * w)
			"chair_l", "chair_r":
				rot = sin(t * 22.0) * 0.045 * damp * (1.0 if id == "chair_l" else -1.0)
			"book":
				lift = absf(sin(t * TAU * 1.4)) * 9.0 * damp
				rot = sin(t * 18.0) * 0.04 * damp
			"cup":
				rot = sin(t * 30.0) * 0.07 * damp
				lift = absf(sin(t * 20.0)) * 2.0 * damp
		var xf := Transform2D(rot, scl, 0.0, pv + Vector2(0, -lift))
		draw_set_transform_matrix(Transform2D(0.0, Vector2(sc, sc), 0.0, off) * xf)
		draw_texture_rect(c, Rect2(box.position - pv, box.size), false)
		draw_set_transform(off, 0.0, Vector2(sc, sc))


## Additive light: fire glow and tongues, embers, the star, window flood, gold traces, hover brighten.
class FxLayer extends Control:
	const K = preload("res://scripts/ui/ui_kit.gd")
	var room_ref
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
	func _draw() -> void:
		var R = room_ref
		if R == null: return
		var n := UiHub.night
		var t: float = R.clock
		var still := UiHub.reduced_motion
		draw_set_transform(R.off, 0.0, Vector2(R.sc, R.sc))
		# light rays breathing + dust in the beams
		var breath := 0.5 + 0.5 * sin(t * 0.45)
		var ray := Color(1.0, 0.86, 0.80).lerp(Color(0.55, 0.66, 0.95), n)
		for i in range(3):
			var x0 := 1110.0 - i * 150.0
			var poly := PackedVector2Array([Vector2(x0, 120 + i * 30), Vector2(x0 + 70, 100 + i * 30), Vector2(x0 - 560, 760), Vector2(x0 - 700, 760)])
			draw_colored_polygon(poly, Color(ray, (0.018 + 0.02 * breath) * (1.0 - i * 0.25) + 0.05 * R.win))
		for o in R.motes:
			var tw := 0.4 + 0.6 * absf(sin(t * 1.3 + o.w))
			draw_circle(o.p, o.s, Color(ray, 0.22 * tw))
		# window flood when open
		if R.win > 0.01:
			R.glow(self, Vector2(1390, 390), 620.0, Color(1, 1, 1, 0.30 * R.win))
			R.glow(self, Vector2(1000, 640), 900.0, Color(1, 1, 1, 0.12 * R.win))
		# fire
		var ft: float = R._k("fireplace")
		var flare := 0.0
		if ft >= 0.0: flare = sin(clampf(ft / 0.18, 0.0, 1.0) * PI * 0.5) * exp(-1.6 * maxf(ft - 0.18, 0.0))
		if still and ft >= 0.0: flare = 0.6
		var flick := 0.0 if still else (sin(t * 7.3) * 0.5 + sin(t * 11.9 + 1.3) * 0.3 + sin(t * 3.1) * 0.2)
		var fire_c := Color(1.0, 0.55, 0.22).lerp(Color(1.0, 0.62, 0.25), n)
		var glow_a := lerpf(0.16, 0.30, n) * (1.0 + 0.22 * flick) + flare * 0.45
		R.glow(self, FIRE + Vector2(0, -8), 150.0 + flare * 160.0 + 6.0 * flick, Color(fire_c, glow_a))
		R.glow(self, FIRE + Vector2(0, -4), 60.0 + flare * 60.0, Color(1.0, 0.8, 0.5, glow_a * 0.8))
		if flare > 0.01:
			# warm light over the whole room
			R.glow(self, FIRE, 1100.0, Color(fire_c, 0.22 * flare))
		# soft flame tongues: stacked glow blobs that sway, kept inside the firebox
		for i in range(9):
			var bx := FIRE_BOX.position.x + 48.0 + i * 13.5
			var hgt := (20.0 + 9.0 * sin(t * (4.6 + i * 0.7) + i * 1.7) * (0.0 if still else 1.0)) * (1.0 + flare * 3.6)
			hgt = minf(hgt, FIRE.y - FIRE_BOX.position.y - 10.0)
			var sway := (0.0 if still else sin(t * 5.2 + i * 0.9) * 3.5) * (1.0 + flare)
			var wbase := 9.0 + flare * 7.0
			for j in range(6):
				var f := float(j) / 6.0
				var p := Vector2(bx + sway * f * f, FIRE.y + 2.0 - hgt * f)
				var col := Color(1.0, 0.86, 0.55).lerp(fire_c, f)
				R.glow(self, p, wbase * (1.6 - f * 1.1), Color(col, (0.30 + flare * 0.25) * (1.0 - f) * lerpf(0.75, 1.0, n)))
		for e in R.embers:
			if e.age < 0: continue
			var q: float = clampf(e.age / e.life, 0.0, 1.0)
			if not e.burst and e.p.y < FIRE_BOX.position.y + 8: continue
			draw_circle(e.p, e.s * (1.0 - q * 0.5), Color(1.0, 0.7, 0.3, (0.85 if e.burst else 0.6) * (1.0 - q)))
		# star ornament
		var st: float = R._k("star")
		var sk := 0.0 if st < 0.0 else sin(clampf(st / DURATION.star, 0.0, 1.0) * PI)
		var tw := 0.5 + 0.5 * sin(t * 1.7)
		var gold := Color(1.0, 0.82, 0.45)
		K.star4(self, STAR, 7.0 + 3.0 * tw * (0.0 if still else 1.0) + 26.0 * sk, Color(gold, 0.35 + 0.25 * tw + 0.4 * sk), 0.14, (st if st > 0 else 0.0) * 3.0)
		if sk > 0.0:
			draw_arc(STAR, 10.0 + 50.0 * (st / DURATION.star), 0, TAU, 40, Color(gold, 0.5 * (1.0 - st / DURATION.star)), 1.4, true)
			R.glow(self, STAR, 70.0 * sk, Color(gold, 0.35 * sk))
		# gold panels: idle bead walking the frame, click: a full fast trace
		for k in PANELS:
			var rect: Rect2 = PANELS[k]
			var per := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y), rect.position])
			var pt: float = R._k(k)
			if pt >= 0.0:
				var q := clampf(pt / 0.8, 0.0, 1.0)
				var fade := 1.0 - clampf((pt - 0.8) / 0.5, 0.0, 1.0)
				_trace(per, q, Color(gold, 0.55 * fade), 2.2)
			if not still:
				var phase := fmod(t * 0.11 + (0.5 if k == "panel_r" else 0.0), 1.0)
				draw_circle(_along(per, phase), 2.6, Color(gold, 0.55))
				draw_circle(_along(per, phase), 7.0, Color(gold, 0.10))
		# sparks (sofa / chairs / star / book pages)
		for s in R.sparks:
			var q2: float = s.age / s.life
			if s.page:
				var pr := Rect2(s.p - Vector2(3, 2), Vector2(6, 4))
				draw_rect(pr, Color(1, 0.95, 0.85, 0.5 * (1.0 - q2)))
			else:
				K.star4(self, s.p, 4.0 * (1.0 - q2) + 1.0, Color(UiHub.c("accent"), 0.6 * (1.0 - q2)), 0.16)
		# hover brighten: the prop's own cut-out drawn again in additive light
		var hid: String = R.hover_id if R.hover_id != "" else R.tag_id
		if R.hover_k > 0.01 and hid != "":
			var lift: float = 0.10 * R.hover_k * (0.8 + 0.2 * sin(t * 4.0))
			var hc := Color(lift, lift, lift, 1.0)
			if hid in PROPS and R._k(hid) < 0.0:
				var ct: Texture2D = R.cut.get(hid + "_" + R._mode())
				if ct: draw_texture_rect(ct, PROPS[hid], false, hc)
			elif hid == "window":
				draw_colored_polygon(PackedVector2Array(WINDOW_POLY), Color(1, 1, 1, 0.05 * R.hover_k))
			elif hid == "fireplace":
				draw_rect(MANTEL, Color(fire_c, 0.04 * R.hover_k))
			elif hid == "table":
				draw_colored_polygon(PackedVector2Array(TABLE_POLY), Color(1, 1, 1, 0.06 * R.hover_k))
			elif hid in PANELS:
				var rr2: Rect2 = PANELS[hid]
				draw_rect(rr2, Color(gold, 0.5 * R.hover_k), false, 1.6)
			elif hid == "star":
				R.glow(self, STAR, 40.0, Color(gold, 0.3 * R.hover_k))
		draw_set_transform(Vector2.ZERO)
	func _along(pts: PackedVector2Array, f: float) -> Vector2:
		var total := 0.0
		for i in range(pts.size() - 1): total += pts[i].distance_to(pts[i + 1])
		var want := total * f
		for i in range(pts.size() - 1):
			var d := pts[i].distance_to(pts[i + 1])
			if want <= d: return pts[i].lerp(pts[i + 1], want / maxf(d, 0.001))
			want -= d
		return pts[pts.size() - 1]
	func _trace(pts: PackedVector2Array, f: float, col: Color, w: float) -> void:
		var total := 0.0
		for i in range(pts.size() - 1): total += pts[i].distance_to(pts[i + 1])
		var want := total * f
		var line := PackedVector2Array([pts[0]])
		for i in range(pts.size() - 1):
			var d := pts[i].distance_to(pts[i + 1])
			if want <= d: line.append(pts[i].lerp(pts[i + 1], want / maxf(d, 0.001))); break
			line.append(pts[i + 1]); want -= d
		if line.size() >= 2: draw_polyline(line, col, w, true)
		draw_circle(line[line.size() - 1], 4.0, col)
