extends SceneTree
const Shell = preload("res://scenes/game_shell.tscn")
const Palette = preload("res://scripts/ui_theme.gd")
var issues: Array = []
var captures: Array = []
func _initialize() -> void:
	call_deferred("capture")
func capture() -> void:
	root.size = Vector2i(1440,900)
	var app = Shell.instantiate()
	app.store.path = "res://.tmp/ui-10-isolated.json"
	root.add_child(app)
	app.rules.start("training.basic",["rin","mingkong"],"ui-10-review-fixture")
	app.records = [{"request_id":"ui-10-review-fixture","mission":"training.basic","outcome":"victory","rounds":4,"actions":8,"party":["rin","mingkong"],"log":["第1回合：凛零使用集中突破。","第1回合：明空使用守望。","第4回合：训练守卫倒地。"],"version":"playable-rules-08"}]
	for dimensions in [Vector2i(1440,900),Vector2i(480,800)]:
		root.size = dimensions
		for frame in range(4): await process_frame
		for mode in ["day","night"]:
			Palette.mode = mode
			for route in app.flow.registry:
				app.flow.current = route; app.flow.modal = ""; app.paused = false; app.selected_action = ""; app.selected_target = ""
				app._render()
				for frame in range(6): await process_frame
				await RenderingServer.frame_post_draw
				var name: String = route+"-"+mode+("-narrow" if dimensions.x == 480 else "")
				root.get_texture().get_image().save_png("res://evidence/ui-10/"+name+".png")
				captures.append(name)
				if app.root_column.size.x > dimensions.x-20: issues.append(name+": horizontal content overflow "+str(app.root_column.size.x))
				if not is_instance_valid(app.sound): issues.append(name+": sound missing")
	app.flow.current = "records"; app.records = []; Palette.mode = "day"; app._render()
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/ui-10/records-empty-narrow.png")
	root.size = Vector2i(1440,900); app.flow.current = "battle"; app.selected_action = "attack"; app.selected_target = "sentinel"; app._render()
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/ui-10/battle-target.png")
	app._pause_menu()
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/ui-10/pause.png")
	var receipt := {"captures":captures,"issues":issues,"note":"Native Godot render, isolated test state. Fixture result is not a played victory. Screenshots alone do not establish browser or host acceptance."}
	var file := FileAccess.open("res://evidence/ui-10/render-receipt.json",FileAccess.WRITE); file.store_string(JSON.stringify(receipt,"  ")); file.close()
	print("CAPTURED ",captures.size()," ROUTE VIEWS; ISSUES: ",issues)
	quit(1 if not issues.is_empty() else 0)
