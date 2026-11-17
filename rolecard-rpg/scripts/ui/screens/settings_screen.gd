extends "res://scripts/ui/ui_screen.gd"
## 设置: 显示 / 声音 / AI设置(API连接) / 世界书(只读) / 存档与恢复.
## Display changes apply live through UiHub and persist. API keys are never written by the UI:
## the connect request goes to the connection service, which owns storage.

var tab := "display"
var ai_type := 0
var ai_source := 0
var key_visible := false
var wb_cat := 0
var wb_entry := 0
var wb_entry_page := 0
var wb_query := ""
var wb_editing := false
var wb_draft_title := ""
var wb_draft_body := ""
var _wb_draft_id := ""
var status := "idle"   # idle | testing | ok | fail
var preview: Label
const SOURCES := [
	{"name": "自定义（兼容OpenAI）", "fields": ["url", "key", "model_id", "model_list"]},
	{"name": "OpenAI", "fields": ["key", "model_list"]},
	{"name": "Claude", "fields": ["key", "model_list"]},
	{"name": "Google AI Studio", "fields": ["key", "model_list"]},
	{"name": "OpenRouter", "fields": ["key", "model_list"]},
]

func build() -> void:
	tab = params.get("tab", tab)
	params.erase("tab")
	decor(81, Rect2(Vector2.ZERO, size), 0.6)
	var back := btn("返回", "tri_left", "secondary", Rect2(30, 960, 260, 86), func(): root.back(), "lb")
	back.name = "Back"
	music_btn(Rect2(1516, 34, 160, 64), "rt")
	var sw := W.ThemeSwitch.new(); put(sw, Rect2(1692, 34, 190, 64), "rt")
	var tab_buttons: Array = []
	var tabs := [["display", "显示", "monitor"], ["audio", "声音", "speaker"], ["ai", "AI与预设", "ai"], ["persona", "个人档案", "person"], ["backup", "存档与恢复", "database"]]
	if Data.edition() == "full": tabs.insert(4, ["worldbook", "世界书", "book"])
	for i in range(tabs.size()):
		var t: Array = tabs[i]
		var b := btn(t[1], t[2], "tab", Rect2(-20, 150 + i * g(110), 380, 92), func(): tab = t[0]; refresh(false), "l", 0.04 * i, null, 28)
		b.selected = tab == t[0]; b.slant = 30; b.arrow = tab != t[0]; b.divider = false
		b.hover_pitch = [1.0, 1.122, 1.26, 1.335, 1.498, 1.682][i]; b.name = "Tab_" + t[0]
		tab_buttons.append(b)
	cursor_for(tab_buttons)
	match tab:
		"audio": _audio()
		"ai": _ai()
		"worldbook": _worldbook()
		"persona": _persona()
		"backup": _backup()
		_: _display()

# ---------- display ----------
func _title(t: String, ic := "") -> void:
	var tick := Control.new(); tick.name = "TitleTick"; tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	put(tick, Rect2(380, 60, 100, 120), "c")
	tick.draw.connect(func():
		tick.draw_arc(Vector2(60, 60), 40, 0, TAU, 48, UiHub.c("accent", 0.5), 1.2, true)
		Kit.crescent(tick, Vector2(64, 60), 39, -PI * 0.45, PI * 0.45, 8, UiHub.c("accent"))
		Kit.star4(tick, Vector2(60, 60), 14, UiHub.c("accent"), 0.16))
	text(t, Rect2(480, 60, 900, 120), 64, "ink", 900, "c", null, HORIZONTAL_ALIGNMENT_LEFT, 0.02)
	var under := Control.new(); put(under, Rect2(480, 176, 400, 6), "c")
	under.draw.connect(func(): under.draw_rect(Rect2(0, 0, 70, 5), UiHub.c("accent")); under.draw_line(Vector2(80, 3), Vector2(320, 3), UiHub.c("line"), 1.5); Kit.hatch(under, Vector2(330, -4), 4, 10, UiHub.c("muted"), 7.0))

func _row(y: float, label: String, h := 110.0) -> Control:
	var row := Control.new(); put(row, Rect2(420, y, 1440, h), "c", 0.08 + y * 0.0002)
	text(label, Rect2(40, 0, 220, h), 30, "ink", 800, "c", row)
	var div := Control.new(); put(div, Rect2(0, 0, 1440, h), "c", -1.0, row)
	var paint := func() -> void:
		div.draw_line(Vector2(270, h * 0.25), Vector2(270, h * 0.75), UiHub.c("line"), 1.5)
		div.draw_line(Vector2(0, h - 1), Vector2(1440, h - 1), UiHub.c("line", 0.6), 1.0)
	div.draw.connect(paint)
	return row

func _slider(row: Control, lo_text: String, hi_text: String, value: float, lo: float, hi: float, cb: Callable, w := 560.0, x := 300.0) -> Control:
	if lo_text != "": text(lo_text, Rect2(x, 0, 90, row.size.y), 24, "ink", 700, "c", row, HORIZONTAL_ALIGNMENT_RIGHT)
	var s := W.ValueSlider.new(); s.min_value = lo; s.max_value = hi; s.value = value; s.step = 0.01
	put(s, Rect2(x + 110, row.size.y * 0.5 - 30, w, 64), "c", -1.0, row)
	s.value_changed.connect(cb)
	if hi_text != "": text(hi_text, Rect2(x + 130 + w, 0, 120, row.size.y), 24, "ink", 700, "c", row)
	return s

func _display() -> void:
	_title("显示设置")
	var r1 := _row(210, "UI布局")
	var sp_val := text("间距 %d%%" % int(round(lerpf(72.0, 132.0, UiHub.spacing))), Rect2(1130, 0, 260, 110), 22, "accent", 800, "c", r1)
	_slider(r1, "紧凑", "宽松", UiHub.spacing, 0.0, 1.0, func(v):
		UiHub.spacing = v; sp_val.text = "间距 %d%%" % int(round(lerpf(72.0, 132.0, v)))
		UiHub.options_changed.emit(); UiHub.save_options())
	var r2 := _row(330, "文字大小")
	_slider(r2, "小", "大", UiHub.text_scale, 0.9, 1.12, func(v):
		UiHub.text_scale = v
		if is_instance_valid(preview): preview.text = "当前字号 %d%%：这里是示例文本，用于预览效果。" % int(round(v * 100.0))
		UiHub.options_changed.emit(); UiHub.save_options())
	var pv := plate(Rect2(1110, 6, 330, 100), {"shape": "rect", "corner": "tr", "corner_size": 16, "layered": false}, "c", -1.0, r2)
	text("文字预览", Rect2(20, 6, 290, 36), 22, "ink", 800, "c", pv)
	preview = text("当前字号 %d%%：这里是示例文本，用于预览效果。" % int(round(UiHub.text_scale * 100.0)), Rect2(20, 42, 300, 56), 18, "muted", 600, "c", pv)
	var r3 := _row(450, "动态效果")
	for k in range(2):
		var calm := k == 1
		var b := btn(["标准", "减弱"][k], "", "segment", Rect2(330 + k * 260, 22, 240, 66), func(): UiHub.reduced_motion = calm; UiHub.options_changed.emit(); UiHub.palette_changed.emit(); UiHub.save_options(); refresh(), "c", -1.0, r3, 26)
		b.center_text = true; b.selected = UiHub.reduced_motion == calm
	text("减弱会停止背景漂移、扫光、过场与震动。", Rect2(880, 0, 520, 110), 20, "muted", 600, "c", r3)
	var r4 := _row(570, "对话速度")
	icon("chat", Rect2(310, 36, 40, 38), "ink", "c", r4)
	_slider(r4, "", "", UiHub.dialog_speed, 0.0, 1.0, func(v): UiHub.set_option("dialog_speed", v), 560, 260)
	icon("skip", Rect2(950, 38, 38, 34), "ink", "c", r4)
	var r5 := _row(690, "自动速度")
	_slider(r5, "慢", "快", UiHub.auto_speed, 0.0, 1.0, func(v): UiHub.set_option("auto_speed", v))
	var upd_btn := btn("检查更新", "refresh", "secondary", Rect2(940, 950, 290, 90), func(): root.open_app_updater(), "c")
	upd_btn.name = "SettingsCheckUpdateBtn"
	btn("恢复默认", "refresh", "secondary", Rect2(1260, 950, 300, 90), func(): UiHub.reset_display(); refresh(), "c").press_sfx = "reset"
	btn("返回", "back", "secondary", Rect2(1590, 950, 290, 90), func(): root.back(), "c")

# ---------- audio ----------
func _audio() -> void:
	_title("声音设置")
	var rh := 92.0
	var rows := [["master", "总音量", "confirm_big"], ["ui", "界面音效", "confirm"], ["sfx", "环境音效", "confirm"], ["music", "音乐", "victory"], ["voice", "语音", "type"]]
	for k in range(rows.size()):
		var bus: String = rows[k][0]; var cue: String = rows[k][2]
		var r := _row(190 + k * rh, rows[k][1], rh)
		var spk := icon("mute" if UiHub.volumes[bus] <= 0.001 else "speaker", Rect2(310, 26, 40, 40), "ink", "c", r)
		var pct := text("%d" % int(UiHub.volumes[bus] * 100), Rect2(1040, 0, 120, rh), 28, "accent", 800, "c", r)
		var on_vol := func(v: float) -> void:
			UiHub.set_volume(bus, v); pct.text = "%d" % int(v * 100)
			var want := "mute" if v <= 0.001 else "speaker"
			if spk.icon != want: spk.icon = want; spk.queue_redraw()
		_slider(r, "", "", UiHub.volumes[bus], 0.0, 1.0, on_vol, 600, 260)
		var play_it := func() -> void:
			request("audio.preview", {"bus": bus})
			if bus == "music":
				UiHub.play_music(UiHub.music_current if UiHub.music_current != "" else String(UiHub.music_manifest.get("title_track", "")))
			elif cue == "type":
				for j in range(6):
					var tw := create_tween(); tw.tween_interval(j * 0.07); tw.tween_callback(UiHub.sfx.bind("type", 0.95 + j * 0.03, 0.0))
			else: UiHub.sfx(cue)
			Kit.pop(spk, 0.0, 0.25)   # the speaker icon bounces with the preview
		var pv := btn("试听", "play", "chip", Rect2(1180, 16, 170, 60), play_it, "c", -1.0, r, 22)
		pv.press_sfx = "none"
	_choice_row(650, "音效风格", ["爱丽丝的摇篮", "空灵水晶"], ["aic", "mystic"], UiHub.sfx_pack, func(v): UiHub.set_pack(v); UiHub.sfx("confirm"))
	_choice_row(742, "震动反馈", ["开启", "关闭"], [true, false], UiHub.haptics, func(v): UiHub.set_option("haptics", v); UiHub.haptic(30))
	_choice_row(834, "失焦静音", ["开启", "关闭"], [true, false], UiHub.mute_unfocused, func(v): UiHub.set_option("mute_unfocused", v))
	var bgm_state := "已彻底关闭" if UiHub.music_disabled else (UiHub.music_current if UiHub.music_current != "" else "无")
	var total_bgm := int(UiHub.music_manifest.get("tracks", []).size())
	var custom_bgm := maxi(0, total_bgm - 14)
	text("《乐章》音乐播放器（共 %d 首：原卡 14 首 ＋ 扩充 %d 首） · 当前：%s" % [total_bgm, custom_bgm, bgm_state], Rect2(460, 944, 880, 44), 21, "ink", 700)
	text("已导入势力/地点/工坊/主页昼夜/情绪补位全部曲库；点右侧「打开乐章」可分类点播或彻底关闭。", Rect2(460, 990, 880, 34), 18, "muted", 600)
	var open_mp := btn("打开乐章", "music", "secondary", Rect2(1340, 946, 224, 74), func(): root.open_music_player(), "c", -1.0, null, 21)
	open_mp.name = "OpenMusicPlayer"; open_mp.press_sfx = "none"
	var shut_b := btn("恢复音乐" if UiHub.music_disabled else "彻底关闭音乐", "speaker" if UiHub.music_disabled else "mute", "primary" if UiHub.music_disabled else "danger", Rect2(1580, 946, 280, 74), func():
		var nxt := not UiHub.music_disabled
		UiHub.set_music_disabled(nxt)
		UiHub.sfx("toggle_off" if nxt else "toggle_on")
		refresh(), "c", -1.0, null, 20)
	shut_b.name = "SettingsShutoffMusic"; shut_b.press_sfx = "none"

func _choice_row(y: float, label: String, names: Array, values: Array, current, cb: Callable) -> void:
	var r := _row(y, label, 92.0)
	var btn_w := 240.0 if names.size() <= 2 else 224.0
	var step := 260.0 if names.size() <= 2 else 238.0
	for k in range(names.size()):
		var v = values[k]
		var b := btn(names[k], "", "segment", Rect2(330 + k * step, 13, btn_w, 66), func(): cb.call(v); refresh(), "c", -1.0, r, 24)
		b.center_text = true; b.selected = current == v

# ---------- AI / API (multi-profile quick switch + full preset manager screen) ----------
func _ai() -> void:
	var c: Dictionary = Game.connection
	var profiles: Array = c.get("profiles", []) if c.get("profiles") is Array else []
	var active_pid := String(c.get("profile_id", ""))
	var active_pname := String(c.get("profile_name", "默认连接"))
	var p := plate(Rect2(420, 114, 1440, 494), {"shape": "rect", "corner": "tr", "corner_size": 22, "layered": true}, "c", 0.05)
	header("AI连接 · 已保存 %d 套配置" % maxi(1, profiles.size()), Rect2(30, 18, 860, 54), 30, "c", p)
	text("当前：%s" % active_pname, Rect2(920, 22, 480, 44), 22, "accent", 800, "c", p, HORIZONTAL_ALIGNMENT_RIGHT)

	# Quick profile switcher chips
	var chip_sc := ScrollContainer.new(); chip_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(chip_sc, Rect2(50, 82, 1340, 56), "c", -1.0, p)
	var chip_hb := HBoxContainer.new(); chip_hb.add_theme_constant_override("separation", 10)
	chip_sc.add_child(chip_hb)
	for idx in range(profiles.size()):
		var pr: Dictionary = profiles[idx]
		var pid := String(pr.get("id", ""))
		var label := String(pr.get("name", "配置 %d" % (idx + 1)))
		if String(pr.get("model", "")) != "" and not (String(pr.get("model", "")) in label):
			label += " (" + String(pr.get("model", "")) + ")"
		var cb := Btn.new(); cb.setup(label, "confirm" if pid == active_pid else "ai", "segment", 18)
		cb.center_text = true; cb.selected = pid == active_pid; cb.name = "ApiProfileChip_" + str(idx)
		cb.custom_minimum_size = Vector2(maxf(200.0, Kit.text_width(label, UiHub.fs(18), 700) + 74.0), 48.0)
		cb.pressed.connect(func(): Game.select_connection_profile(pid))
		chip_hb.add_child(cb)

	var fmt_names := {"openai": "OpenAI 兼容", "claude": "Claude", "google": "Google AI Studio", "openrouter": "OpenRouter"}
	var rows := [["接口格式", "%s · %s" % [fmt_names.get(c.get("format", "openai"), "OpenAI 兼容"), "文本补全" if c.get("mode", "chat") == "text" else "聊天补全"]],
		["API地址", c.get("url", "") if c.get("url", "") != "" else "未填写"], ["模型", c.get("model", "") if c.get("model", "") != "" else "未填写"],
		["密钥", "已保存在本机" if c.get("has_key", false) else "未填写"]]
	for k in range(rows.size()):
		text(rows[k][0], Rect2(50, 148 + k * 58, 220, 52), 24, "muted", 700, "c", p)
		text(str(rows[k][1]), Rect2(280, 148 + k * 58, 1110, 52), 24, "ink", 750, "c", p)
	var open := btn("编辑当前连接", "ai", "primary", Rect2(50, 396, 300, 74), func(): root.go("connect"), "c", -1.0, p, 22)
	open.name = "OpenConnect"
	var add_api := btn("新增 API 配置", "add", "secondary", Rect2(364, 396, 260, 74), func(): root.go("connect", {"new": true}), "c", -1.0, p, 22)
	add_api.name = "NewConnect"
	var test_b := btn("测试连接", "tri_right", "secondary", Rect2(638, 396, 220, 74), func(): Game.test_connection(), "c", -1.0, p, 22)
	test_b.name = "TestConnect"
	var del_b := btn("删除此配置", "trash", "ghost", Rect2(872, 396, 200, 74), func(): Game.delete_connection_profile(active_pid), "c", -1.0, p, 20)
	del_b.name = "DeleteConnect"; del_b.disabled = profiles.size() <= 1
	var st := {"none": "尚未连接", "testing": "正在检查…", "ok": "已连接", "fail": "连接失败", "pending": "还测不了"}
	text(String(st.get(c.get("status", "none"), "")) + ("：" + String(c.message) if String(c.get("message", "")) != "" else ""), Rect2(1086, 396, 326, 74), 19, "ink", 650, "c", p)

	var q := plate(Rect2(420, 628, 1440, 304), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.1)
	header("预设", Rect2(30, 20, 1380, 56), 30, "c", q)
	var cur := "尚未导入预设"
	var p_meta := ""
	for pr in Game.presets:
		if pr.get("active", false):
			cur = String(pr.get("name", ""))
			p_meta = "（已开启 %d / %d 条 · 已自定义 %d 条）" % [int(pr.get("enabled_count", 0)), int(pr.get("entry_count", 0)), int(pr.get("modified_count", 0))]
	text("当前预设", Rect2(50, 98, 220, 56), 25, "muted", 700, "c", q)
	text(cur + p_meta, Rect2(280, 98, 1110, 56), 24, "ink", 750, "c", q)
	var mgr := btn("查看与编辑预设条目", "sliders", "primary", Rect2(50, 190, 360, 76), func(): root.go("presets"), "c", -1.0, q, 22)
	mgr.name = "ManagePresets"
	var imp := btn("导入预设文件", "download", "secondary", Rect2(430, 190, 280, 76), func(): _pick_file(func(path): Game.import_preset(path)), "c", -1.0, q, 22)
	imp.name = "ImportPreset"
	text("点左侧按钮可查看全部预设条目、逐条开启/关闭，并修改任意条目内容。", Rect2(736, 190, 660, 76), 19, "muted", 600, "c", q)
	if not Game.changed.is_connected(_on_game): Game.changed.connect(_on_game)

func _on_game(part: String) -> void:
	if tab == "ai" and part in ["connection", "presets"]: refresh()

func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game): Game.changed.disconnect(_on_game)

func _pick_file(cb: Callable, filt := "*.json,*.jsonl ; 存档与酒馆聊天记录 (.json / .jsonl)") -> void:
	if OS.has_feature("web") and not Game.demo: cb.call(""); return
	if OS.has_feature("web"): toast("网页版暂不支持选择本地文件，请用电脑版", "info"); return
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE; fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray([filt]); fd.use_native_dialog = true
	add_child(fd)
	fd.file_selected.connect(func(path): cb.call(path); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(900, 600))

# ---------- persona (玩家人设) ----------
var persona_draft: Dictionary = {}
func _persona() -> void:
	_title("个人档案")
	var c: Dictionary = Data.content().create
	if persona_draft.is_empty(): persona_draft = Game.persona.duplicate()
	if not Game.has_story():
		text("开始故事后，可以在这里修改你的角色。", Rect2(480, 230, 1200, 60), 28, "muted", 700)
		return
	var rows := [["name", c.name, false], ["race", c.race, false], ["appearance", c.appearance, true], ["bio", c.bio, true]]
	var y := 220.0
	for row in rows:
		var k: String = row[0]
		text(row[1], Rect2(460, y, 220, 64), 28, "ink", 800, "c")
		if row[2]:
			var te := TextEdit.new(); te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; te.text = String(persona_draft.get(k, "")); te.name = "Persona_" + k
			te.text_changed.connect(func(): persona_draft[k] = te.text)
			put(te, Rect2(700, y, 1150, 170), "c"); y += 190
		else:
			var le := LineEdit.new(); le.text = String(persona_draft.get(k, "")); le.name = "Persona_" + k
			le.text_changed.connect(func(v): persona_draft[k] = v)
			put(le, Rect2(700, y, 1150, 64), "c"); y += 86
	var save := btn("保存档案", "save", "primary", Rect2(1560, 950, 300, 90), func(): Game.update_persona(persona_draft.duplicate()); UiHub.sfx("save"), "c")
	save.name = "SavePersona"
	text("改动会在 AI 下次回复时读到。", Rect2(700, 960, 800, 60), 20, "muted", 600)
# ---------- world book ----------
func _worldbook() -> void:
	var book: Dictionary = Data.worldbook()
	var cats: Array = book.get("categories", [])
	var all_entries: Array = book.get("entries", [])
	if cats.is_empty():
		var legacy: Dictionary = Data.demo().get("worldbook", {})
		cats = legacy.keys()
		for k in cats:
			for e in legacy[k]:
				all_entries.append({"title": e.get("title", ""), "category": k, "path": "", "summary": "", "body": e.get("body", "")})
	wb_cat = clampi(wb_cat, 0, maxi(0, cats.size() - 1))
	var cat_name := String(cats[wb_cat]) if not cats.is_empty() else ""
	var q := wb_query.strip_edges().to_lower()
	var entries: Array = []
	for e in all_entries:
		if q == "" and String(e.get("category", "")) != cat_name: continue
		var hay := (String(e.get("title", "")) + " " + String(e.get("category", "")) + " " + String(e.get("summary", "")) + " " + String(e.get("body", ""))).to_lower()
		if q != "" and not hay.contains(q): continue
		entries.append(e)
	const WB_PER_PAGE := 8
	var pages := maxi(1, int(ceili(float(entries.size()) / float(WB_PER_PAGE))))
	wb_entry = clampi(wb_entry, 0, maxi(0, entries.size() - 1))
	wb_entry_page = clampi(int(wb_entry / WB_PER_PAGE), 0, pages - 1) if not entries.is_empty() else 0
	var p := plate(Rect2(420, 120, 1440, 800), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.05)
	header("世界书 · 完整版（共 %d 条）" % all_entries.size(), Rect2(30, 18, 920, 56), 30, "c", p)
	var search := LineEdit.new(); search.name = "Search"; search.placeholder_text = "全局搜索世界书标题、设定与正文（回车）"; search.text = wb_query
	put(search, Rect2(80, 88, 1140, 54), "c", -1.0, p)
	icon("search", Rect2(36, 97, 36, 36), "muted", "c", p)
	search.text_submitted.connect(func(t): wb_query = t; wb_entry = 0; wb_editing = false; _wb_draft_id = ""; refresh(false))
	btn("检索", "", "secondary", Rect2(1232, 88, 90, 54), func(): wb_query = search.text; wb_entry = 0; wb_editing = false; _wb_draft_id = ""; refresh(false), "c", -1.0, p, 20)
	btn("清空", "", "ghost", Rect2(1330, 88, 86, 54), func(): wb_query = ""; wb_entry = 0; wb_editing = false; _wb_draft_id = ""; refresh(false), "c", -1.0, p, 20)
	var cat_icons := {"世界设定": "globe", "国家与组织": "bookmark", "地点设定": "pin", "角色人设": "person", "NPC速览": "person", "剧情事件": "book", "后剧情动态": "refresh", "异危与魔物": "sparkle", "系统与叙事规则": "sliders"}
	for k in range(cats.size()):
		var c: String = String(cats[k])
		var b := btn(c, cat_icons.get(c, "book"), "row", Rect2(20, 160 + k * 60, 260, 54), func(): wb_query = ""; wb_cat = k; wb_entry = 0; wb_editing = false; _wb_draft_id = ""; refresh(false), "c", -1.0, p, 18)
		b.selected = (q == "" and k == wb_cat); b.arrow = true; b.divider = false
	var lo := wb_entry_page * WB_PER_PAGE
	var hi := mini(entries.size(), lo + WB_PER_PAGE)
	for idx in range(lo, hi):
		var row_i := idx - lo
		var item: Dictionary = entries[idx]
		var lbl_txt := String(item.get("title", "未命名")) + (" *" if bool(item.get("_modified", false)) else "")
		if lbl_txt.length() > 14: lbl_txt = lbl_txt.substr(0, 13) + "…"
		var eb := btn(lbl_txt, "", "row", Rect2(290, 160 + row_i * 62, 334, 56), func(): wb_entry = idx; wb_editing = false; _wb_draft_id = ""; refresh(false), "c", -1.0, p, 19)
		eb.selected = (idx == wb_entry); eb.divider = false
	var prev_b := btn("上一页", "tri_left", "ghost", Rect2(290, 672, 128, 52), func(): wb_entry = maxi(0, (wb_entry_page - 1) * WB_PER_PAGE); wb_editing = false; _wb_draft_id = ""; refresh(false), "c", -1.0, p, 17)
	prev_b.disabled = wb_entry_page <= 0
	text("%d / %d" % [wb_entry_page + 1, pages], Rect2(422, 678, 70, 40), 19, "muted", 700, "c", p, HORIZONTAL_ALIGNMENT_CENTER)
	var next_b := btn("下一页", "tri_right", "ghost", Rect2(496, 672, 128, 52), func(): wb_entry = mini(maxi(0, entries.size() - 1), (wb_entry_page + 1) * WB_PER_PAGE); wb_editing = false; _wb_draft_id = ""; refresh(false), "c", -1.0, p, 17)
	next_b.disabled = wb_entry_page >= pages - 1
	var body := plate(Rect2(636, 160, 780, 616), {"shape": "rect", "fill": "surface2", "layered": false}, "c", -1.0, p)
	if entries.is_empty():
		text("没有找到匹配的世界书条目。", Rect2(36, 30, 700, 60), 24, "muted", 700, "c", body)
	else:
		var cur: Dictionary = entries[wb_entry]
		var cur_eid := String(cur.get("id", cur.get("title", "")))
		var cur_title := String(cur.get("title", ""))
		var cur_body := String(cur.get("body", ""))
		var is_mod := bool(cur.get("_modified", false)) or Data.has_worldbook_override(cur_eid)
		if _wb_draft_id != cur_eid:
			_wb_draft_id = cur_eid
			wb_draft_title = cur_title
			wb_draft_body = cur_body

		if wb_editing:
			text("修改条目：", Rect2(24, 18, 120, 46), 20, "accent", 800, "c", body)
			var tle := LineEdit.new(); tle.name = "WorldbookEditTitle"; tle.text = wb_draft_title
			tle.text_changed.connect(func(nt): wb_draft_title = nt)
			put(tle, Rect2(146, 14, 610, 48), "c", -1.0, body)
			var meta := "%s  ·  %s" % [String(cur.get("category", "")), String(cur.get("path", ""))]
			text(meta, Rect2(28, 68, 724, 28), 16, "muted", 600, "c", body)
			var te := TextEdit.new(); te.name = "WorldbookEditBody"
			te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; te.text = wb_draft_body; te.caret_blink = true
			te.text_changed.connect(func(): wb_draft_body = te.text)
			put(te, Rect2(24, 102, 732, 434), "c", -1.0, body)
			var reset_wb := btn("还原默认", "refresh", "secondary", Rect2(24, 548, 176, 52), func():
				Data.reset_worldbook_entry(cur_eid)
				wb_editing = false; _wb_draft_id = ""
				UiHub.sfx("reset"); toast("已恢复该条世界书默认内容", "refresh"); refresh(false)
			, "c", -1.0, body, 18)
			reset_wb.name = "ResetWorldbookBtn"; reset_wb.disabled = not is_mod
			var cancel_wb := btn("取消", "close", "ghost", Rect2(410, 548, 140, 52), func():
				wb_editing = false; _wb_draft_id = ""; refresh(false)
			, "c", -1.0, body, 19)
			cancel_wb.name = "CancelWorldbookBtn"
			var save_wb := btn("保存修改", "save", "primary", Rect2(564, 548, 192, 52), func():
				var final_title := tle.text if is_instance_valid(tle) else wb_draft_title
				var final_body := te.text if is_instance_valid(te) else wb_draft_body
				Data.save_worldbook_entry(cur_eid, final_title, final_body)
				wb_editing = false; _wb_draft_id = ""
				UiHub.sfx("save"); toast("已保存世界书条目修改（将在后续生成读取）", "save"); refresh(false)
			, "c", -1.0, body, 20)
			save_wb.name = "SaveWorldbookBtn"
		else:
			var h := W.Header.new(); h.title = cur_title; h.px = 28; put(h, Rect2(24, 18, 500, 50), "c", -1.0, body)
			var edit_wb := btn("修改", "docs", "secondary", Rect2(540, 16, 108, 46), func():
				wb_editing = true; wb_draft_title = cur_title; wb_draft_body = cur_body; _wb_draft_id = cur_eid; refresh(false)
			, "c", -1.0, body, 19)
			edit_wb.name = "EditWorldbookBtn"
			var reset_inline := btn("还原", "refresh", "ghost", Rect2(654, 16, 100, 46), func():
				Data.reset_worldbook_entry(cur_eid)
				_wb_draft_id = ""; UiHub.sfx("reset"); toast("已恢复默认", "refresh"); refresh(false)
			, "c", -1.0, body, 18)
			reset_inline.name = "ResetWorldbookBtn"; reset_inline.disabled = not is_mod
			var meta := "%s  ·  %s%s" % [String(cur.get("category", "")), String(cur.get("path", "")), "  ·  [已修改]" if is_mod else ""]
			text(meta, Rect2(28, 72, 724, 30), 17, "accent" if is_mod else "muted", 600, "c", body)
			var sc := ScrollContainer.new()
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			put(sc, Rect2(24, 108, 732, 488), "c", -1.0, body)
			var lbl := text(cur_body, Rect2(0, 0, 704, 100), 21, "ink", 500, "c", sc)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.custom_minimum_size = Vector2(704, 0)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scope := ("搜索 [%s]" % q) if q != "" else cat_name
	text("可编辑 · 完整版世界书已本地接入（%s：%d 条，全部 %d 条）" % [scope, entries.size(), all_entries.size()], Rect2(420, 930, 1000, 40), 18, "muted", 600)

# ---------- backup ----------
func _backup() -> void:
	icon("docs", Rect2(460, 120, 140, 150), "ink")
	text("存档与恢复", Rect2(630, 120, 800, 120), 70, "ink", 900, "c", null, HORIZONTAL_ALIGNMENT_LEFT, 0.0)
	var under := Control.new(); put(under, Rect2(640, 240, 200, 6), "c")
	under.draw.connect(func(): under.draw_rect(Rect2(0, 0, 200, 5), UiHub.c("accent")))
	text("可将当前游戏进度导出备份，或从备份文件恢复进度。", Rect2(640, 262, 900, 40), 22, "muted", 600)
	var cards := [["导出备份", "将当前存档导出为备份文件", "upload", "backup.export"], ["导入备份", "从本地备份文件导入存档", "download", "backup.import"], ["恢复备份", "将游戏进度恢复至所选备份", "restore", "backup.restore"]]
	for k in range(cards.size()):
		var c: Array = cards[k]
		var b := Btn.new(); b.variant = "secondary"; b.slant = 50; b.arrow = true
		put(b, Rect2(440 + k * 400, 340, 380, 340), "c", 0.08 + k * 0.06)
		b.pressed.connect(func(): _backup_action(c[3], c[0]))
		b.name = "Backup_" + c[3].get_slice(".", 1)
		icon(c[2], Rect2(130, 30, 110, 110), "ink", "c", b)
		text(c[0], Rect2(60, 170, 280, 60), 36, "ink", 900, "c", b)
		text(c[1], Rect2(60, 236, 250, 70), 20, "muted", 600, "c", b)
		var u := W.Bar.new(); u.value = 1; u.max_value = 1; u.slant = 0; put(u, Rect2(60, 318, 120, 5), "c", -1.0, b)
	var note := plate(Rect2(440, 720, 1180, 76), {"slant": 24, "fill": "surface2", "layered": false}, "c", 0.3)
	icon("info", Rect2(40, 20, 36, 36), "ink", "c", note)
	text("导入前会检查备份内容。", Rect2(96, 0, 800, 76), 24, "ink", 700, "c", note)
	var clear := btn("清除自动存档", "trash", "secondary", Rect2(1340, 830, 280, 76), func(): _confirm_clear(), "c", 0.35, null, 24)
	clear.name = "ClearRecovery"

func _backup_action(action: String, _label: String) -> void:
	match action:
		"backup.export": Game.export_save()
		"backup.import":
			var d = root.dialog({"title": "导入备份", "message": "导入将替换当前进度。", "icon": "file_warn", "buttons": [{"id": "cancel", "text": "取消", "icon": "close"}, {"id": "ok", "text": "选择文件", "icon": "download", "kind": "primary"}]})
			d.chosen.connect(func(id): if id == "ok": _pick_file(func(path): Game.import_save(path)))
		_: root.go("saves", {"mode": "load"})

func _confirm_clear() -> void:
	var d = root.dialog({"title": "清除自动存档", "message": "手动存档不受影响。请先备份需要保留的记录。", "icon": "warn", "tone": "danger", "buttons": [{"id": "cancel", "text": "取消", "icon": "close"}, {"id": "ok", "text": "确认清除", "icon": "warn_fill", "kind": "primary"}]})
	var on_choice := func(id: String) -> void:
		if id == "ok": Game.delete_slot(0); toast("已清除自动存档", "trash")
	d.chosen.connect(on_choice)
func on_back() -> bool:
	return false
