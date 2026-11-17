extends SceneTree
var app
func _initialize() -> void: call_deferred("run")
func pause(seconds:float) -> void: await create_timer(seconds).timeout
func run() -> void:
	root.size=Vector2i(1280,720)
	app=load("res://scenes/home.tscn").instantiate(); root.add_child(app)
	await pause(6.0); app.open_modal("character",app.status)
	await pause(4.0); app.set_night(true)
	await pause(4.0); app.navigate("title")
	await pause(1.8); app.navigate("home")
	await pause(2.2); quit()
