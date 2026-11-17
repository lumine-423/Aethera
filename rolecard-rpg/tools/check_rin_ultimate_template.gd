extends SceneTree
func _initialize() -> void: call_deferred("run")
func check(ok: bool, msg: String) -> void:
	if not ok: push_error(msg); quit(1)
func run() -> void:
	var app = load("res://scenes/rin_base_ultimate_template_01.tscn").instantiate()
	root.add_child(app)
	await process_frame
	if not app.ready_ok: push_error("Presentation did not load"); quit(1); return
	app.set_process(false)
	app.seek(0.0); check(app.idle.visible and not app.pose.visible, "idle start")
	app.seek(0.8); check(app.pose.visible and not app.idle.visible, "pose")
	app.seek(1.28); check(app.frame.visible and app.eyes.visible, "eye closeup")
	var held = app.frame.texture
	app.seek(1.42); check(app.frame.texture == held and app.eyes.visible, "closeup hold")
	app.seek(1.48); check(app.frame.visible and not app.eyes.visible, "mask exit")
	app.seek(2.14); check(app.strikes[0].visible, "first strike")
	app.seek(3.56 + 4.1 / 24.0); check(app.strikes[-1].visible, "final strike")
	var final_held = app.strikes[-1].texture
	app.seek(3.56 + 7.1 / 24.0); check(app.strikes[-1].texture == final_held, "peak hold")
	app.seek(3.84); check(app.hitfx.visible, "hit feedback")
	app.seek(4.4); check(app.idle.visible and not app.strikes[-1].visible, "idle restoration")
	app.set_paused(true); check(app.paused, "pause")
	app.restart(); check(not app.paused and app.elapsed == 0.0, "restart")
	app.skip(); check(app.paused and not app.pose.visible and not app.strikes[-1].visible, "skip")
	print("PASS ultimate assets, timeline, peak holds, pause, restart and skip; no combat state")
	quit()
