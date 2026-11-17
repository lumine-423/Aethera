extends "res://scripts/ui/ui_screen.gd"
## 启动访问验证：首次启动输入一次正确密码后记住本机，随后弹出使用声明公告。

var pwd_draft := ""
var pwd_visible := false
var err_msg := ""
var pwd_edit: LineEdit
var err_lbl: Label

func build() -> void:
	uses_backdrop = true
	backdrop_style = "plain"
	decor(116, Rect2(Vector2.ZERO, size), 0.35)

	var card := plate(Rect2(500, 220, 920, 620), {"shape": "cut", "slant": 34, "corner": "tr", "hatch": true}, "c", 0.04)
	card.name = "GateCard"
	icon("lock", Rect2(44, 34, 42, 42), "accent", "c", card)
	header("《艾瑟拉》访问验证", Rect2(102, 26, 770, 58), 34, "c", card)

	var lead := text("首次启动需输入访问密码，验证通过后将记住本机；随后将弹出使用声明公告。", Rect2(54, 108, 812, 68), 22, "muted", 600, "c", card)
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	text("访问密码", Rect2(54, 214, 150, 62), 26, "ink", 800, "c", card)
	pwd_edit = LineEdit.new()
	pwd_edit.name = "GatePasswordInput"
	pwd_edit.secret = not pwd_visible
	pwd_edit.placeholder_text = "请输入访问密码（区分字母大小写）"
	pwd_edit.text = pwd_draft
	pwd_edit.text_changed.connect(func(t: String) -> void:
		pwd_draft = t
		if err_msg != "":
			err_msg = ""
			if is_instance_valid(err_lbl): err_lbl.text = ""
	)
	pwd_edit.text_submitted.connect(func(_t: String): _submit())
	put(pwd_edit, Rect2(208, 214, 578, 62), "c", -1.0, card)

	var eye := btn("", "eye_off" if pwd_visible else "eye", "icon", Rect2(796, 214, 70, 62), func():
		pwd_visible = not pwd_visible
		if is_instance_valid(pwd_edit): pwd_edit.secret = not pwd_visible
		refresh(false)
	, "c", -1.0, card)
	eye.name = "GateTogglePwd"
	eye.tooltip_text = "显示 / 隐藏密码内容"

	err_lbl = text(err_msg, Rect2(208, 290, 658, 44), 21, "accent", 750, "c", card)
	err_lbl.name = "GateErrorLabel"

	var quit_b := btn("退出游戏", "power", "secondary", Rect2(54, 386, 250, 78), func():
		root.confirm_quit()
	, "c", -1.0, card, 23)
	quit_b.name = "GateQuitBtn"

	var ok_b := btn("确认进入", "confirm", "primary", Rect2(546, 386, 320, 78), func():
		_submit()
	, "c", -1.0, card, 25)
	ok_b.name = "GateSubmitBtn"
	ok_b.center_text = true

	var line := Control.new(); put(line, Rect2(54, 496, 812, 2), "c", -1.0, card)
	line.draw.connect(func(): line.draw_line(Vector2.ZERO, Vector2(812, 0), UiHub.c("line"), 1.2))
	text("作者：明星荧荧Hotaru 免费发布  ·  严禁任何形式二次传播与商业用途", Rect2(54, 514, 812, 66), 20, "muted", 700, "c", card, HORIZONTAL_ALIGNMENT_CENTER)

	pwd_edit.call_deferred("grab_focus")

func _submit() -> void:
	var entered := pwd_edit.text if is_instance_valid(pwd_edit) else pwd_draft
	pwd_draft = entered
	if root != null and root.has_method("pass_gate") and root.pass_gate(entered):
		UiHub.sfx("confirm")
		return
	err_msg = "密码错误，请核对中文及英文字母大小写后重新输入。"
	if is_instance_valid(err_lbl):
		err_lbl.text = err_msg
	UiHub.sfx("warn")
	toast("访问密码错误，无法进入游戏", "lock")

func on_back() -> bool:
	if root != null:
		root.confirm_quit()
	return true
