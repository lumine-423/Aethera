extends "res://scripts/ui/ui_screen.gd"
## 资料库: 角色 / 国家 / 地区 / 世界观 / 魔物 (original card copy, 文案/资料库.js + worldbook 魔物 entries),
## plus doors to 世界地图, 事件档案 and 艾瑟拉的忠告. All regions stay; characters = contest cast only.
## 魔物分包是「魔物图鉴」：异危 / 八地区分组，左列缩略图索引，右侧大幅插图 + 条目正文，
## 数据来自 data/content/monster_codex.json（tools/build_monster_codex.py 从 worldbook/魔物 与 assets/monsters 生成）。

var group := "character"
var picked := 0
var page := 0
var mgroup := 0       ## 图鉴分组：0..7 = 异危 + 八地区，末位 = 总纲
var mview := -1       ## 全屏插图查看序号（-1 = 未打开）
var viewer: Control   ## 全屏插图 / 地区志事弹层
var lore := false
const PER := 8
const CODEX_PER := 5

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
	if group == "monster":
		_build_codex()
		restore_overlays()
		return
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
		return []
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

# ---------------------------------------------------------------- 魔物图鉴

func _codex_groups() -> Array:
	return Data.monster_codex().get("groups", [])

func _codex_is_summary() -> bool:
	return mgroup >= _codex_groups().size()

func _codex_entries() -> Array:
	var gs := _codex_groups()
	if mgroup < 0 or mgroup >= gs.size(): return []
	return gs[mgroup].get("entries", [])

## 分组芯片（异危 + 八地区）＋ 总纲，3 列 × N 行排布
func _build_codex() -> void:
	var codex := Data.monster_codex()
	var gs: Array = codex.get("groups", [])
	var summary: Dictionary = codex.get("summary", {})
	if gs.is_empty():
		var empty_p := plate(Rect2(400, 220, 1280, 360), {"shape": "cut", "slant": 32, "corner": "tr", "hatch": true}, "c", 0.06)
		empty_p.name = "ArchiveEmptyPanel"
		icon("book", Rect2(604, 52, 72, 72), "muted", "c", empty_p)
		text("图鉴数据缺失：请运行 rolecard-rpg/tools/build_monster_codex.py 重新生成。", Rect2(120, 150, 1040, 60), 24, "muted", 700, "c", empty_p, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var total := int(codex.get("total", 0))
	text("魔物图鉴 · 全图鉴 %d 种（8 尊异危 ＋ 106 种常规）" % total, Rect2(380, 116, 520, 30), 18, "muted", 700)
	var chips := gs.size() + (1 if not summary.is_empty() else 0)
	for i in range(chips):
		var idx := i
		var is_sum := idx >= gs.size()
		var cap := String(summary.get("name", "总纲")) if is_sum else String(gs[idx].get("name", ""))
		var cb := func(): mgroup = idx; picked = 0; page = 0; refresh(false)
		var chip := btn(cap, "book" if is_sum else "burst", "chip", Rect2(380 + (idx % 3) * 170, 152 + (idx / 3) * 54, 158, 48), cb, "c", 0.03 * idx, null, 20)
		chip.selected = mgroup == idx; chip.slant = 16; chip.name = "CodexChip%d" % idx
	if _codex_is_summary():
		_codex_summary(summary)
		return
	var cur: Dictionary = gs[mgroup]
	var entries: Array = _codex_entries()
	text("%s · %s" % [String(cur.get("name", "")), String(cur.get("subtitle", ""))], Rect2(380, 372, 520, 26), 17, "muted", 700)
	var pages := maxi(1, int(ceil(entries.size() / float(CODEX_PER))))
	page = clampi(page, 0, pages - 1)
	picked = clampi(picked, 0, maxi(0, entries.size() - 1))
	for k in range(CODEX_PER):
		var i := page * CODEX_PER + k
		if i >= entries.size(): break
		var it: Dictionary = entries[i]
		var row := btn("", "", "row", Rect2(380, 400 + k * 104, 520, 96), func(): picked = i; refresh(), "c", 0.05 + k * 0.03, null, 24)
		row.selected = i == picked; row.arrow = false; row.divider = false; row.name = "CodexRow%d" % k
		var thumb := W.Portrait.new(); thumb.kind = "cg"; thumb.frame = false; thumb.name = "CodexThumb%d" % k
		put(thumb, Rect2(10, 10, 76, 76), "c", -1.0, row)
		var res := String(it.get("res", ""))
		if res != "" and ResourceLoader.exists(res): thumb.set_texture(load(res), false)
		text(String(it.get("name", "")), Rect2(98, 8, 340, 40), 24, "ink", 800, "c", row)
		text("危险等级 %s" % String(it.get("danger", "—")), Rect2(98, 50, 340, 28), 18, "muted", 700, "c", row)
	if pages > 1:
		var prev := btn("", "back", "icon", Rect2(380, 940, 90, 60), func(): page = (page - 1 + pages) % pages; picked = page * CODEX_PER; refresh(), "c")
		prev.name = "CodexPrev"
		text("%d / %d" % [page + 1, pages], Rect2(480, 940, 200, 60), 22, "muted", 700, "c", null, HORIZONTAL_ALIGNMENT_CENTER)
		var nxt := btn("", "next", "icon", Rect2(690, 940, 90, 60), func(): page = (page + 1) % pages; picked = page * CODEX_PER; refresh(), "c")
		nxt.name = "CodexNext"
	if entries.is_empty():
		text("本区暂无图鉴条目", Rect2(380, 400, 520, 60), 24, "muted", 700)
		return
	_codex_detail(entries[picked], cur)

func _codex_body(it: Dictionary) -> String:
	var parts: Array = []
	if it.get("kind", "") == "special" and String(it.get("note", "")) != "":
		parts.append("〔出没区域〕\n" + String(it.get("note", "")))
	for row in it.get("rows", []):
		parts.append("〔%s〕\n%s" % [String(row[0]), String(row[1])])
	return "\n\n".join(parts)

## 右侧条目页：大幅透明插图（点击放大）＋ 名称 / 危险等级 / 条目正文
func _codex_detail(it: Dictionary, cur: Dictionary) -> void:
	var p := plate(Rect2(940, 130, 950, 900), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true, "dots": true}, "c", 0.12)
	p.name = "MonsterDetail"
	var res := String(it.get("res", ""))
	var frame_btn := btn("", "", "secondary", Rect2(24, 34, 386, 534), func(): mview = picked; restore_overlays(), "c", -1.0, p, 22)
	frame_btn.name = "MonsterArtFrame"; frame_btn.slant = 24; frame_btn.press_sfx = "open_book"
	frame_btn.tooltip_text = "点击查看全屏插图"
	var art := W.Portrait.new(); art.kind = "cg"; art.frame = false; art.name = "MonsterArt"
	put(art, Rect2(12, 12, 362, 510), "c", -1.0, frame_btn)
	if res != "" and ResourceLoader.exists(res): art.set_texture(load(res), false)
	var is_special := String(it.get("kind", "")) == "special"
	text("危险等级 " + String(it.get("danger", "—")), Rect2(24, 578, 386, 34), 20, "accent", 850, "c", p, HORIZONTAL_ALIGNMENT_CENTER)
	text("出没区域 · " + String(it.get("note", "")), Rect2(24, 612, 386, 30), 18, "muted", 700, "c", p, HORIZONTAL_ALIGNMENT_CENTER)
	text(String(it.get("title", it.get("name", ""))), Rect2(436, 26, 480, 104), 36, "ink", 850, "c", p)
	var scroll := ScrollContainer.new(); p.add_child(scroll); scroll.position = Vector2(436, 146); scroll.size = Vector2(480, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.name = "MonsterRowsScroll"
	var l := Lbl.new(); l.setup(_codex_body(it), 22, "ink", 600); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 462; scroll.add_child(l)
	if not is_special:
		var lore_btn := btn("本区志事", "book", "chip", Rect2(436, 742, 220, 64), func(): lore = true; restore_overlays(), "c", -1.0, p, 22)
		lore_btn.name = "MonsterLoreBtn"

func _codex_summary(summary: Dictionary) -> void:
	var p := plate(Rect2(940, 130, 950, 900), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true, "dots": true}, "c", 0.12)
	p.name = "MonsterDetail"
	text(String(summary.get("name", "图鉴总纲")), Rect2(60, 34, 830, 70), 40, "ink", 850, "c", p)
	var scroll := ScrollContainer.new(); p.add_child(scroll); scroll.position = Vector2(60, 120); scroll.size = Vector2(830, 720)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.name = "MonsterSummaryScroll"
	var l := Lbl.new(); l.setup(String(summary.get("body", "")), 24, "ink", 600); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 800; scroll.add_child(l)

## 重建界面后恢复已打开的插图 / 志事弹层
func restore_overlays() -> void:
	if mview >= 0: _open_monster_view(mview)
	elif lore: _open_lore()

func _open_monster_view(k: int) -> void:
	var entries: Array = _codex_entries()
	if k < 0 or k >= entries.size(): mview = -1; return
	mview = k
	if is_instance_valid(viewer): viewer.queue_free()
	viewer = Control.new(); viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(viewer); viewer.size = size; viewer.name = "MonsterViewer"
	var bg := ColorRect.new(); bg.color = UiHub.c("background"); viewer.add_child(bg); bg.size = size
	var art := W.Portrait.new(); art.kind = "cg"; art.frame = false; art.name = "MonsterViewArt"
	viewer.add_child(art); art.position = Vector2.ZERO; art.size = size
	var res := String(entries[k].get("res", ""))
	if res != "" and ResourceLoader.exists(res): art.set_texture(load(res), false)
	var box := Control.new(); box.mouse_filter = Control.MOUSE_FILTER_IGNORE; viewer.add_child(box); box.size = size
	var close := Btn.new(); close.setup("", "close", "icon"); box.add_child(close); close.position = Vector2(size.x - 130, 30); close.size = Vector2(96, 70)
	close.pressed.connect(close_overlays); close.press_sfx = "none"; close.name = "MonsterViewClose"
	var prev := Btn.new(); prev.setup("", "back", "icon"); prev.press_sfx = "none"; box.add_child(prev); prev.position = Vector2(30, size.y * 0.5 - 40); prev.size = Vector2(90, 80)
	prev.pressed.connect(func(): _monster_step(-1)); prev.name = "MonsterViewPrev"
	var nxt := Btn.new(); nxt.setup("", "next", "icon"); nxt.press_sfx = "none"; box.add_child(nxt); nxt.position = Vector2(size.x - 120, size.y * 0.5 - 40); nxt.size = Vector2(90, 80)
	nxt.pressed.connect(func(): _monster_step(1)); nxt.name = "MonsterViewNext"
	var cap := Plate.new(); cap.slant = 24; cap.stripe = "left"; box.add_child(cap); cap.position = Vector2(60, size.y - 120); cap.size = Vector2(620, 80)
	var it: Dictionary = entries[k]
	var l := Lbl.new(); l.setup("%s   ·   危险等级 %s" % [String(it.get("title", it.get("name", ""))), String(it.get("danger", "—"))], 28, "ink", 800)
	cap.add_child(l); l.position = Vector2(40, 0); l.size = Vector2(560, 80); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not UiHub.reduced_motion:
		viewer.modulate.a = 0.0; viewer.create_tween().tween_property(viewer, "modulate:a", 1.0, 0.25)

func _monster_step(d: int) -> void:
	var entries: Array = _codex_entries()
	if entries.is_empty(): return
	UiHub.sfx("paper", 1.0 if d > 0 else 0.9)
	_open_monster_view((mview + d + entries.size()) % entries.size())

## 地区志事 / 异危档案：把 worldbook 原文长条目铺开阅读
func _open_lore() -> void:
	lore = true
	if is_instance_valid(viewer): viewer.queue_free()
	viewer = Control.new(); viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(viewer); viewer.size = size; viewer.name = "MonsterLoreViewer"
	var bg := ColorRect.new(); bg.color = Color(0.02, 0.02, 0.03, 0.82); viewer.add_child(bg); bg.size = size
	var p := plate(Rect2(240, 120, 1440, 840), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true, "dots": true}, "c", -1.0, viewer)
	p.name = "MonsterLorePanel"
	var cur: Dictionary = _codex_groups()[mgroup] if not _codex_is_summary() else {}
	var title := String(cur.get("name", "图鉴总纲"))
	text(title, Rect2(60, 30, 1160, 70), 38, "ink", 850, "c", p)
	var close := btn("", "close", "icon", Rect2(1300, 30, 96, 70), func(): close_overlays(), "c", -1.0, p)
	close.name = "MonsterLoreClose"
	var body := _lore_text(cur)
	var scroll := ScrollContainer.new(); p.add_child(scroll); scroll.position = Vector2(60, 120); scroll.size = Vector2(1310, 690)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.name = "MonsterLoreScroll"
	var l := Lbl.new(); l.setup(body, 24, "ink", 600); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 1280; scroll.add_child(l)

## 地区志事正文：取原卡 library.monsters 里的地区长条目，整理成可读排版；找不到时退回条目摘要
func _lore_text(cur: Dictionary) -> String:
	var name := String(cur.get("name", ""))
	for m in Data.content().library.monsters:
		var t := String(m.get("title", ""))
		if name != "" and (t == name + "魔物" or t == name or t.begins_with(name)):
			return _format_lore(String(m.get("body", "")))
	var parts: Array = []
	for e in cur.get("entries", []):
		parts.append("◆ %s（%s）\n%s" % [String(e.get("name", "")), String(e.get("danger", "—")), String(e.get("rows", [["", ""]])[0][1])])
	if String(cur.get("note", "")) != "": parts.append(String(cur.get("note", "")))
	return "\n\n".join(parts)

## 把世界书原文整理成图鉴志事版式：去掉 XML 包裹标签，条目名加 ◆，半角冒号换中文冒号
func _format_lore(raw: String) -> String:
	var out: Array = []
	for line in raw.split("\n"):
		var s := String(line).strip_edges()
		if s == "" or s.begins_with("<"): continue
		if s.ends_with(":"):
			var t := s.substr(0, s.length() - 1).strip_edges()
			if t.begins_with("魔物图鉴"):
				out.append("《" + t.trim_prefix("魔物图鉴·").strip_edges() + "》")
			else:
				out.append("\n◆ " + t)
			continue
		var colon := s.find(":")
		if colon > 0:
			s = s.substr(0, colon).strip_edges() + "：" + s.substr(colon + 1).strip_edges()
		out.append("　" + s)
	return "\n".join(out)

func close_overlays() -> void:
	mview = -1; lore = false
	if is_instance_valid(viewer): viewer.queue_free()

func on_back() -> bool:
	if is_instance_valid(viewer):
		if lore and mview < 0: UiHub.sfx("close_book")
		close_overlays(); return true
	return false
