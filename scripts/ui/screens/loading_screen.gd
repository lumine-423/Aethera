extends "res://scripts/ui/ui_screen.gd"
## 载入画面. params: next, next_params, label, duration.
## Real loads call set_progress(0..1) and finish(); with no service attached it runs a short preview.

var progress := 0.0
var spinner: Control
var meter: Control
var pct: Label
var finished := false

class Spinner extends Control:
	const K = preload("res://scripts/ui/ui_kit.gd")
	var clock := 0.0
	func _ready() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(d: float) -> void:
		clock += d * (0.25 if UiHub.reduced_motion else 1.0); queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		for i in range(4):
			var phase := fmod(clock * 1.4 + i * 0.25, 1.0)
			var s := 18.0 + 6.0 * sin(phase * TAU)
			var p := c + Vector2.from_angle(PI * 0.5 * i + clock * 1.2) * 46.0
			K.diamond(self, p, s, UiHub.c("accent" if i == 0 else "ink", 1.0 if i == 0 else 0.35 + 0.4 * phase))
		K.diamond(self, c, 70.0, UiHub.c("line"), 2.0)

func build() -> void:
	decor(23, Rect2(Vector2.ZERO, size), 0.8)
	spinner = Spinner.new(); put(spinner, Rect2(1600, 820, 180, 180), "rb")
	var label: String = params.get("label", "载入中")
	text(label, Rect2(1180, 870, 400, 60), 36, "ink", 850, "rb", null, HORIZONTAL_ALIGNMENT_RIGHT)
	meter = bar(Rect2(980, 950, 600, 10), progress, 1.0, "accent", null, "rb")
	pct = text("%d%%" % int(progress * 100), Rect2(1420, 960, 160, 40), 22, "muted", 700, "rb", null, HORIZONTAL_ALIGNMENT_RIGHT)
	var tips: Array = Data.demo().tips
	var tip: String = tips[randi() % tips.size()]
	var p := plate(Rect2(80, 860, 820, 120), {"slant": 30, "stripe": "left", "hatch": true}, "lb", 0.1)
	text("提示", Rect2(50, 14, 200, 40), 22, "accent", 800, "c", p)
	text(tip, Rect2(50, 54, 720, 50), 26, "ink", 600, "c", p)

func on_shown() -> void: pass

func enter(delay := 0.0) -> void:
	super.enter(delay)
	UiHub.request("loading.started", {"next": params.get("next", "home")})
	var dur: float = params.get("duration", 1.3)
	var t := create_tween()
	t.tween_method(set_progress, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE)
	t.tween_callback(finish)

func set_progress(v: float) -> void:
	progress = v
	if is_instance_valid(meter): meter.set_value(v, false)
	if is_instance_valid(pct): pct.text = "%d%%" % int(v * 100)

func finish() -> void:
	if finished: return
	if root != null and root.busy:
		get_tree().create_timer(0.05).timeout.connect(finish)
		return
	finished = true
	UiHub.sfx("loaded")
	root.go(params.get("next", "home"), params.get("next_params", {}), "fade", "replace")
