extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var app=load("res://scenes/rin_release_skill2_v2.tscn").instantiate(); root.add_child(app); await process_frame
    if not app.ready_ok: push_error("missing assets"); quit(1); return
    app.set_process(false); app.seek(0.1)
    var scale0:Vector2=app.actor.scale
    for t in [0.8,1.5,2.2,2.6,3.4]:
        app.seek(t)
        if app.actor.scale.distance_to(scale0)>0.0001: push_error("actor scale changed"); quit(1); return
    app.seek(2.48)
    var offset:Vector2=app.target.position-Vector2(960,405)
    if app.hitfx.position.distance_to(offset)>0.0001 or offset.length()<0.5: push_error("hit shake not synchronized"); quit(1); return
    print("PASS fixed sprite scale and synchronized impact shake"); quit()
