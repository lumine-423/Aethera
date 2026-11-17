extends "res://scripts/ui/ui_screen.gd"
## 连接AI：支持多组 API 配置命名保存与随时切换。默认 = OpenAI 兼容 + 聊天补全。
## params: next (保存并继续目标), first (开局引导时提供跳过), new (强制以空白新建配置打开).

var profile_name := ""
var profile_id := ""
var url := ""
var key := ""
var model := ""
var fmt := 0
var mode := 0
var more := false
var key_visible := false
var _initialized := false
var _last_loaded_id := ""
var status_label: Label
var dot: Control
const FORMATS := [["openai", "OpenAI 兼容（默认）"], ["claude", "Claude"], ["google", "Google AI Studio"], ["openrouter", "OpenRouter"]]
const MODES := [["chat", "聊天补全（默认）"], ["text", "文本补全"]]
const STEPS := [
	["找一家模型服务商", "在服务商网站注册账号并开通 API；绝大多数服务商都支持 OpenAI 格式。"],
	["拿到密钥并命名配置", "复制 API key；下方填个配置名称（如 DeepSeek 主力 / 公益站），以后一键切换。"],
	["填好地址与模型", "分别填 API 地址、密钥和模型名称，也能点“拉取模型”自动列表。"],
	["测试或另存多套配置", "点“保存修改”覆盖当前，或点“存为新配置”同时保留多组备用。"],
]

func _sync_fields_from_active(as_new := false) -> void:
	var c: Dictionary = Game.connection
	if as_new:
		profile_id = ""
		profile_name = ""
		url = ""
		model = ""
		key = ""
		fmt = 0
		mode = 0
		more = false
		_last_loaded_id = "__new__"
		return
	profile_id = String(c.get("profile_id", ""))
	profile_name = String(c.get("profile_name", ""))
	url = String(c.get("url", ""))
	model = String(c.get("model", ""))
	key = ""
	fmt = 0
	for i in range(FORMATS.size()):
		if FORMATS[i][0] == String(c.get("format", "openai")): fmt = i
	mode = 1 if String(c.get("mode", "chat")) == "text" else 0
	more = fmt != 0 or mode != 0
	_last_loaded_id = profile_id

func build() -> void:
	var c: Dictionary = Game.connection
	if not _initialized:
		_initialized = true
		var want_new := bool(params.get("new", false))
		params.erase("new")
		_sync_fields_from_active(want_new)
	chrome("连接AI")
	decor(57, Rect2(Vector2.ZERO, size), 0.6)
	_guide(c)
	_form()
	if not Game.changed.is_connected(_on_game): Game.changed.connect(_on_game)

func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game): Game.changed.disconnect(_on_game)

func _guide(c: Dictionary) -> void:
	var p := plate(Rect2(70, 140, 860, 800), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true}, "c", 0.05)
	header("怎么连接（四步）", Rect2(36, 20, 780, 52), 30, "c", p)
	for i in range(STEPS.size()):
		var y := 86.0 + i * clampf(g(96), 84.0, 112.0)
		var num := plate(Rect2(40, y, 72, 72), {"slant": 18, "fill": "accent" if i == 0 else "block", "fill_alpha": 1.0, "border": "", "layered": false, "glass": false}, "c", -1.0, p)
		text("%d" % (i + 1), Rect2(0, 0, 72, 72), 34, "on_accent" if i == 0 else "on_block", 900, "c", num, HORIZONTAL_ALIGNMENT_CENTER)
		text(STEPS[i][0], Rect2(130, y - 2, 690, 36), 25, "ink", 850, "c", p)
		text(STEPS[i][1], Rect2(130, y + 32, 690, 52), 18, "muted", 600, "c", p)

	# 已保存配置快速切换区
	var profiles: Array = c.get("profiles", []) if c.get("profiles") is Array else []
	var sw_box := plate(Rect2(36, 514, 788, 256), {"shape": "rect", "fill": "surface2", "layered": false}, "c", -1.0, p)
	header("已保存的 API 配置（%d 套）" % profiles.size(), Rect2(20, 14, 480, 40), 22, "c", sw_box)
	var add_b := btn("新建空白", "add", "chip", Rect2(574, 12, 194, 44), func():
		_sync_fields_from_active(true); refresh(false)
	, "c", -1.0, sw_box, 18)
	add_b.name = "NewApiProfile"

	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(sc, Rect2(20, 66, 748, 174), "c", -1.0, sw_box)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 8); vb.custom_minimum_size.x = 724
	sc.add_child(vb)
	if profiles.is_empty():
		var el := Lbl.new(); el.setup("尚未保存任何配置；在右侧填写后点击「保存修改」或「存为新配置」。", 18, "muted", 600); vb.add_child(el)
	else:
		for k in range(profiles.size()):
			var pr: Dictionary = profiles[k]
			var pid := String(pr.get("id", ""))
			var is_cur := (pid == profile_id) and (profile_id != "")
			var row_h := Control.new(); row_h.custom_minimum_size = Vector2(720, 50); vb.add_child(row_h)
			var pname := String(pr.get("name", "未命名配置"))
			var pmod := String(pr.get("model", ""))
			var cap := "%s%s" % [pname, (" · " + pmod) if pmod != "" else ""]
			var pb := Btn.new(); pb.setup(cap, "confirm" if is_cur else "ai", "secondary", 18)
			pb.selected = is_cur; pb.name = "SelectProfile_" + str(k)
			pb.position = Vector2(0, 0); pb.size = Vector2(618, 46)
			pb.pressed.connect(func():
				Game.select_connection_profile(pid)
				_sync_fields_from_active(false)
				refresh(false)
			)
			row_h.add_child(pb)
			var del_b := Btn.new(); del_b.setup("", "trash", "ghost", 17)
			del_b.name = "DeleteProfile_" + str(k)
			del_b.position = Vector2(628, 0); del_b.size = Vector2(88, 46)
			del_b.disabled = profiles.size() <= 1
			del_b.pressed.connect(func():
				Game.delete_connection_profile(pid)
				_sync_fields_from_active(false)
				refresh(false)
			)
			row_h.add_child(del_b)

func _form() -> void:
	var p := plate(Rect2(980, 140, 880, 800), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.1)
	header("正在编辑配置" if profile_id != "" else "新建 API 配置", Rect2(30, 20, 820, 56), 30, "c", p)
	var y := 92.0
	y = _field(p, y, "配置名称", "例如 DeepSeek 主力 / 公益站", profile_name, func(t): profile_name = t, "ApiProfileName", 76.0)
	y = _field(p, y, "API地址", "例如 https://api.example.com/v1", url, func(t): url = t, "ApiUrl", 76.0)
	var kt := text("密钥", Rect2(40, y, 200, 60), 25, "ink", 750, "c", p)
	var k := LineEdit.new(); k.name = "ApiKey"; k.secret = not key_visible; k.text = key
	k.placeholder_text = "已保存（留空表示不改）" if (profile_id != "" and Game.connection.get("has_key", false) and key == "") else "粘贴你的 API key"
	k.text_changed.connect(func(t): key = t)
	put(k, Rect2(220, y, 530, 60), "c", -1.0, p)
	var eye := btn("", "eye_off" if key_visible else "eye", "icon", Rect2(760, y, 80, 60), func(): key_visible = not key_visible; k.secret = not key_visible, "c", -1.0, p)
	eye.tooltip_text = "显示 / 隐藏密钥"
	kt.tooltip_text = "服务商给你的密钥，常以 sk- 开头"
	y += 76.0
	text("模型", Rect2(40, y, 200, 60), 25, "ink", 750, "c", p)
	var le_model := LineEdit.new(); le_model.name = "ApiModel"; le_model.placeholder_text = "例如 deepseek-chat"; le_model.text = model
	le_model.text_changed.connect(func(t): model = t)
	put(le_model, Rect2(220, y, 420, 60), "c", -1.0, p)
	var fetch_btn := btn("拉取模型", "refresh", "secondary", Rect2(650, y, 190, 60), func(): _fetch_models(), "c", -1.0, p, 20)
	fetch_btn.name = "FetchModels"
	y += 74.0
	var models: Array = Game.connection.get("models", [])
	if not models.is_empty():
		text("可选模型", Rect2(40, y, 200, 52), 21, "muted", 700, "c", p)
		var opt := OptionButton.new(); opt.name = "ModelSelector"
		opt.add_item("▼ 点击直接选用从服务商拉取的模型（共 %d 个）" % models.size())
		var cur_sel := 0
		for idx in range(models.size()):
			var m_name := str(models[idx])
			opt.add_item(m_name)
			if m_name == model: cur_sel = idx + 1
		opt.selected = cur_sel
		opt.item_selected.connect(func(sel_idx: int):
			if sel_idx > 0 and sel_idx - 1 < models.size():
				model = str(models[sel_idx - 1])
				le_model.text = model
				_save(false, false)
		)
		put(opt, Rect2(220, y, 620, 52), "c", -1.0, p)
		y += 64.0
	var fold := btn("更多接口格式" + ("  ▲" if more else "  ▼"), "filter", "ghost", Rect2(40, y, 420, 52), func(): more = not more; refresh(), "c", -1.0, p, 21)
	fold.name = "MoreFormats"
	y += 60.0
	if more:
		y = _option(p, y, "接口格式", FORMATS, fmt, func(i): fmt = i; _save(false, false), "ApiFormat", 72.0)
		y = _option(p, y, "补全方式", MODES, mode, func(i): mode = i; _save(false, false), "ApiMode", 72.0)
	else:
		text("当前：OpenAI 兼容 · 聊天补全（支持 DeepSeek、千问、硅基流动、OpenRouter 与各类 OneAPI 公益站）。", Rect2(40, y - 4, 800, 38), 17, "muted", 600, "c", p)
		y += 38.0
	y = maxf(y + 6.0, 588.0)
	var save := btn("保存修改" if profile_id != "" else "保存此配置", "save", "secondary", Rect2(40, y, 250, 76), func(): _save(true, false), "c", -1.0, p, 22)
	save.center_text = true; save.name = "Save"
	var save_new := btn("存为新配置", "add", "secondary", Rect2(304, y, 240, 76), func(): _save(true, true), "c", -1.0, p, 22)
	save_new.center_text = true; save_new.name = "SaveAsNew"
	var test := btn("测试连接", "tri_right", "primary", Rect2(558, y, 282, 76), func(): _save(false, false); Game.test_connection(), "c", -1.0, p, 23)
	test.name = "Test"
	dot = Control.new(); put(dot, Rect2(40, y + 102, 26, 26), "c", -1.0, p)
	dot.draw.connect(func(): dot.draw_circle(Vector2(13, 13), 10, UiHub.c("accent" if Game.connected() else "muted")))
	status_label = text("", Rect2(80, y + 86, 760, 58), 20, "ink", 650, "c", p)
	_show_status()
	var nxt: String = params.get("next", "")
	var nxt_p: Dictionary = params.get("next_params", {})
	if nxt != "":
		var go := btn("保存并继续", "next", "primary", Rect2(1460, 960, 400, 90), func(): _save(false, false); root.go(nxt, nxt_p, "wipe"), "c", 0.2, null, 30)
		go.name = "Continue"; go.arrow = true
		if params.get("first", false):
			var skip_text := "先选出身，稍后连接"
			var skip := btn(skip_text, "skip", "secondary", Rect2(980, 960, 460, 90), func(): root.go(nxt, nxt_p, "wipe"), "c", 0.25, null, 24)
			skip.name = "SkipDemo"

func _fetch_models() -> void:
	if url.strip_edges() == "":
		if is_instance_valid(status_label):
			status_label.text = "拉取失败：请先填写有效的 API 地址"
		UiHub.sfx("warn")
		return
	_save(false, false)
	if is_instance_valid(status_label):
		status_label.text = "正在向所填 API 拉取可用模型列表…"
	Game.list_models()

func _field(p: Control, y: float, label: String, hint: String, value: String, cb: Callable, n: String, step_y := 88.0) -> float:
	text(label, Rect2(40, y, 200, 60), 25, "ink", 750, "c", p)
	var le := LineEdit.new(); le.name = n; le.placeholder_text = hint; le.text = value
	le.text_changed.connect(cb)
	put(le, Rect2(220, y, 620, 60), "c", -1.0, p)
	return y + step_y

func _option(p: Control, y: float, label: String, items: Array, sel: int, cb: Callable, n: String, step_y := 84.0) -> float:
	text(label, Rect2(40, y, 200, 58), 24, "ink", 750, "c", p)
	var o := OptionButton.new(); o.name = n
	for it in items: o.add_item(it[1])
	o.selected = sel; o.item_selected.connect(cb)
	put(o, Rect2(220, y, 620, 58), "c", -1.0, p)
	return y + step_y

func _save(say := true, as_new := false) -> void:
	var payload := {
		"name": profile_name.strip_edges(),
		"format": FORMATS[fmt][0],
		"mode": MODES[mode][0],
		"url": url.strip_edges(),
		"key": key.strip_edges(),
		"model": model.strip_edges(),
		"as_new": as_new,
	}
	if not as_new and profile_id != "":
		payload["id"] = profile_id
	Game.set_connection(payload)
	profile_id = String(Game.connection.get("profile_id", profile_id))
	profile_name = String(Game.connection.get("profile_name", profile_name))
	key = ""
	if say: UiHub.sfx("save")

func _show_status() -> void:
	if not is_instance_valid(status_label): return
	var c: Dictionary = Game.connection
	var words := {"none": "尚未连接", "testing": "正在检查…", "ok": "已连接", "fail": "连接失败", "pending": "还测不了"}
	var msg: String = c.get("message", "")
	status_label.text = String(words.get(c.get("status", "none"), "尚未连接")) + ("：" + msg if msg != "" else "")
	if is_instance_valid(dot): dot.queue_redraw()

func _on_game(part: String) -> void:
	if part == "connection":
		var cur_pid := String(Game.connection.get("profile_id", ""))
		if cur_pid != "" and cur_pid != _last_loaded_id and _last_loaded_id != "__new__":
			_sync_fields_from_active(false)
			refresh(false)
			return
		_show_status()
		var cur_models: Array = Game.connection.get("models", [])
		if not cur_models.is_empty():
			var opt: OptionButton = find_child("ModelSelector", true, false)
			if opt == null:
				refresh()
			else:
				opt.clear()
				opt.add_item("▼ 点击直接选用从服务商拉取的模型（共 %d 个）" % cur_models.size())
				var cur_sel := 0
				for idx in range(cur_models.size()):
					var m_name := str(cur_models[idx])
					opt.add_item(m_name)
					if m_name == model: cur_sel = idx + 1
				opt.selected = cur_sel
