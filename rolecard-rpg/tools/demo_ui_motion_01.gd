extends Node
## Scripted walk-through used to record the UI motion with Godot Movie Maker:
## Godot --path . res://tools/demo_ui_motion_01.tscn --write-movie <out.avi> --fixed-fps 30 --resolution 1280x720 -- --ui-review
const ROOT := preload("res://scenes/ui_root.tscn")
var ui

func _ready() -> void: call_deferred("run")

func wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func glide_mouse(to: Vector2, seconds := 0.4) -> void:
	var from := get_viewport().get_mouse_position()
	var steps := int(seconds * 30)
	for i in range(steps):
		var e := InputEventMouseMotion.new(); e.position = from.lerp(to, float(i + 1) / steps)
		Input.parse_input_event(e); await get_tree().process_frame

func at_node(n: Control) -> Vector2:
	return n.get_global_transform_with_canvas() * (n.size * 0.5)

func click_at(p: Vector2) -> void:
	await glide_mouse(p, 0.35)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new(); e.position = p; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed
		Input.parse_input_event(e); await get_tree().process_frame

func run() -> void:
	UiHub.set_night(false, false)
	ui = ROOT.instantiate(); add_child(ui)
	await wait(1.6)
	await click_at(Vector2(640, 360)); await wait(1.0)           # tap to start -> menu cascade
	var t = ui.current()
	for i in range(4):
		await glide_mouse(at_node(t.get_node("Menu%d" % i)), 0.3); await wait(0.25)   # cursor glides
	await click_at(at_node(t.get_node("Menu0"))); await wait(3.4)  # wipe -> loading -> home
	var sw := Vector2(get_viewport().get_visible_rect().size.x - 60, 58)
	await click_at(sw); await wait(1.4)                           # night: circular reveal
	ui.go("operations"); await wait(1.6)
	ui.go("party"); await wait(1.6)
	ui.go("battle", {}, "shutter"); await wait(2.4)
	var b = ui.current()
	b._choose(1); await wait(0.6)
	var enemy := 0
	for i in range(b.units.size()):
		if b.units[i].side == "enemy": enemy = i; break
	await glide_mouse(at_node(b.views[enemy]), 0.5); await wait(0.6)
	b._on_unit(enemy); await wait(1.4)
	b.open_detail(0); await wait(1.4); b.close_detail()
	ui.go("result", {"outcome": "win"}, "wipe", "replace"); await wait(2.8)
	var sw2 := Vector2(get_viewport().get_visible_rect().size.x - 117, 44)
	await click_at(sw2); await wait(1.3)                          # back to day
	ui.go("story", {"chapter": "ch1"}); await wait(2.0)
	var s = ui.current()
	s.advance(); await wait(1.6); s.advance(); await wait(1.8); s.advance(); await wait(1.2)
	s.advance(); await wait(1.6)
	s.panel._tap(0); await wait(1.0)
	s.panel._tap(1); await wait(1.0)
	s.panel._tap(3); await wait(0.6)
	s.panel.free_edit.text = "先去工坊区确认刻印的状态，再和她一起出发。"; s.panel._refresh_confirm(); await wait(0.8)
	s.panel._tap(1); await wait(0.8)
	s.panel._confirm(); await wait(1.6)
	ui._handle_back(); await wait(0.7)
	ui.dialog({"title": "行动暂停", "buttons": [{"id": "resume", "text": "继续行动", "icon": "play", "kind": "primary"}, {"id": "settings", "text": "设置", "icon": "gear"}]}); await wait(1.6)
	ui._handle_back(); await wait(0.8)
	ui.go("inventory"); await wait(1.8)
	ui.go("crafting"); await wait(1.2)
	var D = load("res://scripts/ui/ui_data.gd")
	ui.current()._make(D.demo().recipes[0]); await wait(2.4)
	get_tree().quit()
