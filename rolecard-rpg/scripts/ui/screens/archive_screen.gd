extends "res://scripts/ui/ui_screen.gd"
## 资料库: 角色 / 国家 / 地区 / 世界观 / 魔物 (original card copy, 文案/资料库.js + worldbook 魔物 entries),
## plus doors to 世界地图, 事件档案 and 艾瑟拉的忠告. All regions stay; characters = contest cast only.

var group := "character"
var picked := 0
var page := 0
const PER := 8

func build() -> void:
	group = params.get("group", group); params.erase("group")
	chrome("资料库")
	decor(41, Rect2(Vector2.ZERO, size), 0.6)
	var lib: Dictionary = Data.content().library
	var raw_groups: Array = lib.groups.duplicate()
	var groups_ui: Array = []
	for gr in raw_groups:
		groups_ui.append({"type": String(gr.type), "name": String(gr.name)})
		if String(gr.type) == "character":
			groups_ui.append({"type": "npc", "name": "重要 NPC"})
	var bs: Array = []
	var gi := 0
	for gr in groups_ui:
		var t: String = gr.type
		var b := btn(gr.name, {"character": "person", "npc": "people", "country": "globe", "region": "pin", "world": "book", "monster": "burst"}.get(t, "book"), "tab", Rect2(0, 132 + gi * g(74), 300, 64), func(): group = t; picked = 0; page = 0; refresh(false), "l", 0.04 * gi, null, 22)
		b.selected = group == t; b.slant = 24; b.name = "Group_" + t
		bs.append(b); gi += 1
	cursor_for(bs)
	var doors := [["旅途手札", "docs", "database"], ["世界地图", "globe", "map"], ["事件档案", "bookmark", "events"], ["艾瑟拉的忠告", "book", "help"]]
	for k in range(doors.size()):
		var d: Array = doors[k]
		var db := btn(d[0], d[1], "secondary", Rect2(0, 640 + k * g(86), 330, 72), func(): root.go(d[2]), "l", 0.2 + 0.04 * k, null, 22)
		db.arrow = true; db.name = "Door_" + d[2]
	var items := _items(lib)
	if items.is_empty():
		var empty_txt := "该角色 / NPC 尚未在主线剧情中邂逅解锁，暂无档案资料。" if group in ["character", "npc"] else "暂无条目"
		var empty_p := plate(Rect2(400, 220, 1280, 360), {"shape": "cut", "slant": 32, "corner": "tr", "hatch": true}, "c", 0.06)
		empty_p.name = "ArchiveEmptyPanel"
		icon("lock" if group in ["character", "npc"] else "book", Rect2(604, 52, 72, 72), "muted", "c", empty_p)
		text(empty_txt, Rect2(120, 150, 1040, 60), 26, "muted", 700, "c", empty_p, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var pages := maxi(1, int(ceil(items.size() / float(PER))))
	page = clampi(page, 0, pages - 1)
	picked = clampi(picked, 0, items.size() - 1)
	for k in range(PER):
		var i := page * PER + k
		if i >= items.size(): break
		var it: Dictionary = items[i]
		var row := btn(it.title, "", "row", Rect2(380, 150 + k * g(100), 520, 86), func(): picked = i; refresh(), "c", 0.05 + k * 0.03, null, 26)
		row.selected = i == picked; row.arrow = true; row.name = "Entry%d" % k
	if pages > 1:
		btn("", "back", "icon", Rect2(380, 960, 90, 60), func(): page = (page - 1 + pages) % pages; picked = page * PER; refresh(), "c")
		text("%d / %d" % [page + 1, pages], Rect2(480, 960, 200, 60), 22, "muted", 700, "c", null, HORIZONTAL_ALIGNMENT_CENTER)
		btn("", "next", "icon", Rect2(690, 960, 90, 60), func(): page = (page + 1) % pages; picked = page * PER; refresh(), "c")
	_detail(items[picked])

func _items(lib: Dictionary) -> Array:
	if group == "monster":
		var out: Array = []
		for m in lib.monsters: out.append({"type": "monster", "title": m.title, "body": m.body})
		return out
	if group == "character" or group == "npc":
		var unlocked := Game.unlocked_ids(true)
		if group == "character":
			return lib.items.filter(func(x):
				var cid := Data.id_of(String(x.get("title", "")))
				return x.type == "character" and cid != "" and not Data.is_npc(cid) and (cid in unlocked))
		return lib.items.filter(func(x):
			var cid := Data.id_of(String(x.get("title", "")))
			return x.type == "character" and cid != "" and Data.is_npc(cid) and (cid in unlocked))
	return lib.items.filter(func(x): return x.type == group)

func _detail(it: Dictionary) -> void:
	var p := plate(Rect2(940, 130, 950, 900), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true, "dots": true}, "c", 0.12)
	var img := W.Portrait.new(); img.frame = false
	var body_y := 380.0
	if it.type == "character":
		var id := Data.id_of(it.title)
		img.kind = "full"
		put(img, Rect2(560, 20, 370, 560), "c", -1.0, p)
		img.show_art(id, "daily", "neutral")
		text(it.title, Rect2(50, 30, 500, 90), 60, "ink", 900, "c", p)
		var y := 140.0
		for f in it.get("fields", []):
			text(f[0], Rect2(50, y, 150, 46), 22, "muted", 700, "c", p)
			text(f[1], Rect2(200, y, 340, 46), 24, "ink", 750, "c", p)
			y += 56
		var cscroll := ScrollContainer.new(); p.add_child(cscroll); cscroll.position = Vector2(50, y + 20); cscroll.size = Vector2(490, maxf(180.0, 840.0 - y))
		cscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; cscroll.name = "BodyScroll"
		var cl := Lbl.new(); cl.setup(it.body, 24, "ink", 600); cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.custom_minimum_size.x = 468; cscroll.add_child(cl)
		return
	if it.type in ["country", "region"]:
		img.kind = "scene"
		put(img, Rect2(50, 30, 850, 330), "c", -1.0, p)
		var s := _scene_for(it.title)
		if s != "": img.set_texture(load(s), false)
	else:
		body_y = 130.0
	header(it.title, Rect2(40, body_y - 10, 860, 60), 36, "c", p)
	var scroll := ScrollContainer.new(); p.add_child(scroll); scroll.position = Vector2(50, body_y + 70); scroll.size = Vector2(850, 820 - body_y - 40)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.name = "BodyScroll"
	var l := Lbl.new(); l.setup(it.body, 24, "ink", 600); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 820; scroll.add_child(l)

func _scene_for(title: String) -> String:
	for s in Data.content().scenes:
		if s.kind == "base" and (s.area == title or title in s.area or s.country == title): return s.res
	return ""
