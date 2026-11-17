extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    root.size=Vector2i(960,720)
    var bg:=ColorRect.new(); bg.color=Color("e8edf2"); bg.size=Vector2(960,720); root.add_child(bg)
    var idle = load("res://scenes/rin_idle_drawn_01.tscn").instantiate(); idle.position=Vector2(480,665); root.add_child(idle)
    await process_frame
    if idle.sprite == null or idle.textures.size()!=5: push_error("frame load failed"); quit(1); return
    idle.set_process(false)
    var seen: Dictionary={}
    for i in range(102):
        idle.set_time(float(i)/30.0);seen[idle.current_index]=true
        await RenderingServer.frame_post_draw
        var err=root.get_texture().get_image().save_png("res://evidence/rin-idle-drawn-01/frame-%03d.png" % i)
        if err!=OK: push_error("capture failed"); quit(1); return
    if seen.size()!=5: push_error("not all frames shown"); quit(1); return
    idle.set_time(0.0);var start: int=idle.current_index;idle.set_time(idle.duration)
    if idle.current_index!=start: push_error("loop boundary error"); quit(1); return
    print("PASS: 5 drawn source images played, 102 GPU captures, loop returns first image; no visual acceptance implied")
    quit()

