extends SceneTree
var app
var checks:Array[String]=[]
var failures:Array[String]=[]
func _initialize() -> void: call_deferred("run")
func pause_for(seconds:float) -> void: await create_timer(seconds).timeout
func check(ok:bool,what:String) -> void:
	if ok: checks.append(what)
	else: failures.append(what); push_error(what)
func move(control:Control) -> void:
	var e:=InputEventMouseMotion.new(); e.position=control.get_global_transform_with_canvas()*(control.size*0.5); Input.parse_input_event(e); await process_frame
func away() -> void:
	var e:=InputEventMouseMotion.new(); e.position=Vector2(20,20); Input.parse_input_event(e); await process_frame
func shot(name:String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/fidelity-02/"+name+".png")
func run() -> void:
	root.size=Vector2i(1280,720)
	app=load("res://scenes/home.tscn").instantiate(); root.add_child(app); await away(); await pause_for(1.2)
	for b in app.home_buttons.values(): b.release_focus()
	await pause_for(0.6); await shot("home-day")
	for key in ["story","archive","battle","inventory","settings"]:
		var b=app.home_buttons[key]; await move(b); await pause_for(0.26)
		check(absf(b.visual.position.y+3.0)<0.15,"hover lift -3: "+key)
		check(float(b.tint_material.get_shader_parameter("sheen_strength"))>0.0,"sweep present: "+key)
		await pause_for(0.38); await away(); await pause_for(0.23)
	app.set_night(true); await pause_for(0.8); await shot("home-night")
	check(absf(app.night_amount-1.0)<0.001,"shared palette converges after 0.4 sec")
	app.open_modal("character",app.status); await pause_for(0.5); await shot("panel-night")
	check(app.modal.scale==Vector2.ONE and app.modal.position==Vector2.ZERO,"wide detail keeps master coordinate canvas")
	var p=app.character_detail
	check(p.widgets.FrameOutline.visible,"original outline layer present")
	check(p.widgets.Body.position.y+p.widgets.Body.size.y>=823,"full-height backing retained")
	check(p.widgets.Greeting.position.x>1000,"greeting not animated to top-left")
	p.input.text="你好，今天想聊些什么？"; p.input.text_changed.emit(p.input.text); await move(p.send); await pause_for(0.65)
	await move(p.close_button); await pause_for(0.25)
	check(absf(p.close_button.get_node("Glyph").rotation-PI/2)<0.02,"close icon hover rotation 90 degrees")
	p.selector.select(2); p.selector.item_selected.emit(2); await pause_for(0.65)
	app.set_night(false); await away(); await pause_for(0.7); await shot("panel-day")
	app.close_modal(); await pause_for(0.5)
	check(not app.modal.visible,"modal hide completes after 0.35 sec")
	app.navigate("story"); await pause_for(0.37); await shot("wipe-before-swap")
	check(app.route=="home" and app.busy,"route stays until 0.42 sec")
	await pause_for(0.1); await shot("wipe-after-swap")
	check(app.route=="story" and app.wipe.visible,"swap occurs under curtain")
	await pause_for(0.58); check(not app.busy and not app.wipe.visible,"curtain unlocks at 1.0 sec")
	app.navigate("home"); await pause_for(1.2)
	app.reduced_motion=true; app.open_modal("character",app.status); check(app.modal.modulate.a==1.0,"reduced motion immediate open")
	app.close_modal(); check(not app.modal.visible,"reduced motion immediate close")
	var f:=FileAccess.open("res://evidence/fidelity-02/motion-checks.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"note":"Motion property checks and GPU frames; no aesthetic percentage or driver acceptance."},"  ")); f.close()
	print("FIDELITY MOTION: ",checks.size()," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
