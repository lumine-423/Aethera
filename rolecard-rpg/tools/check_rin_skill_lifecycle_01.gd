extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
    for id in [1,2]:
        var app=load("res://scenes/rin_skill%d_sample_01.tscn"%id).instantiate();root.add_child(app);await process_frame;app.set_process(false)
        if app.fx==null or app.fx.frames.size()!=12:push_error("missing frames");quit(1);return
        app.set_time(1.21);var start:float=app.fx.scale.x
        app.set_time(1.36);var expanded:float=app.fx.scale.x
        app.set_time(1.68);var ending:float=app.fx.scale.x
        app.set_time(1.71);var vanished:bool=not app.fx.visible
        if not (start < expanded and ending < expanded and vanished):push_error("appear/expand/vanish failed");quit(1);return
        app.queue_free();await process_frame
    print("PASS: both 12-image 24fps effects show expansion and disappearance, measured at distinct times")
    quit()
