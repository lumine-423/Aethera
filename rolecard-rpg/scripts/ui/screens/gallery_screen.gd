extends "res://scripts/ui/ui_screen.gd"
## 插画鉴赏: unlocked event illustrations / CG. CG textures come from data/ui/portrait_registry.json "cg".
## Viewer: full-screen, prev/next, tap to hide the frame.

var viewer: Control
var viewing := -1
var frame_hidden := false

func _catalog() -> Array:
	return Data.gallery_catalog(Game.unlocked_cgs(), W.Portrait.registry.get("cg", {}))

func _cg_path(entry: Dictionary) -> String:
	var p := String(entry.get("res", ""))
	if p != "" and ResourceLoader.exists(p): return p
	var spec := Data.illustration_spec(String(entry.get("id", "")), W.Portrait.registry.get("cg", {}))
	return String(spec.get("res", ""))

func build() -> void:
	chrome("插画鉴赏")
	decor(97, Rect2(Vector2.ZERO, size), 0.6)
	var list: Array = _catalog()
	var got := list.filter(func(x): return x.unlocked).size()
	text("已解锁 %d / %d" % [got, list.size()], Rect2(1400, 130, 460, 50), 24, "muted", 700, "c", null, HORIZONTAL_ALIGNMENT_RIGHT)
	var bar := W.Bar.new(); bar.max_value = maxf(1.0, float(list.size())); bar.value = got
	put(bar, Rect2(1560, 182, 300, 8))
	var host: Control = self
	var rows := ceili(float(list.size()) / 3.0)
	if list.size() > 6:
		var sc := ScrollContainer.new(); sc.name = "GalleryScroll"
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		put(sc, Rect2(0, 204, size.x, size.y - 224), "lt")
		var inner := Control.new(); inner.custom_minimum_size = Vector2(size.x, float(rows) * g(400.0) + 40.0)
		inner.mouse_filter = Control.MOUSE_FILTER_PASS; sc.add_child(inner)
		host = inner
	var top_y := 220.0 if host == self else 16.0
	for k in range(list.size()):
		var e: Dictionary = list[k]
		var r := Rect2(90 + (k % 3) * 590 - ((k / 3) % 2) * 20, top_y + (k / 3) * g(400), 560, 370)
		var b := Btn.new(); b.variant = "secondary"; b.slant = 30; b.disabled = not e.unlocked
		put(b, r, "c", 0.06 + minf(float(k), 12.0) * 0.04, host)
		b.pressed.connect(func(): open_viewer(k))
		b.press_sfx = "open_book"
		var art := W.Portrait.new(); art.kind = "cg"; art.frame = false
		var path := _cg_path(e)
		put(art, Rect2(44, 20, 480, 270), "c", -1.0, b)
		if path != "" and ResourceLoader.exists(path): art.set_texture(load(path), false)
		if not e.unlocked:
			art.visible = false
			icon("lock", Rect2(250, 110, 70, 70), "muted", "c", b)
		text(e.title, Rect2(44, 296, 460, 56), 24, "ink" if e.unlocked else "muted", 800, "c", b)
	if viewing >= 0: open_viewer(viewing)

func open_viewer(k: int) -> void:
	var list: Array = _catalog()
	if k < 0 or k >= list.size() or not list[k].unlocked: return
	viewing = k
	if is_instance_valid(viewer): viewer.queue_free()
	viewer = Control.new(); viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(viewer); viewer.size = size
	var bg := ColorRect.new(); bg.color = UiHub.c("background"); viewer.add_child(bg); bg.size = size
	var art := W.Portrait.new(); art.kind = "cg"; art.frame = false
	viewer.add_child(art); art.position = Vector2.ZERO; art.size = size
	var path := _cg_path(list[k])
	if path != "" and ResourceLoader.exists(path): art.set_texture(load(path), false)
	var chrome_box := Control.new(); chrome_box.mouse_filter = Control.MOUSE_FILTER_IGNORE; viewer.add_child(chrome_box); chrome_box.size = size
	chrome_box.name = "Chrome"
	var close := Btn.new(); close.setup("", "close", "icon"); chrome_box.add_child(close); close.position = Vector2(size.x - 130, 30); close.size = Vector2(96, 70)
	close.pressed.connect(close_viewer); close.press_sfx = "none"
	var prev := Btn.new(); prev.setup("", "back", "icon"); prev.press_sfx = "none"; chrome_box.add_child(prev); prev.position = Vector2(30, size.y * 0.5 - 40); prev.size = Vector2(90, 80)
	prev.pressed.connect(func(): _step(-1))
	var nxt := Btn.new(); nxt.setup("", "next", "icon"); nxt.press_sfx = "none"; chrome_box.add_child(nxt); nxt.position = Vector2(size.x - 120, size.y * 0.5 - 40); nxt.size = Vector2(90, 80)
	nxt.pressed.connect(func(): _step(1))
	var cap := Plate.new(); cap.slant = 24; cap.stripe = "left"; chrome_box.add_child(cap); cap.position = Vector2(60, size.y - 120); cap.size = Vector2(560, 80)
	var l := Lbl.new(); l.setup(list[k].title, 28, "ink", 800); cap.add_child(l); l.position = Vector2(40, 0); l.size = Vector2(500, 80); l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	viewer.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: frame_hidden = not frame_hidden; chrome_box.visible = not frame_hidden; UiHub.sfx("collapse" if frame_hidden else "expand"))
	if not UiHub.reduced_motion:
		viewer.modulate.a = 0.0; viewer.create_tween().tween_property(viewer, "modulate:a", 1.0, 0.25)

func _step(d: int) -> void:
	UiHub.sfx("paper", 1.0 if d > 0 else 0.9)
	var list: Array = _catalog()
	var k := viewing
	for i in range(list.size()):
		k = (k + d + list.size()) % list.size()
		if list[k].unlocked: break
	open_viewer(k)

func close_viewer() -> void:
	if viewing >= 0: UiHub.sfx("close_book")
	viewing = -1; frame_hidden = false
	if is_instance_valid(viewer): viewer.queue_free()

func on_back() -> bool:
	if viewing >= 0: close_viewer(); return true
	return false
