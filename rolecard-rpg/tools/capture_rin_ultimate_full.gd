extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	var app = load("res://scenes/rin_base_ultimate_template_01.tscn").instantiate()
	root.add_child(app); await process_frame
	if not app.ready_ok: push_error("presentation missing assets"); quit(1); return
	app.set_process(false); app.idle.set_process(false)
	for i in range(173):
		var at := float(i) / 24.0
		app.seek(at)
		app.idle.material_ref.set_shader_parameter("phase", fposmod(at, 3.6) / 3.6 * TAU)
		await RenderingServer.frame_post_draw
		if root.get_texture().get_image().save_png("res://evidence/rin-ultimate-godot-01/frames/frame-%03d.png" % i) != OK:
			push_error("capture failed"); quit(1); return
	print("PASS: captured 173 Godot frames at 24fps")
	quit()
