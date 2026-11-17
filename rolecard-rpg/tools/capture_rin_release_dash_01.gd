extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    root.size=Vector2i(1280,720)
    for is_ultimate in [false,true]:
        var scene := "res://scenes/rin_release_ultimate_candidate.tscn" if is_ultimate else "res://scenes/rin_release_skill2_candidate.tscn"
        var app=load(scene).instantiate(); root.add_child(app); await process_frame
        if not app.ready_ok: push_error("Missing presentation assets"); quit(1); return
        app.set_process(false)
        var folder := "ultimate" if is_ultimate else "skill2"
        for i in range(120):
            app.seek(float(i)/24.0); await RenderingServer.frame_post_draw
            if root.get_texture().get_image().save_png("res://evidence/rin-release-dash-01/"+folder+"/frame-%03d.png" % i) != OK: quit(1); return
        app.queue_free(); await process_frame
    print("PASS both presentations captured 120 frames at 24fps"); quit()
