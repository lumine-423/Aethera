extends SceneTree
## Home dream room checks + screenshots (2026-11-17). Needs a real window (not headless):
##   Godot --path F:/sigil-circuit/rolecard-rpg --resolution 1920x1080 --script res://tools/capture_home_room.gd -- --ui-review
## Shots go to res://evidence/home-room-20261117/.

const OUT := "res://evidence/home-room-20261117/"
var failures: Array = []
var passes := 0
var ui

func ok(cond: bool, label: String) -> void:
	if cond: passes += 1; print("PASS ", label)
	else: failures.append(label); print("FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end: await process_frame

func shot(name: String) -> void:
	await process_frame; await process_frame
	var img := get_root().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("SHOT ", name)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var hub = get_root().get_node("UiHub")
	hub.set_night(false, false)
	ui = load("res://scenes/ui_root.tscn").instantiate()
	get_root().add_child(ui)
	await process_frame
	if ui.has_method("pass_gate"): ui.pass_gate("明星荧荧Hotaru")
	ui.acknowledge_notice()
	await wait(0.3)
	# review-only: meet one character in memory so the showcase art is on the page
	var game = get_root().get_node("Game")
	var group: Dictionary = game.stat.get("角色组", {})
	group["凛零"] = {"好感度": 40, "色情值": 0}
	game.stat["角色组"] = group
	ui.busy = false
	ui._reset("home", {}); ui.screen_changed.emit("home")   # same signal real navigation sends (drives BGM)
	await wait(1.6)
	ok(hub.music_current == "白昼天晴", "day home plays 白昼天晴 (got %s)" % hub.music_current)
	var home = ui.current()
	var room = home.find_child("Room", false, false)
	ok(room != null, "home mounts the interactive room")
	if room == null: quit(1); return
	ok(room.find_child("RoomTags", true, false) == null, "hovering objects shows no name tag")
	ok(not ui.backdrop.visible, "home hides the shared backdrop (room is its own background)")
	# hit tests on known spots (source px -> screen)
	var probes := {"window": Vector2(1550, 400), "fireplace": Vector2(880, 470), "star": Vector2(729, 386), "cup": Vector2(960, 618),
		"book": Vector2(887, 625), "chair_r": Vector2(1065, 700), "table": Vector2(912, 760), "panel_r": Vector2(946, 300)}
	for id in probes:
		var got: String = room.hit(room.to_screen(probes[id]))
		ok(got == id, "hit %s -> %s" % [id, got])
	var art = home.find_child("Showcase", true, false)
	ok(art != null, "showcase character is on the home page")
	if art:
		var body: Vector2 = art.get_global_rect().get_center() + Vector2(0, 80)
		ok(room.hit(room.get_global_transform().affine_inverse() * body) == "", "click on the character does not reach furniture behind")
	# glass buttons
	var story = home.find_child("Story", true, false)
	ok(story != null and story.fill_mult < 0.7, "home buttons are see-through (fill_mult %.2f)" % (story.fill_mult if story else -1.0))
	await shot("01_home_day")
	room._set_hover("fireplace"); await wait(0.35)
	await shot("02_hover_fireplace_day")
	room._set_hover("")
	room.interact("fireplace"); await wait(0.3)
	await shot("03_fire_flare_day")
	await wait(1.8)
	room.interact("window"); await wait(1.3)
	await shot("04_window_open_day")
	room.interact("sofa"); room.interact("chair_l"); room.interact("book"); room.interact("cup"); room.interact("star")
	await wait(0.09)
	await shot("05_props_moving_day")
	await wait(4.0)
	ok(not room.win_open and room.win < 0.05, "window closes again by itself")
	# hide UI
	home.set_ui_hidden(true); await wait(0.7)
	ok(home.ui_hidden and not home.layers["Front"].visible and home.find_child("HideUI", true, false).is_visible_in_tree(), "hide UI: layers gone, eye key stays")
	await shot("06_hidden_day")
	ok(home.on_back() and not home.ui_hidden, "Esc / back brings the UI back first")
	await wait(0.6)
	# no pointer float (user 2026-11-17): move the pointer to a corner, nothing may move
	var off0: Vector2 = room.off
	get_root().warp_mouse(Vector2(1900, 1060))
	var mv := InputEventMouseMotion.new(); mv.position = Vector2(1900, 1060); mv.global_position = mv.position
	Input.parse_input_event(mv)
	await wait(0.5)
	var moved := false
	for n in home.layers:
		if home.layers[n].position.length() > 0.01: moved = true
	ok(not moved and room.off == off0, "nothing follows the pointer (UI, character, room all still)")
	# night
	hub.set_night(true, false); await wait(0.6)
	ok(hub.music_current == "温柔夜色", "night home plays 温柔夜色 (got %s)" % hub.music_current)
	await shot("07_home_night")
	room.interact("fireplace"); await wait(0.3)
	await shot("08_fire_flare_night")
	await wait(1.8)
	room.interact("window"); await wait(1.3)
	await shot("09_window_open_night")
	await wait(4.2)
	home.set_ui_hidden(true); await wait(0.7)
	await shot("10_hidden_night")
	home.set_ui_hidden(false); await wait(0.6)
	# other pages: blurred room backdrop; story keeps plain
	for nm in ["archive", "settings", "inventory"]:
		ui.busy = false; ui._reset(nm, {}); ui.screen_changed.emit(nm); await wait(1.0)
		ok(ui.backdrop.visible and ui.backdrop.style == "room", "%s uses the blurred room backdrop" % nm)
		await shot("11_%s_night" % nm)
	hub.set_night(false, false); await wait(0.4)
	ui.busy = false; ui._reset("archive", {}); await wait(1.0)
	await shot("12_archive_day")
	ui.busy = false; ui._reset("settings", {}); await wait(1.0)
	await shot("13_settings_day")
	ok(not hub._sfx_map.get("packs", {}).has("original"), "old synth sound pack removed from the pack list")
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/audio/ui/original")), "old synth sound files removed from game assets")
	var missing: Array = []
	for cue in ["room_hover", "room_window_open", "room_window_close", "room_fire", "room_star", "room_panel", "room_sofa", "room_chair", "room_book", "room_cup", "room_table", "room_ui_hide", "room_ui_show"]:
		if hub._stream(cue) == null: missing.append(cue)
	ok(missing.is_empty(), "all 13 synthesized room sounds load %s" % str(missing))
	ui.busy = false; ui._reset("story", {}); await wait(1.2)
	ok(ui.backdrop.style == "plain", "story screen keeps the original backdrop")
	await shot("14_story_day")
	print("\n%d passed, %d failed" % [passes, failures.size()])
	for f in failures: print("  FAIL: ", f)
	quit(1 if failures.size() > 0 else 0)
