extends "res://scripts/ui/ui_screen.gd"
## 启动声明与来源公告：密码验证通过后弹出，确认后直接进入开场动画。
const NOTICE := "res://data/legal_notice.json"
var body_scroll: ScrollContainer

func build() -> void:
	uses_backdrop = true
	backdrop_style = "plain"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NOTICE))
	var review := bool(params.get("review", false))
	header("艾瑟拉  /  " + String(data.get("title", "使用与版权声明")), Rect2(100, 52, 1680, 76), 36)
	text("作者：明星荧荧Hotaru 免费发布  ·  " + String(data.get("version", "")) + "  ·  严禁二次传播与商用", Rect2(110, 128, 1680, 40), 22, "accent", 750)
	decor(116, Rect2(Vector2.ZERO, size), 0.3)
	var page := plate(Rect2(90, 186, 1740, 676), {"shape":"cut", "slant":24, "corner":"tr"}, "c")
	body_scroll = ScrollContainer.new(); body_scroll.name = "NoticeScroll"
	page.add_child(body_scroll); body_scroll.position = Vector2(42, 26); body_scroll.size = Vector2(1654, 622)
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 20); body_scroll.add_child(col)
	paragraph(col, String(data.get("intro", "")), true)
	section(col, "使用与禁止条款", String(data.get("terms", "")))
	if data.has("preset") and String(data.get("preset", "")) != "":
		section(col, "预设来源（创世回廊 / kunlun）", String(data.get("preset", "")))
	section(col, "音乐与音效来源", String(data.get("music", "")))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/music_manifest.json"))
	var titles: PackedStringArray = []
	for track in manifest.get("tracks", []): titles.append(String(track.title))
	for rt in manifest.get("reserved_tracks", []): titles.append(String(rt.title))
	paragraph(col, "收录曲目一览（共 %d 首）：" % titles.size() + "、".join(titles))
	section(col, "美术与角色", String(data.get("art", "")))
	section(col, "字体与音效依赖", String(data.get("other", "")))
	section(col, "程序组件与开源许可", "")
	for item in data.get("components", []):
		paragraph(col, String(item.name) + "  ·  " + String(item.license), true)
		paragraph(col, String(item.purpose) + "\n" + String(item.url))
	section(col, "本地数据说明", String(data.get("privacy", "")))
	var footer_hint := "点击右侧确认后将进入游戏标题页。" if UiHub.opening_seen else "点击右侧确认后将直接进入开场动画。"
	if review: footer_hint = "查看结束后点击右侧按钮返回。"
	text(footer_hint, Rect2(110, 882, 1650, 44), 22, "muted")
	var confirm := btn("已阅读，返回" if review else "我已阅读，进入游戏", "check", "primary", Rect2(1170, 962, 620, 82), func():
		if review: root.back("none")
		else: root.acknowledge_notice(), "c", -1.0, null, 28)
	confirm.name = "NoticeConfirm"; confirm.center_text = true
	if not review:
		btn("退出游戏", "power", "secondary", Rect2(110, 962, 360, 82), func(): root.confirm_quit(), "c", -1.0, null, 26)

func paragraph(col: VBoxContainer, value: String, bold := false) -> void:
	if value == "": return
	var label := Lbl.new(); label.setup(value, 25 if bold else 23, "accent" if bold else "ink", 800 if bold else 500)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(label)

func section(col: VBoxContainer, title: String, value: String) -> void:
	paragraph(col, title, true); paragraph(col, value)

func on_back() -> bool:
	if bool(params.get("review", false)): return false
	toast("请先确认声明公告，或选择退出游戏。", "info")
	return true
