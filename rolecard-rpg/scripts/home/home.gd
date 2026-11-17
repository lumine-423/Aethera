extends Control
## Home-only art assembly. Existing combat, saves and rejected UI stay separate.
signal navigation_requested(destination: String)
signal character_message_requested(character_id: String, message: String)
const ArtButton = preload("res://scripts/home/art_button.gd")
const CharacterPanel = preload("res://scripts/home/character_panel.gd")
const Paint = preload("res://scripts/home/palette.gdshader")
const FONT = preload("res://assets/fonts/NotoSansSC.ttf")
const ROOT_ART := "res://assets/ui/home-v1/"
const DETAIL_ART := "res://assets/ui/fidelity-v2/"
const Motion = preload("res://scripts/home/motion.gd")
const PowerButton = preload("res://scripts/home/power_button.gd")
var detailed_regions:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DETAIL_ART+"regions.json"))
const OPTIONS_PATH := "user://home_ui_sample.cfg"
var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/home_layout.json"))
var regions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT_ART+"regions.json"))
var palette: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/home_palette.json"))
var materials: Array[WeakRef] = []
var main_font: FontVariation
var body_font: FontVariation
var colored_controls: Array[Control] = []
var home_buttons: Dictionary = {}
var art_buttons: Array = []
var icons: Array = []
var labels: Array = []
var entrance_tweens: Array[Tween] = []
var stage: Control
var menu: Control
var background: TextureRect
var decorations: TextureRect
var status: Button
var status_name: Label
var shade: ColorRect
var modal: Control
var modal_kind := ""
var modal_source: Control
var page_slot: Control
var wipe: Control
var wipe_tween: Tween
var theme_tween: Tween
var modal_tween: Tween
var theme_target := false
var night_amount := 0.0
var reduced_motion := false
var spacing := 0.5
var text_scale := 1.0
var busy := false
var route := "home"
var selected_character := ""
var character_messages: Dictionary = {}
var character_detail: Control
var logical_size := Vector2(1672,941)
var review_mode := false
var theme_icon_tweens:Dictionary={}
var status_motion:Tween
var status_face:TextureRect
var status_visual:Control
var ambient_clock:=0.0
var power: Button

func _ready() -> void:
	review_mode = "--home-review" in OS.get_cmdline_user_args()
	main_font=FontVariation.new(); main_font.base_font=FONT; main_font.variation_opentype={2003265652:850.0}
	body_font=FontVariation.new(); body_font.base_font=FONT; body_font.variation_opentype={2003265652:600.0}
	theme=Theme.new(); theme.default_font=body_font; theme.default_font_size=26
	get_window().title="主页"
	if not review_mode: _load_options()
	clip_contents = true
	stage = Control.new(); stage.name = "HomeComposition"; stage.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(stage)
	background = _art(stage,"background.png",Vector2.ZERO,logical_size,false)
	background.name = "BackgroundBase"
	decorations = _art(stage,"decoration.png",Vector2.ZERO,logical_size,true)
	decorations.name = "IndependentAccents"
	background.material.set_shader_parameter("backdrop",true)
	decorations.material.set_shader_parameter("backdrop",true)
	menu = Control.new(); menu.name = "HomeControls"; stage.add_child(menu); menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for spec in layout.buttons:
		var b = _button(menu,spec)
		home_buttons[spec.id] = b
		b.pressed.connect(func(): if spec.id == "settings" and not has_meta("external_router"): open_modal("settings",b)
		else: navigate(spec.id))
	_build_status()
	_build_theme_switch()
	power=PowerButton.new(); power.name="ReturnToTitle"; power.size=Vector2(78,64); power.position=Vector2(30,30); menu.add_child(power)
	power.pressed.connect(func(): navigate("title"))
	page_slot = Control.new(); page_slot.name = "FutureRouteSlot"; page_slot.visible = false; stage.add_child(page_slot)
	shade = ColorRect.new(); shade.name = "ModalShade"; shade.visible = false; shade.mouse_filter = Control.MOUSE_FILTER_STOP; stage.add_child(shade)
	shade.gui_input.connect(func(event): if event is InputEventMouseButton and event.pressed: close_modal())
	modal = Control.new(); modal.name = "SecondaryWindow"; modal.visible = false; stage.add_child(modal)
	wipe = Control.new(); wipe.name = "TransitionCurtain"; wipe.visible = false; wipe.mouse_filter = Control.MOUSE_FILTER_STOP; stage.add_child(wipe)
	resized.connect(arrange)
	_bind_hub()
	arrange(); _paint(); entrance()
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.homeReady = true",true)

## Shared UI hub (autoload) when present: day/night and display options follow the full UI.
## Looked up by path so standalone --script tools that skip autoloads still compile and run.
func _hub() -> Node:
	return get_node_or_null("/root/UiHub")

func _bind_hub() -> void:
	var hub = _hub()
	if hub == null: return
	night_amount = hub.night; theme_target = hub.night_target
	reduced_motion = hub.reduced_motion; spacing = hub.spacing; text_scale = hub.text_scale
	var on_palette := func() -> void:
		night_amount = hub.night; theme_target = hub.night_target; _paint()
	var on_options := func() -> void:
		reduced_motion = hub.reduced_motion; spacing = hub.spacing; text_scale = hub.text_scale; arrange(); _paint()
	hub.palette_changed.connect(on_palette)
	hub.options_changed.connect(on_options)

func _process(delta: float) -> void:
	if reduced_motion or not is_instance_valid(background): return
	ambient_clock+=delta
	background.material.set_shader_parameter("motion_time",ambient_clock)
	decorations.material.set_shader_parameter("motion_time",ambient_clock)

func _material(clean := true, decorative := false) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = Paint
	m.set_shader_parameter("clean_alpha",clean); m.set_shader_parameter("decorative",decorative)
	for pair in [["night_base_color","background"],["night_plane_color","plane"],["night_accent_color","accent"],["night_decoration_color","decoration"]]:
		m.set_shader_parameter(pair[0],Color(palette.night[pair[1]]))
	m.set_shader_parameter("day_accent_color",Color(palette.day.accent))
	m.set_shader_parameter("night_mix",night_amount); materials.append(weakref(m)); return m

func _color(role: String) -> Color:
	return Color(palette.day[role]).lerp(Color(palette.night[role]),night_amount)

func _clip_material(m: ShaderMaterial, texture: AtlasTexture, slant: float) -> void:
	var extent := texture.atlas.get_size(); var r := texture.region
	m.set_shader_parameter("art_region",Vector4(r.position.x/extent.x,r.position.y/extent.y,r.size.x/extent.x,r.size.y/extent.y))
	m.set_shader_parameter("edge_slant",slant)

func atlas(kind: String, id: String) -> AtlasTexture:
	var tex := AtlasTexture.new(); tex.atlas = load(ROOT_ART+kind+".png")
	var r: Array = regions[kind][id]; tex.region = Rect2(r[0],r[1],r[2],r[3]); tex.filter_clip = true; return tex

func detailed_atlas(id:String) -> AtlasTexture:
	var tex:=AtlasTexture.new(); tex.atlas=load(DETAIL_ART+"home.png")
	var r:Array=detailed_regions[id]; tex.region=Rect2(r[0],r[1],r[2],r[3]); tex.filter_clip=true
	return tex

func master_glyph(parent:Node,source:String,rect:Rect2,destination:Rect2,role:String,white_on_red:=false) -> TextureRect:
	var t:=TextureRect.new(); var a:=AtlasTexture.new(); a.atlas=load(DETAIL_ART+source+"-glyph-source.png"); a.region=rect; a.filter_clip=true
	t.texture=a; t.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; t.position=destination.position; t.size=destination.size
	t.mouse_filter=Control.MOUSE_FILTER_IGNORE; parent.add_child(t); t.set_deferred("size",destination.size)
	var m:=_material(false); m.set_shader_parameter("glyph",true); m.set_shader_parameter("key_mode",2 if white_on_red else 1); t.material=m
	icons.append({"node":t,"role":role,"material":m}); return t

func _art(parent: Node, filename: String, pos: Vector2, extent: Vector2, decorative := false) -> TextureRect:
	var t := TextureRect.new(); t.texture = load(ROOT_ART+filename); t.position = pos; t.size = extent
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR; t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.material = _material(filename != "background.png",decorative); parent.add_child(t); return t

func _label(parent: Node, text: String, rect: Rect2, font_size: int, secondary := false) -> Label:
	var l := Label.new(); l.text = text; l.position = rect.position; l.size = rect.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE; l.add_theme_font_override("font",main_font if font_size>=40 else body_font)
	l.add_theme_font_size_override("font_size",int(font_size*text_scale)); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_meta("font_size",font_size); l.set_meta("secondary",secondary); parent.add_child(l); labels.append(l); return l

func _glyph(parent: Node, id: String, rect: Rect2, color_role := "ink") -> TextureRect:
	var t := TextureRect.new(); t.texture = atlas("icons",id); t.position = rect.position
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size = rect.size
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE; parent.add_child(t)
	t.set_deferred("size",rect.size)
	var m := _material(); m.set_shader_parameter("glyph",true); t.material = m
	icons.append({"node":t,"role":color_role,"material":m}); return t

func _button(parent: Node, spec: Dictionary):
	var b = ArtButton.new(); b.name = spec.id.capitalize(); parent.add_child(b)
	art_buttons.append(b)
	var r: Array = spec.rect; b.position = Vector2(r[0],r[1]); b.size = Vector2(r[2],r[3])
	var detailed:bool=spec.id in ["story","archive","battle","inventory","settings"]
	var plate := detailed_atlas(spec.id if spec.id in ["archive","battle"] else spec.surface) if detailed else atlas("surfaces",spec.surface); var paint := _material(); _clip_material(paint,plate,0.0 if detailed else 0.11)
	paint.set_shader_parameter("preserve_ink",true)
	if spec.id=="battle":
		var source_points=[Vector2(1290,443),Vector2(1631,443),Vector2(1628,451),Vector2(1660,451),Vector2(1578,617),Vector2(1559,617),Vector2(1559,624),Vector2(1188,624)]
		var mask:PackedVector2Array=[]
		for point in source_points: mask.append((point-plate.region.position)/plate.region.size)
		paint.set_shader_parameter("mask_count",mask.size()); paint.set_shader_parameter("mask_points",mask)
	if spec.id=="story": paint.set_shader_parameter("keep_white_rect",Vector4(970.0/1672.0,210.0/941.0,185.0/1672.0,176.0/941.0))
	b.configure(plate,atlas("icons",spec.icon),spec.title,main_font,paint,spec)
	b.glyph_node.visible=not detailed
	if detailed:
		var text_boxes={"story":Rect2(1204,242,257,126),"archive":Rect2(1051,487,154,66),"battle":Rect2(1466,486,117,68),"inventory":Rect2(1153,662,108,62),"settings":Rect2(1207,799,56,32)}
		var titles={"story":"剧情","archive":"资料库","battle":"作战","inventory":"仓库","settings":"设置"}
		var box:Rect2=text_boxes[spec.id]; var lettering:=AtlasTexture.new(); lettering.atlas=load(DETAIL_ART+"home-glyph-source.png"); lettering.region=box; lettering.filter_clip=true
		var text_paint:=_material(false); text_paint.set_shader_parameter("key_mode",1); text_paint.set_shader_parameter("preserve_ink",true)
		b.bind_reference_text(lettering,text_paint,titles[spec.id],Rect2(box.position-Vector2(r[0],r[1]),box.size))
	var glyph_material := _material(); glyph_material.set_shader_parameter("glyph",true); b.glyph_node.material = glyph_material
	icons.append({"node":b.glyph_node,"role":"white" if spec.id=="story" else "ink","material":glyph_material})
	labels.append(b.caption); b.caption.set_meta("font_size",int(spec.font)); b.caption.set_meta("secondary",false)
	return b

func _build_status() -> void:
	status = Button.new(); status.name = "CharacterStatus"; status.flat = true; status.text = ""; menu.add_child(status)
	status.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; status.tooltip_text = "切换看板角色"
	for state in ["normal","hover","pressed","focus"]: status.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	var p := TextureRect.new(); p.texture = detailed_atlas("status"); p.material = _material(); p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_face=p; _clip_material(p.material,p.texture,0.0); p.material.set_shader_parameter("preserve_ink",true)
	p.material.set_shader_parameter("erase_rect",Vector4(263.0/1672.0,835.0/941.0,245.0/1672.0,23.0/941.0)); p.material.set_shader_parameter("erase_shift_y",24.0/941.0)
	p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; p.stretch_mode = TextureRect.STRETCH_SCALE
	status.add_child(p); p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status_name = _label(status,"看板角色",Rect2(213,31,130,47),25)
	_label(status,"切换",Rect2(459,31,82,47),25)
	_label(status,"好感度",Rect2(250,89,91,43),24)
	var track:=TextureRect.new(); track.name="UnknownAffinityTrack"; track.position=Vector2(335,107); track.size=Vector2(150,10); track.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; track.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var track_texture:=AtlasTexture.new(); track_texture.atlas=load(DETAIL_ART+"home.png"); track_texture.region=Rect2(266,842,237,13); track.texture=track_texture
	status.add_child(track)
	track.set_deferred("size",Vector2(150,10))
	status.tooltip_text="看板角色详情 · 好感度暂无数据"
	status.pressed.connect(func(): open_modal("character",status))
	status.mouse_entered.connect(func(): _status_feedback(true))
	status.mouse_exited.connect(func(): _status_feedback(false))
	status.button_down.connect(func(): _status_feedback(false,true))
	status.button_up.connect(func(): _status_feedback(status.is_hovered()))
	status_visual=Control.new(); status_visual.name="HoverLayer"; status_visual.mouse_filter=Control.MOUSE_FILTER_IGNORE
	status.resized.connect(func(): status_visual.size=status.size)
	var children=status.get_children(); status.add_child(status_visual)
	for child in children: child.reparent(status_visual,false)

func _status_feedback(active:bool,down:=false) -> void:
	if status_motion: status_motion.kill()
	var start:=status_visual.position.y; var target:=2.0 if down else -3.0 if active else 0.0
	if reduced_motion: status_visual.position.y=target; return
	status_motion=create_tween(); status_motion.tween_method(func(v): status_visual.position.y=lerpf(start,target,Motion.ease(v,Motion.EASE)); status_face.material.set_shader_parameter("sheen_position",lerpf(-0.6,1.2,v)); status_face.material.set_shader_parameter("sheen_strength",0.45 if active else 0.0),0.0,1.0,0.55)
	status_motion.tween_callback(func(): status_face.material.set_shader_parameter("sheen_strength",0.0))

func _build_theme_switch() -> void:
	var box := Control.new(); box.name = "ThemeSwitch"; menu.add_child(box); box.size=Vector2(190,67)
	var shell:=TextureRect.new(); shell.texture=detailed_atlas("theme"); shell.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; shell.size=box.size; shell.mouse_filter=Control.MOUSE_FILTER_IGNORE; shell.material=_material()
	_clip_material(shell.material,shell.texture,0.0); shell.material.set_shader_parameter("erase_rect",Vector4(1481.0/1672.0,55.0/941.0,42.0/1672.0,39.0/941.0)); shell.material.set_shader_parameter("erase_rect_b",Vector4(1572.0/1672.0,54.0/941.0,40.0/1672.0,42.0/941.0)); shell.material.set_shader_parameter("erase_sample_x",1531.0/1672.0)
	shell.material.set_shader_parameter("erase_ink_only",true)
	box.add_child(shell)
	for id in ["sun","moon"]:
		var b := Button.new(); b.name = id.capitalize(); b.custom_minimum_size = Vector2(76,54); b.flat = true
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND; b.tooltip_text = "昼间模式" if id=="sun" else "夜间模式"
		b.position=Vector2(10 if id=="sun" else 100,7); b.size=Vector2(76,54)
		for state in ["normal","hover","pressed","focus"]: b.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		box.add_child(b)
		var g=master_glyph(b,"home",Rect2(1484,58,37,36) if id=="sun" else Rect2(1572,57,39,37),Rect2(20,10,36,36),id); g.name="AnimatedGlyph"; g.pivot_offset=g.size*0.5
		b.pressed.connect(func(): set_night(id=="moon"))

func arrange() -> void:
	if not stage: return
	var narrow := size.x / maxf(size.y,1) < 1.20
	logical_size = Vector2(960,1280) if narrow else Vector2(1672,941)
	var factor := minf(size.x/logical_size.x,size.y/logical_size.y)
	stage.size = logical_size; stage.scale = Vector2.ONE * factor; stage.position = (size-logical_size*factor)/2.0
	background.size = logical_size; decorations.size = logical_size; menu.size = logical_size
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var compact_rects := {"story":Rect2(67,429,826,253),"archive":Rect2(42,695,470,187),"battle":Rect2(452,695,470,187),"inventory":Rect2(121,900,732,126),"settings":Rect2(622,1100,290,90)}
	for spec in layout.buttons:
		var b = home_buttons[spec.id]; var a: Array = spec.rect
		var r := Rect2(a[0],a[1],a[2],a[3])
		if narrow: r = compact_rects[spec.id]
		else:
			var row := 0 if spec.id=="story" else 1 if spec.id in ["archive","battle"] else 2 if spec.id=="inventory" else 3
			r.position.y += (spacing-0.5)*12.0*row
		b.position = r.position; b.size = r.size; b.arrange()
	var sr: Array = layout.status_rect
	status.position = Vector2(24,1095) if narrow else Vector2(sr[0],sr[1]); status.size = Vector2(sr[2],sr[3])
	status.scale = Vector2.ONE*0.9 if narrow else Vector2.ONE
	var th := menu.get_node("ThemeSwitch") as Control; th.position = Vector2(logical_size.x-217,43)
	if shade: shade.size = logical_size
	if wipe: wipe.size = logical_size
	if modal and modal.visible: _position_modal()
	if page_slot and page_slot.visible: _build_route()
	_apply_font_scale()

func _apply_font_scale() -> void:
	for item in labels:
		if not is_instance_valid(item): continue
		var n: int = int(item.get_meta("font_size",28))
		item.add_theme_font_size_override("font_size",int(n*text_scale))
	for b in home_buttons.values():
		if b.reference_text: b.reference_text.scale=Vector2.ONE*text_scale

func _paint() -> void:
	icons=icons.filter(func(entry): return is_instance_valid(entry.node))
	labels=labels.filter(func(item): return is_instance_valid(item))
	materials=materials.filter(func(item): return item.get_ref()!=null)
	colored_controls=colored_controls.filter(func(item): return is_instance_valid(item))
	art_buttons=art_buttons.filter(func(item): return is_instance_valid(item))
	var ink := _color("ink")
	var muted := _color("muted")
	var accent := _color("accent")
	if is_instance_valid(power):
		power.ink=ink; power.accent=accent; power.reduced_motion=reduced_motion; power.queue_redraw()
	for m in materials:
		m.get_ref().set_shader_parameter("night_mix",night_amount)
		m.get_ref().set_shader_parameter("ambient_motion",not reduced_motion)
	for c in colored_controls:
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: c.add_theme_color_override(state,ink)
	for entry in icons:
		if not is_instance_valid(entry.node): continue
		var color: Color = ink
		match entry.role:
			"muted": color = muted
			"white": color = Color.WHITE
			"accent": color = accent
			"badge": color = Color.WHITE.lerp(Color("252a33"),night_amount)
			"sun": color = accent if not theme_target else muted
			"moon": color = accent if theme_target else muted
		entry.material.set_shader_parameter("glyph_color",color)
	for l in labels:
		if is_instance_valid(l): l.add_theme_color_override("font_color",muted if l.get_meta("secondary",false) else ink)
	for b in art_buttons: b.accent = accent; b.reduced_motion = reduced_motion; b.queue_redraw()
	if shade: shade.color = _color("shade")
	if is_instance_valid(character_detail): character_detail.apply_palette()

func set_night(value: bool, animate := true) -> void:
	var hub = _hub()
	if hub and has_meta("external_router"):
		theme_target = value; hub.set_night(value, animate); _animate_theme_icon("Moon" if value else "Sun"); return
	theme_target = value
	if theme_tween: theme_tween.kill()
	var target := 1.0 if value else 0.0
	if reduced_motion or not animate:
		night_amount = target; _paint()
	else:
		theme_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		theme_tween.tween_method(func(v): night_amount = v; _paint(),night_amount,target,0.4)
	_animate_theme_icon("Moon" if value else "Sun")
	_save_options()

func _animate_theme_icon(selected:String) -> void:
	for id in ["Sun","Moon"]:
		var g:Control=menu.get_node("ThemeSwitch/"+id+"/AnimatedGlyph")
		if theme_icon_tweens.has(id): theme_icon_tweens[id].kill()
		var on:bool=id==selected; var target:=1.08 if on else 1.0
		if reduced_motion: g.rotation=0; g.scale=Vector2.ONE*target; continue
		var start_scale:=0.6 if on else g.scale.x
		var t:=create_tween(); theme_icon_tweens[id]=t
		t.tween_method(func(v): g.rotation=lerpf(-PI/2.0 if on else 0.0,0.0,Motion.ease(v)); g.scale=Vector2.ONE*lerpf(start_scale,target,Motion.ease(minf(v*2.4,1.0),Motion.EASE)),0.0,1.0,0.6)

func entrance() -> void:
	for t in entrance_tweens:
		if is_instance_valid(t): t.kill()
	entrance_tweens.clear()
	var i := 0
	for b in home_buttons.values():
		b.entrance_layer.position = Vector2.ZERO; b.modulate.a = 1.0
		if not reduced_motion:
			b.entrance_layer.position.x = 46; b.modulate.a = 0.0
			var t:=create_tween(); t.tween_interval(i*0.07)
			t.tween_method(func(v): var q:=Motion.ease(v); b.entrance_layer.position.x=46.0*(1.0-q); b.modulate.a=q,0.0,1.0,0.62)
			entrance_tweens.append(t)
		i += 1

func navigate(destination: String) -> void:
	if busy: return
	if has_meta("external_router"):
		# Full UI mode: the UI root owns transitions and the screen stack.
		if modal.visible: close_modal(true)
		navigation_requested.emit(destination); return
	if modal.visible: close_modal(true)
	busy = true
	if reduced_motion: _swap_route(destination); busy = false; return
	wipe.visible = true
	for child in wipe.get_children(): child.queue_free()
	var colors := [_color("accent"),_color("ink"),_color("background")]
	for i in range(3):
		var slab:=Polygon2D.new(); wipe.add_child(slab); slab.color=colors[i]
		var w:float=logical_size.x*[1.5,1.3,1.15][i]; var h:=logical_size.y*1.10; var skew:=h*tan(deg_to_rad(15.0))
		slab.polygon=PackedVector2Array([Vector2(0,0),Vector2(w,0),Vector2(w-skew,h),Vector2(-skew,h)])
		slab.position=Vector2(-logical_size.x*1.70,-logical_size.y*0.05)
		var t:=create_tween(); t.tween_interval(i*0.05)
		t.tween_method(func(v): slab.position.x=lerpf(-logical_size.x*1.70,logical_size.x*1.40,Motion.ease(v,Motion.WIPE)),0.0,1.0,0.84)
	wipe_tween=create_tween(); wipe_tween.tween_interval(0.42)
	wipe_tween.tween_callback(func(): _swap_route(destination))
	wipe_tween.tween_interval(0.58); wipe_tween.tween_callback(func(): wipe.visible=false; busy=false)

func _swap_route(destination: String) -> void:
	route = destination; menu.visible = destination=="home"; page_slot.visible = destination!="home"
	if route=="home": entrance(); home_buttons.story.grab_focus()
	else: _build_route(); navigation_requested.emit(destination)
	if OS.has_feature("web"): JavaScriptBridge.eval("window.homeRoute = '"+destination+"'",true)

func _build_route() -> void:
	for child in page_slot.get_children(): child.free()
	if route=="title":
		# Final title artwork is a separate user decision. This is a working return boundary.
		_label(page_slot,"准备开始",Rect2(logical_size.x*0.5-310,logical_size.y*0.39,620,120),76).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var enter = _button(page_slot,{"id":"enter","title":"进入主页","surface":"strip","icon":"arrow","rect":[logical_size.x*0.5-220,logical_size.y*0.62,440,90],"font":32,"icon_rect":[55,24,38,40],"label_rect":[125,10,260,70]})
		enter.name="EnterHome"; enter.pressed.connect(func(): navigate("home")); enter.grab_focus(); _paint()
		return
	# This slot deliberately has no gameplay; future modules mount at this boundary.
	var names := {"story":"剧情","archive":"资料库","battle":"作战","inventory":"仓库"}
	_label(page_slot,names.get(route,route),Rect2(100,75,600,130),64)
	var b = _button(page_slot,{"id":"back","title":"返回主页","surface":"strip","icon":"arrow","rect":[logical_size.x-520,logical_size.y-180,440,90],"font":32,"icon_rect":[55,24,38,40],"label_rect":[125,10,260,70]})
	b.pressed.connect(func(): navigate("home")); b.grab_focus(); _paint()

func open_modal(kind: String, source: Control = null) -> void:
	if busy: return
	if modal_tween: modal_tween.kill()
	modal_source = source; modal_kind = kind
	for child in modal.get_children(): child.free()
	modal.size = Vector2(900,625); modal.visible = true; shade.visible = kind!="character"
	modal.mouse_filter=Control.MOUSE_FILTER_IGNORE if kind=="character" else Control.MOUSE_FILTER_STOP
	_set_home_controls_visible(kind!="character")
	if kind=="character":
		_character_controls()
	else:
		var face := TextureRect.new(); face.texture = atlas("surfaces","modal"); face.material = _material(); face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_clip_material(face.material,face.texture,0.23)
		face.mouse_filter = Control.MOUSE_FILTER_STOP; modal.add_child(face); face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label(modal,"显示设置",Rect2(220,78,500,90),44)
		var close := Button.new(); close.name="Close"; close.text="×"; close.flat=true; close.add_theme_font_size_override("font_size",44)
		for state in ["normal","hover","pressed","focus"]: close.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		colored_controls.append(close)
		close.position=Vector2(760,67); close.size=Vector2(65,65); modal.add_child(close); close.pressed.connect(close_modal)
		_settings_controls(); close.grab_focus()
	_position_modal(); _paint()
	if is_instance_valid(character_detail) and kind=="character": character_detail.input.grab_focus()
	if modal_tween: modal_tween.kill()
	modal.modulate.a=1.0
	if not reduced_motion:
		var target_position:=modal.position
		modal.modulate.a=0.0; modal.position.y+=30
		modal_tween=create_tween()
		modal_tween.tween_method(func(time): modal.modulate.a=Motion.ease(minf(time/0.3,1.0),Motion.EASE); modal.position=target_position+Vector2(0,30.0*(1.0-Motion.ease(time/0.4))),0.0,0.4,0.4)

func _position_modal() -> void:
	if modal_kind=="character" and is_instance_valid(character_detail):
		character_detail.arrange(logical_size.x<1100)
		modal.size=character_detail.logical_size
		if logical_size.x>=1100:
			modal.scale=Vector2.ONE; modal.position=Vector2.ZERO; return
		var scale_factor:=minf(1.0,minf((logical_size.x-40)/modal.size.x,(logical_size.y-160)/modal.size.y))
		modal.scale=Vector2.ONE*scale_factor; modal.position=(logical_size-modal.size*scale_factor)/2.0
		return
	var fit := minf(1.0,(logical_size.x-70)/900.0)
	modal.scale = Vector2.ONE*fit; modal.position=(logical_size-modal.size*fit)/2.0

func _settings_controls() -> void:
	_slider("UI布局",220,0.0,1.0,spacing,func(v): spacing=v; arrange(); _save_options())
	_slider("文字大小",320,0.90,1.12,text_scale,func(v): text_scale=v; _apply_font_scale(); _save_options())
	var check := CheckButton.new(); check.name="ReducedMotion"; check.text="减弱动态效果"; check.button_pressed=reduced_motion
	check.position=Vector2(180,436); check.size=Vector2(520,62); check.add_theme_font_override("font",body_font); check.add_theme_font_size_override("font_size",28)
	colored_controls.append(check)
	modal.add_child(check); check.toggled.connect(func(v): reduced_motion=v; entrance(); _paint(); _save_options())

func _slider(title: String,y: float,lo: float,hi: float,value: float,callback: Callable) -> void:
	_label(modal,title,Rect2(180,y,250,60),29)
	var slider := HSlider.new(); slider.name="Spacing" if title=="UI布局" else "TextScale"
	slider.min_value=lo; slider.max_value=hi; slider.step=0.01; slider.value=value
	slider.position=Vector2(430,y+8); slider.size=Vector2(315,48); modal.add_child(slider); slider.value_changed.connect(callback)

func _character_controls() -> void:
	character_detail=CharacterPanel.new(); modal.add_child(character_detail); character_detail.configure(self)
	character_detail.chat_requested.connect(func(id,value): character_message_requested.emit(id,value))

func _set_home_controls_visible(value: bool) -> void:
	for b in home_buttons.values(): b.visible=value
	status.visible=value

func close_modal(immediate := false) -> void:
	if not modal or not modal.visible: return
	if modal_tween: modal_tween.kill()
	if reduced_motion or immediate:
		_finish_modal_close()
	else:
		var start_position:=modal.position; var start_alpha:=modal.modulate.a
		modal_tween=create_tween(); modal_tween.tween_method(func(time): modal.modulate.a=start_alpha*(1.0-Motion.ease(minf(time/0.3,1.0),Motion.EASE)); modal.position=start_position+Vector2(0,30.0*Motion.ease(minf(time/0.4,1.0))),0.0,0.35,0.35)
		modal_tween.tween_callback(_finish_modal_close)

func _finish_modal_close() -> void:
	modal.visible=false; shade.visible=false; _set_home_controls_visible(true)
	if is_instance_valid(modal_source): modal_source.grab_focus()

func _input(event: InputEvent) -> void:
	if not is_instance_valid(modal) or not modal.visible or not event.is_action_pressed("ui_cancel"): return
	if modal_kind=="character" and is_instance_valid(character_detail) and character_detail.selector.get_popup().visible: return
	close_modal(); get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if modal.visible: close_modal()
		elif route!="home": navigate("home")
		get_viewport().set_input_as_handled()

func _load_options() -> void:
	var c := ConfigFile.new()
	if c.load(OPTIONS_PATH)!=OK: return
	theme_target=bool(c.get_value("home","night",false)); night_amount=1.0 if theme_target else 0.0
	reduced_motion=bool(c.get_value("home","reduced_motion",false))
	spacing=clampf(float(c.get_value("home","spacing",0.5)),0.0,1.0)
	text_scale=clampf(float(c.get_value("home","text_scale",1.0)),0.90,1.12)

func _save_options() -> void:
	if review_mode: return
	var c := ConfigFile.new(); c.set_value("home","night",theme_target); c.set_value("home","reduced_motion",reduced_motion)
	c.set_value("home","spacing",spacing); c.set_value("home","text_scale",text_scale); c.save(OPTIONS_PATH)
