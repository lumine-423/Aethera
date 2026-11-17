extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var app = load("res://scenes/rin_base_ultimate_template_01.tscn").instantiate()
	root.add_child(app); await process_frame
	if not app.ready_ok: push_error("presentation missing assets"); quit(1); return
	app.set_process(false); app.idle.set_process(false)
	for i in range(6):
		var at: float = [0.8, 1.30, 2.41, 3.2, 3.75, 3.86][i]
		app.seek(at)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image.is_empty() or image.save_png("res://evidence/rin-ultimate-godot-01/phase-%d.png" % i) != OK:
			push_error("capture failed"); quit(1); return
	print("PASS: Godot GPU six timeline captures")
	quit()
