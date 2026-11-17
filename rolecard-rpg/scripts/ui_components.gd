extends RefCounted
const Art = preload("res://scripts/ui_art.gd")
const Palette = preload("res://scripts/ui_theme.gd")
const Tile = preload("res://scripts/ui_tile.gd")

static func art(kind: String, height: float, actor_id: String = "") -> Control:
	var node := Art.new(); node.kind = kind; node.custom_minimum_size.y = height
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if kind in ["portrait","avatar"]:
		node.kind = "portrait"
		var path := "res://assets/ui/portraits/"+actor_id+("-avatar" if kind == "avatar" else "")+".webp"
		if ResourceLoader.exists(path): node.portrait = load(path)
		if actor_id in ["mingkong","ye"]: node.crop_top = 0.5
	return node

static func tile(app,title_text: String,subtitle: String,callback: Callable,main: bool = false,height: float = 100) -> Button:
	var button := Tile.new(); button.heading = title_text; button.subtitle = subtitle; button.primary = main
	button.heading_size = 38 if main else 23
	button.custom_minimum_size.y = height; button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.tooltip_text = title_text; button.pressed.connect(func(): app._click_sound(); callback.call())
	return button

static func split(app, parent: Node, ratio: float = 1.0) -> Array:
	var row: BoxContainer = VBoxContainer.new() if app.compact else HBoxContainer.new()
	row.add_theme_constant_override("separation",24); parent.add_child(row)
	var left := VBoxContainer.new(); var right := VBoxContainer.new()
	for column in [left,right]:
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",16); row.add_child(column)
	left.size_flags_stretch_ratio = ratio
	return [left,right]

static func title(app,parent: Node,text: String,detail: String = "") -> void:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation",14); parent.add_child(row)
	var mark := ColorRect.new(); mark.color = Palette.color("accent"); mark.custom_minimum_size = Vector2(5,38); row.add_child(mark)
	row.add_child(app._label(text,34))
	if not detail.is_empty(): parent.add_child(app._label(detail,16,Palette.color("muted")))

static func primary(app,text: String, callback: Callable, disabled: bool = false) -> Button:
	var b: Button = app._button(text,callback,disabled); Palette.apply_button(b,"primary")
	b.custom_minimum_size.y = 52
	return b

static func chip(app,text: String,selected: bool = false) -> Label:
	return app._label(text,14,Palette.color("accent") if selected else Palette.color("muted"))

static func portrait_card(app,parent: Node,id: String,height: float = 220.0) -> VBoxContainer:
	var panel := PanelContainer.new(); panel.add_theme_stylebox_override("panel",Palette.panel())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(panel)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation",10); panel.add_child(col)
	col.add_child(art("portrait",height,id))
	return col

static func metric(app,parent: Node,value: String,caption: String) -> void:
	var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; parent.add_child(col)
	col.add_child(app._label(value.trim_suffix(".0"),32)); col.add_child(app._label(caption,15,Palette.color("muted")))

static func empty(app,parent: Node,title_text: String,detail: String) -> void:
	var panel = app._panel(parent,title_text,detail)
	panel.add_child(art("sigil",100))

