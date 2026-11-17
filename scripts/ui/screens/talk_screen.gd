extends "res://scripts/ui/ui_screen.gd"
## 看板角色交谈 (1-on-1 Isolated Bridge Chat synced with GameDatabase + Hotaru #60).
## Reads & persists per-character bridge_dialogues in Game.db; sends only filtered Worldbook +
## character_knowledge_facts + visible <sumUp> summaries (never full main-story chatHistory).

static var logs: Dictionary = {}      # Legacy fallback cache for external test hooks
var id := ""
var input: LineEdit
var list_box: VBoxContainer
var scroll: ScrollContainer

func _unlocked_roster() -> Array:
	return Game.unlocked_ids(true)

func open(owner_root: Node, p: Dictionary) -> void:
	super.open(owner_root, p)
	id = String(p.get("id", ""))

func build() -> void:
	chrome("看板角色交谈")
	if not Game.changed.is_connected(_on_game): Game.changed.connect(_on_game)
	var unlocked: Array = _unlocked_roster()
	if id == "" and not unlocked.is_empty():
		id = String(unlocked[0])
	if id == "" or not (id in unlocked):
		var empty_p := plate(Rect2(360, 260, 1200, 440), {"shape": "cut", "slant": 36, "corner": "tr", "hatch": true}, "c", 0.06)
		empty_p.name = "TalkLockedNotice"
		icon("lock", Rect2(564, 54, 72, 72), "muted", "c", empty_p)
		var lock_title := "当前暂无已解锁的看板角色" if unlocked.is_empty() else ("「%s」尚未在主线中解锁" % Data.name_of(id))
		text(lock_title, Rect2(120, 148, 960, 52), 32, "ink", 850, "c", empty_p, HORIZONTAL_ALIGNMENT_CENTER)
		text("只有你在主线剧情中正式邂逅的角色，才会登上看板并开放 1 对 1 私聊。", Rect2(120, 214, 960, 64), 21, "muted", 600, "c", empty_p, HORIZONTAL_ALIGNMENT_CENTER)
		var go_st := btn("前往主线剧情", "play", "primary", Rect2(310, 314, 280, 74), func(): root.go("story_hub"), "c", -1.0, empty_p, 22)
		go_st.name = "LockedGoStory"
		if not unlocked.is_empty():
			var sw_btn := btn("切到已解锁角色", "swap", "secondary", Rect2(610, 314, 280, 74), func():
				id = String(unlocked[0]); refresh(false)
			, "c", -1.0, empty_p, 21)
			sw_btn.name = "LockedSwitchUnlocked"
		return

	var art := portrait(id, "full", Rect2(40, 110, 700, 970), null, "lb")
	art.framing = "home"; art.frame = false; art.always_show = true; art.show_art(id, "daily", "neutral")
	var p := plate(Rect2(760, 120, 1120, 900), {"slant": 50, "corner": "tr"}, "r", 0.05)
	var prev := btn("", "back", "ghost", Rect2(24, 22, 52, 52), func(): _cycle(-1), "c", -1.0, p)
	prev.name = "PrevChar"; prev.disabled = unlocked.size() <= 1
	text(Data.name_of(id), Rect2(80, 18, 160, 60), 30, "ink", 700, "c", p, HORIZONTAL_ALIGNMENT_CENTER)
	var nx := btn("", "next", "ghost", Rect2(244, 22, 52, 52), func(): _cycle(1), "c", -1.0, p)
	nx.name = "NextChar"; nx.disabled = unlocked.size() <= 1
	var char_st: Dictionary = Game.db_char_state(id)
	var known: Dictionary = Game.known()
	var k_entry: Dictionary = known.get(Data.name_of(id), {}) if known.get(Data.name_of(id)) is Dictionary else {}
	var aff = k_entry.get("好感度", char_st.get("affection", null))
	var lewd = k_entry.get("色情值", char_st.get("lewdness", null))
	var form_s := String(k_entry.get("当前形态", char_st.get("form", "日常")))
	icon("sparkle", Rect2(302, 36, 22, 22), "ink", "c", p)
	text("好感 " + (str(int(aff)) if aff != null else "—"), Rect2(328, 18, 114, 60), 19, "ink", 650, "c", p)
	icon("heart", Rect2(444, 36, 22, 22), "accent", "c", p)
	text("色情 " + (str(int(lewd)) if lewd != null else "—"), Rect2(470, 18, 118, 60), 19, "ink", 650, "c", p)

	var db_btn := btn("她的记忆", "docs", "chip", Rect2(604, 22, 168, 52), func():
		root.go("database", {"tab": "characters", "character": id})
	, "c", -1.0, p, 18)
	db_btn.name = "OpenCharDb"
	var cmp_btn := btn("归纳", "book", "ghost", Rect2(782, 22, 128, 52), func(): Game.db_compress_bridge(id), "c", -1.0, p, 17)
	cmp_btn.name = "CompressBridge"
	var clr_btn := btn("清空", "trash", "ghost", Rect2(920, 22, 128, 52), func(): Game.db_clear_bridge(id), "c", -1.0, p, 17)
	clr_btn.name = "ClearBridge"

	# Database isolation & memory status line
	var vis_info := Game.db_summaries_for_char(id)
	var loc_s := String(char_st.get("last_known_location", ""))
	if loc_s == "": loc_s = "未记录"
	var memo_s := String(char_st.get("attitude_memo", ""))
	if memo_s == "": memo_s = "常规印象"
	if memo_s.length() > 18: memo_s = memo_s.substr(0, 17) + "…"
	text("私聊隔离 · 形态:%s · 可知 %d 件(屏蔽私密 %d) · %s · 印象:%s" % [
		form_s, vis_info.get("visible", []).size(), int(vis_info.get("hidden_private_count", 0)), loc_s.split("·")[-1], memo_s
	], Rect2(40, 88, 1040, 34), 16, "muted", 600, "c", p)

	scroll = ScrollContainer.new(); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; scroll.name = "ChatScroll"
	put(scroll, Rect2(40, 132, 1040, 622), "c", -1.0, p)
	list_box = VBoxContainer.new(); list_box.add_theme_constant_override("separation", 18)
	list_box.custom_minimum_size.x = 1020; scroll.add_child(list_box)

	var db_log: Dictionary = Game.db_bridge_log(id)
	var db_sum := String(db_log.get("summary", "")).strip_edges()
	var lines: Array = db_log.get("messages", [])
	if lines.is_empty() and logs.has(id):
		lines = logs.get(id, [])
	if db_sum != "":
		_hint("【远期单聊摘要】\n" + db_sum)
	if lines.is_empty():
		_hint("和%s开启一对一私聊吧。仅加载她本人完整人设与已知事件（每次回复 1～5 条纯台词，绝不带旁白与主线剧透）。" % Data.name_of(id))
	var prev_who := ""
	for l in lines:
		var role_s := String(l.get("role", l.get("who", "me")))
		var is_me := (role_s == "user" or role_s == "me")
		var side := "me" if is_me else "them"
		_bubble(side, String(l.get("text", "")), side != prev_who)
		prev_who = side
	var busy_bridge: bool = bool(Game.generation.get("busy", false)) and String(Game.generation.get("kind", "")) == "bridge_chat"
	if busy_bridge:
		_hint("%s 正在输入消息…" % Data.name_of(id))
	input = LineEdit.new(); input.name = "TalkInput"; input.placeholder_text = "输入要单独对%s说的话……" % Data.name_of(id)
	put(input, Rect2(40, 780, 820, 84), "c", -1.0, p)
	input.text_submitted.connect(func(_t): _send())
	var send := btn("发送中" if busy_bridge else "发送", "send", "primary", Rect2(880, 780, 200, 84), func(): _send(), "c", -1.0, p, 26)
	send.name = "Send"; send.press_sfx = "none"; send.disabled = busy_bridge
	call_deferred("_to_end")

func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game): Game.changed.disconnect(_on_game)

func _on_game(part: String) -> void:
	if part in ["db", "stat", "generation"]:
		refresh(false)

func _hint(t: String) -> void:
	var l := Lbl.new(); l.setup(t, 19, "muted", 500); l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.custom_minimum_size = Vector2(1000, 56)
	list_box.add_child(l)

func _bubble(who: String, t: String, show_who := true) -> void:
	var b := Bubble.new(); b.mine = who == "me"; b.text = t; b.who = "我" if b.mine else Data.name_of(id); b.show_who = show_who
	b.custom_minimum_size = Vector2(1000, b.measure(1000.0))
	list_box.add_child(b)

func _send() -> void:
	var t := input.text.strip_edges()
	if t == "": UiHub.sfx("deny"); return
	if not Game.ensure_generation_ready(): return
	UiHub.sfx("send")
	input.text = ""
	request("character.chat", {"character": id, "text": t})
	refresh(false)

## Service hook: append a reply line for a character (kept for external test compatibility).
static func add_reply(cid: String, t: String) -> void:
	if not logs.has(cid): logs[cid] = []
	logs[cid].append({"who": "them", "text": t})

func _cycle(step: int) -> void:
	var r := _unlocked_roster()
	if r.size() <= 1: return
	var i := r.find(id)
	id = String(r[(i + step + r.size()) % r.size()])
	UiHub.sfx("swap"); refresh(true)

func _to_end() -> void:
	if is_instance_valid(scroll): scroll.scroll_vertical = 1 << 20
	if is_instance_valid(input): input.grab_focus()


class Bubble extends Control:
	const K = preload("res://scripts/ui/ui_kit.gd")
	var mine := false
	var text := ""
	var who := ""
	var show_who := true
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE; UiHub.palette_changed.connect(queue_redraw)
	func _lines(w: float) -> PackedStringArray:
		var f := K.font(500); var px := UiHub.fs(24)
		var out := PackedStringArray(); var cur := ""
		for ch in text:
			if ch == "\n":
				out.append(cur); cur = ""
			elif f.get_string_size(cur + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > w:
				out.append(cur); cur = ch
			else: cur += ch
		if cur != "": out.append(cur)
		return out
	func measure(total: float) -> float:
		var top_pad := 30.0 if show_who else 4.0
		return top_pad + 28.0 + _lines(total * 0.62).size() * 36.0
	func _draw() -> void:
		var top_y := 30.0 if show_who else 4.0
		var lines := _lines(size.x * 0.62)
		var w := 0.0
		for l in lines: w = maxf(w, K.text_width(l, UiHub.fs(24), 500))
		w = maxf(w + 56.0, 120.0)
		var h := 24.0 + lines.size() * 36.0
		var x := size.x - w - 10.0 if mine else 10.0
		var r := Rect2(x, top_y, w, h)
		var poly := K.plate_poly(r, 26.0 if not mine else 14.0, 14.0 if not mine else 26.0, 8)
		draw_colored_polygon(poly, UiHub.c("surface", 0.92))
		if mine: draw_colored_polygon(poly, UiHub.c("accent", 0.05))
		draw_polyline(K.closed(poly), UiHub.c("accent" if mine else "line"), 1.2, true)
		draw_line(Vector2(x + 18, top_y + h), Vector2(x + 58, top_y + h), UiHub.c("accent"), 1.6, true)
		if show_who:
			K.text(self, Rect2(x + (w - 100 if mine else 4), 0, 100, 28), who, UiHub.fs(18), UiHub.c("muted"), HORIZONTAL_ALIGNMENT_RIGHT if mine else HORIZONTAL_ALIGNMENT_LEFT, 500)
		for i in range(lines.size()):
			K.text(self, Rect2(x + 28, top_y + 12.0 + i * 36.0, w - 40, 36), lines[i], UiHub.fs(24), UiHub.c("ink"), HORIZONTAL_ALIGNMENT_LEFT, 500)
