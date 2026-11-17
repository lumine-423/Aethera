extends "res://scripts/ui/ui_screen.gd"
## 物品栏 (role-play inventory, kept by user decision). Reads MVU 主角组: 持有物品 / 魔法 / 魔力 /
## 已讨伐异危 from Game.stat. Crafting (刻印工坊) is not in the contest edition.

var tab := "items"
var picked := 0
var page := 0
const ICONS := ["item_crystal", "item_cube", "item_plate", "item_ore", "item_orb", "item_tetra", "item_prism", "item_shards", "item_ring", "item_chip"]

func build() -> void:
	tab = params.get("tab", tab); params.erase("tab")
	chrome("物品栏")
	decor(45, Rect2(Vector2.ZERO, size), 0.6)
	var tabs := [["items", "持有物品", "item_cube"], ["magic", "可用魔法", "comet"], ["status", "本体状态", "person"]]
	var bs: Array = []
	for i in range(tabs.size()):
		var t: Array = tabs[i]
		var b := btn(t[1], t[2], "tab", Rect2(0, 170 + i * g(100), 340, 84), func(): tab = t[0]; picked = 0; page = 0; refresh(false), "l", 0.05 * i)
		b.selected = tab == t[0]; b.slant = 26; b.name = "Tab_" + t[0]
		bs.append(b)
	cursor_for(bs)
	if not Game.changed.is_connected(_on_game): Game.changed.connect(_on_game)
	match tab:
		"magic": _magic()
		"status": _status()
		_: _items()

func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game): Game.changed.disconnect(_on_game)

func _on_game(part: String) -> void:
	if part == "stat": refresh()

func _empty(msg: String) -> void:
	var p := plate(Rect2(420, 380, 1100, 160), {"slant": 30, "stripe": "left", "hatch": true}, "c", 0.1)
	text(msg, Rect2(60, 0, 1000, 160), 30, "muted", 700, "c", p)

func _items() -> void:
	var items: Dictionary = Game.hero().get("持有物品", {})
	var names: Array = items.keys()
	if names.is_empty(): _empty("暂无物品——获得物品后会出现在这里。"); return
	picked = clampi(picked, 0, names.size() - 1)
	page = clampi(page, 0, (names.size() - 1) / 12)
	if picked / 12 != page: picked = page * 12
	for slot in range(mini(names.size() - page * 12, 12)):
		var k := page * 12 + slot
		var n: String = names[k]
		var e: Dictionary = items[n] if items[n] is Dictionary else {}
		var r := Rect2(420 + (slot % 4) * 270, 170 + (slot / 4) * 250, 250, 230)
		var b := Btn.new(); b.variant = "secondary"; b.slant = 24; b.selected = k == picked; b.press_sfx = "select"
		b.name = "Item%d" % k
		put(b, r, "c", 0.05 + slot * 0.03)
		var kk := k
		b.pressed.connect(func(): picked = kk; refresh())
		icon(ICONS[abs(n.hash()) % ICONS.size()], Rect2(70, 24, 110, 110), "ink", "c", b)
		text(n, Rect2(20, 140, 210, 44), 22, "ink", 800, "c", b, HORIZONTAL_ALIGNMENT_CENTER)
		text("×%d" % int(e.get("数量", 1)), Rect2(20, 182, 210, 36), 22, "accent", 800, "c", b, HORIZONTAL_ALIGNMENT_CENTER)
	_pager(names.size(), 12, 1480)
	var sel: String = names[picked]
	var info: Dictionary = items[sel] if items[sel] is Dictionary else {}
	var p := plate(Rect2(1520, 170, 370, 760), {"shape": "cut", "slant": 30, "corner": "tr", "hatch": true}, "r", 0.15)
	icon(ICONS[abs(sel.hash()) % ICONS.size()], Rect2(110, 40, 150, 150), "ink", "c", p)
	text(sel, Rect2(30, 210, 310, 70), 32, "ink", 850, "c", p, HORIZONTAL_ALIGNMENT_CENTER)
	text("数量 %d" % int(info.get("数量", 1)), Rect2(30, 280, 310, 40), 22, "accent", 800, "c", p, HORIZONTAL_ALIGNMENT_CENTER)
	text(String(info.get("描述", "")), Rect2(30, 340, 310, 300), 22, "ink", 600, "c", p)
	var use := btn("在剧情里使用", "chat", "primary", Rect2(30, 660, 310, 76), func(): _use(sel), "c", -1.0, p, 22)
	use.name = "UseItem"; use.tooltip_text = "回到剧情，把“使用这件物品”写进行动框"

func _use(item: String) -> void:
	root.back()
	var s = root.current()
	if s and s.has_method("show_choices"):
		s.show_choices([])
		if is_instance_valid(s.input): s.input.text = "我拿出【%s】，" % item

func _magic() -> void:
	var magic: Dictionary = Game.hero().get("魔法", {})
	if magic.is_empty(): _empty("还没有学会魔法。"); return
	var names: Array = magic.keys()
	page = clampi(page, 0, (names.size() - 1) / 4)
	var y := 170.0
	for n in names.slice(page * 4, mini((page + 1) * 4, names.size())):
		var e: Dictionary = magic[n] if magic[n] is Dictionary else {}
		var p := plate(Rect2(420, y, 1440, 150), {"slant": 30, "stripe": "left", "corner": "br"}, "c", 0.05)
		icon("comet", Rect2(36, 36, 78, 78), "accent", "c", p)
		text(String(n), Rect2(140, 16, 700, 56), 32, "ink", 850, "c", p)
		text("载体：%s" % e.get("载体", "—"), Rect2(140, 76, 500, 40), 22, "muted", 700, "c", p)
		text("耗用 %s" % str(e.get("耗用", "—")), Rect2(1220, 16, 180, 56), 26, "accent", 800, "c", p)
		text(String(e.get("效果", "")), Rect2(640, 70, 760, 70), 22, "ink", 600, "c", p)
		y += 150 + g(20)
	_pager(names.size(), 4, 1860)

func _pager(count: int, capacity: int, right: float) -> void:
	var prev := btn("上一页", "back", "chip", Rect2(420, 950, 200, 64), func(): _page(-1, capacity), "c", -1.0, null, 22)
	prev.name = "InventoryPrev"; prev.disabled = page == 0
	text("%d / %d 页 · 共 %d 项" % [page + 1, ceili(float(count) / capacity), count], Rect2(640, 950, right - 880, 64), 22, "muted", 600, "c", null, HORIZONTAL_ALIGNMENT_CENTER)
	var next := btn("下一页", "tri_right", "chip", Rect2(right - 200, 950, 200, 64), func(): _page(1, capacity), "c", -1.0, null, 22)
	next.name = "InventoryNext"; next.disabled = (page + 1) * capacity >= count

func _page(delta: int, capacity: int) -> void:
	page += delta; picked = page * capacity; refresh()

func _status() -> void:
	var h: Dictionary = Game.hero()
	var p := plate(Rect2(420, 170, 1440, 760), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.05)
	header("本体全状态", Rect2(30, 20, 1380, 54), 30, "c", p)
	var cast_raw = h.get("当前在场角色", [])
	var cast_str := "、".join(PackedStringArray(cast_raw)) if (cast_raw is Array and not cast_raw.is_empty()) else "暂无同行角色"
	var rows := [
		["姓名", Game.persona.get("name", "—")],
		["简介", h.get("简介", "—")],
		["当前地点", h.get("当前地点", "—")],
		["时间", h.get("时间", "—")],
		["当前乐章", h.get("当前BGM", "Main Theme")],
		["在场角色", cast_str],
	]
	for k in range(rows.size()):
		var y := 94.0 + k * g(66)
		text(rows[k][0], Rect2(50, y, 200, 52), 24, "muted", 700, "c", p)
		text(str(rows[k][1]), Rect2(260, y, 1120, 52), 24, "ink", 750, "c", p)
	var y2 := 94.0 + rows.size() * g(66)
	text("魔力", Rect2(50, y2, 200, 52), 24, "muted", 700, "c", p)
	var mana = h.get("魔力", null); var top = h.get("魔力上限", null)
	if typeof(mana) in [TYPE_INT, TYPE_FLOAT] and typeof(top) in [TYPE_INT, TYPE_FLOAT]:
		bar(Rect2(260, y2 + 18, 700, 16), float(mana), maxf(float(top), 1.0), "accent", p)
		text("%d / %d" % [int(mana), int(top)], Rect2(990, y2, 300, 52), 24, "accent", 800, "c", p)
	else:
		text(str(mana) if mana != null else "—", Rect2(260, y2, 700, 52), 24, "ink", 750, "c", p)
	var slain: Array = h.get("已讨伐异危", [])
	text("已讨伐异危", Rect2(50, y2 + g(66), 200, 52), 24, "muted", 700, "c", p)
	text("、".join(PackedStringArray(slain)) if not slain.is_empty() else "暂无", Rect2(260, y2 + g(66), 1120, 52), 24, "ink", 750, "c", p)
