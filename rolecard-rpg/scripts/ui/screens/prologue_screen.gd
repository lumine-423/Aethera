extends "res://scripts/ui/ui_screen.gd"
## 开场序幕（Prologue）：复刻原版角色卡的圣洁极简纯文字序幕，并在「拯救艾瑟拉吧」消散后直接进入主页面（Title Screen）。
## 序幕只保留背景音乐，不触发动画或按钮音效。
## 完整流程：
##   阶段一（phase = "mode"）：选择昼夜（「请选择昼夜模式 / （后续可随时更改）」+ 「昼」「夜」双菱形按钮，支持悬停预览与点击碎裂转场）
##   阶段二（phase = "intro"）：纯文字序幕动画（无多余几何装饰，仅纯净画布 + 微尘 + 文字本身）：
##     1. 呼唤短句（callPhrases，24次金/绯红微光短句漂移与双闪烁）
##     2. 中心独白（bigLines，5句居中正文逐句浮现消隐，末句「请你」小字收束）
##     3. 终句破碎（finalLine「拯救艾瑟拉吧」逐字显现 → 冲击震屏 → 逐字旋转碎裂 → 柔雾拂过 → 直接进入主页面）

const T_BIG_START := 4.70
const T_BIG_STEP := 2.50
const T_BIG_DUR := 3.10
const T_BIG_START_REDUCED := 0.25
const T_BIG_STEP_REDUCED := 1.25
const T_BIG_DUR_REDUCED := 1.15

const COL_DAY_CENTER := Color("f8f7f2")
const COL_DAY_MID := Color("f1f0e8")
const COL_DAY_EDGE := Color("e9e8de")
const COL_NIGHT_CENTER := Color("1c141c")
const COL_NIGHT_MID := Color("120c14")
const COL_NIGHT_EDGE := Color("0c0810")
const COL_INK_DAY := Color("1a1614")
const COL_INK_NIGHT := Color("f4efe6")
const COL_SUB_DAY := Color("5a524c")
const COL_SUB_NIGHT := Color("c9bfb4")
const COL_GOLD := Color("d4b36a")
const COL_CRIMSON := Color("c3272b")

var phase := "mode"           # "mode" (选择昼夜) | "intro" (纯文字动画)
var mode_elapsed := 0.0
var mode_shattering := false
var mode_shatter_t := 0.0
var preview_night := 0.0
var preview_target := 0.0
var active_pick := "day"      # "day" | "night"

var elapsed := 0.0
var _leaving := false
var _test_frozen := false

var mode_title := "请选择昼夜模式\n（后续可随时更改）"
var mode_day_text := "昼"
var mode_night_text := "夜"
var call_phrases: Array = []
var big_lines: Array = []
var final_line := "拯救艾瑟拉吧"

var dust_specs: Array = []
var mode_char_specs: Array = []
var whisper_specs: Array = []
var char_specs: Array = []
var mist_specs: Array = []

var stage_holder: Control
var sacred_stage: PrologueStage
var pick_day_btn: Button
var pick_night_btn: Button
var skip_btn: Button


class PrologueStage extends Control:
	var owner_screen
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiHub.palette_changed.connect(queue_redraw)
	func _draw() -> void:
		if owner_screen == null: return
		owner_screen._draw_stage(self)


class ModeDiamondBtn extends Button:
	var label_text := "昼"
	var is_night_btn := false
	var owner_screen
	var hover_mix := 0.0
	func _init(txt: String, night_btn: bool, scr) -> void:
		label_text = txt
		is_night_btn = night_btn
		owner_screen = scr
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func _ready() -> void:
		mouse_entered.connect(func():
			if owner_screen and owner_screen.phase == "mode" and not owner_screen.mode_shattering:
				owner_screen._set_mode_preview(is_night_btn))
		focus_entered.connect(func():
			if owner_screen and owner_screen.phase == "mode" and not owner_screen.mode_shattering:
				owner_screen._set_mode_preview(is_night_btn))
		pressed.connect(func():
			if owner_screen:
				owner_screen.pick_mode(is_night_btn))
	func _process(d: float) -> void:
		var target := 1.0 if (is_hovered() or has_focus()) else 0.0
		hover_mix = move_toward(hover_mix, target, d * 6.0)
		queue_redraw()
	func _draw() -> void:
		if owner_screen == null or owner_screen.phase != "mode": return
		owner_screen._draw_mode_diamond(self, is_night_btn, label_text, hover_mix)


class MinimalSkipBtn extends Button:
	var label_text := "跳过"
	var owner_screen
	var hover_mix := 0.0
	func _init(txt: String, scr) -> void:
		label_text = txt
		owner_screen = scr
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	func _process(d: float) -> void:
		var target := 1.0 if (is_hovered() or has_focus()) else 0.0
		hover_mix = move_toward(hover_mix, target, d * 6.0)
		queue_redraw()
	func _draw() -> void:
		if owner_screen == null: return
		var K = preload("res://scripts/ui/ui_kit.gd")
		var n: float = owner_screen.preview_night
		var r := Rect2(Vector2.ZERO, size)
		var bg := Color(1.0, 0.99, 0.97, lerpf(0.55, 0.85, hover_mix)).lerp(Color(0.11, 0.08, 0.14, lerpf(0.55, 0.85, hover_mix)), n)
		var bd := COL_INK_DAY.lerp(COL_INK_NIGHT, n)
		bd.a = lerpf(0.18, 0.48, hover_mix)
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.border_color = bd
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(999)
		draw_style_box(sb, r)
		var tc := COL_SUB_DAY.lerp(COL_SUB_NIGHT, n).lerp(COL_INK_DAY.lerp(COL_INK_NIGHT, n), hover_mix)
		tc.a = lerpf(0.76, 1.0, hover_mix)
		K.text(self, r, label_text, UiHub.fs(20), tc, HORIZONTAL_ALIGNMENT_CENTER, 700)


func open(owner_root: Node, p: Dictionary) -> void:
	uses_backdrop = false
	super.open(owner_root, p)
	_load_copy()
	_build_schedule()
	preview_target = 1.0 if UiHub.night_target else 0.0
	preview_night = preview_target
	active_pick = "night" if UiHub.night_target else "day"
	if String(p.get("phase", "")) == "intro":
		phase = "intro"
		elapsed = float(p.get("time", 0.0))
	else:
		phase = "mode"
		mode_elapsed = 0.0
		mode_shattering = false
		mode_shatter_t = 0.0


func _load_copy() -> void:
	var content: Dictionary = Data.content()
	var op: Dictionary = content.get("opening", {})
	mode_title = String(op.get("modeTitle", "请选择昼夜模式\n（后续可随时更改）"))
	mode_day_text = String(op.get("modeDay", "昼"))
	mode_night_text = String(op.get("modeNight", "夜"))
	call_phrases = op.get("callPhrases", [
		"去拯救吧", "我始终相信你是英雄", "献上你的觉悟", "你愿意见证吗",
		"来向我证明你做得到啊", "我一直相信着你", "这是你的觉悟吗", "见证这一切吧",
		"别再犹豫了", "那种事情我办不到", "回答我", "还来得及吗", "以艾瑟拉之名", "觉悟的时刻到了"
	])
	var key := "bigLinesReduced" if UiHub.reduced_motion else "bigLines"
	big_lines = op.get(key, [
		"没想到会以这样的方式与你相见",
		"这次你又会带来怎样的故事呢",
		"看起来，时间不够了",
		"这次，我依然祝你一路顺风",
		"请你"
	])
	final_line = String(op.get("finalLine", "拯救艾瑟拉吧"))


func _build_schedule() -> void:
	dust_specs.clear()
	mode_char_specs.clear()
	whisper_specs.clear()
	char_specs.clear()
	mist_specs.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112

	# 24 subtle floating dust motes (#soDust i)
	for i in range(24):
		dust_specs.append({
			"pos": Vector2(rng.randf_range(60.0, 1860.0), rng.randf_range(50.0, 1030.0)),
			"r": rng.randf_range(1.6, 3.8),
			"phase": rng.randf_range(0.0, TAU),
			"speed": rng.randf_range(0.65, 1.15),
		})

	# Per-character specs for modeTitle ("请选择昼夜模式\n（后续可随时更改）")
	var m_lines := mode_title.split("\n")
	var m_idx := 0
	for li in range(m_lines.size()):
		var ln := String(m_lines[li])
		var n_ln := ln.length()
		var is_sub := li > 0
		var step_x := 36.0 if is_sub else 54.0
		var base_y := 468.0 if is_sub else 404.0
		var start_x := 960.0 - float(n_ln - 1) * step_x * 0.5
		for ci in range(n_ln):
			var sx := rng.randf_range(-110.0, 110.0)
			var sy := (-45.0 - rng.randf_range(35.0, 110.0)) if (m_idx % 2 == 0) else (45.0 + rng.randf_range(35.0, 110.0))
			var sr := deg_to_rad(rng.randf_range(-95.0, 95.0))
			mode_char_specs.append({
				"ch": ln.substr(ci, 1),
				"sub": is_sub,
				"pos": Vector2(start_x + float(ci) * step_x, base_y),
				"bd": float(m_idx) * 0.055,
				"sd": rng.randf_range(0.0, 0.08),
				"sx": sx,
				"sy": sy,
				"sr": sr,
			})
			m_idx += 1

	# 24 whispers in 4 waves matching original card: [[6, 0.30], [6, 0.20], [6, 0.14], [6, 0.08]]
	var waves := [[6, 0.30, 0.00], [6, 0.20, 1.60], [6, 0.14, 2.70], [6, 0.08, 3.40]]
	var idx := 0
	var order := [0, 7, 3, 12, 1, 9, 5, 13, 2, 10, 4, 11, 6, 8, 12, 0, 5, 1, 13, 3, 8, 2, 11, 6]
	for w_idx in range(waves.size()):
		var w: Array = waves[w_idx]
		var count: int = w[0]
		var gap: float = w[1]
		var t_wave: float = w[2]
		for k in range(count):
			var p_idx: int = order[idx % order.size()] % max(call_phrases.size(), 1)
			# Distribute whispers organically across the screen (8%..78% X, 10%..84% Y) like original card
			var ang := idx * 2.3999632 + rng.randf_range(-0.22, 0.22)
			var rad_x := lerpf(160.0, 680.0, fmod(idx * 0.39 + rng.randf_range(0.0, 0.22), 1.0))
			var rad_y := lerpf(110.0, 380.0, fmod(idx * 0.53 + rng.randf_range(0.0, 0.22), 1.0))
			var start_pos := Vector2(960.0 + cos(ang) * rad_x, 510.0 + sin(ang) * rad_y)
			var drift := Vector2(rng.randf_range(-44.0, 44.0), rng.randf_range(-28.0, 28.0))
			if drift.length() < 18.0:
				drift = Vector2(28.0 if idx % 2 == 0 else -28.0, -16.0)
			var is_acc := (idx % 3 == 0)
			whisper_specs.append({
				"text": String(call_phrases[p_idx]),
				"t0": t_wave + float(k) * gap,
				"life": rng.randf_range(1.15, 1.75),
				"pos": start_pos,
				"drift": drift,
				"px": rng.randi_range(22, 28) if not is_acc else rng.randi_range(26, 33),
				"accent": is_acc,
				"wave": w_idx,
			})
			idx += 1

	# Final line ("拯救艾瑟拉吧") per-character reveal & shatter specs
	var n_chars := final_line.length()
	var step_f := 88.0
	var start_fx := 960.0 - float(n_chars - 1) * step_f * 0.5
	for i in range(n_chars):
		var sx := rng.randf_range(-135.0, 135.0) + (float(i) - float(n_chars - 1) * 0.5) * 32.0
		var sy := (-45.0 - rng.randf_range(40.0, 125.0)) if (i % 2 == 0) else (55.0 + rng.randf_range(40.0, 125.0))
		var sr := deg_to_rad(rng.randf_range(-100.0, 100.0))
		if absf(sr) < 0.30: sr = 0.48 if i % 2 == 0 else -0.48
		char_specs.append({
			"ch": final_line.substr(i, 1),
			"pos": Vector2(start_fx + float(i) * step_f, 496.0),
			"bd": float(i) * 0.055,
			"sd": rng.randf_range(0.0, 0.08),
			"sx": sx,
			"sy": sy,
			"sr": sr,
		})

	# 5 soft mist bands (#soSweep i)
	for i in range(5):
		mist_specs.append({
			"w": rng.randf_range(520.0, 860.0),
			"h": rng.randf_range(130.0, 240.0),
			"y": rng.randf_range(220.0, 720.0),
			"dur": rng.randf_range(1.65, 2.25),
			"delay": float(i) * 0.08,
		})


func _t_big_start() -> float:
	return T_BIG_START_REDUCED if UiHub.reduced_motion else T_BIG_START

func _t_big_step() -> float:
	return T_BIG_STEP_REDUCED if UiHub.reduced_motion else T_BIG_STEP

func _t_big_dur() -> float:
	return T_BIG_DUR_REDUCED if UiHub.reduced_motion else T_BIG_DUR

func _t_final() -> float:
	return _t_big_start() + float(big_lines.size()) * _t_big_step()

func _t_finish() -> float:
	return _t_final() + (1.35 if UiHub.reduced_motion else 3.00)


func build() -> void:
	uses_backdrop = false
	_load_copy()
	if whisper_specs.is_empty():
		_build_schedule()

	stage_holder = Control.new()
	stage_holder.name = "StageHolder"
	stage_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_holder.set_meta("layer", true)
	put(stage_holder, Rect2(0, 0, 1920, 1080), "c")

	sacred_stage = PrologueStage.new()
	sacred_stage.name = "PrologueStage"
	sacred_stage.owner_screen = self
	stage_holder.add_child(sacred_stage)
	sacred_stage.position = Vector2.ZERO
	sacred_stage.size = Vector2(1920, 1080)

	# Phase 1: Two rotated diamond buttons ("昼" and "夜")
	pick_day_btn = ModeDiamondBtn.new(mode_day_text, false, self)
	pick_day_btn.name = "PickDay"
	put(pick_day_btn, Rect2(800, 536, 136, 136), "c", -1.0)

	pick_night_btn = ModeDiamondBtn.new(mode_night_text, true, self)
	pick_night_btn.name = "PickNight"
	put(pick_night_btn, Rect2(984, 536, 136, 136), "c", -1.0)

	# Phase 2: Minimalist bottom-right Skip pill button (#soSkipBtn)
	var hub: Dictionary = Data.content().get("hub", {})
	skip_btn = MinimalSkipBtn.new(String(hub.get("skip", "跳过")), self)
	skip_btn.name = "SkipIntro"
	skip_btn.pressed.connect(func(): skip_to_title())
	put(skip_btn, Rect2(1748, 996, 132, 48), "rb", -1.0)

	_sync_visuals()


func _set_mode_preview(is_night: bool) -> void:
	active_pick = "night" if is_night else "day"
	preview_target = 1.0 if is_night else 0.0


func pick_mode(is_night: bool) -> void:
	if phase != "mode" or mode_shattering or _leaving: return
	active_pick = "night" if is_night else "day"
	preview_target = 1.0 if is_night else 0.0
	UiHub.set_night(is_night, false)
	UiHub.haptic(18)
	if root and root.has_method("_update_music"):
		root._update_music()
	if UiHub.reduced_motion or _test_frozen:
		_start_intro()
	else:
		mode_shattering = true
		mode_shatter_t = 0.0


func _start_intro() -> void:
	phase = "intro"
	mode_shattering = false
	elapsed = 0.0
	_sync_visuals()


func _process(delta: float) -> void:
	if _leaving or _test_frozen: return
	preview_night = move_toward(preview_night, preview_target, delta * 2.2)
	if phase == "mode":
		mode_elapsed += delta
		if mode_shattering:
			mode_shatter_t += delta
			if mode_shatter_t >= 0.88:
				_start_intro()
				return
	else:
		elapsed += delta
		if elapsed >= _t_finish():
			_finish_to_title()
			return
	_sync_visuals()


func set_time_for_test(t: float, test_phase := "intro") -> void:
	_test_frozen = true
	phase = test_phase
	preview_target = 1.0 if UiHub.night_target else 0.0
	preview_night = preview_target
	if phase == "mode":
		mode_elapsed = t
		mode_shattering = false
		mode_shatter_t = 0.0
	else:
		elapsed = t
	for c in get_children():
		if c is Control:
			c.modulate.a = 1.0
			if "reveal" in c: c.reveal = 1.0
	_sync_visuals()


func skip_to_title() -> void:
	if _leaving: return
	_finish_to_title()


func _finish_to_title() -> void:
	if _leaving: return
	_leaving = true
	var nxt := String(params.get("next", "title"))
	if nxt == "title":
		root.go("title", {"phase": "menu"}, "fade", "reset")
	else:
		root.go(nxt, {}, "fade", "reset")


func on_back() -> bool:
	skip_to_title()
	return true


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or _leaving: return
	if phase == "mode" and not mode_shattering:
		if e.is_action("ui_left"):
			_set_mode_preview(false)
			if is_instance_valid(pick_day_btn): pick_day_btn.grab_focus()
			get_viewport().set_input_as_handled()
		elif e.is_action("ui_right"):
			_set_mode_preview(true)
			if is_instance_valid(pick_night_btn): pick_night_btn.grab_focus()
			get_viewport().set_input_as_handled()
		elif e.is_action("ui_accept"):
			pick_mode(active_pick == "night")
			get_viewport().set_input_as_handled()
	elif phase == "intro":
		if e.is_action("ui_accept") or e.is_action("ui_cancel"):
			skip_to_title()
			get_viewport().set_input_as_handled()


func active_whispers() -> Array:
	if phase != "intro" or UiHub.reduced_motion: return []
	var gate := clampf((_t_big_start() - 0.15 - elapsed) / 0.25, 0.0, 1.0)
	if gate <= 0.001: return []
	var out: Array = []
	for w in whisper_specs:
		var u: float = (elapsed - float(w.t0)) / float(w.life)
		if u >= 0.0 and u <= 1.0:
			var a := _gz_alpha(u) * gate
			if a > 0.01:
				out.append({"spec": w, "u": u, "alpha": a})
	return out


func _gz_alpha(u: float) -> float:
	if u < 0.0 or u > 1.0: return 0.0
	if u < 0.07: return lerpf(0.0, 0.95, u / 0.07)
	if u < 0.20: return lerpf(0.95, 0.08, (u - 0.07) / 0.13)
	if u < 0.30: return lerpf(0.08, 0.95, (u - 0.20) / 0.10)
	if u < 0.46: return lerpf(0.95, 0.10, (u - 0.30) / 0.16)
	if u < 0.56: return lerpf(0.10, 0.92, (u - 0.46) / 0.10)
	if u < 0.80: return lerpf(0.92, 0.50, (u - 0.56) / 0.24)
	return lerpf(0.50, 0.0, (u - 0.80) / 0.20)


func current_big_line() -> Dictionary:
	if phase != "intro": return {}
	var t0 := _t_big_start()
	var step := _t_big_step()
	var dur := _t_big_dur()
	for i in range(big_lines.size()):
		var start := t0 + float(i) * step
		# Cleanly end previous line right before the next line starts so two bigLines never overlap
		var next_start := t0 + float(i + 1) * step
		if elapsed < start or elapsed >= next_start: continue
		var u := clampf((elapsed - start) / minf(dur, next_start - start), 0.0, 1.0)
		var a := 1.0
		var y_off := 0.0
		var blur_k := 0.0
		if u < 0.28:
			var k := u / 0.28
			a = smoothstep(0.0, 1.0, k)
			y_off = lerpf(16.0, 0.0, Kit.curve(k))
			blur_k = 1.0 - k
		elif u > 0.70:
			var k := (u - 0.70) / 0.30
			a = 1.0 - smoothstep(0.0, 1.0, k)
			y_off = lerpf(0.0, -20.0, k)
			blur_k = k
		return {"index": i, "text": String(big_lines[i]), "alpha": a, "y_off": y_off, "blur": blur_k, "small": i == big_lines.size() - 1, "u": u}
	return {}


func _sync_visuals() -> void:
	if not is_instance_valid(stage_holder): return
	var in_mode := (phase == "mode")
	var picks_ready := in_mode and (mode_elapsed >= 0.78 or UiHub.reduced_motion or _test_frozen)
	if is_instance_valid(pick_day_btn):
		pick_day_btn.visible = in_mode
		pick_day_btn.disabled = not picks_ready or mode_shattering
		pick_day_btn.queue_redraw()
	if is_instance_valid(pick_night_btn):
		pick_night_btn.visible = in_mode
		pick_night_btn.disabled = not picks_ready or mode_shattering
		pick_night_btn.queue_redraw()
	if is_instance_valid(skip_btn):
		skip_btn.visible = (phase == "intro")
		skip_btn.queue_redraw()

	var shake_off := Vector2.ZERO
	if phase == "intro" and not UiHub.reduced_motion:
		var dt_shake := elapsed - _t_final()
		if dt_shake >= 1.55 and dt_shake < 1.95:
			var sk := (dt_shake - 1.55) / 0.40
			var amp := (1.0 - sk) * 6.0
			shake_off = Vector2(sin(sk * TAU * 4.0) * amp, cos(sk * TAU * 3.0) * amp * 0.6)

	stage_holder.position = at(0, 0, "c") + shake_off
	if is_instance_valid(sacred_stage):
		sacred_stage.queue_redraw()


func final_char_states() -> Array:
	if phase != "intro": return []
	var dt_f := elapsed - _t_final()
	if dt_f < 0.0 or dt_f > 2.65: return []
	var punch_scale := 1.0
	if not UiHub.reduced_motion and dt_f >= 1.55 and dt_f < 1.77:
		var pk := clampf((dt_f - 1.55) / 0.22, 0.0, 1.0)
		punch_scale = 1.0 + 0.09 * sin(pk * PI)
	var center_p := Vector2(960.0, 496.0)
	var out: Array = []
	for spec in char_specs:
		var ch := String(spec.ch)
		var base_pos: Vector2 = center_p + (spec.pos - center_p) * punch_scale
		var pos := base_pos
		var rot := 0.0
		var alpha := 0.0
		var blur_k := 0.0
		if dt_f < 1.70:
			var u_in := clampf((dt_f - float(spec.bd)) / 0.55, 0.0, 1.0)
			var q_in := Kit.curve(u_in)
			pos = base_pos + Vector2(0.0, lerpf(14.0, 0.0, q_in))
			alpha = q_in
			blur_k = 1.0 - q_in
		elif UiHub.reduced_motion:
			var u_fade := clampf((dt_f - 1.70) / 0.50, 0.0, 1.0)
			alpha = 1.0 - u_fade
		else:
			var u_sh := clampf((dt_f - 1.70 - float(spec.sd)) / 0.85, 0.0, 1.0)
			var q_sh := 1.0 - pow(1.0 - u_sh, 3.0)
			pos = base_pos + Vector2(float(spec.sx), float(spec.sy)) * q_sh
			rot = float(spec.sr) * q_sh
			alpha = pow(1.0 - u_sh, 1.35)
			blur_k = u_sh * 0.7
		out.append({
			"ch": ch,
			"pos": pos,
			"rot": rot,
			"alpha": alpha,
			"blur": blur_k,
			"scale": punch_scale,
		})
	return out


func _draw_stage(ci: Control) -> void:
	var n := preview_night
	# 1. Pure sacred canvas with smooth hardware-interpolated radial gradient (matching CSS radial-gradient)
	var bg_edge := COL_DAY_EDGE.lerp(COL_NIGHT_EDGE, n)
	var bg_mid := COL_DAY_MID.lerp(COL_NIGHT_MID, n)
	var bg_center := COL_DAY_CENTER.lerp(COL_NIGHT_CENTER, n)
	ci.draw_rect(Rect2(-600, -400, 3120, 1880), bg_edge)
	_draw_radial_backdrop(ci, Vector2(960.0, 460.0), Vector2(720.0, 430.0), Vector2(1480.0, 880.0), bg_center, bg_mid, bg_edge)

	# 2. Subtle floating dust motes (#soDust i)
	var dust_time := (mode_elapsed if phase == "mode" else elapsed) if not UiHub.reduced_motion else 0.0
	var dust_base := Color(0.604, 0.420, 0.208).lerp(Color(0.667, 0.745, 0.863), n)
	for d in dust_specs:
		var wv := 0.5 + 0.5 * sin(dust_time * float(d.speed) + float(d.phase))
		var dy := lerpf(10.0, -22.0, wv)
		var sc := lerpf(0.75, 1.12, wv)
		var dc := dust_base
		dc.a = lerpf(0.06, 0.36, wv)
		ci.draw_circle(d.pos + Vector2(0.0, dy), float(d.r) * sc, dc)

	if phase == "mode":
		_draw_mode_title(ci, n)
	else:
		_draw_intro_text(ci, n)


func _draw_mode_title(ci: Control, n: float) -> void:
	var main_col := COL_INK_DAY.lerp(COL_INK_NIGHT, n)
	var sub_col := COL_SUB_DAY.lerp(COL_SUB_NIGHT, n)
	for spec in mode_char_specs:
		var is_sub: bool = spec.sub
		var px := UiHub.fs(22 if is_sub else 38)
		var wt := 500 if is_sub else 750
		var base_pos: Vector2 = spec.pos
		var ch := String(spec.ch)
		var pos := base_pos
		var rot := 0.0
		var alpha := 1.0
		if not mode_shattering:
			if not UiHub.reduced_motion and not _test_frozen:
				var u_in := clampf((mode_elapsed - float(spec.bd)) / 0.52, 0.0, 1.0)
				var q_in := Kit.curve(u_in)
				pos = base_pos + Vector2(0.0, lerpf(10.0, 0.0, q_in))
				alpha = q_in
		else:
			var u_sh := clampf((mode_shatter_t - float(spec.sd)) / 0.82, 0.0, 1.0)
			var q_sh := 1.0 - pow(1.0 - u_sh, 3.0)
			pos = base_pos + Vector2(float(spec.sx), float(spec.sy)) * q_sh
			rot = float(spec.sr) * q_sh
			alpha = pow(1.0 - u_sh, 1.4)
		if is_sub:
			alpha *= lerpf(0.72, 0.78, n)
		if alpha <= 0.01: continue
		var col := sub_col if is_sub else main_col
		col.a = alpha
		_draw_glyph_transformed(ci, ch, pos, px, wt, col, rot, 1.0, Color(col.r, col.g, col.b, alpha * 0.16 * n))


func _draw_mode_diamond(btn_node: Control, is_night_btn: bool, label_txt: String, hover_mix: float) -> void:
	var n := preview_night
	var u_in := 1.0
	var delay := 0.86 if is_night_btn else 0.78
	if not UiHub.reduced_motion and not _test_frozen:
		u_in = clampf((mode_elapsed - delay) / 0.52, 0.0, 1.0)
	if u_in <= 0.01: return
	var q_in := Kit.curve(u_in)
	var y_off := lerpf(14.0, 0.0, q_in)
	var scale_f := lerpf(1.0, 1.08, hover_mix)
	var alpha := q_in
	var char_rot := 0.0
	var char_off := Vector2.ZERO
	if mode_shattering:
		var u_out := clampf(mode_shatter_t / 0.82, 0.0, 1.0)
		var q_out := 1.0 - pow(1.0 - u_out, 3.0)
		y_off += lerpf(0.0, -22.0, q_out)
		scale_f *= lerpf(1.0, 0.86, q_out)
		alpha *= pow(1.0 - u_out, 1.35)
		char_off = Vector2(28.0 if is_night_btn else -28.0, -48.0) * q_out
		char_rot = (0.45 if is_night_btn else -0.45) * q_out
	if alpha <= 0.01: return

	var is_on := (active_pick == ("night" if is_night_btn else "day")) or hover_mix > 0.25
	var c := btn_node.size * 0.5 + Vector2(0.0, y_off)
	var half_diag := 64.0 * scale_f
	var pts := PackedVector2Array([
		c + Vector2(0.0, -half_diag),
		c + Vector2(half_diag, 0.0),
		c + Vector2(0.0, half_diag),
		c + Vector2(-half_diag, 0.0),
	])
	var fill_col: Color
	var border_col: Color
	var txt_col: Color
	if is_on:
		fill_col = Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, alpha)
		border_col = Color(1.0, 1.0, 1.0, alpha * 0.92) if n > 0.4 else Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, alpha)
		txt_col = Color(1.0, 1.0, 1.0, alpha)
		# Subtle crimson/gold glow around active diamond
		var glow_pts := PackedVector2Array([
			c + Vector2(0.0, -(half_diag + 8.0)),
			c + Vector2(half_diag + 8.0, 0.0),
			c + Vector2(0.0, half_diag + 8.0),
			c + Vector2(-(half_diag + 8.0), 0.0),
		])
		btn_node.draw_colored_polygon(glow_pts, Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, alpha * 0.18))
	else:
		fill_col = Color(1.0, 0.99, 0.97, 0.22 * alpha).lerp(Color(0.07, 0.05, 0.08, 0.45 * alpha), n)
		border_col = Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, 0.55 * alpha).lerp(Color(0.957, 0.937, 0.902, 0.55 * alpha), n)
		txt_col = Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, alpha).lerp(Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, alpha), n)

	btn_node.draw_colored_polygon(pts, fill_col)
	var closed := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
	btn_node.draw_polyline(closed, border_col, 1.6, true)
	_draw_glyph_transformed(btn_node, label_txt, c + char_off, UiHub.fs(26), 900, txt_col, char_rot, scale_f, Color(0, 0, 0, 0.25 * alpha if is_on else 0.0))


func _draw_intro_text(ci: Control, n: float) -> void:
	# 1. Movement 1: 24 Whispers (.gz / .gz.acc — gold #d4b36a and crimson #c3272b)
	for w in active_whispers():
		var spec: Dictionary = w.spec
		var u: float = w.u
		var a: float = w.alpha
		var p: Vector2 = spec.pos + spec.drift * u
		var px: int = UiHub.fs(int(spec.px))
		var is_acc: bool = spec.accent
		var w_text := String(spec.text)
		var tw := Kit.text_width(w_text, px, 750 if is_acc else 600)
		var r := Rect2(p.x - tw * 0.5 - 10.0, p.y - 24.0, tw + 20.0, 48.0)
		if is_acc:
			var glow_c := Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, a * 0.32)
			Kit.text(ci, Rect2(r.position + Vector2(0.0, 1.0), r.size), w_text, px, glow_c, HORIZONTAL_ALIGNMENT_CENTER, 750)
			var main_c := Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, a)
			Kit.text(ci, r, w_text, px, main_c, HORIZONTAL_ALIGNMENT_CENTER, 750)
		else:
			# Original .gz: gold #d4b36a with soft gold glow + 1px crimson chromatic hint
			var chr_c := Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, a * 0.28)
			Kit.text(ci, Rect2(r.position + Vector2(1.5, 0.0), r.size), w_text, px, chr_c, HORIZONTAL_ALIGNMENT_CENTER, 600)
			var glow_g := Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, a * 0.28)
			Kit.text(ci, Rect2(r.position + Vector2(0.0, 1.5), r.size), w_text, px, glow_g, HORIZONTAL_ALIGNMENT_CENTER, 600)
			var main_g := Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, a)
			Kit.text(ci, r, w_text, px, main_g, HORIZONTAL_ALIGNMENT_CENTER, 600)

	# 2. Movement 2: 5 Central Big Lines (.so-bigline — pure ink, NO underlines or frames)
	var bl := current_big_line()
	if not bl.is_empty():
		var b_text := String(bl.text)
		var b_alpha := float(bl.alpha)
		var b_y := 496.0 + float(bl.y_off)
		var b_blur := float(bl.blur)
		var is_small := bool(bl.small)
		var px := UiHub.fs(34 if is_small else 46)
		var wt := 750 if is_small else 850
		var ink_c := COL_INK_DAY.lerp(COL_INK_NIGHT, n)
		var r := Rect2(260.0, b_y - 48.0, 1400.0, 96.0)
		if b_blur > 0.05 and not UiHub.reduced_motion:
			var spread := b_blur * 5.0
			var halo_c := Color(ink_c.r, ink_c.g, ink_c.b, b_alpha * 0.16)
			for off in [Vector2(-spread, 0), Vector2(spread, 0), Vector2(0, -spread * 0.7), Vector2(0, spread * 0.7)]:
				Kit.text(ci, Rect2(r.position + off, r.size), b_text, px, halo_c, HORIZONTAL_ALIGNMENT_CENTER, wt)
		ink_c.a = b_alpha
		Kit.text(ci, r, b_text, px, ink_c, HORIZONTAL_ALIGNMENT_CENTER, wt)

	# 3. Movement 3: Final Line ("拯救艾瑟拉吧" — pure crimson #c3272b, per-char reveal -> punch -> per-char shatter)
	var dt_f := elapsed - _t_final()
	if dt_f >= 0.0 and dt_f <= 2.65:
		var punch_scale := 1.0
		if not UiHub.reduced_motion and dt_f >= 1.55 and dt_f < 1.77:
			var pk := clampf((dt_f - 1.55) / 0.22, 0.0, 1.0)
			punch_scale = 1.0 + 0.09 * sin(pk * PI)
		var center_p := Vector2(960.0, 496.0)
		for spec in char_specs:
			var ch := String(spec.ch)
			var base_pos: Vector2 = center_p + (spec.pos - center_p) * punch_scale
			var pos := base_pos
			var rot := 0.0
			var alpha := 0.0
			var blur_k := 0.0
			if dt_f < 1.70:
				var u_in := clampf((dt_f - float(spec.bd)) / 0.55, 0.0, 1.0)
				var q_in := Kit.curve(u_in)
				pos = base_pos + Vector2(0.0, lerpf(14.0, 0.0, q_in))
				alpha = q_in
				blur_k = 1.0 - q_in
			elif UiHub.reduced_motion:
				var u_fade := clampf((dt_f - 1.70) / 0.50, 0.0, 1.0)
				alpha = 1.0 - u_fade
			else:
				var u_sh := clampf((dt_f - 1.70 - float(spec.sd)) / 0.85, 0.0, 1.0)
				var q_sh := 1.0 - pow(1.0 - u_sh, 3.0)
				pos = base_pos + Vector2(float(spec.sx), float(spec.sy)) * q_sh
				rot = float(spec.sr) * q_sh
				alpha = pow(1.0 - u_sh, 1.35)
				blur_k = u_sh * 0.7
			if alpha <= 0.01: continue
			var c_col := Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, alpha)
			var glow_col := Color(COL_CRIMSON.r, COL_CRIMSON.g, COL_CRIMSON.b, alpha * (0.28 + blur_k * 0.16))
			_draw_glyph_transformed(ci, ch, pos, UiHub.fs(68), 900, c_col, rot, punch_scale, glow_col)

	# 4. Soft mist sweep (#soSweep i — soft translucent mist bands, NO hard polygons)
	if dt_f >= 2.15 and dt_f <= 3.10 and not UiHub.reduced_motion:
		var mist_col := Color(0.494, 0.541, 0.620)
		for m in mist_specs:
			var u_m := (dt_f - 2.15 - float(m.delay)) / float(m.dur)
			if u_m <= 0.0 or u_m >= 1.0: continue
			var ma := sin(u_m * PI) * 0.18
			var mx := lerpf(-float(m.w), 1920.0 + float(m.w) * 0.5, Kit.curve(u_m))
			_draw_soft_ellipse(ci, Vector2(mx, float(m.y)), Vector2(float(m.w) * 0.5, float(m.h) * 0.5), mist_col, ma)


func _draw_glyph_transformed(ci: Control, ch: String, center: Vector2, px: int, weight: int, col: Color, rot: float, sc: float, glow_col: Color) -> void:
	ci.draw_set_transform(center, rot, Vector2.ONE * sc)
	var box := Rect2(-64.0, -64.0, 128.0, 128.0)
	if glow_col.a > 0.01:
		for off in [Vector2(-3.0, 0.0), Vector2(3.0, 0.0), Vector2(0.0, -3.0), Vector2(0.0, 3.0)]:
			Kit.text(ci, Rect2(box.position + off, box.size), ch, px, glow_col, HORIZONTAL_ALIGNMENT_CENTER, weight)
	Kit.text(ci, box, ch, px, col, HORIZONTAL_ALIGNMENT_CENTER, weight)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_radial_backdrop(ci: Control, center: Vector2, mid_radii: Vector2, outer_radii: Vector2, col_center: Color, col_mid: Color, col_edge: Color) -> void:
	var segs := 48
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var m0 := center + d0 * mid_radii
		var m1 := center + d1 * mid_radii
		var o0 := center + d0 * outer_radii
		var o1 := center + d1 * outer_radii
		ci.draw_polygon(PackedVector2Array([center, m0, m1]), PackedColorArray([col_center, col_mid, col_mid]))
		ci.draw_polygon(PackedVector2Array([m0, o0, o1, m1]), PackedColorArray([col_mid, col_edge, col_edge, col_mid]))


func _draw_soft_ellipse(ci: Control, center: Vector2, radii: Vector2, col: Color, max_alpha: float) -> void:
	var segs := 32
	var c_in := Color(col.r, col.g, col.b, max_alpha)
	var c_out := Color(col.r, col.g, col.b, 0.0)
	for i in range(segs):
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var p0 := center + Vector2(cos(a0) * radii.x, sin(a0) * radii.y)
		var p1 := center + Vector2(cos(a1) * radii.x, sin(a1) * radii.y)
		ci.draw_polygon(PackedVector2Array([center, p0, p1]), PackedColorArray([c_in, c_out, c_out]))
