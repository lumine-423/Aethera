extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app = load("res://scenes/rin_guard_sample_01.tscn").instantiate()
	root.add_child(app); await process_frame
	if app.pose == null: push_error("missing guard"); quit(1); return
	app.set_process(false); app.seek(1.0)
	if not app.pose.visible or app.idle.visible: push_error("guard did not appear"); quit(1); return
	app.seek(1.21)
	if not app.hitfx.visible or app.hitfx.effect_path != "res://assets/effects/shared-hit-outline-02/impact.png": push_error("missing shared hit feedback"); quit(1); return
	if not is_equal_approx(app.pose.position.x - 480.0, app.hitfx.position.x): push_error("guard and effect shake do not match"); quit(1); return
	app.seek(3.0)
	if app.pose.visible or not app.idle.visible or app.hitfx.visible: push_error("idle did not return"); quit(1); return
	print("PASS guard pose, shared hit image, synchronized local shake and idle transition"); quit()
