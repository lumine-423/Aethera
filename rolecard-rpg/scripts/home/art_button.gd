extends Button
const Motion = preload("res://scripts/home/motion.gd")
## Each button owns its plate, glyph and editable label; no screenshot hit boxes.
var visual: Control
var entrance_layer: Control
var face: TextureRect
var glyph_node: TextureRect
var caption: Label
var tint_material: ShaderMaterial
var hover_tween: Tween
var reduced_motion := false
var accent := Color("cf203a")
var base_font_size := 32
var hovered := false
var sheen_tween:Tween
var down_state:=false
var reference_text:TextureRect
var reference_title:=""
var reference_rect:=Rect2()

func bind_reference_text(texture:Texture2D,paint:ShaderMaterial,title:String,rect:Rect2) -> void:
	reference_title=title; reference_rect=rect
	reference_text=TextureRect.new(); reference_text.name="ReferenceLettering"; reference_text.texture=texture; reference_text.material=paint
	reference_text.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; reference_text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	visual.add_child(reference_text); arrange()

func _process(_delta:float) -> void:
	if reference_text:
		var original:=caption.text==reference_title
		caption.visible=not original; reference_text.visible=original

func _ready() -> void:
	flat = true
	text = ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(func(): hovered = true; feedback())
	mouse_exited.connect(func(): hovered = false; feedback())
	focus_entered.connect(feedback)
	focus_exited.connect(feedback)
	button_down.connect(func(): feedback(true))
	button_up.connect(feedback)
	resized.connect(func(): if visual: visual.size = size; queue_redraw())

func configure(plate: Texture2D, glyph_tex: Texture2D, title: String, font: Font, material_instance: ShaderMaterial, spec: Dictionary) -> void:
	tint_material = material_instance
	entrance_layer=Control.new(); entrance_layer.name="EntranceLayer"; entrance_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(entrance_layer)
	visual = Control.new(); visual.name = "HoverLayer"; visual.mouse_filter = Control.MOUSE_FILTER_IGNORE; entrance_layer.add_child(visual)
	face = TextureRect.new(); face.name = "Plate"; face.texture = plate; face.material = material_instance
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; face.stretch_mode = TextureRect.STRETCH_SCALE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE; visual.add_child(face); face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph_node = TextureRect.new(); glyph_node.name = "Glyph"; glyph_node.texture = glyph_tex
	glyph_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; glyph_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph_node.mouse_filter = Control.MOUSE_FILTER_IGNORE; visual.add_child(glyph_node)
	caption = Label.new(); caption.name = "EditableText"; caption.text = title
	caption.add_theme_font_override("font", font); caption.add_theme_constant_override("outline_size", 0)
	base_font_size = int(spec.get("font", 32)); caption.add_theme_font_size_override("font_size", base_font_size)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(caption)
	set_meta("label_rect", spec.get("label_rect", [110, 5, 260, 75]))
	set_meta("icon_rect", spec.get("icon_rect", [45, 18, 50, 50]))
	set_meta("reference_size", Vector2(spec.get("rect", [0,0,420,90])[2], spec.get("rect", [0,0,420,90])[3]))
	resized.connect(arrange)
	arrange()

func arrange() -> void:
	if not visual: return
	visual.size = size
	entrance_layer.size = size
	var ref: Vector2 = get_meta("reference_size", size)
	var factor := size / ref
	for pair in [[glyph_node,"icon_rect"], [caption,"label_rect"]]:
		var r: Array = get_meta(pair[1]); pair[0].position = Vector2(r[0],r[1]) * factor
		pair[0].size = Vector2(r[2],r[3]) * factor
	caption.add_theme_font_size_override("font_size", int(base_font_size * minf(factor.x, factor.y)))
	if reference_text:
		reference_text.position=reference_rect.position*factor; reference_text.size=reference_rect.size*factor; reference_text.pivot_offset=reference_text.size*0.5

func feedback(down := false) -> void:
	if not visual: return
	if hover_tween: hover_tween.kill()
	var active := hovered or has_focus()
	down_state=down
	var target := Vector2(0,2 if down else -3 if active else 0)
	if reduced_motion:
		visual.position = target
	else:
		var start:=visual.position
		hover_tween=create_tween()
		hover_tween.tween_method(func(v): visual.position=start.lerp(target,Motion.ease(v,Motion.EASE)),0.0,1.0,0.2)
	tint_material.set_shader_parameter("hover_amount", 1.0 if active else 0.0)
	if active and not down and not reduced_motion:
		if sheen_tween: sheen_tween.kill()
		tint_material.set_shader_parameter("sheen_strength",0.45)
		sheen_tween=create_tween()
		sheen_tween.tween_method(func(v): tint_material.set_shader_parameter("sheen_position",lerpf(-0.6,1.2,Motion.ease(v,Motion.EASE))),0.0,1.0,0.55)
		sheen_tween.tween_callback(func(): tint_material.set_shader_parameter("sheen_strength",0.0))
	elif not active or reduced_motion:
		if sheen_tween: sheen_tween.kill()
		tint_material.set_shader_parameter("sheen_strength",0.0)
	queue_redraw()

func _has_point(point: Vector2) -> bool:
	if size.x <= 0 or size.y <= 0: return false
	var p := point / size
	return p.y >= 0.0 and p.y <= 1.0 and p.x >= 0.12 * (1.0-p.y) and p.x <= 1.0 - 0.12*p.y

func _draw() -> void:
	if has_focus():
		draw_polyline(PackedVector2Array([Vector2(size.x*0.12,2),Vector2(size.x-2,2),Vector2(size.x*0.88,size.y-2),Vector2(2,size.y-2),Vector2(size.x*0.12,2)]),accent,2.5,true)
