extends SceneTree
var app
var checks:Array[String]=[]
var failures:Array[String]=[]
const OUT="res://evidence/home-motion-03/"
func _initialize() -> void: call_deferred("run")
func pause(seconds:float) -> void: await create_timer(seconds).timeout
func check(ok:bool,what:String) -> void:
	if ok: checks.append(what)
	else: failures.append(what); push_error(what)
func frame() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func click(control:Control) -> void:
	var point:=control.get_global_transform_with_canvas()*(control.size*0.5)
	var move:=InputEventMouseMotion.new(); move.position=point; Input.parse_input_event(move); await process_frame
	for down in [true,false]:
		var e:=InputEventMouseButton.new(); e.position=point; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=down; Input.parse_input_event(e); await process_frame
func run() -> void:
	root.size=Vector2i(1280,720)
	app=load("res://scenes/home.tscn").instantiate(); root.add_child(app)
	await pause(1.4)
	var first:Image=await frame(); first.save_png(OUT+"home-day.png")
	var before:Vector2=app.home_buttons.story.position
	await pause(3.0)
	var second:Image=await frame(); second.save_png(OUT+"home-day-later.png")
	var changed:=0
	for y in range(150,480,4):
		for x in range(130,430,4):
			var difference:Color=first.get_pixel(x,y)-second.get_pixel(x,y)
			if Vector3(difference.r,difference.g,difference.b).length()>0.008: changed+=1
	check(changed>100,"large left background moves in actual GPU frames")
	check(app.home_buttons.story.position==before,"background drift leaves button coordinates unchanged")
	check(app.home_buttons.story.tint_material.get_shader_parameter("backdrop")!=true,"foreground excluded from backdrop transform")
	await click(app.power); await pause(1.1)
	check(app.route=="title" and app.page_slot.visible and not app.menu.visible,"power click reaches title through curtain")
	(await frame()).save_png(OUT+"title.png")
	await click(app.page_slot.get_node("EnterHome")); await pause(1.15)
	check(app.route=="home" and app.menu.visible,"title enter button returns to home")
	app.open_modal("character",app.status); await pause(0.6)
	(await frame()).save_png(OUT+"bridge-day.png")
	await click(app.power); await pause(1.1)
	check(app.route=="title" and not app.modal.visible,"power remains clickable from bridge and closes detail")
	app.navigate("home"); await pause(1.1); app.set_night(true); await pause(0.6)
	(await frame()).save_png(OUT+"home-night.png")
	app.open_modal("character",app.status); await pause(0.6)
	(await frame()).save_png(OUT+"bridge-night.png")
	app.reduced_motion=true; app._paint()
	var clock_before:float=app.ambient_clock
	var still:Image=await frame(); await pause(0.8); var later:Image=await frame()
	check(app.ambient_clock==clock_before,"reduced motion freezes background clock")
	check(still.get_pixel(250,250)==later.get_pixel(250,250),"reduced motion background remains still on GPU")
	app.close_modal(true)
	# Narrow title flow uses the same return boundary.
	root.size=Vector2i(640,900); await pause(0.25); app.navigate("title"); await pause(0.1)
	check(app.page_slot.get_node("EnterHome").get_global_rect().intersects(Rect2(Vector2.ZERO,Vector2(root.size))),"narrow title enter control remains in viewport")
	(await frame()).save_png(OUT+"title-narrow.png")
	var f:=FileAccess.open(OUT+"checks.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"background_changed_samples":changed,"note":"GPU visual samples and real input events; aesthetic acceptance remains with user."},"  ")); f.close()
	print("HOME MOTION 03: ",checks.size()," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
