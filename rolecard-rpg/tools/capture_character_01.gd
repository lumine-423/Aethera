extends SceneTree
const Home = preload("res://scenes/home.tscn")
var app
var checks:Array[String]=[]
var failures:Array[String]=[]
var captures:Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(ok:bool,label:String) -> void:
	if ok: checks.append(label)
	else: failures.append(label); push_error(label)
func settle(seconds:=0.1) -> void:
	await create_timer(seconds).timeout
	for i in range(3): await process_frame
func click(control:Control) -> void:
	var pos:=control.get_global_transform_with_canvas()*(control.size/2)
	var move:=InputEventMouseMotion.new(); move.position=pos; Input.parse_input_event(move)
	await process_frame
	for state in [true,false]:
		var e:=InputEventMouseButton.new(); e.position=pos; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=state; Input.parse_input_event(e); await process_frame
func shot(name:String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://evidence/character-panel-01/"+name+".png"); captures.append(name)
func run() -> void:
	root.size=Vector2i(1672,941); app=Home.instantiate(); root.add_child(app); await settle(1.0)
	var background_id=app.background.texture.get_instance_id()
	print("STATUS ",app.status.get_global_rect()," WINDOW ",root.size," visible ",app.status.visible)
	await click(app.status); await settle(0.4)
	if not is_instance_valid(app.character_detail):
		await shot("click-failure")
		print("FOCUS ",app.get_viewport().gui_get_focus_owner()," MODAL ",app.modal_kind)
		quit(1); return
	check(app.modal.visible and app.modal_kind=="character","status entry opens detail panel")
	check(is_instance_valid(app.character_detail),"separate detail module instantiated")
	check(not app.home_buttons.story.visible and not app.status.visible,"old home buttons hidden behind common background")
	check(app.background.texture.get_instance_id()==background_id,"uses existing common background instance")
	check(app.character_detail.get_node_or_null("Interact")==null and app.character_detail.get_node_or_null("DynamicDemo")==null,"removed action blocks have no runtime nodes")
	check(app.character_detail.meter.value==0.0 and app.character_detail.widgets.AffinityValue.text=="—","missing affinity not fabricated")
	await shot("detail-day")
	var texture_id=app.character_detail.widgets.Body.texture.get_instance_id()
	await click(app.menu.get_node("ThemeSwitch/Moon")); await settle(0.65)
	check(app.theme_target and app.night_amount>0.99,"theme switch receives mouse input through transparent detail container")
	check(app.character_detail.widgets.Body.texture.get_instance_id()==texture_id,"night uses same foreground texture")
	await shot("detail-night")
	app.set_night(false,false)
	var p=app.character_detail
	p.input.text="测试内容 [b] 保留原文"; p.input.text_changed.emit(p.input.text)
	await click(p.send); await settle(0.1)
	check(app.character_messages.rin==["测试内容 [b] 保留原文"],"send preserves typed content")
	check(p.history.text.contains("你：测试内容 [b] 保留原文") and not p.history.bbcode_enabled,"message markup remains plain text")
	check(p.connection.visible and p.connection.text=="AI尚未连接","unconnected backend clearly indicated; no fake AI reply")
	check(p.send.disabled and p.input.text.is_empty(),"empty send is disabled after submission")
	p.selector.select(2); p.selector.item_selected.emit(2); await settle()
	check(app.selected_character=="merlin" and app.modal.visible,"header switches character without leaving detail page")
	check(not p.history.visible and p.greeting.visible,"character histories remain separated")
	p.selector.select(0); p.selector.item_selected.emit(0); await settle()
	check(p.history.text.contains("测试内容"),"returning to character restores its in-memory content")
	await shot("detail-message")
	await click(p.close_button); await settle(0.45)
	check(not app.modal.visible and app.home_buttons.story.visible and app.status.visible,"close restores home controls")
	check(app.status.has_focus(),"close restores opener focus")
	await click(app.status); await settle(0.5)
	check(app.character_detail.history.text.contains("测试内容"),"reopening preserves session-only input history")
	var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true; Input.parse_input_event(escape); await settle(0.45)
	check(not app.modal.visible,"Escape closes detail from text input")
	root.size=Vector2i(480,800); await settle(0.2); await click(app.status); await settle(0.5)
	p=app.character_detail
	check(p.logical_size==Vector2(900,1180),"narrow panel uses readable reflow")
	for id in ["Selector","Input","Send","Close","History"]:
		check(Rect2(Vector2.ZERO,p.logical_size).encloses(Rect2(p.widgets[id].position,p.widgets[id].size)),"control remains in panel: "+id)
	await shot("detail-narrow-day")
	app.set_night(true,false); await settle(); await shot("detail-narrow-night")
	var f:=FileAccess.open("res://evidence/character-panel-01/checks.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"captures":captures,"note":"Native UI input and GPU render; no AI service or actual affection data connected."},"  ")); f.close()
	print("CHARACTER CHECKS: ",checks.size()," passed; ",failures.size()," failed")
	quit(0 if failures.is_empty() else 1)
