extends Node
## Renders every UI screen (day + night) through the real UI root with the GPU renderer and
## saves PNGs to evidence/ui-full-01. Also records script errors via a simple pass/fail list.
## Usage: Godot --path . res://tools/capture_ui_full_01.tscn -- --ui-review [--only=a,b] [--size=1920x1080] [--day-only]
const ROOT := preload("res://scenes/ui_root.tscn")
const OUT := "res://evidence/ui-full-01/"
var ui
var targets := [
	["title", "title", {}], ["title-menu", "title", {"_phase": "menu"}], ["title-unlock", "title", {"locked": true, "_phase": "unlock"}],
	["loading", "loading", {"next": "showcase", "duration": 30.0}], ["home", "home", {}], ["saves", "saves", {"mode": "save"}],
	["story-hub", "story_hub", {}], ["story", "story", {"chapter": "ch1", "_line": 3}], ["story-choice-open", "story", {"chapter": "ch1", "_line": 3, "_expand": 0}], ["story-free-open", "story", {"chapter": "ch1", "_line": 3, "_expand": 3}], ["story-replay", "story", {"replay": true, "_line": 1}],
	["archive", "archive", {}], ["characters", "characters", {}], ["gallery", "gallery", {}],
	["operations", "operations", {}], ["party", "party", {}], ["battle", "battle", {}], ["battle-detail", "battle", {"_detail": true}],
	["result-win", "result", {"outcome": "win"}], ["result-lose", "result", {"outcome": "lose"}], ["result-retreat", "result", {"outcome": "retreat"}],
	["records", "records", {}], ["crafting", "crafting", {}], ["inventory", "inventory", {}],
	["settings-display", "settings", {"tab": "display"}], ["settings-audio", "settings", {"tab": "audio"}], ["settings-ai", "settings", {"tab": "ai"}],
	["settings-worldbook", "settings", {"tab": "worldbook"}], ["settings-backup", "settings", {"tab": "backup"}], ["showcase", "showcase", {}],
]

func _ready() -> void: call_deferred("run")

func settle(seconds := 0.2) -> void:
	await get_tree().create_timer(seconds).timeout
	for i in range(3): await get_tree().process_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + name + ".png")
	print("captured ", name)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only: Array = []
	var dims := Vector2i(1920, 1080)
	var day_only := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="): only = a.trim_prefix("--only=").split(",")
		if a.begins_with("--size="):
			var p := a.trim_prefix("--size=").split("x"); dims = Vector2i(int(p[0]), int(p[1]))
		if a == "--day-only": day_only = true
	if "--checks" in OS.get_cmdline_user_args():
		await run_checks(); return
	get_window().size = dims; get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	ui = ROOT.instantiate(); add_child(ui); await settle(0.5)
	var suffix := "" if dims == Vector2i(1920, 1080) else "-%dx%d" % [dims.x, dims.y]
	for t in targets:
		if not only.is_empty() and not t[0] in only: continue
		for night in ([false] if day_only else [false, true]):
			UiHub.set_night(night, false)
			ui._reset(t[1], t[2])
			var n = ui.current()
			if t[2].has("_phase"): n.phase = t[2]._phase; n.rebuild()
			if t[2].has("_line") and n.has_method("jump_to"): n.jump_to(t[2]._line)
			if t[2].has("_detail") and n.has_method("open_detail"): n.open_detail(0)
			if t[2].has("_expand"):
				await settle(0.3); n.panel._tap(t[2]._expand)
			await settle(2.2 if t[1] == "battle" else 1.1)
			await shot(t[0] + ("-night" if night else "-day") + suffix)
	get_tree().quit()

# ---------- interaction checks (--checks) ----------
var passed: Array = []
var failed: Array = []
var requests: Array = []
var sounds_seen: Array = []

func check(ok: bool, label: String) -> void:
	if ok: passed.append(label)
	else: failed.append(label); push_error("CHECK FAILED: " + label)

func click(control: Control) -> void:
	var pos := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var move := InputEventMouseMotion.new(); move.position = pos; Input.parse_input_event(move)
	await get_tree().process_frame
	for pressed in [true, false]:
		var e := InputEventMouseButton.new(); e.position = pos; e.button_index = MOUSE_BUTTON_LEFT; e.pressed = pressed
		Input.parse_input_event(e); await get_tree().process_frame

func run_checks() -> void:
	get_window().size = Vector2i(1600, 900)
	UiHub.action_requested.connect(func(a, p): requests.append(a))
	UiHub.sfx_requested.connect(func(c): if not c in sounds_seen: sounds_seen.append(c))
	ui = ROOT.instantiate(); add_child(ui); await settle(0.6)
	check(ui.current_name() == "title", "starts on title")
	# every registered screen builds
	for name in ui.SCREENS.keys():
		ui._reset(name, {}); await settle(0.15)
		check(ui.current() != null and ui.current().get_child_count() > 0, "screen builds: " + name)
	# real click through title menu
	ui._reset("title", {}); var t = ui.current(); t.phase = "menu"; t.rebuild(); await settle(0.9)
	await click(t.get_node("Menu4")); await settle(1.2)
	check(ui.current_name() == "showcase", "real click: title menu -> 界面总览")
	ui.back(); await settle(1.2)
	check(ui.current_name() == "title", "back returns to title")
	# home routing
	ui._reset("home", {}); await settle(0.8)
	var home = ui.current()
	home.navigate("battle"); await settle(1.2)
	check(ui.current_name() == "operations", "home 作战 -> 地点 screen")
	ui._handle_back(); await settle(1.2)
	check(ui.current_name() == "home" and ui.current().visible, "Esc/back from 地点 returns home")
	home.navigate("settings"); await settle(1.2)
	check(ui.current_name() == "settings", "home 设置 -> full settings screen")
	ui._reset("home", {}); await settle(0.5)
	# battle: skill -> target -> damage, hp bar follows
	ui._reset("battle", {}); await settle(0.6)
	var b = ui.current()
	var enemy := -1
	for i in range(b.units.size()):
		if b.units[i].side == "enemy": enemy = i; break
	var hp0: int = b.units[enemy].hp
	b._choose(0); await settle(0.2)
	check(b.views[enemy].targetable, "battle: enemies become targets after picking 普攻")
	b._on_unit(enemy); await settle(0.3)
	check(b.units[enemy].hp < hp0, "battle: target loses HP (%d -> %d)" % [hp0, b.units[enemy].hp])
	check("battle.use_skill" in requests, "battle: use_skill request emitted to services")
	await settle(1.0)
	b.open_detail(0); await settle(0.4)
	check(is_instance_valid(b.detail), "battle: 角色详情 panel opens")
	ui._handle_back(); await settle(0.4)
	check(not is_instance_valid(b.detail) or b.detail.is_queued_for_deletion(), "battle: back closes detail first")
	# story: advance, choices, free input
	ui._reset("story", {}); await settle(0.5)
	var s = ui.current()
	s.advance(); s.advance(); await settle(0.2)
	check(s.index == 1, "story: click completes text then advances")
	s.jump_to(3); await settle(0.4)
	check(s.choices_visible and is_instance_valid(s.panel) and s.panel.rows.size() == 4, "story: 行动框 shows 3 options + 自由输入")
	s.panel._tap(1); await settle(0.6)
	check(s.panel.expanded == 1 and s.panel.rows[1].cur > 100.0, "story: tapping an option expands its full text")
	check(not s.panel.confirm.disabled, "story: 发送 enabled after choosing")
	s.panel._tap(3); await settle(0.5)
	check(s.panel.confirm.disabled, "story: 发送 disabled while 自由输入 is empty")
	s.input.text = "测试输入"; s._send_free(); await settle(0.1)
	check("story.free_input" in requests, "story: free input request emitted")
	s.open_backlog(); await settle(0.2)
	check(s.backlog_open, "story: 回看 opens")
	ui._handle_back(); await settle(0.2)
	check(not s.backlog_open, "story: back closes 回看")
	ui._reset("story", {"replay": true}); await settle(0.4)
	check(ui.current().input == null, "replay: no free input / send")
	# day / night and options
	UiHub.set_night(true, false); await settle(0.1)
	check(UiHub.c("accent").is_equal_approx(Color(UiHub.palette.night.accent)), "night palette applied")
	UiHub.set_night(false, false)
	var sp := UiHub.spacing; UiHub.spacing = 1.0; UiHub.options_changed.emit(); await settle(0.1)
	check(UiHub.gap(100) > 120, "UI布局 widens gaps")
	UiHub.spacing = sp; UiHub.options_changed.emit()
	# sound kit: every cue resolves in both packs; interactions above produced cues
	for pack in ["aic", "mystic"]:
		UiHub.set_pack(pack)
		var missing: Array = []
		for cue in UiHub._sfx_map.cues.keys():
			if UiHub._stream(cue) == null: missing.append(cue)
		check(missing.is_empty(), "sound pack %s: all %d cues load %s" % [pack, UiHub._sfx_map.cues.size(), str(missing)])
	UiHub.set_pack("aic")
	for need in ["hover", "confirm", "aim", "hit", "advance", "expand", "popup"]:
		check(need in sounds_seen, "sound played during flow: " + need)
	check(AudioServer.get_bus_index("UI") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "audio buses UI / SFX exist")
	# dialog + back
	var d = ui.dialog({"title": "测试", "buttons": [{"id": "a", "text": "确定"}]}); await settle(0.5)
	ui._handle_back(); await settle(0.5)
	check(not is_instance_valid(d) or d.is_queued_for_deletion(), "dialog closes on back")
	# aspect ratios: phone 20:9, tablet 4:3
	for dims in [Vector2i(2400, 1080), Vector2i(1440, 1080)]:
		get_window().size = dims; await settle(0.3)
		ui._reset("battle", {}); await settle(0.4)
		check(ui.logical.y >= 1080 and ui.logical.x >= 1920, "aspect %dx%d keeps full design canvas" % [dims.x, dims.y])
		await shot("aspect-battle-%dx%d" % [dims.x, dims.y])
		ui._reset("story", {"chapter": "ch1"}); await settle(0.4)
		await shot("aspect-story-%dx%d" % [dims.x, dims.y])
	print("CHECKS passed=%d failed=%d" % [passed.size(), failed.size()])
	for f in failed: print("FAILED: ", f)
	var report := {"passed": passed, "failed": failed, "requests_seen": requests}
	var fa := FileAccess.open(OUT + "checks.json", FileAccess.WRITE); fa.store_string(JSON.stringify(report, "  ")); fa.close()
	get_tree().quit()
