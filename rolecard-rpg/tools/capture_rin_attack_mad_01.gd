extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    root.size=Vector2i(1280,720)
    var app=load("res://scenes/rin_attack_mad_01.tscn").instantiate();root.add_child(app)
    await process_frame
    if app.pose==null or app.effect==null or app.cut_frames.size()!=3: push_error("resource load failed");quit(1);return
    app.set_process(false);app.idle.set_process(false)
    var phases := {}
    for i in range(132):
        app.set_time(float(i)/30.0)
        app.idle.material_ref.set_shader_parameter("phase", fposmod(float(i)/30.0, app.idle.loop_seconds) / app.idle.loop_seconds * TAU)
        if app.pose.visible: phases["pose"]=true
        if app.effect.visible: phases["fx"]=true
        if app.lines.visible: phases["lines"]=true
        if app.idle.visible: phases["idle"]=true
        await RenderingServer.frame_post_draw
        var err=root.get_texture().get_image().save_png("res://evidence/rin-attack-mad-01/frame-%03d.png"%i)
        if err!=OK: push_error("capture failed");quit(1);return
    if phases.size()!=4:push_error("missing phase");quit(1);return
    app.set_time(0.0);if not app.idle.visible or app.pose.visible:push_error("idle restore failed");quit(1);return
    print("PASS: idle, attack, speed-line, VFX phases displayed and loop returns to idle; visual acceptance pending")
    quit()

