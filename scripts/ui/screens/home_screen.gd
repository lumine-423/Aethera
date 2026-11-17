extends "res://scripts/ui/ui_screen.gd"
## 功能主页 (concept 07, mystic geometry). Code-drawn; replaces the old image-sliced home.tscn in the
## full version (the sample scene itself stays untouched for its old checks).
## Right: one great construction circle carrying 剧情 (crescent emblem) / 资料库 / 作战 / 仓库 and a
## pill row 角色 | 地图 | 刻印 | 事件档案. Left: the showcase character's full art; bottom-left card with
## name, 切换, 好感度. Top: power (back to title), 设置, day / night.

## 2026-11-17: the page now sits in the interactive dream room (scripts/ui/home_room.gd). All UI is
## see-through glass in day and night, nothing follows the pointer,
## and an eye key next to power hides every UI piece and the character so the whole room shows.

const Room = preload("res://scripts/ui/home_room.gd")
const GLASS_DAY := 0.45
const GLASS_NIGHT := 0.66
## No pointer float on the home page (user 2026-11-17: removed, it felt laggy). UI, character and
## room all stay still; layers only slide when the eye key hides / shows the UI.

var showcase := ""
var ring: Control
var art: Control
var room: Control
var layers := {}
var hide_btn: Button
var ui_hidden := false
var _hide_tween: Tween

func open(owner_root: Node, p: Dictionary) -> void:
	super.open(owner_root, p)
	uses_backdrop = false

func _layer(n: String) -> Control:
	var L := Control.new(); L.name = n; L.mouse_filter = Control.MOUSE_FILTER_IGNORE
	L.set_meta("layer", true)
	add_child(L); L.position = Vector2.ZERO; L.size = size
	layers[n] = L
	return L

func build() -> void:
	showcase = _pick_showcase()
	layers.clear()
	room = Room.new(); room.name = "Room"
	add_child(room); room.position = Vector2.ZERO; room.size = size
	room.blockers.append(func(p: Vector2) -> bool:
		return is_instance_valid(art) and art.is_visible_in_tree() and art.opaque_at(art.get_global_transform().affine_inverse() * (room.get_global_transform() * p)))
	var back_l := _layer("Back"); var art_l := _layer("Art"); var front_l := _layer("Front"); var card_l := _layer("Card")
	var toggle_l := _layer("Toggle")
	ring = Ring.new(); ring.name = "Ring"
	put(ring, Rect2(700, 40, 1220, 1020), "r", -1.0, front_l)
	# showcase art on the left: ONLY shown when a character has been unlocked
	if showcase != "":
		art = portrait(showcase, "full", Rect2(60, 40, 760, 1040), art_l, "lb")
		art.framing = "home"; art.frame = false; art.always_show = true
		art.show_art(showcase, "daily", "neutral")
		art.name = "Showcase"
	else:
		art = null
	# top-left power + hide-UI eye
	var pw := btn("", "power", "icon", Rect2(40, 30, 84, 84), func(): root.go("title", {"phase": "menu"}, "wipe", "reset"), "lt", -1.0, back_l)
	pw.name = "Power"; pw.tooltip_text = "返回标题"
	var deco := Control.new(); deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	put(deco, Rect2(30, 20, 180, 120), "lt", -1.0, back_l)
	deco.draw.connect(func():
		Kit.arc_fade(deco, Vector2(52, 52), 62, -PI * 0.15, PI * 0.55, UiHub.c("hair"), 1.0, 20, 0.3)
		deco.draw_line(Vector2(12, 112), Vector2(64, 112), UiHub.c("accent"), 2.0, true))
	hide_btn = btn("", "eye_off" if ui_hidden else "eye", "icon", Rect2(146, 36, 72, 72), func(): set_ui_hidden(not ui_hidden), "lt", -1.0, toggle_l)
	hide_btn.name = "HideUI"; hide_btn.tooltip_text = "隐藏界面，看看整个房间（再点一次 / 右键 / Esc 恢复）"
	hide_btn.press_sfx = "none"
	# top-right extensions hub + music player + settings chip + theme switch
	var cw := btn("扩展", "star4", "chip", Rect2(972, 30, 224, 76), func(): root.go("extensions"), "rt", 0.03, back_l, 24)
	cw.name = "Extensions"
	cw.tooltip_text = "打开已适配扩展中心（创意工坊 / 故事神谕）"
	music_btn(Rect2(1214, 30, 166, 76), "rt", back_l, 24)
	var st := btn("设置", "gear", "chip", Rect2(1400, 30, 250, 76), func(): root.go("settings"), "rt", 0.05, back_l, 26)
	st.name = "Settings"
	var sw := W.ThemeSwitch.new(); sw.name = "ThemeSwitch"
	put(sw, Rect2(1680, 34, 200, 70), "rt", -1.0, back_l)
	# main stack
	var story := btn("剧 情", "story", "primary", Rect2(1010, 190, 840, 200), func(): root.go("story_hub"), "r", 0.06, front_l, 64)
	story.sub = "推进故事，解锁新的篇章"; story.arrow = true; story.emblem = true; story.name = "Story"; story.hover_pitch = 1.0
	var arc_ := btn("资料库", "book", "secondary", Rect2(1030, 430, 780, 136), func(): root.go("archive"), "r", 0.1, front_l, 42)
	arc_.sub = "查阅记录与情报"; arc_.name = "Archive"; arc_.hover_pitch = 1.122
	var inv := btn("仓 库", "dome", "secondary", Rect2(1060, 606, 740, 126), func(): root.go("inventory"), "r", 0.16, front_l, 40)
	inv.sub = "管理道具与材料"; inv.name = "Inventory"; inv.hover_pitch = 1.335
	# pill row
	var row := plate(Rect2(1000, 780, 880, 104), {"shape": "pill", "detail": false}, "r", 0.2, front_l)
	row.name = "QuickRow"
	var items := [["角色", "person", "characters"], ["地图", "pin", "map"], ["刻印", "seal", "workshop"], ["事件", "docs", "events"], ["手札", "book", "database"]]
	var x := 22.0
	var widths := [148.0, 148.0, 148.0, 152.0, 168.0]
	for i in range(items.size()):
		var it: Array = items[i]
		var dest: String = it[2]
		var b := btn(it[0], it[1], "ghost", Rect2(x, 14, widths[i], 76), func(): root.go(dest), "c", -1.0, row, 21)
		b.name = "Quick_" + dest; b.hover_pitch = 1.5 + i * 0.12
		x += widths[i] + 10
		if i < items.size() - 1:
			var sep := Control.new(); sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			put(sep, Rect2(x - 6, 30, 4, 44), "c", -1.0, row)
			sep.draw.connect(func(): sep.draw_line(Vector2(1, 0), Vector2(1, 44), UiHub.c("hair"), 1.0, true))
	_character_card()
	_apply_glass()
	if not UiHub.palette_changed.is_connected(_apply_glass):
		UiHub.palette_changed.connect(_apply_glass)
		tree_exiting.connect(func():
			if UiHub.palette_changed.is_connected(_apply_glass): UiHub.palette_changed.disconnect(_apply_glass))
	_apply_hidden(false)

## See-through glass for every surface on this page, day and night.
## Night glass is pulled toward the room's deep navy so, over the bright window, it reads as
## blue-tinted glass instead of flat gray.
const NIGHT_TINT := Color(0.07, 0.10, 0.17)
func _apply_glass() -> void:
	var g := lerpf(GLASS_DAY, GLASS_NIGHT, UiHub.night)
	var tint := Color(NIGHT_TINT, 0.75 * UiHub.night)
	for L in layers.values():
		if not is_instance_valid(L): continue
		for n in L.find_children("*", "", true, false):
			if n is Btn: n.fill_mult = g; n.glass_tint = tint; n.queue_redraw()
			elif n is Plate:
				if not n.has_meta("base_fill"): n.set_meta("base_fill", n.fill_alpha)
				n.fill_alpha = float(n.get_meta("base_fill")) * g; n.glass_tint = tint; n.queue_redraw()
			elif n is W.ThemeSwitch: n.fill_mult = g; n.glass_tint = tint; n.queue_redraw()

func enter(delay := 0.0) -> void:
	super.enter(delay)
	# the base cascade only walks direct children; do the same inside each layer
	var explicit := {}
	for item in rises: explicit[item.node] = true
	for L in layers.values():
		if L.name == "Toggle": continue
		for c in L.get_children():
			if explicit.has(c) or not c is Control or not "reveal" in c: continue
			var order: float = clampf(c.position.x / maxf(size.x, 1.0), 0.0, 1.0) * 0.22 + clampf(c.position.y / maxf(size.y, 1.0), 0.0, 1.0) * 0.12
			Kit.rise(c, delay + 0.03 + order, 26.0, 0.55)

func _process(_d: float) -> void:
	if not is_visible_in_tree(): return
	# pointer float removed (user 2026-11-17: felt laggy). Layers only move for the hide-UI slide.
	for n in layers:
		var L: Control = layers[n]
		if not is_instance_valid(L): continue
		var to: Vector2 = L.get_meta("slide", Vector2.ZERO)
		# skip sub-0.01px updates so a resting page does no work
		if not L.position.is_equal_approx(to) and L.position.distance_squared_to(to) > 0.0001: L.position = to
	if is_instance_valid(room) and room.size != size: room.size = size

## Hide / show every UI piece and the character so the whole room can be seen. The room stays
## clickable; the eye key, a right click or Esc / Back brings the UI back.
func set_ui_hidden(on: bool) -> void:
	if on == ui_hidden: return
	ui_hidden = on
	UiHub.sfx("room_ui_hide" if on else "room_ui_show")
	_apply_hidden(true)

func _apply_hidden(animate: bool) -> void:
	if is_instance_valid(hide_btn):
		hide_btn.icon_name = "eye_off" if ui_hidden else "eye"
		hide_btn.tooltip_text = "显示界面" if ui_hidden else "隐藏界面，看看整个房间（再点一次 / 右键 / Esc 恢复）"
		hide_btn.queue_redraw()
	if _hide_tween: _hide_tween.kill()
	var slides := {"Back": Vector2(0, -36), "Art": Vector2(-60, 0), "Front": Vector2(70, 0), "Card": Vector2(0, 50)}
	var fast := not animate or UiHub.reduced_motion
	if not fast:
		_hide_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for n in slides:
		var L: Control = layers.get(n)
		if not is_instance_valid(L): continue
		var to_a := 0.0 if ui_hidden else 1.0
		var to_s: Vector2 = slides[n] if ui_hidden else Vector2.ZERO
		if ui_hidden == false: L.visible = true
		if fast:
			L.modulate.a = to_a; L.set_meta("slide", to_s); L.visible = not ui_hidden
		else:
			var from_s: Vector2 = L.get_meta("slide", Vector2.ZERO)
			_hide_tween.tween_property(L, "modulate:a", to_a, 0.34 if ui_hidden else 0.42)
			_hide_tween.tween_method(func(v: Vector2): if is_instance_valid(L): L.set_meta("slide", v), from_s, to_s, 0.4 if ui_hidden else 0.5)
	if not fast and ui_hidden:
		_hide_tween.chain().tween_callback(func():
			for n in slides:
				var L: Control = layers.get(n)
				if is_instance_valid(L) and ui_hidden: L.visible = false)

func on_back() -> bool:
	if ui_hidden:
		set_ui_hidden(false); return true
	return false

func _gui_input(e: InputEvent) -> void:
	if ui_hidden and e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
		set_ui_hidden(false); accept_event()

func _character_card() -> void:
	var card := plate(Rect2(40, 854, 620, 176), {"slant": 40}, "lb", 0.18, layers["Card"])
	card.name = "CharacterCard"
	if showcase == "":
		icon("lock", Rect2(34, 48, 72, 72), "muted", "c", card)
		text("暂无看板角色", Rect2(128, 30, 320, 46), 28, "ink", 800, "c", card)
		text("在主线剧情中正式邂逅同伴后，才会登上看板并开启私聊。", Rect2(128, 84, 330, 64), 17, "muted", 600, "c", card)
		var go_st := btn("去剧情", "play", "primary", Rect2(466, 56, 134, 64), func(): root.go("story_hub"), "c", -1.0, card, 19)
		go_st.name = "EmptyShowcaseGoStory"
		return
	var av := portrait(showcase, "avatar", Rect2(26, 31, 114, 114), card)
	av.name = "Avatar"; av.always_show = true; av.frame = false; av.circle_clip = true; av.show_character(showcase, "avatar", false)
	var ring_c := Control.new(); ring_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	put(ring_c, Rect2(20, 25, 126, 126), "c", -1.0, card)
	ring_c.draw.connect(func():
		ring_c.draw_arc(Vector2(63, 63), 58, 0, TAU, 48, UiHub.c("ink"), 1.2, true)
		Kit.arc_fade(ring_c, Vector2(63, 63), 63, -PI * 0.2, PI * 0.6, UiHub.c("accent"), 1.6, 24, 0.3))
	var talk := btn("", "", "ghost", Rect2(20, 25, 126, 126), func(): root.go("talk", {"id": showcase}), "c", -1.0, card)
	talk.name = "Talk"; talk.tooltip_text = "和看板角色交谈"
	var nm := Data.name_of(showcase) if showcase != "" else "看板角色"
	text(nm, Rect2(170, 14, 210, 48), 32, "ink", 700, "c", card)
	var sw := btn("切换", "refresh", "ghost", Rect2(400, 14, 180, 48), func(): _next_showcase(), "c", -1.0, card, 22)
	sw.name = "SwitchShowcase"
	var aff := _affection(showcase)
	icon("sparkle", Rect2(170, 74, 28, 28), "ink", "c", card)
	text("好感度", Rect2(208, 66, 114, 42), 22, "ink", 600, "c", card)
	var b := bar(Rect2(334, 80, 174, 14), aff if aff >= 0.0 else 0.0, 100.0, "accent", card)
	b.name = "Affection"
	text(("%d%%" % int(aff)) if aff >= 0.0 else "—", Rect2(516, 66, 84, 42), 21, "ink", 600, "c", card, HORIZONTAL_ALIGNMENT_RIGHT)

	var lewd := _lewdness(showcase)
	icon("heart", Rect2(170, 120, 28, 28), "accent", "c", card)
	text("色情值", Rect2(208, 112, 114, 42), 22, "ink", 600, "c", card)
	var lb := bar(Rect2(334, 126, 174, 14), lewd if lewd >= 0.0 else 0.0, 100.0, "ink", card)
	lb.name = "Lewdness"
	text(("%d%%" % int(lewd)) if lewd >= 0.0 else "—", Rect2(516, 112, 84, 42), 21, "ink", 600, "c", card, HORIZONTAL_ALIGNMENT_RIGHT)

func _roster() -> Array:
	var out: Array = []
	for cid_raw in Game.unlocked_ids(true):
		var cid := String(cid_raw)
		if Data.art_path(cid, "daily", "neutral") != "":
			out.append(cid)
	return out

func _pick_showcase() -> String:
	var list := _roster()
	if list.is_empty(): return ""
	var saved_id := String(UiHub.get_meta("showcase_id", ""))
	if saved_id != "" and saved_id in list: return saved_id
	var best: String = "rin" if "rin" in list else String(list[0])
	var top := -1.0
	var known: Dictionary = Game.known()
	for name in known:
		var id: String = Data.id_of(name)
		if id in list and float(known[name].get("好感度", 0)) > top: top = float(known[name].get("好感度", 0)); best = id
	return best

func _next_showcase() -> void:
	var list := _roster()
	if list.is_empty(): UiHub.sfx("deny"); toast("暂无已解锁的看板角色", "lock"); return
	if list.size() == 1: UiHub.sfx("deny"); toast("目前仅解锁了这 1 位看板角色，推进主线可结识更多同伴", "person"); return
	var i := list.find(showcase)
	showcase = list[(i + 1) % list.size()]
	UiHub.set_meta("showcase_id", showcase)
	UiHub.sfx("swap")
	refresh(true)

func _affection(id: String) -> float:
	var known: Dictionary = Game.known()
	var cname := Data.name_of(id)
	if known.has(cname) and known[cname].has("好感度"): return clampf(float(known[cname]["好感度"]), 0.0, 100.0)
	return -1.0

func _lewdness(id: String) -> float:
	var known: Dictionary = Game.known()
	var cname := Data.name_of(id)
	if known.has(cname) and known[cname].has("色情值"): return clampf(float(known[cname]["色情值"]), 0.0, 100.0)
	return -1.0


## The great sweeping circle behind the button stack: two hairline arcs that turn very slowly,
## beads riding them, a long diagonal with a short red double slash (concept 07).
class Ring extends Control:
	const K = preload("res://scripts/ui/ui_kit.gd")
	var clock := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE; UiHub.palette_changed.connect(queue_redraw)
	var _acc := 0.0
	func _process(d: float) -> void:
		if UiHub.reduced_motion or not is_visible_in_tree(): return
		clock += d; _acc += d
		# the arcs turn ~0.5 px per 1/30 s: redrawing 30 times a second looks the same, costs far less
		if _acc >= 1.0 / 30.0: _acc = fmod(_acc, 1.0 / 30.0); queue_redraw()
	func _draw() -> void:
		var c := Vector2(size.x * 0.66, size.y * 0.47)
		var r := size.y * 0.47
		var hair := UiHub.c("hair"); var acc := UiHub.c("accent")
		var s := clock * 0.03
		K.arc_fade(self, c, r, PI * 0.55 + s, PI * 1.62 + s, hair, 1.2, 96, 0.08)
		K.arc_fade(self, c + Vector2(30, 10), r * 0.98, PI * 0.62 - s * 0.7, PI * 1.5 - s * 0.7, Color(hair, 0.5), 1.0, 96, 0.1)
		for k in range(3):
			var a := PI * (0.8 + k * 0.3) + s
			draw_circle(c + Vector2.from_angle(a) * r, 3.0, Color(UiHub.c("muted"), 0.8))
		# long diagonal through the emblem area + red double slash
		var p0 := Vector2(size.x * 0.12, size.y * 0.62); var p1 := Vector2(size.x * 0.48, size.y * 0.02)
		K.line_fade(self, p0, p1, Color(hair, 0.9), 1.0, 20)
		var m := p0.lerp(p1, 0.72)
		var d := (p1 - p0).normalized(); var n := Vector2(-d.y, d.x)
		for j in range(2):
			draw_line(m + n * (8 + j * 9) - d * 34, m + n * (8 + j * 9) + d * 34, acc, 1.6, true)
		# lower sweep under the quick row
		K.arc_fade(self, Vector2(size.x * 0.62, size.y * 0.05), size.y * 0.93, PI * 0.42, PI * 0.62, Color(hair, 0.7), 1.0, 40, 0.2)
