extends Control
## Base class for every full screen. Screens keep their state in variables and rebuild their
## node tree from that state, so text size, layout spacing and day/night can change at any time.
## Layout is authored on a 1920x1080 design canvas; anchors keep corner chrome on the real edges
## for wider phones (20:9) and taller tablets (4:3).

const Kit = preload("res://scripts/ui/ui_kit.gd")
const Plate = preload("res://scripts/ui/ui_plate.gd")
const Btn = preload("res://scripts/ui/ui_button.gd")
const Lbl = preload("res://scripts/ui/ui_label.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const W = preload("res://scripts/ui/ui_widgets.gd")
const Data = preload("res://scripts/ui/ui_data.gd")

var root: Node
var params: Dictionary = {}
var design := Vector2(1920, 1080)
var origin := Vector2.ZERO
var rises: Array = []
var uses_backdrop := true
## "room": the home room picture, heavily blurred, under the drawn geometry (2026-11-17 default)
## "plain": the original paper / black backdrop (story screen keeps this)
var backdrop_style := "room"
var decor_seed := 3
var built_spacing := -1.0
var built_text_scale := -1.0
var screen_id := ""
var _has_built := false

func open(owner_root: Node, p: Dictionary) -> void:
	root = owner_root; params = p

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS

## Override: create nodes from state.
func build() -> void:
	pass

## Override: return true when the screen consumed a back / Esc press (e.g. closed a sub panel).
func on_back() -> bool:
	return false

## Override: called after the enter transition completed.
func on_shown() -> void:
	pass

func rebuild() -> void:
	for c in get_children(): c.free()
	rises.clear()
	origin = ((size - design) * 0.5).floor()
	built_spacing = UiHub.spacing
	built_text_scale = UiHub.text_scale
	build()
	_has_built = true

func needs_layout_rebuild() -> bool:
	return not is_equal_approx(built_spacing, UiHub.spacing) or not is_equal_approx(built_text_scale, UiHub.text_scale)

var _refresh_pending := false
var _refresh_anim := false
## Safe rebuild from inside button callbacks (never frees the node that is emitting).
func refresh(animate := false) -> void:
	_refresh_anim = _refresh_anim or animate
	if _refresh_pending: return
	_refresh_pending = true
	call_deferred("_do_refresh")

func _do_refresh() -> void:
	_refresh_pending = false
	rebuild()
	if _refresh_anim: enter()
	_refresh_anim = false

func enter(delay := 0.0) -> void:
	var explicit := {}
	for i in range(rises.size()):
		var item = rises[i]
		if is_instance_valid(item.node):
			explicit[item.node] = true
			Kit.rise(item.node, delay + item.delay, item.dist, 0.62, item.axis)
	# Cascade: every other top-level plate / button slices in, ordered left -> right, top -> bottom.
	for c in get_children():
		if explicit.has(c) or not c is Control or not "reveal" in c: continue
		var order: float = clampf(c.position.x / maxf(size.x, 1.0), 0.0, 1.0) * 0.22 + clampf(c.position.y / maxf(size.y, 1.0), 0.0, 1.0) * 0.12
		Kit.rise(c, delay + 0.03 + order, 26.0, 0.55)

## Sliding accent cursor that glides between the given buttons (all must share one parent).
func cursor_for(buttons: Array) -> Control:
	if buttons.is_empty(): return null
	var cur := W.Cursor.new()
	var parent: Node = buttons[0].get_parent()
	parent.add_child(cur); parent.move_child(cur, buttons[0].get_index())
	cur.track(buttons)
	return cur

# ---------- placement ----------
func at(x: float, y: float, anchor := "c") -> Vector2:
	var p := origin + Vector2(x, y)
	if "l" in anchor: p.x = x
	if "r" in anchor: p.x = size.x - (design.x - x)
	if "t" in anchor: p.y = y
	if "b" in anchor: p.y = size.y - (design.y - y)
	return p

func put(node: Control, r: Rect2, anchor := "c", rise := -1.0, parent: Node = null, axis := Vector2.RIGHT) -> Control:
	if node.get_script() == null and node.get_class() == "Control" and node.get_signal_connection_list("gui_input").is_empty(): node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else self).add_child(node)
	node.position = at(r.position.x, r.position.y, anchor) if parent == null or parent.has_meta("layer") else r.position
	node.size = r.size
	if rise >= 0.0: rises.append({"node": node, "delay": rise, "dist": 46.0, "axis": axis})
	return node

func g(v: float) -> float:
	return UiHub.gap(v)

# ---------- builders ----------
func plate(r: Rect2, opts := {}, anchor := "c", rise := -1.0, parent: Node = null) -> Control:
	var p := Plate.new()
	for k in opts: p.set(k, opts[k])
	return put(p, r, anchor, rise, parent)

func btn(caption: String, icon_name: String, kind: String, r: Rect2, cb: Callable, anchor := "c", rise := -1.0, parent: Node = null, px := 28) -> Button:
	var b := Btn.new(); b.setup(caption, icon_name, kind, px)
	if cb.is_valid(): b.pressed.connect(cb)
	put(b, r, anchor, rise, parent)
	return b

func text(value: String, r: Rect2, px := 26, role := "ink", weight := 600, anchor := "c", parent: Node = null, align := HORIZONTAL_ALIGNMENT_LEFT, rise := -1.0) -> Label:
	var l := Lbl.new(); l.setup(value, px, role, weight)
	l.horizontal_alignment = align; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var wrap := (r.size.y >= px * 1.85 and (("\n" in value) or Kit.text_width(value, UiHub.fs(px), weight) > r.size.x - 4.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF: l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.clip_text = l.autowrap_mode == TextServer.AUTOWRAP_OFF
	put(l, r, anchor, rise, parent)
	return l

func icon(name: String, r: Rect2, role := "ink", anchor := "c", parent: Node = null, hole := "surface") -> Control:
	var i := Icon.new(); i.icon = name; i.role = role; i.hole_role = hole
	return put(i, r, anchor, -1.0, parent)

func header(title: String, r: Rect2, px := 28, anchor := "c", parent: Node = null, rise := -1.0) -> Control:
	var h := W.Header.new(); h.title = title; h.px = px
	if _has_built: h.intro = false
	return put(h, r, anchor, rise, parent)

func bar(r: Rect2, value: float, max_value: float, role := "accent", parent: Node = null, anchor := "c") -> Control:
	var b := W.Bar.new(); b.value = value; b.max_value = max_value; b.role = role
	if screen_id == "loading" or _has_built: b.intro = false
	return put(b, r, anchor, -1.0, parent)

func portrait(id: String, kind: String, r: Rect2, parent: Node = null, anchor := "c") -> Control:
	var p := W.Portrait.new(); p.character_id = id; p.kind = kind
	return put(p, r, anchor, -1.0, parent)

func decor(seed_value: int, r: Rect2, density := 1.0) -> Control:
	var d := W.Decor.new(); d.seed_value = seed_value; d.density = density
	return put(d, r, "lt")

## Standard top chrome: accent back chevron, page title with hairline, day/night switch.
func chrome(title: String, with_switch := true, back_text := "") -> void:
	var back := btn(back_text, "back", "icon" if back_text == "" else "chip", Rect2(28, 30, 96 if back_text == "" else 170, 70), func(): root.back(), "lt")
	back.name = "Back"
	back.tooltip_text = "返回"
	if title != "":
		var t := text(title, Rect2(150 if back_text == "" else 220, 28, 700, 76), 44, "ink", 850, "lt")
		t.name = "PageTitle"
		# mystic pass: a small accent four-point star with a sweeping hairline after the title
		var tick := Control.new(); tick.mouse_filter = Control.MOUSE_FILTER_IGNORE; tick.name = "TitleStar"
		put(tick, Rect2((150 if back_text == "" else 220) + Kit.text_width(title, UiHub.fs(44), 850) + 18, 26, 140, 80), "lt")
		tick.draw.connect(func():
			Kit.star4(tick, Vector2(20, 38), 13, UiHub.c("accent"), 0.15)
			Kit.arc_fade(tick, Vector2(-40, -60), 150, PI * 0.18, PI * 0.5, UiHub.c("accent", 0.8), 1.4, 20, 0.25))
		UiHub.palette_changed.connect(tick.queue_redraw)
		rises.append({"node": t, "delay": 0.0, "dist": 30.0, "axis": Vector2.RIGHT})
	if with_switch:
		music_btn(Rect2(1516, 34, 160, 64), "rt")
		var sw := W.ThemeSwitch.new(); sw.name = "ThemeSwitch"
		put(sw, Rect2(1692, 34, 190, 64), "rt")

func music_btn(r: Rect2, anchor := "rt", parent: Node = null, px := 22) -> Button:
	var mb := btn("已静音" if UiHub.music_disabled else "乐章", "mute" if UiHub.music_disabled else "music", "chip", r, func(): root.open_music_player(), anchor, -1.0, parent, px)
	mb.name = "MusicPlayerBtn"
	mb.press_sfx = "none"
	mb.tooltip_text = "打开乐章播放器（点播音乐 / 彻底关闭音乐）"
	var sync := func() -> void:
		if not is_instance_valid(mb): return
		mb.caption = "已静音" if UiHub.music_disabled else "乐章"
		mb.icon_name = "mute" if UiHub.music_disabled else "music"
		mb.selected = not UiHub.music_disabled and UiHub.music_override != ""
		mb.queue_redraw()
	UiHub.music_changed.connect(sync)
	mb.tree_exited.connect(func():
		if UiHub.music_changed.is_connected(sync): UiHub.music_changed.disconnect(sync))
	sync.call()
	return mb

func toast(msg: String, icon_name := "info") -> void:
	if root: root.toast(msg, icon_name)

func request(action: String, payload := {}) -> void:
	UiHub.request(action, payload)
