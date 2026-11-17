extends RefCounted
## Static drawing and motion helpers shared by every UI component.
## 2026-11-14 mystic geometry pass: thin serif type, hairline outlines, long sweeping arcs,
## crimson (day) / gold (night) accents: crescents, four-point stars, small dots and short underlines.
## Everything is native CanvasItem drawing: resolution independent and recolorable.

const Motion = preload("res://scripts/home/motion.gd")
const FONT_FILE = preload("res://assets/fonts/NotoSerifSC.ttf")
static var _fonts := {}

## The old UI asked for heavy sans weights (600-900). The serif reads best thin, so weights are
## compressed: 900 -> 520, 800 -> 470, 700 -> 410, 600 -> 360, 500 -> 310.
static func serif_weight(weight: int) -> float:
	return clampf(220.0 + (float(weight) - 400.0) * 0.6 + 60.0, 260.0, 560.0)

static func font(weight := 600, spacing := 0) -> Font:
	var key := "%d:%d" % [weight, spacing]
	if not _fonts.has(key):
		var f := FontVariation.new(); f.base_font = FONT_FILE
		f.variation_opentype = {2003265652: serif_weight(weight)}
		if spacing != 0: f.spacing_glyph = spacing
		_fonts[key] = f
	return _fonts[key]

static func curve(x: float, shape := Motion.RISE) -> float:
	return Motion.ease(x, shape)

# ---------------------------------------------------------------- shapes
## Rounded rectangle polygon. rad is clamped to half the short side.
static func rrect(r: Rect2, rad: float, seg := 10) -> PackedVector2Array:
	rad = clampf(rad, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var out := PackedVector2Array()
	if rad < 0.5:
		return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cs := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad), Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	for k in range(4):
		var a0 := -PI * 0.5 + PI * 0.5 * k
		for i in range(seg + 1):
			out.append(cs[k] + Vector2.from_angle(a0 + PI * 0.5 * i / seg) * rad)
	return out

## Asymmetric "mystic plate": big round on the left, smaller round on the right
## (the concept panels lean on a sweeping left arc).
static func plate_poly(r: Rect2, left_rad: float, right_rad: float, seg := 12) -> PackedVector2Array:
	var h := r.size.y
	left_rad = clampf(left_rad, 0.0, minf(h * 0.5, r.size.x * 0.45))
	right_rad = clampf(right_rad, 0.0, minf(h * 0.5, r.size.x * 0.45))
	var out := PackedVector2Array()
	var corners := [
		[Vector2(r.end.x - right_rad, r.position.y + right_rad), right_rad, -PI * 0.5],
		[Vector2(r.end.x - right_rad, r.end.y - right_rad), right_rad, 0.0],
		[Vector2(r.position.x + left_rad, r.end.y - left_rad), left_rad, PI * 0.5],
		[Vector2(r.position.x + left_rad, r.position.y + left_rad), left_rad, PI]]
	for c in corners:
		var rr: float = c[1]
		if rr < 0.5:
			out.append(c[0]); continue
		for i in range(seg + 1):
			out.append(c[0] + Vector2.from_angle(c[2] + PI * 0.5 * i / seg) * rr)
	return out

static func pill(r: Rect2, seg := 16) -> PackedVector2Array:
	return rrect(r, r.size.y * 0.5, seg)

## Legacy shape names still used by screens. Both now map to the rounded mystic plate.
static func slant(r: Rect2, s: float) -> PackedVector2Array:
	if s <= 0.5: return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	return plate_poly(r, minf(r.size.y * 0.5, s * 1.6 + 6.0), minf(r.size.y * 0.5, s * 0.9 + 4.0), 8)

static func cut(r: Rect2, c: float) -> PackedVector2Array:
	return rrect(r, c * 0.9 + 6.0, 8)

static func closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0: out.append(points[0])
	return out

static func circle_poly(c: Vector2, r: float, n := 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(n): out.append(c + Vector2.from_angle(TAU * i / n) * r)
	return out

static func bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p: Vector2 in poly: r = r.expand(p)
	return r

## Fill every polygon returned by a Geometry2D boolean op, skipping hole outlines.
static func fill_all(ci: CanvasItem, polys: Array, color: Color) -> void:
	for p in polys:
		if p.size() >= 3 and Geometry2D.triangulate_polygon(p).is_empty(): continue
		if p.size() >= 3 and not Geometry2D.is_polygon_clockwise(p): ci.draw_colored_polygon(p, color)
		elif p.size() >= 3 and polys.size() == 1: ci.draw_colored_polygon(p, color)

# ---------------------------------------------------------------- mystic marks
## Four-point star (the house glyph): long thin rays. thin = ray waist ratio.
static func star4(ci: CanvasItem, c: Vector2, s: float, color: Color, thin := 0.18, rot := 0.0) -> void:
	if s < 0.4 or color.a <= 0.003: return
	var pts := PackedVector2Array()
	for i in range(8):
		var r := s if i % 2 == 0 else s * thin
		pts.append(c + Vector2.from_angle(rot - PI * 0.5 + PI * 0.25 * i) * r)
	ci.draw_colored_polygon(pts, color)

## Outline-only four-point star with concave sides.
static func star4_line(ci: CanvasItem, c: Vector2, s: float, color: Color, width := 1.2, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for k in range(4):
		var a := rot - PI * 0.5 + PI * 0.5 * k
		var tip := c + Vector2.from_angle(a) * s
		var nxt := c + Vector2.from_angle(a + PI * 0.5) * s
		for i in range(9):
			var t := i / 8.0
			var lin := tip.lerp(nxt, t)
			pts.append(lin.lerp(c, 0.55 * sin(t * PI)))
	pts.append(pts[0])
	ci.draw_polyline(pts, color, width, true)

## Thick-to-thin crescent: an arc whose width swells in the middle (concept emblem).
## a0..a1 in radians, w = max thickness.
static func crescent(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, w: float, color: Color, seg := 40) -> void:
	if color.a <= 0.003 or r < 1.0: return
	var outer := PackedVector2Array(); var inner := PackedVector2Array()
	for i in range(seg + 1):
		var t := float(i) / seg
		var a := lerpf(a0, a1, t)
		var k := pow(sin(t * PI), 0.8) * w
		outer.append(c + Vector2.from_angle(a) * (r + k * 0.5))
		inner.append(c + Vector2.from_angle(a) * (r - k * 0.5))
	inner.reverse()
	outer.append_array(inner)
	if Geometry2D.triangulate_polygon(outer).is_empty():
		ci.draw_polyline(outer, color, 1.0, true); return
	ci.draw_colored_polygon(outer, color)

## Hairline arc with tapered ends (fades at both ends by splitting into segments).
## One polyline with per-point alpha (2026-11-17: was one draw_line per segment, ~50 draw commands
## per arc; a single command keeps the same look and makes every page cheaper to render).
static func arc_fade(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, color: Color, width := 1.0, seg := 48, fade := 0.25) -> void:
	if color.a <= 0.003 or seg < 1: return
	var pts := PackedVector2Array(); var cols := PackedColorArray()
	pts.resize(seg + 1); cols.resize(seg + 1)
	for i in range(seg + 1):
		var t := float(i) / seg
		pts[i] = c + Vector2.from_angle(lerpf(a0, a1, t)) * r
		cols[i] = Color(color, color.a * clampf(minf(t, 1.0 - t) / maxf(fade, 0.001), 0.0, 1.0))
	ci.draw_polyline_colors(pts, cols, width, true)

## Straight hairline that fades toward both ends.
static func line_fade(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, width := 1.0, seg := 12) -> void:
	if color.a <= 0.003 or seg < 1: return
	var pts := PackedVector2Array(); var cols := PackedColorArray()
	pts.resize(seg + 1); cols.resize(seg + 1)
	for i in range(seg + 1):
		var t := float(i) / seg
		pts[i] = a.lerp(b, t)
		cols[i] = Color(color, color.a * sin(t * PI))
	ci.draw_polyline_colors(pts, cols, width, true)

## Red bead on a line.
static func bead(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	ci.draw_circle(c, r, color)

# ---------------------------------------------------------------- legacy marks (restyled)
## Old diagonal hatch -> a quiet row of tiny beads.
static func hatch(ci: CanvasItem, origin: Vector2, count: int, h: float, color: Color, step := 7.0, width := 2.0) -> void:
	for i in range(count):
		ci.draw_circle(origin + Vector2(i * maxf(step, 9.0), h * 0.5), 1.4, Color(color, color.a * (1.0 - i * 0.14)))

static func dots(ci: CanvasItem, origin: Vector2, cols: int, rows: int, step: float, r: float, color: Color) -> void:
	for y in range(rows):
		for x in range(cols):
			ci.draw_circle(origin + Vector2(x * step, y * step), maxf(r * 0.45, 1.0), color)

## Small chevron (outline) instead of the old solid triangles; dir: 0 up, 1 right, 2 down, 3 left.
static func tri(ci: CanvasItem, c: Vector2, s: float, dir: int, color: Color) -> void:
	var pts := [Vector2(-0.55, -1.0), Vector2(0.45, 0.0), Vector2(-0.55, 1.0)]
	var out := PackedVector2Array()
	for p in pts: out.append(c + p.rotated((dir - 1) * PI * 0.5) * s)
	ci.draw_polyline(out, color, maxf(1.2, s * 0.22), true)

static func diamond(ci: CanvasItem, c: Vector2, s: float, color: Color, outline := 0.0) -> void:
	if s < 0.35 or color.a <= 0.002: return
	var pts := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)])
	if outline > 0.0:
		pts.append(pts[0]); ci.draw_polyline(pts, color, minf(outline, 1.4), true)
	else:
		ci.draw_colored_polygon(pts, color)

static func diamond_rot(ci: CanvasItem, c: Vector2, s: float, ang: float, color: Color, width := 1.5) -> void:
	var pts := PackedVector2Array()
	for j in range(5): pts.append(c + Vector2.from_angle(ang + PI * 0.5 * j) * s)
	ci.draw_polyline(pts, color, minf(width, 1.4), true)

## Corner mark: now a short hairline quarter-arc that hugs the corner.
static func bracket(ci: CanvasItem, p: Vector2, a: Vector2, b: Vector2, color: Color, length := 18.0, inset := 10.0) -> void:
	var o := p + (a + b) * inset
	var pts := PackedVector2Array()
	for i in range(9):
		var t := i / 8.0
		pts.append(o + a * length * (1.0 - t) * (1.0 - t) + b * length * t * t + (a + b) * length * 0.0)
	ci.draw_polyline(pts, color, 1.2, true)

## Fine diagonal stripes clipped to a polygon (kept for screens that call it; drawn as hairlines).
static func stripes(ci: CanvasItem, poly: PackedVector2Array, color: Color, step := 10.0, offset := 0.0, from := 0.55, width := 2.0, fade := true) -> void:
	if poly.size() < 3: return
	var r := bounds(poly)
	var h := r.size.y
	var x0 := r.position.x + r.size.x * from
	var x := x0 - h + fmod(offset, step * 2.0)
	while x < r.end.x + h:
		var k := 1.0 if not fade else clampf((x - x0 + h * 0.3) / maxf(r.end.x - x0, 1.0), 0.0, 1.0)
		if k > 0.03:
			var seg := PackedVector2Array([Vector2(x + h * 0.9, r.position.y - 2), Vector2(x, r.end.y + 2)])
			for part in Geometry2D.intersect_polyline_with_polygon(seg, poly):
				ci.draw_polyline(part, Color(color, color.a * k * 0.5), 1.0, true)
		x += step * 2.0

## Fill for every former "solid" block: a whisper of tint, an accent hairline, a sweeping inner arc
## at the left and a bead. Replaces the dark blocks the mystic direction does not use.
static func ornate(ci: CanvasItem, poly: PackedVector2Array, base: Color, march := 0.0, press := 0.0) -> void:
	if poly.size() < 3 or Geometry2D.triangulate_polygon(poly).is_empty(): return
	var r := bounds(poly)
	var tint := Color(base, 0.07 + 0.05 * press)
	ci.draw_colored_polygon(poly, UiHub.c("surface", 0.96))
	ci.draw_colored_polygon(poly, tint)
	ci.draw_polyline(closed(poly), Color(base, 0.85), 1.3, true)
	var inner := Geometry2D.offset_polygon(poly, -5.0)
	if not inner.is_empty() and inner[0].size() >= 3:
		ci.draw_polyline(closed(inner[0]), Color(base, 0.22), 1.0, true)
	if r.size.y >= 30.0 and r.size.x > 70.0:
		var c := Vector2(r.position.x + r.size.y * 0.5, r.position.y + r.size.y * 0.5)
		var sweep := fmod(march * 0.02, TAU)
		arc_fade(ci, c, r.size.y * 0.36, PI * 0.6 + sweep * 0.05, PI * 1.6 + sweep * 0.05, Color(base, 0.5), 1.0, 28)
		ci.draw_circle(Vector2(r.position.x + r.size.x * 0.12 + 12.0, r.position.y), 2.6, base)

## Keep only the part of a polygon left of x (slice-in reveal). Empty when nothing is left.
static func clip_x(poly: PackedVector2Array, x: float, h: float, lean := 0.0) -> PackedVector2Array:
	var cutp := PackedVector2Array([Vector2(-4000, -10), Vector2(x + lean, -10), Vector2(x, h + 10), Vector2(-4000, h + 10)])
	var res := Geometry2D.intersect_polygons(poly, cutp)
	return res[0] if not res.is_empty() else PackedVector2Array()

# ---------------------------------------------------------------- text
static func text_width(value: String, size: int, weight := 600) -> float:
	return font(weight).get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## Draw a single line of text vertically centered inside `r`.
static func text(ci: CanvasItem, r: Rect2, value: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, weight := 700, spacing := 0) -> void:
	var f := font(weight, spacing)
	var asc := f.get_ascent(size); var desc := f.get_descent(size)
	var baseline := r.position.y + (r.size.y - (asc + desc)) * 0.5 + asc
	ci.draw_string(f, Vector2(r.position.x, baseline), value, align, r.size.x, size, color, TextServer.JUSTIFICATION_NONE)

# ---------------------------------------------------------------- motion helpers
## Turn a full-screen ColorRect into frosted glass (blurred + palette shade), kept in sync with day/night.
static func frost(rect: ColorRect) -> void:
	rect.color = Color.WHITE
	var m := ShaderMaterial.new(); m.shader = preload("res://scripts/ui/frost.gdshader")
	m.set_shader_parameter("tint", UiHub.c("shade"))
	rect.material = m
	var sync := func() -> void: m.set_shader_parameter("tint", UiHub.c("shade"))
	UiHub.palette_changed.connect(sync)
	rect.tree_exiting.connect(func(): if UiHub.palette_changed.is_connected(sync): UiHub.palette_changed.disconnect(sync))

## Count a label up to a number (used for rewards, stats).
static func count(label: Label, to: float, fmt := "%d", duration := 0.8, delay := 0.0) -> void:
	if UiHub.reduced_motion or not label.is_inside_tree():
		label.text = fmt % to; return
	label.text = fmt % 0
	var t := label.create_tween()
	if delay > 0.0: t.tween_interval(delay)
	var last := [-1]
	var step := func(v: float) -> void:
		label.text = fmt % v
		if int(v) != last[0]:
			last[0] = int(v)
			UiHub.sfx("count", 0.9 + 0.5 * v / maxf(to, 1.0))
	t.tween_method(step, 0.0, to, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

## Rise entrance used across screens: slide + fade, 0.62s, staggered. Plates also draw their
## outline in (reveal 0..1) so the hairlines trace themselves.
static func rise(node: CanvasItem, delay := 0.0, distance := 46.0, duration := 0.62, axis := Vector2.RIGHT) -> void:
	if UiHub.reduced_motion or not node.is_inside_tree(): return
	var base: Vector2 = node.position
	distance *= 0.6
	node.modulate.a = 0.0
	node.position = base + axis * distance
	var t := node.create_tween()
	if delay > 0.0: t.tween_interval(delay)
	var sliced := "reveal" in node
	if sliced: node.reveal = 0.0
	var step := func(v: float) -> void:
		if not is_instance_valid(node): return
		var q := Motion.ease(v)
		node.position = base + axis * distance * (1.0 - q)
		node.modulate.a = minf(1.0, q * 1.5)
		if sliced: node.reveal = Motion.ease(minf(v * 1.15, 1.0), Motion.RISE)
	t.tween_method(step, 0.0, 1.0, duration)

static func pop(node: Control, delay := 0.0, duration := 0.34) -> void:
	if UiHub.reduced_motion or not node.is_inside_tree(): return
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2.ONE * 0.9; node.modulate.a = 0.0
	var t := node.create_tween()
	if delay > 0.0: t.tween_interval(delay)
	var step := func(v: float) -> void:
		if not is_instance_valid(node): return
		var q := Motion.ease(v)
		node.scale = Vector2.ONE * lerpf(0.9, 1.0, q)
		node.modulate.a = q
	t.tween_method(step, 0.0, 1.0, duration)
