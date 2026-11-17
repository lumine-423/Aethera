extends "res://scripts/ui/ui_screen.gd"
## 艾瑟拉的忠告: world primer from the original card (文案/忠告.js). The 关于本卡 tab is left out of
## the contest edition; the text itself is not rewritten.

var tab := ""

func build() -> void:
	var man: Dictionary = Data.content().manual
	var tabs: Array = man.tabs
	if tab == "": tab = tabs[0].id
	chrome(Data.content().hub.get("manualTitle", "艾瑟拉的忠告"))
	btn("使用与来源公告", "book", "secondary", Rect2(1120, 34, 510, 64), func(): root.go("notice", {"review":true}), "rt", -1.0, null, 24)
	decor(97, Rect2(Vector2.ZERO, size), 0.6)
	var bs: Array = []
	for i in range(tabs.size()):
		var tid: String = tabs[i].id
		var b := btn(tabs[i].label, "book", "tab", Rect2(0, 160 + i * g(100), 340, 84), func(): tab = tid; refresh(false), "l", 0.05 * i)
		b.selected = tab == tid; b.slant = 26; b.name = "Tab_" + tid
		bs.append(b)
	cursor_for(bs)
	var p := plate(Rect2(420, 130, 1460, 900), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true}, "c", 0.08)
	var scroll := ScrollContainer.new(); p.add_child(scroll); scroll.position = Vector2(60, 40); scroll.size = Vector2(1360, 820)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.name = "ManualScroll"
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", int(g(26))); col.custom_minimum_size.x = 1320; scroll.add_child(col)
	for blk in man.get(tab, []):
		var h := Lbl.new(); h.setup(blk.h, 34, "accent", 850); col.add_child(h)
		for para in blk.p:
			var l := Lbl.new(); l.setup(String(para).replace("**", ""), 25, "ink", 600)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 1300; col.add_child(l)
