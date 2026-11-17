extends SceneTree
## Mystic UI pass checks (2026-11-14). Run:
##   Godot --headless --path F:/sigil-circuit/rolecard-rpg --script res://tools/check_mystic_ui.gd -- --ui-review
## 1) every script under scripts/ui compiles; 2) every routed screen builds inside a real UiRoot;
## 3) workshop model: attach / blueprint text / cost; 4) map data loads.

var failures: Array = []
var passes := 0

func ok(cond: bool, label: String) -> void:
	if cond: passes += 1; print("PASS ", label)
	else: failures.append(label); print("FAIL ", label)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var dir := DirAccess.open("res://scripts/ui/screens")
	for f in dir.get_files():
		if f.ends_with(".gd"):
			var s = load("res://scripts/ui/screens/" + f)
			ok(s != null and s.can_instantiate(), "compile " + f)
	for f in ["ui_kit.gd", "ui_plate.gd", "ui_button.gd", "ui_widgets.gd", "ui_backdrop.gd", "ui_root.gd", "ui_overlay.gd", "ui_icon.gd"]:
		var s2 = load("res://scripts/ui/" + f)
		ok(s2 != null, "compile " + f)
	var root_scene: PackedScene = load("res://scenes/ui_root.tscn")
	var ui = root_scene.instantiate()
	get_root().add_child(ui)
	ui.size = Vector2(1920, 1080)
	await process_frame
	# Gate -> Notice -> Opening animation verification
	ok(ui.current_name() == "gate" and not ui.gate_passed, "app starts on password gate screen")
	var gate_scr = ui.current()
	var g_edit: LineEdit = gate_scr.find_child("GatePasswordInput", true, false) if gate_scr else null
	var g_btn: Button = gate_scr.find_child("GateSubmitBtn", true, false) if gate_scr else null
	ok(g_edit != null and g_btn != null, "gate mounts password input and submit button")
	if g_edit: g_edit.text = "wrong_password"
	if g_btn: g_btn.pressed.emit()
	await process_frame
	ok(ui.current_name() == "gate" and not ui.gate_passed, "incorrect password stays blocked on gate")
	ui.go("title")
	await process_frame
	ok(ui.current_name() == "gate", "navigation bypass before gate unlock is rejected")
	if g_edit: g_edit.text = "明星荧荧Hotaru"
	if g_btn: g_btn.pressed.emit()
	await process_frame
	ok(ui.current_name() == "notice" and ui.gate_passed, "exact password 明星荧荧Hotaru unlocks immediately to notice")
	var n_scr = ui.current()
	var n_labels: String = ""
	if n_scr:
		for l in n_scr.find_children("*", "Label", true, false):
			n_labels += l.text + "\n"
	ok("明星荧荧Hotaru" in n_labels and "创世回廊" in n_labels and "kunlun" in n_labels and "严禁" in n_labels and "Crystar" in n_labels and not ("魔搭" in n_labels) and not ("完整版" in n_labels) and not ("非参赛" in n_labels), "notice declares clean release by 明星荧荧Hotaru, 创世回廊/kunlun preset & music anti-redistribution without boilerplate")
	var n_btn: Button = n_scr.find_child("NoticeConfirm", true, false) if n_scr else null
	if n_btn: n_btn.pressed.emit()
	await process_frame
	ok(ui.current_name() == "prologue" and ui.notice_acknowledged, "confirming notice goes directly to opening animation")
	if ui.current() and ui.current().get("phase") != null:
		ok(String(ui.current().get("phase")) == "intro", "opening screen enters PV intro animation immediately after notice")
	var op_skip: Button = ui.current().find_child("Skip", true, false) if ui.current() else null
	ok(op_skip != null and not op_skip.visible, "opening Skip button stays hidden before user clicks screen")
	if ui.current():
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = Vector2(960, 540)
		ui.current()._gui_input(ev)
		await process_frame
	ok(op_skip != null and op_skip.visible and ui.current_name() == "prologue", "clicking opening screen reveals Skip button without skipping immediately")
	var prev_rm: bool = get_root().get_node("UiHub").reduced_motion
	get_root().get_node("UiHub").reduced_motion = true
	if op_skip: op_skip.pressed.emit()
	await process_frame
	ok(ui.current_name() == "title", "clicking revealed Skip button finishes opening animation to title")
	get_root().get_node("UiHub").reduced_motion = prev_rm
	var screens: Array = ui.SCREENS.keys()
	screens.append("home")
	for name in screens:
		if name in ["gate", "notice"]: continue
		ui.busy = false
		ui._reset(name, {})
		await process_frame
		await process_frame
		var cur = ui.current()
		ok(cur != null and cur.get_child_count() > 0, "build " + name)
	# workshop model
	ui._reset("workshop", {})
	await process_frame
	var ws = ui.current()
	ws.draft = {"name": "破阵之印", "carrier": "长剑剑脊", "effect": "见血就 亮起来", "parts": []}
	ws.add_part("core.release", Vector2(590, 330), false)
	var core_id: String = ws.draft.parts[0].id
	var port_pos: Vector2 = ws.world_port(ws.worlds()[core_id], ws.defp("core.release"), "s1")
	ws.add_part("outer.beam", port_pos, true)
	ws.add_part("micro.overload", ws.world_port(ws.worlds()[ws.draft.parts[1].id], ws.defp("outer.beam"), "exit"), true)
	await process_frame
	ok(ws.draft.parts[1].parent == core_id and ws.draft.parts[1].slot == "s1", "workshop snap to core port")
	ok(ws.draft.parts[2].parent == ws.draft.parts[1].id, "workshop chain outer -> micro")
	var bp: Dictionary = ws._describe()
	print(bp.text)
	ok("核纹·输出【释雷】（接口2已启用）×1" in bp.text, "blueprint core line")
	ok("外纹·输出【导束】（正位，接口2-①）×1" in bp.text, "blueprint outer branch")
	ok("缀纹·输出【过载】（接口2-②）×1" in bp.text, "blueprint micro branch")
	ok("【耗用】3" in bp.text, "cost = 3+2+1 - sync 3")
	ok("玩家编写效果：见血就亮起来" in bp.text, "effect CJK space collapse")
	var lines = load("res://scripts/ui/screens/map_screen.gd").MapLines
	ok(JSON.parse_string(FileAccess.get_file_as_string("res://data/map/world_lines.json")).layers.coast.size() > 50, "map vectors load")
	ok(ResourceLoader.exists("res://assets/ui/mystic/title_logo_mask.png"), "title wordmark asset")
	ok(ResourceLoader.exists("res://assets/ui/mystic/title_falling_girl.png") and ResourceLoader.exists("res://assets/ui/mystic/title_cradle_halo.png"), "title falling girl and halo assets imported")
	ok(ResourceLoader.exists("res://assets/ui/mystic/title_logo_text_mask.png") and ResourceLoader.exists("res://assets/ui/mystic/title_logo_star_mask.png"), "title split text/star masks imported")
	ok(ResourceLoader.exists("res://assets/audio/ui/mystic/hover.ogg"), "mystic sound pack imported")
	var D = load("res://scripts/ui/ui_data.gd")
	var hub = get_root().get_node("UiHub")
	ok(ResourceLoader.exists("res://assets/audio/ui/aic/hover.ogg"), "aic sound pack imported")
	ok(hub.sfx_pack == "aic", "default sfx pack is aic")
	var sound_spec: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/ui_sounds.json"))
	var cues: Dictionary = sound_spec.get("cues", {}) if sound_spec is Dictionary else {}
	var missing_aic: Array[String] = []
	for cue_name in cues.keys():
		var c := str(cue_name)
		# room_* cues (2026-11-17) use one fixed "file" for every pack instead of aic/<cue>.ogg
		var fixed := str(cues[cue_name].get("file", "")) if cues[cue_name] is Dictionary else ""
		var want := fixed if fixed != "" else "res://assets/audio/ui/aic/%s.ogg" % c
		if not ResourceLoader.exists(want) or hub._stream(c) == null:
			missing_aic.append(c)
	ok(cues.size() >= 78 and missing_aic.is_empty(), "all %d aic cues imported and resolved (missing: %s)" % [cues.size(), str(missing_aic)])
	for c in ["theme_day", "theme_night", "hover_soft", "hover_card", "chip", "ghost", "icon_btn", "toggle_on", "toggle_off", "map_open", "bag_open", "char_open", "music_open", "music_pick", "attach", "page"]:
		ok(hub._stream(c) != null, "aic cue resolves: " + c)
	ok(hub.music_manifest.get("title_track", "") == "Main Theme", "original card title_track is Main Theme")
	var all_tracks: Array = hub.music_manifest.get("tracks", [])
	var orig_count := 0
	var custom_count := 0
	var missing_bgm := 0
	for tr in all_tracks:
		if String(tr.get("id", "")).begins_with("orig-"): orig_count += 1
		else: custom_count += 1
		if not ResourceLoader.exists(String(tr.get("res", ""))): missing_bgm += 1
	ok(orig_count == 14 and custom_count == 37 and missing_bgm == 0, "all 14 original + 37 custom BGM tracks registered and imported (missing: %d)" % missing_bgm)
	ok(ResourceLoader.exists("res://assets/audio/bgm/original/qm0aff.ogg") and ResourceLoader.exists("res://assets/audio/bgm/custom/crystar.ogg"), "original Main Theme and reserved Crystar ogg imported")
	var ws_act: Array = hub.music_manifest.get("workshop_activation", [])
	var ws_ok := ws_act.size() == 4 and ws_act.all(func(w): return ResourceLoader.exists(String(w.get("res", ""))))
	ok(ws_ok, "all 4 trimmed workshop activation ogg tracks registered and imported")
	ok(String(hub.music_spec("Main Theme").get("res", "")).begins_with("res://assets/audio/bgm/original/"), "Main Theme resolves to original card BGM")
	ok(String(hub.music_spec("Hakushin's Lullaby").get("title", "")) == "神狐的祝福" and String(hub.music_spec("Ｌ").get("title", "")) == "L" and String(hub.music_spec("Old City Market").get("id", "")) == "cust-loc03-b", "custom BGM aliases & Mili Old City Market resolve cleanly")
	ok(String(hub.music_spec_for_location("塞蕾特公国·尼德霍格区").get("title", "")) == "Old City ~ Respite" and String(hub.music_spec_for_location("龙渊帝国·紫宸宫").get("title", "")) == "北国的宝库", "location BGM fallback resolves canon regions")
	for r in ["operations", "party", "battle", "result", "records"]:
		ok(not ui.SCREENS.has(r), "battle route removed: " + r)
	ok(D.edition() == "full", "full edition active")
	ok(D.content().get("origins", []).size() == 8, "full 8 origins loaded")
	ok(D.cast().size() == 21 and D.npcs().size() == 8, "full 21 cast + 8 npcs loaded")
	ok(D.content().get("archive", {}).get("events", []).size() == 25, "full 25 archive events loaded")
	ok(D.worldbook().get("entries", []).size() >= 130, "full worldbook entries loaded")
	var all_ids: Array = D.roster()
	ok(all_ids.size() == 29, "roster has all 29 characters (21 cast + 8 npcs)")
	var missing_art := 0
	for cid in all_ids:
		if D.art_path(cid, "daily", "neutral") == "" or D.avatar_path(cid) == "" or not ResourceLoader.exists("res://assets/ui/portraits/%s.webp" % cid):
			missing_art += 1
	ok(missing_art == 0, "all 29 characters have daily portrait, avatar, and card webp")
	ok(D.art_path("rin", "liberate", "confident").ends_with("rin/liberate/confident.webp"), "rin liberate confident resolved")
	ok(D.art_path("jian", "liberate_side", "smile").ends_with("jian/liberate_side/smile.webp"), "jian liberate_side resolved")
	ok(D.art_path("alanya", "daily_side_a", "bashful").ends_with("alanya/daily_side_a/bashful.webp"), "alanya daily_side_a resolved")
	ok(D.art_path("xiaoai", "daily_front_b", "star-eyes").ends_with("xiaoai/daily_front_b/star-eyes.webp"), "xiaoai daily_front_b resolved")
	ok(D.art_path("larentia", "nude", "neutral").ends_with("larentia/nude/neutral.webp"), "larentia nude resolved")
	ok(D.art_path("lufa", "casual_b", "speaking").ends_with("lufa/casual_b/speaking.webp"), "lufa casual_b resolved")
	ok(ResourceLoader.exists("res://assets/emotions/confident.png"), "confident emotion asset imported")
	ui.busy = false
	var game = get_root().get_node("Game")
	# Unlocked-only gate check BEFORE any story starts
	ui._reset("characters", {})
	await process_frame
	ok(ui.current() != null and ui.current()._group_ids().is_empty() and ui.current().find_child("CharactersLockedPanel", true, false) != null, "characters screen locks out unmet cast & NPCs before story start")
	var dup_back: Array = ui.current().find_children("*", "Button", true, false).filter(func(b): return "caption" in b and String(b.get("caption")) == "返回")
	ok(dup_back.is_empty(), "characters screen removed duplicate bottom-right 返回 button")
	ui.busy = false
	ui._reset("characters", {"id": "edgar"})
	await process_frame
	ok(ui.current() != null and ui.current().find_child("CharactersLockedPanel", true, false) != null and ui.current().find_child("Art", true, false) == null, "locked NPC profile/art cannot be viewed before encounter")
	ui.busy = false
	ui._reset("archive", {})
	await process_frame
	ok(ui.current() != null and ui.current().find_child("ArchiveEmptyPanel", true, false) != null, "archive 资料库 hides unmet cast before encounter")

	# Unlock rin & edgar temporarily via DB to test unlocked roster, dual galleries & NPC poses
	game.db_update_char_memo("rin", {"met": true, "affection": 50, "lewdness": 40})
	game.db_update_char_memo("edgar", {"met": true})
	ui.busy = false
	ui._reset("characters", {"id": "rin"})
	await process_frame
	var cs = ui.current()
	ok(cs != null and cs.find_child("Outfit_daily", true, false) != null and cs.find_child("Outfit_liberate", true, false) != null and cs.find_child("Pose_daily", true, false) != null, "characters screen mounts unlocked rin outfits and poses")
	var gtab_aff: Button = cs.find_child("GalleryTab_affection", true, false) if cs else null
	var gtab_ero: Button = cs.find_child("GalleryTab_erotic", true, false) if cs else null
	ok(gtab_aff != null and "4/8" in gtab_aff.caption and gtab_ero != null and "4/10" in gtab_ero.caption, "characters dual gallery counts unlock threshold 25/50/75/100 (4/8) & 20/40/60/80/100 (4/10)")
	var slot_aff_1: Button = cs.find_child("GallerySlot_affection_1", true, false)
	ok(slot_aff_1 != null, "characters gallery renders unlocked slot #1 thumbnail")
	if slot_aff_1:
		slot_aff_1.pressed.emit()
		await process_frame
	ok(cs.find_child("CharGalleryZoom", true, false) != null and cs.on_back() and cs.find_child("CharGalleryZoom", true, false) == null, "clicking unlocked character gallery opens zoom viewer and Back closes cleanly")
	if gtab_ero:
		gtab_ero.pressed.emit()
		await process_frame
	ok(ui.current().find_child("GallerySlot_erotic_1", true, false) != null and ui.current().find_child("GallerySlot_erotic_4", true, false) != null, "switching to 色情插图 renders unlocked slots for 色情值 40")
	ui.busy = false
	ui._reset("characters", {"id": "edgar"})
	await process_frame
	ok(ui.current() != null and ui.current().find_child("Pose_daily_front_b", true, false) != null and ui.current().find_child("GalleryTab_affection", true, false) == null, "unlocked NPC edgar mounts poses cleanly without cast gallery")
	ui.busy = false
	ui._reset("characters", {})
	await process_frame
	ok(ui.current() != null and String(ui.current().tab_group) == "cast" and ui.current()._group_ids() == ["rin"], "characters 角色组 shows only unlocked cast and excludes NPCs")
	var npc_tab_btn: Button = ui.current().find_child("CharGroupNpc", true, false)
	ok(npc_tab_btn != null, "characters screen mounts dedicated 重要 NPC tab")
	if npc_tab_btn:
		npc_tab_btn.pressed.emit()
		await process_frame
	ok(ui.current() != null and String(ui.current().tab_group) == "npcs" and ui.current()._group_ids() == ["edgar"], "NPC 板块 displays only unlocked NPCs")
	ui.busy = false
	ui._reset("archive", {})
	await process_frame
	ok(ui.current() != null and ui.current().find_child("Group_npc", true, false) != null and ui.current()._items(load("res://scripts/ui/ui_data.gd").content().library).size() == 1, "archive 资料库 filters 角色 strictly to unlocked cast")
	game.backend.gdb.reset_all()
	game.backend._push_db()
	ui.busy = false
	ui._reset("settings", {"tab": "worldbook"})
	await process_frame
	ok(ui.current() != null and ui.current().tab == "worldbook", "build settings worldbook tab")
	# new game flow: title -> connect -> origin -> create -> loading -> story -> home
	hub.reduced_motion = true
	ui.busy = false
	game.connection["has_key"] = false
	ui._reset("title", {"phase": "menu"})
	await process_frame
	var t_scr = ui.current()
	var t_stage = t_scr.find_child("TitleStage", true, false) if t_scr else null
	var t_wm = t_scr.find_child("TitleWordmark", true, false) if t_scr else null
	ok(t_stage != null and t_stage.girl_tex != null and t_stage.halo_tex != null, "title stage loads falling girl & halo textures")
	ok(t_wm != null and t_stage.wordmark_mat != null, "title wordmark mounts stroke-star shader material")
	if t_stage:
		t_stage._sync_intro_stages(0.55)
		ok(t_stage.text_progress > 0.7 and t_stage.star_progress == 0.0, "title writes text strokes before star emerges")
		t_stage._sync_intro_stages(0.80)
		ok(t_stage.text_progress == 1.0 and t_stage.star_progress > 0.0 and t_stage.star_progress < 1.0, "title cross-star emerges gradually after text")
		t_stage._sync_intro_stages(1.0)
		ok(t_stage.text_progress == 1.0 and t_stage.star_progress == 1.0, "title completes text then cross-star")
	ui.current()._start_new()
	await process_frame
	ok(ui.current_name() == "connect", "flow title -> connect")
	var skip_btn: Button = ui.current().find_child("SkipDemo", true, false)
	ok(skip_btn != null, "connect has SkipDemo button")
	if skip_btn: skip_btn.pressed.emit()
	await process_frame
	ok(ui.current_name() == "origin", "flow connect -> origin")
	ui.current()._confirm()
	await process_frame
	ok(ui.current_name() == "create", "flow origin -> create")
	ui.current()._commit()
	await process_frame
	ok(ui.current_name() == "loading", "flow create -> loading")
	var waited := 0.0
	while ui.current_name() == "loading" and waited < 2.5:
		await create_timer(0.1).timeout
		waited += 0.1
	await process_frame
	ok(ui.current_name() == "story", "flow loading -> story")
	ok(hub.music_current == "誠に遺憾ながら、知り合い", "sereth origin story starts on central academy BGM")
	ui._handle_back()
	await process_frame
	ok(ui.current_name() == "home", "flow story Esc -> home")
	ok(hub.music_current == "白昼天晴" or hub.music_current == "温柔夜色", "home screen switches to day/night home BGM")
	hub.set_night(false, false)
	await process_frame
	ok(hub.music_current == "白昼天晴", "home day mode plays 白昼天晴")
	hub.set_night(true, false)
	await process_frame
	ok(hub.music_current == "温柔夜色", "home night mode switches to 温柔夜色")
	hub.set_night(false, false)
	await process_frame
	ui.busy = false
	ui.go("opening", {"next": "title", "replay": true}, "none")
	await process_frame
	var op_scr = ui.current()
	ok(ui.current_name() == "opening" and hub.music_current == "", "opening screen releases UiHub BGM (PV plays its own Crystar)")
	ok(op_scr.pv_ok and op_scr.video != null and op_scr.video.stream != null and op_scr.music != null and op_scr.music.stream != null and op_scr.music.bus == "Music", "opening PV video + non-looping Crystar player built")
	ok(op_scr.music.stream.loop == false and op_scr.get_node_or_null("PvFx") == null, "opening PV music does not loop and has no glitch/snow overlay")
	ui.busy = false
	ui.go("workshop", {}, "none", "replace")
	await process_frame
	ok(ui.current_name() == "workshop" and hub.music_current == "人工梦游", "workshop screen switches to 人工梦游 BGM")
	hub.start_workshop_activation()
	ok(hub._ws_click_player != null and hub._ws_loop_player != null and hub._music_ducked, "workshop activation triggers new audio sequence & ducks BGM")
	hub.finish_workshop_activation()
	hub.stop_workshop_activation(true)
	ok(not hub._music_ducked, "workshop activation stop restores BGM level")
	ui._handle_back()
	await process_frame
	ok(ui.current_name() == "home", "workshop Esc -> home")
	ok(ui.current().find_child("MusicPlayerBtn", true, false) != null, "home has MusicPlayerBtn")
	hub.select_music("luminous")
	ok(hub.music_override == "luminous" and hub.music_current == "luminous" and not hub.music_disabled, "select_music plays requested track")
	hub.set_music_disabled(true)
	hub.play_music("Main Theme")
	ok(hub.music_disabled and hub.music_current == "", "set_music_disabled blocks play_music")
	hub.set_music_disabled(false)
	ok(not hub.music_disabled and hub.music_current == "luminous", "re-enabling music restores selected track")
	hub.clear_music_override()
	ok(hub.music_override == "" and hub.music_current == "白昼天晴", "clear_music_override restores active screen/story BGM")
	var mp = ui.open_music_player()
	await process_frame
	ok(mp != null and mp.find_child("Track_0", true, false) != null and mp.find_child("Track_50", true, false) != null and mp.find_child("TrackScroll", true, false) != null, "music player opens with scrollable all 51 tracks")
	ok(mp != null and mp.find_child("MusicCat_world", true, false) != null and mp.find_child("MusicCat_story", true, false) != null and mp.find_child("MusicCat_original", true, false) != null, "music player mounts category filter tabs")
	ok(mp != null and mp.find_child("ShutoffBtn", true, false) != null and mp.find_child("PlayPauseBtn", true, false) != null and mp.find_child("SeekSlider", true, false) != null and mp.find_child("VolumeSlider", true, false) != null and mp.find_child("FollowVarBtn", true, false) != null, "music player controls mounted")
	ui._handle_back()
	await process_frame
	ok(ui.current_name() == "home", "music player back preserves home screen")

	# ---------- Database + Hotaru V8 Protocol + Isolated Bridge Chat checks ----------
	ok(FileAccess.file_exists("res://data/hotaru_preset_v1.json"), "bundled Hotaru V8 preset exists")
	ok(game.presets.size() >= 1 and "Hotaru" in String(game.presets[0].get("name", "")) and bool(game.presets[0].get("active", false)), "Hotaru preset active in Game.presets")

	var RP = load("res://scripts/game/reply_parser.gd")
	var sample_v8 := "<在场>凛零</在场>\n<pose>\n人物: 凛零\n姿势: 低头喝咖啡\n状态: 常态\n</pose>\n<content>\n凛零轻声道好。\n</content>\n<BTS>这段幕后花絮不该进主舞台</BTS>\n<sumUp>\n时间: 1015年2月1日 08:30\n地点: 塞蕾特公国·中央学院\n角色: 凛零、主角\n可见: 在场私密\n何事: 两人在钟楼旧回廊约定暗中查探魔导异常\n线索: 铁栅门上的古刻印记\n变动: 凛零警惕略微下降\n</sumUp>\n<choices>\n1. 【试探】：问问咖啡合不合胃口\n</choices>"
	var vp: Dictionary = RP.parse(sample_v8, "测试旅人")
	ok(vp.beats.size() == 1 and "凛零轻声道好" in String(vp.beats[0].text), "ReplyParser unwraps <content> and keeps clean beat")
	ok(not ("sumUp" in String(vp.beats[0].text)) and not ("幕后花絮" in String(vp.beats[0].text)), "ReplyParser strips <sumUp> and <BTS> from beats")
	ok(vp.options == ["【试探】：问问咖啡合不合胃口"], "ReplyParser merges <choices> into options")
	ok(String(vp.sum_up.get("time", "")) == "1015年2月1日 08:30" and String(vp.sum_up.get("visibility", "")) == "present_only", "ReplyParser parses <sumUp> time & visibility")
	ok("rin" == load("res://scripts/ui/ui_data.gd").id_of(String(vp.sum_up.get("role_names", [""])[0])), "ReplyParser extracts <sumUp> participant names")
	ok(String(vp.pose.get("character", "")) == "凛零", "ReplyParser extracts <pose>")

	# Enable offline deterministic generation ONLY inside this automated fixture
	game.backend.test_replies_enabled = true
	game.new_game({"name": "测试旅人", "race": "人族", "appearance": "", "bio": ""}, "sereth")
	await process_frame
	game.send_action("去钟楼旧回廊看看", "free")
	var w_gen := 0.0
	while bool(game.generation.get("busy", false)) and w_gen < 3.0:
		await create_timer(0.1).timeout
		w_gen += 0.1
	await process_frame
	ok(not bool(game.generation.get("busy", false)) and game.db_summaries().size() >= 1, "main story reply ingests <sumUp> into Game.db")
	ok(int(game.recap.get("summary_count", 0)) >= 1, "recap counts <sumUp> entries cleanly")

	# Verify isolated context assembly: present rin vs absent merlin + full character setting & 1-5 spoken msg lock
	var ctx_rin: Dictionary = game.preview_bridge_context("rin", "钟楼旧回廊的印记")
	var ctx_merlin: Dictionary = game.preview_bridge_context("merlin", "钟楼旧回廊的印记")
	ok(not bool(ctx_rin.get("main_chat_history_sent", true)) and not bool(ctx_merlin.get("main_chat_history_sent", true)), "bridge chat never sends full main chatHistory")
	ok(bool(ctx_rin.get("persona_sheet_included", false)) and "性格调色盘" in String(ctx_rin.get("assembled_prompt_preview", "")) and "1～5 条" in String(ctx_rin.get("assembled_prompt_preview", "")), "bridge chat injects full character setting & 1-5 spoken-line lock")
	var bridge_sys := String(game.backend._preset_system_prompt(true, "凛零"))
	ok("凛零" in bridge_sys and "<msg>" in bridge_sys and not ("{{getvar::" in bridge_sys) and not ("1500～2400 字" in bridge_sys), "bridge preset system prompt resolves macros cleanly without main-story length leak")
	var bp_multi: Dictionary = RP.bridge_plain("<content>\n<msg>第一句，今天咖啡豆快用完了。</msg>\n<msg>（歪头思考）</msg>\n<msg>第二句，你要顺路带一包回来吗？</msg>\n</content><dbNote>\n态度: 期待回复\n记忆: 无\n</dbNote>", "测试旅人", "凛零")
	ok(bp_multi.get("messages", []).size() == 2 and "今天咖啡豆" in String(bp_multi.messages[0]), "ReplyParser.bridge_plain parses 1-5 <msg> bubbles and strips stage directions")
	ok(ctx_rin.get("visible_summaries", []).size() >= 1, "present character rin sees witnessed <sumUp>")
	ok(int(ctx_merlin.get("isolated_private_summaries_count", 0)) >= 1 and ctx_merlin.get("visible_summaries", []).size() < ctx_rin.get("visible_summaries", []).size(), "absent character merlin isolates present_only <sumUp>")
	ok(ctx_merlin.get("worldbook_filtered_secrets", []).size() >= 1, "high-secret worldbook lore gated unless unlocked")

	# Verify talk screen + character.chat multi-bubble persistence & <dbNote> write-back
	ui.busy = false
	ui._reset("talk", {"id": "rin"})
	await process_frame
	hub.request("character.chat", {"character": "rin", "text": "刚才的印记你记下了吗？"})
	await process_frame
	var rin_blog: Dictionary = game.db_bridge_log("rin")
	var rin_msgs: Array = rin_blog.get("messages", [])
	var assistant_cnt := 0
	for bm in rin_msgs:
		if String(bm.get("role", "")) == "assistant": assistant_cnt += 1
	ok(rin_msgs.size() >= 2 and rin_msgs.size() <= 6 and assistant_cnt >= 1 and assistant_cnt <= 5, "bridge chat persists user turn + 1-5 spoken bubbles in Game.db")
	ok(String(game.db_char_state("rin").get("attitude_memo", "")) != "", "<dbNote> attitude updates character_states")
	ok(game.db_char_facts("rin").any(func(f): return String(f.get("fact_type", "")) == "bridge_memory"), "<dbNote> memory writes bridge_memory fact")

	# Verify manual fact add & rewind idempotence
	game.db_add_fact("merlin", "测试梅林私人补充记忆", "manual")
	ok(game.db_char_facts("merlin").size() >= 1, "manual character fact stored")
	game.rewind_to(0)
	await process_frame
	ok(game.db_summaries().is_empty(), "rewind_to(0) cleanly rolls back main-story <sumUp>")
	ok(game.db_bridge_log("rin").get("messages", []).size() == rin_msgs.size() and game.db_char_facts("merlin").size() >= 1, "rewind preserves persistent bridge_dialogues & manual facts")

	# Verify full character stats (lewdness, form, fetishes) + swapped affection/lewdness icons
	var rin_st: Dictionary = game.db_char_state("rin")
	ok(rin_st.has("lewdness") and rin_st.has("fetishes") and rin_st.has("form"), "Game.db character_states tracks lewdness, fetishes & form")
	ui.busy = false
	ui._reset("home", {})
	await process_frame
	var card_node: Node = ui.current().find_child("CharacterCard", true, false)
	var has_swapped_icons := false
	var IconCls = load("res://scripts/ui/ui_icon.gd")
	if card_node != null:
		var found_sparkle := false
		var found_heart := false
		for ic in card_node.get_children():
			if ic.get_script() == IconCls:
				var ctrl: Control = ic
				var ic_name := str(ctrl.get("icon"))
				if ic_name == "sparkle" and ctrl.position.y < 100.0: found_sparkle = true
				elif ic_name == "heart" and ctrl.position.y > 100.0: found_heart = true
		has_swapped_icons = found_sparkle and found_heart
	ok(has_swapped_icons, "home character card swapped icons (affection=sparkle, lewdness=heart)")
	ok(ui.current().find_child("Lewdness", true, false) != null and ui.current().find_child("Affection", true, false) != null, "home character card mounts both Affection & Lewdness bars")
	# Check unlocked-only showcase & talk rule: sereth unlocks only rin + merlin; longyuan unlocks 0 characters
	ok(game.unlocked_ids(true) == ["rin", "merlin"], "sereth origin unlocks strictly rin & merlin")
	var story_api_msgs: Array = game.backend._build_story_api_messages()
	var story_sys := String(story_api_msgs[0].get("content", "")) if not story_api_msgs.is_empty() else ""
	ok("[mvu_update]" in story_sys and "角色组" in story_sys and "对话格式规则" in story_sys and "VN_VIEWPORT_NPC_SILHOUETTE_PROTOCOL" in story_sys, "main story system prompt injects live stat_data, MVU update specs, worldbook & NPC silhouette VN rule")
	var DataCls = load("res://scripts/ui/ui_data.gd")
	var sil_ok := true
	for sk in ["sil_child", "sil_woman", "sil_man", "sil_elder", "sil_monster"]:
		if DataCls.art_path(sk, "daily", "neutral") == "": sil_ok = false
	ok(sil_ok, "all 5 default NPC silhouette assets (child/woman/man/elder/monster) resolve cleanly")
	var sample_npc := "<在场>凛零(日常), 老人:守门大爷, 魔物:暗巷灰狼</在场>\n<content>\n【老人:守门大爷】：“前面修路，请出示证件。”\n【守门大爷】：“没有公国批条谁都不能过去。”\n【女人|酒馆老板娘】：“顺便帮我带一箱麦芽糖呗？”\n</content>"
	var parsed_npc: Dictionary = RP.parse(sample_npc, "测试旅人")
	ok(parsed_npc.cast.size() == 3 and String(parsed_npc.cast[1].sil) == "sil_elder" and String(parsed_npc.cast[1].name) == "守门大爷" and String(parsed_npc.cast[2].sil) == "sil_monster", "ReplyParser parses <在场> NPC identity categories into silhouettes and clean NPC names")
	ok(parsed_npc.beats.size() == 3 and String(parsed_npc.beats[0].speaker) == "守门大爷" and String(parsed_npc.beats[0].sil) == "sil_elder" and String(parsed_npc.beats[1].sil) == "sil_elder" and String(parsed_npc.beats[2].speaker) == "酒馆老板娘" and String(parsed_npc.beats[2].sil) == "sil_woman", "ReplyParser extracts NPC silhouette from 身份:名 and remembers <在场> mapping across lines")
	# Mount story_screen with an assistant floor containing a silhouette NPC to verify live Portrait + nameplate rendering
	game.backend.chat.append(game.backend._msg("assistant", "艾瑟拉", sample_npc))
	game.backend._push_messages()
	game.backend._sync_and_push_state()
	ui.busy = false
	ui._reset("story", {})
	await process_frame
	var st_scr = ui.current()
	var sil_stage_node: Node = st_scr.find_child("Cast_sil_elder_守门大爷", true, false) if st_scr else null
	ok(sil_stage_node != null and sil_stage_node.texture != null and st_scr.name_label.text == "守门大爷", "story_screen mounts silhouette portrait for non-official NPC while displaying clean NPC name on nameplate")
	ok(game.unlocked_ids(true) == ["rin", "merlin"], "non-official NPC silhouettes never pollute official unlocked character roster")
	game.new_game({"name": "无同伴测试", "race": "人族", "appearance": "", "bio": ""}, "longyuan")
	await process_frame
	ok(game.unlocked_ids(true).is_empty(), "longyuan origin starts with 0 unlocked characters")
	ui.busy = false
	ui._reset("home", {})
	await process_frame
	ok(ui.current().find_child("Showcase", true, false) == null and ui.current().find_child("EmptyShowcaseGoStory", true, false) != null, "home screen shows no showcase portrait when 0 characters unlocked")
	ui.busy = false
	ui._reset("talk", {})
	await process_frame
	ok(ui.current().find_child("TalkLockedNotice", true, false) != null, "talk screen locks out when 0 characters unlocked")
	# Switch back to sereth so subsequent tests stay on rin
	game.new_game({"name": "测试旅人", "race": "人族", "appearance": "", "bio": ""}, "sereth")
	await process_frame
	ui.busy = false
	ui._reset("characters", {"id": "rin"})
	await process_frame
	var char_has_lewd := false
	for child in ui.current().find_children("*", "Label", true, false):
		if "色情值" in child.text:
			char_has_lewd = true; break
	ok(char_has_lewd, "characters screen displays 色情值 state")

	# Verify database_screen builds cleanly across all 4 tabs
	for dtab in ["characters", "timeline", "world_state", "bridge_preview"]:
		ui.busy = false
		ui._reset("database", {"tab": dtab, "character": "rin"})
		await process_frame
		ok(ui.current_name() == "database" and ui.current() != null and ui.current().get_child_count() > 0, "database screen mounts tab " + dtab)
		if dtab == "bridge_preview":
			var raw_t: Button = ui.current().find_child("ToggleRawPrompt", true, false)
			ok(raw_t != null and ui.current().find_child("BridgePromptPreviewText", true, false) == null, "privacy tab hides developer raw prompt by default")
			if raw_t:
				raw_t.pressed.emit()
				await process_frame
				await process_frame
			var p_lbl = ui.current().find_child("BridgePromptPreviewText", true, false)
			ok(p_lbl != null and "hotaru_opt_bridge_chat" in p_lbl.text, "database privacy tab toggles raw Hotaru prompt preview")

	# Verify comic emotion decals are hidden on story portraits while emotion assets stay preserved on disk
	var WCls = load("res://scripts/ui/ui_widgets.gd")
	var emo_dict: Dictionary = DataCls.portrait_registry().get("emotions", {})
	var emo_assets_ok: bool = emo_dict.size() >= 10
	for ek in emo_dict.keys():
		if not ResourceLoader.exists(String(emo_dict[ek])):
			emo_assets_ok = false
	ok(emo_assets_ok, "all emotion assets under assets/emotions/ remain preserved on disk")

	game.new_game({"name": "插画测试", "race": "人族", "appearance": "", "bio": ""}, "sereth")
	await process_frame
	var PortraitCls = WCls.Portrait
	var had_cg: bool = PortraitCls.registry.has("cg")
	var prev_cg = PortraitCls.registry.get("cg", {}).duplicate(true) if had_cg else {}
	PortraitCls.registry["cg"] = {
		"CHB-TEST-01": {
			"id": "CHB-TEST-01",
			"title": "测试Q版·早安打招呼",
			"category": "group",
			"res": "res://assets/backgrounds/ACA01-day-v1.webp",
		}
	}
	var cg_msg := "<场景>塞蕾特公国·中央学院</场景>\n<在场>凛零(日常), 梅林(日常)</在场>\n<插画>《测试Q版·早安打招呼》</插画>\n【凛零|说话】：“早上好。”\n【梅林|微笑】：“走吧，要迟到了。”"
	game.backend.chat.append(game.backend._msg("assistant", "艾瑟拉", cg_msg))
	game.backend._push_messages()
	game.backend._sync_and_push_state()
	ui.busy = false
	ui._reset("story", {})
	await process_frame
	await process_frame
	var story_cg_scr = ui.current()
	var cast_rin_node: Control = story_cg_scr.find_child("Cast_rin", true, false)
	var cast_merlin_node: Control = story_cg_scr.find_child("Cast_merlin", true, false)
	var cg_layer_node: Control = story_cg_scr.find_child("CgLayer", true, false)
	var cg_art_node: Control = story_cg_scr.find_child("CgArt", true, false)
	var cg_cap_node: Label = story_cg_scr.find_child("CgCaption", true, false)
	var close_cg_btn: Button = story_cg_scr.find_child("CloseCg", true, false)
	var show_cg_btn: Button = story_cg_scr.find_child("ShowCg", true, false)
	var zoom_cg_btn: Button = story_cg_scr.find_child("ZoomCg", true, false)
	var headroom_ok := false
	if cast_merlin_node != null and cast_merlin_node.texture != null:
		var mr: Rect2 = cast_merlin_node.framed_rect(cast_merlin_node.texture)
		headroom_ok = mr.position.y + 0.015 * mr.size.y >= 100.0
	ok(cast_rin_node != null and not cast_rin_node.show_emotion_deco and headroom_ok, "story portraits hide comic emotion stickers and clear the top toolbar headroom")
	ok(cg_layer_node != null and cg_layer_node.visible and cg_art_node != null and cg_art_node.texture != null and cg_cap_node != null and cg_cap_node.text == "测试Q版·早安打招呼", "story_screen renders <插画> showcase with real texture and normalized title match")
	ok(game.is_cg_unlocked("CHB-TEST-01"), "<插画> display unlocks illustration ID in GameDatabase")
	# Advance to beat 1 (merlin speaks) -> rin resets leftover 'speaking' expression to 'neutral' while CG stays inspectable
	story_cg_scr.index = story_cg_scr.reply_start + 1
	story_cg_scr._show_line(story_cg_scr.index, false)
	story_cg_scr._finish_typing()
	await process_frame
	ok(cast_rin_node.expression_id == "neutral", "non-speaking cast resets stale 'speaking' mouth expression back to neutral")
	if close_cg_btn: close_cg_btn.pressed.emit()
	await process_frame
	ok(not cg_layer_node.visible and show_cg_btn != null and show_cg_btn.visible, "dismissing <插画> hides showcase card and reveals 查看插画 restore chip")
	if show_cg_btn: show_cg_btn.pressed.emit()
	await process_frame
	ok(cg_layer_node.visible and show_cg_btn != null and not show_cg_btn.visible, "clicking 查看插画 restores <插画> showcase card")
	if zoom_cg_btn: zoom_cg_btn.pressed.emit()
	await process_frame
	ok(story_cg_scr.find_child("CgZoom", true, false) != null and story_cg_scr.on_back() and story_cg_scr.find_child("CgZoom", true, false) == null, "fullscreen <插画> zoom opens cleanly and Back closes zoom in place")
	# Missing illustration must never display a broken blank box over dialogue
	var miss_msg := "<插画>还没画出来的未知插画</插画>\n【凛零|平静】：“先继续往前走吧。”"
	game.backend.chat.append(game.backend._msg("assistant", "艾瑟拉", miss_msg))
	game.backend._push_messages()
	ui.busy = false
	ui._reset("story", {})
	await process_frame
	story_cg_scr = ui.current()
	cg_layer_node = story_cg_scr.find_child("CgLayer", true, false)
	ok(cg_layer_node != null and not cg_layer_node.visible, "unregistered/unpainted <插画> name safely stays hidden without blank box")
	ui.busy = false
	ui._reset("gallery", {})
	await process_frame
	var gal_scr = ui.current()
	var gal_cat: Array = gal_scr._catalog()
	ok(gal_cat.size() == 1 and bool(gal_cat[0].unlocked) and gal_scr.find_children("*", "Label", true, false).any(func(l): return "测试Q版" in l.text), "gallery_screen displays live registry catalog synced with unlocked DB state")
	gal_scr.open_viewer(0)
	await process_frame
	ok(gal_scr.viewing == 0 and is_instance_valid(gal_scr.viewer), "gallery_screen opens unlocked illustration fullscreen viewer cleanly")
	if had_cg: PortraitCls.registry["cg"] = prev_cg
	else: PortraitCls.registry.erase("cg")

	# ---------- 2026-11-17 Bugfix & Feature Verification Suite ----------
	# 1. BGM routing: home -> secondary screens stays on home day/night BGM (workshop still plays 人工梦游);
	#    story -> secondary screens stays on active story BGM; never leaks track #26 into home branches.
	hub.set_night(false, false)
	ui.busy = false
	ui._reset("home", {})
	await process_frame
	ok(hub.music_current == "白昼天晴", "home day BGM starts as 白昼天晴 before secondary nav")
	ui.go("characters", {}, "none")
	await process_frame
	ok(ui.current_name() == "characters" and hub.music_current == "白昼天晴", "home -> characters keeps home day BGM (no #26 leak)")
	ui.go("settings", {"tab": "display"}, "none")
	await process_frame
	ok(ui.current_name() == "settings" and hub.music_current == "白昼天晴", "home -> characters -> settings keeps home day BGM")
	hub.set_night(true, false)
	await process_frame
	ok(hub.music_current == "温柔夜色", "switching night inside home-origin settings switches to 温柔夜色")
	ui.go("workshop", {}, "none")
	await process_frame
	ok(ui.current_name() == "workshop" and hub.music_current == "人工梦游", "entering workshop switches to 人工梦游 regardless of origin")
	ui.back("none")
	await process_frame
	ok(hub.music_current == "温柔夜色", "leaving workshop restores underlying home BGM")
	hub.set_night(false, false)
	ui._reset("home", {})
	await process_frame

	# Now push story -> secondary screens -> verify story BGM preserved
	game.new_game({"name": "BGM旅人", "race": "人族", "appearance": "", "bio": ""}, "sereth")
	await process_frame
	ui.busy = false
	ui._reset("home", {})
	await process_frame
	ui.go("story", {}, "none")
	await process_frame
	ok(ui.current_name() == "story" and hub.music_current == "誠に遺憾ながら、知り合い", "story entry plays Sereth story BGM")
	ui.go("settings", {"tab": "display"}, "none")
	await process_frame
	ok(hub.music_current == "誠に遺憾ながら、知り合い", "story -> settings preserves story BGM cleanly")
	ui.go("database", {"tab": "characters"}, "none")
	await process_frame
	ok(hub.music_current == "誠に遺憾ながら、知り合い", "story -> settings -> database preserves story BGM cleanly")
	ui.back("none")
	await process_frame

	# 2. 图5: UI 布局 + 文字大小调整生效且返回剧情不丢失背景
	var pre_story: Control = ui.stack[ui.stack.size() - 2].node
	var pre_box_h := 0.0
	if is_instance_valid(pre_story) and pre_story.find_child("DialogBox", true, false) != null:
		pre_box_h = (pre_story.find_child("DialogBox", true, false) as Control).size.y
	hub.set_option("spacing", 0.0)
	hub.set_option("text_scale", 1.1)
	await process_frame
	ui.back("none")
	await process_frame
	var cur_story = ui.current()
	var post_box = cur_story.find_child("DialogBox", true, false) if cur_story else null
	ok(ui.current_name() == "story" and is_equal_approx(cur_story.built_spacing, 0.0) and is_equal_approx(cur_story.built_text_scale, 1.1), "returning to story rebuilds cleanly on BOTH spacing and text_scale changes")
	ok(post_box != null and post_box.size.y < pre_box_h, "UI 布局 compact spacing visibly resizes DialogBox on story return")
	ok(cur_story.bg_path != "" and is_instance_valid(cur_story.scene_slot) and cur_story.scene_slot.texture != null, "returning to story after layout change preserves real scene background texture")
	hub.reset_display()
	await process_frame

	# 3. 图2: 自由输入悬浮大窗 + 手机端竖屏输入模式适配
	cur_story.show_choices(["先观察四周动向"])
	await process_frame
	var ap: Control = cur_story.panel
	ok(ap != null, "story mounts ActionPanel for input tests")
	if ap != null:
		ap.select(ap.rows.size() - 1)
		await process_frame
		ok(is_instance_valid(ap.expand_btn) and is_instance_valid(ap.portrait_btn), "ActionPanel mounts 悬浮窗 & 竖屏输入 buttons")
		ap.open_composer(false)
		await process_frame
		var ov: Control = ui.overlay_layer.find_child("FloatingComposerOverlay", true, false)
		var cte: TextEdit = ov.find_child("ComposerTextEdit", true, false) if ov else null
		ok(ov != null and cte != null and not bool(ov.get_meta("portrait_mode", true)), "floating composer modal mounts cleanly")
		if cte: cte.text = "前往钟楼检查残余刻印"
		var ok_btn: Button = ov.find_child("ComposerConfirmBtn", true, false) if ov else null
		if ok_btn: ok_btn.pressed.emit()
		await process_frame
		ok(ap.free_edit.text == "前往钟楼检查残余刻印" and not ap.confirm.disabled, "confirming floating composer fills FreeInput & readies Send")
		ap.open_composer(true)
		await process_frame
		var pov: Control = ui.overlay_layer.find_child("FloatingComposerOverlay", true, false)
		var pcard: Control = pov.find_child("ComposerCard", true, false) if pov else null
		var pte: TextEdit = pov.find_child("ComposerTextEdit", true, false) if pov else null
		ok(hub.mobile_portrait_input and pcard != null and pcard.size.y > pcard.size.x, "portrait input mode activates vertical orientation state & tall composer frame")
		if pte: pte.text = "竖屏输入后的自定义行动文本"
		var pok: Button = pov.find_child("ComposerConfirmBtn", true, false) if pov else null
		if pok: pok.pressed.emit()
		await process_frame
		ok(not hub.mobile_portrait_input and ap.free_edit.text == "竖屏输入后的自定义行动文本", "confirming portrait composer restores landscape and preserves editable input")

	# 4. 图3: 多套 API 配置切换 + 独立预设管理页面（开关 + 修改正文）
	game.set_connection({"name": "主用 DeepSeek", "format": "openai", "mode": "chat", "url": "https://api.a.example/v1", "model": "deepseek-chat", "as_new": true})
	var pid_a := String(game.connection.get("profile_id", ""))
	game.set_connection({"name": "备用公益站", "format": "claude", "mode": "chat", "url": "https://api.b.example/v1", "model": "claude-3-7-sonnet", "as_new": true})
	var pid_b := String(game.connection.get("profile_id", ""))
	ok(pid_a != "" and pid_b != "" and pid_a != pid_b and game.connection.get("profiles", []).size() >= 2, "multi-API stores distinct named profiles")
	game.select_connection_profile(pid_a)
	await process_frame
	ok(String(game.connection.get("profile_id", "")) == pid_a and String(game.connection.get("model", "")) == "deepseek-chat", "select_connection_profile switches active API cleanly")
	ui.busy = false
	ui._reset("settings", {"tab": "ai"})
	await process_frame
	ok(ui.current().find_child("ApiProfileChip_0", true, false) != null and ui.current().find_child("ManagePresets", true, false) != null, "settings AI tab renders quick API profile switcher & preset manager button")
	game.delete_connection_profile(pid_b)
	game.delete_connection_profile(pid_a)

	ui.go("presets", {}, "none")
	await process_frame
	ok(ui.current_name() == "presets" and ui.current().find_child("PresetToggleBtn", true, false) != null and ui.current().find_child("PresetContentEdit", true, false) != null, "dedicated presets screen mounts toggle and editor controls")
	var base_sys := String(game.backend._preset_system_prompt(false))
	ok("Hotaru" in base_sys or "本预设为" in base_sys, "default preset includes hotaru_meta")
	game.set_preset_entry("hotaru_meta", {"enabled": false, "content": "CUSTOM_META_TOKEN"})
	game.set_preset_entry("hotaru_world_open", {"content": "【自定义世界开篇指令】测试内容"})
	var mod_sys := String(game.backend._preset_system_prompt(false))
	ok(not ("CUSTOM_META_TOKEN" in mod_sys) and "【自定义世界开篇指令】测试内容" in mod_sys, "preset toggles & edited entry content take effect in prompt assembly")
	game.reset_preset_overrides()

	# 5. 图4: 世界书在线编辑修改与还原
	ui.busy = false
	ui._reset("settings", {"tab": "worldbook"})
	await process_frame
	var s_wb = ui.current()
	var edit_wb_btn: Button = s_wb.find_child("EditWorldbookBtn", true, false)
	ok(edit_wb_btn != null, "worldbook viewer mounts 修改 button")
	if edit_wb_btn:
		edit_wb_btn.pressed.emit()
		await process_frame
	var wb_te: TextEdit = ui.current().find_child("WorldbookEditBody", true, false)
	ok(wb_te != null, "clicking 修改 opens WorldbookEditBody text editor")
	var orig_wb_text := wb_te.text if wb_te else ""
	if wb_te:
		wb_te.text = orig_wb_text + "\n# 测试世界书补充规则"
	var save_wb_btn: Button = ui.current().find_child("SaveWorldbookBtn", true, false)
	if save_wb_btn:
		save_wb_btn.pressed.emit()
		await process_frame
		await process_frame
	var found_wb_edit := false
	for e in DataCls.worldbook().get("entries", []):
		if "测试世界书补充规则" in String(e.get("body", "")):
			found_wb_edit = true; break
	ok(found_wb_edit, "saving worldbook entry persists modification cleanly")
	var reset_wb_btn: Button = ui.current().find_child("ResetWorldbookBtn", true, false)
	if reset_wb_btn:
		reset_wb_btn.pressed.emit()
		await process_frame
		await process_frame

	# 6. Top-left PageTitle appears whole directly without per-character visible_ratio pop-in
	hub.reduced_motion = false
	ui.busy = false
	ui._reset("archive", {})
	await process_frame
	var page_title_lbl: Label = ui.current().find_child("PageTitle", true, false) if ui.current() else null
	ok(page_title_lbl != null and is_equal_approx(page_title_lbl.visible_ratio, 1.0), "top-left page title displays whole immediately without glyph-by-glyph pop-in")
	hub.reduced_motion = true

	# 7. Extensions Hub (扩展中心), Creative Workshop & Story Oracle + legacy SillyTavern .jsonl saves
	ui.busy = false
	ui._reset("home", {})
	await process_frame
	var ext_btn: Button = ui.current().find_child("Extensions", true, false) if ui.current() else null
	ok(ext_btn != null and String(ext_btn.caption) == "扩展", "home screen mounts 扩展 button in place of 创意工坊")
	ui.busy = false
	ui._reset("extensions", {})
	await process_frame
	var ext_scr = ui.current()
	ok(ext_scr != null and ext_scr.find_child("ExtCard_creative_workshop", true, false) != null and ext_scr.find_child("ExtCard_story_oracle", true, false) != null and ext_scr.find_child("ExtOpenWorkshopBtn", true, false) != null and ext_scr.find_child("ExtOpenOracleBtn", true, false) != null, "extensions hub mounts both 创意工坊 and 故事神谕 cards cleanly")

	ui.busy = false
	ui._reset("workshop", {})
	await process_frame
	var ws_ent = ui.current()
	ok(ws_ent != null and ws_ent.find_child("SigilCreativeWorkshop", true, false) != null and ws_ent.find_child("SigilUploadWorkshop", true, false) != null, "sigil workshop mounts standalone 创意工坊 & 上传工坊 buttons")

	var ws_hub = hub.workshop()
	var tmp_ws_dir := "user://_check_ws_hub/"
	var tmp_ws_store := "user://_check_ws_store.json"
	var tmp_wb_custom := "user://_check_wb_custom.json"
	ws_hub.base_dir_override = tmp_ws_dir
	ws_hub.workshop_store_override = tmp_ws_store
	DataCls.custom_worldbook_path_override = tmp_wb_custom
	DataCls.reset_custom_worldbook_cache()

	var sample_sigil_pkg := {
		"packageVersion": "1.0.0", "id": "test.sigil-arc", "series": "aethera", "cardScope": "aethera",
		"category": "blueprint", "type": "blueprint", "title": "苍穹星轨阵", "official": false, "downloads": 7, "favs": 3,
		"publisher": {"discordId": "42", "displayName": "测试造物师"},
		"payload": {"extra": {"desc": "召唤高天星轨", "sigilArchive": {
			"format": "academy-sigil-archive", "version": 3,
			"draft": {"name": "苍穹星轨阵", "carrier": "星盘", "effect": "引动星辉", "parts": [{"id": "c1", "partId": "core.release", "parent": "", "slot": "", "plug": "", "rot": 0, "x": 590, "y": 330}]},
			"saved": [{"id": "sig_star_1", "name": "苍穹星轨阵", "carrier": "星盘", "effect": "引动星辉", "parts": [{"id": "c1", "partId": "core.release", "parent": "", "slot": "", "plug": "", "rot": 0, "x": 590, "y": 330}], "cost": 1}],
		}}},
	}
	var sample_char_pkg := {
		"packageVersion": "1.0.0", "id": "test.char-lily", "series": "aethera", "cardScope": "aethera",
		"category": "character", "type": "character", "title": "莉莉DLC", "official": false, "downloads": 12, "favs": 5,
		"publisher": {"discordId": "42", "displayName": "测试造物师"},
		"payload": {"extra": {"roleNames": ["莉莉"], "overview": "  莉莉:\n    简介: 来自工坊的见习占星术士\n    形态:\n      - 日常", "archive": "莉莉擅长观测星象与刻画符印。", "imageDailyUrl": "https://example.com/lily.webp"}},
	}
	var sample_rule_pkg := {
		"packageVersion": "1.0.0", "id": "test.rule-extra", "series": "aethera", "cardScope": "aethera",
		"category": "rule", "type": "rule", "title": "工坊补充法则", "official": true, "downloads": 20, "favs": 8,
		"publisher": {"discordId": "1", "displayName": "官方工坊"},
		"payload": {"extra": {"content": "在艾瑟拉的工坊延伸法则下，星辰共振消耗减半。"}},
	}
	var mock_pkgs := [sample_sigil_pkg, sample_char_pkg, sample_rule_pkg]
	var cloud_dls := []
	ws_hub.mock_transport = func(method: int, path: String, body, auth_tok: String) -> Dictionary:
		if path.begins_with("/api/workshop/packages?cardScope="):
			return {"status": 200, "body": {"packages": mock_pkgs}}
		if path.begins_with("/api/workshop/packages/") and method == HTTPClient.METHOD_GET:
			var req_id := path.trim_prefix("/api/workshop/packages/").uri_decode()
			for mpkg in mock_pkgs:
				if String(mpkg.id) == req_id: return {"status": 200, "body": {"package": mpkg}}
			return {"status": 404, "body": {"errors": ["not found"]}}
		if path == "/api/workshop/me/downloads" and method == HTTPClient.METHOD_POST:
			var pid := String(body.get("packageId", "")) if body is Dictionary else ""
			for mpkg in mock_pkgs:
				if String(mpkg.id) == pid and not (mpkg in cloud_dls): cloud_dls.append(mpkg)
			return {"status": 200, "body": {"ok": true, "added": true}}
		if path == "/api/workshop/me/downloads" and method == HTTPClient.METHOD_GET:
			return {"status": 200, "body": {"ok": true, "downloads": cloud_dls}}
		if path == "/api/workshop/me" and method == HTTPClient.METHOD_GET:
			if auth_tok == "mock_tok_ok":
				return {"status": 200, "body": {"ok": true, "loggedIn": true, "admin": false, "user": {"id": "42", "username": "tester", "displayName": "测试玩家"}}}
			return {"status": 401, "body": {"errors": ["login required"]}}
		if path == "/api/workshop/packages" and method == HTTPClient.METHOD_POST:
			var created: Dictionary = body.duplicate(true) if body is Dictionary else {}
			created["id"] = "42.uploaded-sigil"
			created["revision"] = 1
			mock_pkgs.push_front(created)
			return {"status": 200, "body": {"package": created}}
		return {"status": 200, "body": {"ok": true}}

	ws_hub.refresh_catalog()
	ui.busy = false
	ui._reset("creative_workshop", {"tab": "browse"})
	await process_frame
	var cw_scr = ui.current()
	ok(cw_scr != null and cw_scr.find_child("CwCard_0", true, false) != null and cw_scr.find_child("CwCard_2", true, false) != null, "creative workshop renders aethera cloud catalog cards inside game")
	var dl_btn0: Button = cw_scr.find_child("CwCardDl_0", true, false)
	if dl_btn0: dl_btn0.pressed.emit()
	await process_frame
	ws_hub.download_package(sample_char_pkg)
	ws_hub.download_package(sample_rule_pkg)
	ok(ws_hub.repo_packages().size() == 3, "downloading works from creative workshop populates management panel warehouse cleanly")
	var exp_path: String = ws_hub.export_package_file(sample_sigil_pkg)
	var imp_json_res: Dictionary = ws_hub.import_local_file(exp_path)
	ok(bool(imp_json_res.ok) and int(imp_json_res.added) == 1, "exported web workshop .json package imports cleanly into management panel")

	# Switch to 管理面板 (repo) & run batch import
	cw_scr.tab = "repo"; cw_scr.refresh(false)
	await process_frame
	var sel_all_btn: Button = ui.current().find_child("CwRepoSelectAll", true, false)
	if sel_all_btn: sel_all_btn.pressed.emit()
	await process_frame
	var imp_sel_btn: Button = ui.current().find_child("CwImportSelectedBtn", true, false)
	ok(imp_sel_btn != null and not imp_sel_btn.disabled, "management panel selects downloaded works for batch import")
	if imp_sel_btn: imp_sel_btn.pressed.emit()
	await process_frame
	var saved_store_parsed = JSON.parse_string(FileAccess.get_file_as_string(tmp_ws_store))
	var sigil_saved_ok: bool = saved_store_parsed is Dictionary and saved_store_parsed.get("saved", []).any(func(s): return String(s.get("name", "")) == "苍穹星轨阵")
	ok(sigil_saved_ok, "importing blueprint package merges sigil into user workshop store (苍穹星轨阵)")
	var wb_titles: Array = DataCls.worldbook().get("entries", []).map(func(e): return String(e.get("title", "")))
	ok("DLC/莉莉" in wb_titles and "DLC角色速览" in wb_titles and "DLC/工坊补充法则" in wb_titles, "importing character & rule packages populates worldbook DLC entries")

	var test_gdb = load("res://scripts/game/game_database.gd").new()
	var ctx_pre: String = test_gdb.build_main_story_world_context({"主角组": {"当前地点": "塞蕾特公国·中央学院"}, "角色组": {}}, {"name": "主角"}, "")
	var ctx_with_lily: String = test_gdb.build_main_story_world_context({"主角组": {"当前地点": "塞蕾特公国·中央学院"}, "角色组": {"莉莉": {"好感度": 10}}}, {"name": "主角"}, "")
	var b1 := "DLC角色速览" in ctx_pre
	var b2 := "星辰共振消耗减半" in ctx_pre
	var b3 := not ("<DLC_莉莉>" in ctx_pre)
	var b4 := "<DLC_莉莉>" in ctx_with_lily
	ok(b1 and b2 and b3 and b4, "runtime story context activates imported workshop rule & DLC character when unlocked")

	# Test loopback OAuth socket binding & manual token publish
	var oa_start: Dictionary = ws_hub._start_oauth_loopback()
	ok(bool(oa_start.ok) and int(oa_start.port) > 0, "discord OAuth loopback callback listener binds local 127.0.0.1 port cleanly")
	ws_hub.cancel_login()
	var tok_box := [false]
	ws_hub.set_manual_token("mock_tok_ok", func(ok_f: bool, _e: String): tok_box[0] = ok_f)
	ok(bool(tok_box[0]) and ws_hub.is_logged_in() and ws_hub.display_name() == "测试玩家", "workshop token claim logs into Discord account cleanly")
	var pub_box := [false]
	ws_hub.publish_package({"category": "blueprint", "type": "blueprint", "title": "新星法印", "payload": {"extra": {"desc": "test", "sigilArchive": sample_sigil_pkg.payload.extra.sigilArchive}}}, func(ok_p: bool, _c: Dictionary, _e: String): pub_box[0] = ok_p)
	ok(bool(pub_box[0]), "logged-in player can publish sigil blueprint to aethera creative workshop")

	# Uninstall and verify cleanup
	ws_hub.uninstall_package("test.char-lily")
	ws_hub.uninstall_package("test.sigil-arc")
	ws_hub.uninstall_package("test.rule-extra")
	var wb_titles_after: Array = DataCls.worldbook().get("entries", []).map(func(e): return String(e.get("title", "")))
	ok(not ("DLC/莉莉" in wb_titles_after) and not ("DLC/工坊补充法则" in wb_titles_after), "uninstalling workshop DLC cleanly removes entries from worldbook")

	ws_hub.mock_transport = Callable()
	ws_hub.logout()
	ws_hub.catalog.clear(); ws_hub.local_packs.clear(); ws_hub.installed = {"packages": {}, "dlc_characters": {}}
	ws_hub.base_dir_override = ""; ws_hub.workshop_store_override = ""
	DataCls.custom_worldbook_path_override = ""; DataCls.reset_custom_worldbook_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_ws_store))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_wb_custom))
	for fn in ["account.json", "local_packs.json", "installed.json", "favs.json", "cloud_downloads.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_ws_dir + fn))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(exp_path))

	# 8. Machine-local persistence: password unlock + one-time notice + opening-seen skip straight to title
	ui.queue_free()
	await process_frame
	var tmp_opt := "user://_check_home_opts.cfg"
	var tmp_extra := "user://_check_ui_opts.cfg"
	hub.options_path_override = tmp_opt
	hub.extra_path_override = tmp_extra
	hub.gate_unlock_hash = ""
	hub.notice_seen = false
	hub.opening_seen = false
	hub.review_mode = false
	hub.mark_gate_unlocked("明星荧荧Hotaru")
	hub.mark_opening_seen()
	hub.gate_unlock_hash = ""
	hub.opening_seen = false
	hub.load_options()
	ok(hub.is_gate_unlocked("明星荧荧Hotaru") and not hub.is_gate_unlocked("wrong"), "local gate unlock hash persists via ConfigFile reload and rejects wrong password")
	ok(hub.opening_seen and not hub.notice_seen, "local opening_seen flag persists cleanly while notice_seen stays false before reading")

	# Launch #2: gate unlocked, notice not read yet -> opens notice -> confirming remembers notice_seen and enters title
	var ui2 = root_scene.instantiate()
	get_root().add_child(ui2)
	ui2.size = Vector2(1920, 1080)
	await process_frame
	ok(ui2.current_name() == "notice" and ui2.gate_passed, "launch with unread notice enters notice screen")
	var n2_btn: Button = ui2.current().find_child("NoticeConfirm", true, false) if ui2.current() else null
	if n2_btn: n2_btn.pressed.emit()
	await process_frame
	ok(ui2.current_name() == "title" and ui2.notice_acknowledged and hub.notice_seen, "confirming notice once marks notice_seen and enters title main UI")
	ui2.queue_free()
	await process_frame

	# Launch #3: gate + notice + opening all seen -> enters main UI (title) directly without repeating notice or PV
	var ui3 = root_scene.instantiate()
	get_root().add_child(ui3)
	ui3.size = Vector2(1920, 1080)
	await process_frame
	ok(ui3.current_name() == "title" and ui3.notice_acknowledged and ui3.gate_passed, "subsequent launch after reading notice goes directly to main title UI")
	hub.review_mode = true

	# 9. Story Oracle adaptation (red-circle button, floating window, mobile portrait input, Data Channel, remote update pull, SillyTavern .jsonl save import)
	game.backend.test_replies_enabled = true
	game.new_game({"name": "测试者", "race": "人类", "origin": "sereth"}, "sereth")
	game.send_action("与凛零打招呼", "free")
	await create_timer(1.6).timeout
	ui3.busy = false
	ui3._reset("story", {})
	await process_frame
	var oracle_entry: Button = ui3.current().find_child("StoryOracleBtn", true, false)
	ok(oracle_entry != null and oracle_entry.position.x < 120.0 and oracle_entry.position.y > 380.0 and oracle_entry.position.y < 540.0, "story screen mounts 故事神谕 trigger button inside left-edge red circle zone")
	if oracle_entry: oracle_entry.pressed.emit()
	await process_frame
	var so_ov: Control = ui3.overlay_layer.find_child("StoryOracleOverlay", true, false)
	var b_clr: Control = so_ov.find_child("OracleClearBtn", true, false) if so_ov else null
	var b_dbg: Control = so_ov.find_child("OracleDebugBtn", true, false) if so_ov else null
	var b_set: Control = so_ov.find_child("OracleSetBtn", true, false) if so_ov else null
	var b_full: Control = so_ov.find_child("OracleFullBtn", true, false) if so_ov else null
	var b_x: Control = so_ov.find_child("OracleCloseBtn", true, false) if so_ov else null
	var hdr_spaced := (b_clr != null and b_dbg != null and b_set != null and b_full != null and b_x != null
		and b_clr.position.x + b_clr.size.x <= b_dbg.position.x + 1.0
		and b_dbg.position.x + b_dbg.size.x <= b_set.position.x + 1.0
		and b_set.position.x + b_set.size.x <= b_full.position.x + 1.0
		and b_full.position.x + b_full.size.x <= b_x.position.x + 1.0)
	ok(so_ov != null and hdr_spaced and ui3.overlay_layer.find_child("OracleInput", true, false) != null, "clicking 故事神谕 opens floating StoryOracleOverlay with non-overlapping header controls cleanly")

	# Mobile portrait & floating composer inside Story Oracle
	var so_port_btn: Button = ui3.overlay_layer.find_child("OraclePortraitBtn", true, false)
	if so_port_btn: so_port_btn.pressed.emit()
	await process_frame
	var so_comp_ov: Control = ui3.overlay_layer.find_child("FloatingComposerOverlay", true, false)
	var so_comp_te: TextEdit = so_comp_ov.find_child("ComposerTextEdit", true, false) if so_comp_ov else null
	ok(hub.mobile_portrait_input and so_comp_ov != null and so_comp_te != null, "story oracle input triggers vertical portrait composer cleanly")
	if so_comp_te: so_comp_te.text = "请检查当前凛零好感度并调整时间"
	var so_comp_ok: Button = so_comp_ov.find_child("ComposerConfirmBtn", true, false) if so_comp_ov else null
	if so_comp_ok: so_comp_ok.pressed.emit()
	await process_frame
	var so_in: TextEdit = ui3.overlay_layer.find_child("OracleInput", true, false)
	ok(not hub.mobile_portrait_input and so_in != null and so_in.text == "请检查当前凛零好感度并调整时间", "confirming story oracle portrait composer restores landscape and fills OracleInput")

	# Test Data Channel bidirectional read/write + Undo across Diagnose / Worldbook / Advisor / Fix / Forge
	var oh = hub.story_oracle()
	var tmp_so_dir := "user://_check_story_oracle/"
	oh.base_dir_override = tmp_so_dir
	var ch_snap: Dictionary = oh.read_channel_snapshot()
	ok(int(ch_snap.get("message_count", 0)) >= 2 and (ch_snap.get("worldbook_entries", []) as Array).size() >= 100 and ch_snap.get("stat_data", {}).has("主角组"), "story oracle Data Channel reads live game stat, chat history, and worldbook snapshot")

	# Diagnose write & undo
	oh.mock_transport = func(kind: String, arg: String, _data: Dictionary) -> Dictionary:
		if kind == "CHAT":
			if arg == "diagnose":
				return {"reply": "<UpdateVariable><Analysis>校准时间与好感度</Analysis><JSONPatch>[{\"op\":\"replace\",\"path\":\"/stat_data/主角组/时间\",\"value\":\"1015年2月9日 18:00\"}]</JSONPatch></UpdateVariable>"}
			if arg == "worldinfo":
				return {"reply": "<LorebookEdit>\naction: create\ntitle: DLC/神谕测试条目\ncategory: 创意工坊DLC\n<<<content\n来自故事神谕的测试设定。\ncontent>>>\n</LorebookEdit>"}
			if arg == "advisor":
				return {"reply": "<StoryPlan>\ntitle: 钟楼夜谈\ngoal: 让凛零在夜色下主动提起古代封印的异常波动\nseed: 一道蓝白火花自表壳边缘跃起\nwhy: 衔接当前探索节奏\n</StoryPlan>"}
			if arg == "fix":
				return {"reply": "<fix_think>精修测试</fix_think>\n<FixedReply>\n<content>\n（故事神谕精修版：夜风轻拂过中央学院的石廊。）\n</content>\n</FixedReply>"}
			if arg == "forge":
				return {"reply": "<CharDraft>\ntarget: npc\nname: 艾玛\noverview: 学院图书室夜班管理员\n<<<archive\n艾玛熟知古代手抄本脉络。\narchive>>>\n</CharDraft>"}
		if kind == "GET" and "raw.githubusercontent.com" in arg:
			return {"status": 503, "body": ""}
		if kind == "GET" and "cdn.jsdelivr.net" in arg:
			if "manifest.json" in arg:
				return {"status": 200, "body": "{\"version\":\"1.90.0\",\"display_name\":\"故事神谕\"}"}
			if "index.js" in arg:
				return {"status": 200, "body": "const DEFAULT_SYSTEM_PROMPT = `远端拉取的 1.90.0 新版神谕核心提示`;\nconst DIAGNOSE_SYSTEM_PROMPT = `远端 1.90.0 诊断规则`;"}
			if "README.md" in arg:
				return {"status": 200, "body": "# Story Oracle v1.90.0 Changelog"}
		return {"status": 200, "body": "{}"}

	var diag_box := [{}]
	oh.send_oracle_message("diagnose", "校对时间", func(_ok_d: bool, rec: Dictionary): diag_box[0] = rec)
	var d_res: Dictionary = oh.apply_message_diagnose(int(diag_box[0].get("id", 0)))
	ok(bool(d_res.get("ok", false)) and String(game.hero().get("时间", "")) == "1015年2月9日 18:00", "story oracle diagnose patch writes back to live Game.stat cleanly")
	oh.undo_message_action(int(diag_box[0].get("id", 0)))
	ok(String(game.hero().get("时间", "")) != "1015年2月9日 18:00", "undoing story oracle diagnose patch restores Game.stat cleanly")

	# Worldbook edit & undo
	DataCls.custom_worldbook_path_override = tmp_so_dir + "wb_custom.json"
	DataCls.reset_custom_worldbook_cache()
	var wb_box := [{}]
	oh.send_oracle_message("worldinfo", "新增测试条目", func(_ok_w: bool, rec: Dictionary): wb_box[0] = rec)
	var wb_res: Dictionary = oh.apply_message_lorebook(int(wb_box[0].get("id", 0)))
	var has_or_wb: bool = DataCls.worldbook().get("entries", []).any(func(e): return String(e.get("title", "")) == "DLC/神谕测试条目")
	ok(bool(wb_res.get("ok", false)) and has_or_wb, "story oracle <LorebookEdit> writes directly into live Worldbook")
	oh.undo_message_action(int(wb_box[0].get("id", 0)))
	var gone_or_wb: bool = not DataCls.worldbook().get("entries", []).any(func(e): return String(e.get("title", "")) == "DLC/神谕测试条目")
	ok(gone_or_wb, "undoing story oracle <LorebookEdit> removes created entry cleanly")

	# Advisor guidance & prompt injection
	var adv_box := [{}]
	oh.send_oracle_message("advisor", "给个方向", func(_ok_a: bool, rec: Dictionary): adv_box[0] = rec)
	var plans_parsed: Array = adv_box[0].get("actions", {}).get("plans", [])
	if not plans_parsed.is_empty(): oh.adopt_story_plan(plans_parsed[0])
	var main_msgs: Array = game.backend._build_story_api_messages()
	var injected_ok: bool = main_msgs.any(func(m): return "让凛零在夜色下主动提起" in String(m.get("content", "")))
	ok(oh.has_active_guidance() and injected_ok, "adopted story oracle Advisor plan injects guidance into main story AI prompt")
	oh.clear_guidance()

	# Fix reply -> appends non-destructive swipe & undo
	var last_ai_id: int = game.last_assistant_id()
	var before_swipes: int = (game.message(last_ai_id).get("swipes", []) as Array).size()
	var fix_box := [{}]
	oh.send_oracle_message("fix", "润色环境", func(_ok_f: bool, rec: Dictionary): fix_box[0] = rec)
	var fix_res: Dictionary = oh.apply_message_fix(int(fix_box[0].get("id", 0)))
	var m_after: Dictionary = game.message(last_ai_id)
	ok(bool(fix_res.get("ok", false)) and (m_after.get("swipes", []) as Array).size() == before_swipes + 1 and "故事神谕精修版" in game.text_of(m_after) and "<UpdateVariable>" in game.text_of(m_after), "story oracle Fix appends new Swipe while preserving original reply and MVU patch")
	oh.undo_message_action(int(fix_box[0].get("id", 0)))
	ok(not ("故事神谕精修版" in game.text_of(game.message(last_ai_id))), "undoing story oracle Fix switches active Swipe back cleanly")

	# Forge NPC write
	var frg_box := [{}]
	oh.send_oracle_message("forge", "造一个管理员", func(_ok_g: bool, rec: Dictionary): frg_box[0] = rec)
	var frg_res: Dictionary = oh.apply_message_forge(int(frg_box[0].get("id", 0)))
	var has_emma: bool = DataCls.worldbook().get("entries", []).any(func(e): return String(e.get("title", "")) == "DLC/艾玛")
	ok(bool(frg_res.get("ok", false)) and has_emma, "story oracle Character Forge writes NPC DLC cleanly into Worldbook")

	# Remote GitHub Raw failover -> jsDelivr update check + pull + prompt reload
	var upd_chk_box := [false]
	oh.check_for_updates(func(ok_c: bool, ver: String, _m: String): upd_chk_box[0] = ok_c and ver == "1.90.0")
	ok(bool(upd_chk_box[0]) and oh.update_available, "story oracle update check detects remote v1.90.0 via GitHub/jsDelivr fallback")
	var upd_pull_box := [false]
	oh.pull_update(func(ok_p: bool, _m: String): upd_pull_box[0] = ok_p)
	ok(bool(upd_pull_box[0]) and oh.installed_version == "1.90.0" and not oh.update_available and "远端拉取的 1.90.0 新版" in oh.base_prompt_for("normal"), "story oracle pulls update and hot-reloads upstream prompt templates cleanly")

	# Legacy SillyTavern .jsonl chat save import
	var tmp_jsonl := "user://_check_st_chat.jsonl"
	var st_line0 := JSON.stringify({"user_name": "星旅者", "character_name": "艾瑟拉", "chat_metadata": {"variables": {"stat_data": {"主角组": {"简介": "中央学院学生", "当前地点": "塞蕾特公国·中央学院", "时间": "1015年2月1日 16:30", "魔力": 1000, "魔力上限": 1000, "魔法": {}}, "角色组": {}, "剧情事件": {"当前触发事件": {}, "已完成事件": []}}}}})
	var st_line1 := JSON.stringify({"is_user": false, "is_system": false, "name": "艾瑟拉", "mes": "<场景>中央学院·校舍长廊</场景>\n<在场>凛零</在场>\n【凛零|平静】：“先去资料室。”", "swipes": ["<场景>中央学院·校舍长廊</场景>\n<在场>凛零</在场>\n【凛零|平静】：“先去资料室。”"], "swipe_id": 0, "variables": [{"stat_data": {"主角组": {"简介": "中央学院学生", "当前地点": "塞蕾特公国·中央学院", "时间": "1015年2月1日 16:30", "魔力": 1000, "魔力上限": 1000, "魔法": {}}, "角色组": {"凛零": {"好感度": 5, "色情值": 0}}, "剧情事件": {"当前触发事件": {}, "已完成事件": []}}}]})
	var st_line2 := JSON.stringify({"is_user": true, "is_system": false, "name": "{{user}}", "mes": "走吧，顺手记下定身刻印。"})
	var st_line3 := JSON.stringify({"is_user": false, "is_system": false, "name": "艾瑟拉", "mes": "<content>冰糖从廊角走来，替你校准了魔法书。</content>\n<UpdateVariable><JSONPatch>[{\"op\":\"insert\",\"path\":\"/角色组/冰糖\",\"value\":{\"好感度\":18,\"色情值\":2}},{\"op\":\"insert\",\"path\":\"/主角组/魔法/定身\",\"value\":{\"载体\":\"书本\",\"耗用\":11}}]</JSONPatch></UpdateVariable>\n<StatusPlaceHolderImpl/>", "swipes": ["<content>冰糖从廊角走来，替你校准了魔法书。</content>\n<UpdateVariable><JSONPatch>[{\"op\":\"insert\",\"path\":\"/角色组/冰糖\",\"value\":{\"好感度\":18,\"色情值\":2}},{\"op\":\"insert\",\"path\":\"/主角组/魔法/定身\",\"value\":{\"载体\":\"书本\",\"耗用\":11}}]</JSONPatch></UpdateVariable>\n<StatusPlaceHolderImpl/>"], "swipe_id": 0, "variables": [{"stat_data": {"主角组": {"简介": "中央学院学生", "当前地点": "塞蕾特公国·中央学院", "时间": "1015年2月1日 17:04", "当前BGM": "Humidity", "魔力": 989, "魔力上限": 1000, "魔法": {"定身": {"载体": "书本", "耗用": 11}}}, "角色组": {"凛零": {"好感度": 5, "色情值": 0}, "冰糖": {"好感度": 18, "色情值": 2}}, "剧情事件": {"当前触发事件": {}, "已完成事件": []}}}]})
	var jf := FileAccess.open(tmp_jsonl, FileAccess.WRITE)
	if jf:
		jf.store_string(st_line0 + "\n" + st_line1 + "\n" + st_line2 + "\n" + st_line3 + "\n")
		jf.close()
	game.import_save(tmp_jsonl)
	ok(game.messages.size() == 3 and String(game.persona.get("name", "")) == "星旅者" and game.known().has("冰糖") and int(game.known()["冰糖"].get("好感度", 0)) == 18 and game.hero().get("魔法", {}).has("定身") and int(game.hero().get("魔力", 0)) == 989, "SillyTavern legacy .jsonl chat save imports cleanly with full MVU stat_data, swipes & DB sync")

	# Home circular avatar clip (prevents square avatar corners spilling past ring)
	hub.set_meta("showcase_id", "bintang")
	ui3._reset("home", {})
	await process_frame
	var home_card = ui3.current().find_child("CharacterCard", true, false) if ui3.current() else null
	var home_av = home_card.find_child("Avatar", true, false) if home_card else null
	ok(home_av != null and bool(home_av.circle_clip) and is_equal_approx(home_av.size.x, 114.0) and (home_av.position + home_av.size * 0.5).is_equal_approx(Vector2(83.0, 88.0)), "home CharacterCard Avatar enables circular clip centered inside the ring")
	hub.remove_meta("showcase_id")

	# Title screen Check Update placeholder & cross-platform GitHub AppUpdater (Android APK + Desktop PCK)
	ui3._reset("title", {"phase": "menu"})
	await process_frame
	var title_upd_btn: Button = ui3.current().find_child("CheckUpdateBtn", true, false) if ui3.current() else null
	var has_old_demo_lbl: bool = false
	if ui3.current():
		for ch in ui3.current().find_children("*", "Label", true, false):
			if "预览模式" in String(ch.text):
				has_old_demo_lbl = true
	ok(title_upd_btn != null and "检查更新" in title_upd_btn.caption and not has_old_demo_lbl, "title bottom-left mounts CheckUpdateBtn placeholder in place of old demo label")
	if title_upd_btn:
		title_upd_btn.pressed.emit()
		await process_frame
	var upd_ov: Control = ui3.overlay_layer.find_child("AppUpdateOverlay", true, false)
	var upd_chk_b: Button = upd_ov.find_child("UpdateCheckBtn", true, false) if upd_ov else null
	var upd_pull_b: Button = upd_ov.find_child("UpdatePullBtn", true, false) if upd_ov else null
	var upd_dl_b: Button = upd_ov.find_child("UpdateDownloadBtn", true, false) if upd_ov else null
	ok(upd_ov != null and upd_chk_b != null and upd_pull_b != null and upd_dl_b != null, "clicking CheckUpdateBtn opens AppUpdateOverlay with check/pull/download controls")

	var uh = hub.updater()
	var tmp_upd_cfg := "user://_check_app_updater.cfg"
	var tmp_upd_dir := "user://_check_updates/"
	uh.cfg_path_override = tmp_upd_cfg
	uh.updates_dir_override = tmp_upd_dir
	uh.load_all()
	ok(uh.is_repo_configured() and uh.repo_slug() == "lumine-423/Aethera", "AppUpdater binds official lumine-423/Aethera GitHub repo cleanly")
	uh.set_repo_config("https://github.com/Hotaru/aethera-test.git", "", "main", false)
	var pck_bytes := "PCK_DEMO_PATCH_120".to_utf8_buffer()
	var apk_bytes := "APK_DEMO_BINARY_120".to_utf8_buffer()
	var pck_sha := ""
	var apk_sha := ""
	for pair in [[pck_bytes, "pck"], [apk_bytes, "apk"]]:
		var ctx := HashingContext.new(); ctx.start(HashingContext.HASH_SHA256); ctx.update(pair[0])
		if pair[1] == "pck": pck_sha = ctx.finish().hex_encode().to_lower()
		else: apk_sha = ctx.finish().hex_encode().to_lower()
	uh.mock_transport = func(op: String, url: String, _extra: Dictionary) -> Dictionary:
		if op == "GET":
			if "releases/latest" in url:
				return {"status": 200, "body": JSON.stringify({
					"tag_name": "v1.2.0",
					"name": "艾瑟拉 v1.2.0 测试版",
					"body": "修复头像裁剪并新增自动更新。",
					"html_url": "https://github.com/Hotaru/aethera-test/releases/tag/v1.2.0",
					"published_at": "2026-11-18T00:00:00Z",
					"assets": [
						{"name": "checksums.txt", "size": 160, "browser_download_url": "https://github.com/Hotaru/aethera-test/releases/download/v1.2.0/checksums.txt"},
						{"name": "Aethera-v1.2.0.apk", "size": apk_bytes.size(), "browser_download_url": "https://github.com/Hotaru/aethera-test/releases/download/v1.2.0/Aethera-v1.2.0.apk"},
						{"name": "Aethera-v1.2.0-patch.pck", "size": pck_bytes.size(), "browser_download_url": "https://github.com/Hotaru/aethera-test/releases/download/v1.2.0/Aethera-v1.2.0-patch.pck"}
					]
				})}
			if "checksums.txt" in url:
				return {"status": 200, "body": "%s  Aethera-v1.2.0.apk\n%s  Aethera-v1.2.0-patch.pck\n" % [apk_sha, pck_sha]}
		elif op == "DOWNLOAD":
			if ".apk" in url:
				return {"status": 200, "bytes": apk_bytes}
			if ".pck" in url:
				return {"status": 200, "bytes": pck_bytes}
		return {"status": 404, "body": ""}
	# Android flow: detect .apk, pull manifest/checksums, download verified .apk
	uh.platform_override = "android"
	var u_chk_and := [false]
	uh.check_for_updates(func(ok_c: bool, ver: String, _m: String): u_chk_and[0] = ok_c and ver == "1.2.0")
	ok(bool(u_chk_and[0]) and uh.update_available and String(uh.recommended_asset().get("name", "")) == "Aethera-v1.2.0.apk", "AppUpdater on Android detects GitHub Release v1.2.0 and selects .apk asset")
	var u_pull_ok := [false]
	uh.pull_update(func(ok_p: bool, _m: String): u_pull_ok[0] = ok_p)
	ok(bool(u_pull_ok[0]) and String(uh.pulled_manifest.get("version", "")) == "1.2.0" and uh.remote_checksums.has("Aethera-v1.2.0.apk"), "AppUpdater pull_update fetches changelog, manifest and SHA256 checksums")
	var u_dl_and := [""]
	uh.download_recommended(func(ok_d: bool, p_out: String, _m: String): u_dl_and[0] = p_out if ok_d else "")
	ok(u_dl_and[0] != "" and FileAccess.file_exists(u_dl_and[0]) and uh.downloaded_sha256 == apk_sha, "AppUpdater downloads and SHA256-verifies Android .apk cleanly")
	# Desktop Windows flow: detect .pck hotpatch, download verified .pck, apply patch
	uh.platform_override = "windows"
	uh.use_mirror = true
	var u_chk_win := [false]
	uh.check_for_updates(func(ok_c: bool, _v: String, _m: String): u_chk_win[0] = ok_c)
	ok(bool(u_chk_win[0]) and String(uh.recommended_asset().get("name", "")) == "Aethera-v1.2.0-patch.pck" and "镜像" in uh.last_source_used, "AppUpdater on Desktop prioritizes .pck hotpatch and respects GitHub mirror setting")
	var u_dl_win := [""]
	uh.download_recommended(func(ok_d: bool, p_out: String, _m: String): u_dl_win[0] = p_out if ok_d else "")
	var pck_res: Dictionary = uh.apply_downloaded_pck_patch()
	ok(u_dl_win[0] != "" and bool(pck_res.get("ok", false)) and uh.installed_patch_version == "1.2.0" and FileAccess.file_exists(uh.active_pck_path), "AppUpdater Desktop downloads verified .pck and stages active hotpatch cleanly")
	if is_instance_valid(upd_ov): upd_ov.close()
	uh.mock_transport = Callable(); uh.platform_override = ""
	uh.reset_repo_config()
	uh.cfg_path_override = ""; uh.updates_dir_override = ""
	uh.active_pck_path = ""; uh.installed_patch_version = ""
	for fn in ["pulled_manifest.json", "Aethera-v1.2.0.apk", "Aethera-v1.2.0-patch.pck", "active_patch.pck"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_upd_dir + fn))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_upd_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_upd_cfg))

	# Connect page wording (公益站, zero 中转) + Rotating Origin Wheel + Custom Origin dynamic opening
	hub.review_mode = true
	ui3.busy = false
	ui3._reset("connect", {"next": "origin", "first": true})
	await process_frame
	var conn_scr = ui3.current()
	var saw_gongyi := false
	var saw_zhongzhuan := false
	if conn_scr:
		for ch in conn_scr.find_children("*", "", true, false):
			for prop in ["text", "caption", "placeholder_text"]:
				var v = ch.get(prop)
				if v != null:
					var s_v := String(v)
					if "公益站" in s_v: saw_gongyi = true
					if "中转" in s_v: saw_zhongzhuan = true
	ok(saw_gongyi and not saw_zhongzhuan, "connect screen uses 公益站 copy and contains zero 中转 wording")

	ui3.busy = false
	ui3._reset("origin", {})
	await process_frame
	var o_scr = ui3.current()
	ok(o_scr != null and o_scr.find_child("WheelStage", true, false) != null and o_scr.find_child("WheelPrevBtn", true, false) != null and o_scr.find_child("WheelNextBtn", true, false) != null and o_scr.find_child("ConfirmOrigin", true, false) != null, "origin screen mounts rotating wheel stage and controls")
	var staff_card: Button = o_scr.find_child("Origin_staff", true, false) if o_scr else null
	if staff_card:
		staff_card.pressed.emit()
		await process_frame
	var ln_lbl: Label = o_scr.find_child("WheelListName", true, false) if o_scr else null
	var idx_lbl: Label = o_scr.find_child("WheelIdxLabel", true, false) if o_scr else null
	ok(o_scr != null and o_scr.picked == 1 and ln_lbl != null and ln_lbl.text == "蛇杖" and idx_lbl != null and idx_lbl.text == "2 / 8", "clicking side wheel card rotates origin wheel to front")
	if staff_card:
		staff_card.pressed.emit()
		await process_frame
	ok(o_scr != null and o_scr.find_child("OriginPop", true, false) != null, "clicking front wheel card opens OriginPop detail modal")
	var pop_close_b: Button = o_scr.find_child("OriginPopCloseBtn", true, false) if o_scr else null
	if pop_close_b:
		pop_close_b.pressed.emit()
		await process_frame
	ok(o_scr != null and o_scr.find_child("OriginPop", true, false) == null, "closing OriginPop dismisses detail modal cleanly")

	# Ensure empty API blocks custom origin cleanly at both origin & create screens
	game.backend.test_replies_enabled = true
	game.set_connection({"name": "空配置测试", "format": "openai", "mode": "chat", "url": "", "model": "", "as_new": true})
	var tmp_empty_pid := String(game.connection.get("profile_id", ""))
	await process_frame
	ok(not game.has_configured_api(), "has_configured_api is false when url/model are blank")
	var custom_card: Button = o_scr.find_child("Origin_custom", true, false) if o_scr else null
	if custom_card:
		custom_card.pressed.emit()
		await process_frame
	if o_scr: o_scr._confirm()
	await process_frame
	ok(ui3.current_name() == "origin" and o_scr != null and o_scr.find_child("CustomOriginApiPop", true, false) != null and o_scr.find_child("ApiPopGoConnectBtn", true, false) != null, "selecting custom origin without configured API stays on origin and prompts API setup")
	ui3.busy = false
	ui3._reset("create", {"origin": "custom"})
	await process_frame
	var c_scr = ui3.current()
	ok(c_scr != null and c_scr.find_child("CustomOpeningNotice", true, false) != null and c_scr.find_child("CreateGoConnectBtn", true, false) != null, "create screen for custom origin explains dynamic start and shows API prompt")
	if c_scr: c_scr._commit()
	await process_frame
	ok(ui3.current_name() == "create" and c_scr != null and c_scr.find_child("CreateCustomApiPop", true, false) != null, "create commit for custom origin blocks without API")

	# Configure real-shaped API & verify custom opening pre-prompt + no fixed location + 1015年·2月1日 + retry transition
	game.set_connection({"name": "公益站测试", "format": "openai", "mode": "chat", "url": "https://api.gongyi.example/v1", "model": "deepseek-chat", "as_new": true})
	var tmp_gongyi_pid := String(game.connection.get("profile_id", ""))
	await process_frame
	ok(game.has_configured_api(), "has_configured_api is true once endpoint and model are configured")
	var custom_cap := {"msgs": [], "kind": ""}
	var mock_fail_first := [true]
	game.backend.mock_story_transport = func(msgs: Array, kind: String, on_done: Callable):
		custom_cap["msgs"] = msgs.duplicate(true)
		custom_cap["kind"] = kind
		if bool(mock_fail_first[0]):
			on_done.call(false, "模拟网络超时")
			return
		var custom_patch := [
			{"op": "replace", "path": "/主角组/当前地点", "value": "自由联邦·琥珀港灯塔广场"},
			{"op": "replace", "path": "/主角组/时间", "value": "1015年·2月1日 14:20"},
			{"op": "replace", "path": "/主角组/当前BGM", "value": "Main Theme"},
			{"op": "replace", "path": "/主角组/简介", "value": "莱因（半精灵），带着旧海图的流浪画师。"},
		]
		var reply_txt := "\n".join([
			"<场景>自由联邦·琥珀港灯塔广场</场景>",
			"<content>",
			"1015年·2月1日午后，海风卷着盐粒掠过琥珀港的石阶。莱因合上手中的旧海图，抬眼望向正缓缓旋转的青铜灯塔。",
			"</content>",
			"<sumUp>",
			"时间: 1015年·2月1日 14:20",
			"地点: 自由联邦·琥珀港灯塔广场",
			"角色: 莱因",
			"可见: 在场私密",
			"何事: 莱因按随机开局降临于自由联邦·琥珀港灯塔广场",
			"线索: 灯塔底座刻着旧时代海图坐标",
			"变动: 初始化开局地点",
			"</sumUp>",
			"<choices>",
			"1. 【探索】：靠近青铜灯塔石基核对海图印记",
			"2. 【打听】：向码头守望者打听今日航船消息",
			"</choices>",
			"<UpdateVariable><Analysis>custom random start</Analysis><JSONPatch>" + JSON.stringify(custom_patch) + "</JSONPatch></UpdateVariable>",
		])
		on_done.call(true, reply_txt)

	game.new_game({"name": "莱因", "race": "半精灵", "appearance": "银发翠瞳的旅袍少年", "bio": "带着旧海图自自由联邦海岸启程的流浪画师"}, "custom")
	await process_frame
	var pre_prompt_user := ""
	for cm in custom_cap.get("msgs", []):
		if String(cm.get("role", "")) == "user":
			pre_prompt_user += String(cm.get("content", "")) + "\n"
	ok(String(custom_cap.get("kind", "")) == "custom_open" and "1015年·2月1日" in pre_prompt_user and "莱因" in pre_prompt_user and "半精灵" in pre_prompt_user and "银发翠瞳的旅袍少年" in pre_prompt_user and "流浪画师" in pre_prompt_user and "不设定固定开局地点" in pre_prompt_user, "custom origin sends structured pre-prompt containing 1015年·2月1日 and full player profile to model (kind=%s len=%d)" % [String(custom_cap.get("kind", "")), pre_prompt_user.length()])
	ok(String(game.hero().get("当前地点", "bad")) == "" and String(game.hero().get("时间", "")) == "1015年·2月1日" and game.messages.is_empty(), "before opening completes custom origin has empty location and fixed 1015年·2月1日 time")
	ui3.busy = false
	ui3._reset("story", {})
	await process_frame
	var cs_scr = ui3.current()
	var retry_btn: Button = cs_scr.find_child("RetryCustomBtn", true, false) if cs_scr else null
	ok(retry_btn != null and retry_btn.visible and cs_scr.status_label != null and "地点待生成" in cs_scr.status_label.text and "1015年·2月1日" in cs_scr.status_label.text, "story screen shows RetryCustomBtn and 地点待生成 · 1015年·2月1日 while custom opening has no reply yet")
	mock_fail_first[0] = false
	if retry_btn: retry_btn.pressed.emit()
	await process_frame
	ok(not game.messages.is_empty() and String(game.hero().get("当前地点", "")) == "自由联邦·琥珀港灯塔广场" and String(game.hero().get("时间", "")).begins_with("1015年·2月1日") and cs_scr != null and not cs_scr.lines.is_empty() and (retry_btn == null or not retry_btn.visible) and "琥珀港灯塔广场" in cs_scr.status_label.text, "retrying custom opening dynamically sets chosen location and renders generated story (msgs=%d loc=%s lines=%d vis=%s st=%s)" % [game.messages.size(), String(game.hero().get("当前地点", "")), cs_scr.lines.size() if cs_scr else -1, str(retry_btn.visible) if retry_btn else "null", cs_scr.status_label.text if cs_scr and cs_scr.status_label else ""])

	game.backend.mock_story_transport = Callable()
	game.delete_connection_profile(tmp_gongyi_pid)
	game.delete_connection_profile(tmp_empty_pid)
	await process_frame

	if is_instance_valid(so_ov): so_ov.close()
	oh.mock_transport = Callable()
	oh.clear_history(); oh.clear_guidance()
	oh.pulled_prompts.clear(); oh.installed_version = oh.SO_VERSION_DEFAULT; oh.latest_version = ""; oh.update_available = false
	oh.base_dir_override = ""
	DataCls.custom_worldbook_path_override = ""; DataCls.reset_custom_worldbook_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_jsonl))
	for fn in ["settings.json", "state.json", "pulled_prompts.json", "wb_custom.json", "remote/manifest.json", "remote/index.js", "remote/README.md"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_so_dir + fn))

	ui3.queue_free()
	await process_frame
	hub.gate_unlock_hash = ""
	hub.notice_seen = false
	hub.opening_seen = false
	hub.review_mode = true
	hub.options_path_override = ""
	hub.extra_path_override = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_opt))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_extra))

	game.backend.test_replies_enabled = false

	print("RESULT %d passed, %d failed" % [passes, failures.size()])
	for f in failures: print("  failed: ", f)
	quit(0 if failures.is_empty() else 1)
