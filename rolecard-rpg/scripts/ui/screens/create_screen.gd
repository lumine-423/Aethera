extends "res://scripts/ui/ui_screen.gd"
## 个人信息（角色创建）. Field names and hints are the original card copy (文案/开场.js).
## params: origin. 降临 -> Game.new_game() -> story.

var values := {"name": "", "race": "", "appearance": "", "bio": ""}
var edits := {}
var _api_pop: Control

func build() -> void:
	var c: Dictionary = Data.content().create
	var hub: Dictionary = Data.content().hub
	chrome(hub.get("createTitle", "个人信息"))
	decor(71, Rect2(Vector2.ZERO, size), 0.5)
	var draft = params.get("draft", {})
	if draft is Dictionary and not draft.is_empty():
		for dk in ["name", "race", "appearance", "bio"]:
			if draft.has(dk): values[dk] = String(draft[dk])
	var origin_key := String(params.get("origin", "sereth"))
	var origin: Dictionary = {}
	for o in Data.content().origins:
		if o.key == origin_key: origin = o
	var side := plate(Rect2(70, 150, 560, 760), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true, "dots": true}, "c", 0.05)
	text(hub.get("originLabel", "出身"), Rect2(40, 30, 300, 40), 24, "accent", 800, "c", side)
	text(origin.get("formName", ""), Rect2(40, 74, 480, 70), 48, "ink", 900, "c", side)
	text(origin.get("popTag", ""), Rect2(40, 150, 480, 40), 24, "muted", 700, "c", side)
	var pdesc := text(origin.get("popDesc", ""), Rect2(40, 210, 480, 290), 22, "ink", 600, "c", side)
	pdesc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if origin_key == "custom":
		var custom_box := plate(Rect2(36, 514, 488, 212), {"slant": 18, "fill": "surface2", "layered": false, "stripe": "left"}, "c", -1.0, side)
		custom_box.name = "CustomOpeningNotice"
		text("随机动态开局 · 1015年·2月1日", Rect2(44, 14, 424, 34), 21, "accent", 850, "c", custom_box)
		var cn := text("不设定固定开局地点，仅预设时间「1015年·2月1日」。\n降临后将向模型发送前置语，按你右侧填写的人物资料随机生成初始地点与首幕剧情。", Rect2(44, 52, 424, 104), 17, "ink", 600, "c", custom_box)
		cn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if Game.has_configured_api():
			text("API 状态：已就绪，可直接降临生成", Rect2(44, 164, 424, 34), 17, "accent", 750, "c", custom_box)
		else:
			var api_btn := btn("尚未配置 API · 点击前往配置", "settings", "secondary", Rect2(44, 158, 424, 42), func():
				root.go("connect", {"next": "create", "next_params": {"origin": "custom", "draft": values.duplicate()}}, "wipe")
			, "c", -1.0, custom_box, 17)
			api_btn.name = "CreateGoConnectBtn"
			api_btn.center_text = true
	var p := plate(Rect2(680, 150, 1180, 760), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.1)
	var rows := [["name", c.name, c.namePh, false], ["race", c.race, c.racePh, false], ["appearance", c.appearance, c.appearancePh, true], ["bio", c.bio, c.bioPh, true]]
	var y := 40.0
	for row in rows:
		text(row[1], Rect2(40, y, 240, 64), 28, "ink", 800, "c", p)
		var tall: bool = row[3]
		var e: Control
		if tall:
			var te := TextEdit.new(); te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; te.placeholder_text = row[2]; te.text = values[row[0]]
			var k: String = row[0]
			te.text_changed.connect(func(): values[k] = te.text)
			e = te
		else:
			var le := LineEdit.new(); le.placeholder_text = row[2]; le.text = values[row[0]]
			var k2: String = row[0]
			le.text_changed.connect(func(t): values[k2] = t)
			e = le
		e.name = "Field_" + row[0]; edits[row[0]] = e
		var h := 190.0 if tall else 64.0
		put(e, Rect2(280, y, 860, h), "c", -1.0, p)
		y += h + g(28)
	var go := btn(c.get("commit", "降临"), "star4", "primary", Rect2(1460, 940, 400, 96), func(): _commit(), "c", 0.3, null, 34)
	go.name = "Descend"; go.arrow = true
	if edits.has("name"): edits.name.call_deferred("grab_focus")

func _close_api_pop() -> void:
	if is_instance_valid(_api_pop):
		_api_pop.queue_free()
		_api_pop = null

func _open_api_required_pop() -> void:
	_close_api_pop()
	UiHub.sfx("warn")
	_api_pop = Control.new()
	_api_pop.name = "CreateCustomApiPop"
	put(_api_pop, Rect2(Vector2.ZERO, size), "c")
	_api_pop.z_index = 450
	var dim := Button.new()
	dim.flat = true; dim.focus_mode = Control.FOCUS_NONE
	var esb := StyleBoxEmpty.new()
	for sname in ["normal", "hover", "pressed", "focus", "disabled"]:
		dim.add_theme_stylebox_override(sname, esb)
	put(dim, Rect2(Vector2.ZERO, size), "c", -1.0, _api_pop)
	dim.draw.connect(func(): dim.draw_rect(Rect2(Vector2.ZERO, dim.size), Color(0.02, 0.03, 0.05, 0.68)))
	dim.pressed.connect(func(): _close_api_pop())
	var box := plate(Rect2(500, 320, 920, 400), {"shape": "cut", "slant": 34, "corner": "tr", "fill": "surface", "fill_alpha": 0.99, "hatch": true}, "c", -1.0, _api_pop)
	text("「自定义」降临前须配置 API", Rect2(44, 34, 832, 48), 32, "ink", 900, "c", box)
	var m := text("当前出身选择了「自定义」随机开局（时间：1015年·2月1日，地点由模型按你填写的设定随机决定）。\n尚未检测到已配置的 API 地址与模型，请先配置后再降临（已填内容会自动保留）。", Rect2(44, 102, 832, 172), 20, "muted", 600, "c", box)
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var stay_b := btn("返回修改", "back", "secondary", Rect2(44, 298, 250, 68), func(): _close_api_pop(), "c", -1.0, box, 21)
	stay_b.center_text = true
	var go_b := btn("前往配置 API", "next", "primary", Rect2(566, 298, 310, 68), func():
		_close_api_pop()
		root.go("connect", {"next": "create", "next_params": {"origin": "custom", "draft": values.duplicate()}}, "wipe")
	, "c", -1.0, box, 23)
	go_b.arrow = true

func _commit() -> void:
	var origin_key := String(params.get("origin", "sereth"))
	if origin_key == "custom" and not Game.has_configured_api():
		_open_api_required_pop()
		return
	var toasts := {"unnamed": "未署名"}
	var p := {}
	for k in values: p[k] = String(values[k]).strip_edges()
	if p.name == "": p.name = toasts.unnamed
	UiHub.sfx("start"); UiHub.haptic(20)
	Game.new_game(p, origin_key)
	root.go("loading", {"next": "story", "label": Data.content().hub.get("descend", "降临")}, "wipe", "reset")
