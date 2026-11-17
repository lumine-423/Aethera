extends SceneTree
## Screenshots of the mystic UI pass (real GPU renderer, not headless). Run sequentially:
##   Godot --path F:/sigil-circuit/rolecard-rpg --script res://tools/capture_mystic_ui.gd -- --ui-review [--only=a,b] [--night]
## Output: evidence/mystic-ui-20261114/<screen>_<day|night>.png

const OUT := "res://evidence/mystic-ui-20261114/"
var shots := ["title", "home", "story_hub", "story", "archive", "map", "workshop", "operations", "party", "battle", "result", "inventory", "characters", "events", "settings", "saves", "connect", "origin", "opening", "talk", "gallery", "records", "create", "help", "edit", "loading"]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	get_root().size = Vector2i(1600, 900)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var night := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): shots = a.trim_prefix("--only=").split(",")
		if a == "--night": night = true
	var ui = load("res://scenes/ui_root.tscn").instantiate()
	get_root().add_child(ui)
	await _frames(4)
	if ui.has_method("pass_gate"): ui.pass_gate("明星荧荧Hotaru")
	ui.acknowledge_notice()
	await _frames(4)
	get_root().get_node("UiHub").set_night(night, false)
	for name in shots:
		ui.busy = false
		var p := {}
		if name == "workshop": p = {}
		if name == "workshop_result":
			ui._reset("workshop", p); await _wait(0.3)
			_seed_workshop(ui.current()); await _wait(0.6)
			ui.current()._activate(); await _wait(2.6)
		elif name == "wipe_mid":
			ui._reset("home", p); await _wait(1.0)
			ui.go("title", {"phase": "menu"}, "wipe", "reset"); await _wait(0.36)
		else:
			ui._reset(name, p)
		if name == "workshop": _seed_workshop(ui.current())
		if name == "wipe_mid":
			get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "wipe_mid.png")); print("shot wipe"); continue
		await _wait(1.6)
		var img := get_root().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT + "%s_%s.png" % [name, "night" if night else "day"]))
		print("shot ", name)
	quit(0)

func _seed_workshop(ws) -> void:
	ws.draft = {"name": "破阵之印", "carrier": "长剑剑脊", "effect": "", "parts": []}
	ws.add_part("core.release", Vector2(590, 330), false)
	var core_id: String = ws.draft.parts[0].id
	for s in ["s0", "s1", "s3"]:
		ws.add_part("outer.beam" if s != "s3" else "outer.burst", ws.world_port(ws.worlds()[core_id], ws.defp("core.release"), s), true)
	ws.add_part("micro.overload", ws.world_port(ws.worlds()[ws.draft.parts[2].id], ws.defp("outer.beam"), "exit"), true)
	ws.selected_id = core_id
	ws.refresh()

func _frames(n: int) -> void:
	for i in range(n): await process_frame

func _wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
