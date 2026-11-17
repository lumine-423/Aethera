extends SceneTree
const Home = preload("res://scenes/home.tscn")
var app
var failures: Array[String] = []
var checks: Array[String] = []
var captures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if ok: checks.append(label)
	else: failures.append(label); push_error(label)
func settle(seconds := 0.1) -> void:
	await create_timer(seconds).timeout
	for i in range(3): await process_frame
func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/home-build-01/"+name+".png"); captures.append(name)
func click(control: Control, local := Vector2(-1,-1)) -> void:
	var point := control.size/2 if local.x < 0 else local
	var pos := control.get_global_transform_with_canvas()*point
	var move := InputEventMouseMotion.new(); move.position=pos; Input.parse_input_event(move)
	await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new(); event.position=pos; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; Input.parse_input_event(event)
		await process_frame
func run() -> void:
	root.size=Vector2i(1672,941)
	app=Home.instantiate(); root.add_child(app); await settle(1.1)
	check(app.home_buttons.size()==5,"5 independent home buttons")
	check(app.home_buttons.story.caption.text=="剧情","editable story label")
	check(not app.home_buttons.story._has_point(Vector2.ZERO),"cut corner is not clickable")
	var resources_before: Array = []
	for b in app.home_buttons.values(): resources_before.append(b.face.texture.get_instance_id())
	await shot("home-day")
	await click(app.menu.get_node("ThemeSwitch/Moon")); await settle(0.6)
	check(app.theme_target and app.night_amount>0.99,"real mouse click switches night")
	var resources_after: Array = []
	for b in app.home_buttons.values(): resources_after.append(b.face.texture.get_instance_id())
	check(resources_before==resources_after,"day/night reuse same texture instances")
	await shot("home-night")
	app.set_night(false,false)
	await click(app.home_buttons.settings); await settle(0.5)
	check(app.modal.visible and app.modal_kind=="settings","settings opens through button")
	await shot("settings")
	var space=app.modal.get_node("Spacing"); space.value=1.0
	var text=app.modal.get_node("TextScale"); text.value=1.12
	check(is_equal_approx(app.spacing,1.0) and is_equal_approx(app.text_scale,1.12),"spacing/text sliders update live")
	var esc:=InputEventKey.new(); esc.keycode=KEY_ESCAPE; esc.pressed=true; Input.parse_input_event(esc); await settle(0.45)
	check(not app.modal.visible,"Escape closes modal")
	check(app.home_buttons.settings.has_focus(),"modal restores opener keyboard focus")
	await click(app.status); await settle(0.5)
	check(app.modal.visible and app.modal_kind=="character","character status opens secondary window")
	await shot("character-window")
	app.character_detail.selector.select(2); app.character_detail.selector.item_selected.emit(2); await settle(0.1)
	check(app.selected_character=="merlin" and app.status_name.text=="梅林","character switch uses real roster")
	app.close_modal(); await settle(0.45)
	app.spacing=0.5; app.text_scale=1.0; app.arrange()
	await click(app.home_buttons.story); await settle(1.1)
	check(app.route=="story" and not app.busy,"transition hands off to story slot")
	check(app.home_buttons.story.visible,"home nodes retained for reuse")
	app.navigate("home"); await settle(1.1)
	check(app.route=="home" and app.menu.visible,"return transition restores home")
	app.set_night(true); app.set_night(false); app.set_night(true); await settle(0.6)
	check(app.night_amount>0.99 and not app.busy,"rapid theme toggles converge")
	app.reduced_motion=true; app.entrance(); app.navigate("inventory")
	check(app.route=="inventory" and not app.busy,"reduced motion navigates without delayed lock")
	app.navigate("home"); app.set_night(false,false); app.selected_character=""; app.status_name.text="看板角色"
	for dim in [Vector2i(960,540),Vector2i(480,800)]:
		root.size=dim; await settle(0.2)
		for b in app.home_buttons.values():
			check(Rect2(Vector2.ZERO,app.logical_size).encloses(Rect2(b.position,b.size)),"button in bounds "+b.name+" "+str(dim))
		await shot("home-"+str(dim.x)+"x"+str(dim.y))
		app.set_night(true,false); await settle(0.1); await shot("home-night-"+str(dim.x)+"x"+str(dim.y)); app.set_night(false,false)
	var receipt := {"checks":checks,"failures":failures,"captures":captures,"note":"Native Godot input and GPU render. No gameplay, AI, database or user art acceptance implied."}
	var f := FileAccess.open("res://evidence/home-build-01/checks.json",FileAccess.WRITE); f.store_string(JSON.stringify(receipt,"  ")); f.close()
	print("HOME CHECKS: ",checks.size()," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
