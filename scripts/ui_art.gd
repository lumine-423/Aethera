extends Control
## Original resolution-independent drawing; supplied project portraits stay separate.
const Palette = preload("res://scripts/ui_theme.gd")
var kind := "sigil"
var portrait: Texture2D
var crop_top := 0.0
var wash := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)

func _draw() -> void:
	var ink := Palette.color("text")
	var line := Palette.color("border")
	var accent := Palette.color("accent")
	var w := size.x
	var h := size.y
	if kind == "portrait":
		draw_rect(Rect2(Vector2.ZERO,size),Palette.color("soft"))
		if portrait != null:
			var ts := portrait.get_size()
			var scale_value := maxf(w/ts.x,h/ts.y)
			var source := Vector2(w,h)/scale_value
			var origin := Vector2((ts.x-source.x)*0.5,(ts.y-source.y)*crop_top)
			draw_texture_rect_region(portrait,Rect2(Vector2.ZERO,size),Rect2(origin,source))
			if wash: draw_rect(Rect2(Vector2.ZERO,size),Color(Palette.color("background"),0.13))
		return
	if kind == "backdrop":
		draw_rect(Rect2(Vector2.ZERO,size),Palette.color("background"))
		for x in range(0,int(w),36):
			for y in range(0,int(h),36): draw_circle(Vector2(x,y),0.65,Color(line,0.5))
		var center := Vector2(w*0.35,h*0.52)
		for r in [h*0.33,h*0.36,h*0.57]: draw_arc(center,r,0,TAU,100,Color(line,0.45),1,true)
		draw_line(Vector2(w*0.67,0),Vector2(w*0.36,h),Color(line,0.45),1,true)
		return
	if kind == "mission":
		draw_rect(Rect2(Vector2.ZERO,size),Palette.color("soft"))
		for i in range(7):
			var x := w*0.1+i*w*0.13
			draw_line(Vector2(x,0),Vector2(x-h*0.25,h),line,1,true)
		for i in range(4): draw_line(Vector2(0,h*i/3.0),Vector2(w,h*i/3.0),line,1,true)
		var c := Vector2(w*0.52,h*0.5)
		var r := minf(h*0.32,w*0.25)
		draw_arc(c,r,0,TAU,64,accent,2,true)
		draw_arc(c,r*0.7,0.3,4.5,48,line,4,true)
		draw_colored_polygon(PackedVector2Array([c+Vector2(0,-r*0.7),c+Vector2(r*0.65,0),c+Vector2(0,r*0.7),c+Vector2(-r*0.65,0)]),accent)
		draw_line(c+Vector2(-r*1.5,0),c+Vector2(r*1.5,0),accent,1,true)
		draw_circle(c,5,Palette.color("surface"))
		return
	var c := size/2
	var r := minf(w,h)*0.39
	var points := PackedVector2Array([c+Vector2(0,-r),c+Vector2(r,0),c+Vector2(0,r),c+Vector2(-r,0),c+Vector2(0,-r)])
	draw_polyline(points,accent,2,true)
	draw_arc(c,r*0.62,0,TAU,40,ink,1.5,true)
	draw_line(c+Vector2(0,-r*1.2),c+Vector2(0,r*1.2),accent,1.5,true)
	draw_line(c+Vector2(-r*1.2,0),c+Vector2(r*1.2,0),accent,1.5,true)
	draw_circle(c,r*0.15,accent)

