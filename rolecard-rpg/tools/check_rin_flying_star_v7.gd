extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var app=load("res://scenes/rin_flying_star_v7.tscn").instantiate(); root.add_child(app); await process_frame
    if not app.ready_ok: quit(1); return
    app.set_process(false)
    var previous=-999.0
    for i in range(27):
        var t=0.65+float(i)*1.08/26.0
        app.seek(t)
        if app.actor.flip_h or app.actor.position.x < previous: push_error("wrong direction"); quit(1); return
        previous=app.actor.position.x
    var v1=app.flight_position(1.05).x-app.flight_position(0.95).x
    var v2=app.flight_position(1.65).x-app.flight_position(1.55).x
    if v2<=v1: push_error("not accelerating"); quit(1); return
    app.seek(1.90)
    if not app.impact.visible: push_error("impact missing"); quit(1); return
    print("PASS continuous rightward acceleration and final impact"); quit()
