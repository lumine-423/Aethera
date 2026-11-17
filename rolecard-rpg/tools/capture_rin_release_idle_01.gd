extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    root.size = Vector2i(1280, 720)
    var app = load("res://scenes/rin_release_idle_01.tscn").instantiate()
    root.add_child(app); await process_frame
    if not app.ready_ok: push_error("missing idle source"); quit(1); return
    app.set_process(false)
    app.seek(0.0)
    var p0: Vector2 = app.actor.position
    var phase0: float = app.breath.get_shader_parameter("phase")
    app.seek(4.0)
    if app.actor.position.distance_to(p0) > 0.0001 or absf(float(app.breath.get_shader_parameter("phase")) - phase0) > 0.0001:
        push_error("loop seam mismatch"); quit(1); return
    for i in range(96):
        app.seek(float(i) / 24.0)
        await RenderingServer.frame_post_draw
        if root.get_texture().get_image().save_png("res://evidence/rin-release-idle-01/frames/frame-%03d.png" % i) != OK: quit(1); return
    print("PASS: 96 captures at 24fps; 4 second loop seam exact"); quit()
