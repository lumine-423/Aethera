extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var holder:=Node2D.new();root.add_child(holder)
    var fx=load("res://scripts/battle_art/hit_feedback.gd").new();holder.add_child(fx)
    if fx.image == null:push_error("missing hit image");quit(1);return
    var before:Vector2=fx.seek(-0.01)
    if fx.visible or before!=Vector2.ZERO:push_error("effect before hit");quit(1);return
    var during:Vector2=fx.seek(0.08)
    if not fx.visible or during==Vector2.ZERO or fx.position!=during:push_error("local shake missing");quit(1);return
    var after:Vector2=fx.seek(0.25)
    if fx.visible or after!=Vector2.ZERO:push_error("effect did not finish");quit(1);return
    holder.free()
    print("PASS: one still image; local shake only while impact active, then restore")
    quit()
