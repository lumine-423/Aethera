extends RefCounted
static var tokens: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_tokens.json"))
static var mode := "day"
static var font_resource: FontVariation

static func color(key: String) -> Color:
	return Color(tokens.palettes[mode].get(key,"aa7788"))

static func legacy(value: Color) -> Color:
	var mapping := {"e9e7de":"text","afbfcc":"muted","9aa9b5":"muted","bdc8cf":"muted","b9c6d0":"muted","899aa8":"muted","b3dbc7":"ally","77cbb0":"ally","e4d3a5":"text","dac48e":"warning","efa7a3":"error","d68d88":"enemy","111922":"background","202a35":"surface","3e4a57":"border","354b5a":"hover"}
	return color(mapping[value.to_html(false)]) if mapping.has(value.to_html(false)) else value

static func panel(color_value: String = "",border_value: String = "") -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color("surface") if color_value.is_empty() else legacy(Color(color_value))
	box.border_color = color("border") if border_value.is_empty() else legacy(Color(border_value))
	box.set_border_width_all(1); box.set_corner_radius_all(3)
	box.content_margin_left = 22; box.content_margin_right = 22
	box.content_margin_top = 18; box.content_margin_bottom = 18
	return box

static func button_style(kind: String, state: String = "normal") -> StyleBoxFlat:
	var box := panel()
	box.content_margin_top = 10; box.content_margin_bottom = 10
	box.content_margin_left = 18; box.content_margin_right = 18
	if kind == "primary":
		box.bg_color = color("accent"); box.border_color = color("accent")
	elif kind == "selected":
		box.bg_color = color("soft"); box.border_color = color("accent"); box.border_width_bottom = 3
	if state == "hover": box.bg_color = box.bg_color.lerp(color("text"),0.07)
	if state == "pressed": box.bg_color = box.bg_color.lerp(color("text"),0.13)
	if state == "disabled": box.bg_color = color("disabled"); box.border_color = color("border")
	return box

static func apply_button(button: Button, kind: String) -> void:
	for state in ["normal","hover","pressed","disabled"]: button.add_theme_stylebox_override(state,button_style(kind,state))
	var text_color := color("on_accent") if kind == "primary" else color("text")
	for state in ["font_color","font_hover_color","font_pressed_color"]: button.add_theme_color_override(state,text_color)

static func build(large: bool) -> Theme:
	var theme := Theme.new(); theme.default_font_size = 20 if large else 18
	if font_resource == null:
		font_resource = FontVariation.new(); font_resource.base_font = load("res://assets/fonts/NotoSansSC.ttf")
		font_resource.variation_opentype = {0x77676874:500}
	theme.default_font = font_resource
	for state in ["normal","hover","pressed","disabled"]: theme.set_stylebox(state,"Button",button_style("normal",state))
	var focus := panel("00000000")
	focus.bg_color = Color.TRANSPARENT; focus.border_color = color("accent"); focus.set_border_width_all(2)
	theme.set_stylebox("focus","Button",focus)
	for type in ["Label","Button","CheckButton","CheckBox"]:
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: theme.set_color(key,type,color("text"))
	theme.set_color("font_disabled_color","Button",color("muted"))
	theme.set_stylebox("panel","AcceptDialog",panel())
	var window_style := panel(); window_style.expand_margin_top = 38
	theme.set_stylebox("embedded_border","Window",window_style); theme.set_color("title_color","Window",color("text"))
	for icon_state in ["close","close_pressed"]: theme.set_icon(icon_state,"Window",load("res://assets/ui/close-"+mode+".svg"))
	var track := panel(); track.bg_color = color("soft"); track.set_content_margin_all(2)
	var grab := panel(); grab.bg_color = color("border"); grab.set_content_margin_all(3)
	theme.set_stylebox("scroll","VScrollBar",track); theme.set_stylebox("grabber","VScrollBar",grab)
	theme.set_stylebox("grabber_highlight","VScrollBar",grab); theme.set_stylebox("grabber_pressed","VScrollBar",grab)
	return theme
