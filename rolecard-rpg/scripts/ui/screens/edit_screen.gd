extends "res://scripts/ui/ui_screen.gd"
## 改原文: a separate page for editing any floor's raw text (user decision). Assistant floors show the
## full AI original including tags and <UpdateVariable>, so the player sees exactly what is stored.
## Saving goes through Game.edit_message(); the back end recomputes variables.

const Parser = preload("res://scripts/game/reply_parser.gd")
var current := -1
var draft := ""
var editor: TextEdit
var page := 0
const PER := 9

func build() -> void:
	if current < 0: current = int(params.get("id", Game.last_assistant_id()))
	chrome("改原文")
	decor(87, Rect2(Vector2.ZERO, size), 0.5)
	var msgs: Array = Game.messages
	var left := plate(Rect2(40, 130, 620, 900), {"shape": "cut", "slant": 30, "corner": "tr"}, "c", 0.05)
	header("选择要改的一条", Rect2(30, 20, 560, 56), 28, "c", left)
	var pages := maxi(1, int(ceil(msgs.size() / float(PER))))
	if page == 0 and current >= 0:
		for i in range(msgs.size()):
			if int(msgs[i].id) == current: page = i / PER
	page = clampi(page, 0, pages - 1)
	for k in range(PER):
		var i := page * PER + k
		if i >= msgs.size(): break
		var m: Dictionary = msgs[i]
		var id := int(m.id)
		var preview := Parser.plain(Game.text_of(m)) if m.role == "assistant" else Game.text_of(m)
		preview = preview.replace("\n", " ")
		if preview.length() > 18: preview = preview.substr(0, 17) + "…"
		var b := btn(("你：" if m.role == "user" else "剧情：") + preview, "", "row", Rect2(24, 90 + k * 82, 570, 74), func(): _pick(id), "c", -1.0, left, 18)
		b.selected = id == current; b.arrow = true
	btn("", "back", "icon", Rect2(24, 836, 90, 56), func(): page = (page - 1 + pages) % pages; refresh(false), "c", -1.0, left)
	text("%d / %d" % [page + 1, pages], Rect2(124, 836, 200, 56), 22, "muted", 700, "c", left, HORIZONTAL_ALIGNMENT_CENTER)
	btn("", "next", "icon", Rect2(334, 836, 90, 56), func(): page = (page + 1) % pages; refresh(false), "c", -1.0, left)
	var m2: Dictionary = Game.message(current)
	var p := plate(Rect2(700, 130, 1180, 900), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.1)
	if m2.is_empty():
		text("没有可以修改的内容。", Rect2(40, 40, 900, 60), 28, "muted", 700, "c", p); return
	var head := "AI 原文" if m2.role == "assistant" else "你说的话"
	if m2.role == "assistant" and m2.swipes.size() > 1: head += "（第 %d / %d 版）" % [int(m2.swipe) + 1, m2.swipes.size()]
	header(head, Rect2(30, 20, 1120, 56), 30, "c", p)
	text("标签和变量也在这里，改动保存后会重新计算状态。格式见《AI回复格式约定》。" if m2.role == "assistant" else "保存后，AI 下次回复会读到改过的内容。", Rect2(40, 80, 1100, 40), 19, "muted", 600, "c", p)
	editor = TextEdit.new(); editor.name = "RawEditor"; editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	editor.text = draft if draft != "" else Game.text_of(m2)
	editor.text_changed.connect(func(): draft = editor.text)
	put(editor, Rect2(40, 130, 1100, 640), "c", -1.0, p)
	editor.mouse_filter = Control.MOUSE_FILTER_STOP
	editor.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			var step_lines := 3.0 * maxf(1.0, e.factor)
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				editor.scroll_vertical = maxf(0.0, editor.scroll_vertical - step_lines)
				editor.accept_event()
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				editor.scroll_vertical += step_lines
				editor.accept_event()
	)
	var save := btn("保存修改", "save", "primary", Rect2(40, 790, 320, 86), func(): _save(), "c", -1.0, p, 28)
	save.name = "SaveEdit"; save.center_text = true
	btn("恢复原样", "refresh", "secondary", Rect2(380, 790, 280, 86), func(): draft = ""; refresh(false), "c", -1.0, p, 26).center_text = true
	btn("回到剧情", "tri_left", "secondary", Rect2(860, 790, 280, 86), func(): root.back(), "c", -1.0, p, 26).center_text = true

func _pick(id: int) -> void:
	if id == current: return
	current = id; draft = ""; refresh(false)

func _save() -> void:
	if not is_instance_valid(editor): return
	if editor.text.strip_edges() == "": toast("内容不能为空", "warn"); return
	Game.edit_message(current, editor.text)
	draft = ""; UiHub.sfx("save"); refresh(false)
