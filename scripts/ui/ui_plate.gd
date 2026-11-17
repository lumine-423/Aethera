extends Control
## Panel surface (mystic geometry pass, 2026-11-14).
## A soft rounded plate: big arc on the left, smaller on the right, hairline outline, a faint second
## outline offset behind it (叠片), a crimson/gold bead on the top edge and a short accent underline.
## Large plates also throw one long tangent sweep off the left arc and one diagonal hairline across
## the lower right corner. The old property names stay so every screen keeps working.

const Kit = preload("res://scripts/ui/ui_kit.gd")
var shape := "slant"        # slant | cut | rect | pill
var slant := 22.0
var fill := "surface"
var fill_alpha := 0.94
var border := "line"
var border_alpha := 0.9
var layered := true
var layer_offset := Vector2(12, 10)
var glass := true
var glass_tint := Color(0, 0, 0, 0)   # a > 0: pull the fill colour toward this tint (home night glass)
var stripe := ""            # "" | left | top
var corner := ""            # "" | tr | bl | br | tl
var corner_size := 26.0
var hatch := false
var underline := 0.0        # fraction of width; accent line at bottom-left
var block := false          # former solid dark plate -> light tinted accent outline
var dots := false
var detail := true          # sweep lines + beads on large plates
var bead := true
var reveal := 1.0: set = _set_reveal   # 0..1 trace-in (driven by Kit.rise)

func _set_reveal(v: float) -> void:
	reveal = v; queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiHub.palette_changed.connect(queue_redraw)
	resized.connect(queue_redraw)

func radii() -> Vector2:
	var h := size.y
	match shape:
		"rect": return Vector2(minf(10.0, h * 0.2), minf(10.0, h * 0.2))
		"cut": return Vector2(minf(h * 0.5, 18.0 + slant * 0.6), minf(h * 0.5, 18.0 + slant * 0.6))
		"pill": return Vector2(h * 0.5, h * 0.5)
		_:
			if slant <= 0.5: return Vector2(minf(10.0, h * 0.2), minf(10.0, h * 0.2))
			return Vector2(minf(h * 0.5, 26.0 + slant * 1.3), minf(h * 0.5, 14.0 + slant * 0.5))

func poly(r := Rect2()) -> PackedVector2Array:
	if r.size == Vector2.ZERO: r = Rect2(Vector2.ZERO, size)
	var k := radii()
	return Kit.plate_poly(r, k.x, k.y, 12)

func _has_point(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, poly())

## Draw the first `frac` of a closed outline (trace-in). Starts at the top-left arc.
static func trace(ci: CanvasItem, pts: PackedVector2Array, frac: float, color: Color, width: float) -> Vector2:
	var n := pts.size()
	if n < 2: return Vector2.ZERO
	var total := 0.0
	for i in range(n): total += pts[i].distance_to(pts[(i + 1) % n])
	var want := total * clampf(frac, 0.0, 1.0)
	var start := int(n * 0.75)       # top-left corner region of plate_poly ordering
	var acc := 0.0
	var head := pts[start]
	var line := PackedVector2Array([pts[start]])
	for j in range(n):
		var a := pts[(start + j) % n]; var b := pts[(start + j + 1) % n]
		var d := a.distance_to(b)
		if acc + d >= want:
			head = a.lerp(b, (want - acc) / maxf(d, 0.001)); line.append(head); break
		line.append(b); acc += d; head = b
	if line.size() >= 2: ci.draw_polyline(line, color, width, true)
	return head

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	if r.size.x < 2 or r.size.y < 2: return
	var main := poly()
	var k := radii()
	var solid: bool = block or (fill in ["accent", "block", "ink"] and fill_alpha >= 0.7)
	var acc := UiHub.c("accent")
	var line_c := UiHub.c(border if border != "" else "line", border_alpha)
	var show := clampf(reveal, 0.0, 1.0)
	var big := size.x > 240.0 and size.y > 120.0
	# ghost outline (叠片): a second hairline offset behind
	if layered and show > 0.3:
		var ghost := PackedVector2Array()
		var off := layer_offset * 0.55
		for p in main: ghost.append(p + off)
		draw_polyline(Kit.closed(ghost), UiHub.c("line", 0.55 * show), 1.0, true)
	# fill
	if solid:
		var base := UiHub.c("accent") if fill == "accent" else UiHub.c("muted")
		if show >= 1.0: Kit.ornate(self, main, base)
		else:
			draw_colored_polygon(main, Color(UiHub.c("surface"), 0.96 * show))
			trace(self, main, show, Color(base, 0.85), 1.3)
	else:
		var fa := fill_alpha * (0.88 if fill == "surface" else 1.0)
		var fc := UiHub.c(fill, fa * show)
		if glass_tint.a > 0.0: fc = Color(fc.lerp(Color(glass_tint, fc.a), glass_tint.a), fc.a)
		draw_colored_polygon(main, fc)
		if glass and show > 0.5:
			var top := Color(UiHub.c("glow"), lerpf(0.55, 0.04, UiHub.night) * show)
			var mid := Geometry2D.intersect_polygons(main, PackedVector2Array([Vector2(-10, -10), Vector2(size.x + 10, -10), Vector2(size.x + 10, size.y * 0.42), Vector2(-10, size.y * 0.42)]))
			for m in mid:
				if m.size() < 3: continue
				var cols := PackedColorArray()
				for p: Vector2 in m: cols.append(Color(top, top.a * (1.0 - clampf(p.y / maxf(size.y * 0.42, 1.0), 0.0, 1.0))))
				draw_polygon(m, cols)
		if border != "":
			if show < 1.0:
				var head := trace(self, main, show, line_c, 1.2)
				draw_circle(head, 2.6, Color(acc, 1.0 - show))
			else:
				draw_polyline(Kit.closed(main), line_c, 1.2, true)
	if show < 0.85: return
	var a := (show - 0.85) / 0.15
	# long sweeps on big plates: tangent off the left arc, diagonal across the lower right corner
	if detail and big and not solid:
		var c0 := Vector2(k.x, k.x)
		var ang := PI * 1.18
		var p0 := c0 + Vector2.from_angle(ang) * k.x
		var tg := Vector2.from_angle(ang - PI * 0.5)
		Kit.line_fade(self, p0 + tg * 6.0, p0 + tg * minf(size.y * 0.9, 220.0), UiHub.c("hair", 0.55 * a), 1.0)
		var br := Vector2(size.x - k.y * 0.3, size.y - k.y * 0.3)
		Kit.line_fade(self, br + Vector2(-46, 46), br + Vector2(36, -36), UiHub.c("hair", 0.6 * a), 1.0)
	# bead on the top edge + short underline
	if bead and size.x > 120.0 and border != "":
		var bx := k.x + minf(size.x * 0.08, 60.0)
		draw_circle(Vector2(bx, 0), 3.0 if big else 2.4, Color(acc, a))
	var ul := underline if underline > 0.0 else (0.07 if big and not solid and border != "" else 0.0)
	if ul > 0.0:
		var ux := k.x + minf(size.x * 0.05, 40.0)
		draw_line(Vector2(ux, size.y), Vector2(ux + size.x * minf(ul, 0.25), size.y), Color(acc, a), 2.0, true)
	if stripe == "left":
		var c := Vector2(k.x + 2.0, size.y * 0.5)
		Kit.crescent(self, c, minf(size.y * 0.32, 40.0), PI * 0.62, PI * 1.38, 4.0, Color(acc, a))
	elif stripe == "top":
		draw_line(Vector2(k.x, 1), Vector2(k.x + minf(size.x * 0.22, 140.0), 1), Color(acc, a), 2.0, true)
	if corner != "":
		var cs := clampf(corner_size * 0.42, 6.0, 13.0)
		var pos: Vector2 = {"tr": Vector2(size.x - k.y * 0.4, k.y * 0.4), "tl": Vector2(k.x * 0.4, k.x * 0.4), "br": Vector2(size.x - k.y * 0.4, size.y - k.y * 0.4), "bl": Vector2(k.x * 0.4, size.y - k.x * 0.4)}.get(corner, Vector2.ZERO)
		Kit.star4(self, pos, cs, Color(acc, a), 0.16)
	if hatch:
		Kit.hatch(self, Vector2(size.x - k.y - 70, size.y - 22), 5, 0, UiHub.c("muted", 0.7 * a))
	if dots:
		Kit.dots(self, Vector2(size.x - k.y - 120, 26), 4, 1, 14, 3, Color(acc, 0.5 * a))
