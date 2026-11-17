extends SceneTree
## Home page frame-time probe (2026-11-17). Real window:
##   Godot --path . --resolution 1920x1080 --script res://tools/probe_home_perf.gd -- --ui-review
## Moves the pointer in a circle and reports frame times and script time per frame.

var ui

func _initialize() -> void:
	call_deferred("_run")

func wait(sec: float) -> void:
	var end := Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < end: await process_frame

func measure(label: String, sec: float) -> void:
	var dts: Array = []; var procs: Array = []
	var t0 := Time.get_ticks_usec(); var last := t0
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(sec * 1000.0):
		var a := (Time.get_ticks_msec() - start) / 1000.0 * 2.0
		var p := Vector2(960, 540) + Vector2(cos(a), sin(a)) * Vector2(700, 380)
		var ev := InputEventMouseMotion.new(); ev.position = p; ev.global_position = p
		get_root().warp_mouse(p); Input.parse_input_event(ev)
		await process_frame
		var now := Time.get_ticks_usec()
		dts.append((now - last) / 1000.0); last = now
		procs.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	var vp := get_root().get_viewport_rid()
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(vp)
	var cpu_r := RenderingServer.viewport_get_measured_render_time_cpu(vp)
	var jit := 0.0
	for i in range(1, dts.size()): jit += absf(dts[i] - dts[i - 1])
	jit /= maxf(dts.size() - 1, 1)
	print("PERF %s gpu=%.2fms render_cpu=%.2fms frame_jitter=%.2fms" % [label, gpu, cpu_r, jit])
	dts.sort(); procs.sort()
	var avg := 0.0
	for v in dts: avg += v
	avg /= maxf(dts.size(), 1)
	var pavg := 0.0
	for v in procs: pavg += v
	pavg /= maxf(procs.size(), 1)
	print("PERF %s frames=%d avg=%.2fms p95=%.2fms max=%.2fms | process avg=%.2fms p95=%.2fms | draw_calls=%d objects=%d" % [label, dts.size(), avg, dts[int(dts.size() * 0.95)], dts[-1], pavg, procs[int(procs.size() * 0.95)], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])

func _run() -> void:
	var hub = get_root().get_node("UiHub")
	hub.set_night(false, false)
	ui = load("res://scenes/ui_root.tscn").instantiate()
	get_root().add_child(ui)
	await process_frame
	if ui.has_method("pass_gate"): ui.pass_gate("明星荧荧Hotaru")
	ui.acknowledge_notice()
	await wait(0.3)
	var game = get_root().get_node("Game")
	var group: Dictionary = game.stat.get("角色组", {})
	group["凛零"] = {"好感度": 40, "色情值": 0}
	game.stat["角色组"] = group
	ui.busy = false
	ui._reset("home", {}); ui.screen_changed.emit("home")
	await wait(2.0)
	RenderingServer.viewport_set_measure_render_time(get_root().get_viewport_rid(), true)
	if "--novsync" in OS.get_cmdline_user_args(): DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var counts := {}
	for n in get_root().find_children("*", "CanvasItem", true, false):
		if not (n as CanvasItem).is_visible_in_tree(): continue
		var top: Node = n
		while top.get_parent() and top.get_parent() != ui and top.get_parent() != get_root(): top = top.get_parent()
		counts[top.name] = counts.get(top.name, 0) + 1
	var procn: Array = []
	for n in get_root().find_children("*", "", true, false):
		if n.is_processing() and n.get_script() != null:
			procn.append("%s(%s)" % [n.name, String(n.get_script().resource_path).get_file()])
	print("PERF processing nodes (%d): %s" % [procn.size(), ", ".join(procn)])
	print("PERF nodes=%d visible canvas items by top node: %s" % [get_root().get_child_count(), str(counts)])
	print("PERF fps_engine=%d vsync=%d max_fps=%d" % [Engine.get_frames_per_second(), DisplayServer.window_get_vsync_mode(), Engine.max_fps])
	await measure("home_day", 4.0)
	hub.set_night(true, false); await wait(0.6)
	await measure("home_night", 4.0)
	if "--ablate" in OS.get_cmdline_user_args():
		var home = ui.current()
		var room = home.find_child("Room", false, false)
		room.set_process(false); await wait(0.3)
		await measure("room_process_off", 3.0)
		room.set_process(true)
		home.set_process(false); await wait(0.3)
		await measure("ui_float_off", 3.0)
		home.set_process(true)
		var ring = home.find_child("Ring", true, false)
		ring.set_process(false); await wait(0.3)
		await measure("ring_off", 3.0)
		ring.set_process(true)
		for b in home.find_children("*", "Button", true, false): b.set_process(false)
		await wait(0.3)
		await measure("buttons_process_off", 3.0)
		room.set_process(false); ring.set_process(false); home.set_process(false)
		await wait(0.3)
		await measure("all_home_process_off", 3.0)
		home.visible = false; await wait(0.3)
		await measure("home_hidden", 3.0)
	quit(0)
