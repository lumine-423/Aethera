extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app = load("res://scenes/rin_release_transition_01.tscn").instantiate()
	root.add_child(app); await process_frame
	if not app.ready_ok or app.frames.size() != 24: push_error("missing transition assets"); quit(1); return
	app.set_process(false)
	app.seek(0.0)
	if not app.base.visible or app.released.visible or app.chain.visible: push_error("incorrect start"); quit(1); return
	app.seek(0.65)
	if not app.chain.visible or not app.base.visible: push_error("chain did not appear"); quit(1); return
	app.seek(1.62)
	if app.flash.color.a <= 0.0 or not app.base.visible: push_error("flash should precede switch"); quit(1); return
	app.seek(1.625)
	if app.flash.color.a != 1.0 or app.flash.size != Vector2(1280, 720): push_error("missing fully white frame"); quit(1); return
	app.seek(1.70)
	if not app.released.visible or app.base.visible or app.flash.color.a <= 0.0: push_error("release switch"); quit(1); return
	app.seek(2.0)
	if not app.released.visible or app.chain.visible or app.flash.color.a > 0.0: push_error("release hold"); quit(1); return
	app.restart()
	if not app.playing or app.elapsed != 0.0: push_error("restart"); quit(1); return
	app.skip()
	if app.playing or not app.released.visible: push_error("skip"); quit(1); return
	print("PASS: 24 chain frames, flash, form switch, restart, skip; no combat state")
	quit()
