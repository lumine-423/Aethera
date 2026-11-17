extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
    root.size=Vector2i(960,720)
    var bg:=ColorRect.new();bg.color=Color("e8edf2");bg.size=Vector2(960,720);root.add_child(bg)
    var idle=load("res://scenes/rin_idle_mad_01.tscn").instantiate();idle.character_path="res://assets/characters/rin-idle-mad-02/rin-base.png";idle.position=Vector2(480,665);root.add_child(idle)
    await process_frame
    if idle.material_ref==null:push_error("idle missing");quit(1);return
    idle.set_process(false)
    for i in range(109):
        var tm=float(i)/30.0;idle.material_ref.set_shader_parameter("phase",fposmod(tm,idle.loop_seconds)/idle.loop_seconds*TAU)
        await RenderingServer.frame_post_draw
        var err=root.get_texture().get_image().save_png("res://evidence/rin-idle-seam-01/frame-%03d.png"%i)
        if err!=OK:push_error("capture failed");quit(1);return
    print("PASS: idle 108-frame cycle plus repeated first frame captured at 30fps")
    quit()
