extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    root.size=Vector2i(960,720)
    var app=load("res://scenes/rin_reaction_sample_01.tscn").instantiate();root.add_child(app)
    await process_frame
    if app.figure==null or app.hitfx==null:push_error("missing reaction asset");quit(1);return
    app.set_process(false);app.idle.set_process(false)
    var seen:={}
    for i in range(180):
        var t=float(i)/30.0;app.set_time(t)
        app.idle.material_ref.set_shader_parameter("phase",fposmod(t,app.idle.loop_seconds)/app.idle.loop_seconds*TAU)
        if app.figure.visible:
            for k in app.poses:
                if app.figure.texture==app.poses[k]:seen[k]=true
        if app.hitfx.visible:seen["hitfx"]=true
        await RenderingServer.frame_post_draw
        var err=root.get_texture().get_image().save_png("res://evidence/rin-reactions-01/reaction-%03d.png"%i)
        if err!=OK:push_error("capture failed");quit(1);return
    if seen.size()!=4:push_error("missing reaction state");quit(1);return
    print("PASS: hit, down candidate, victory and local impact graphic rendered; visual acceptance pending")
    quit()
