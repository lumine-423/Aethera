extends SceneTree
## 开场PV实机抽查（需要真窗口，不能 --headless）：
##   Godot --path F:/sigil-circuit/rolecard-rpg --script res://tools/capture_opening_pv.gd -- --ui-review
## 从标题页“重播开场”的入口进入，按全片时钟在几个秒数截图，并打印视频位置与音乐时钟的偏差。
## 截图写到 workspaces/frontend-ui/materials/opening-pv-20261116/godot-capture/。

const SHOTS := [1.6, 6.0, 21.0, 23.5, 44.0, 76.0, 86.0, 104.0, 121.5, 134.0]
const OUT := "res://workspaces/frontend-ui/materials/opening-pv-20261116/godot-capture"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ui = (load("res://scenes/ui_root.tscn") as PackedScene).instantiate()
	get_root().add_child(ui)
	await process_frame
	if ui.has_method("pass_gate"): ui.pass_gate("明星荧荧Hotaru")
	if ui.has_method("acknowledge_notice"): ui.acknowledge_notice()
	await process_frame
	ui.busy = false
	ui.go("opening", {"next": "title", "replay": true}, "none")
	await process_frame
	await process_frame
	var scr = ui.current()
	print("pv_ok=", scr.pv_ok, " music_playing=", scr.music.playing if scr.music else false)
	var i := 0
	var max_drift := 0.0
	var last := Time.get_ticks_msec()
	while i < SHOTS.size():
		await process_frame
		if not is_instance_valid(scr) or ui.current() != scr: break
		var tt: float = scr.pv_time()
		if scr.video.is_playing():
			max_drift = maxf(max_drift, absf(scr.video.stream_position - tt))
		if tt >= SHOTS[i]:
			await RenderingServer.frame_post_draw
			var im := get_root().get_texture().get_image()
			im.save_png(ProjectSettings.globalize_path(OUT + "/t_%06.2f.png" % SHOTS[i]))
			print("shot ", SHOTS[i], " clock=", snappedf(tt, 0.01), " video=", snappedf(scr.video.stream_position, 0.01), " fps=", Engine.get_frames_per_second())
			i += 1
	print("max_drift=", snappedf(max_drift, 0.01))
	scr._finish(false)
	for k in range(90): await process_frame
	print("after_end screen=", ui.current_name(), " music=", get_root().get_node("UiHub").music_current)
	quit(0)
