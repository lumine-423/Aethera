extends "res://scripts/ui/ui_screen.gd"
## 角色档案（仅显示主线已解锁的角色组与重要 NPC；右侧表情预览下方含原卡双图集：日常插图 / 色情插图）。

var selected := 0
var page := 0
var tab_group := "cast"      # "cast" (主角组已解锁) | "npcs" (重要NPC已解锁)
var gallery_tab := "affection" # "affection" (日常插图，好感 25/50/75/100×2) | "erotic" (色情插图，色情 20/40/60/80/100×2)
var outfit := "daily"
var pose_key := "daily"
var expr := "neutral"
var art: Control
var gallery_zoom: Control
var _zoom_items: Array = []
var _zoom_idx := -1
const PER_PAGE := 8
const OUTFIT_NAMES := {"daily": "日常服", "casual": "休闲服", "liberate": "解放形态", "nude": "裸体"}

func _unlocked_set() -> Dictionary:
	var out := {}
	for cid in Game.unlocked_ids(true):
		out[String(cid)] = true
	return out

func _group_ids(group_override := "") -> Array:
	var gkey := tab_group if group_override == "" else group_override
	var u := _unlocked_set()
	var base := Data.npc_ids() if gkey == "npcs" else Data.cast_ids()
	return base.filter(func(cid): return u.has(String(cid)))

func on_back() -> bool:
	if is_instance_valid(gallery_zoom):
		_close_gallery_zoom()
		return true
	return false

func _close_gallery_zoom(silent := false) -> void:
	if is_instance_valid(gallery_zoom):
		if not silent: UiHub.sfx("close_book")
		if gallery_zoom.get_parent() != null:
			gallery_zoom.get_parent().remove_child(gallery_zoom)
		gallery_zoom.queue_free()
	gallery_zoom = null
	_zoom_idx = -1

func _open_gallery_zoom(items: Array, idx: int, cname: String, mode_label: String) -> void:
	if idx < 0 or idx >= items.size(): return
	var item: Dictionary = items[idx]
	if not bool(item.get("unlocked", false)): return
	var res_path := String(item.get("res", ""))
	if res_path == "" or not ResourceLoader.exists(res_path): return
	_close_gallery_zoom(true)
	_zoom_items = items
	_zoom_idx = idx
	UiHub.sfx("open_book")
	gallery_zoom = Control.new()
	gallery_zoom.name = "CharGalleryZoom"
	gallery_zoom.mouse_filter = Control.MOUSE_FILTER_STOP
	gallery_zoom.set_meta("layer", true)
	put(gallery_zoom, Rect2(Vector2.ZERO, size), "c")
	var bg := ColorRect.new(); bg.color = Color(0.03, 0.03, 0.04, 0.92); bg.size = size
	gallery_zoom.add_child(bg)
	var big := W.Portrait.new(); big.kind = "cg"; big.frame = false; big.size = size
	gallery_zoom.add_child(big); big.set_texture(load(res_path), false)
	var cap := plate(Rect2(44, size.y - 108, 620, 74), {"slant": 24, "stripe": "left", "fill_alpha": 0.92}, "c", -1.0, gallery_zoom)
	text("%s · %s 第 %d 张（解锁条件 ≥ %d）" % [cname, mode_label, int(item.get("slot", idx + 1)), int(item.get("need", 0))], Rect2(28, 0, 564, 74), 21, "ink", 750, "c", cap)
	if items.size() > 1:
		var prev_z := btn("", "back", "icon", Rect2(30, size.y * 0.5 - 40, 86, 80), func(): _step_gallery_zoom(-1, cname, mode_label), "c", -1.0, gallery_zoom)
		prev_z.name = "ZoomPrev"
		var next_z := btn("", "next", "icon", Rect2(size.x - 116, size.y * 0.5 - 40, 86, 80), func(): _step_gallery_zoom(1, cname, mode_label), "c", -1.0, gallery_zoom)
		next_z.name = "ZoomNext"
	var close_b := btn("", "close", "icon", Rect2(size.x - 130, 30, 96, 70), func(): _close_gallery_zoom(), "c", -1.0, gallery_zoom)
	close_b.name = "CloseGalleryZoom"
	gallery_zoom.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close_gallery_zoom()
			gallery_zoom.accept_event()
	)
	Kit.pop(gallery_zoom)

func _step_gallery_zoom(delta_i: int, cname: String, mode_label: String) -> void:
	if _zoom_items.is_empty(): return
	for step_k in range(1, _zoom_items.size() + 1):
		var cand := (_zoom_idx + delta_i * step_k + _zoom_items.size() * 4) % _zoom_items.size()
		if bool(_zoom_items[cand].get("unlocked", false)):
			_open_gallery_zoom(_zoom_items, cand, cname, mode_label)
			return

func build() -> void:
	_close_gallery_zoom(true)
	chrome("角色档案")
	var cast_unlocked := _group_ids("cast")
	var npc_unlocked := _group_ids("npcs")
	var locked_target := ""
	if params.has("id"):
		var want_id := String(params.id)
		tab_group = "npcs" if Data.is_npc(want_id) else "cast"
		var grp_list := npc_unlocked if tab_group == "npcs" else cast_unlocked
		var found := grp_list.find(want_id)
		if found >= 0:
			selected = found
			page = selected / PER_PAGE
			outfit = "daily"; pose_key = "daily"; expr = "neutral"
		else:
			locked_target = want_id
		params.erase("id")

	# 顶部板块切换：仅展示已解锁数量
	var b_cast := btn("角色组 (%d)" % cast_unlocked.size(), "", "segment", Rect2(30, 118, 178, 44), func():
		if tab_group != "cast":
			tab_group = "cast"; selected = 0; page = 0; outfit = "daily"; pose_key = "daily"; expr = "neutral"; refresh(false)
	, "c", -1.0, null, 18)
	b_cast.center_text = true; b_cast.selected = tab_group == "cast"; b_cast.name = "CharGroupCast"
	var b_npc := btn("重要 NPC (%d)" % npc_unlocked.size(), "", "segment", Rect2(218, 118, 178, 44), func():
		if tab_group != "npcs":
			tab_group = "npcs"; selected = 0; page = 0; outfit = "daily"; pose_key = "daily"; expr = "neutral"; refresh(false)
	, "c", -1.0, null, 18)
	b_npc.center_text = true; b_npc.selected = tab_group == "npcs"; b_npc.name = "CharGroupNpc"

	var ids: Array = npc_unlocked if tab_group == "npcs" else cast_unlocked
	if locked_target != "" or ids.is_empty():
		var lock_p := plate(Rect2(440, 220, 1160, 480), {"shape": "cut", "slant": 36, "corner": "tr", "hatch": true}, "c", 0.06)
		lock_p.name = "CharactersLockedPanel"
		icon("lock", Rect2(544, 58, 72, 72), "muted", "c", lock_p)
		var heading := "当前分组暂无已解锁角色" if tab_group == "cast" else "当前分组暂无已解锁重要 NPC"
		if locked_target != "":
			heading = "「%s」尚未在主线剧情中解锁" % Data.name_of(locked_target)
		text(heading, Rect2(100, 152, 960, 56), 34, "ink", 850, "c", lock_p, HORIZONTAL_ALIGNMENT_CENTER)
		var sub := "所有角色与重要 NPC 均需在主线剧情正式邂逅解锁后，才会显现档案与对应资料。"
		var sub_lbl := text(sub, Rect2(110, 222, 940, 72), 22, "muted", 600, "c", lock_p, HORIZONTAL_ALIGNMENT_CENTER)
		sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var go_st := btn("前往主线剧情" if not Game.has_story() else "回到故事界面", "play", "primary", Rect2(270, 344, 290, 74), func():
			if Game.has_story(): root.go("story")
			else: root.go("story_hub")
		, "c", -1.0, lock_p, 22)
		go_st.name = "LockedGoStory"
		if not ids.is_empty():
			var show_unlocked := btn("查看本组已解锁 (%d)" % ids.size(), "person", "secondary", Rect2(590, 344, 310, 74), func():
				selected = 0; page = 0; refresh(false)
			, "c", -1.0, lock_p, 21)
			show_unlocked.name = "ShowUnlockedInGroup"
		else:
			var other := npc_unlocked if tab_group == "cast" else cast_unlocked
			if not other.is_empty():
				var sw_btn := btn("切到已解锁分组 (%d)" % other.size(), "swap", "secondary", Rect2(590, 344, 310, 74), func():
					tab_group = "npcs" if tab_group == "cast" else "cast"; selected = 0; page = 0; refresh(false)
				, "c", -1.0, lock_p, 21)
				sw_btn.name = "SwitchUnlockedGroup"
		return

	selected = clampi(selected, 0, ids.size() - 1)
	var pages := maxi(1, ceili(float(ids.size()) / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)
	var id: String = ids[selected]
	var is_npc_flag := Data.is_npc(id)
	var c: Dictionary = Data.cast_entry(id)
	var cname: String = Data.name_of(id)
	var known: Dictionary = Game.known().get(cname, {})
	var db_st: Dictionary = Game.db_char_state(id)
	var fav := float(known.get("好感度", db_st.get("affection", 0)))
	var lewd := float(known.get("色情值", db_st.get("lewdness", 0)))
	var outfits: Array = Data.content().get("outfits", {}).get(id, ["daily"])
	if outfits.is_empty(): outfits = ["daily"]
	if not outfit in outfits: outfit = outfits[0]
	var poses: Array = Data.pose_groups(id, outfit)
	var pose_keys: Array = []
	for pg in poses: pose_keys.append(str(pg.get("key", "")))
	if not pose_keys.is_empty():
		if not pose_key in pose_keys: pose_key = pose_keys[0]
	else:
		pose_key = outfit
	var active_pg := {}
	for pg in poses:
		if str(pg.get("key", "")) == pose_key: active_pg = pg; break
	var supported_exprs: Array = active_pg.get("expressions", [])
	if not supported_exprs.is_empty() and not expr in supported_exprs:
		expr = "neutral"

	# 左侧名册：当前页最多 8 人（2 列 × 4 行，仅展示已解锁）
	var start := page * PER_PAGE
	var stop := mini(start + PER_PAGE, ids.size())
	for slot in range(stop - start):
		var i := start + slot
		var cid: String = ids[i]
		var r := Rect2(30 + (slot % 2) * 190, 174 + (slot / 2) * g(150), 176, 134)
		var b := Btn.new(); b.variant = "secondary"; b.slant = 18; b.selected = i == selected; b.press_sfx = "card"
		b.name = "Roster_" + cid
		put(b, r, "c", 0.02 + slot * 0.02)
		var ii := i
		b.pressed.connect(func(): _select(ii))
		var av := W.Portrait.new(); av.kind = "avatar"; av.character_id = cid
		put(av, Rect2(46, 8, 84, 84), "c", -1.0, b)
		text(Data.name_of(cid), Rect2(8, 96, 160, 32), 19, "accent" if i == selected else "ink", 800, "c", b, HORIZONTAL_ALIGNMENT_CENTER)

	# 分页控制
	var grp_tag := "已解锁 NPC" if tab_group == "npcs" else "已解锁角色"
	text("%s · %d/%d 页 · %d 人" % [grp_tag, page + 1, pages, ids.size()], Rect2(30, 908, 366, 36), 18, "muted", 700, "c", null, HORIZONTAL_ALIGNMENT_CENTER)
	var prev_b := btn("上一页", "back", "chip", Rect2(30, 954, 174, 72), func(): _set_page(page - 1), "c", -1.0, null, 20)
	prev_b.name = "CharPrev"; prev_b.disabled = pages <= 1
	var next_b := btn("下一页", "tri_right", "chip", Rect2(222, 954, 174, 72), func(): _set_page(page + 1), "c", -1.0, null, 20)
	next_b.name = "CharNext"; next_b.disabled = pages <= 1

	# 立绘展示区
	var band := plate(Rect2(560, -40, 360, 1160), {"slant": 180, "fill": "plane", "fill_alpha": 0.5, "border": "", "layered": false, "glass": false})
	band.z_index = -1
	art = W.Portrait.new(); art.name = "Art"
	put(art, Rect2(430, 60, 700, 1020), "c")
	art.show_art(id, pose_key, expr)

	# 视角与动作差分切换（位于服装栏上方）
	if poses.size() > 1:
		var pcount := poses.size()
		var pgap := 8.0
		var pw := minf(164.0, (706.0 - float(pcount - 1) * pgap) / float(pcount))
		var px := 424.0
		for pg in poses:
			var gk := str(pg.get("key", ""))
			var glabel := str(pg.get("label", gk))
			var pb := btn(glabel, "", "segment", Rect2(px, 904, pw, 46), func(): pose_key = gk; _swap_art(), "c", -1.0, null, 14)
			pb.center_text = true; pb.selected = gk == pose_key; pb.name = "Pose_" + gk
			px += pw + pgap

	# 服装分类切换
	var ocount := outfits.size()
	var ogap := 8.0
	var ow := minf(170.0, (680.0 - float(maxi(0, ocount - 1)) * ogap) / float(maxi(1, ocount)))
	var ox := 440.0
	for o in outfits:
		var ob := btn(OUTFIT_NAMES.get(o, o), "", "segment", Rect2(ox, 962, ow, 54), func():
			outfit = o
			var cat_poses := Data.pose_groups(id, o)
			pose_key = str(cat_poses[0].get("key", o)) if not cat_poses.is_empty() else o
			_swap_art()
		, "c", -1.0, null, 19)
		ob.center_text = true; ob.selected = o == outfit; ob.name = "Outfit_" + o
		ox += ow + ogap

	# 右侧情报栏
	var info := plate(Rect2(1150, 110, 740, 930), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true}, "c", 0.08)
	var title_fs := 44 if cname.length() >= 6 else 60
	text(cname, Rect2(46, 16, 580, 74), title_fs, "ink", 900, "c", info)
	var dia := Control.new(); put(dia, Rect2(46 + Kit.text_width(cname, UiHub.fs(title_fs), 900) + 22, 42, 20, 20), "c", -1.0, info)
	dia.draw.connect(func(): Kit.diamond(dia, Vector2(10, 10), 10, UiHub.c("accent")))
	var y := 92.0
	for f in c.get("fields", []):
		text(f[0], Rect2(46, y, 150, 34), 19, "muted", 700, "c", info)
		var flbl := text(f[1], Rect2(198, y, 502, 34), 19, "ink", 750, "c", info)
		flbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		y += clampf(g(34), 28.0, 40.0)
	var desc_sc := ScrollContainer.new()
	desc_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(desc_sc, Rect2(46, y + 2, 648, 72), "c", -1.0, info)
	var desc := Lbl.new()
	desc.setup(c.get("body", ""), 18, "ink", 600)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.clip_text = false
	desc.custom_minimum_size = Vector2(630, 0)
	desc_sc.add_child(desc)
	y += 80
	var line := Control.new(); put(line, Rect2(46, y, 648, 2), "c", -1.0, info)
	line.draw.connect(func(): line.draw_line(Vector2.ZERO, Vector2(648, 0), UiHub.c("line"), 1.5))
	y += 10

	if not is_npc_flag:
		var cur_form := String(known.get("当前形态", db_st.get("form", "日常")))
		var fet_raw = known.get("已解锁性癖", db_st.get("fetishes", []))
		var fet_list: Array = fet_raw if fet_raw is Array else []
		icon("sparkle", Rect2(46, y + 6, 20, 20), "ink", "c", info)
		text("好感度", Rect2(72, y, 96, 32), 18, "muted", 700, "c", info)
		bar(Rect2(174, y + 10, 420, 12), fav, 100.0, "accent", info)
		text("%d" % int(fav), Rect2(604, y, 90, 32), 20, "accent", 850, "c", info, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 32

		icon("heart", Rect2(46, y + 6, 20, 20), "accent", "c", info)
		text("色情值", Rect2(72, y, 96, 32), 18, "muted", 700, "c", info)
		bar(Rect2(174, y + 10, 420, 12), lewd, 100.0, "ink", info)
		text("%d" % int(lewd), Rect2(604, y, 90, 32), 20, "ink", 850, "c", info, HORIZONTAL_ALIGNMENT_RIGHT)
		y += 32

		var fet_str := "、".join(PackedStringArray(fet_list)) if not fet_list.is_empty() else "尚未解锁"
		text("形态：%s   ｜   性癖：%s" % [cur_form, fet_str], Rect2(46, y, 648, 30), 17, "accent" if not fet_list.is_empty() else "muted", 700, "c", info)
		y += 30
	else:
		text("身份分类：重要 NPC · 已在主线正式邂逅", Rect2(46, y, 648, 32), 18, "accent", 700, "c", info)
		y += 34

	text("近况", Rect2(46, y, 110, 36), 18, "muted", 700, "c", info)
	var intro_txt := String(known.get("简介", ""))
	if intro_txt == "":
		var lloc := String(db_st.get("last_known_location", ""))
		intro_txt = ("最近现身：%s" % lloc) if lloc != "" else "已在主线解锁并收录同伴资料。"
	var intro_lbl := text(intro_txt, Rect2(166, y, 528, 48), 18, "ink", 600, "c", info)
	intro_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	y += 52

	text("表情预览", Rect2(46, y, 220, 28), 18, "muted", 700, "c", info)
	y += 30
	var exprs: Array = Data.content().expressions.duplicate()
	if "confident" in supported_exprs:
		exprs.append(["confident", "自信笑"])
	for k in range(exprs.size()):
		var ex: Array = exprs[k]
		var eb := btn(ex[1], "", "segment", Rect2(46 + (k % 5) * 130, y + (k / 5) * 42, 122, 36), func(): expr = ex[0]; _swap_art(), "c", -1.0, info, 16)
		eb.center_text = true; eb.selected = ex[0] == expr; eb.name = "Expr_" + ex[0]
	y += 92

	# 表情预览下方：原卡日常插图（好感度解锁）与色情插图（色情值解锁）
	if not is_npc_flag:
		_build_gallery_section(info, id, cname, y, fav, lewd)
	else:
		var npc_note := plate(Rect2(46, y + 6, 648, 120), {"shape": "rect", "fill": "surface2", "layered": false}, "c", -1.0, info)
		text("重要 NPC · 仅收录角色单人立绘与主线记事，无好感 / 色情双图集。", Rect2(24, 34, 600, 52), 18, "muted", 600, "c", npc_note, HORIZONTAL_ALIGNMENT_CENTER)

	# 底部快捷入口（已移除与左上角返回重复的右下角返回按钮）
	var cdb := btn("同伴记忆与隐私", "docs", "chip", Rect2(46, 856, 320, 56), func(): root.go("database", {"tab": "characters", "character": id}), "c", -1.0, info, 20)
	cdb.name = "CharDbBtn"
	var ctalk := btn("单独交谈", "chat", "primary", Rect2(384, 856, 310, 56), func(): root.go("talk", {"id": id}), "c", -1.0, info, 20)
	ctalk.name = "CharTalkBtn"

func _build_gallery_section(info: Control, id: String, cname: String, y: float, fav: float, lewd: float) -> void:
	var gal: Dictionary = Data.character_gallery(id)
	var raw_aff: Array = gal.get("affection", []) if gal.get("affection") is Array else []
	var raw_ero: Array = gal.get("erotic", []) if gal.get("erotic") is Array else []
	var aff_items: Array = []
	var aff_unlocked := 0
	for it in raw_aff:
		if not it is Dictionary: continue
		var d: Dictionary = it.duplicate()
		var ok_u := fav >= float(d.get("need", 100))
		d["unlocked"] = ok_u
		if ok_u: aff_unlocked += 1
		aff_items.append(d)
	var ero_items: Array = []
	var ero_unlocked := 0
	for it in raw_ero:
		if not it is Dictionary: continue
		var d: Dictionary = it.duplicate()
		var ok_u := lewd >= float(d.get("need", 100))
		d["unlocked"] = ok_u
		if ok_u: ero_unlocked += 1
		ero_items.append(d)

	var b_aff := btn("日常插图 (%d/%d)" % [aff_unlocked, aff_items.size()], "image", "segment", Rect2(46, y, 206, 38), func():
		if gallery_tab != "affection": gallery_tab = "affection"; refresh(false)
	, "c", -1.0, info, 17)
	b_aff.center_text = true; b_aff.selected = gallery_tab == "affection"; b_aff.name = "GalleryTab_affection"
	var b_ero := btn("色情插图 (%d/%d)" % [ero_unlocked, ero_items.size()], "heart", "segment", Rect2(262, y, 206, 38), func():
		if gallery_tab != "erotic": gallery_tab = "erotic"; refresh(false)
	, "c", -1.0, info, 17)
	b_ero.center_text = true; b_ero.selected = gallery_tab == "erotic"; b_ero.name = "GalleryTab_erotic"

	var rule_hint := ("好感度 %d（每 25 解锁 2 张）" % int(fav)) if gallery_tab == "affection" else ("色情值 %d（每 20 解锁 2 张）" % int(lewd))
	text(rule_hint, Rect2(476, y + 4, 218, 30), 15, "muted", 600, "c", info, HORIZONTAL_ALIGNMENT_RIGHT)

	var cur_items := aff_items if gallery_tab == "affection" else ero_items
	var mode_label := "日常插图" if gallery_tab == "affection" else "色情插图"
	var box_h := maxf(180.0, 846.0 - (y + 44.0))
	var sc := ScrollContainer.new(); sc.name = "CharGalleryScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(sc, Rect2(46, y + 44.0, 648, box_h), "c", -1.0, info)
	var inner := Control.new(); inner.mouse_filter = Control.MOUSE_FILTER_PASS
	sc.add_child(inner)

	if cur_items.is_empty():
		inner.custom_minimum_size = Vector2(630, box_h)
		text("暂无收录该角色的%s。" % mode_label, Rect2(20, 40, 590, 44), 19, "muted", 600, "c", inner, HORIZONTAL_ALIGNMENT_CENTER)
		return

	const COLS := 4
	const CW := 150.0
	const CH := 112.0
	const CGAP := 10.0
	var rows := ceili(float(cur_items.size()) / float(COLS))
	inner.custom_minimum_size = Vector2(634, float(rows) * (CH + CGAP))

	for k in range(cur_items.size()):
		var item: Dictionary = cur_items[k]
		var unlocked_it := bool(item.get("unlocked", false))
		var need := int(item.get("need", 100))
		var res_p := String(item.get("res", ""))
		var col := k % COLS
		var row := k / COLS
		var cx := float(col) * (CW + CGAP)
		var cy := float(row) * (CH + CGAP)
		var b := Btn.new(); b.variant = "secondary"; b.slant = 12
		b.name = "GallerySlot_%s_%d" % [gallery_tab, k + 1]
		put(b, Rect2(cx, cy, CW, CH), "c", -1.0, inner)
		if unlocked_it and res_p != "" and ResourceLoader.exists(res_p):
			var tr := TextureRect.new()
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture = load(res_p)
			put(tr, Rect2(6, 6, CW - 12.0, CH - 28.0), "c", -1.0, b)
			text("#%d · ≥%d" % [k + 1, need], Rect2(6, CH - 22.0, CW - 12.0, 20), 13, "accent", 800, "c", b, HORIZONTAL_ALIGNMENT_CENTER)
			var idx_cap := k
			b.pressed.connect(func(): _open_gallery_zoom(cur_items, idx_cap, cname, mode_label))
		else:
			icon("lock", Rect2(CW * 0.5 - 16.0, 22, 32, 32), "muted", "c", b)
			var req_txt := ("好感 ≥ %d" if gallery_tab == "affection" else "色情 ≥ %d") % need
			text(req_txt, Rect2(6, 64, CW - 12.0, 32), 15, "muted", 700, "c", b, HORIZONTAL_ALIGNMENT_CENTER)
			b.pressed.connect(func(): toast("需要 %s 的%s达到 %d 才能解锁第 %d 张%s" % [cname, "好感度" if gallery_tab == "affection" else "色情值", need, k + 1, mode_label], "lock"))

func _set_page(p: int) -> void:
	var ids: Array = _group_ids()
	var pages := maxi(1, ceili(float(ids.size()) / float(PER_PAGE)))
	page = (p + pages) % pages
	selected = page * PER_PAGE
	outfit = "daily"; pose_key = "daily"; expr = "neutral"
	UiHub.sfx("page")
	refresh(false)
	call_deferred("_nudge")

func _select(i: int) -> void:
	if i == selected: return
	selected = i; page = selected / PER_PAGE; outfit = "daily"; pose_key = "daily"; expr = "neutral"
	refresh(false)
	call_deferred("_nudge")

func _swap_art() -> void:
	if not is_instance_valid(art): return
	var ids: Array = _group_ids()
	if ids.is_empty(): return
	art.show_art(ids[clampi(selected, 0, ids.size() - 1)], pose_key, expr)
	refresh(false)

func _nudge() -> void:
	if is_instance_valid(art) and not UiHub.reduced_motion: Kit.rise(art, 0.0, 22.0, 0.28)
