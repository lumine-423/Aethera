extends Control
## 刻印激活演出 (2026-11-17, plan #4). Full-screen ceremony played over the workshop when the
## player presses 激活, locked to the activation music the user picked. User rules (2026-11-17):
## the same for day and night; four clips, each played to its end:
##   1 activate_click, then 2 activate_loop_a + 3 activate_loop_b together, then 4 activate_done
##   (once both 2 and 3 are over) - and nothing else sounds meanwhile (no added effect sounds;
##   UiHub.sfx_quiet mutes the UI).
## Timing comes from data/workshop/activation_cues.json (tools/build_workshop_activation.py): each
## clip's loudness curve drives intensity, its hits fire light pulses, rings lock and glyphs light on
## its hits. The clock follows the heard position of the sequence (UiHub.workshop_activation_time).
## The clip placement is the user's (data/workshop/activation_mix.json -> one-file mix). Phase marks
## follow it (user's 2026-11-17 layout: 1 at 0, 2 at 0.67, 3 at 3.94, 4 at 9.34):
##   0..R1     启印 + 法阵展开  dark veil, flash and shock rings on the click hits; six rings draw on
##             (ticks / rune band / hexagram / nature names / octagram / bead ring). R1 = the later of
##             2 / 3 comes in (3.94, shock ring)
##   R1..G0    数据流 + 回路充能  glyph columns of the blueprint text + hex fall, packets run down 8
##             conduits, the blueprint text circles the inner ring; the player's own sigil lights glyph
##             by glyph on the hits of 2 and 3. G0 = 2.4 s before 4 (6.94)
##   G0..D     汇聚  motes rush in, rays open, the circle tightens up to 2's climax (9.12, shock ring)
##             and holds to D
##   D..end    铭刻  4 starts (9.34): white flash, cross light, shock ring, burst, the circle collapses,
##             the sigil is stamped; D+0.75 「刻印铭成」【name】; fades out as 4 ends, then the result panel
## Click / tap anywhere: before the seal jumps to it (only 4 plays), after it closes the ceremony.

signal sealed
signal finished

const Kit = preload("res://scripts/ui/ui_kit.gd")
const CUES_PATH := "res://data/workshop/activation_cues.json"
const ORDER := ["click", "loop_a", "loop_b", "done"]
const HEX := "0123456789ABCDEF"
const NATURES := ["空间", "静止", "运动", "生命", "力场", "构建", "输出", "特殊"]
const TONE := {"空间": "9f8cf0", "静止": "5fd8d0", "运动": "e06450", "生命": "9ac47a", "力场": "d8a84e", "构建": "c98f3d", "输出": "f0e3a0", "特殊": "ff5fa2"}
const RING_R := [1.0, 0.86, 0.72, 0.58, 0.46, 0.36]

var screen                      # the workshop screen (draft, worlds, paint_glyph ...)
var title := ""
var blueprint := ""
var T := 6.0
var t := 0.0
var _clock := 0.0
var _skipped := false
var _sealed := false
var _ended := false
var _playing := false
var seg: Dictionary = {}        # role -> {start, dur, env (PackedFloat32Array), fps, onsets, peak}
var A0 := 5.0                   # first of 2 / 3 comes in
var R1 := 5.0                   # the later of 2 / 3 comes in: rings done, data flow starts
var B0 := 10.0                  # the gathering starts
var A_PEAK := 13.5              # climax of 2 (loop_a)
var END := 20.0                 # end of 4 (done)
var events: Array = []          # [{t, kind, i}] in time order
var _next_ev := 0
var ring_t: Array[float] = []
var ring_rot: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var part_ids: Array[String] = []
var part_t: Dictionary = {}
var nature_lit: Dictionary = {}
var ws: Dictionary = {}
var sig_center := Vector2.ZERO
var sig_k := 1.0
var pulses: Array = []
var packets: Array = []
var motes: Array = []
var burst: Array = []
var cols: Array = []
var runes: Array = []
var data_chars: PackedStringArray = PackedStringArray()
var ring_text := ""
var _pkt_acc := 0.0
var add: Control
var rng := RandomNumberGenerator.new()
var C := Vector2.ZERO
var R := 450.0

static var _glow_tex: GradientTexture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add = Control.new(); add.name = "Light"; add.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.material = m
	add_child(add)
	add.draw.connect(func(): _draw_light(add))
	resized.connect(func(): add.size = size)

## Call after add_child, right after UiHub.start_workshop_activation().
func play() -> void:
	rng.seed = 20261117
	add.size = size
	C = size * 0.5 + Vector2(0, -10)
	R = minf(size.y * 0.42, size.x * 0.3)
	var sheet = JSON.parse_string(FileAccess.get_file_as_string(CUES_PATH)) if FileAccess.file_exists(CUES_PATH) else null
	var clips: Dictionary = sheet.get("clips", {}) if sheet is Dictionary else {}
	var fallback := {"click": 5.07, "loop_a": 10.21, "loop_b": 5.35, "done": 4.52}
	var dur := {}
	for role in ORDER: dur[role] = float(clips.get(role, {}).get("duration", fallback[role]))
	# 1, then 2 and 3 together, then 4 once both are over (UiHub.start_workshop_activation)
	var start := {"click": 0.0, "loop_a": dur.click, "loop_b": dur.click, "done": dur.click + maxf(dur.loop_a, dur.loop_b)}
	# the one-file mix records where each clip really sits (tuned on the user's mixer page)
	var placed: Dictionary = sheet.get("sequence", {}).get("start", {}) if sheet is Dictionary else {}
	for role in ORDER:
		if placed.has(role): start[role] = float(placed[role])
	for role in ORDER:
		var c: Dictionary = clips.get(role, {})
		seg[role] = {"start": start[role], "dur": dur[role], "env": PackedFloat32Array(c.get("env", [])), "fps": float(c.get("fps", 30)),
			"onsets": c.get("onsets", []), "peak": float(c.get("peak", dur[role] * 0.8))}
	# phase marks, all taken from where the user placed the clips (activation_mix.json):
	#   rings draw on until the later of 2 / 3 comes in (R1); data flow + glyphs until the gathering
	#   (G0, 2.4 s before 4); the gathering peaks on 2's climax (or on 4 if that comes first); 4 seals
	T = seg.done.start; END = T + dur.done
	A0 = minf(seg.loop_a.start, seg.loop_b.start)
	R1 = clampf(maxf(seg.loop_a.start, seg.loop_b.start), 2.0, T - 3.0)
	B0 = clampf(T - 2.4, R1 + 1.2, T - 0.6)
	A_PEAK = float(seg.loop_a.start) + float(seg.loop_a.peak)
	if A_PEAK > T or A_PEAK < B0 + 0.4: A_PEAK = T
	_build_text()
	_build_runes()
	_build_columns()
	_build_sigil()
	_build_events()
	pulses.append({"t0": 0.0, "r": 0.0, "big": true, "age": 0.0})
	_playing = true
	queue_redraw()

# ------------------------------------------------------------------ setup
func _build_text() -> void:
	var src := blueprint if blueprint != "" else title
	var keep := ""
	for ch in src:
		if ch.strip_edges() == "" or ch in "【】（）()，、；：×\n": continue
		keep += ch
	if keep == "": keep = "刻印"
	for ch in keep: data_chars.append(ch)
	for i in range(16): data_chars.append(HEX[i])
	ring_text = ""
	while ring_text.length() < 64: ring_text += keep + "·"
	ring_text = ring_text.substr(0, 64)

func _build_runes() -> void:
	# 24 small procedural runes on a 3x3 grid: 2-4 strokes, sometimes a ring
	var g := [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]
	for i in range(24):
		var strokes: Array = []
		var n := 2 + rng.randi() % 3
		var last := rng.randi() % 9
		for s in range(n):
			var pts := PackedVector2Array([g[last]])
			for k in range(1 + rng.randi() % 2):
				var nx := rng.randi() % 9
				if nx == last: nx = (nx + 4) % 9
				pts.append(g[nx]); last = nx
			strokes.append(pts)
		runes.append({"s": strokes, "o": rng.randf() < 0.3})

func _build_columns() -> void:
	var xs := [110.0, 230.0, 350.0, size.x - 350.0, size.x - 230.0, size.x - 110.0]
	for i in range(xs.size()):
		var chars: Array = []
		for k in range(22): chars.append(data_chars[rng.randi() % data_chars.size()])
		cols.append({"x": xs[i], "y": -rng.randf() * size.y, "v": 120.0 + rng.randf() * 140.0, "c": chars, "sz": 18 + rng.randi() % 8})

func _build_sigil() -> void:
	if screen == null: return
	ws = screen.worlds()
	if ws.is_empty(): return
	var first: Dictionary = ws.values()[0]
	var bb := Rect2(Vector2(first.x, first.y), Vector2.ZERO)
	for w in ws.values(): bb = bb.expand(Vector2(w.x, w.y))
	bb = bb.grow(70)
	var fit := R * RING_R[5] * 1.85
	sig_k = minf(fit / bb.size.x, fit / bb.size.y)
	sig_center = bb.get_center()
	# light order: cores first, then outward (breadth first, same as the card's lit sequence)
	var frontier: Array = screen.draft.parts.filter(func(p): return screen.defp(p.partId).kind == "core" or not screen._attached(p))
	var seen := {}
	while not frontier.is_empty():
		var nxt: Array = []
		for p in frontier:
			var id := str(p.id)
			if seen.has(id): continue
			seen[id] = true; part_ids.append(id)
			nxt.append_array(screen._children(id))
		frontier = nxt

func _snap(times: Array[float], onsets: Array, tol: float, floor_t: float) -> Array[float]:
	var used := {}
	var out: Array[float] = []
	var prev := floor_t
	for g in times:
		var best := g; var bd := tol
		for o in onsets:
			var of := float(o)
			if used.has(of) or of <= prev + 0.12: continue
			if absf(of - g) < bd: bd = absf(of - g); best = of
		if best != g: used[best] = true
		best = maxf(best, prev + 0.12)
		out.append(best); prev = best
	return out

func _onsets(role: String) -> Array[float]:
	## hits of one clip, as times on the whole sequence
	var out: Array[float] = []
	for o in seg[role].onsets: out.append(float(seg[role].start) + float(o))
	return out

func _build_events() -> void:
	events.clear()
	var all: Array[float] = []
	for role in ORDER: all.append_array(_onsets(role))
	# rings draw on from the click until the later of 2 / 3 comes in (R1)
	var grid: Array[float] = []
	for k in range(6): grid.append(lerpf(0.45, R1 - 0.55, k / 5.0))
	ring_t = _snap(grid, all, 0.3, 0.0)
	for k in range(6): events.append({"t": ring_t[k], "kind": "ring", "i": k})
	# the player's glyphs light on the hits of 2 / 3 between R1 and the gathering
	var a_peak := A_PEAK
	var mid: Array[float] = []
	mid.append_array(_onsets("loop_a")); mid.append_array(_onsets("loop_b"))
	mid.sort()
	var n := part_ids.size()
	if n > 0:
		var pg: Array[float] = []
		for i in range(n): pg.append(lerpf(R1 + 0.3, B0 - 0.2, (i / float(n - 1)) if n > 1 else 0.0))
		var pt := _snap(pg, mid, 0.3, R1)
		for i in range(n):
			part_t[part_ids[i]] = pt[i]
			events.append({"t": pt[i], "kind": "rune", "i": i})
	# every hit of 03/04/05 flashes a ring; the click hits and 04's climax send a shock ring
	for o in _onsets("click"): events.append({"t": o, "kind": "spark" if o < 1.0 else "pulse", "i": 0})
	for o in mid:
		if o < T - 0.05: events.append({"t": o, "kind": "pulse", "i": 0})
	events.append({"t": R1, "kind": "spark", "i": 0})        # the second build-up comes in
	if a_peak < T - 0.08: events.append({"t": a_peak, "kind": "spark", "i": 0})    # 2's climax
	events.append({"t": T, "kind": "seal", "i": 0})
	events.append({"t": T + 0.75, "kind": "title", "i": 0})
	events.append({"t": END + 0.05, "kind": "end", "i": 0})
	events.sort_custom(func(a, b): return a.t < b.t)
	_next_ev = 0

# ------------------------------------------------------------------ clock + events
func _e(at: float) -> float:
	## loudness (0..1) at sequence time `at`: the loudest of the clips sounding then (2 and 3 overlap)
	var best := 0.0
	for role in ORDER:
		var s: Dictionary = seg.get(role, {})
		if s.is_empty() or at < float(s.start) or at >= float(s.start) + float(s.dur): continue
		var env: PackedFloat32Array = s.env
		var v := 0.6 if env.is_empty() else env[clampi(int((at - float(s.start)) * float(s.fps)), 0, env.size() - 1)]
		best = maxf(best, v)
	return best

func _process(d: float) -> void:
	if not _playing: return
	_clock += d
	if not _skipped:
		var a := UiHub.workshop_activation_time()
		if a >= 0.0 and absf(a - _clock) < 0.5: _clock = a    # follow the music as heard
	t = maxf(t, _clock)
	while _next_ev < events.size() and t >= float(events[_next_ev].t):
		_fire(events[_next_ev]); _next_ev += 1
	if _ended: return
	_step(d)
	queue_redraw(); add.queue_redraw()

## Visual beats only: the four music clips are the only sound (no effect sounds here).
func _fire(ev: Dictionary) -> void:
	if _skipped and float(ev.t) < T and String(ev.kind) in ["pulse", "spark", "rune", "ring"]:
		# skipped: no pile-up of old beats, just mark the glyph natures lit
		if String(ev.kind) == "rune" and screen:
			var pp: Dictionary = screen._node(part_ids[ev.i])
			if not pp.is_empty(): nature_lit[str(screen.defp(pp.partId).nature)] = t
		return
	match String(ev.kind):
		"ring":
			pulses.append({"t0": t, "r": R * RING_R[ev.i], "big": false, "age": 0.0})
		"rune":
			var id: String = part_ids[ev.i]
			var p: Dictionary = screen._node(id) if screen else {}
			if not p.is_empty(): nature_lit[str(screen.defp(p.partId).nature)] = t
			var sp := _sig_pos(id)
			for k in range(10):
				var a := rng.randf() * TAU
				burst.append({"p": sp, "v": Vector2.from_angle(a) * rng.randf_range(60, 200), "age": 0.0, "life": rng.randf_range(0.4, 0.8), "s": 2.0, "trail": []})
		"pulse":
			pulses.append({"t0": t, "r": R * RING_R[rng.randi() % 6], "big": false, "age": 0.0})
		"spark":
			pulses.append({"t0": t, "r": 0.0, "big": true, "age": 0.0})
		"seal":
			_do_seal()
		"end":
			_ended = true; _playing = false
			finished.emit()

func _do_seal() -> void:
	if _sealed: return
	_sealed = true
	t = maxf(t, T); _clock = t
	sealed.emit()
	UiHub.haptic(40)
	pulses.append({"t0": t, "r": 0.0, "big": true, "age": 0.0})
	for i in range(150):
		var a := rng.randf() * TAU
		burst.append({"p": C, "v": Vector2.from_angle(a) * rng.randf_range(160, 980), "age": 0.0, "life": rng.randf_range(0.9, 2.0),
			"s": rng.randf_range(1.6, 4.2), "trail": []})

## Before the seal: cut to it (the sequence stops, only 06 plays). After it: close now.
func skip() -> void:
	if _ended: return
	if not _sealed:
		_skipped = true
		UiHub.skip_workshop_activation()
		# every ring and glyph is already lit at the seal; events before T fire this frame
		_clock = T; t = T
	elif t < END - 0.4:
		_clock = END - 0.4; t = _clock
func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
		skip(); accept_event()

func _unhandled_key_input(e: InputEvent) -> void:
	if e.is_pressed() and not e.is_echo() and (e.is_action("ui_accept") or e.is_action("ui_cancel")):
		skip(); get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ simulation
func _conv() -> float:
	# rises from G0 to 2's climax (or to 4), then holds until 4 seals
	return clampf((t - B0) / maxf(A_PEAK - B0, 0.4), 0.0, 1.0) if not _sealed else 0.0

func _step(d: float) -> void:
	var e := _e(t)
	var conv := _conv()
	var speed := [0.05, -0.08, 0.11, -0.06, 0.16, -0.12]
	for k in range(6):
		ring_rot[k] += d * float(speed[k]) * (1.0 + 2.6 * conv + (6.0 if _sealed else 0.0))
	for p in pulses: p.age = t - float(p.t0)
	pulses = pulses.filter(func(p): return p.age < (1.0 if p.big else 0.7))
	# data packets down the conduits
	var conduits_on := t > ring_t[5] + 0.25 and not _sealed
	if conduits_on:
		_pkt_acc += d * (5.0 + 34.0 * e)
		while _pkt_acc >= 1.0 and packets.size() < 90:
			_pkt_acc -= 1.0
			packets.append({"k": rng.randi() % 8, "u": 0.0, "v": rng.randf_range(0.9, 1.5) * (1.0 + conv * 1.5)})
	for q in packets: q.u += d * q.v
	packets = packets.filter(func(q): return q.u < 1.0 and not _sealed)
	# data columns
	for c in cols:
		c.y += d * c.v * (1.0 + 1.5 * e)
		if c.y > size.y + 60: c.y = -c.c.size() * float(c.sz) * 1.2; c.c[rng.randi() % c.c.size()] = data_chars[rng.randi() % data_chars.size()]
		if rng.randf() < d * 6.0: c.c[rng.randi() % c.c.size()] = data_chars[rng.randi() % data_chars.size()]
	# converging motes
	if conv > 0.0:
		var want := int(30 + 120 * conv)
		while motes.size() < want:
			var a := rng.randf() * TAU
			motes.append({"p": C + Vector2.from_angle(a) * R * rng.randf_range(0.9, 1.5), "s": rng.randf_range(1.2, 3.2), "k": rng.randf_range(2.0, 4.5)})
	for m in motes:
		m.p = m.p.lerp(C, minf(1.0, d * float(m.k) * (1.0 + 2.0 * conv)))
	motes = motes.filter(func(m): return m.p.distance_to(C) > 10.0 and not _sealed)
	# burst particles (seal + glyph sparks)
	for b in burst:
		b.age += d
		b.trail.append(b.p)
		if b.trail.size() > 7: b.trail.remove_at(0)
		b.p += b.v * d; b.v *= pow(0.12, d)
		b.p.y -= 12.0 * d
	burst = burst.filter(func(b): return b.age < b.life)

# ------------------------------------------------------------------ drawing helpers
func _glow(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r <= 0.5 or col.a <= 0.002: return
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.12), Color(1, 1, 1, 0)])
		_glow_tex = GradientTexture2D.new(); _glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5); _glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128; _glow_tex.height = 128
	ci.draw_texture_rect(_glow_tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false, col)

func _prog(k: int) -> float:
	## draw-on progress of ring k (0..1), eased
	var u := clampf((t - ring_t[k]) / 0.55, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 3.0)

func _geo() -> Dictionary:
	## global scale + alpha of the circle
	var s := 1.0; var a := 1.0
	if t < 0.5: s = lerpf(1.12, 1.0, 1.0 - pow(1.0 - t / 0.5, 3.0))
	var conv := _conv()
	if conv > 0.0: s *= lerpf(1.0, 0.9, conv * conv)
	if _sealed:
		var q := clampf((t - T) / 0.45, 0.0, 1.0)
		s = lerpf(0.9, 0.22, q * q); a = 1.0 - q
	return {"s": s, "a": a}

func _fade() -> float:
	var f := clampf(t / 0.35, 0.0, 1.0)
	if t > END - 0.4: f *= 1.0 - clampf((t - END + 0.4) / 0.4, 0.0, 1.0)
	return f

func _arc_on(ci: CanvasItem, c: Vector2, r: float, a0: float, p: float, col: Color, w: float, seg := 96) -> void:
	if p <= 0.0: return
	var n := maxi(4, int(seg * p))
	var pts := PackedVector2Array()
	for i in range(n + 1): pts.append(c + Vector2.from_angle(a0 + TAU * p * i / n) * r)
	ci.draw_polyline(pts, col, w, true)

func _poly_on(ci: CanvasItem, pts: PackedVector2Array, p: float, col: Color, w: float) -> void:
	if p <= 0.0 or pts.size() < 2: return
	var total := 0.0
	for i in range(pts.size() - 1): total += pts[i].distance_to(pts[i + 1])
	var want := total * p
	var line := PackedVector2Array([pts[0]])
	for i in range(pts.size() - 1):
		var dd := pts[i].distance_to(pts[i + 1])
		if want <= dd: line.append(pts[i].lerp(pts[i + 1], want / maxf(dd, 0.001))); break
		line.append(pts[i + 1]); want -= dd
	if line.size() >= 2: ci.draw_polyline(line, col, w, true)

func _ngon(c: Vector2, r: float, n: int, rot: float, step := 1) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n + 1): pts.append(c + Vector2.from_angle(rot + TAU * float((i * step) % n) / n - PI * 0.5) * r)
	return pts

func _rune(ci: CanvasItem, idx: int, c: Vector2, s: float, rot: float, col: Color) -> void:
	var r: Dictionary = runes[idx % runes.size()]
	for st in r.s:
		var pts := PackedVector2Array()
		for q in st: pts.append(c + (q as Vector2).rotated(rot) * s)
		ci.draw_polyline(pts, col, 1.3, true)
	if r.o: ci.draw_arc(c, s * 1.35, 0, TAU, 16, Color(col, col.a * 0.7), 1.0, true)

func _sig_pos(id: String) -> Vector2:
	var w: Dictionary = ws.get(id, {})
	if w.is_empty(): return C
	return C + (Vector2(w.x, w.y) - sig_center) * sig_k

func _lit(id: String) -> float:
	if _sealed: return 1.0
	if not part_t.has(id): return 0.0
	return clampf((t - float(part_t[id])) / 0.25, 0.0, 1.0)

# ------------------------------------------------------------------ draw: veil, lines, text (normal blend)
func _draw() -> void:
	if not _playing and not _ended: return
	var f := _fade()
	var night := UiHub.night
	var veil := Color(0.035, 0.03, 0.06).lerp(Color(0.012, 0.012, 0.028), night)
	draw_rect(Rect2(Vector2.ZERO, size), Color(veil, 0.95 * f))
	var acc := UiHub.c("accent")
	var silver := Color(0.86, 0.84, 0.95)
	var e := _e(t)
	var geo := _geo()
	var gs: float = geo.s; var ga: float = geo.a * f
	var bright := 0.55 + 0.45 * e
	# data columns
	var col_a := clampf((t - R1 + 0.3) / 1.2, 0.0, 1.0) * f * (0.25 + 0.35 * e) * (1.0 - clampf((t - T) / 0.5, 0.0, 1.0))
	if col_a > 0.01:
		var font := Kit.font(500)
		for c in cols:
			var sz: int = c.sz
			for i in range(c.c.size()):
				var y: float = c.y + i * sz * 1.2
				if y < -sz or y > size.y + sz: continue
				var head: float = float(i) / float(c.c.size())
				var ccol := silver.lerp(acc, 0.35 if i == c.c.size() - 1 else 0.0)
				draw_char(font, Vector2(c.x - sz * 0.5, y), String(c.c[i]), sz, Color(ccol, col_a * (0.25 + 0.75 * head)))
	if ga <= 0.01: return
	var s := R * gs
	# ring 0: double circle + 72 ticks
	var p0 := _prog(0)
	if p0 > 0.0:
		var r0 := s * RING_R[0]
		_arc_on(self, C, r0, -PI * 0.5 + ring_rot[0], p0, Color(silver, 0.75 * ga * bright), 1.4, 128)
		_arc_on(self, C, r0 - 12.0 * gs, PI * 0.5 + ring_rot[0], p0, Color(silver, 0.45 * ga), 1.0, 128)
		for i in range(int(72 * p0)):
			var a := ring_rot[0] + TAU * i / 72.0
			var L := (10.0 if i % 6 == 0 else 5.0) * gs
			draw_line(C + Vector2.from_angle(a) * (r0 - 12.0 * gs), C + Vector2.from_angle(a) * (r0 - 12.0 * gs - L), Color(silver, 0.5 * ga), 1.0, true)
		for i in range(4):
			var a := ring_rot[0] + TAU * i / 4.0 - PI * 0.5
			if p0 > i / 4.0: Kit.star4(self, C + Vector2.from_angle(a) * r0, 9.0 * gs, Color(acc, ga), 0.16, a)
	# ring 1: rune band
	var p1 := _prog(1)
	if p1 > 0.0:
		var r1 := s * RING_R[1]
		_arc_on(self, C, r1 + 16.0 * gs, ring_rot[1], p1, Color(silver, 0.35 * ga), 1.0)
		_arc_on(self, C, r1 - 16.0 * gs, ring_rot[1] + PI, p1, Color(silver, 0.35 * ga), 1.0)
		for i in range(int(24 * p1)):
			var a := ring_rot[1] + TAU * i / 24.0
			_rune(self, i, C + Vector2.from_angle(a) * r1, 7.0 * gs, a + PI * 0.5, Color(silver, 0.8 * ga * bright))
	# ring 2: dashed circle + hexagram
	var p2 := _prog(2)
	if p2 > 0.0:
		var r2 := s * RING_R[2]
		var nd := 60
		for i in range(int(nd * p2)):
			if i % 2 == 0: draw_arc(C, r2, ring_rot[2] + TAU * i / nd, ring_rot[2] + TAU * (i + 1) / nd, 4, Color(silver, 0.45 * ga), 1.0, true)
		_poly_on(self, _ngon(C, r2, 3, ring_rot[2]), p2, Color(acc, 0.85 * ga * bright), 1.5)
		_poly_on(self, _ngon(C, r2, 3, ring_rot[2] + PI), p2, Color(acc, 0.85 * ga * bright), 1.5)
	# ring 3: the eight natures (light up in their tone when a glyph of that nature lights)
	var p3 := _prog(3)
	if p3 > 0.0:
		var r3 := s * RING_R[3]
		_arc_on(self, C, r3, ring_rot[3], p3, Color(silver, 0.5 * ga), 1.0)
		var font3 := Kit.font(600)
		for i in range(int(8 * p3 + 0.001)):
			var nat: String = NATURES[i]
			var a := ring_rot[3] + TAU * i / 8.0 - PI * 0.5
			var pos := C + Vector2.from_angle(a) * (r3 + 26.0 * gs)
			var lit_t: float = float(nature_lit.get(nat, -99.0))
			var on := clampf((t - lit_t) / 0.3, 0.0, 1.0) if lit_t > -90.0 else 0.0
			var tc := silver.lerp(Color(TONE[nat]), on)
			var fs := int(20 * gs + 4)
			draw_set_transform(pos, a + PI * 0.5, Vector2.ONE)
			draw_string(font3, Vector2(-fs, fs * 0.35), nat, HORIZONTAL_ALIGNMENT_CENTER, fs * 2.0, fs, Color(tc, (0.5 + 0.5 * on) * ga))
			draw_set_transform(Vector2.ZERO)
			draw_circle(C + Vector2.from_angle(a + TAU / 16.0) * r3, 2.2, Color(acc, ga))
	# ring 4: octagram (two squares)
	var p4 := _prog(4)
	if p4 > 0.0:
		var r4 := s * RING_R[4]
		_poly_on(self, _ngon(C, r4, 4, ring_rot[4]), p4, Color(silver, 0.7 * ga * bright), 1.2)
		_poly_on(self, _ngon(C, r4, 4, ring_rot[4] + PI * 0.25), p4, Color(silver, 0.7 * ga * bright), 1.2)
		_arc_on(self, C, r4 * 0.707, -ring_rot[4], p4, Color(acc, 0.5 * ga), 1.0)
	# ring 5: bead ring + circling blueprint text (the data the sigil is made of)
	var p5 := _prog(5)
	if p5 > 0.0:
		var r5 := s * RING_R[5]
		_arc_on(self, C, r5, ring_rot[5], p5, Color(silver, 0.6 * ga), 1.2)
		for i in range(int(12 * p5)):
			var a := ring_rot[5] + TAU * i / 12.0
			draw_arc(C + Vector2.from_angle(a) * r5, 4.0 * gs, 0, TAU, 12, Color(acc, 0.8 * ga), 1.2, true)
		var font5 := Kit.font(500)
		var nch := ring_text.length()
		var shown := int(nch * p5)
		var fs5 := maxi(9, int(13 * gs))
		for i in range(shown):
			var a := -ring_rot[5] * 1.6 + TAU * i / nch
			var pos := C + Vector2.from_angle(a) * (r5 - 18.0 * gs)
			draw_set_transform(pos, a + PI * 0.5, Vector2.ONE)
			draw_char(font5, Vector2(-fs5 * 0.5, fs5 * 0.35), ring_text[i], fs5, Color(silver, 0.45 * ga * bright))
		draw_set_transform(Vector2.ZERO)
		# 8 conduits from the outer ring into the bead ring
		if t > ring_t[5] + 0.2:
			var ca := clampf((t - ring_t[5] - 0.2) / 0.5, 0.0, 1.0) * ga
			for k in range(8):
				var a := ring_rot[0] + TAU * k / 8.0 + TAU / 16.0
				Kit.line_fade(self, C + Vector2.from_angle(a) * s * RING_R[0], C + Vector2.from_angle(a) * r5, Color(silver, 0.5 * ca), 1.0)
	# the player's sigil: links + glyphs, lit one by one
	_draw_sigil(self, gs, ga, acc, silver, veil)

func _draw_sigil(ci: CanvasItem, gs: float, ga: float, acc: Color, ink: Color, hole: Color) -> void:
	if screen == null or ws.is_empty(): return
	var stamp := 1.0
	var sa := ga
	if _sealed:
		var q := clampf((t - T) / 0.35, 0.0, 1.0)
		stamp = lerpf(1.25, 1.0, 1.0 - pow(1.0 - q, 3.0)); sa = _fade()
		gs = 1.0
	var k := sig_k * gs * stamp
	var sc: float = screen.cat().scale
	for p in screen.draft.parts:
		if not screen._attached(p): continue
		var par: Dictionary = screen._node(str(p.parent))
		var a: Vector2 = C + (screen.world_port(ws[str(par.id)], screen.defp(par.partId), str(p.slot)) - sig_center) * k
		var b: Vector2 = C + (screen.world_port(ws[str(p.id)], screen.defp(p.partId), str(p.get("plug", "root"))) - sig_center) * k
		var lv := _lit(str(p.id))
		ci.draw_line(a, b, Color(ink, 0.35 * sa).lerp(Color(acc, sa), lv), 1.2 + lv, true)
	for p in screen.draft.parts:
		var id := str(p.id)
		var w: Dictionary = ws[id]
		var sp: Vector2 = C + (Vector2(w.x, w.y) - sig_center) * k
		var lv := _lit(id)
		screen.paint_glyph(ci, p.partId, sp, w.a, sc * k, Color(ink, (0.35 + 0.65 * lv) * sa), Color(acc, sa), Color(hole, sa), lv)

# ------------------------------------------------------------------ draw: light (additive)
func _draw_light(ci: CanvasItem) -> void:
	if not _playing and not _ended: return
	var f := _fade()
	var acc := UiHub.c("accent")
	var white := Color(1.0, 0.97, 0.92)
	var e := _e(t)
	var geo := _geo()
	var gs: float = geo.s; var ga: float = geo.a * f
	var conv := _conv()
	# core light breathing with the music
	if not _sealed:
		_glow(ci, C, R * (0.25 + 0.35 * e + 0.4 * conv) * gs, Color(acc, (0.10 + 0.22 * e + 0.3 * conv) * f))
		_glow(ci, C, R * (0.08 + 0.1 * e + 0.12 * conv), Color(white, (0.12 + 0.22 * e + 0.4 * conv * conv) * f))
	# pulses (music hits)
	for p in pulses:
		var age: float = p.age
		if p.big:
			var q := clampf(age / 1.0, 0.0, 1.0)
			var rr := lerpf(10.0, R * 1.5, 1.0 - pow(1.0 - q, 2.4))
			ci.draw_arc(C, rr, 0, TAU, 96, Color(white, 0.6 * (1.0 - q) * f), 2.0 + 6.0 * (1.0 - q), true)
			_glow(ci, C, 120.0 + 300.0 * q, Color(white, 0.5 * (1.0 - q) * f))
		else:
			var q2 := clampf(age / 0.7, 0.0, 1.0)
			ci.draw_arc(C, float(p.r) * gs, 0, TAU, 96, Color(acc, 0.45 * (1.0 - q2) * ga), 1.0 + 3.0 * (1.0 - q2), true)
	# conduit packets: data flowing into the centre
	var s := R * gs
	for q in packets:
		var a := ring_rot[0] + TAU * int(q.k) / 8.0 + TAU / 16.0
		var u: float = q.u * q.u
		var r := lerpf(s * RING_R[0], s * RING_R[5], u)
		var pos := C + Vector2.from_angle(a) * r
		var tail := C + Vector2.from_angle(a) * minf(r + 26.0, s * RING_R[0])
		ci.draw_line(tail, pos, Color(acc, 0.5 * ga), 2.0, true)
		ci.draw_circle(pos, 2.4, Color(white, 0.9 * ga))
	# flowing light along the player's lit links
	if screen != null and not ws.is_empty() and not _sealed:
		var k := sig_k * gs
		for p in screen.draft.parts:
			if not screen._attached(p): continue
			var lv := _lit(str(p.id))
			if lv <= 0.0: continue
			var par: Dictionary = screen._node(str(p.parent))
			var a2: Vector2 = C + (screen.world_port(ws[str(par.id)], screen.defp(par.partId), str(p.slot)) - sig_center) * k
			var b2: Vector2 = C + (screen.world_port(ws[str(p.id)], screen.defp(p.partId), str(p.get("plug", "root"))) - sig_center) * k
			var ph := fmod(t * 1.4 + float(hash(str(p.id)) % 100) / 100.0, 1.0)
			ci.draw_circle(a2.lerp(b2, ph), 2.6, Color(white, 0.8 * lv * ga))
		for id in part_ids:
			var lv2 := _lit(id)
			if lv2 > 0.0: _glow(ci, _sig_pos_k(id, k), 34.0 * gs, Color(acc, 0.35 * lv2 * ga * (0.7 + 0.3 * e)))
	# converge: rays + motes
	if conv > 0.0:
		for i in range(20):
			var a := TAU * i / 20.0 + t * 0.6
			var L := R * (0.4 + 0.5 * float((i * 7) % 5) / 4.0) * conv
			Kit.line_fade(ci, C, C + Vector2.from_angle(a) * L, Color(white, 0.35 * conv * f), 1.6, 8)
	for m in motes:
		ci.draw_circle(m.p, m.s, Color(white, 0.8 * f))
		_glow(ci, m.p, m.s * 4.0, Color(acc, 0.25 * f))
	# seal: flash, cross light, stamp glow
	if _sealed:
		var q := t - T
		var fl := exp(-q * 5.0)
		ci.draw_rect(Rect2(Vector2.ZERO, size), Color(white, 0.75 * fl))
		var cr := exp(-q * 2.2) * f
		var h := 2.0 + 10.0 * exp(-q * 6.0)
		ci.draw_rect(Rect2(0, C.y - h * 0.5, size.x, h), Color(white, 0.55 * cr))
		ci.draw_rect(Rect2(C.x - h * 0.5, 0, h, size.y), Color(white, 0.55 * cr))
		_glow(ci, C, R * 0.9, Color(acc, 0.35 * f * (0.6 + 0.4 * exp(-q * 1.5))))
		_glow(ci, C, R * 0.35, Color(white, 0.25 * f))
		# a clean seal circle around the stamped sigil
		var ring_r := R * RING_R[5] * 1.15
		var rq := clampf(q / 0.5, 0.0, 1.0)
		ci.draw_arc(C, ring_r, -PI * 0.5, -PI * 0.5 + TAU * (1.0 - pow(1.0 - rq, 3.0)), 96, Color(acc, 0.9 * f), 2.0, true)
		Kit.crescent(ci, C, ring_r + 10.0, -PI * 0.45, PI * 0.2, 5.0, Color(acc, 0.8 * f * rq))
		Kit.star4(ci, C + Vector2(0, -ring_r), 12.0 * rq, Color(white, f), 0.16)
	for b in burst:
		var q3: float = b.age / b.life
		var col := white.lerp(acc, q3)
		if b.trail.size() >= 2:
			var tr := PackedVector2Array(b.trail); tr.append(b.p)
			ci.draw_polyline(tr, Color(col, 0.35 * (1.0 - q3) * f), b.s * 0.6, true)
		ci.draw_circle(b.p, b.s * (1.0 - q3 * 0.5), Color(col, (1.0 - q3) * f))
	# name
	if _sealed and t > T + 0.75:
		var tq := clampf((t - T - 0.75) / 0.4, 0.0, 1.0)
		var ty := C.y + R * 0.62 + 20.0 * (1.0 - tq)
		var font := Kit.font(600)
		var nm := "【" + (title if title != "" else "未命名刻印") + "】"
		ci.draw_string(font, Vector2(0, ty), "刻 印 铭 成", HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(acc, 0.9 * tq * f))
		ci.draw_string(font, Vector2(0, ty + 58), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color(white, tq * f))

func _sig_pos_k(id: String, k: float) -> Vector2:
	var w: Dictionary = ws.get(id, {})
	if w.is_empty(): return C
	return C + (Vector2(w.x, w.y) - sig_center) * k
