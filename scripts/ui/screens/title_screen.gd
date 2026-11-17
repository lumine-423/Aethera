extends "res://scripts/ui/ui_screen.gd"
## 标题页 (full version, mystic pass 2026-11-14). Classic galgame title layout: scene art fills the
## screen, the showcase character stands on the right, a soft veil on the left carries the accepted
## AETHERA r6 wordmark (assets/ui/mystic/title_logo_mask.png, alpha read from the master, tinted per
## theme) and a vertical menu of thin serif words. Hover / focus: a four-point star appears, the word
## slides right and a hairline underline draws out. Star dust drifts down like snow.
## Optional unlock step (password field) kept from the previous title; UI only.

const LOGO := "res://assets/ui/mystic/title_logo_mask.png"
const LOGO_TEXT := "res://assets/ui/mystic/title_logo_text_mask.png"
const LOGO_STAR := "res://assets/ui/mystic/title_logo_star_mask.png"
const FALLING_GIRL := "res://assets/ui/mystic/title_falling_girl.png"
const CRADLE_HALO := "res://assets/ui/mystic/title_cradle_halo.png"
const BG_DAY := "res://assets/backgrounds/ACA01-day-v1.webp"
const BG_NIGHT := "res://assets/backgrounds/ACA01-variant-02-v1.webp"
var phase := "menu"        # menu | prompt | unlock
var wrong := false
var pw: LineEdit
var stage: Stage
var items: Array = []

func open(owner_root: Node, p: Dictionary) -> void:
	super.open(owner_root, p)
	uses_backdrop = false
	if p.has("phase"): phase = String(p.get("phase", "menu"))
	elif bool(p.get("locked", false)): phase = "unlock"
	else: phase = "menu"

func build() -> void:
	stage = Stage.new(); stage.name = "TitleStage"
	stage.showcase = _showcase()
	put(stage, Rect2(0, 0, 1920, 1080), "lt")
	stage.size = size
	music_btn(Rect2(1516, 34, 160, 64), "rt")
	var sw := W.ThemeSwitch.new(); sw.name = "ThemeSwitch"
	put(sw, Rect2(1692, 34, 190, 64), "rt")
	var upd := UiHub.updater()
	var upd_cap := ("发现新版本 v%s · 点击更新" % String(upd.latest_version)) if upd.update_available else ("v%s · 检查更新" % String(upd.local_version()))
	var upd_btn := btn(upd_cap, "refresh", "chip", Rect2(56, 1012, 340, 48), func(): root.open_app_updater(), "lb", -1.0, null, 18)
	upd_btn.name = "CheckUpdateBtn"
	upd_btn.selected = bool(upd.update_available)
	upd_btn.tooltip_text = "检查 GitHub 新版本、拉取更新与下载对应平台更新包（手机端 / 电脑端）"
	var sync_upd := func() -> void:
		if not is_instance_valid(upd_btn): return
		var u := UiHub.updater()
		upd_btn.caption = ("发现新版本 v%s · 点击更新" % String(u.latest_version)) if u.update_available else ("v%s · 检查更新" % String(u.local_version()))
		upd_btn.selected = bool(u.update_available)
		upd_btn.queue_redraw()
	if not upd.changed.is_connected(sync_upd):
		upd.changed.connect(sync_upd)
	upd_btn.tree_exited.connect(func():
		if is_instance_valid(upd) and upd.changed.is_connected(sync_upd):
			upd.changed.disconnect(sync_upd))
	if not UiHub.review_mode and not upd.has_meta("startup_checked"):
		upd.set_meta("startup_checked", true)
		if upd.is_repo_configured():
			upd.call_deferred("check_for_updates")
	match phase:
		"prompt": _prompt()
		"unlock": _unlock()
		_: _menu()

func _showcase() -> String:
	var sid := String(UiHub.get_meta("showcase_id", ""))
	if sid != "" and Data.art_path(sid, "daily", "neutral") != "": return sid
	return "rin" if Data.art_path("rin", "daily", "neutral") != "" else ""

func _menu() -> void:
	var can_continue: bool = Game.saves.any(func(s): return s.slot == 0 and s.used)
	var list := []
	if can_continue: list.append(["继续游戏", func(): Game.load_slot(0); root.go("loading", {"next": "home", "label": "载入存档"}, "wipe", "reset"), "confirm_big"])
	list.append(["新的开始", func(): _confirm_new(), "confirm_big"])
	list.append(["读取进度", func(): root.go("saves", {"mode": "load"}), ""])
	list.append(["重播开场", func(): root.go("opening", {"next": "title", "replay": true}, "fade"), "none"])
	list.append(["艾瑟拉的忠告", func(): root.go("help"), ""])
	list.append(["设置", func(): root.go("settings"), ""])
	list.append(["退出", func(): root.confirm_quit(), ""])
	items.clear()
	var y := 560.0
	var pitches := [1.0, 1.122, 1.26, 1.335, 1.498, 1.682, 1.888]
	for i in range(list.size()):
		var it: Array = list[i]
		var m := MenuItem.new(); m.caption = it[0]; m.name = "Menu%d" % i; m.index = i
		m.hover_pitch = pitches[mini(i, pitches.size() - 1)]; m.press_cue = it[2]
		m.pressed.connect(it[1])
		put(m, Rect2(110, y, 520, 60), "l")
		items.append(m)
		y += 64.0
	for i in range(items.size()):
		var m: MenuItem = items[i]
		m.siblings = items
		m.appear(0.75 + i * 0.08)
	if not items.is_empty(): items[0].call_deferred("grab_focus")

func _confirm_new() -> void:
	if not Game.has_story() and not Game.saves.any(func(s): return s.used):
		_start_new(); return
	var d = root.dialog({"title": "新的开始", "message": "开始新的进度。自动存档会被新进度覆盖，手动存档不受影响。", "icon": "star4", "buttons": [{"id": "cancel", "text": "取消", "icon": "close"}, {"id": "ok", "text": "开始", "icon": "play", "kind": "primary"}]})
	d.chosen.connect(func(id: String): if id == "ok": _start_new())

## New game: enter origin selection (or API connection check first).
func _start_new() -> void:
	if Game.connection.get("has_key", false): root.go("origin", {}, "wipe")
	else: root.go("connect", {"next": "origin", "first": true}, "wipe")

func _prompt() -> void:
	var l := text("点击任意处开始", Rect2(110, 640, 600, 70), 34, "ink", 500, "l")
	l.name = "StartPrompt"
	if not UiHub.reduced_motion:
		var t := l.create_tween().set_loops()
		t.tween_property(l, "modulate:a", 0.3, 1.1).set_trans(Tween.TRANS_SINE)
		t.tween_property(l, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)
	text("TAP  ·  CLICK  ·  ENTER", Rect2(112, 712, 600, 30), 16, "muted", 500, "l")

func _gui_input(e: InputEvent) -> void:
	if phase != "prompt": return
	if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
		_advance(); accept_event()

func _unhandled_key_input(e: InputEvent) -> void:
	if phase == "prompt" and e.pressed and not e.is_action("ui_cancel"):
		_advance(); get_viewport().set_input_as_handled()

func _advance() -> void:
	UiHub.sfx("start"); UiHub.haptic(20); UiHub.quiet_focus()
	phase = "unlock" if params.get("locked", false) else "menu"
	refresh(true)

func _unlock() -> void:
	var p := plate(Rect2(100, 560, 660, 360), {"slant": 40, "corner": "tr"}, "l", 0.1)
	icon("lock", Rect2(40, 34, 56, 56), "accent", "c", p)
	text("输入访问密码", Rect2(110, 34, 500, 56), 34, "ink", 600, "c", p)
	text("密码只用于本机进入，不等于加密或防破解。", Rect2(40, 100, 580, 36), 18, "muted", 500, "c", p)
	pw = LineEdit.new(); pw.secret = true; pw.placeholder_text = "密码"; pw.name = "Password"
	put(pw, Rect2(40, 150, 580, 66), "c", -1.0, p)
	pw.text_submitted.connect(func(_t): _try_unlock())
	pw.call_deferred("grab_focus")
	if wrong: text("密码不正确，请再试一次。", Rect2(40, 222, 580, 32), 18, "accent", 500, "c", p)
	var ub := btn("解锁", "unlock", "primary", Rect2(340, 260, 280, 76), func(): _try_unlock(), "c", -1.0, p)
	ub.center_text = true; ub.press_sfx = "none"

func _try_unlock() -> void:
	UiHub.request("access.unlock", {"password": pw.text})
	if pw.text == "":
		UiHub.sfx("error"); UiHub.haptic(40); wrong = true; refresh(); return
	UiHub.sfx("unlock"); UiHub.quiet_focus()
	phase = "menu"; refresh(true)

func enter(delay := 0.0) -> void:
	super.enter(delay)
	if stage: stage.play_intro()


## One galgame menu word. Draws itself; behaves as a Button for mouse, touch and keyboard.
class MenuItem extends Button:
	const K = preload("res://scripts/ui/ui_kit.gd")
	var caption := ""
	var index := 0
	var hover := 0.0
	var shown := 1.0
	var hover_pitch := 1.0
	var press_cue := ""
	var siblings: Array = []
	var _t: Tween
	func _ready() -> void:
		flat = true; text = ""; focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for s in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]: add_theme_stylebox_override(s, StyleBoxEmpty.new())
		mouse_entered.connect(func(): grab_focus())
		focus_entered.connect(_on_focus)
		focus_exited.connect(func(): _to(0.0); _redraw_all())
		pressed.connect(func():
			UiHub.haptic(14)
			if press_cue != "none": UiHub.sfx(press_cue if press_cue != "" else "confirm"))
		UiHub.palette_changed.connect(queue_redraw)
	func _on_focus() -> void:
		_to(1.0)
		if UiHub.focus_sound_ok() or is_hovered(): UiHub.sfx("hover", hover_pitch)
		_redraw_all()
	func _redraw_all() -> void:
		for s in siblings:
			if is_instance_valid(s): s.queue_redraw()
	func appear(delay: float) -> void:
		if UiHub.reduced_motion: return
		shown = 0.0
		var t := create_tween(); t.tween_interval(delay)
		t.tween_method(func(v): shown = v; queue_redraw(), 0.0, 1.0, 0.7)
	func _to(v: float) -> void:
		if _t: _t.kill()
		if UiHub.reduced_motion: hover = v; queue_redraw(); return
		_t = create_tween(); _t.tween_method(func(x): hover = x; queue_redraw(), hover, v, 0.32 if v > 0.5 else 0.22).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	func _any_focus() -> bool:
		for s in siblings:
			if is_instance_valid(s) and s.has_focus(): return true
		return false
	func _draw() -> void:
		var q := K.curve(shown)
		var acc := UiHub.c("accent"); var ink := UiHub.c("ink")
		var dim := 1.0 if hover > 0.5 or not _any_focus() else 0.62
		var x := 40.0 + 14.0 * hover - 30.0 * (1.0 - q)
		var a := q * dim
		var px := UiHub.fs(34 if index == 0 else 30)
		# star marker
		if hover > 0.01:
			K.star4(self, Vector2(16, size.y * 0.5), 9.0 * hover, Color(acc, hover * q), 0.16, (1.0 - hover) * 0.8)
		K.text(self, Rect2(x, 0, size.x - x, size.y - 6), caption, px, Color(ink, a), HORIZONTAL_ALIGNMENT_LEFT, 600, 10)
		# underline: hairline + accent head
		var tw := K.text_width(caption, px, 600) + caption.length() * 10.0
		var ux := lerpf(tw * 0.15, tw + 120.0, hover)
		draw_line(Vector2(x - 6, size.y - 6), Vector2(x - 6 + ux, size.y - 6), Color(ink, 0.35 * q), 1.0, true)
		if hover > 0.01:
			draw_line(Vector2(x - 6, size.y - 6), Vector2(x - 6 + ux * 0.4, size.y - 6), Color(acc, hover * q), 1.6, true)
			draw_circle(Vector2(x - 6 + ux, size.y - 6), 2.2, Color(acc, hover * q))


## Transparent falling-girl visual, day-red / night-yellow halo, mouse parallax,
## calligraphy-stroke title reveal followed by cross-star emergence, and star snow.
class Stage extends Control:
	const K = preload("res://scripts/ui/ui_kit.gd")
	const D = preload("res://scripts/ui/ui_data.gd")
	const WORDMARK_SHADER_CODE := """shader_type canvas_item;
uniform sampler2D text_tex : filter_linear, repeat_disable;
uniform sampler2D star_tex : filter_linear, repeat_disable;
uniform float text_progress : hint_range(0.0, 1.0) = 1.0;
uniform float star_progress : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ink_color : source_color = vec4(0.133, 0.118, 0.125, 1.0);
uniform vec4 star_color : source_color = vec4(0.61, 0.60, 0.58, 1.0);
uniform vec4 accent_color : source_color = vec4(0.86, 0.15, 0.18, 1.0);

void fragment() {
	vec4 tm = texture(text_tex, UV);
	vec4 sm = texture(star_tex, UV);
	float t_stroke = tm.r;
	float s_rad = sm.r;

	float stroke_vis = (text_progress >= 0.999) ? 1.0 : smoothstep(t_stroke - 0.025, t_stroke + 0.004, text_progress);
	float pen_glow = (text_progress >= 0.999 || text_progress <= 0.001) ? 0.0 : clamp(1.0 - abs(text_progress - t_stroke) / 0.026, 0.0, 1.0);
	float ta = tm.a * stroke_vis;

	float star_vis = (star_progress <= 0.001) ? 0.0 : ((star_progress >= 0.999) ? 1.0 : smoothstep(s_rad - 0.16, s_rad + 0.02, star_progress) * pow(clamp(star_progress, 0.0, 1.0), 0.6));
	float star_tip_glow = (star_progress <= 0.001 || star_progress >= 0.999) ? 0.0 : clamp(1.0 - abs(star_progress - s_rad) / 0.10, 0.0, 1.0) * 0.45;
	float sa = sm.a * star_vis;

	vec3 t_rgb = mix(ink_color.rgb, accent_color.rgb, pen_glow * 0.68);
	vec3 s_rgb = mix(star_color.rgb, accent_color.rgb, star_tip_glow);
	float tot_a = clamp(ta + sa * (1.0 - ta), 0.0, 1.0);
	vec3 out_rgb = (tot_a > 0.0001) ? ((t_rgb * ta + s_rgb * sa * (1.0 - ta)) / tot_a) : vec3(0.0);
	COLOR = vec4(out_rgb, tot_a * COLOR.a);
}
"""
	var showcase := ""
	var bg_day: Texture2D
	var bg_night: Texture2D
	var logo: Texture2D
	var logo_text: Texture2D
	var logo_star: Texture2D
	var girl_tex: Texture2D
	var halo_tex: Texture2D
	var art: Texture2D
	var wordmark_rect: ColorRect
	var wordmark_mat: ShaderMaterial
	var clock := 0.0
	var intro := 1.0
	var text_progress := 1.0
	var star_progress := 1.0
	var flakes: Array = []
	var look := Vector2.ZERO
	var _intro_tween: Tween
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_day = _tex(BG_DAY); bg_night = _tex(BG_NIGHT); logo = _tex(LOGO)
		logo_text = _tex(LOGO_TEXT); logo_star = _tex(LOGO_STAR)
		girl_tex = _tex(FALLING_GIRL); halo_tex = _tex(CRADLE_HALO)
		if showcase != "":
			var p: String = D.art_path(showcase, "daily", "neutral")
			if p != "": art = load(p)
		_setup_wordmark()
		var rng := RandomNumberGenerator.new(); rng.seed = 2026
		for i in range(90):
			flakes.append({"p": Vector2(rng.randf(), rng.randf()), "s": rng.randf_range(1.2, 4.6), "v": rng.randf_range(0.012, 0.05), "w": rng.randf() * TAU, "star": rng.randf() < 0.22, "z": rng.randf()})
		UiHub.palette_changed.connect(_on_visual_dirty)
		resized.connect(_layout_wordmark)
		_sync_intro_stages(1.0)
	func _setup_wordmark() -> void:
		wordmark_rect = ColorRect.new()
		wordmark_rect.name = "TitleWordmark"
		wordmark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wordmark_rect.color = Color.WHITE
		if logo_text and logo_star:
			var sh := Shader.new()
			sh.code = WORDMARK_SHADER_CODE
			wordmark_mat = ShaderMaterial.new()
			wordmark_mat.shader = sh
			wordmark_mat.set_shader_parameter("text_tex", logo_text)
			wordmark_mat.set_shader_parameter("star_tex", logo_star)
			wordmark_rect.material = wordmark_mat
		add_child(wordmark_rect)
		_layout_wordmark()
		_sync_wordmark_uniforms()
	func _layout_wordmark() -> void:
		if wordmark_rect == null: return
		var ref_tex := logo_text if logo_text else logo
		var ls := ref_tex.get_size() if ref_tex else Vector2(1301.0, 838.0)
		var lw := 640.0
		var lh := ls.y * lw / maxf(ls.x, 1.0)
		wordmark_rect.position = Vector2(70.0, 70.0)
		wordmark_rect.size = Vector2(lw, lh)
	func _sync_wordmark_uniforms() -> void:
		if wordmark_mat == null: return
		var n := UiHub.night
		var star_col := Color(0.61, 0.59, 0.57, 1.0).lerp(Color(0.76, 0.69, 0.52, 1.0), n)
		var halo_acc := Color(0.86, 0.15, 0.18, 1.0).lerp(Color(1.0, 0.82, 0.24, 1.0), n)
		wordmark_mat.set_shader_parameter("ink_color", UiHub.c("ink"))
		wordmark_mat.set_shader_parameter("star_color", star_col)
		wordmark_mat.set_shader_parameter("accent_color", halo_acc)
		wordmark_mat.set_shader_parameter("text_progress", text_progress)
		wordmark_mat.set_shader_parameter("star_progress", star_progress)
		if wordmark_rect:
			wordmark_rect.visible = (logo_text != null and logo_star != null)
	func _sync_intro_stages(v: float) -> void:
		intro = clampf(v, 0.0, 1.0)
		# Phase 1 (0.04..0.58, ~3.35s): calm calligraphy stroke reveal for AETHERA + 艾瑟拉
		var u_text := clampf((intro - 0.04) / 0.54, 0.0, 1.0)
		text_progress = 1.0 if intro >= 0.58 else (u_text * 0.35 + (u_text * u_text * (3.0 - 2.0 * u_text)) * 0.65)
		# Brief beat (0.58..0.62) before the star emerges; Phase 2 (0.62..1.00, ~2.36s): slow smooth radial emergence
		var u_star := clampf((intro - 0.62) / 0.38, 0.0, 1.0)
		star_progress = 1.0 if intro >= 0.999 else (u_star * u_star * (3.0 - 2.0 * u_star))
		_sync_wordmark_uniforms()
	func _on_visual_dirty() -> void:
		_sync_wordmark_uniforms()
		queue_redraw()
	func _tex(p: String) -> Texture2D:
		return load(p) if ResourceLoader.exists(p) else null
	func play_intro() -> void:
		if _intro_tween: _intro_tween.kill()
		if UiHub.reduced_motion:
			_sync_intro_stages(1.0); queue_redraw(); return
		_sync_intro_stages(0.0); queue_redraw()
		_intro_tween = create_tween()
		_intro_tween.tween_method(func(v): _sync_intro_stages(v); queue_redraw(), 0.0, 1.0, 6.20)
	func _process(d: float) -> void:
		if UiHub.reduced_motion or not is_visible_in_tree(): return
		clock += d
		for f in flakes:
			f.p.y += f.v * d * (0.6 + f.z)
			f.p.x += sin(clock * 0.6 + f.w) * 0.0004
			if f.p.y > 1.03: f.p.y = -0.03; f.p.x = randf()
		var m := get_local_mouse_position()
		var target := Vector2.ZERO
		if size.x > 0 and Rect2(Vector2.ZERO, size).has_point(m): target = (m / size - Vector2(0.5, 0.5)) * 2.0
		look = look.lerp(target, minf(d * 1.6, 1.0))
		queue_redraw()
	func _draw_girl(tex: Texture2D, center: Vector2, scale_h: float, alpha: float, shift: Vector2, tint: Color = Color.WHITE) -> void:
		if tex == null or alpha <= 0.001: return
		var sc := (size.y / 1080.0) * scale_h
		var ds := tex.get_size() * sc
		var pos := center + shift - Vector2(ds.x * 0.6738, ds.y * 0.5035)
		draw_texture_rect(tex, Rect2(pos, ds), false, Color(tint.r, tint.g, tint.b, tint.a * alpha))
	func _draw() -> void:
		var W := size.x; var H := size.y
		var n := UiHub.night
		var e := K.curve(clampf(intro / 0.28, 0.0, 1.0))
		draw_rect(Rect2(Vector2.ZERO, size), UiHub.c("background"))
		var par := -look * 12.0
		var float_ofs := Vector2.ZERO if UiHub.reduced_motion else Vector2(sin(clock * 0.65) * 3.8, cos(clock * 0.5) * 5.2)

		# Day -> Red halo; Night -> Yellow halo sized cleanly around the user's oval center
		var halo_day := Color(0.86, 0.15, 0.18)
		var halo_night := Color(1.0, 0.82, 0.24)
		var halo_col := halo_day.lerp(halo_night, n)
		var base_center := Vector2(W * 0.679, H * 0.555)
		var cc := base_center + par * 0.85 + float_ofs * 0.35

		if halo_tex:
			var breath := 1.0 if UiHub.reduced_motion else (1.0 + 0.014 * sin(clock * 0.9))
			var hs := H * 0.48 * breath
			draw_texture_rect(halo_tex, Rect2(cc - Vector2(hs, hs) * 0.5, Vector2(hs, hs)), false, Color(halo_col, 0.92 * e))

		# Rotating delicate orbital lines synced to Day-Red / Night-Yellow halo
		for i in range(3):
			var r := H * (0.21 + i * 0.052)
			var a := clock * (0.04 + i * 0.018) * (1.0 if i % 2 == 0 else -1.0)
			K.arc_fade(self, cc, r, a, a + PI * 1.25, Color(halo_col, (0.30 if n < 0.5 else 0.36) * e), 1.0, 88, 0.12)
		K.crescent(self, cc, H * 0.245, clock * 0.05 - 0.6, clock * 0.05 + 0.5, 2.8, Color(halo_col, 0.42 * e))

		# Falling girl transparent foreground at crisp 0.90x native scale (no upscaling blur) + mouse parallax
		if girl_tex:
			var girl_shift := par * 1.35 + float_ofs + Vector2(56.0 * (1.0 - e), 16.0 * (1.0 - e))
			if n < 0.5:
				_draw_girl(girl_tex, base_center, 0.90, 0.14 * e * (1.0 - n * 2.0), girl_shift + Vector2(1.5, 2.0), Color(0.35, 0.24, 0.26, 1.0))
			_draw_girl(girl_tex, base_center, 0.90, e, girl_shift)
		elif art:
			var ts := art.get_size()
			var h := H * 1.18
			var w := ts.x * h / ts.y
			var x := W * 0.66 - w * 0.5 + 120.0 * (1.0 - e) + par.x * 1.4
			draw_texture_rect(art, Rect2(x, H - h * 0.86 + par.y, w, h), false, Color(1, 1, 1, e))

		# Left veil gradient & delicate hairlines
		var veil := UiHub.c("background")
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(W * 0.44, 0), Vector2(W * 0.44, H), Vector2(0, H)])
		draw_polygon(pts, PackedColorArray([Color(veil, 0.72), Color(veil, 0.0), Color(veil, 0.0), Color(veil, 0.72)]))
		K.line_fade(self, Vector2(60, H * 0.495), Vector2(W * 0.36, H * 0.495), UiHub.c("hair", 0.8 * e), 1.0, 16)
		K.line_fade(self, Vector2(W * 0.06, H * 0.98), Vector2(W * 0.36, H * 0.02), UiHub.c("hair", 0.5 * e), 1.0, 20)

		# Fallback static mask if split text/star masks aren't loaded yet, plus central glint once star blooms
		var lw := 640.0
		var ref_tex := logo_text if logo_text else logo
		var lh := (ref_tex.get_size().y * lw / ref_tex.get_size().x) if ref_tex else 412.0
		var lp := Vector2(70.0, 70.0)
		if wordmark_mat == null and logo:
			var rev := text_progress
			if rev > 0.0:
				var ls := logo.get_size()
				draw_texture_rect_region(logo, Rect2(lp, Vector2(lw * rev, lh)), Rect2(0, 0, ls.x * rev, ls.y), UiHub.c("ink"))
		if star_progress > 0.55:
			var sc := lp + Vector2(lw * 0.5, lh * 0.45)
			var vis_star := clampf((star_progress - 0.55) / 0.45, 0.0, 1.0)
			var g := 0.5 + 0.5 * sin(clock * 1.4)
			K.star4(self, sc, (6.5 + 3.0 * g) * vis_star, Color(halo_col, (0.35 + 0.45 * g) * vis_star), 0.14)

		# Star snow (two depths with parallax)
		for f in flakes:
			var p: Vector2 = Vector2(f.p.x * W, f.p.y * H) + par * (0.4 + f.z)
			var tw: float = 0.45 + 0.55 * absf(sin(clock * 1.2 + f.w))
			var col := UiHub.c("glow" if n > 0.5 else "surface", 0.9 * tw * e) if not f.star else Color(halo_col, 0.55 * tw * e)
			if f.star: K.star4(self, p, f.s * 1.6, col, 0.16)
			else:
				draw_circle(p, f.s * (0.6 + f.z * 0.5), Color(col, col.a * 0.55))
				draw_circle(p, f.s * 0.35, col)
		# Large soft foreground bokeh drifting slowly
		for i in range(5):
			var bp := Vector2(fmod(W * (0.15 + i * 0.21) + clock * (6 + i * 3), W + 200) - 100, H * (0.2 + 0.15 * i) + sin(clock * 0.3 + i) * 30.0)
			draw_circle(bp, 40.0 + i * 12.0, Color(halo_col, 0.045 * e))
