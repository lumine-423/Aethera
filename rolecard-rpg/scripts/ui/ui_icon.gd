extends Control
## Vector icon library. Every glyph is drawn from geometry in a 0..1 box, so it follows the
## day/night palette, stays sharp at any DPI and needs no bitmap per state.
## Use as a node (set `icon`) or call `paint()` from any _draw().

const Kit = preload("res://scripts/ui/ui_kit.gd")
@export var icon := "star4"
@export var role := "ink"
@export var accent_role := "accent"
@export var hole_role := "surface"
var tint := Color(0, 0, 0, 0)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiHub.palette_changed.connect(queue_redraw)

func _draw() -> void:
	var ink := tint if tint.a > 0.0 else UiHub.c(role)
	paint(self, icon, Rect2(Vector2.ZERO, size), ink, UiHub.c(accent_role), UiHub.c(hole_role))

static func _pts(o: Vector2, k: float, v: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(0, v.size(), 2): out.append(o + Vector2(v[i], v[i + 1]) * k)
	return out

static func _ell(c: Vector2, rx: float, ry: float, a0: float, a1: float, n := 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(n + 1):
		var a := lerpf(a0, a1, float(i) / n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out

static func _star(c: Vector2, outer: float, inner: float, points: int, rot := -PI / 2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(points * 2):
		var r := outer if i % 2 == 0 else inner
		out.append(c + Vector2.from_angle(rot + PI * i / points) * r)
	return out

static func _head(ci: CanvasItem, tip: Vector2, d: Vector2, s: float, color: Color) -> void:
	var n := d.normalized(); var side := Vector2(-n.y, n.x)
	ci.draw_colored_polygon(PackedVector2Array([tip + n * s, tip - n * s * 0.4 + side * s, tip - n * s * 0.4 - side * s]), color)

static func _doc(ci: CanvasItem, o: Vector2, k: float, ink: Color, w: float) -> void:
	ci.draw_polyline(Kit.closed(_pts(o, k, [0.2, 0.1, 0.58, 0.1, 0.74, 0.26, 0.74, 0.9, 0.2, 0.9])), ink, w, true)
	ci.draw_polyline(_pts(o, k, [0.58, 0.1, 0.58, 0.26, 0.74, 0.26]), ink, w * 0.8, true)

static func _person(ci: CanvasItem, c: Vector2, s: float, color: Color) -> void:
	ci.draw_circle(c + Vector2(0, -s * 0.62), s * 0.36, color)
	var body := _ell(c + Vector2(0, s * 0.62), s * 0.62, s * 0.66, PI, TAU, 16)
	ci.draw_colored_polygon(body, color)

static func paint(ci: CanvasItem, name: String, r: Rect2, ink: Color, acc: Color, hole: Color) -> void:
	var k := minf(r.size.x, r.size.y)
	var o := r.position + (r.size - Vector2(k, k)) * 0.5
	var w := 0.05 * k
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	if _mystic(ci, name, o, k, ink, acc, hole): return
	match name:
		"back":
			ci.draw_polyline(_pts(o, k, [0.64, 0.16, 0.3, 0.5, 0.64, 0.84]), ink, 0.072 * k, true)
		"next":
			ci.draw_polyline(_pts(o, k, [0.36, 0.16, 0.7, 0.5, 0.36, 0.84]), ink, 0.072 * k, true)
		"down":
			ci.draw_colored_polygon(_pts(o, k, [0.18, 0.32, 0.82, 0.32, 0.5, 0.74]), ink)
		"tri_right":
			ci.draw_colored_polygon(_pts(o, k, [0.28, 0.16, 0.8, 0.5, 0.28, 0.84]), ink)
		"tri_left":
			ci.draw_colored_polygon(_pts(o, k, [0.72, 0.16, 0.2, 0.5, 0.72, 0.84]), ink)
		"close":
			ci.draw_line(P.call(0.22, 0.22), P.call(0.78, 0.78), ink, 0.066 * k, true)
			ci.draw_line(P.call(0.78, 0.22), P.call(0.22, 0.78), ink, 0.066 * k, true)
		"sun":
			ci.draw_circle(P.call(0.5, 0.5), 0.17 * k, ink)
			for i in range(8):
				var d := Vector2.from_angle(TAU * i / 8.0)
				ci.draw_line(P.call(0.5, 0.5) + d * 0.27 * k, P.call(0.5, 0.5) + d * 0.41 * k, ink, 0.041 * k, true)
		"moon":
			var crescent := Geometry2D.clip_polygons(Kit.circle_poly(P.call(0.47, 0.53), 0.36 * k), Kit.circle_poly(P.call(0.68, 0.36), 0.3 * k))
			Kit.fill_all(ci, crescent, ink)
		"pause":
			ci.draw_rect(Rect2(P.call(0.24, 0.18), Vector2(0.17, 0.64) * k), ink)
			ci.draw_rect(Rect2(P.call(0.59, 0.18), Vector2(0.17, 0.64) * k), ink)
		"play":
			ci.draw_colored_polygon(_pts(o, k, [0.28, 0.16, 0.82, 0.5, 0.28, 0.84]), ink)
		"skip":
			ci.draw_colored_polygon(_pts(o, k, [0.1, 0.22, 0.5, 0.5, 0.1, 0.78]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.48, 0.22, 0.88, 0.5, 0.48, 0.78]), ink)
		"auto":
			ci.draw_arc(P.call(0.5, 0.5), 0.4 * k, -PI * 0.35, PI * 1.45, 32, ink, 0.039 * k, true)
			_head(ci, P.call(0.5, 0.5) + Vector2.from_angle(-PI * 0.35) * 0.4 * k, Vector2.from_angle(-PI * 0.35 + PI / 2), 0.1 * k, ink)
			ci.draw_colored_polygon(_pts(o, k, [0.4, 0.32, 0.68, 0.5, 0.4, 0.68]), ink)
		"log":
			_doc(ci, o, k, ink, w)
			for y in [0.44, 0.58, 0.72]: ci.draw_line(P.call(0.32, y), P.call(0.62, y), ink, 0.07 * k)
		"docs":
			ci.draw_colored_polygon(_pts(o, k, [0.34, 0.08, 0.84, 0.08, 0.84, 0.74, 0.34, 0.74]), Color(ink, ink.a * 0.5))
			ci.draw_colored_polygon(_pts(o, k, [0.16, 0.24, 0.6, 0.24, 0.7, 0.34, 0.7, 0.92, 0.16, 0.92]), ink)
			for y in [0.46, 0.6, 0.74]: ci.draw_line(P.call(0.26, y), P.call(0.58, y), hole, 0.06 * k)
		"gear":
			for i in range(8):
				var d := Vector2.from_angle(TAU * i / 8.0); var n := Vector2(-d.y, d.x) * 0.075 * k
				var c0: Vector2 = P.call(0.5, 0.5) + d * 0.2 * k; var c1: Vector2 = P.call(0.5, 0.5) + d * 0.43 * k
				ci.draw_colored_polygon(PackedVector2Array([c0 + n, c1 + n, c1 - n, c0 - n]), ink)
			ci.draw_circle(P.call(0.5, 0.5), 0.3 * k, ink)
			ci.draw_circle(P.call(0.5, 0.5), 0.12 * k, hole)
		"heart":
			ci.draw_circle(P.call(0.33, 0.36), 0.19 * k, ink)
			ci.draw_circle(P.call(0.67, 0.36), 0.19 * k, ink)
			ci.draw_colored_polygon(_pts(o, k, [0.15, 0.42, 0.5, 0.42, 0.85, 0.42, 0.5, 0.86]), ink)
		"swap":
			ci.draw_arc(P.call(0.5, 0.5), 0.3 * k, PI * 1.1, PI * 1.85, 16, ink, w, true)
			_head(ci, P.call(0.5, 0.5) + Vector2.from_angle(PI * 1.85) * 0.3 * k, Vector2.from_angle(PI * 1.85 + PI / 2), 0.12 * k, ink)
			ci.draw_arc(P.call(0.5, 0.5), 0.3 * k, PI * 0.1, PI * 0.85, 16, ink, w, true)
			_head(ci, P.call(0.5, 0.5) + Vector2.from_angle(PI * 0.85) * 0.3 * k, Vector2.from_angle(PI * 0.85 + PI / 2), 0.12 * k, ink)
		"refresh":
			ci.draw_arc(P.call(0.5, 0.5), 0.32 * k, -PI * 0.3, PI * 1.35, 32, ink, w * 1.1, true)
			_head(ci, P.call(0.5, 0.5) + Vector2.from_angle(-PI * 0.3) * 0.32 * k, Vector2.from_angle(-PI * 0.3 - PI / 2), 0.13 * k, ink)
		"people":
			_person(ci, P.call(0.22, 0.6), 0.16 * k, ink)
			_person(ci, P.call(0.78, 0.6), 0.16 * k, ink)
			_person(ci, P.call(0.5, 0.52), 0.22 * k, ink)
		"person":
			_person(ci, P.call(0.5, 0.52), 0.3 * k, ink)
		"pin":
			var ring := _ell(P.call(0.5, 0.84), 0.34 * k, 0.09 * k, 0.0, TAU, 28)
			ci.draw_polyline(ring, ink, 0.035 * k, true)
			ci.draw_circle(P.call(0.5, 0.36), 0.24 * k, ink)
			ci.draw_colored_polygon(_pts(o, k, [0.28, 0.44, 0.72, 0.44, 0.5, 0.82]), ink)
			ci.draw_circle(P.call(0.5, 0.36), 0.095 * k, hole)
		"home":
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.12, 0.9, 0.48, 0.78, 0.48, 0.78, 0.88, 0.22, 0.88, 0.22, 0.48, 0.1, 0.48]), ink)
			ci.draw_rect(Rect2(P.call(0.42, 0.6), Vector2(0.16, 0.28) * k), hole)
		"warn":
			ci.draw_polyline(Kit.closed(_pts(o, k, [0.5, 0.1, 0.92, 0.86, 0.08, 0.86])), ink, w, true)
			ci.draw_rect(Rect2(P.call(0.455, 0.36), Vector2(0.09, 0.27) * k), ink)
			ci.draw_rect(Rect2(P.call(0.455, 0.69), Vector2(0.09, 0.09) * k), ink)
		"warn_fill":
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.08, 0.94, 0.88, 0.06, 0.88]), ink)
			ci.draw_rect(Rect2(P.call(0.455, 0.36), Vector2(0.09, 0.27) * k), hole)
			ci.draw_rect(Rect2(P.call(0.455, 0.7), Vector2(0.09, 0.09) * k), hole)
		"send":
			ci.draw_colored_polygon(_pts(o, k, [0.08, 0.46, 0.92, 0.12, 0.62, 0.9, 0.47, 0.58]), ink)
			ci.draw_line(P.call(0.47, 0.58), P.call(0.86, 0.17), hole, 0.035 * k, true)
		"story":
			ci.draw_colored_polygon(_pts(o, k, [0.06, 0.58, 0.94, 0.08, 0.58, 0.92, 0.47, 0.62]), ink)
			ci.draw_line(P.call(0.47, 0.62), P.call(0.88, 0.14), hole, 0.035 * k, true)
			ci.draw_colored_polygon(_star(P.call(0.24, 0.82), 0.12 * k, 0.035 * k, 4), ink)
		"star4":
			ci.draw_colored_polygon(_star(P.call(0.5, 0.5), 0.44 * k, 0.12 * k, 4), ink)
		"search":
			ci.draw_arc(P.call(0.42, 0.42), 0.25 * k, 0.0, TAU, 32, ink, w, true)
			ci.draw_line(P.call(0.61, 0.61), P.call(0.88, 0.88), ink, 0.066 * k, true)
		"book":
			ci.draw_colored_polygon(_pts(o, k, [0.06, 0.2, 0.46, 0.28, 0.46, 0.88, 0.06, 0.8]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.54, 0.28, 0.94, 0.2, 0.94, 0.8, 0.54, 0.88]), ink)
		"speaker":
			ci.draw_colored_polygon(_pts(o, k, [0.1, 0.36, 0.28, 0.36, 0.52, 0.14, 0.52, 0.86, 0.28, 0.64, 0.1, 0.64]), ink)
			ci.draw_arc(P.call(0.52, 0.5), 0.18 * k, -0.85, 0.85, 12, ink, 0.039 * k, true)
			ci.draw_arc(P.call(0.52, 0.5), 0.33 * k, -0.85, 0.85, 16, ink, 0.039 * k, true)
		"mute":
			ci.draw_colored_polygon(_pts(o, k, [0.06, 0.36, 0.24, 0.36, 0.48, 0.14, 0.48, 0.86, 0.24, 0.64, 0.06, 0.64]), ink)
			ci.draw_line(P.call(0.62, 0.36), P.call(0.9, 0.64), acc, 0.044 * k, true)
			ci.draw_line(P.call(0.9, 0.36), P.call(0.62, 0.64), acc, 0.044 * k, true)
		"monitor":
			ci.draw_rect(Rect2(P.call(0.1, 0.14), Vector2(0.8, 0.54) * k), ink, false, w)
			ci.draw_rect(Rect2(P.call(0.44, 0.68), Vector2(0.12, 0.14) * k), ink)
			ci.draw_rect(Rect2(P.call(0.26, 0.8), Vector2(0.48, 0.08) * k), ink)
		"ai":
			ci.draw_colored_polygon(_pts(o, k, [0.3, 0.92, 0.3, 0.68, 0.18, 0.56, 0.16, 0.36, 0.28, 0.17, 0.5, 0.08, 0.72, 0.14, 0.84, 0.32, 0.84, 0.46, 0.92, 0.58, 0.82, 0.62, 0.82, 0.74, 0.68, 0.76, 0.66, 0.92]), ink)
			ci.draw_circle(P.call(0.5, 0.38), 0.09 * k, hole)
			ci.draw_line(P.call(0.5, 0.47), P.call(0.5, 0.62), hole, 0.04 * k)
			ci.draw_line(P.call(0.32, 0.38), P.call(0.41, 0.38), hole, 0.04 * k)
			ci.draw_line(P.call(0.59, 0.38), P.call(0.7, 0.38), hole, 0.04 * k)
		"database":
			ci.draw_rect(Rect2(P.call(0.16, 0.22), Vector2(0.68, 0.58) * k), ink)
			ci.draw_colored_polygon(_ell(P.call(0.5, 0.22), 0.34 * k, 0.11 * k, 0.0, TAU, 28), ink)
			ci.draw_colored_polygon(_ell(P.call(0.5, 0.8), 0.34 * k, 0.11 * k, 0.0, TAU, 28), ink)
			for y in [0.42, 0.62]: ci.draw_polyline(_ell(P.call(0.5, y), 0.34 * k, 0.1 * k, 0.15, PI - 0.15, 16), hole, 0.035 * k, true)
		"upload":
			ci.draw_polyline(_pts(o, k, [0.12, 0.56, 0.12, 0.88, 0.88, 0.88, 0.88, 0.56]), ink, w, true)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.08, 0.78, 0.38, 0.22, 0.38]), acc)
			ci.draw_rect(Rect2(P.call(0.43, 0.36), Vector2(0.14, 0.36) * k), acc)
		"download":
			ci.draw_polyline(_pts(o, k, [0.12, 0.56, 0.12, 0.88, 0.88, 0.88, 0.88, 0.56]), ink, w, true)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.74, 0.78, 0.44, 0.22, 0.44]), acc)
			ci.draw_rect(Rect2(P.call(0.43, 0.08), Vector2(0.14, 0.38) * k), acc)
		"restore":
			ci.draw_arc(P.call(0.52, 0.52), 0.34 * k, PI * 0.95, PI * 2.6, 36, ink, w, true)
			_head(ci, P.call(0.52, 0.52) + Vector2.from_angle(PI * 0.95) * 0.34 * k, Vector2.from_angle(PI * 0.95 - PI / 2), 0.12 * k, ink)
			ci.draw_line(P.call(0.52, 0.52), P.call(0.52, 0.32), ink, 0.07 * k)
			ci.draw_line(P.call(0.52, 0.52), P.call(0.68, 0.6), acc, 0.07 * k)
		"wifi_off":
			for rr in [0.2, 0.4, 0.6]: ci.draw_arc(P.call(0.5, 0.86), rr * k, PI * 1.25, PI * 1.75, 16, ink, w, true)
			ci.draw_circle(P.call(0.5, 0.84), 0.06 * k, ink)
			ci.draw_line(P.call(0.78, 0.12), P.call(0.3, 0.9), acc, 0.039 * k, true)
			ci.draw_line(P.call(0.68, 0.7), P.call(0.86, 0.88), acc, 0.039 * k, true)
			ci.draw_line(P.call(0.86, 0.7), P.call(0.68, 0.88), acc, 0.039 * k, true)
		"file_block":
			_doc(ci, o, k, ink, w)
			ci.draw_circle(P.call(0.7, 0.72), 0.21 * k, hole)
			ci.draw_arc(P.call(0.7, 0.72), 0.17 * k, 0.0, TAU, 24, acc, 0.044 * k, true)
			ci.draw_line(P.call(0.58, 0.84), P.call(0.82, 0.6), acc, 0.039 * k, true)
		"file_warn":
			_doc(ci, o, k, ink, w)
			for y in [0.36, 0.5]: ci.draw_line(P.call(0.3, y), P.call(0.6, y), ink, 0.06 * k)
			ci.draw_colored_polygon(_pts(o, k, [0.7, 0.5, 0.96, 0.94, 0.44, 0.94]), acc)
			ci.draw_rect(Rect2(P.call(0.68, 0.62), Vector2(0.05, 0.16) * k), hole)
			ci.draw_rect(Rect2(P.call(0.68, 0.83), Vector2(0.05, 0.05) * k), hole)
		"filter":
			ci.draw_colored_polygon(_pts(o, k, [0.1, 0.16, 0.9, 0.16, 0.58, 0.54, 0.58, 0.88, 0.42, 0.78, 0.42, 0.54]), ink)
		"sword":
			ci.draw_colored_polygon(_pts(o, k, [0.84, 0.08, 0.92, 0.16, 0.44, 0.66, 0.34, 0.56]), ink)
			ci.draw_line(P.call(0.22, 0.54), P.call(0.46, 0.78), ink, 0.05 * k, true)
			ci.draw_line(P.call(0.34, 0.66), P.call(0.12, 0.88), ink, 0.055 * k, true)
		"burst":
			var pts := _star(P.call(0.5, 0.5), 0.46 * k, 0.2 * k, 7, -PI / 2 + 0.2)
			for i in range(pts.size()):
				if i % 2 == 0: pts[i] = P.call(0.5, 0.5) + (pts[i] - P.call(0.5, 0.5)) * (0.78 if i % 4 == 0 else 1.0)
			ci.draw_colored_polygon(pts, ink)
			ci.draw_colored_polygon(_pts(o, k, [0.1, 0.1, 0.24, 0.16, 0.16, 0.26]), ink)
		"cover":
			var shield := _pts(o, k, [0.5, 0.08, 0.86, 0.2, 0.82, 0.56, 0.5, 0.92, 0.18, 0.56, 0.14, 0.2])
			ci.draw_colored_polygon(shield, ink)
			Kit.fill_all(ci, Geometry2D.intersect_polygons(shield, _pts(o, k, [0.5, 0.0, 1.0, 0.0, 1.0, 0.36, 0.5, 0.86])), acc)
		"shield":
			ci.draw_polyline(Kit.closed(_pts(o, k, [0.5, 0.08, 0.86, 0.2, 0.82, 0.56, 0.5, 0.92, 0.18, 0.56, 0.14, 0.2])), ink, w, true)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.24, 0.7, 0.31, 0.68, 0.54, 0.5, 0.76, 0.32, 0.54, 0.3, 0.31]), ink)
		"release":
			ci.draw_arc(P.call(0.5, 0.5), 0.36 * k, 0.0, TAU, 40, ink, 0.035 * k, true)
			ci.draw_colored_polygon(_star(P.call(0.5, 0.5), 0.46 * k, 0.11 * k, 4), ink)
		"comet":
			ci.draw_colored_polygon(_pts(o, k, [0.92, 0.08, 0.7, 0.5, 0.16, 0.92, 0.42, 0.42]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.66, 0.14, 0.5, 0.3, 0.12, 0.5, 0.42, 0.24]), Color(ink, ink.a * 0.6))
			ci.draw_colored_polygon(_pts(o, k, [0.86, 0.34, 0.7, 0.52, 0.5, 0.88, 0.76, 0.58]), Color(ink, ink.a * 0.6))
		"eye", "eye_off":
			var top := _ell(P.call(0.5, 0.74), 0.44 * k, 0.48 * k, PI * 7.0 / 6.0, PI * 11.0 / 6.0, 18)
			var bottom := _ell(P.call(0.5, 0.26), 0.44 * k, 0.48 * k, PI / 6.0, PI * 5.0 / 6.0, 18)
			ci.draw_colored_polygon(top + bottom.slice(1, bottom.size() - 1), ink)
			ci.draw_circle(P.call(0.5, 0.5), 0.15 * k, hole)
			ci.draw_circle(P.call(0.5, 0.5), 0.07 * k, ink)
			if name == "eye_off": ci.draw_line(P.call(0.16, 0.86), P.call(0.84, 0.14), acc, 0.044 * k, true)
		"chat":
			ci.draw_rect(Rect2(P.call(0.08, 0.14), Vector2(0.84, 0.58) * k), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.22, 0.7, 0.44, 0.7, 0.2, 0.92]), ink)
			for x in [0.3, 0.5, 0.7]: ci.draw_rect(Rect2(P.call(x - 0.05, 0.38), Vector2(0.1, 0.1) * k), hole)
		"plus":
			ci.draw_rect(Rect2(P.call(0.38, 0.12), Vector2(0.24, 0.76) * k), ink)
			ci.draw_rect(Rect2(P.call(0.12, 0.38), Vector2(0.76, 0.24) * k), ink)
		"lock", "unlock":
			var a1 := PI * 2.0 if name == "lock" else PI * 1.75
			ci.draw_arc(P.call(0.5, 0.4), 0.2 * k, PI, a1, 16, ink, 0.05 * k, true)
			ci.draw_line(P.call(0.3, 0.4), P.call(0.3, 0.48), ink, 0.09 * k)
			if name == "lock": ci.draw_line(P.call(0.7, 0.4), P.call(0.7, 0.48), ink, 0.09 * k)
			ci.draw_rect(Rect2(P.call(0.2, 0.46), Vector2(0.6, 0.44) * k), ink)
			ci.draw_circle(P.call(0.5, 0.62), 0.06 * k, hole)
			ci.draw_rect(Rect2(P.call(0.475, 0.62), Vector2(0.05, 0.14) * k), hole)
		"image":
			ci.draw_rect(Rect2(P.call(0.08, 0.16), Vector2(0.84, 0.68) * k), ink, false, w)
			ci.draw_colored_polygon(_pts(o, k, [0.16, 0.76, 0.4, 0.44, 0.56, 0.64, 0.68, 0.52, 0.84, 0.76]), ink)
			ci.draw_circle(P.call(0.7, 0.34), 0.07 * k, acc)
		"target":
			Kit.diamond(ci, P.call(0.5, 0.5), 0.4 * k, ink, 0.07 * k)
			Kit.diamond(ci, P.call(0.5, 0.5), 0.17 * k, acc)
		"save":
			ci.draw_colored_polygon(_pts(o, k, [0.12, 0.1, 0.72, 0.1, 0.9, 0.28, 0.9, 0.9, 0.12, 0.9]), ink)
			ci.draw_rect(Rect2(P.call(0.26, 0.56), Vector2(0.5, 0.26) * k), hole)
			ci.draw_rect(Rect2(P.call(0.3, 0.1), Vector2(0.34, 0.22) * k), hole)
			ci.draw_rect(Rect2(P.call(0.5, 0.14), Vector2(0.08, 0.14) * k), ink)
		"trash":
			ci.draw_line(P.call(0.14, 0.24), P.call(0.86, 0.24), ink, 0.08 * k)
			ci.draw_rect(Rect2(P.call(0.38, 0.1), Vector2(0.24, 0.1) * k), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.22, 0.32, 0.78, 0.32, 0.72, 0.9, 0.28, 0.9]), ink)
		"music":
			ci.draw_circle(P.call(0.32, 0.74), 0.14 * k, ink)
			ci.draw_rect(Rect2(P.call(0.39, 0.16), Vector2(0.08, 0.58) * k), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.47, 0.16, 0.84, 0.26, 0.84, 0.42, 0.47, 0.32]), ink)
		"mic":
			ci.draw_circle(P.call(0.5, 0.26), 0.15 * k, ink); ci.draw_circle(P.call(0.5, 0.48), 0.15 * k, ink)
			ci.draw_rect(Rect2(P.call(0.35, 0.26), Vector2(0.3, 0.22) * k), ink)
			ci.draw_arc(P.call(0.5, 0.48), 0.25 * k, 0.0, PI, 16, ink, 0.035 * k, true)
			ci.draw_line(P.call(0.5, 0.73), P.call(0.5, 0.9), ink, 0.07 * k)
		"globe":
			ci.draw_arc(P.call(0.5, 0.5), 0.38 * k, 0.0, TAU, 40, ink, 0.039 * k, true)
			ci.draw_polyline(_ell(P.call(0.5, 0.5), 0.16 * k, 0.38 * k, 0.0, TAU, 28), ink, 0.035 * k, true)
			ci.draw_line(P.call(0.12, 0.5), P.call(0.88, 0.5), ink, 0.06 * k)
		"info":
			ci.draw_circle(P.call(0.5, 0.5), 0.42 * k, ink)
			ci.draw_rect(Rect2(P.call(0.45, 0.44), Vector2(0.1, 0.3) * k), hole)
			ci.draw_rect(Rect2(P.call(0.45, 0.26), Vector2(0.1, 0.1) * k), hole)
		"power":
			ci.draw_arc(P.call(0.5, 0.54), 0.32 * k, -PI * 0.3, PI * 1.3, 32, ink, 0.055 * k, true)
			ci.draw_line(P.call(0.5, 0.1), P.call(0.5, 0.48), ink, 0.1 * k)
		"replay":
			ci.draw_arc(P.call(0.5, 0.5), 0.4 * k, 0.0, TAU, 40, ink, 0.039 * k, true)
			ci.draw_colored_polygon(_pts(o, k, [0.4, 0.3, 0.7, 0.5, 0.4, 0.7]), acc)
		"bookmark":
			ci.draw_colored_polygon(_pts(o, k, [0.24, 0.08, 0.76, 0.08, 0.76, 0.92, 0.5, 0.7, 0.24, 0.92]), ink)
		"archive":
			ci.draw_colored_polygon(_pts(o, k, [0.24, 0.94, 0.26, 0.66, 0.14, 0.52, 0.14, 0.32, 0.3, 0.14, 0.52, 0.08, 0.66, 0.12, 0.56, 0.32, 0.72, 0.42, 0.8, 0.56, 0.7, 0.62, 0.7, 0.76, 0.56, 0.78, 0.54, 0.94]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.62, 0.06, 0.94, 0.22, 0.7, 0.4]), acc)
		"battle":
			for c in [[0.5, 0.2], [0.34, 0.4], [0.66, 0.4]]: Kit.diamond(ci, P.call(c[0], c[1]), 0.11 * k, acc)
			_person(ci, P.call(0.17, 0.72), 0.14 * k, ink); _person(ci, P.call(0.83, 0.72), 0.14 * k, ink)
			_person(ci, P.call(0.5, 0.76), 0.12 * k, ink)
		"defeat":
			ci.draw_colored_polygon(_pts(o, k, [0.06, 0.58, 0.94, 0.08, 0.58, 0.92, 0.47, 0.62]), ink)
			ci.draw_polyline(_pts(o, k, [0.3, 0.2, 0.44, 0.46, 0.36, 0.56, 0.6, 0.9]), hole, 0.039 * k, true)
		"retreat":
			ci.draw_arc(P.call(0.5, 0.44), 0.26 * k, PI, TAU, 18, ink, 0.066 * k, true)
			ci.draw_line(P.call(0.76, 0.43), P.call(0.76, 0.9), ink, 0.12 * k)
			_head(ci, P.call(0.24, 0.56), Vector2.DOWN, 0.17 * k, ink)
		"energy":
			ci.draw_colored_polygon(_pts(o, k, [0.58, 0.06, 0.2, 0.56, 0.47, 0.56, 0.38, 0.94, 0.8, 0.4, 0.53, 0.4]), ink)
		"turn":
			ci.draw_line(P.call(0.16, 0.16), P.call(0.84, 0.84), ink, 0.05 * k, true)
			ci.draw_line(P.call(0.84, 0.16), P.call(0.16, 0.84), ink, 0.05 * k, true)
			ci.draw_line(P.call(0.62, 0.86), P.call(0.86, 0.62), ink, 0.08 * k); ci.draw_line(P.call(0.14, 0.62), P.call(0.38, 0.86), ink, 0.08 * k)
		"action":
			ci.draw_polyline(_pts(o, k, [0.16, 0.18, 0.46, 0.5, 0.16, 0.82]), ink, 0.066 * k, true)
			ci.draw_polyline(_pts(o, k, [0.52, 0.18, 0.82, 0.5, 0.52, 0.82]), acc, 0.066 * k, true)
		"hand":
			ci.draw_rect(Rect2(P.call(0.24, 0.48), Vector2(0.56, 0.42) * k), ink)
			for i in range(4): ci.draw_rect(Rect2(P.call(0.25 + i * 0.14, 0.16 + absf(i - 1.5) * 0.06), Vector2(0.11, 0.38) * k), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.24, 0.6, 0.06, 0.44, 0.14, 0.38, 0.3, 0.5]), ink)
		"sigil_a", "sigil_b", "sigil_c":
			var c: Vector2 = P.call(0.5, 0.5)
			if name == "sigil_a":
				Kit.diamond(ci, c, 0.44 * k, ink, 0.09 * k); Kit.diamond(ci, c, 0.16 * k, acc)
			elif name == "sigil_b":
				ci.draw_colored_polygon(_pts(o, k, [0.5, 0.06, 0.66, 0.4, 0.5, 0.32, 0.34, 0.4]), ink)
				ci.draw_colored_polygon(_pts(o, k, [0.16, 0.46, 0.46, 0.5, 0.5, 0.94, 0.2, 0.62]), ink)
				ci.draw_colored_polygon(_pts(o, k, [0.84, 0.46, 0.54, 0.5, 0.5, 0.94, 0.8, 0.62]), ink)
				Kit.diamond(ci, c + Vector2(0, -0.02 * k), 0.07 * k, acc)
			else:
				ci.draw_colored_polygon(_star(c, 0.46 * k, 0.2 * k, 4, -PI / 2), ink)
				Kit.diamond(ci, c, 0.12 * k, hole)
		"item_crystal":
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.06, 0.6, 0.34, 0.54, 0.88, 0.5, 0.88]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.06, 0.5, 0.88, 0.44, 0.88, 0.4, 0.34]), Color(ink, ink.a * 0.55))
			ci.draw_colored_polygon(_pts(o, k, [0.18, 0.36, 0.4, 0.6, 0.44, 0.88, 0.3, 0.8]), Color(ink, ink.a * 0.75))
			ci.draw_colored_polygon(_pts(o, k, [0.82, 0.3, 0.7, 0.74, 0.56, 0.88, 0.6, 0.6]), acc)
			ci.draw_colored_polygon(_pts(o, k, [0.08, 0.6, 0.3, 0.8, 0.4, 0.92, 0.2, 0.86]), Color(ink, ink.a * 0.45))
		"item_cube":
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.12, 0.86, 0.3, 0.5, 0.48, 0.14, 0.3]), Color(ink, ink.a * 0.35))
			ci.draw_colored_polygon(_pts(o, k, [0.14, 0.3, 0.5, 0.48, 0.5, 0.9, 0.14, 0.72]), Color(ink, ink.a * 0.65))
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.48, 0.86, 0.3, 0.86, 0.72, 0.5, 0.9]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.48, 0.62, 0.42, 0.62, 0.62, 0.5, 0.68]), acc)
		"item_plate":
			ci.draw_colored_polygon(_pts(o, k, [0.1, 0.42, 0.56, 0.26, 0.9, 0.4, 0.44, 0.56]), Color(ink, ink.a * 0.4))
			ci.draw_colored_polygon(_pts(o, k, [0.1, 0.42, 0.44, 0.56, 0.44, 0.64, 0.1, 0.5]), Color(ink, ink.a * 0.8))
			ci.draw_colored_polygon(_pts(o, k, [0.44, 0.56, 0.9, 0.4, 0.9, 0.48, 0.44, 0.64]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.2, 0.66, 0.54, 0.78, 0.84, 0.62, 0.54, 0.7]), acc)
		"item_ore":
			ci.draw_colored_polygon(_pts(o, k, [0.24, 0.3, 0.52, 0.14, 0.8, 0.28, 0.88, 0.58, 0.64, 0.86, 0.3, 0.82, 0.12, 0.56]), Color(ink, ink.a * 0.55))
			ci.draw_colored_polygon(_pts(o, k, [0.52, 0.14, 0.8, 0.28, 0.88, 0.58, 0.56, 0.5]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.24, 0.3, 0.52, 0.14, 0.56, 0.5, 0.3, 0.5]), Color(ink, ink.a * 0.3))
			ci.draw_colored_polygon(_pts(o, k, [0.12, 0.56, 0.3, 0.5, 0.3, 0.82]), acc)
		"item_orb":
			ci.draw_circle(P.call(0.5, 0.5), 0.3 * k, Color(ink, ink.a * 0.7))
			ci.draw_colored_polygon(_ell(P.call(0.5, 0.5), 0.3 * k, 0.3 * k, PI * 0.15, PI * 0.95, 16), ink)
			ci.draw_polyline(_ell(P.call(0.5, 0.52), 0.46 * k, 0.12 * k, 0.0, TAU, 32), ink, 0.035 * k, true)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.5, 0.74, 0.5, 0.56, 0.76]), acc)
		"item_tetra":
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.08, 0.86, 0.78, 0.5, 0.92]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.08, 0.5, 0.92, 0.14, 0.78]), Color(ink, ink.a * 0.55))
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.08, 0.86, 0.78, 0.66, 0.6]), acc)
		"item_prism":
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.06, 0.84, 0.44, 0.5, 0.94, 0.5, 0.44]), acc)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.06, 0.5, 0.44, 0.5, 0.94, 0.16, 0.44]), Color(acc, acc.a * 0.65))
			ci.draw_colored_polygon(_pts(o, k, [0.16, 0.44, 0.5, 0.44, 0.84, 0.44, 0.5, 0.56]), Color(1, 1, 1, 0.35))
		"item_shards":
			ci.draw_colored_polygon(_pts(o, k, [0.42, 0.08, 0.62, 0.46, 0.36, 0.4]), Color(ink, ink.a * 0.7))
			ci.draw_colored_polygon(_pts(o, k, [0.66, 0.2, 0.9, 0.42, 0.64, 0.5]), acc)
			ci.draw_colored_polygon(_pts(o, k, [0.12, 0.5, 0.42, 0.56, 0.28, 0.82]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.6, 0.78, 0.66, 0.58, 0.92]), Color(ink, ink.a * 0.55))
		"item_ring":
			ci.draw_arc(P.call(0.5, 0.5), 0.3 * k, 0.0, TAU, 40, ink, 0.088 * k, true)
			ci.draw_arc(P.call(0.5, 0.5), 0.3 * k, -PI * 0.45, PI * 0.05, 12, acc, 0.088 * k, true)
			ci.draw_arc(P.call(0.5, 0.5), 0.12 * k, 0.0, TAU, 24, Color(ink, ink.a * 0.5), 0.035 * k, true)
		"item_chip":
			ci.draw_colored_polygon(_pts(o, k, [0.18, 0.3, 0.7, 0.16, 0.86, 0.56, 0.34, 0.74]), ink)
			ci.draw_colored_polygon(_pts(o, k, [0.18, 0.3, 0.34, 0.74, 0.32, 0.84, 0.14, 0.4]), Color(ink, ink.a * 0.6))
			ci.draw_colored_polygon(_pts(o, k, [0.34, 0.74, 0.86, 0.56, 0.84, 0.66, 0.32, 0.84]), acc)
			for i in range(4): ci.draw_line(P.call(0.32 + i * 0.1, 0.36 - i * 0.02), P.call(0.42 + i * 0.1, 0.6 - i * 0.04), hole, 0.025 * k)
		# ---- mystic pass additions (thin line glyphs) ----
		"minus":
			ci.draw_line(P.call(0.2, 0.5), P.call(0.8, 0.5), ink, 0.06 * k, true)
		"doc":
			_doc(ci, o, k, ink, 0.05 * k)
			ci.draw_line(P.call(0.32, 0.5), P.call(0.6, 0.5), acc, 0.04 * k, true)
		"diamond":
			ci.draw_polyline(Kit.closed(_pts(o, k, [0.5, 0.08, 0.92, 0.5, 0.5, 0.92, 0.08, 0.5])), ink, 0.05 * k, true)
			ci.draw_colored_polygon(_pts(o, k, [0.5, 0.36, 0.64, 0.5, 0.5, 0.64, 0.36, 0.5]), acc)
		"seal":
			ci.draw_arc(P.call(0.5, 0.5), 0.4 * k, 0.0, TAU, 40, ink, 0.045 * k, true)
			ci.draw_polyline(Kit.closed(_pts(o, k, [0.5, 0.22, 0.78, 0.5, 0.5, 0.78, 0.22, 0.5])), ink, 0.045 * k, true)
			ci.draw_colored_polygon(_star(P.call(0.5, 0.5), 0.16 * k, 0.04 * k, 4), acc)
		"link":
			ci.draw_arc(P.call(0.3, 0.7), 0.13 * k, 0.0, TAU, 24, ink, 0.05 * k, true)
			ci.draw_arc(P.call(0.7, 0.3), 0.13 * k, 0.0, TAU, 24, ink, 0.05 * k, true)
			ci.draw_line(P.call(0.4, 0.6), P.call(0.6, 0.4), acc, 0.05 * k, true)
		"unlink":
			ci.draw_arc(P.call(0.3, 0.7), 0.13 * k, 0.0, TAU, 24, ink, 0.05 * k, true)
			ci.draw_arc(P.call(0.7, 0.3), 0.13 * k, 0.0, TAU, 24, ink, 0.05 * k, true)
			ci.draw_line(P.call(0.36, 0.36), P.call(0.64, 0.64), acc, 0.05 * k, true)
		"check":
			ci.draw_arc(P.call(0.5, 0.5), 0.4 * k, 0.0, TAU, 40, acc, 0.045 * k, true)
			ci.draw_polyline(_pts(o, k, [0.3, 0.52, 0.45, 0.66, 0.72, 0.38]), acc, 0.055 * k, true)
		"cloud":
			ci.draw_polyline(_ell(P.call(0.36, 0.58), 0.18 * k, 0.16 * k, PI * 0.5, PI * 1.5, 16), ink, 0.05 * k, true)
			ci.draw_polyline(_ell(P.call(0.56, 0.46), 0.22 * k, 0.22 * k, PI * 1.0, PI * 2.0, 18), ink, 0.05 * k, true)
			ci.draw_polyline(_ell(P.call(0.74, 0.6), 0.14 * k, 0.14 * k, -PI * 0.5, PI * 0.5, 12), ink, 0.05 * k, true)
			ci.draw_line(P.call(0.36, 0.74), P.call(0.74, 0.74), ink, 0.05 * k, true)
			ci.draw_line(P.call(0.55, 0.66), P.call(0.55, 0.42), acc, 0.05 * k, true)
		"map":
			ci.draw_polyline(_pts(o, k, [0.12, 0.22, 0.36, 0.12, 0.64, 0.22, 0.88, 0.12, 0.88, 0.78, 0.64, 0.88, 0.36, 0.78, 0.12, 0.88, 0.12, 0.22]), ink, 0.05 * k, true)
			ci.draw_line(P.call(0.36, 0.12), P.call(0.36, 0.78), ink, 0.035 * k, true)
			ci.draw_line(P.call(0.64, 0.22), P.call(0.64, 0.88), ink, 0.035 * k, true)
			ci.draw_circle(P.call(0.5, 0.46), 0.05 * k, acc)
		"crescent":
			Kit.crescent(ci, P.call(0.5, 0.5), 0.34 * k, -PI * 0.5, PI * 0.5, 0.12 * k, acc)
			ci.draw_arc(P.call(0.5, 0.5), 0.34 * k, 0.0, TAU, 32, ink, 0.035 * k, true)
		"compass":
			ci.draw_arc(P.call(0.5, 0.5), 0.4 * k, 0.0, TAU, 40, ink, 0.04 * k, true)
			ci.draw_colored_polygon(_star(P.call(0.5, 0.5), 0.34 * k, 0.07 * k, 4), acc)
		"dome":
			ci.draw_polyline(_ell(P.call(0.5, 0.62), 0.32 * k, 0.36 * k, PI, TAU, 20), ink, 0.05 * k, true)
			ci.draw_line(P.call(0.18, 0.62), P.call(0.82, 0.62), ink, 0.05 * k, true)
			ci.draw_circle(P.call(0.62, 0.48), 0.04 * k, acc)
		"scroll":
			_doc(ci, o, k, ink, 0.05 * k)
			for i in range(3): ci.draw_line(P.call(0.3, 0.42 + i * 0.12), P.call(0.64, 0.42 + i * 0.12), ink if i else acc, 0.035 * k, true)
		_:
			ci.draw_colored_polygon(_star(P.call(0.5, 0.5), 0.44 * k, 0.12 * k, 4), ink)


## Mystic pass (2026-11-14): thin-line versions of the glyphs the main surfaces use most.
## Returns true when it drew the icon, so the older filled drawing is skipped.
static func _mystic(ci: CanvasItem, name: String, o: Vector2, k: float, ink: Color, acc: Color, hole: Color) -> bool:
	var w := 0.045 * k
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * k
	match name:
		"gear":
			var c: Vector2 = P.call(0.5, 0.5)
			var pts := PackedVector2Array()
			for i in range(49):
				var a := TAU * i / 48.0
				var r := 0.36 if (i % 6) < 3 else 0.3
				pts.append(c + Vector2.from_angle(a) * r * k)
			ci.draw_polyline(pts, ink, w, true)
			ci.draw_arc(c, 0.12 * k, 0.0, TAU, 24, acc, w, true)
		"book":
			ci.draw_polyline(_pts(o, k, [0.5, 0.26, 0.32, 0.18, 0.1, 0.2, 0.1, 0.78, 0.32, 0.76, 0.5, 0.84, 0.68, 0.76, 0.9, 0.78, 0.9, 0.2, 0.68, 0.18, 0.5, 0.26, 0.5, 0.84]), ink, w, true)
			ci.draw_colored_polygon(_pts(o, k, [0.7, 0.14, 0.8, 0.14, 0.8, 0.4, 0.75, 0.34, 0.7, 0.4]), acc)
		"battle":
			ci.draw_line(P.call(0.24, 0.3), P.call(0.76, 0.84), ink, w, true)
			ci.draw_line(P.call(0.76, 0.3), P.call(0.24, 0.84), ink, w, true)
			ci.draw_arc(P.call(0.5, 0.5), 0.34 * k, PI * 1.12, PI * 1.88, 24, acc, w * 1.4, true)
		"person":
			ci.draw_arc(P.call(0.5, 0.32), 0.15 * k, 0.0, TAU, 28, ink, w, true)
			ci.draw_polyline(_ell(P.call(0.5, 0.86), 0.3 * k, 0.32 * k, PI, TAU, 20), ink, w, true)
			ci.draw_line(P.call(0.36, 0.9), P.call(0.64, 0.9), acc, w, true)
		"people":
			ci.draw_arc(P.call(0.38, 0.34), 0.12 * k, 0.0, TAU, 24, ink, w, true)
			ci.draw_polyline(_ell(P.call(0.38, 0.84), 0.22 * k, 0.26 * k, PI, TAU, 16), ink, w, true)
			ci.draw_arc(P.call(0.68, 0.38), 0.1 * k, 0.0, TAU, 20, acc, w, true)
			ci.draw_polyline(_ell(P.call(0.7, 0.84), 0.18 * k, 0.22 * k, PI * 1.2, TAU, 12), acc, w, true)
		"docs":
			ci.draw_polyline(Kit.closed(_pts(o, k, [0.22, 0.12, 0.78, 0.12, 0.78, 0.88, 0.22, 0.88])), ink, w, true)
			for i in range(3): ci.draw_line(P.call(0.34, 0.34 + i * 0.16), P.call(0.66, 0.34 + i * 0.16), acc if i == 0 else ink, w * 0.8, true)
		"pin":
			var pts2 := _ell(P.call(0.5, 0.4), 0.24 * k, 0.24 * k, PI * 0.8, PI * 2.2, 24)
			pts2.append(P.call(0.5, 0.9)); pts2.append(pts2[0])
			ci.draw_polyline(pts2, ink, w, true)
			ci.draw_circle(P.call(0.5, 0.4), 0.07 * k, acc)
		"heart":
			var hp := PackedVector2Array()
			for i in range(41):
				var t := TAU * i / 40.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				hp.append(P.call(0.5 + x * 0.024, 0.48 - y * 0.024))
			ci.draw_polyline(hp, acc, w * 1.1, true)
		"story":
			ci.draw_arc(P.call(0.5, 0.5), 0.36 * k, 0.0, TAU, 32, Color(acc, acc.a * 0.6), w * 0.7, true)
			Kit.crescent(ci, P.call(0.53, 0.5), 0.35 * k, -PI * 0.45, PI * 0.45, 0.1 * k, acc)
			Kit.star4(ci, P.call(0.5, 0.5), 0.14 * k, acc, 0.16)
		"power":
			ci.draw_arc(P.call(0.5, 0.54), 0.3 * k, -PI * 0.32, PI * 1.32, 32, ink, w, true)
			ci.draw_line(P.call(0.5, 0.14), P.call(0.5, 0.5), ink, w, true)
		"save":
			ci.draw_polyline(Kit.closed(_pts(o, k, [0.16, 0.14, 0.7, 0.14, 0.86, 0.3, 0.86, 0.86, 0.16, 0.86])), ink, w, true)
			ci.draw_polyline(_pts(o, k, [0.32, 0.14, 0.32, 0.34, 0.62, 0.34, 0.62, 0.14]), ink, w * 0.8, true)
			ci.draw_line(P.call(0.32, 0.66), P.call(0.68, 0.66), acc, w, true)
		"search":
			ci.draw_arc(P.call(0.44, 0.44), 0.26 * k, 0.0, TAU, 32, ink, w, true)
			ci.draw_line(P.call(0.63, 0.63), P.call(0.86, 0.86), acc, w * 1.2, true)
		"chat":
			var cp := Kit.rrect(Rect2(P.call(0.12, 0.18), Vector2(0.76, 0.52) * k), 0.16 * k, 6)
			ci.draw_polyline(Kit.closed(cp), ink, w, true)
			ci.draw_polyline(_pts(o, k, [0.3, 0.7, 0.26, 0.86, 0.46, 0.7]), ink, w, true)
			for i in range(3): ci.draw_circle(P.call(0.34 + i * 0.16, 0.44), 0.03 * k, acc if i == 1 else ink)
		"archive":
			ci.draw_polyline(Kit.closed(_pts(o, k, [0.14, 0.2, 0.86, 0.2, 0.86, 0.36, 0.14, 0.36])), ink, w, true)
			ci.draw_polyline(_pts(o, k, [0.2, 0.36, 0.2, 0.84, 0.8, 0.84, 0.8, 0.36]), ink, w, true)
			ci.draw_line(P.call(0.4, 0.52), P.call(0.6, 0.52), acc, w, true)
		"home":
			ci.draw_polyline(_pts(o, k, [0.14, 0.5, 0.5, 0.16, 0.86, 0.5]), ink, w, true)
			ci.draw_polyline(_pts(o, k, [0.24, 0.42, 0.24, 0.86, 0.76, 0.86, 0.76, 0.42]), ink, w, true)
			ci.draw_circle(P.call(0.5, 0.6), 0.05 * k, acc)
		"trash":
			ci.draw_line(P.call(0.16, 0.24), P.call(0.84, 0.24), ink, w, true)
			ci.draw_polyline(_pts(o, k, [0.24, 0.24, 0.3, 0.88, 0.7, 0.88, 0.76, 0.24]), ink, w, true)
			ci.draw_polyline(_pts(o, k, [0.38, 0.24, 0.42, 0.12, 0.58, 0.12, 0.62, 0.24]), ink, w * 0.8, true)
			ci.draw_line(P.call(0.5, 0.4), P.call(0.5, 0.74), acc, w, true)
		"send":
			ci.draw_polyline(Kit.closed(_pts(o, k, [0.12, 0.46, 0.88, 0.14, 0.62, 0.88, 0.48, 0.56])), ink, w, true)
			ci.draw_line(P.call(0.48, 0.56), P.call(0.88, 0.14), acc, w, true)
		"star4":
			Kit.star4(ci, P.call(0.5, 0.5), 0.44 * k, acc, 0.14)
		"info":
			ci.draw_arc(P.call(0.5, 0.5), 0.38 * k, 0.0, TAU, 32, ink, w, true)
			ci.draw_line(P.call(0.5, 0.44), P.call(0.5, 0.72), ink, w, true)
			ci.draw_circle(P.call(0.5, 0.32), 0.035 * k, acc)
		_:
			return false
	return true
