extends Button
## A semantic control; geometry stays sharp at any window scale.
var ink := Color("454b53")
var accent := Color("cf1933")
var hover := 0.0
var motion: Tween
var reduced_motion := false

func _ready() -> void:
	flat = true
	tooltip_text = "返回标题页面"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(func(): feedback(1.0))
	mouse_exited.connect(func(): feedback(0.0))
	focus_entered.connect(func(): feedback(1.0))
	focus_exited.connect(func(): feedback(0.0))
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func feedback(target: float) -> void:
	if motion: motion.kill()
	if reduced_motion: hover=target; queue_redraw(); return
	motion=create_tween()
	motion.tween_method(func(v): hover=v; queue_redraw(),hover,target,0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _draw() -> void:
	var offset:=Vector2(0,2 if button_pressed else -2*hover)
	var plate:=PackedVector2Array([Vector2(12,0),Vector2(77,0),Vector2(64,64),Vector2(0,64)])
	for i in plate.size(): plate[i]+=offset
	draw_colored_polygon(plate,Color(ink,0.06+hover*0.06))
	var color:=ink.lerp(accent,hover)
	var center:=Vector2(38,31)+offset
	draw_arc(center,15,deg_to_rad(-48),deg_to_rad(228),40,color,3.0,true)
	draw_line(center+Vector2(0,-21),center+Vector2(0,-3),color,3.0,true)
	draw_line(Vector2(14,62)+offset,Vector2(59,62)+offset,Color(accent,0.45+0.55*hover),1.5,true)
	if has_focus(): draw_polyline(PackedVector2Array([plate[0],plate[1],plate[2],plate[3],plate[0]]),Color(accent,0.8),1.2,true)
