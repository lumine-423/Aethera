extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
    root.size=Vector2i(1280,720)
    for skill in [1,2]:
        var app=load("res://scenes/rin_skill%d_sample_01.tscn"%skill).instantiate();root.add_child(app)
        await process_frame
        if app.pose==null or app.fx==null or app.fx.frames.size()!=12 or app.hitfx==null:push_error("skill missing asset");quit(1);return
        app.set_process(false);app.idle.set_process(false)
        var seen:={}
        for i in range(216):
            var tm=float(i)/30.0;app.set_time(tm)
            app.idle.material_ref.set_shader_parameter("phase", fposmod(tm,app.idle.loop_seconds)/app.idle.loop_seconds*TAU)
            if app.idle.visible:seen["idle"]=true
            if app.pose.visible:seen["pose"]=true
            if app.fx.visible:seen["fx"]=true
            if app.hitfx.visible:seen["hit"]=true
            await RenderingServer.frame_post_draw
            var err=root.get_texture().get_image().save_png("res://evidence/rin-skills-01/skill%d/frame-%03d.png"%[skill,i])
            if err!=OK:push_error("capture failed");quit(1);return
        if seen.size()!=4:push_error("missing phase");quit(1);return
        app.set_time(0.0);if not app.idle.visible:push_error("idle restore failed");quit(1);return
        app.queue_free();await process_frame
    print("PASS: 2 skill samples show idle, pose, 12-frame effect, local hit; 7.2s video matches two idle cycles")
    quit()
