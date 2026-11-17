extends Control
## Shared page background (mystic geometry pass, 2026-11-14), fully code-drawn so day (white paper,
## gray hairlines, crimson beads) and night (black, warm gray, gold) come from one palette.
## Layers: paper tone with a soft centre light, giant construction circles that turn very slowly,
## long diagonal hairlines, one huge faint four-point star outline, and slow twinkling dust.
## Screens that show a game scene (story, battle) hide it and draw their own scene slot.

## 2026-11-17: style "room" lays the home room picture under everything, blurred until only soft
## colour fields remain (assets/ui/home_room/blur_{day,night}.webp), so the room is always "there".
## The story screen asks for "plain" and keeps the old look.

const Kit = preload("res://scripts/ui/ui_kit.gd")
const BLUR_DAY := "res://assets/ui/home_room/blur_day.webp"
const BLUR_NIGHT := "res://assets/ui/home_room/blur_night.webp"
var clock := 0.0
var dust: Array = []
var look := Vector2.ZERO
var style := "room": set = _set_style
var blur_day: Texture2D
var blur_night: Texture2D

func _set_style(v: String) -> void:
	style = v; queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(BLUR_DAY): blur_day = load(BLUR_DAY)
	if ResourceLoader.exists(BLUR_NIGHT): blur_night = load(BLUR_NIGHT)
	UiHub.palette_changed.connect(queue_redraw)
	UiHub.options_changed.connect(queue_redraw)
	resized.connect(queue_redraw)
	var rng := RandomNumberGenerator.new(); rng.seed = 1114
	for i in range(46):
		dust.append({"p": Vector2(rng.randf(), rng.randf()), "s": rng.randf_range(1.6, 5.0), "tw": rng.randf() * TAU, "v": rng.randf_range(0.003, 0.01), "star": rng.randf() < 0.3})

func _process(delta: float) -> void:
	if UiHub.reduced_motion or not is_visible_in_tree(): return
	clock += delta
	for d in dust:
		d.p.y -= d.v * delta
		if d.p.y < -0.02: d.p.y = 1.02; d.p.x = randf()
	var m := get_local_mouse_position()
	var target := Vector2.ZERO
	if size.x > 0 and m.x >= 0 and m.y >= 0 and m.x <= size.x and m.y <= size.y: target = (m / size - Vector2(0.5, 0.5)) * 2.0
	look = look.lerp(target, minf(delta * 2.0, 1.0))
	queue_redraw()

func _draw() -> void:
	var W := size.x; var H := size.y
	if W < 2: return
	var bg := UiHub.c("background")
	draw_rect(Rect2(Vector2.ZERO, size), bg)
	# background never follows the pointer (user rule 2026-11-17: only UI floats)
	var par := Vector2.ZERO
	if style == "room" and blur_day:
		var ts := blur_day.get_size()
		var s := maxf(W / ts.x, H / ts.y)
		var ds := ts * s
		var rp := (size - ds) * 0.5
		draw_texture_rect(blur_day, Rect2(rp, ds), false)
		if blur_night and UiHub.night > 0.001: draw_texture_rect(blur_night, Rect2(rp, ds), false, Color(1, 1, 1, UiHub.night))
		# a thin veil of the page colour keeps text readable
		draw_rect(Rect2(Vector2.ZERO, size), Color(bg, lerpf(0.30, 0.38, UiHub.night)))
	# soft centre light / edge shade
	var glow := UiHub.c("glow", lerpf(0.55, 0.035, UiHub.night))
	for i in range(5):
		draw_circle(Vector2(W * 0.42, H * 0.46), H * (0.95 - i * 0.16), Color(glow, glow.a * 0.18))
	var hair := UiHub.c("hair", lerpf(0.42, 0.55, UiHub.night))
	var line := UiHub.c("line", 0.8)
	var acc := UiHub.c("accent")
	var t := clock
	# giant construction circles anchored right of centre (concept home sweep)
	var c1 := Vector2(W * 0.74, H * 0.52) + par * 0.6
	for i in range(3):
		var r := H * (0.56 + i * 0.17)
		var a0 := -PI * 0.92 + t * (0.012 + i * 0.006) * (1.0 if i % 2 == 0 else -1.0)
		Kit.arc_fade(self, c1, r, a0, a0 + PI * (1.25 - i * 0.18), hair if i == 0 else line, 1.0, 96, 0.14)
		draw_circle(c1 + Vector2.from_angle(a0 + PI * 0.4) * r, 2.2 if i else 2.8, Color(acc if i == 0 else UiHub.c("muted"), 0.55))
	# small circle top-left
	var c2 := Vector2(W * 0.1, H * 0.12) + par
	Kit.arc_fade(self, c2, H * 0.2, PI * 0.1 + t * 0.02, PI * 1.3 + t * 0.02, line, 1.0, 48, 0.2)
	# long diagonal hairlines
	for i in range(4):
		var x := W * (0.18 + i * 0.27) + sin(t * 0.07 + i) * 6.0 + par.x * (0.4 + i * 0.2)
		Kit.line_fade(self, Vector2(x - H * 0.55, H * 1.05), Vector2(x + H * 0.55, -H * 0.05), Color(hair, hair.a * (0.55 if i % 2 else 0.85)), 1.0, 18)
	Kit.line_fade(self, Vector2(W * 0.5, H * 0.98) + par, Vector2(W * 0.92, H * 0.06) + par, Color(acc, 0.16), 1.0, 18)
	# huge faint four-point star outline that turns very slowly
	Kit.star4_line(self, Vector2(W * 0.3, H * 0.55) + par * 0.3, H * 0.42, Color(line, 0.45), 1.0, sin(t * 0.03) * 0.06)
	# beads on a horizon hairline
	var hy := H * 0.86 + par.y * 0.3
	Kit.line_fade(self, Vector2(W * 0.04, hy), Vector2(W * 0.6, hy), Color(line, 0.6), 1.0, 20)
	draw_circle(Vector2(W * 0.22, hy), 2.4, Color(acc, 0.6))
	# dust
	for d in dust:
		var tw: float = 0.3 + 0.7 * absf(sin(t * 0.9 + d.tw))
		var p: Vector2 = Vector2(d.p.x * W, d.p.y * H) + par * 0.5
		if d.star: Kit.star4(self, p, d.s * (0.8 + 0.3 * tw), Color(acc, 0.42 * tw), 0.16)
		else: draw_circle(p, d.s * 0.26, UiHub.c("muted", 0.3 * tw))
