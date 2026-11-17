extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var app = load("res://scenes/rin_release_transition_03.tscn").instantiate()
	root.add_child(app); await process_frame
	if not app.ready_ok: push_error("missing transition assets"); quit(1); return
	app.set_process(false)
	for i in range(87):
		app.seek(float(i) / 24.0)
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png("res://evidence/rin-release-transition-03/frames/frame-%03d.png" % i) != OK:
			push_error("capture failed"); quit(1); return
	print("PASS: 87 transition captures at 24fps"); quit()
