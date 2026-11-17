extends "res://scripts/ui/ui_screen.gd"
## 旅途手札 (Player-friendly Journal & Memory Hub built on GameDatabase + Hotaru V8).
## Presents affection, lewdness, fetishes, form, timeline journal, hero state, and clear privacy guards
## without burying players in raw developer text walls.

const TABS := [
	["characters", "同伴档案", "person"],
	["timeline", "剧情大事记", "docs"],
	["world_state", "主角与局势", "globe"],
	["bridge_preview", "私聊保密", "chat"],
]

var tab := "characters"
var char_group := "cast" # "cast" (21角色组) | "npcs" (8重要NPC)
var vis_filter := "all" # all | world_public | present_only
var sum_picked := 0
var char_id := ""
var char_page := 0
var fact_kind := "manual"
var fact_draft := ""
var preview_draft := ""
var show_raw_prompt := false

var editing_sum := false
var edit_sum_id := ""
var draft_time := ""
var draft_loc := ""
var draft_roles := ""
var draft_vis := "present_only"
var draft_event := ""
var draft_clues := ""
var draft_changes := ""

func _group_roster() -> Array:
	var unlocked := Game.unlocked_ids(true)
	var base := Data.npc_ids() if char_group == "npcs" else Data.cast_ids()
	return base.filter(func(cid): return String(cid) in unlocked)

func open(owner_root: Node, p: Dictionary) -> void:
	super.open(owner_root, p)
	if p.has("tab") and String(p.get("tab", "")) != "":
		tab = String(p.get("tab", "characters"))
	if p.has("character") and String(p.get("character", "")) != "":
		var want_cid := String(p.get("character", ""))
		if want_cid in Game.unlocked_ids(true):
			char_id = want_cid
			char_group = "npcs" if Data.is_npc(char_id) else "cast"
	if char_id == "" and not _group_roster().is_empty():
		char_id = String(_group_roster()[0])

func build() -> void:
	if params.has("tab") and String(params.get("tab", "")) != "":
		tab = String(params.get("tab", "characters"))
		params.erase("tab")
	if params.has("character") and String(params.get("character", "")) != "":
		var want_cid := String(params.get("character", ""))
		params.erase("character")
		if want_cid in Game.unlocked_ids(true):
			char_id = want_cid
			char_group = "npcs" if Data.is_npc(char_id) else "cast"
			var r_tmp := _group_roster()
			var idx_tmp := r_tmp.find(char_id)
			if idx_tmp >= 0: char_page = idx_tmp / 5
	var roster_all := _group_roster()
	if char_id == "" or roster_all.find(char_id) < 0:
		char_id = String(roster_all[0]) if not roster_all.is_empty() else ""

	chrome("旅途手札")
	decor(43, Rect2(Vector2.ZERO, size), 0.45)
	if not Game.changed.is_connected(_on_game): Game.changed.connect(_on_game)

	var tab_btns: Array = []
	for k in range(TABS.size()):
		var t_spec: Array = TABS[k]
		var tid: String = t_spec[0]
		var b := btn(t_spec[1], t_spec[2], "tab", Rect2(0, 146 + k * g(94), 312, 78), func():
			tab = tid
			editing_sum = false
			refresh(false)
		, "l", 0.03 * k, null, 22)
		b.selected = tab == tid
		b.slant = 24
		b.name = "Tab_" + tid
		tab_btns.append(b)
	cursor_for(tab_btns)

	_build_sidebar_summary()

	match tab:
		"timeline": _build_timeline()
		"bridge_preview": _build_bridge_privacy(roster_all)
		"world_state": _build_world_state()
		_: _build_characters(roster_all)

func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game): Game.changed.disconnect(_on_game)

func _on_game(part: String) -> void:
	if part in ["db", "stat", "messages", "presets", "persona"]:
		refresh(false)

func _build_sidebar_summary() -> void:
	var st: Dictionary = Game.db.get("stats", {})
	var p := plate(Rect2(20, 560, 292, 468), {"shape": "cut", "slant": 24, "corner": "tr", "hatch": true}, "l", 0.08)
	header("手札统计", Rect2(20, 16, 252, 44), 22, "c", p)
	var met_cast := 0
	var met_npc := 0
	var all_cs: Dictionary = Game.db.get("character_states", {})
	for cid in all_cs.keys():
		if all_cs[cid] is Dictionary and bool(all_cs[cid].get("met", false)):
			if Data.is_npc(String(cid)): met_npc += 1
			else: met_cast += 1
	var lines := PackedStringArray([
		"角色组已解锁：%d / %d" % [met_cast, Data.cast_ids().size()],
		"重要 NPC 邂逅：%d / %d" % [met_npc, Data.npc_ids().size()],
		"已记录大事：%d 件" % int(st.get("summaries", Game.db_summaries().size())),
		"个人记事/秘密：%d 条" % int(st.get("facts", 0)),
		"物品与魔法：%d 项" % int(st.get("items", 0)),
	])
	var lbl := text("\n".join(lines), Rect2(20, 70, 252, 196), 18, "ink", 600, "c", p)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var hint_l := text("提示：只有主线解锁后的角色才能私聊；私聊会自动过滤未经历事件与隐藏机密。", Rect2(20, 266, 252, 66), 15, "muted", 500, "c", p)
	hint_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	var can_talk := char_id in Game.unlocked_ids(true)
	var talk_b := btn(("去找 %s 单聊" % Data.name_of(char_id)) if can_talk else "未邂逅 · 暂不可单聊", "chat" if can_talk else "lock", "primary" if can_talk else "secondary", Rect2(20, 342, 252, 54), func():
		if can_talk: root.go("talk", {"id": char_id})
		else: toast("需先在主线剧情邂逅 %s 才能解锁看板单聊" % Data.name_of(char_id), "lock")
	, "c", -1.0, p, 18)
	talk_b.name = "DbGoTalk"
	var wb_b := btn("查看世界设定集", "book", "secondary", Rect2(20, 404, 252, 48), func(): root.go("settings", {"tab": "worldbook"}), "c", -1.0, p, 18)
	wb_b.name = "DbGoWorldbook"

# ---------- Character Selector Strip (Role Group vs Dedicated NPC Section) ----------
func _build_char_selector(_roster_all: Array) -> void:
	var cast_un := Game.unlocked_ids(false)
	var all_un := Game.unlocked_ids(true)
	var npc_un := Data.npc_ids().filter(func(nid): return String(nid) in all_un)
	var active_roster := npc_un if char_group == "npcs" else cast_un
	var g_cast := btn("角色组(%d)" % cast_un.size(), "", "segment", Rect2(344, 134, 146, 54), func():
		if char_group != "cast":
			char_group = "cast"; char_page = 0; char_id = String(cast_un[0]) if not cast_un.is_empty() else ""; refresh(false)
	, "c", -1.0, null, 17)
	g_cast.center_text = true; g_cast.selected = char_group == "cast"; g_cast.name = "DbGroupCast"
	var g_npc := btn("NPC(%d)" % npc_un.size(), "", "segment", Rect2(498, 134, 126, 54), func():
		if char_group != "npcs":
			char_group = "npcs"; char_page = 0; char_id = String(npc_un[0]) if not npc_un.is_empty() else ""; refresh(false)
	, "c", -1.0, null, 17)
	g_npc.center_text = true; g_npc.selected = char_group == "npcs"; g_npc.name = "DbGroupNpc"

	const PER_ROW := 5
	var pages := maxi(1, ceili(float(active_roster.size()) / float(PER_ROW)))
	char_page = clampi(char_page, 0, pages - 1)
	var prev_p := btn("", "back", "icon", Rect2(636, 134, 52, 54), func(): char_page = (char_page - 1 + pages) % pages; refresh(false), "c")
	prev_p.name = "CharPagePrev"
	var start := char_page * PER_ROW
	for slot_i in range(PER_ROW):
		var idx := start + slot_i
		if idx >= active_roster.size(): break
		var cid := String(active_roster[idx])
		var cb := btn(Data.name_of(cid) + " ★", "", "segment", Rect2(698 + slot_i * 204, 134, 196, 54), func():
			char_id = cid; refresh(false)
		, "c", -1.0, null, 18)
		cb.center_text = true; cb.selected = cid == char_id; cb.name = "DbChar_" + cid
	var next_p := btn("", "next", "icon", Rect2(1722, 134, 52, 54), func(): char_page = (char_page + 1) % pages; refresh(false), "c")
	next_p.name = "CharPageNext"
	text("%d/%d" % [char_page + 1, pages], Rect2(1782, 134, 96, 54), 18, "muted", 700, "c", null, HORIZONTAL_ALIGNMENT_CENTER)

# ---------- Tab 1: Companion Profile (Affection, Lewdness, Fetishes, Form, Witnessed Memory) ----------
func _build_characters(roster_all: Array) -> void:
	_build_char_selector(roster_all)
	if char_id == "" or roster_all.is_empty():
		var lp := plate(Rect2(344, 210, 1534, 420), {"shape": "cut", "slant": 32, "corner": "tr", "hatch": true}, "c", 0.05)
		lp.name = "DbCharactersEmpty"
		icon("lock", Rect2(731, 64, 72, 72), "muted", "c", lp)
		text("当前分组尚无已解锁同伴或 NPC 资料", Rect2(200, 156, 1134, 52), 30, "ink", 850, "c", lp, HORIZONTAL_ALIGNMENT_CENTER)
		text("请在主线剧情中正式邂逅对应人物后，再查看其好感、态度、已知记忆与私人单聊通道。", Rect2(200, 224, 1134, 60), 21, "muted", 600, "c", lp, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var st: Dictionary = Game.db_char_state(char_id)
	var cname := Data.name_of(char_id)
	var met := bool(st.get("met", false))
	var aff := float(st.get("affection", 0))
	var lewd := float(st.get("lewdness", 0))
	var fetishes: Array = st.get("fetishes", []) if st.get("fetishes") is Array else []
	var form_str := String(st.get("form", "日常"))

	# Top companion card
	var top := plate(Rect2(344, 200, 1534, 246), {"shape": "cut", "slant": 28, "corner": "tr", "hatch": true}, "c", 0.04)
	var av := portrait(char_id, "avatar", Rect2(24, 24, 136, 136), top)
	av.always_show = true; av.frame = false; av.show_character(char_id, "avatar", false)
	text("形态 · " + form_str, Rect2(20, 168, 144, 34), 17, "accent", 750, "c", top, HORIZONTAL_ALIGNMENT_CENTER)
	text("%s · %s" % [cname, String(st.get("stage", "未邂逅"))], Rect2(184, 18, 410, 44), 30, "ink", 900, "c", top)
	text("所属：%s   ｜   最后见面：%s · %s" % [
		String(st.get("homeland", "未知")),
		String(st.get("last_known_location", "暂无")),
		String(st.get("last_seen_time", "未遇到"))
	], Rect2(184, 62, 680, 32), 18, "muted", 650, "c", top)

	# Full state bars: Affection & Lewdness
	icon("sparkle", Rect2(184, 108, 22, 22), "ink", "c", top)
	text("好感度", Rect2(210, 102, 74, 34), 19, "ink", 750, "c", top)
	bar(Rect2(290, 113, 286, 12), aff if met else 0.0, 100.0, "accent", top)
	text("%d / 100" % int(aff), Rect2(590, 102, 120, 34), 19, "accent", 800, "c", top)

	icon("heart", Rect2(184, 146, 22, 22), "accent", "c", top)
	text("色情值", Rect2(210, 140, 74, 34), 19, "ink", 750, "c", top)
	bar(Rect2(290, 151, 286, 12), lewd if met else 0.0, 100.0, "ink", top)
	text("%d / 100（%s）" % [int(lewd), String(st.get("lewd_stage", "纯净"))], Rect2(590, 140, 210, 34), 18, "ink", 750, "c", top)

	var fet_txt := "、".join(PackedStringArray(fetishes)) if not fetishes.is_empty() else "尚未解锁特殊性癖"
	text("已解锁性癖：" + fet_txt, Rect2(184, 182, 690, 44), 17, "muted" if fetishes.is_empty() else "accent", 650, "c", top)

	# Right half of top card: Attitude memo & quick actions
	var memo := String(st.get("attitude_memo", ""))
	if memo == "": memo = String(st.get("relationship_note", ""))
	if memo == "": memo = "尚未形成特别印象，去主线或单独交谈互动吧。"
	var memo_box := plate(Rect2(890, 22, 616, 146), {"slant": 18, "fill": "surface2", "layered": false, "stripe": "left"}, "c", -1.0, top)
	text("她对你的当前印象", Rect2(24, 10, 280, 30), 17, "accent", 800, "c", memo_box)
	var mlbl := text(memo, Rect2(24, 42, 568, 92), 18, "ink", 600, "c", memo_box)
	mlbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; mlbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	btn("改对她的印象", "edit", "secondary", Rect2(890, 180, 220, 48), func():
		root.prompt({"title": "记录 %s 对你的印象" % cname, "message": "这条印象会直接带入你们的单独对话。", "input": {"text": String(st.get("attitude_memo", "")), "placeholder": "例如：态度放松下来，愿意私下跟你聊聊……"}}, func(v: String):
			Game.db_update_char_memo(char_id, {"attitude_memo": v.strip_edges(), "met": true})
		)
	, "c", -1.0, top, 18)
	var go_priv := btn("隐私过滤检查", "chat", "secondary", Rect2(1126, 180, 200, 48), func(): tab = "bridge_preview"; refresh(false), "c", -1.0, top, 18)
	go_priv.name = "DbCharGoPrivacy"
	var go_talk := btn("单独交谈", "play", "primary", Rect2(1340, 180, 166, 48), func(): root.go("talk", {"id": char_id}), "c", -1.0, top, 18)
	go_talk.name = "DbCharGoTalk"

	# Bottom left: Story events she knows (card list)
	var vis_info := Game.db_summaries_for_char(char_id)
	var visible_sums: Array = vis_info.get("visible", [])
	var hidden_cnt := int(vis_info.get("hidden_private_count", 0))
	var left_p := plate(Rect2(344, 462, 754, 568), {"shape": "rect", "corner": "tr", "corner_size": 18}, "c", 0.06)
	header("她知道的经历（%d 件）" % visible_sums.size(), Rect2(24, 14, 706, 44), 22, "c", left_p)
	text("另有 %d 件她不在场的私密剧情已自动保密" % hidden_cnt, Rect2(24, 58, 706, 30), 16, "muted", 600, "c", left_p)
	var lsc := ScrollContainer.new(); lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(lsc, Rect2(24, 94, 706, 454), "c", -1.0, left_p)
	var lvb := VBoxContainer.new(); lvb.add_theme_constant_override("separation", 12); lvb.custom_minimum_size.x = 682
	lsc.add_child(lvb)
	if visible_sums.is_empty():
		var nl := Lbl.new(); nl.setup("你们还没有在主线里共同经历已记录的事件，外头也暂无相关传闻。", 19, "muted", 600)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; nl.custom_minimum_size.x = 678; lvb.add_child(nl)
	else:
		for s in visible_sums:
			var is_pub := String(s.get("visibility", "")) == "world_public"
			var card := MarginContainer.new()
			card.custom_minimum_size.x = 678
			var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 4); card.add_child(box)
			var meta_l := Lbl.new()
			meta_l.setup("%s · %s · 【%s】" % [String(s.get("game_time", "未知时间")), String(s.get("location", "未知地点")), "大家传开了" if is_pub else "她当时在场"], 16, "accent" if not is_pub else "muted", 750)
			box.add_child(meta_l)
			var ev_l := Lbl.new()
			ev_l.setup(String(s.get("event", "")), 19, "ink", 600)
			ev_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ev_l.custom_minimum_size.x = 674
			box.add_child(ev_l)
			lvb.add_child(card)

	# Bottom right: Personal memories & player notes
	var facts := Game.db_char_facts(char_id)
	var right_p := plate(Rect2(1124, 462, 754, 568), {"shape": "rect", "corner": "tr", "corner_size": 18}, "c", 0.08)
	header("她的私人记忆与秘密（%d 条）" % facts.size(), Rect2(24, 14, 706, 44), 22, "c", right_p)
	var fin := LineEdit.new(); fin.name = "NewFactInput"; fin.placeholder_text = "想让 %s 牢记的一件事或秘密…" % cname; fin.text = fact_draft
	fin.text_changed.connect(func(v): fact_draft = v)
	put(fin, Rect2(24, 68, 412, 48), "c", -1.0, right_p)
	var fk_b := btn("秘密" if fact_kind == "secret_known" else "普通", "", "segment", Rect2(446, 68, 120, 48), func():
		fact_kind = "manual" if fact_kind == "secret_known" else "secret_known"; refresh(false)
	, "c", -1.0, right_p, 18)
	fk_b.center_text = true; fk_b.selected = fact_kind == "secret_known"
	var add_f := btn("记下来", "", "primary", Rect2(576, 68, 152, 48), func():
		if fact_draft.strip_edges() == "": toast("先写点什么吧", "warn"); return
		Game.db_add_fact(char_id, fact_draft, fact_kind)
		fact_draft = ""
		refresh(false)
	, "c", -1.0, right_p, 18)
	add_f.name = "AddFactBtn"; add_f.center_text = true

	var rsc := ScrollContainer.new(); rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(rsc, Rect2(24, 130, 706, 418), "c", -1.0, right_p)
	var rvb := VBoxContainer.new(); rvb.add_theme_constant_override("separation", 10); rvb.custom_minimum_size.x = 682
	rsc.add_child(rvb)
	if facts.is_empty():
		var ef := Lbl.new(); ef.setup("这里会记下她亲眼看到的事件、你们单独聊过的心事，或你手动告诉她的秘密。", 19, "muted", 600)
		ef.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; ef.custom_minimum_size.x = 678; rvb.add_child(ef)
	else:
		for f in facts:
			var ftype := String(f.get("fact_type", ""))
			var fbadge: String = String({"bridge_memory": "💬 私聊记忆", "secret_known": "🔒 已知秘密", "manual": "📝 玩家补充", "main_story_witnessed": "👀 亲历事件"}.get(ftype, "📌 记忆"))
			var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); row.custom_minimum_size.x = 678
			rvb.add_child(row)
			var fl := Lbl.new()
			fl.setup("%s：%s" % [fbadge, String(f.get("content", ""))], 18, "ink", 600)
			fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(fl)
			var fid := String(f.get("id", ""))
			var del := Btn.new(); del.setup("移除", "", "ghost", 16); del.center_text = true; del.custom_minimum_size = Vector2(78, 38)
			del.pressed.connect(func(): Game.db_delete_fact(fid))
			row.add_child(del)

# ---------- Tab 2: Story Timeline Journal ----------
func _filtered_summaries() -> Array:
	var out: Array = []
	for s in Game.db_summaries():
		if not s is Dictionary: continue
		if vis_filter != "all" and String(s.get("visibility", "present_only")) != vis_filter:
			continue
		out.append(s)
	return out

func _build_timeline() -> void:
	var filters := [["all", "全部大事记"], ["present_only", "私密经历"], ["world_public", "公开传闻"]]
	for i in range(filters.size()):
		var fid: String = filters[i][0]
		var fb := btn(filters[i][1], "", "segment", Rect2(344 + i * 190, 134, 178, 52), func():
			vis_filter = fid; sum_picked = 0; editing_sum = false; refresh(false)
		, "c", -1.0, null, 19)
		fb.center_text = true; fb.selected = vis_filter == fid; fb.name = "Filter_" + fid
	var add_b := btn("＋ 补记一件事", "edit", "primary", Rect2(1600, 134, 276, 54), func():
		_start_edit_summary({})
	, "c", -1.0, null, 19)
	add_b.name = "AddManualSummary"

	var list := _filtered_summaries()
	var lp := plate(Rect2(344, 202, 540, 828), {"shape": "rect", "corner": "tr", "corner_size": 18}, "c", 0.05)
	header("剧情大事记（共 %d 条）" % list.size(), Rect2(22, 16, 496, 44), 22, "c", lp)
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(sc, Rect2(20, 72, 500, 736), "c", -1.0, lp)
	var vbox := VBoxContainer.new(); vbox.add_theme_constant_override("separation", 10); vbox.custom_minimum_size.x = 480
	sc.add_child(vbox)
	if list.is_empty():
		var empty_l := Lbl.new(); empty_l.setup("暂无大事记。\n在剧情里每走过一幕，系统会自动把时间、地点和经过记成手账放在这里。", 19, "muted", 600)
		empty_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; empty_l.custom_minimum_size = Vector2(476, 100)
		vbox.add_child(empty_l)
	else:
		sum_picked = clampi(sum_picked, 0, list.size() - 1)
		for idx in range(list.size()):
			var s: Dictionary = list[idx]
			var loc_short := String(s.get("location", "未知地点")).split("·")[-1]
			var title_str := "%s · %s" % [String(s.get("game_time", "未记时间")), loc_short]
			var rb := Btn.new()
			rb.setup(title_str, "", "row", 18)
			rb.selected = (idx == sum_picked) and not editing_sum
			rb.badge = "传闻" if String(s.get("visibility", "")) == "world_public" else "私密"
			rb.arrow = true
			rb.custom_minimum_size = Vector2(476, 78)
			rb.name = "SumRow_%d" % idx
			var ii := idx
			rb.pressed.connect(func(): sum_picked = ii; editing_sum = false; refresh(false))
			vbox.add_child(rb)

	var rp := plate(Rect2(908, 202, 970, 828), {"shape": "cut", "slant": 32, "corner": "tr", "hatch": true}, "c", 0.08)
	if editing_sum:
		_build_summary_editor(rp)
	elif list.is_empty():
		text("选左边的一条大事记，这里会展示前因后果。", Rect2(44, 60, 860, 70), 24, "muted", 650, "c", rp)
	else:
		_build_summary_detail(rp, list[sum_picked])

func _start_edit_summary(s: Dictionary) -> void:
	editing_sum = true
	edit_sum_id = String(s.get("id", ""))
	draft_time = String(s.get("game_time", Game.hero().get("时间", "1015年2月1日 09:00")))
	draft_loc = String(s.get("location", Game.hero().get("当前地点", "塞蕾特公国·中央学院")))
	var pnames: Array = s.get("participant_names", [])
	draft_roles = "、".join(PackedStringArray(pnames)) if not pnames.is_empty() else "凛零"
	draft_vis = String(s.get("visibility", "present_only"))
	draft_event = String(s.get("event", ""))
	draft_clues = String(s.get("clues", ""))
	draft_changes = String(s.get("changes", ""))
	refresh(false)

func _build_summary_detail(rp: Control, s: Dictionary) -> void:
	var is_pub := String(s.get("visibility", "")) == "world_public"
	header("%s  ·  %s" % [String(s.get("game_time", "时间待补")), String(s.get("location", "未知地点"))], Rect2(36, 22, 898, 54), 26, "c", rp)
	var pnames: Array = s.get("participant_names", [])
	var roles_str := "、".join(PackedStringArray(pnames)) if not pnames.is_empty() else "仅主角"
	text("当时在场：%s" % roles_str, Rect2(36, 86, 898, 36), 20, "ink", 700, "c", rp)
	text("传闻范围：%s" % ("公开传闻（没到场的同伴也可能会听闻）" if is_pub else "私密经历（只有当时在场的人会记得）"), Rect2(36, 124, 898, 36), 18, "accent" if not is_pub else "muted", 650, "c", rp)

	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(sc, Rect2(36, 174, 898, 540), "c", -1.0, rp)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 18); vb.custom_minimum_size.x = 874
	sc.add_child(vb)
	for sec in [["📖 事情经过", String(s.get("event", ""))], ["🔍 留下的线索", String(s.get("clues", ""))], ["✨ 带来的变化", String(s.get("changes", ""))]]:
		var body_s: String = String(sec[1]).strip_edges()
		if body_s == "" and sec[0] != "📖 事情经过": continue
		var h := Lbl.new(); h.setup(sec[0], 21, "accent", 800); vb.add_child(h)
		var b := Lbl.new(); b.setup(body_s if body_s != "" else "暂无详细记载", 22, "ink", 600)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; b.custom_minimum_size.x = 868; vb.add_child(b)

	var edit_b := btn("修改这条记录", "docs", "secondary", Rect2(36, 742, 240, 58), func(): _start_edit_summary(s), "c", -1.0, rp, 19)
	edit_b.name = "EditSummaryBtn"
	var del_b := btn("删除", "trash", "ghost", Rect2(296, 742, 160, 58), func(): Game.db_delete_summary(String(s.get("id", ""))), "c", -1.0, rp, 19)
	del_b.name = "DeleteSummaryBtn"

func _build_summary_editor(rp: Control) -> void:
	header("补记大事" if edit_sum_id == "" else "修改这条记录", Rect2(36, 20, 898, 50), 26, "c", rp)
	var y := 84.0
	for row in [["游戏时间", draft_time, "SumEditTime"], ["发生地点", draft_loc, "SumEditLoc"], ["谁在场（顿号隔开）", draft_roles, "SumEditRoles"]]:
		text(row[0], Rect2(36, y, 220, 46), 19, "muted", 700, "c", rp)
		var le := LineEdit.new(); le.name = row[2]; le.text = row[1]
		put(le, Rect2(264, y, 650, 46), "c", -1.0, rp)
		match row[2]:
			"SumEditTime": le.text_changed.connect(func(v): draft_time = v)
			"SumEditLoc": le.text_changed.connect(func(v): draft_loc = v)
			"SumEditRoles": le.text_changed.connect(func(v): draft_roles = v)
		y += 58.0
	text("知道范围", Rect2(36, y, 220, 46), 19, "muted", 700, "c", rp)
	var p_btn := btn("仅在场人知道", "", "segment", Rect2(264, y, 200, 46), func(): draft_vis = "present_only"; refresh(false), "c", -1.0, rp, 18)
	p_btn.center_text = true; p_btn.selected = draft_vis != "world_public"
	var pub_btn := btn("传开成为公开传闻", "", "segment", Rect2(478, y, 220, 46), func(): draft_vis = "world_public"; refresh(false), "c", -1.0, rp, 18)
	pub_btn.center_text = true; pub_btn.selected = draft_vis == "world_public"
	y += 62.0
	text("发生了什么", Rect2(36, y, 220, 46), 19, "muted", 700, "c", rp)
	var ev_ed := TextEdit.new(); ev_ed.name = "SumEditEvent"; ev_ed.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; ev_ed.text = draft_event
	ev_ed.text_changed.connect(func(): draft_event = ev_ed.text)
	put(ev_ed, Rect2(264, y, 650, 176), "c", -1.0, rp)
	y += 192.0
	for row2 in [["留下的线索", draft_clues, "SumEditClues"], ["后续变化", draft_changes, "SumEditChanges"]]:
		text(row2[0], Rect2(36, y, 220, 46), 19, "muted", 700, "c", rp)
		var le2 := LineEdit.new(); le2.name = row2[2]; le2.text = row2[1]
		put(le2, Rect2(264, y, 650, 46), "c", -1.0, rp)
		if row2[2] == "SumEditClues": le2.text_changed.connect(func(v): draft_clues = v)
		else: le2.text_changed.connect(func(v): draft_changes = v)
		y += 58.0
	var save_b := btn("保存记入", "save", "primary", Rect2(36, 742, 240, 58), func():
		if draft_event.strip_edges() == "":
			toast("请先写清楚发生了什么事", "warn"); return
		Game.db_save_summary({
			"id": edit_sum_id,
			"game_time": draft_time,
			"location": draft_loc,
			"roles_raw": draft_roles,
			"visibility": draft_vis,
			"event": draft_event,
			"clues": draft_clues,
			"changes": draft_changes,
		})
		editing_sum = false
		refresh(false)
	, "c", -1.0, rp, 19)
	save_b.name = "SaveSummaryBtn"
	btn("取消", "close", "secondary", Rect2(296, 742, 180, 58), func(): editing_sum = false; refresh(false), "c", -1.0, rp, 19)

# ---------- Tab 3: Hero Full Status, Items/Magic & World Events ----------
func _build_world_state() -> void:
	var ps: Dictionary = Game.db.get("player_state", {})
	var p1 := plate(Rect2(344, 134, 754, 372), {"shape": "cut", "slant": 26, "corner": "tr", "hatch": true}, "c", 0.04)
	header("主角全状态", Rect2(24, 14, 706, 44), 22, "c", p1)
	var cast_arr: Array = ps.get("present_cast", []) if ps.get("present_cast") is Array else []
	var slain_arr: Array = ps.get("slain_anomalies", []) if ps.get("slain_anomalies") is Array else []
	var p_lines := PackedStringArray([
		"姓名：%s  ｜  出身：%s  ｜  种族：%s" % [String(ps.get("name", "你")), String(ps.get("origin", "未定")), String(ps.get("race", "未定"))],
		"时间：%s  ｜  所在：%s" % [String(ps.get("current_time", "未开始")), String(ps.get("current_location", "未知"))],
		"魔力：%s / %s  ｜  当前乐章：%s" % [str(ps.get("mana", "—")), str(ps.get("mana_max", "—")), String(ps.get("bgm", "Main Theme"))],
		"当前在场同伴：%s" % ("、".join(PackedStringArray(cast_arr)) if not cast_arr.is_empty() else "暂无人同行"),
		"已讨伐异危魔物：%s" % ("、".join(PackedStringArray(slain_arr)) if not slain_arr.is_empty() else "暂无讨伐记录"),
		"简介：%s" % String(ps.get("summary", "待初始化")),
	])
	var pl := text("\n".join(p_lines), Rect2(24, 68, 706, 286), 19, "ink", 600, "c", p1)
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; pl.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	var items: Array = Game.db.get("inventory_and_sigils", [])
	var p2 := plate(Rect2(344, 524, 754, 506), {"shape": "rect", "corner": "tr", "corner_size": 18}, "c", 0.06)
	header("持有物品与魔法（%d 项）" % items.size(), Rect2(24, 14, 706, 44), 22, "c", p2)
	var isc := ScrollContainer.new(); isc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(isc, Rect2(24, 68, 706, 418), "c", -1.0, p2)
	var ivb := VBoxContainer.new(); ivb.add_theme_constant_override("separation", 10); ivb.custom_minimum_size.x = 682
	isc.add_child(ivb)
	if items.is_empty():
		var ei := Lbl.new(); ei.setup("背包还是空的，推进剧情获得的物品或魔法会自动收进这里。", 19, "muted", 600); ei.custom_minimum_size.x = 678; ivb.add_child(ei)
	else:
		for it in items:
			var kind_lbl := "✨ 魔法" if String(it.get("kind", "item")) == "magic" else "🎒 物品"
			var il := Lbl.new()
			il.setup("%s 【%s】 ×%d\n   %s" % [kind_lbl, String(it.get("name", "")), int(it.get("count", 1)), String(it.get("description", ""))], 18, "ink", 600)
			il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; il.custom_minimum_size.x = 678; ivb.add_child(il)

	var evs: Array = Game.db.get("plot_events_and_world_flags", [])
	var p3 := plate(Rect2(1124, 134, 754, 896), {"shape": "cut", "slant": 30, "corner": "tr", "hatch": true}, "c", 0.08)
	header("大陆局势与剧情事件（%d 条）" % evs.size(), Rect2(24, 14, 706, 44), 22, "c", p3)
	var esc := ScrollContainer.new(); esc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(esc, Rect2(24, 68, 706, 804), "c", -1.0, p3)
	var evb := VBoxContainer.new(); evb.add_theme_constant_override("separation", 14); evb.custom_minimum_size.x = 682
	esc.add_child(evb)
	if evs.is_empty():
		var ee := Lbl.new(); ee.setup("目前还没有触发重大主线事件或公开传闻。", 19, "muted", 600); ee.custom_minimum_size.x = 678; evb.add_child(ee)
	else:
		for ev in evs:
			var el := Lbl.new()
			var tag: String = String({"live": "🔥 正在进行", "done": "✔ 已完结", "rumor": "📢 坊间传闻"}.get(String(ev.get("status", "rumor")), "📌 动态"))
			el.setup("%s｜%s\n%s" % [tag, String(ev.get("title", "")), String(ev.get("description", ""))], 19, "ink", 600)
			el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; el.custom_minimum_size.x = 678; evb.add_child(el)

# ---------- Tab 4: Simple Player-Friendly Privacy Check (+ Optional Raw Prompt Foldout) ----------
func _build_bridge_privacy(roster_all: Array) -> void:
	_build_char_selector(roster_all)
	if char_id == "" or roster_all.is_empty():
		var ep := plate(Rect2(344, 210, 1534, 420), {"shape": "cut", "slant": 32, "corner": "tr", "hatch": true}, "c", 0.05)
		ep.name = "DbBridgeEmpty"
		icon("lock", Rect2(731, 64, 72, 72), "muted", "c", ep)
		text("当前分组尚无已解锁角色的私聊隐私记录", Rect2(200, 156, 1134, 52), 30, "ink", 850, "c", ep, HORIZONTAL_ALIGNMENT_CENTER)
		text("只有主线中正式邂逅的角色与 NPC，才会开放私聊频道与独立记事保密统计。", Rect2(200, 224, 1134, 60), 21, "muted", 600, "c", ep, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var ctx: Dictionary = Game.preview_bridge_context(char_id, preview_draft)
	var cname := String(ctx.get("character_name", Data.name_of(char_id)))
	var iso_cnt := int(ctx.get("isolated_private_summaries_count", 0))
	var wb_hit: Array = ctx.get("worldbook_matched", [])
	var wb_sec: Array = ctx.get("worldbook_filtered_secrets", [])
	var v_sums: Array = ctx.get("visible_summaries", [])
	var r_msgs: Array = ctx.get("recent_bridge_messages", [])
	var main_sent := bool(ctx.get("main_chat_history_sent", false))

	# Top plain-language summary bar
	var banner := plate(Rect2(344, 200, 1534, 72), {"slant": 24, "stripe": "left", "fill": "surface2", "layered": false}, "c", 0.03)
	text("和 %s 单聊时：不发送主线全篇聊天 · 已自动保密 %d 件私密事件与 %d 条隐藏秘密" % [
		cname, iso_cnt, wb_sec.size()
	], Rect2(24, 12, 956, 48), 18, "ink", 750, "c", banner)
	var raw_toggle := btn("收起AI原始文本" if show_raw_prompt else "进阶查看：AI发包原文", "docs", "secondary", Rect2(992, 12, 256, 48), func():
		show_raw_prompt = not show_raw_prompt; refresh(false)
	, "c", -1.0, banner, 17)
	raw_toggle.name = "ToggleRawPrompt"
	var can_talk := char_id in Game.unlocked_ids(true)
	var talk_btn := btn(("和 %s 单聊" % cname) if can_talk else "未邂逅 · 暂不可聊", "chat" if can_talk else "lock", "primary" if can_talk else "secondary", Rect2(1262, 12, 252, 48), func():
		if can_talk: root.go("talk", {"id": char_id})
		else: toast("需先在主线剧情邂逅 %s 才能解锁看板单聊" % cname, "lock")
	, "c", -1.0, banner, 18)
	talk_btn.name = "PreviewGoTalk"

	if show_raw_prompt:
		var rp := plate(Rect2(344, 286, 1534, 744), {"shape": "cut", "slant": 28, "corner": "tr", "hatch": true}, "c", 0.06)
		header("进阶视图：发送给 AI 的完整单聊提示包（仅供作者/调试核对）", Rect2(28, 16, 1478, 44), 22, "c", rp)
		var rsc := ScrollContainer.new(); rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		put(rsc, Rect2(28, 72, 1478, 646), "c", -1.0, rp)
		var plbl := Lbl.new(); plbl.name = "BridgePromptPreviewText"
		plbl.setup(String(ctx.get("assembled_prompt_preview", "")), 18, "ink", 500)
		plbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; plbl.custom_minimum_size.x = 1452
		rsc.add_child(plbl)
		return

	# Clean 3 protection status cards
	var cards := [
		["主线聊天全量隔离", "已拦截" if not main_sent else "异常", "只发精选记忆，不会让 AI 读取主线全篇水字或别处的无关对话。", "accent"],
		["不在场私密屏蔽", "屏蔽 %d 件" % iso_cnt, "你没带 %s 参与的私密事件不会剧透；她只记得自己在场或传闻。" % cname, "ink"],
		["世界真相防串台", "锁住 %d 条" % wb_sec.size(), "七罪、龙种等高级设定在她解锁前不会提前塞进她脑子里。", "ink"],
	]
	for k in range(cards.size()):
		var cinfo: Array = cards[k]
		var cp := plate(Rect2(344 + k * 518, 286, 498, 154), {"slant": 22, "stripe": "left", "fill": "surface", "layered": false}, "c", 0.05)
		text(cinfo[0], Rect2(24, 16, 260, 36), 21, "ink", 800, "c", cp)
		text(cinfo[1], Rect2(300, 14, 174, 38), 22, cinfo[3], 850, "c", cp, HORIZONTAL_ALIGNMENT_RIGHT)
		var cd := text(cinfo[2], Rect2(24, 58, 450, 82), 17, "muted", 600, "c", cp)
		cd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; cd.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	# Bottom left: What knowledge %s HAS access to when chatting
	var lp := plate(Rect2(344, 456, 754, 574), {"shape": "rect", "corner": "tr", "corner_size": 18}, "c", 0.06)
	header("和 %s 聊天时，她脑子里带着这些设定与记忆" % cname, Rect2(24, 16, 706, 44), 21, "c", lp)
	var lsc := ScrollContainer.new(); lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(lsc, Rect2(24, 70, 706, 484), "c", -1.0, lp)
	var lvb := VBoxContainer.new(); lvb.add_theme_constant_override("separation", 12); lvb.custom_minimum_size.x = 682
	lsc.add_child(lvb)
	var p_chars := int(ctx.get("persona_sheet_chars", 0))
	var l_items := [
		["🎭 角色完整设定（已注入 %d 字）" % p_chars, "包含 %s 的性格调色盘、说话口癖、语料示例与禁写规则，AI 只允许扮演她一人并回复 1～5 条纯台词消息。" % cname],
		["📘 关联的世界设定（%d 条）" % wb_hit.size(), "、".join(PackedStringArray(wb_hit)) if not wb_hit.is_empty() else "仅带入她自己的角色基础设定"],
		["📖 可供回忆的大事（%d 件）" % v_sums.size(), "只包含她在场或流传开的事件（可在「同伴档案」页增删）。"],
		["💬 单聊私密记忆窗口", "保留最近 %d 条单独消息；老对话过长时会自动浓缩成摘要。" % r_msgs.size()],
	]
	for li in l_items:
		var lh := Lbl.new(); lh.setup(li[0], 20, "accent", 800); lvb.add_child(lh)
		var lb := Lbl.new(); lb.setup(li[1], 18, "ink", 600); lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; lb.custom_minimum_size.x = 678; lvb.add_child(lb)

	# Bottom right: Secrets currently sealed from her
	var rp2 := plate(Rect2(1124, 456, 754, 574), {"shape": "rect", "corner": "tr", "corner_size": 18}, "c", 0.08)
	header("已替你锁住、暂不让她知道的世界秘密（%d 条）" % wb_sec.size(), Rect2(24, 16, 706, 44), 21, "c", rp2)
	var rsc2 := ScrollContainer.new(); rsc2.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(rsc2, Rect2(24, 70, 706, 484), "c", -1.0, rp2)
	var rvb2 := VBoxContainer.new(); rvb2.add_theme_constant_override("separation", 10); rvb2.custom_minimum_size.x = 682
	rsc2.add_child(rvb2)
	if wb_sec.is_empty():
		var es := Lbl.new(); es.setup("当前无相关保密词条触发限制。", 18, "muted", 600); es.custom_minimum_size.x = 678; rvb2.add_child(es)
	else:
		var tip := Lbl.new(); tip.setup("如果想让 %s 知道其中某件秘密，只要在「同伴档案」里给她手动记一条包含对应名字的秘密，系统就会放行：" % cname, 17, "muted", 600)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tip.custom_minimum_size.x = 678; rvb2.add_child(tip)
		for sec_name in wb_sec:
			var sl := Lbl.new(); sl.setup("🔒  " + String(sec_name), 18, "ink", 600)
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; sl.custom_minimum_size.x = 678; rvb2.add_child(sl)
