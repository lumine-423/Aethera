extends Control
## Foreground-only detail panel; background, palette and glyphs belong to Home.
signal chat_requested(character_id: String, message: String)
const ART := "res://assets/ui/fidelity-v2/"
const Piece=preload("res://scripts/home/art_piece.gd")
const Motion=preload("res://scripts/home/motion.gd")
const ROSTER := [["rin","凛零"],["mingkong","明空"],["merlin","梅林"]]
var ui
var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/character_panel_layout.json"))
var regions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ART+"panel-polygons.json"))
var logical_size := Vector2(1400,650)
var widgets: Dictionary = {}
var selector: OptionButton
var input: LineEdit
var send: Button
var close_button: Button
var history: RichTextLabel
var greeting: Label
var connection: Label
var meter: ProgressBar
var current_id := ""
var arranged:=false
var send_visual:Control
var send_face:Control
var send_tween:Tween
var character_tween:Tween

func configure(host) -> void:
	ui=host; name="CharacterDetail"; mouse_filter=Control.MOUSE_FILTER_IGNORE
	_surface("FrameOutline","FrameOutline",false)
	_surface("Body","Body",false)
	for id in ["TopRim","RightRim","BottomRim","TitleAccent"]: _surface(id,id,false)
	for pair in [["TitlePlate","header"],["NamePlate","header"],["AffinityPlate","affinity"],["ConversationPlate","conversation"],["SectionPlate","section"],["InputPlate","input"]]:
		_surface(pair[0],pair[0],true)
	_text("Title","看板角色",43)
	_text("AffinityTitle","好感度",27)
	_text("AffinityValue","—",27,true)
	_text("SectionTitle","交谈",33)
	_text("SwitchTitle","切换",27)
	widgets.SwitchIcon=ui.master_glyph(self,"panel",Rect2(1367,177,34,36),Rect2(0,0,30,30),"ink")
	widgets.SectionIcon=ui.master_glyph(self,"panel",Rect2(1043,349,44,39),Rect2(0,0,43,38),"badge",true)
	greeting=_text("Greeting","今天，想聊些什么？",30); greeting.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	connection=_text("ConnectionStatus","AI尚未连接",20,true); connection.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; connection.visible=false
	widgets.Heart=ui._glyph(self,"heart",Rect2(0,0,32,28),"accent")
	meter=ProgressBar.new(); meter.name="AffinityBar"; meter.show_percentage=false; meter.value=0.0; meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(meter); widgets.AffinityBar=meter
	selector=OptionButton.new(); selector.name="Selector"; selector.flat=true; selector.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	selector.add_theme_font_override("font",ui.body_font); selector.add_theme_font_size_override("font_size",34)
	for row in ROSTER: selector.add_item(row[1])
	for state in ["normal","hover","pressed","focus"]: selector.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	add_child(selector); widgets.Selector=selector; selector.item_selected.connect(choose_character)
	close_button=Button.new(); close_button.name="Close"; close_button.flat=true; add_child(close_button); widgets.Close=close_button
	_surface("ClosePlate","ClosePlate",true)
	move_child(widgets.ClosePlate,close_button.get_index())
	var close_icon=ui.master_glyph(close_button,"panel",Rect2(1545,132,35,36),Rect2(49,13,35,36),"badge",true); close_icon.name="Glyph"
	close_icon.pivot_offset=close_icon.size/2.0
	close_button.mouse_entered.connect(func(): _close_feedback(close_icon,true))
	close_button.mouse_exited.connect(func(): _close_feedback(close_icon,false))
	for state in ["normal","hover","pressed","focus"]: close_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	close_button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND; close_button.pressed.connect(func(): ui.close_modal())
	input=LineEdit.new(); input.name="Input"; input.placeholder_text="输入想说的话…"; input.max_length=2000
	input.add_theme_font_override("font",ui.body_font); input.add_theme_font_size_override("font_size",23)
	for state in ["normal","focus"]: input.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	add_child(input); widgets.Input=input; input.text_changed.connect(func(value): send.disabled=value.strip_edges().is_empty(); send_visual.get_child(1).modulate.a=0.45 if send.disabled else 1.0)
	input.text_submitted.connect(func(_text_value): submit_message())
	send=Button.new(); send.name="Send"; send.flat=true; send.disabled=true; send.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	for state in ["normal","hover","pressed","focus","disabled"]: send.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	add_child(send); widgets.Send=send
	send_visual=Control.new(); send_visual.name="HoverLayer"; send_visual.mouse_filter=Control.MOUSE_FILTER_IGNORE; send.add_child(send_visual)
	send_face=Piece.new(); send_face.name="SendPlate"; send_visual.add_child(send_face); send_face.configure(load(ART+"panel.png"),regions.SendPlate,ui._material())
	ui.master_glyph(send_visual,"panel",Rect2(1498,603,48,42),Rect2(46,15,48,42),"badge",true)
	send.mouse_entered.connect(func(): _send_feedback(true))
	send.mouse_exited.connect(func(): _send_feedback(false))
	send.button_down.connect(func(): _send_feedback(false,true))
	send.button_up.connect(func(): _send_feedback(send.is_hovered()))
	send.pressed.connect(submit_message)
	history=RichTextLabel.new(); history.name="History"; history.bbcode_enabled=false; history.scroll_following=true
	history.add_theme_font_override("normal_font",ui.body_font); history.add_theme_font_size_override("normal_font_size",25)
	add_child(history); widgets.History=history
	var index:=0
	for i in range(ROSTER.size()):
		if ROSTER[i][0]==ui.selected_character: index=i
	selector.select(index); choose_character(index)
	arrange(false); apply_palette()

func _surface(id: String, _part: String, _use_atlas: bool) -> void:
	var t=Piece.new(); t.name=id; add_child(t); widgets[id]=t
	var source:="panel-glyph-source.png" if id=="FrameOutline" else "panel-backing.png" if id in ["Body","BottomRim"] else "panel.png"
	var paint=ui._material()
	if id=="FrameOutline": paint.set_shader_parameter("key_mode",2)
	t.configure(load(ART+source),regions[id],paint)

var close_tween:Tween
func _send_feedback(on:bool,down:=false) -> void:
	if send.disabled:
		if send_tween: send_tween.kill()
		send_visual.position=Vector2.ZERO
		send_face.pieces[0].material.set_shader_parameter("sheen_strength",0)
		return
	if send_tween: send_tween.kill()
	var start:=send_visual.position.y; var target:=2.0 if down else -3.0 if on else 0.0
	var m:ShaderMaterial=send_face.pieces[0].material
	if ui.reduced_motion: send_visual.position.y=target; m.set_shader_parameter("sheen_strength",0); return
	send_tween=create_tween()
	send_tween.tween_method(func(v): send_visual.position.y=lerpf(start,target,Motion.ease(minf(v*2.75,1.0),Motion.EASE)); m.set_shader_parameter("sheen_position",lerpf(-0.6,1.2,v)); m.set_shader_parameter("sheen_strength",0.45 if on else 0.0),0.0,1.0,0.55)
	send_tween.tween_callback(func(): m.set_shader_parameter("sheen_strength",0))

func _close_feedback(icon:Control,on:bool) -> void:
	if close_tween: close_tween.kill()
	var start:=icon.rotation; var target:=PI/2.0 if on else 0.0
	if ui.reduced_motion: icon.rotation=target; return
	close_tween=create_tween(); close_tween.tween_method(func(v): icon.rotation=lerpf(start,target,Motion.ease(v,Motion.EASE)),0.0,1.0,0.2)

func _text(id: String,value: String,font_size: int,secondary:=false) -> Label:
	var l=ui._label(self,value,Rect2(0,0,100,50),font_size,secondary); l.name=id; widgets[id]=l; return l

func arrange(compact: bool) -> void:
	var dimensions:Array=layout.narrow_size if compact else layout.wide_size
	logical_size=Vector2(dimensions[0],dimensions[1]); size=logical_size
	var positions:Dictionary=layout.narrow if compact else layout.wide
	for id in widgets:
		var r:Array=positions[id]; var w:Control=widgets[id]
		w.position=Vector2(r[0],r[1]); w.size=Vector2(r[2],r[3])
	send_face.size=send.size
	apply_palette()
	arranged=true

func apply_palette() -> void:
	if not ui: return
	var ink:Color=ui._color("ink"); var accent:Color=ui._color("accent"); var muted:Color=ui._color("muted")
	for c in [selector,input]:
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]: c.add_theme_color_override(state,ink)
	selector.add_theme_color_override("font_outline_color",Color.TRANSPARENT)
	var no_arrow:=Image.create(1,1,false,Image.FORMAT_RGBA8); no_arrow.fill(Color.TRANSPARENT)
	selector.add_theme_icon_override("arrow",ImageTexture.create_from_image(no_arrow))
	for state in ["icon_normal_color","icon_hover_color","icon_pressed_color","icon_hover_pressed_color"]: selector.add_theme_color_override(state,ink)
	var popup:=selector.get_popup()
	popup.add_theme_font_override("font",ui.body_font)
	popup.add_theme_font_size_override("font_size",29)
	popup.add_theme_color_override("font_color",ink); popup.add_theme_color_override("font_hover_color",ink)
	var popup_panel:=StyleBoxFlat.new(); popup_panel.bg_color=ui._color("background"); popup_panel.border_color=muted; popup_panel.set_border_width_all(1)
	popup.add_theme_stylebox_override("panel",popup_panel)
	var popup_hover:=StyleBoxFlat.new(); popup_hover.bg_color=accent; popup_hover.bg_color.a=0.16
	popup.add_theme_stylebox_override("hover",popup_hover)
	input.add_theme_color_override("font_placeholder_color",muted); input.add_theme_color_override("caret_color",accent)
	history.add_theme_color_override("default_color",ink)
	var track:=StyleBoxFlat.new(); track.bg_color=muted; track.bg_color.a=0.35; track.set_corner_radius_all(6)
	var fill:=StyleBoxFlat.new(); fill.bg_color=accent; fill.set_corner_radius_all(6)
	meter.add_theme_stylebox_override("background",track); meter.add_theme_stylebox_override("fill",fill)
	# Red/yellow section badge needs dark text at night, white text by day.
	widgets.SectionTitle.add_theme_color_override("font_color",Color.WHITE.lerp(Color("252a33"),ui.night_amount))
	if send:
		send_visual.get_child(1).modulate.a=0.45 if send.disabled else 1.0

func choose_character(index: int) -> void:
	current_id=ROSTER[index][0]; ui.selected_character=current_id; ui.status_name.text=ROSTER[index][1]
	selector.text=ROSTER[index][1]
	input.clear(); send.disabled=true; refresh_history()
	if arranged and is_inside_tree() and ui.modal.visible and not ui.reduced_motion:
		if character_tween: character_tween.kill()
		var pos:Dictionary=layout.narrow if logical_size.x<1100 else layout.wide
		var target:=Vector2(pos.Greeting[0],pos.Greeting[1]); var title_target:=Vector2(pos.Selector[0],pos.Selector[1])
		character_tween=create_tween(); character_tween.tween_method(func(v): var q:=Motion.ease(v); greeting.position=target+Vector2(46.0*(1.0-q),0); greeting.modulate.a=q; selector.position=title_target+Vector2(46.0*(1.0-q),0); selector.modulate.a=q,0.0,1.0,0.55)

func refresh_history() -> void:
	var messages:Array=ui.character_messages.get(current_id,[])
	var lines:PackedStringArray=[]
	for message in messages: lines.append("你："+str(message))
	history.text="\n\n".join(lines)
	greeting.visible=messages.is_empty(); history.visible=not messages.is_empty(); connection.visible=not messages.is_empty()
	apply_palette()

func submit_message() -> void:
	var value:=input.text.strip_edges()
	if value.is_empty(): return
	if not ui.character_messages.has(current_id): ui.character_messages[current_id]=[]
	ui.character_messages[current_id].append(value)
	chat_requested.emit(current_id,value)
	input.clear(); send.disabled=true; refresh_history()
	if is_inside_tree() and ui.modal.visible and not ui.reduced_motion:
		var target:=greeting.position; greeting.modulate.a=0.0
		var change=create_tween(); change.tween_method(func(v): greeting.position=target+Vector2(46.0*(1.0-Motion.ease(v)),0); greeting.modulate.a=Motion.ease(v),0.0,1.0,0.55); input.grab_focus()
