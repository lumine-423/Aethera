extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    root.size=Vector2i(1280,720)
    var app=load("res://scenes/rin_flying_star_v3.tscn").instantiate(); root.add_child(app); await process_frame
    if not app.ready_ok: push_error("missing assets"); quit(1); return
    app.set_process(false)
    for i in range(120):
        app.seek(float(i)/24.0); await RenderingServer.frame_post_draw
        if root.get_texture().get_image().save_png("res://evidence/rin-flying-star-v3/frames/frame-%03d.png" % i) != OK: quit(1); return
    print("PASS 120 frames at 24fps"); quit()
