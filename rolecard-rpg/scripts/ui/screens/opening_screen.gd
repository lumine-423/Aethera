extends "res://scripts/ui/ui_screen.gd"
## 开场 (concept 02)：昼夜选择 -> 2分19秒开场PV -> next screen。随时可跳过。
## PV 画面是离线渲染好的 Theora 视频（tools/opening_pv/render.py 生成，无声）；
## 音乐由本页单独、不循环地播放 crystar.ogg，并以音乐的播放位置作为全片时钟。
## 找不到视频时退回原先代码绘制的占位开场，流程不断。

const PV_VIDEO := "res://assets/opening/opening_pv.ogv"
const PV_MUSIC := "res://assets/audio/bgm/custom/crystar.ogg"
const PV_LEN := 139.2
const PV_END := 138.6        # 闭眼后的寂静余韵够长了，提前一点溶入标题页

var phase := "mode"       # mode | intro
var t := 0.0
var lines: Array = []
var final_line := ""
var stage: Control
var skip_btn: Button
var skip_revealed := false
var done := false
var mode_shattering := false   # read by ui_root (contest prologue contract)

var pv_ok := false
var video: VideoStreamPlayer
var music: AudioStreamPlayer
var pv_clock := 0.0
var _seek_cool := 0.0

func open(owner_root: Node, p: Dictionary) -> void:
	super.open(owner_root, p)
	uses_backdrop = true
	var op: Dictionary = Data.content().get("opening", {})
	lines = op.get("bigLines", [])
	final_line = String(op.get("finalLine", ""))
	if bool(p.get("replay", false)): phase = "intro"

## 播放中重建会把视频和音乐一起释放，所以 PV 已开始时只调整尺寸。
func rebuild() -> void:
	if pv_ok and is_instance_valid(video):
		_layout_pv()
		return
	super.rebuild()

func build() -> void:
	skip_revealed = false
	if phase == "intro":
		mouse_filter = Control.MOUSE_FILTER_STOP
		UiHub.mark_opening_seen()
		if _start_pv():
			skip_btn = btn("跳过", "skip", "chip", Rect2(1690, 960, 190, 70), func(): _finish(true), "rb", -1.0, null, 24)
			skip_btn.name = "Skip"
			skip_btn.visible = false
			skip_btn.modulate.a = 0.0
			return
	else:
		mouse_filter = Control.MOUSE_FILTER_PASS
	stage = Control.new(); stage.mouse_filter = Control.MOUSE_FILTER_IGNORE; stage.name = "OpeningStage"
	put(stage, Rect2(0, 0, 1920, 1080), "lt"); stage.size = size
	stage.draw.connect(_paint)
	if phase == "mode": _mode()
	else:
		text("开场动画 · 占位", Rect2(40, 1030, 400, 30), 16, "muted", 500, "lb")
		skip_btn = btn("跳过", "skip", "chip", Rect2(1690, 960, 190, 70), func(): _finish(true), "rb", -1.0, null, 24)
		skip_btn.name = "Skip"
		skip_btn.visible = false
		skip_btn.modulate.a = 0.0

# ---------------- PV ----------------
func _start_pv() -> bool:
	if not ResourceLoader.exists(PV_VIDEO): return false
	var st := load(PV_VIDEO) as VideoStream
	if st == null: return false
	var black := ColorRect.new(); black.name = "PvBlack"; black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	video = VideoStreamPlayer.new(); video.name = "OpeningPV"
	video.stream = st; video.expand = true; video.loop = false
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(video)
	music = AudioStreamPlayer.new(); music.name = "OpeningMusic"; music.bus = "Music"
	var ms := load(PV_MUSIC) as AudioStreamOggVorbis
	if ms != null:
		ms.loop = false
		music.stream = ms
		music.volume_db = _music_gain()
	add_child(music)
	pv_ok = true
	_layout_pv()
	pv_clock = 0.0
	video.play()
	if music.stream != null and not UiHub.music_disabled:
		music.play(0.0)
	return true

func _music_gain() -> float:
	for rt in UiHub.music_manifest.get("reserved_tracks", []):
		if String(rt.get("res", "")) == PV_MUSIC: return float(rt.get("gain_db", -10.0))
	return -10.0

## 16:9 等比放进当前窗口，四周留黑。
func _layout_pv() -> void:
	var s := size
	var w := s.x; var h := w * 9.0 / 16.0
	if h > s.y: h = s.y; w = h * 16.0 / 9.0
	var r := Rect2((s - Vector2(w, h)) * 0.5, Vector2(w, h))
	if is_instance_valid(video): video.position = r.position; video.size = r.size
	var black := get_node_or_null("PvBlack") as ColorRect
	if black: black.position = Vector2.ZERO; black.size = s

## 全片时钟：音乐在放就跟音乐走，静音 / 无声卡 / headless 时用累加时钟。
func pv_time() -> float:
	if is_instance_valid(music) and music.playing:
		return music.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	return pv_clock

func _process(d: float) -> void:
	if phase != "intro" or done: return
	if pv_ok:
		pv_clock += d
		var tt := pv_time()
		if is_instance_valid(music) and music.playing: pv_clock = tt
		_seek_cool -= d
		if _seek_cool <= 0.0 and video.is_playing() and absf(video.stream_position - tt) > 0.35:
			video.stream_position = tt
			_seek_cool = 2.0
		if tt >= PV_END or (tt > 3.0 and not video.is_playing() and not (is_instance_valid(music) and music.playing)):
			_finish(false)
		return
	t += d if not UiHub.reduced_motion else d * 3.0
	if is_instance_valid(stage): stage.queue_redraw()
	var total := lines.size() * 2.2 + 3.4
	if t > total: _finish(true)

func _stop_pv() -> void:
	if is_instance_valid(music): music.stop()
	if is_instance_valid(video): video.stop()

func _exit_tree() -> void:
	_stop_pv()

# ---------------- 昼夜选择与占位 ----------------
func _mode() -> void:
	var op: Dictionary = Data.content().get("opening", {})
	text(String(op.get("modeTitle", "请选择昼夜模式")).split("\n")[0], Rect2(0, 250, 1920, 70), 40, "ink", 500, "c", null, HORIZONTAL_ALIGNMENT_CENTER)
	text("（后续可随时更改）", Rect2(0, 320, 1920, 40), 20, "muted", 500, "c", null, HORIZONTAL_ALIGNMENT_CENTER)
	var d := btn(String(op.get("modeDay", "昼")), "sun", "primary", Rect2(560, 470, 360, 140), func(): _pick(false), "c", 0.1, null, 44)
	d.center_text = false; d.name = "ModeDay"; d.press_sfx = "none"
	var n := btn(String(op.get("modeNight", "夜")), "moon", "primary", Rect2(1000, 470, 360, 140), func(): _pick(true), "c", 0.16, null, 44)
	n.name = "ModeNight"; n.press_sfx = "none"
	(n if UiHub.night_target else d).call_deferred("grab_focus")

func _pick(night: bool) -> void:
	UiHub.sfx("theme", 0.8 if night else 1.12)
	UiHub.set_night(night)
	phase = "intro"; t = 0.0
	refresh(true)

func _paint() -> void:
	var W := stage.size.x; var H := stage.size.y
	var c := Vector2(W * 0.5, H * 0.46)
	var acc := UiHub.c("accent"); var ink := UiHub.c("ink"); var hair := UiHub.c("hair")
	var k := clampf(t / 1.2, 0.0, 1.0) if phase == "intro" else 0.4
	for i in range(3):
		var r := (180.0 + i * 120.0) * Kit.curve(k)
		Kit.arc_fade(stage, c, r, t * (0.1 + i * 0.05), t * (0.1 + i * 0.05) + PI * 1.5, Color(hair, 0.8), 1.0, 96, 0.1)
	Kit.star4_line(stage, c, 240.0 * Kit.curve(k), Color(ink, 0.35), 1.0)
	Kit.star4(stage, c, 26.0 * Kit.curve(k), acc, 0.14, t * 0.1)
	if phase != "intro": return
	var idx := int(t / 2.2)
	if idx < lines.size():
		var lt := fmod(t, 2.2) / 2.2
		var a := clampf(lt / 0.2, 0.0, 1.0) * clampf((1.0 - lt) / 0.25, 0.0, 1.0)
		Kit.text(stage, Rect2(0, H * 0.72, W, 70), String(lines[idx]), UiHub.fs(40), Color(ink, a), HORIZONTAL_ALIGNMENT_CENTER, 500, 6)
		Kit.line_fade(stage, Vector2(W * 0.38, H * 0.8), Vector2(W * 0.62, H * 0.8), Color(acc, a * 0.7), 1.0)
	else:
		var ft := clampf((t - lines.size() * 2.2) / 1.2, 0.0, 1.0)
		Kit.text(stage, Rect2(0, H * 0.7, W, 90), final_line, UiHub.fs(58), Color(ink, ft), HORIZONTAL_ALIGNMENT_CENTER, 600, 14)
		Kit.crescent(stage, c, 300.0, -PI * 0.5, -PI * 0.5 + TAU * ft * 0.5, 6.0, Color(acc, ft))

## skipped=true：玩家跳过（擦除转场+音效）；false：PV 自然放完（静静溶入标题页）。
func _finish(skipped := true) -> void:
	if done: return
	if root != null and root.busy:
		get_tree().create_timer(0.05).timeout.connect(func(): _finish(skipped))
		return
	done = true
	UiHub.mark_opening_seen()
	_stop_pv()
	if skipped: UiHub.sfx("start")
	var trans := "wipe" if skipped or not pv_ok else "fade"
	var nxt := String(params.get("next", "title"))
	if nxt == "title": root.go("title", {"phase": "menu"}, trans, "reset")
	else: root.go(nxt, params.get("next_params", {}), trans, "replace")

func _reveal_skip() -> void:
	if skip_revealed or not is_instance_valid(skip_btn): return
	skip_revealed = true
	skip_btn.visible = true
	UiHub.sfx("tick")
	if UiHub.reduced_motion:
		skip_btn.modulate.a = 0.85
		return
	var tw := skip_btn.create_tween()
	tw.tween_property(skip_btn, "modulate:a", 0.85, 0.24).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _gui_input(e: InputEvent) -> void:
	if phase != "intro" or done: return
	if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
		if not skip_revealed:
			_reveal_skip()
			accept_event()

func on_back() -> bool:
	if phase == "intro":
		if not skip_revealed: _reveal_skip()
		else: _finish(true)
		return true
	return false

func _unhandled_key_input(e: InputEvent) -> void:
	if phase == "intro" and e.pressed and e.is_action("ui_accept"):
		if not skip_revealed: _reveal_skip()
		else: _finish(true)
		get_viewport().set_input_as_handled()
