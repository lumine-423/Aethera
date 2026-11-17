extends Button
const Palette = preload("res://scripts/ui_theme.gd")
var heading := ""
var subtitle := ""
var primary := false
var emblem := "arrow"
var heading_size := 28

func _ready() -> void:
	for state in ["normal","hover","pressed","disabled","focus"]: add_theme_stylebox_override(state,StyleBoxEmpty.new())
	resized.connect(queue_redraw); mouse_entered.connect(queue_redraw); mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw); focus_exited.connect(queue_redraw)

func _draw() -> void:
	var w := size.x; var h := size.y
	var paper := Palette.color("accent") if primary else Palette.color("surface")
	var ink := Palette.color("on_accent") if primary else Palette.color("text")
	if is_hovered(): paper = paper.lerp(ink,0.08)
	if button_pressed: paper = paper.lerp(ink,0.16)
	if disabled: paper = Palette.color("disabled"); ink = Palette.color("muted")
	var cut := minf(24,h*0.18)
	var points := PackedVector2Array([Vector2(0,0),Vector2(w,0),Vector2(w,h-cut),Vector2(w-cut,h),Vector2(0,h),Vector2(0,0)])
	draw_colored_polygon(points,paper)
	draw_polyline(points,Palette.color("accent") if has_focus() else Palette.color("border"),2 if has_focus() else 1,true)
	var font := get_theme_default_font()
	var base := 50.0 if h > 150 else 35.0
	draw_string(font,Vector2(24,base),heading,HORIZONTAL_ALIGNMENT_LEFT,w-80,heading_size,ink)
	draw_string(font,Vector2(24,base+32),subtitle,HORIZONTAL_ALIGNMENT_LEFT,w-58,15,Color(ink,0.85))
	var c := Vector2(w-43,h-38)
	draw_line(c-Vector2(16,0),c+Vector2(10,0),ink,2,true)
	draw_polyline(PackedVector2Array([c+Vector2(2,-8),c+Vector2(10,0),c+Vector2(2,8)]),ink,2,true)
	if primary:
		var center := Vector2(w*0.8,h*0.33)
		for r in [h*.38,h*.48,h*.65]: draw_arc(center,r,-1.4,1.7,60,Color(ink,0.12),1,true)
		draw_line(Vector2(24,h-29),Vector2(w*.51,h-29),Color(ink,0.55),1,true)
		draw_circle(Vector2(24,h-29),3,ink)
