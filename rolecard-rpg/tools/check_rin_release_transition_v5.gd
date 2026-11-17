extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var app = load("res://scenes/rin_release_transition_05.tscn").instantiate()
	root.add_child(app); await process_frame
	if not app.ready_ok or app.frames.size() != 12: push_error("missing chain assets"); quit(1); return
	app.set_process(false)
	app.seek(0.0)
	if not app.base.visible or app.chain.visible or app.flash.visible: push_error("bad start"); quit(1); return
	app.seek(0.55 + 5.1 / 24.0)
	if not app.chain.visible: push_error("missing chain peak"); quit(1); return
	var held: Texture2D = app.chain.texture
	app.seek(0.55 + 9.1 / 24.0)
	if app.chain.texture != held: push_error("chain peak not held"); quit(1); return
	var flash_start: float = app.config.flash_start
	app.seek(flash_start + 0.09)
	var material: ShaderMaterial = app.flash.material
	if not app.flash.visible or material.get_shader_parameter("phase") != 0: push_error("flash did not expand"); quit(1); return
	app.seek(flash_start + 0.34)
	if material.get_shader_parameter("phase") != 1: push_error("missing white hold"); quit(1); return
	app.seek(float(app.config.switch_time) + 0.01)
	if not app.released.visible or app.base.visible: push_error("missing switch"); quit(1); return
	app.seek(flash_start + 0.60)
	if material.get_shader_parameter("phase") != 2: push_error("missing center-out disappearance"); quit(1); return
	app.skip()
	if app.playing or not app.released.visible or app.flash.visible: push_error("skip"); quit(1); return
	print("PASS 12 source frames, chain hold, center-out flash stages, form switch and skip")
	quit()
