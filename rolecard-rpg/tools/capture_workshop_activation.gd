extends SceneTree
## Workshop activation ceremony checks + screenshots (2026-11-17). Needs a real window (audio clock):
##   Godot --path F:/sigil-circuit/rolecard-rpg --resolution 1920x1080 --script res://tools/capture_workshop_activation.gd -- --ui-review
## User rules checked: day and night are the same; 03 click -> 04 loop_a -> 05 loop_b -> 06 done play
## in order, each to its end; nothing else sounds while they play. Also: picture follows the music
## clock, the seal lands on 06, the result panel follows, skipping works.

const OUT := "res://evidence/workshop-activation-20261117/"
var failures: Array = []
var passes := 0
var ui
var hub
var rec: AudioEffectRecord
var sheet: Dictionary = {}

func ok(cond: bool, label: String) -> void:
	if cond: passes += 1; print("PASS ", label)
	else: failures.append(label); print("FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end: await process_frame

func shot(name: String) -> void:
	await process_frame
	get_root().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("SHOT ", name)

func seed_draft(ws) -> void:
	ws.draft = {"name": "破阵之印", "carrier": "长剑剑脊", "effect": "剑脊亮起一线白光，斩开迎面的结界", "parts": []}
	ws.add_part("core.release", Vector2(590, 330), false)
	var core_id: String = ws.draft.parts[0].id
	for s in ["s0", "s1", "s3"]:
		ws.add_part("outer.beam" if s != "s3" else "outer.burst", ws.world_port(ws.worlds()[core_id], ws.defp("core.release"), s), true)
	ws.add_part("micro.overload", ws.world_port(ws.worlds()[ws.draft.parts[2].id], ws.defp("outer.beam"), "exit"), true)
	ws.selected_id = core_id
	ws.refresh()

func other_sound_playing() -> bool:
	for k in hub._sfx_players:
		for p in hub._sfx_players[k].pool:
			if p.playing: return true
	return hub._ws_click_player != null and hub._ws_click_player.playing

func until_t(fx, target: float, max_sec: float) -> bool:
	## waits, returns true if any non-activation sound played meanwhile
	var bad := false
	var end := Time.get_ticks_msec() + int(max_sec * 1000.0)
	while is_instance_valid(fx) and fx.t < target and Time.get_ticks_msec() < end:
		if other_sound_playing(): bad = true
		await process_frame
	return bad

func run_variant(label: String, night: bool) -> void:
	hub.set_night(night, false); await wait(0.4)
	var ws = ui.current()
	seed_draft(ws); await wait(0.8)
	ws._activate()
	await process_frame
	var fx = ws.find_child("ActivationFx", false, false)
	ok(fx != null, "%s: activation ceremony starts" % label)
	if fx == null: return
	var st: AudioStream = hub._ws_loop_player.stream
	var placed: Dictionary = sheet.get("sequence", {}).get("start", {})
	var mix = JSON.parse_string(FileAccess.get_file_as_string("res://data/workshop/activation_mix.json")) if FileAccess.file_exists("res://data/workshop/activation_mix.json") else {}
	var layout_ok: bool = mix is Dictionary and not mix.is_empty()
	if layout_ok:
		for r in ["click", "loop_a", "loop_b", "done"]:
			if absf(float(placed.get(r, -9)) - float(mix.starts[r])) > 0.002: layout_ok = false
	ok(st != null and String(st.resource_path).ends_with("activate_sequence.ogg") and not (st as AudioStreamOggVorbis).loop and layout_ok,
		"%s: one-file mix placed as the user set it, played once (%s)" % [label, str(placed)])
	ok(hub.sfx_quiet and absf(fx.T - float(placed.get("done", -1))) < 0.002, "%s: UI sounds muted; seal at the start of 4 (%.2fs)" % [label, fx.T])
	if label == "day":
		var bus := AudioServer.get_bus_index("Master")
		rec = AudioEffectRecord.new(); AudioServer.add_bus_effect(bus, rec)
		rec.set_recording_active(true)
	var beats := [["01_ignite", 0.3], ["02_rings", fx.R1 - 0.4], ["03_dataflow", fx.R1 + 1.5], ["04_gather", fx.B0 + 1.2], ["05_climax", fx.A_PEAK - 0.05]]
	var max_off := 0.0
	var bad := false
	for b in beats:
		if await until_t(fx, float(b[1]), 30.0): bad = true
		var a: float = hub.workshop_activation_time()
		if a >= 0.0: max_off = maxf(max_off, absf(a - fx.t))
		await shot("%s_%s" % [label, b[0]])
	ok(max_off < 0.08, "%s: picture follows the music clock (max offset %.3fs)" % [label, max_off])
	if await until_t(fx, fx.T + 0.12, 6.0): bad = true
	ok(fx._sealed and hub._ws_loop_player.playing, "%s: seal lands on 06 while the sequence keeps playing" % label)
	await shot("%s_06_seal" % label)
	if await until_t(fx, fx.T + 1.3, 3.0): bad = true
	await shot("%s_07_title" % label)
	if await until_t(fx, fx.END, 6.0): bad = true
	ok(not bad, "%s: no other sound played during the ceremony" % label)
	if rec and rec.is_recording_active():
		rec.set_recording_active(false)
		var wav: AudioStreamWAV = rec.get_recording()
		if wav: wav.save_to_wav(ProjectSettings.globalize_path(OUT + "heard_day.wav")); print("REC saved")
	await wait(0.4)
	ok(ws.overlay == "result" and ws.find_child("ResultOk", true, false) != null and not hub.sfx_quiet, "%s: result panel after 06 ends, UI sounds back" % label)
	await shot("%s_08_result" % label)
	ws.find_child("ResultOk", true, false).pressed.emit()
	await wait(0.4)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(OUT)): DirAccess.remove_absolute(ProjectSettings.globalize_path(OUT + f))
	hub = get_root().get_node("UiHub")
	ui = load("res://scenes/ui_root.tscn").instantiate()
	get_root().add_child(ui)
	await process_frame
	if ui.has_method("pass_gate"): ui.pass_gate("明星荧荧Hotaru")
	ui.acknowledge_notice()
	await wait(0.3)
	ui.busy = false
	ui._reset("workshop", {}); ui.screen_changed.emit("workshop")
	await wait(0.8)
	sheet = JSON.parse_string(FileAccess.get_file_as_string("res://data/workshop/activation_cues.json"))
	ok(sheet is Dictionary and sheet.clips.size() == 4, "activation cue sheet built from the 4 clips")
	ok(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://assets/audio/ui/workshop_activation/fx")), "no self-made effect sounds in the game")
	await run_variant("day", false)
	await run_variant("night", true)
	# skip
	var ws = ui.current()
	seed_draft(ws); await wait(0.3)
	ws._activate(); await wait(2.0)
	var fx = ws.find_child("ActivationFx", false, false)
	var ev := InputEventMouseButton.new(); ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
	fx._gui_input(ev); await wait(0.2)
	ok(fx._sealed and not hub._ws_loop_player.playing and hub._ws_click_player.playing and String(hub._ws_click_player.stream.resource_path).ends_with("activate_done.ogg"), "click skips to the seal: only 06 plays")
	fx._gui_input(ev); await wait(0.9)
	ok(ws.overlay == "result", "second click closes the ceremony")
	print("%d passed, %d failed" % [passes, failures.size()])
	for f in failures: print("  failed: ", f)
	quit(0 if failures.is_empty() else 1)
