extends "res://scripts/ui/ui_screen.gd"
## 事件档案 (原卡「档案馆」): 进行中 / 即将发生 / 已归档 / 全部. Event text is original card copy,
## filtered to the contest cast; state comes from MVU 剧情事件 (当前触发事件 / 已完成事件).
## Events the AI starts on its own (not in the archive) also appear under 进行中.

var view := ""
var picked := 0
var page := 0
const PAGE_SIZE := 9

func build() -> void:
	if view == "": view = "live" if not Game.events().get("当前触发事件", {}).is_empty() else "soon"
	chrome("事件档案")
	decor(53, Rect2(Vector2.ZERO, size), 0.6)
	var arc: Dictionary = Data.content().archive
	var bs: Array = []
	var k := 0
	for v in arc.views:
		var vid: String = v.id
		var b := btn(v.name, {"live": "play", "soon": "bookmark", "done": "archive", "all": "docs"}.get(vid, "docs"), "tab", Rect2(0, 150 + k * g(96), 360, 82), func(): view = vid; picked = 0; page = 0; refresh(false), "l", 0.04 * k, null, 24)
		b.selected = view == vid; b.slant = 24; b.name = "View_" + vid
		bs.append(b); k += 1
	cursor_for(bs)
	var list := _list()
	if list.is_empty():
		var p := plate(Rect2(440, 380, 1000, 150), {"slant": 30, "stripe": "left", "hatch": true}, "c", 0.1)
		text({"live": "现在没有进行中的事件。", "done": "还没有完成的事件。"}.get(view, "暂无事件。"), Rect2(60, 0, 900, 150), 30, "muted", 700, "c", p)
		return
	picked = clampi(picked, 0, list.size() - 1)
	page = clampi(page, 0, (list.size() - 1) / PAGE_SIZE)
	if picked / PAGE_SIZE != page: picked = page * PAGE_SIZE
	for slot in range(mini(list.size() - page * PAGE_SIZE, PAGE_SIZE)):
		var i := page * PAGE_SIZE + slot
		var e: Dictionary = list[i]
		var row := btn(e.title, "", "row", Rect2(420, 150 + slot * 94, 560, 84), func(): picked = i; refresh(), "c", 0.05 + slot * 0.03, null, 24)
		row.selected = i == picked; row.arrow = true; row.badge = {"live": "进行中", "done": "已完成"}.get(e.state, ""); row.name = "Event%d" % i
	_detail(list[picked])
	var prev := btn("上一页", "back", "chip", Rect2(420, 1012, 170, 54), func(): _page(-1), "c", -1.0, null, 20)
	prev.name = "EventsPrev"; prev.disabled = page == 0
	text("%d / %d 页 · 共 %d 项" % [page + 1, ceili(float(list.size()) / PAGE_SIZE), list.size()], Rect2(595, 1012, 210, 54), 19, "muted", 600, "c", null, HORIZONTAL_ALIGNMENT_CENTER)
	var next := btn("下一页", "tri_right", "chip", Rect2(810, 1012, 170, 54), func(): _page(1), "c", -1.0, null, 20)
	next.name = "EventsNext"; next.disabled = (page + 1) * PAGE_SIZE >= list.size()

func _page(delta: int) -> void:
	page += delta; picked = page * PAGE_SIZE; refresh()

func _list() -> Array:
	var ev: Dictionary = Game.events()
	var live: Dictionary = ev.get("当前触发事件", {})
	var done: Array = ev.get("已完成事件", [])
	var out: Array = []
	var seen := {}
	for e in Data.content().archive.events:
		var st := "live" if live.has(e.title) else ("done" if e.title in done else "soon")
		var row: Dictionary = e.duplicate(); row["state"] = st
		if live.has(e.title): row["now"] = live[e.title]
		seen[e.title] = true
		if view == "all" or view == st: out.append(row)
	for name in live:
		if seen.has(name): continue
		if view in ["live", "all"]: out.append({"title": name, "state": "live", "now": live[name], "place": "", "who": [], "detail": "", "impact": ""})
	for name in done:
		if seen.has(name) or live.has(name): continue
		if view in ["done", "all"]: out.append({"title": name, "state": "done", "place": "", "who": [], "detail": "", "impact": ""})
	return out

func _detail(e: Dictionary) -> void:
	var p := plate(Rect2(1010, 130, 880, 900), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true, "dots": true}, "c", 0.12)
	text(e.title, Rect2(44, 30, 800, 80), 46, "ink", 900, "c", p)
	var meta: PackedStringArray = []
	if e.get("place", "") != "": meta.append("地点：" + String(e.place))
	var who: Array = e.get("who", [])
	if not who.is_empty(): meta.append("人物：" + "、".join(PackedStringArray(who)))
	meta.append({"live": "进行中", "done": "已归档", "soon": "即将发生"}.get(e.state, ""))
	text("    ".join(meta), Rect2(44, 110, 800, 44), 21, "accent", 750, "c", p)
	var y := 170.0
	if e.has("now"):
		var nowp := plate(Rect2(44, y, 790, 80), {"slant": 20, "fill": "surface2", "layered": false, "stripe": "left"}, "c", -1.0, p)
		text("现在：" + String(e.now), Rect2(30, 0, 740, 80), 22, "ink", 700, "c", nowp)
		y += 100
	var scroll := ScrollContainer.new(); p.add_child(scroll); scroll.position = Vector2(44, y); scroll.size = Vector2(800, 860 - y)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := String(e.get("detail", e.get("brief", "")))
	if e.get("impact", "") != "": body += "\n\n【触发条件】\n· " + String(e.impact)
	var l := Lbl.new(); l.setup(body if body.strip_edges() != "" else "这是剧情中新出现的事件，详情会随故事展开。", 23, "ink", 600)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 780; scroll.add_child(l)
