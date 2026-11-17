extends SceneTree
func _initialize() -> void: call_deferred("run")
func pause_for(seconds: float) -> void: await create_timer(seconds).timeout
func run() -> void:
	root.size=Vector2i(1280,720)
	var app=load("res://scenes/home.tscn").instantiate(); root.add_child(app)
	await pause_for(1.3)
	app.home_buttons.story.hovered=true; app.home_buttons.story.feedback(); await pause_for(0.45)
	app.home_buttons.story.hovered=false; app.home_buttons.story.feedback(); app.set_night(true); await pause_for(1.1)
	app.open_modal("settings",app.home_buttons.settings); await pause_for(1.1)
	app.close_modal(); await pause_for(0.4)
	app.set_night(false); await pause_for(0.7)
	app.navigate("story"); await pause_for(1.2)
	app.navigate("home"); await pause_for(1.2)
	quit()
