extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size=Vector2i(1672,941)
	var app=load("res://scenes/home.tscn").instantiate(); root.add_child(app)
	await create_timer(0.8).timeout
	print("FONT AXES ",app.FONT.get_supported_variation_list())
	print("FONT STYLE ",app.FONT.get_font_style_name())
	print("FONT VAR ",app.main_font.variation_opentype)
	for entry in app.icons:
		print("GLYPH ",entry.role," SIZE ",entry.node.size," MIN ",entry.node.get_combined_minimum_size()," POS ",entry.node.position," STRETCH ",entry.node.stretch_mode," EXPAND ",entry.node.expand_mode)
	quit()

