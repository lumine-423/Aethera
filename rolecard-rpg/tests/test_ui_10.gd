extends SceneTree
const Shell = preload("res://scenes/game_shell.tscn")
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool,caption: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(caption)

func run() -> void:
	root.size = Vector2i(1280,800)
	var app = Shell.instantiate()
	app.store.path = "res://.tmp/ui-10-test-%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	await process_frame
	var sound_id: int = app.sound.get_instance_id()
	app._navigate("missions"); app._navigate("mission_detail"); app._navigate("prepare")
	check(app.page == "prepare","navigation retains route")
	check(is_instance_valid(app.sound) and app.sound.get_instance_id() == sound_id,"sound survives repeated renders")
	app._begin()
	check(app.page == "battle" and app.rules.state.status == "active","prepare starts existing combat rules")
	var revision: int = app.rules.state.revision
	app._select_action("attack"); app.selected_target = "sentinel"
	app._commit(); app._skip_presentation()
	check(app.rules.unit("sentinel").hp == 25 and app.rules.state.revision == revision+1,"redrawn controls commit once")
	app._pause_menu()
	check(app.flow.modal == "pause" and app.paused and is_instance_valid(app.modal_shade),"pause owns modal and shade")
	root.size = Vector2i(480,800)
	await process_frame; await process_frame
	check(app.flow.modal == "pause" and is_instance_valid(app.modal_shade),"resize preserves live modal")
	var dialog: ConfirmationDialog
	for child in app.get_children():
		if child is ConfirmationDialog and child.title == "行动暂停": dialog = child
	check(dialog != null and dialog.visible,"pause dialog survives resize")
	dialog.confirmed.emit()
	await process_frame
	check(app.flow.modal.is_empty() and not app.paused and app.compact,"resume after resize restores compact controls")
	app._save_and_leave()
	check(app.page == "home" and not app.saved_battle.is_empty(),"save and return preserved")
	app._continue()
	check(app.page == "battle" and app.paused and app.rules.unit("sentinel").hp == 25,"restore keeps action and pauses")
	app._finish("retreat")
	check(app.page == "result" and app.records.size() == 1,"result view receives recorded action")
	check(is_instance_valid(app.sound) and app.sound.get_instance_id() == sound_id,"sound survives full player flow")
	print("UI_10 ",checks," checks / ",failures," failures")
	quit(failures)
