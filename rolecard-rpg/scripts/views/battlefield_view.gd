extends Control
const Library = preload("res://scripts/animation_library.gd")
const Palette = preload("res://scripts/ui_theme.gd")
var snapshot: Dictionary = {}
var selected := ""
var library = Library.new()
var sprites: Array[AnimatedSprite2D] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(queue_redraw)

func set_state(value: Dictionary, actor_id: String) -> void:
	snapshot = value.duplicate(true); selected = actor_id; queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Palette.color("soft"))
	var mid := size.y*0.76
	draw_colored_polygon(PackedVector2Array([Vector2(0,mid),Vector2(size.x,mid),Vector2(size.x,size.y),Vector2(0,size.y)]),Palette.color("background"))
	for index in range(1,6): draw_line(Vector2(size.x*index/6.0,mid),Vector2(size.x*(index-0.5)/5.0,size.y),Palette.color("border"),1)
	draw_line(Vector2(size.x*0.5,20),Vector2(size.x*0.5,size.y-15),Palette.color("border"),1)
	if snapshot.is_empty(): return
	var font := get_theme_default_font()
	for side in ["allies","enemies"]:
		var units: Array = snapshot[side]
		for index in range(units.size()):
			var member: Dictionary = units[index]
			var root := Vector2(size.x*(0.2+index*0.14 if side=="allies" else 0.67+index*0.14),mid)
			var color := Palette.color("ally" if side=="allies" else "enemy")
			if member.hp<=0: color = Color("53616a")
			if member.id==selected: draw_arc(root+Vector2(0,2),24,0,TAU,24,Palette.color("accent"),2)
			draw_colored_polygon(PackedVector2Array([root+Vector2(0,-61),root+Vector2(23,-35),root+Vector2(0,-9),root+Vector2(-23,-35)]),color.darkened(.55))
			draw_circle(root+Vector2(0,-35),8,color)
			draw_string(font,root+Vector2(-60,-78),member.name,HORIZONTAL_ALIGNMENT_CENTER,120,16,color)
			if member.hp<=0: draw_line(root+Vector2(-10,-45),root+Vector2(10,-25),color,3)
	# These geometric role marks are deliberate asset fallbacks, not character art.

func attach_clip(actor_id: String, form: String, action: String) -> bool:
	var clip: Dictionary = library.resolve_clip(actor_id,form,action)
	if not clip.ok: return false
	var sprite := AnimatedSprite2D.new(); sprite.sprite_frames = clip.frames; sprite.centered = false
	sprite.position = Vector2(size.x*.2,size.y*.76)-clip.anchor
	add_child(sprite); sprites.append(sprite); sprite.play(action)
	return true
