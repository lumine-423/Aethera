extends Control
## Application UI root: scales one 1920x1080 design canvas to any window or phone screen,
## owns the screen stack, page transitions, dialogs, toasts and Back / Esc / Android back.

const Kit = preload("res://scripts/ui/ui_kit.gd")
const Backdrop = preload("res://scripts/ui/ui_backdrop.gd")
const Overlay = preload("res://scripts/ui/ui_overlay.gd")
const OracleOverlay = preload("res://scripts/ui/story_oracle_overlay.gd")
const UpdateOverlay = preload("res://scripts/ui/app_update_overlay.gd")
const ThemeBuilder = preload("res://scripts/ui/ui_theme_builder.gd")
const HOME_SCENE := "res://scenes/home.tscn"
const ACCESS_PASSWORD := "明星荧荧Hotaru"
const SCREENS := {
	"gate": "res://scripts/ui/screens/gate_screen.gd",
	"notice": "res://scripts/ui/screens/notice_screen.gd",
	"title": "res://scripts/ui/screens/title_screen.gd",
	"prologue": "res://scripts/ui/screens/opening_screen.gd",   # full version: placeholder opening
	"loading": "res://scripts/ui/screens/loading_screen.gd",
	"story_hub": "res://scripts/ui/screens/story_hub_screen.gd",
	"story": "res://scripts/ui/screens/story_screen.gd",
	"archive": "res://scripts/ui/screens/archive_screen.gd",
	"characters": "res://scripts/ui/screens/characters_screen.gd",
	"gallery": "res://scripts/ui/screens/gallery_screen.gd",
	"settings": "res://scripts/ui/screens/settings_screen.gd",
	"saves": "res://scripts/ui/screens/saves_screen.gd",
	"home": "res://scripts/ui/screens/home_screen.gd",
	"opening": "res://scripts/ui/screens/opening_screen.gd",
	"talk": "res://scripts/ui/screens/talk_screen.gd",
	"workshop": "res://scripts/ui/screens/workshop_screen.gd",
	"crafting": "res://scripts/ui/screens/workshop_screen.gd",
	"showcase": "res://scripts/ui/screens/showcase_screen.gd",
	"connect": "res://scripts/ui/screens/connect_screen.gd",
	"origin": "res://scripts/ui/screens/origin_screen.gd",
	"create": "res://scripts/ui/screens/create_screen.gd",
	"inventory": "res://scripts/ui/screens/inventory_screen.gd",
	"map": "res://scripts/ui/screens/map_screen.gd",
	"events": "res://scripts/ui/screens/events_screen.gd",
	"edit": "res://scripts/ui/screens/edit_screen.gd",
	"help": "res://scripts/ui/screens/help_screen.gd",
	"database": "res://scripts/ui/screens/database_screen.gd",
	"presets": "res://scripts/ui/screens/presets_screen.gd",
	"extensions": "res://scripts/ui/screens/extensions_screen.gd",
	"creative_workshop": "res://scripts/ui/screens/creative_workshop_screen.gd",
	"full_only": "res://scripts/ui/screens/full_only_screen.gd",
}
## Home buttons -> screens. Keeps home.tscn unchanged as a standalone sample.
const HOME_ROUTES := {"story": "story_hub", "archive": "archive", "inventory": "inventory", "characters": "characters", "settings": "settings", "title": "title"}

signal screen_changed(name: String)

var design := Vector2(1920, 1080)
var logical := Vector2(1920, 1080)
var stage: Control
var backdrop: Control
var screen_layer: Control
var overlay_layer: Control
var toast_layer: Control
var wipe_layer: Control
var stack: Array = []
var busy := false
var dialogs: Array = []
var gate_passed := false
var notice_acknowledged := false
var _requested_start := ""
var _last_story_bgm := ""

func _ready() -> void:
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage = Control.new(); stage.name = "Stage"; stage.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(stage)
	backdrop = Backdrop.new(); backdrop.name = "Backdrop"; stage.add_child(backdrop)
	screen_layer = _layer("Screens"); overlay_layer = _layer("Overlays"); toast_layer = _layer("Toasts"); wipe_layer = _layer("Transition")
	wipe_layer.mouse_filter = Control.MOUSE_FILTER_STOP; wipe_layer.visible = false
	theme = ThemeBuilder.build()
	UiHub.reveal_handler = _night_reveal
	get_tree().node_added.connect(_wire_native)
	UiHub.palette_changed.connect(_retheme)
	UiHub.options_changed.connect(_retheme)
	resized.connect(_arrange)
	_arrange()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-start="): _requested_start = a.trim_prefix("--ui-start=")
	_last_story_bgm = String(Game.hero().get("当前BGM", ""))
	UiHub.music_route_resolver = Callable(self, "_update_music")
	screen_changed.connect(func(_name): _update_music())
	Game.changed.connect(_music_state_changed)
	if UiHub.is_gate_unlocked(ACCESS_PASSWORD):
		gate_passed = true
		if UiHub.notice_seen:
			notice_acknowledged = true
			var default_start := "title" if UiHub.opening_seen else "prologue"
			var start := _requested_start if _requested_start != "" else default_start
			if start in ["gate", "notice"] or (start != "home" and not SCREENS.has(start)): start = default_start
			var p := {"phase": "menu"} if start == "title" else ({"next": "title", "replay": true} if start == "prologue" else {})
			_push(start, p)
			screen_changed.emit(start)
		else:
			notice_acknowledged = false
			_push("notice", {})
			screen_changed.emit("notice")
	else:
		_push("gate", {})
		screen_changed.emit("gate")
	Game.notice.connect(func(msg): toast(msg, "info"))
	Game.error_reported.connect(_on_game_error)

func pass_gate(pwd: String) -> bool:
	if pwd.strip_edges() != ACCESS_PASSWORD:
		return false
	gate_passed = true
	UiHub.mark_gate_unlocked(ACCESS_PASSWORD)
	if UiHub.notice_seen:
		notice_acknowledged = false
		acknowledge_notice()
		return true
	notice_acknowledged = false
	_reset("notice", {})
	screen_changed.emit("notice")
	return true

func acknowledge_notice() -> void:
	if not gate_passed or notice_acknowledged: return
	notice_acknowledged = true
	UiHub.mark_notice_seen()
	var default_start := "title" if UiHub.opening_seen else "prologue"
	var start := _requested_start if _requested_start != "" else default_start
	if start in ["gate", "notice"] or (start != "home" and not SCREENS.has(start)): start = default_start
	var p := {"phase":"menu"} if start == "title" else ({"next":"title", "replay": true} if start == "prologue" else {})
	_reset(start, p); screen_changed.emit(start)

func _has_any_save() -> bool:
	return Game.saves.any(func(s): return s is Dictionary and bool(s.get("used", false)))

func _layer(n: String) -> Control:
	var c := Control.new(); c.name = n; c.mouse_filter = Control.MOUSE_FILTER_IGNORE; stage.add_child(c); return c

func _retheme() -> void:
	theme = ThemeBuilder.build()

func _arrange() -> void:
	if size.x < 2 or size.y < 2: return
	var aspect := size.x / size.y
	logical = Vector2(design.y * aspect, design.y) if aspect >= design.x / design.y else Vector2(design.x, design.x / aspect)
	stage.scale = Vector2.ONE * (size.y / logical.y)
	stage.size = logical
	for c in stage.get_children():
		c.position = Vector2.ZERO; c.size = logical
	for entry in stack:
		var n: Control = entry.node
		if is_instance_valid(n):
			n.size = logical
			if n.has_method("rebuild"): n.rebuild()
	for d in dialogs:
		if is_instance_valid(d): d.size = logical

func current() -> Control:
	return stack.back().node if not stack.is_empty() else null

func current_name() -> String:
	return stack.back().name if not stack.is_empty() else ""

# ---------- navigation ----------
func _make(name: String, p: Dictionary) -> Control:
	var node: Control
	if name == "home" and not SCREENS.has("home"):
		node = load(HOME_SCENE).instantiate()
		node.set_anchors_preset(Control.PRESET_TOP_LEFT)
		node.set_meta("external_router", true)
		node.navigation_requested.connect(_on_home_nav)
		node.character_message_requested.connect(func(id, msg): UiHub.request("character.chat", {"character": id, "text": msg}); UiHub.sfx("send"))
		node.ready.connect(_wire_home_sounds.bind(node), CONNECT_ONE_SHOT)
		node.ready.connect(_home_showcase.bind(node), CONNECT_ONE_SHOT)
	else:
		var path: String = SCREENS.get(name, "")
		if path == "" or not ResourceLoader.exists(path):
			push_warning("unknown screen " + name); name = "title"; path = SCREENS.title
		node = load(path).new()
		node.screen_id = name
		node.open(self, p)
	node.name = name.capitalize().replace(" ", "")
	node.size = logical
	return node

func _push(name: String, p: Dictionary) -> void:
	UiHub.quiet_focus()
	var prev := current()
	if prev:
		prev.visible = false; prev.process_mode = Node.PROCESS_MODE_DISABLED
	var node := _make(name, p)
	screen_layer.add_child(node)
	node.size = logical
	if node.has_method("rebuild"):
		node.rebuild(); node.enter(0.12)
		backdrop.visible = node.uses_backdrop
		backdrop.style = node.backdrop_style
	else:
		backdrop.visible = false
	stack.append({"name": name, "params": p, "node": node})

func _pop() -> void:
	if stack.size() <= 1: return
	UiHub.quiet_focus()
	var top: Dictionary = stack.pop_back()
	top.node.queue_free()
	var prev := current()
	prev.visible = true; prev.process_mode = Node.PROCESS_MODE_INHERIT
	if prev.has_method("rebuild"):
		if (prev.has_method("needs_layout_rebuild") and prev.needs_layout_rebuild()) or (not is_equal_approx(prev.built_spacing, UiHub.spacing)):
			prev.rebuild()
		prev.enter(0.05)
		backdrop.visible = prev.uses_backdrop
		backdrop.style = prev.backdrop_style
		prev.on_shown()
	else:
		backdrop.visible = false
		if prev.has_method("entrance"): prev.entrance()

func _reset(name: String, p: Dictionary) -> void:
	while not stack.is_empty():
		var e: Dictionary = stack.pop_back(); e.node.queue_free()
	_push(name, p)

## Open a screen on top of the stack. mode: push | replace | reset.
const TOP_LEVEL := ["home", "title", "story_hub", "archive", "settings", "loading"]
func go(name: String, p := {}, transition := "auto", mode := "push") -> void:
	if not gate_passed and name != "gate": return
	if not notice_acknowledged and not (name in ["gate", "notice"]): return
	if name != "home" and not SCREENS.has(name):
		return
	if busy: return
	if transition == "auto":
		transition = "wipe" if (current_name() in ["home", "title"] or name in ["home", "title"] or mode == "reset") else "slide_in"
	var enter_cue := ""
	if name in ["archive", "events", "help"]: enter_cue = "open_book"
	elif name == "inventory": enter_cue = "bag_open"
	elif name == "map": enter_cue = "map_open"
	elif name in ["characters", "origin"]: enter_cue = "char_open"
	elif name in ["workshop", "crafting"]: enter_cue = "recipe"
	elif name == "saves": enter_cue = "paper"
	if enter_cue != "": UiHub.sfx(enter_cue)
	var swap := func() -> void:
		match mode:
			"replace":
				if not stack.is_empty():
					var e: Dictionary = stack.pop_back(); e.node.queue_free()
				_push(name, p)
			"reset": _reset(name, p)
			_: _push(name, p)
		screen_changed.emit(name)
	_transition(transition, swap)

func back(transition := "auto") -> void:
	if not notice_acknowledged: return
	if busy: return
	if transition == "auto":
		var below: String = stack[stack.size() - 2].name if stack.size() > 1 else ""
		transition = "wipe" if below in ["home", "title"] else "slide_out"
	if stack.size() <= 1:
		if current_name() == "title": confirm_quit()
		else: go("title", {}, transition, "reset")
		return
	_transition(transition, func() -> void: _pop(); screen_changed.emit(current_name()))

func home(transition := "wipe") -> void:
	go("home", {}, transition, "reset")

func _on_home_nav(dest: String) -> void:
	var target: String = HOME_ROUTES.get(dest, dest)
	if target == "title": go("title", {}, "wipe", "reset")
	elif dest == "characters" and current() != null and "selected_character" in current() and String(current().selected_character) != "":
		go(target, {"id": String(current().selected_character)}, "wipe")
	else: go(target, {}, "wipe")

## Native input controls get the same feedback as drawn ones: key clicks while typing,
## a pop when a dropdown opens, a select when an entry is chosen, a soft tick on focus.
func _wire_native(n: Node) -> void:
	if n is LineEdit:
		n.text_changed.connect(func(_t): UiHub.sfx("type", 1.15 + randf() * 0.1))
		n.focus_entered.connect(func(): if UiHub.focus_sound_ok(): UiHub.sfx("focus", 1.1))
		n.text_submitted.connect(func(_t): UiHub.sfx("confirm"))
	elif n is TextEdit:
		n.text_changed.connect(func(): UiHub.sfx("type", 1.15 + randf() * 0.1))
		n.focus_entered.connect(func(): if UiHub.focus_sound_ok(): UiHub.sfx("focus", 1.1))
	elif n is OptionButton:
		n.pressed.connect(func(): UiHub.sfx("popup", 1.1))
		n.item_selected.connect(func(_i): UiHub.sfx("select"))
		n.get_popup().id_focused.connect(func(_i): UiHub.sfx("hover"))

## 看板 character: user-chosen showcase if set, else the best friend so far (highest 好感度 among the contest cast), else the origin's guide.
func _home_showcase(h: Control) -> void:
	var D = preload("res://scripts/ui/ui_data.gd")
	var saved_id := String(UiHub.get_meta("showcase_id", ""))
	var best := saved_id
	var known: Dictionary = Game.known()
	var is_unlocked := func(cid: String) -> bool:
		var cname := D.name_of(cid)
		return cid == "rin" or (known.has(cname) and not known[cname].is_empty())
	if best == "" or not is_unlocked.call(best) or D.art_path(best, "daily", "neutral") == "":
		var orig_leads := {"sereth": "rin", "staff": "bingtang", "omanut": "mingkong", "jwanshakti": "alanya", "longyuan": "yanyuan", "gloria": "alice", "akitsu": "yangxiang", "custom": "ye"}
		best = String(orig_leads.get(String(Game.persona.get("origin", "sereth")), "rin"))
		if D.art_path(best, "daily", "neutral") == "": best = "rin"
		var top := -1.0
		for name in known:
			var id: String = D.id_of(name)
			if id != "" and float(known[name].get("好感度", 0)) > top: top = float(known[name].get("好感度", 0)); best = id
	var path: String = D.art_path(best, "daily", "neutral")
	if path != "": h.set_showcase(best, D.name_of(best))

## The home sample keeps its own buttons; give each one hover / press / theme sounds from here.
func _wire_home_sounds(h: Control) -> void:
	var i := 0
	for b in h.home_buttons.values():
		var k := i
		b.mouse_entered.connect(func(): UiHub.sfx("hover", 1.0 + k * 0.04))
		b.pressed.connect(func(): UiHub.sfx("confirm_big" if b == h.home_buttons.get("story") else "confirm"); UiHub.haptic(14))
		i += 1
	h.status.mouse_entered.connect(func(): UiHub.sfx("hover"))
	h.status.pressed.connect(func(): UiHub.sfx("popup"))
	h.power.pressed.connect(func(): UiHub.sfx("back"))
	for id in ["Sun", "Moon"]:
		var sb: Button = h.menu.get_node("ThemeSwitch/" + id)
		sb.pressed.connect(func(): UiHub.sfx("theme_day" if id == "Sun" else "theme_night"))

# ---------- transitions ----------
func _transition(kind: String, swap: Callable) -> void:
	if UiHub.reduced_motion or kind == "none":
		swap.call(); return
	busy = true
	match kind:
		"slide_in": _slide(swap, 1.0)
		"slide_out": _slide(swap, -1.0)
		"fade", "slide": _fade(swap, kind == "slide")
		"shutter": _shutter(swap)
		_: _wipe(swap)

## Three slanted slabs (accent, ink, background) sweep across; the page swaps under cover.
## Timing copied from the reference HTML: 0.84s sweep, 50ms stagger, swap at 0.42s.
## Mystic iris (2026-11-14): a paper-coloured disc grows from the centre behind a thin ring and a
## sweeping crescent, a four-point star flares at full cover, the page swaps underneath, then the
## disc opens again as a ring that keeps expanding. 0.9s total, swap at 0.42s.
func _wipe(swap: Callable) -> void:
	UiHub.sfx("wipe")
	wipe_layer.visible = true
	for c in wipe_layer.get_children(): c.queue_free()
	var cover := Control.new(); cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wipe_layer.add_child(cover); cover.size = logical
	var c := logical * 0.5
	var far := c.length() + 40.0
	var st := {"k": 0.0, "out": 0.0}
	cover.draw.connect(func():
		var bg := UiHub.c("background"); var acc := UiHub.c("accent"); var ink := UiHub.c("ink")
		var k: float = st.k; var o: float = st.out
		var r := far * k
		if o <= 0.0:
			cover.draw_circle(c, r, bg)
			cover.draw_arc(c, r, 0, TAU, 96, Color(ink, 0.5), 1.2, true)
			Kit.crescent(cover, c, r + 10.0, -PI * 0.5 + TAU * k, -PI * 0.5 + TAU * k + PI * 0.7, 8.0, acc, 48)
			Kit.line_fade(cover, c + Vector2(-far, far * 0.55) * k, c + Vector2(far, -far * 0.55) * k, Color(acc, 0.6), 1.2, 16)
		else:
			# opening: draw the paper as a thick ring outside an expanding hole
			var hole := far * Kit.curve(o)
			var ring := PackedVector2Array()
			var n := 96
			for i in range(n + 1): ring.append(c + Vector2.from_angle(TAU * i / n) * hole)
			for i in range(n + 1): ring.append(c + Vector2.from_angle(TAU * (n - i) / n) * (far + 60.0))
			var tri := Geometry2D.triangulate_polygon(ring)
			if not tri.is_empty(): cover.draw_colored_polygon(ring, Color(bg, 1.0 - o * 0.6))
			cover.draw_arc(c, hole, 0, TAU, 96, Color(acc, 1.0 - o), 1.6, true)
			cover.draw_arc(c, hole * 0.82, 0, TAU, 96, Color(ink, 0.35 * (1.0 - o)), 1.0, true)
		var flare: float = sin(clampf((k - 0.7) / 0.3, 0.0, 1.0) * PI * 0.5) * (1.0 - o)
		if flare > 0.0:
			Kit.star4(cover, c, 90.0 * flare + 10.0, Color(acc, flare), 0.08, o * 0.6)
			cover.draw_arc(c, 60.0 + 40.0 * o, 0, TAU, 64, Color(acc, 0.6 * flare), 1.2, true))
	var t := create_tween()
	t.tween_method(func(v): st.k = v; cover.queue_redraw(), 0.0, 1.0, 0.42).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(swap); t.tween_callback(_scan)
	t.tween_method(func(v): st.out = v; cover.queue_redraw(), 0.001, 1.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(func(): cover.queue_free(); wipe_layer.visible = false; busy = false)

func _fade(swap: Callable, slide: bool) -> void:
	var cover := ColorRect.new(); cover.color = UiHub.c("background"); cover.modulate.a = 0.0
	wipe_layer.visible = true; wipe_layer.add_child(cover); cover.size = logical
	var t := create_tween()
	t.tween_property(cover, "modulate:a", 1.0, 0.16)
	t.tween_callback(swap)
	var nudge := func() -> void:
		var n := current()
		if slide and n:
			n.position.x = 60.0
			create_tween().tween_property(n, "position:x", 0.0, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(nudge)
	t.tween_property(cover, "modulate:a", 0.0, 0.24)
	t.tween_callback(func(): cover.queue_free(); wipe_layer.visible = false; busy = false)

## Sub-page move: the old frame (snapshot) drifts away and fades while the new page slides in.
## dir 1 = deeper, -1 = back. 0.42s expo out; feels continuous instead of a curtain.
func _slide(swap: Callable, dir: float) -> void:
	UiHub.sfx("slide", 1.0 if dir > 0 else 0.86)
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		swap.call(); busy = false; return
	var shot := TextureRect.new(); shot.texture = ImageTexture.create_from_image(img)
	shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; shot.stretch_mode = TextureRect.STRETCH_SCALE
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wipe_layer.visible = true; wipe_layer.add_child(shot); shot.position = Vector2.ZERO; shot.size = logical
	var edge := Polygon2D.new(); var sk := logical.y * 0.18
	# a hairline sweep (thin accent line with a pale wake) instead of the old solid slab
	edge.polygon = PackedVector2Array([Vector2(sk, 0), Vector2(sk + 2, 0), Vector2(2, logical.y), Vector2(0, logical.y)])
	edge.color = UiHub.c("accent"); wipe_layer.add_child(edge)
	var wake := Polygon2D.new(); wake.polygon = PackedVector2Array([Vector2(sk + 2, 0), Vector2(sk + 120, 0), Vector2(120, logical.y), Vector2(2, logical.y)])
	wake.color = UiHub.c("background", 0.55); edge.add_child(wake)
	edge.position.x = logical.x if dir > 0 else -sk - 10
	swap.call()
	_scan()
	var n := current()
	if n: n.position.x = 90.0 * dir
	var t := create_tween().set_parallel(true).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(shot, "position:x", -160.0 * dir, 0.42)
	t.tween_property(shot, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	t.tween_property(edge, "position:x", -sk - 10 if dir > 0 else logical.x, 0.42)
	if n: t.tween_property(n, "position:x", 0.0, 0.48)
	t.chain().tween_callback(func(): shot.queue_free(); edge.queue_free(); wipe_layer.visible = false; busy = false)

## Battle entry: two dark wedges close along the diagonal, an accent cut flashes, then they part.
func _shutter(swap: Callable) -> void:
	UiHub.sfx("battle_enter")
	wipe_layer.visible = true
	for c in wipe_layer.get_children(): c.queue_free()
	var a := Polygon2D.new(); var b := Polygon2D.new(); var cut := Line2D.new()
	var W := logical.x; var H := logical.y
	a.polygon = PackedVector2Array([Vector2(-W * 0.2, -H * 0.1), Vector2(W * 1.25, -H * 0.1), Vector2(-W * 0.2, H * 1.6)])
	b.polygon = PackedVector2Array([Vector2(W * 1.2, -H * 0.6), Vector2(W * 1.2, H * 1.1), Vector2(-W * 0.25, H * 1.1)])
	a.color = UiHub.c("background"); b.color = UiHub.c("surface2")
	cut.points = PackedVector2Array([Vector2(-W * 0.1, H * 1.25), Vector2(W * 1.1, -H * 0.2)]); cut.width = 3; cut.default_color = UiHub.c("accent")
	for n in [a, b, cut]: wipe_layer.add_child(n)
	a.position = Vector2(-W, -H * 0.5); b.position = Vector2(W, H * 0.5); cut.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(a, "position", Vector2.ZERO, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_property(b, "position", Vector2.ZERO, 0.32).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.chain().tween_property(cut, "modulate:a", 1.0, 0.04)
	t.chain().tween_callback(swap)
	t.chain().tween_interval(0.18)
	t.chain().tween_property(cut, "width", 0.0, 0.2)
	t.parallel().tween_property(a, "position", Vector2(-W, -H * 0.5), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(b, "position", Vector2(W, H * 0.5), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(func(): wipe_layer.visible = false; busy = false)

## Day/night: freeze the current frame, switch the palette underneath, then let a circle grow
## from the pointer and wipe the old frame away (accent ring on the edge).
var _reveal_node: TextureRect
func _night_reveal(value: bool) -> void:
	UiHub.sfx("theme_night" if value else "theme_day")
	if is_instance_valid(_reveal_node): _reveal_node.queue_free()
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		UiHub.set_night(value, false); return
	var over := TextureRect.new(); over.texture = ImageTexture.create_from_image(img)
	over.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; over.stretch_mode = TextureRect.STRETCH_SCALE
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(over); over.position = Vector2.ZERO; over.size = size
	_reveal_node = over
	var m := ShaderMaterial.new(); m.shader = preload("res://scripts/ui/reveal.gdshader")
	var c := get_local_mouse_position()
	if c.x < 0 or c.y < 0 or c.x > size.x or c.y > size.y: c = Vector2(size.x - 120, 60)
	m.set_shader_parameter("extent", size); m.set_shader_parameter("center", c); m.set_shader_parameter("radius", 0.0)
	over.material = m
	UiHub.set_night(value, false)
	m.set_shader_parameter("ring_color", UiHub.c("accent"))
	var far := 0.0
	for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]: far = maxf(far, c.distance_to(corner))
	var t := create_tween()
	t.tween_method(func(r): m.set_shader_parameter("radius", r), 0.0, far + 40.0, 0.8).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(over.queue_free)

## One soft light band crosses the new page top to bottom (0.55s), like a screen settling.
func _scan() -> void:
	if UiHub.reduced_motion: return
	UiHub.sfx("scan")
	var band := Control.new(); band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(band); band.size = Vector2(logical.x, 160)
	var paint := func() -> void:
		var g := UiHub.c("glow", 0.12)
		band.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(logical.x, 0), Vector2(logical.x, 160), Vector2(0, 160)]),
			PackedColorArray([Color(g, 0), Color(g, 0), g, g]))
		Kit.line_fade(band, Vector2(0, 159), Vector2(logical.x, 159), UiHub.c("accent", 0.4), 1.0, 24)
	band.draw.connect(paint)
	band.position.y = -160
	var t := create_tween(); t.tween_property(band, "position:y", logical.y, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(band.queue_free)

# ---------- overlays ----------
func dialog(spec: Dictionary) -> Control:
	UiHub.quiet_focus()
	UiHub.sfx("error" if spec.get("tone", "") == "error" else "popup")
	var d := Overlay.Dialog.new(); d.spec = spec; d.size = logical
	overlay_layer.add_child(d); dialogs.append(d)
	d.chosen.connect(func(_id): dialogs.erase(d))
	return d

func prompt(spec: Dictionary, on_confirm: Callable) -> Control:
	if not spec.has("input"): spec["input"] = {}
	if not spec.has("buttons"):
		spec["buttons"] = [
			{"id": "cancel", "text": "取消", "icon": "close"},
			{"id": "ok", "text": "确定", "icon": "tri_right", "kind": "primary"}
		]
	var d := dialog(spec)
	d.chosen.connect(func(id: String):
		if (id == "ok" or id == "confirm" or id == spec.get("confirm_id", "ok")) and on_confirm.is_valid():
			on_confirm.call(d.get_input_text())
	)
	return d

func toast(msg: String, icon_name := "info") -> void:
	UiHub.sfx("toast")
	var t := Overlay.Toast.new(); t.message = msg; t.icon_name = icon_name
	toast_layer.add_child(t)
	t.position = Vector2((logical.x - t.size.x) * 0.5, 34 + toast_layer.get_child_count() * 4)
	t.play(34)

func reward(entries: Array) -> Control:
	UiHub.sfx("reward")
	var r := Overlay.Reward.new(); r.entries = entries; r.size = logical
	overlay_layer.add_child(r); return r

func open_music_player() -> Control:
	for c in overlay_layer.get_children():
		if c.has_meta("music_player_modal"):
			return c
	UiHub.quiet_focus()
	UiHub.sfx("music_open")
	var mp := Overlay.MusicPlayer.new()
	mp.set_meta("music_player_modal", true)
	mp.size = logical
	overlay_layer.add_child(mp)
	return mp

func open_story_oracle(mode := "") -> Control:
	if mode != "":
		UiHub.story_oracle().set_mode(mode)
	for c in overlay_layer.get_children():
		if is_instance_valid(c) and c.has_meta("story_oracle_modal"):
			c.move_to_front()
			return c
	UiHub.quiet_focus()
	UiHub.sfx("popup")
	var ov := OracleOverlay.new()
	ov.size = logical
	overlay_layer.add_child(ov)
	return ov

func open_text_composer(spec: Dictionary, on_apply: Callable, on_close := Callable()) -> Control:
	return Overlay.open_text_composer(overlay_layer, spec, on_apply, on_close)

func open_app_updater() -> Control:
	for c in overlay_layer.get_children():
		if is_instance_valid(c) and c.has_meta("app_update_modal"):
			c.move_to_front()
			return c
	UiHub.quiet_focus()
	UiHub.sfx("popup")
	var uv := UpdateOverlay.new()
	uv.owner_root = self
	uv.size = logical
	overlay_layer.add_child(uv)
	return uv

## Standard recoverable error dialogs (13 异常与恢复). retry is called when the player retries.
func error(kind: String, retry := Callable()) -> void:
	var specs := {
		"network": {"title": "连接中断", "message": "本次输入已保留。", "icon": "wifi_off", "buttons": [{"id": "retry", "text": "重试", "icon": "refresh", "kind": "primary"}, {"id": "cancel", "text": "返回", "icon": "tri_left"}]},
		"resource": {"title": "资源未能载入", "message": "缺失的素材不会被替换成别的内容。", "icon": "file_block", "buttons": [{"id": "retry", "text": "重新载入", "icon": "refresh", "kind": "primary"}, {"id": "cancel", "text": "返回", "icon": "tri_left"}]},
		"save": {"title": "未能保存", "message": "进度仍在内存中，可以重试或先导出备份。", "icon": "file_warn", "buttons": [{"id": "retry", "text": "重试保存", "icon": "refresh", "kind": "primary"}, {"id": "export", "text": "导出备份", "icon": "upload"}, {"id": "cancel", "text": "返回", "icon": "tri_left"}]},
	}
	var spec: Dictionary = specs.get(kind, specs.resource); spec["tone"] = "error"
	var d := dialog(spec)
	var on_choice := func(id: String) -> void:
		if id == "retry" and retry.is_valid(): retry.call()
		elif id == "export": UiHub.request("save.export_backup", {})
	d.chosen.connect(on_choice)

func _on_game_error(kind: String, msg: String) -> void:
	if kind == "api_configuration":
		for existing in dialogs:
			if is_instance_valid(existing) and existing.spec.get("id", "") == "api_configuration": return
		var d := dialog({"id": "api_configuration", "title": "请先配置 API", "message": msg + "\n本次操作未执行，已输入的内容会保留。", "icon": "ai", "tone": "error", "buttons": [{"id": "cancel", "text": "返回", "icon": "back"}, {"id": "configure", "text": "去配置", "icon": "gear", "kind": "primary"}]})
		d.chosen.connect(func(id):
			if id == "configure": go("connect", {}, "slide_in")
			elif current_name() == "story" and is_instance_valid(current().input): current().input.call_deferred("grab_focus"))
		return
	if kind == "network": error("network"); return
	dialog({"title": "出错了", "message": msg, "icon": "warn", "tone": "error", "buttons": [{"id": "ok", "text": "知道了", "icon": "close", "kind": "primary"}]})

func confirm_quit() -> void:
	var d := dialog({"title": "退出游戏", "message": "未保存的进度会丢失。", "icon": "power", "buttons": [{"id": "cancel", "text": "取消", "icon": "close"}, {"id": "quit", "text": "退出", "icon": "power", "kind": "primary"}]})
	var on_choice := func(id: String) -> void:
		if id == "quit":
			UiHub.request("app.quit", {})
			get_tree().quit()
	d.chosen.connect(on_choice)

func _handle_back() -> void:
	if not dialogs.is_empty():
		var d = dialogs.back()
		if is_instance_valid(d): d.cancel()
		return
	for c in overlay_layer.get_children():
		if c.has_method("close"): c.close(); return
		if c.has_meta("close_cb"): c.get_meta("close_cb").call(); return
		if c.has_signal("closed"): c.emit_signal("closed"); c.queue_free(); return
	var n := current()
	if n and n.has_method("on_back") and n.on_back(): return
	back()

func _input(event: InputEvent) -> void:
	var pos := Vector2(-1, -1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: pos = event.position
	if pos.x >= 0.0 and not UiHub.reduced_motion: _tap_mark(pos / stage.scale.x)

func _tap_mark(p: Vector2) -> void:
	var m := Control.new(); m.mouse_filter = Control.MOUSE_FILTER_IGNORE; m.position = p
	toast_layer.add_child(m)
	var k := [0.0]
	var paint := func() -> void:
		var v: float = k[0]; var r := 8.0 + 30.0 * v
		m.draw_arc(Vector2.ZERO, r, 0, TAU, 32, UiHub.c("accent", 0.7 * (1.0 - v)), 1.2, true)
		m.draw_arc(Vector2.ZERO, r * 0.55, 0, TAU, 24, UiHub.c("ink", 0.3 * (1.0 - v)), 1.0, true)
		Kit.star4(m, Vector2.ZERO, 9.0 * (1.0 - v) + 1.0, UiHub.c("accent", 1.0 - v), 0.14, v * 0.8)
		for j in range(4):
			var d := Vector2.from_angle(PI * 0.25 + PI * 0.5 * j)
			m.draw_circle(d * (10.0 + 30.0 * v), 1.8 * (1.0 - v), UiHub.c("accent", 1.0 - v))
	m.draw.connect(paint)
	var t := m.create_tween(); t.tween_method(func(v): k[0] = v; m.queue_redraw(), 0.0, 1.0, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_callback(m.queue_free)

## Clicks that hit no control still answer with a soft tick (any input gets feedback).
func _gui_input(event: InputEvent) -> void:
	if current_name() not in ["prologue", "notice"] and event is InputEventMouseButton and event.pressed: UiHub.sfx("tick")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_back(); get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _handle_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST: UiHub.request("app.closing", {})

func _music_state_changed(part: String) -> void:
	if part == "saves" and _has_any_save() and current_name() == "prologue":
		var scr := current()
		if scr != null and not bool(scr.params.get("replay", false)) and String(scr.get("phase")) == "mode" and not bool(scr.get("mode_shattering")):
			_reset("title", {"phase": "menu"})
			screen_changed.emit("title")
			return
	if part == "stat" and current_name() == "home" and current() != null:
		if current().has_method("set_showcase"): _home_showcase(current())
		elif current().has_method("refresh"): current().refresh()
	if part == "stat":
		var cur_var := String(Game.hero().get("当前BGM", ""))
		if cur_var != _last_story_bgm:
			_last_story_bgm = cur_var
			if cur_var != "" and UiHub.music_override != "":
				UiHub.music_override = ""
	if part == "stat" or part == "session": _update_music()

func _music_origin_context() -> String:
	var top := current_name()
	if top in ["gate", "notice", "prologue", "opening", "workshop", "home", "story"]:
		return top
	if top in ["title", "connect", "origin", "create", "loading"]:
		return "title"
	# Secondary screens inherit BGM from the mode that opened them (home vs story vs title),
	# never accidentally falling back to sereth track #26 when opened from home.
	for i in range(stack.size() - 2, -1, -1):
		var nm := String(stack[i].get("name", ""))
		if nm == "story": return "story"
		if nm == "home": return "home"
		if nm == "title": return "title"
	return "home"

func _update_music() -> void:
	var scr_name := current_name()
	if scr_name != "workshop":
		UiHub.stop_workshop_activation(false)
	var ctx := _music_origin_context()
	if ctx in ["gate", "notice"]:
		UiHub.play_music("无音乐"); return
	if ctx in ["prologue", "opening"]:
		# 开场页自己不循环地播放 crystar.ogg 并以它为全片时钟，这里只让出背景乐
		UiHub.play_music("无音乐"); return
	if ctx == "title":
		UiHub.play_music(String(UiHub.music_manifest.get("title_track", "Main Theme")))
		return
	if ctx == "home":
		var key := "home_night" if UiHub.night_target else "home_day"
		UiHub.play_music(UiHub.ui_screen_track(key, String(UiHub.music_manifest.get("title_track", "Main Theme"))))
		return
	if ctx == "workshop":
		UiHub.play_music(UiHub.ui_screen_track("workshop", "luminous"))
		return
	var value := String(Game.hero().get("当前BGM", ""))
	if value in ["无", "没有", "静音", "none", "null", "silent", "无音乐"]:
		UiHub.play_music("无音乐"); return
	if Game.messages.is_empty() and value == "":
		value = String(UiHub.music_manifest.get("title_track", "Main Theme"))
	elif value in ["", "待初始化", "未初始化", "空"]:
		var loc_spec := UiHub.music_spec_for_location(String(Game.hero().get("当前地点", "")))
		value = String(loc_spec.get("title", UiHub.music_manifest.get("title_track", "Main Theme")))
	UiHub.play_music(value)

func _exit_tree() -> void:
	UiHub.stop_music()
