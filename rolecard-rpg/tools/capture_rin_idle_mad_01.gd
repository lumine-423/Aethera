extends SceneTree
const OUT := "res://evidence/rin-idle-mad-01/"
func _initialize() -> void: call_deferred("run")
func run() -> void:
    root.size = Vector2i(960,720)
    var bg := ColorRect.new(); bg.color = Color("e8edf2"); bg.size = Vector2(960,720); root.add_child(bg)
    var idle = load("res://scenes/rin_idle_mad_01.tscn").instantiate(); idle.position = Vector2(480,665); root.add_child(idle)
    await process_frame
    await process_frame
    if idle.sprite == null or idle.material_ref == null:
        push_error("idle failed to load"); quit(1); return
    idle.set_process(false)
    for i in range(108):
        idle.material_ref.set_shader_parameter("phase", TAU * float(i) / 108.0)
        await RenderingServer.frame_post_draw
        var image := root.get_texture().get_image()
        if image == null or image.is_empty(): push_error("empty render"); quit(1); return
        var err := image.save_png(OUT + "frame-%03d.png" % i)
        if err != OK: push_error("cannot save frame"); quit(1); return
    idle.set_motion_enabled(false)
    if idle.material_ref.get_shader_parameter("phase") != 0.0: push_error("motion toggle failed"); quit(1); return
    print("PASS: 108 GPU frames generated; 30 fps timeline, motion-off resets phase; human acceptance pending")
    quit()

