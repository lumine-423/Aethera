extends "res://scripts/ui/ui_screen.gd"
## 艾瑟拉创意工坊与本地仓库管理面板（迁自原卡 + hotaru-workshop v2.9.2 插件）
## - 逛工坊：直连 https://workshop.hotaruworkshop.l.cd（aethera 板块）浏览/搜索/筛选/查看详情/收藏/下载
## - 管理面板：我的仓库（云端下载同步 + 本地缓存 + 导入官网导出的 .json / 刻印存档 + 一键导入游戏）
## - 已导入管理：查看与卸载已导入的 DLC 角色 / 设定规则 / 刻印图纸
## - 发布作品：上传刻印存档（对齐原卡 btnShopUpload）或 DLC 角色/阵营/事件/玩法/规则/其他

const WorkshopScr = preload("res://scripts/ui/screens/workshop_screen.gd")
const WorkshopHub = preload("res://scripts/game/workshop_hub.gd")

var tab := "browse"        # browse | repo | installed | upload
var cat_filter := "all"
var channel_filter := "all" # all | official | community
var search_q := ""
var selected_pkg_id := ""
var selected_pkg_full: Dictionary = {}
var _detail_loading := false

var repo_selected := {}    # pkg_id -> bool
var upload_cat := "blueprint"
var upload_title := ""
var upload_desc := ""
var upload_cover := ""
var upload_role_name := ""
var upload_role_daily_url := ""
var upload_role_form_url := ""
var upload_role_avatar_url := ""
var upload_role_overview := ""
var upload_role_archive := ""
var upload_keywords := ""
var upload_event_names := ""
var upload_event_roles := ""
var upload_body := ""
var upload_sigil_archive: Dictionary = {}

var modal := ""            # "" | auth
var _oauth_msg := ""
var _token_draft := ""
var _busy_msg := ""
var _initial_loaded := false

func open(owner_root: Node, p: Dictionary) -> void:
	super.open(owner_root, p)
	if p.has("tab"): tab = String(p.get("tab", "browse"))
	if p.has("cat"): cat_filter = String(p.get("cat", "all"))
	if p.has("upload_sigil_archive") and p.get("upload_sigil_archive") is Dictionary:
		upload_sigil_archive = p.get("upload_sigil_archive").duplicate(true)
		upload_cat = "blueprint"
		var first_s: Dictionary = upload_sigil_archive.get("saved", [{}])[0] if not upload_sigil_archive.get("saved", []).is_empty() else {}
		var nm := String(first_s.get("name", "")).strip_edges()
		if nm != "" and nm != "未命名符印": upload_title = nm
		upload_desc = String(first_s.get("effect", ""))
	if upload_sigil_archive.is_empty():
		_prefill_first_saved_sigil()

func _prefill_first_saved_sigil() -> void:
	var store_path := hub()._workshop_store_path()
	if not FileAccess.file_exists(store_path): return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(store_path))
	if not parsed is Dictionary: return
	var d: Dictionary = parsed.get("draft", {}) if parsed.get("draft") is Dictionary else {}
	if d.get("parts") is Array and not d.parts.is_empty():
		upload_sigil_archive = WorkshopScr.current_archive_for_draft(d, 0)
		if upload_title == "" and String(d.get("name", "")) != "": upload_title = String(d.get("name", ""))
		if upload_desc == "": upload_desc = String(d.get("effect", ""))
		return
	var sv: Array = parsed.get("saved", []) if parsed.get("saved") is Array else []
	if not sv.is_empty() and sv[0] is Dictionary and sv[0].get("parts") is Array and not sv[0].parts.is_empty():
		upload_sigil_archive = WorkshopScr.current_archive_for_draft(sv[0], int(sv[0].get("cost", 0)))
		if upload_title == "": upload_title = String(sv[0].get("name", ""))
		if upload_desc == "": upload_desc = String(sv[0].get("effect", ""))

func hub() -> WorkshopHub:
	return UiHub.workshop() as WorkshopHub

func _ready() -> void:
	super._ready()
	var h := hub()
	if not h.changed.is_connected(_on_hub_changed): h.changed.connect(_on_hub_changed)
	if not h.oauth_status.is_connected(_on_oauth_status): h.oauth_status.connect(_on_oauth_status)
	if not _initial_loaded:
		_initial_loaded = true
		if h.catalog.is_empty() and not UiHub.review_mode:
			h.refresh_catalog()
		if h.is_logged_in() and not UiHub.review_mode:
			h.sync_cloud_downloads()
			h.refresh_favorites()

func _exit_tree() -> void:
	var h := UiHub.workshop()
	if is_instance_valid(h):
		if h.changed.is_connected(_on_hub_changed): h.changed.disconnect(_on_hub_changed)
		if h.oauth_status.is_connected(_on_oauth_status): h.oauth_status.disconnect(_on_oauth_status)

func _on_hub_changed() -> void:
	if is_inside_tree(): refresh(false)

func _on_oauth_status(st: String, msg: String) -> void:
	_oauth_msg = msg
	if st == "ok":
		toast(msg, "check")
		modal = ""
		hub().refresh_catalog()
	elif st == "error":
		toast(msg, "warn")
	if is_inside_tree(): refresh(false)

func build() -> void:
	uses_backdrop = true
	backdrop_style = "room"
	decor(77, Rect2(Vector2.ZERO, size), 0.35)
	chrome("创意工坊")

	var h := hub()
	var repo_count := h.repo_packages().size()
	var inst_pkgs_map: Dictionary = h.installed.get("packages", {}) if h.installed.get("packages") is Dictionary else {}
	var inst_count: int = inst_pkgs_map.size()
	var top_tabs := [
		["browse", "逛工坊", 136.0],
		["repo", "管理面板 (%d)" % repo_count, 186.0],
		["installed", "已导入 (%d)" % inst_count, 162.0],
		["upload", "发布作品", 146.0],
	]
	var tx := 382.0
	for t in top_tabs:
		var k := String(t[0]); var cap := String(t[1]); var tw := float(t[2])
		var tb := btn(cap, "", "tab", Rect2(tx, 34, tw, 64), func():
			tab = k; modal = ""; refresh(false)
		, "lt", -1.0, null, 20)
		tb.selected = (tab == k)
		tb.center_text = true
		tb.name = "CwTab_" + k
		tx += tw + 8.0

	var acc_cap := ("已登录 · " + h.display_name()) if h.is_logged_in() else "Discord 登录 / 账号"
	var acc_btn := btn(acc_cap, "unlock" if h.is_logged_in() else "person", "chip", Rect2(1134, 34, 366, 64), func():
		modal = "auth"; refresh(false)
	, "rt", -1.0, null, 19)
	acc_btn.name = "CwAccountBtn"
	acc_btn.selected = h.is_logged_in()

	match tab:
		"repo": _build_repo(h)
		"installed": _build_installed(h)
		"upload": _build_upload(h)
		_: _build_browse(h)

	if modal == "auth":
		_build_auth_modal(h)

# ================================================================ 逛工坊（艾瑟拉云端浏览 + 下载）
func _filtered_catalog(h: WorkshopHub) -> Array:
	var q := search_q.strip_edges().to_lower()
	var out: Array = []
	for p in h.catalog:
		if not p is Dictionary: continue
		var cat_k := String(p.get("category", p.get("type", "")))
		if cat_filter != "all" and cat_k != cat_filter: continue
		if channel_filter == "official" and not bool(p.get("official", false)): continue
		if channel_filter == "community" and bool(p.get("official", false)): continue
		if q != "":
			var pub: Dictionary = p.get("publisher", {}) if p.get("publisher") is Dictionary else {}
			var hay := (String(p.get("title", "")) + " " + String(pub.get("displayName", "")) + " " + String(pub.get("username", "")) + " " + h.summary_of(p)).to_lower()
			if not hay.contains(q): continue
		out.append(p)
	return out

func _build_browse(h: WorkshopHub) -> void:
	var bar_p := plate(Rect2(36, 118, 1848, 134), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.04)
	var se := LineEdit.new(); se.name = "CwSearchInput"; se.text = search_q; se.placeholder_text = "搜索作品名称、作者或简介（回车检索）"
	put(se, Rect2(22, 14, 620, 48), "c", -1.0, bar_p)
	se.text_submitted.connect(func(nt): search_q = nt; refresh(false))
	var sb := btn("搜索", "search", "secondary", Rect2(654, 14, 114, 48), func(): search_q = se.text; refresh(false), "c", -1.0, bar_p, 19)
	sb.name = "CwSearchBtn"
	if search_q != "":
		var cl := btn("清空", "close", "ghost", Rect2(776, 14, 96, 48), func(): search_q = ""; refresh(false), "c", -1.0, bar_p, 18)
		cl.name = "CwSearchClear"

	var cx := 892.0
	for ch in [["all", "全部来源"], ["official", "官方精选"], ["community", "玩家共创"]]:
		var ck := String(ch[0])
		var cb := btn(String(ch[1]), "", "segment", Rect2(cx, 16, 116, 44), func(): channel_filter = ck; refresh(false), "c", -1.0, bar_p, 16)
		cb.selected = channel_filter == ck; cb.center_text = true; cb.name = "CwChan_" + ck
		cx += 122.0

	var ref_b := btn("刷新列表", "refresh", "secondary", Rect2(1284, 14, 164, 48), func(): h.refresh_catalog(), "c", -1.0, bar_p, 19)
	ref_b.name = "CwRefreshBtn"
	var web_b := btn("打开网页工坊", "globe", "chip", Rect2(1462, 14, 190, 48), func():
		OS.shell_open(h.gateway + "/?scope=aethera")
		toast("已在浏览器打开荧荧工坊（艾瑟拉板块）", "globe")
	, "c", -1.0, bar_p, 18)
	web_b.name = "CwOpenWebBtn"
	var go_repo := btn("去管理面板导入", "download", "primary", Rect2(1664, 14, 164, 48), func(): tab = "repo"; refresh(false), "c", -1.0, bar_p, 17)
	go_repo.name = "CwQuickRepoBtn"

	# Category strip
	var cat_x := 22.0
	for item in h.CATEGORIES:
		var ck := String(item.key); var clabel := String(item.label)
		var w := clampf(Kit.text_width(clabel, UiHub.fs(18), 700) + 46.0, 88.0, 170.0)
		var cb := btn(clabel, "", "segment", Rect2(cat_x, 74, w, 44), func(): cat_filter = ck; refresh(false), "c", -1.0, bar_p, 17)
		cb.selected = cat_filter == ck; cb.center_text = true; cb.name = "CwCat_" + ck
		cat_x += w + 8.0

	# Left grid
	var list_p := plate(Rect2(36, 266, 1180, 774), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.06)
	var items := _filtered_catalog(h)
	var header_msg := "艾瑟拉世界板块 · 共 %d 件公开作品" % items.size()
	if h.catalog_loading: header_msg = "正在从荧荧工坊拉取艾瑟拉板块列表…"
	elif h.last_error != "" and items.is_empty(): header_msg = "云端连接异常：" + h.last_error
	text(header_msg, Rect2(26, 16, 860, 38), 21, "accent" if h.last_error != "" and items.is_empty() else "ink", 800, "c", list_p)
	text("免登录即可下载并导入公开作品", Rect2(880, 18, 276, 34), 16, "muted", 600, "c", list_p, HORIZONTAL_ALIGNMENT_RIGHT)

	if items.is_empty():
		var empty_t := "正在连接云端工坊…" if h.catalog_loading else ("暂无符合当前筛选的作品" if h.last_error == "" else "暂时无法连上荧荧工坊，请检查网络，或切换到「管理面板」直接导入网页导出的 .json 文件。")
		var em := text(empty_t, Rect2(80, 140, 1020, 110), 22, "muted", 600, "c", list_p, HORIZONTAL_ALIGNMENT_CENTER)
		em.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if not h.catalog_loading:
			var r_btn := btn("重新拉取列表", "refresh", "secondary", Rect2(310, 276, 260, 64), func(): h.refresh_catalog(), "c", -1.0, list_p, 21)
			r_btn.name = "CwRetryCatalog"
			var m_btn := btn("打开管理面板导入文件", "upload", "primary", Rect2(590, 276, 290, 64), func(): tab = "repo"; refresh(false), "c", -1.0, list_p, 21)
			m_btn.name = "CwEmptyToRepo"
	else:
		var sc := ScrollContainer.new(); sc.name = "CwCatalogScroll"
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		put(sc, Rect2(20, 64, 1140, 692), "c", -1.0, list_p)
		var grid := GridContainer.new(); grid.columns = 2
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 14)
		sc.add_child(grid)
		for idx in range(items.size()):
			var pkg: Dictionary = items[idx]
			grid.add_child(_make_catalog_card(h, pkg, idx))

	# Right inspector
	_build_detail_inspector(h, Rect2(1234, 266, 650, 774))

func _make_catalog_card(h: WorkshopHub, pkg: Dictionary, idx: int) -> Control:
	var pid := String(pkg.get("id", ""))
	var is_sel := selected_pkg_id == pid
	var card := Plate.new(); card.shape = "rect"; card.corner = "tr"; card.corner_size = 16; card.layered = is_sel
	card.custom_minimum_size = Vector2(552, 188)
	card.name = "CwCard_%d" % idx

	var cover := h.cover_url_of(pkg)
	var tex: Texture2D = h.cached_thumb(cover) if cover != "" else null
	if tex != null:
		var tr := TextureRect.new(); tr.texture = tex; tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(14, 14); tr.size = Vector2(96, 130)
		card.add_child(tr)
	else:
		var icon_box := Plate.new(); icon_box.shape = "rect"; icon_box.fill = "surface2"; icon_box.layered = false
		icon_box.position = Vector2(14, 14); icon_box.size = Vector2(96, 130); card.add_child(icon_box)
		var cat_k := String(pkg.get("category", pkg.get("type", "")))
		var ic_map := {"blueprint": "seal", "character": "person", "faction": "shield", "event": "book", "gameplay": "play", "rule": "docs", "cosmetic_frontend": "image"}
		var ic_name := String(ic_map.get(cat_k, "star4"))
		icon(ic_name, Rect2(24, 40, 48, 48), "accent" if bool(pkg.get("official", false)) else "ink", "c", icon_box)

	var title := String(pkg.get("title", "未命名"))
	var pub: Dictionary = pkg.get("publisher", {}) if pkg.get("publisher") is Dictionary else {}
	var author := String(pub.get("displayName", pub.get("username", "匿名")))
	if bool(pkg.get("official", false)): author += " · 官方"
	var kind_str := h.category_label(String(pkg.get("category", pkg.get("type", ""))))

	text(title, Rect2(124, 12, 412, 34), 22, "accent" if is_sel else "ink", 850, "c", card)
	text("%s  ·  %s  ·  下载 %d" % [author, kind_str, int(pkg.get("downloads", 0))], Rect2(124, 46, 412, 26), 15, "muted", 600, "c", card)
	var sum_lbl := text(h.summary_of(pkg), Rect2(124, 76, 412, 52), 16, "ink", 500, "c", card)
	sum_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var in_repo := h.repo_packages().any(func(rp): return String(rp.get("id", "")) == pid)
	var b_view := btn("查看详情", "", "ghost", Rect2(124, 136, 130, 40), func(): _select_pkg(pkg), "c", -1.0, card, 16)
	b_view.name = "CwCardView_%d" % idx
	var b_dl := btn("已在管理面板" if in_repo else "下载入仓", "check" if in_repo else "download", "secondary" if in_repo else "primary", Rect2(262, 136, 146, 40), func():
		_download_with_feedback(pkg)
	, "c", -1.0, card, 16)
	b_dl.name = "CwCardDl_%d" % idx
	var b_imp := btn("一键导入", "upload", "chip", Rect2(416, 136, 122, 40), func():
		_download_and_import(pkg)
	, "c", -1.0, card, 16)
	b_imp.name = "CwCardImp_%d" % idx
	return card

func _select_pkg(pkg: Dictionary) -> void:
	selected_pkg_id = String(pkg.get("id", ""))
	selected_pkg_full = pkg.duplicate(true)
	if not (pkg.get("payload") is Dictionary) or pkg.payload.is_empty():
		_detail_loading = true
		refresh(false)
		hub().fetch_package_detail(selected_pkg_id, func(ok_flag: bool, full: Dictionary, err: String):
			_detail_loading = false
			if ok_flag and String(full.get("id", "")) == selected_pkg_id:
				selected_pkg_full = full
			elif not ok_flag:
				toast(err, "warn")
			if is_inside_tree(): refresh(false)
		)
	else:
		_detail_loading = false
		refresh(false)

func _build_detail_inspector(h: WorkshopHub, rect: Rect2) -> void:
	var dp := plate(rect, {"shape": "cut", "slant": 30, "corner": "tr"}, "c", 0.08)
	if selected_pkg_id == "" or selected_pkg_full.is_empty():
		icon("globe", Rect2(288, 220, 74, 74), "muted", "c", dp)
		text("艾瑟拉创意工坊详情", Rect2(40, 316, 570, 44), 28, "ink", 800, "c", dp, HORIZONTAL_ALIGNMENT_CENTER)
		var g_lbl := text("点左侧任意作品卡片查看详情；也可直接点击「下载入仓」或「一键导入」。\n\n支持导入到本机游戏的内容：\n· 刻印（blueprint）：导入到「刻印工坊 → 已保存」\n· 角色（character）：导入到「世界书 DLC」及角色控制器\n· 阵营 / 事件 / 玩法 / 规则：导入到「世界书」并在对话读取", Rect2(56, 376, 538, 220), 19, "muted", 600, "c", dp, HORIZONTAL_ALIGNMENT_CENTER)
		g_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return

	var pkg: Dictionary = selected_pkg_full
	var pid := String(pkg.get("id", ""))
	var cat_k := String(pkg.get("category", pkg.get("type", "")))
	var pub: Dictionary = pkg.get("publisher", {}) if pkg.get("publisher") is Dictionary else {}
	var author := String(pub.get("displayName", pub.get("username", "匿名")))
	header(String(pkg.get("title", "未命名")), Rect2(26, 20, 598, 48), 28, "c", dp)
	text("%s · %s · %s · 下载 %d · 收藏 %d" % [author, h.category_label(cat_k), "已导入 ✓" if h.is_installed(pid) else "未导入", int(pkg.get("downloads", 0)), int(pkg.get("favs", 0))], Rect2(26, 74, 598, 30), 16, "accent" if h.is_installed(pid) else "muted", 700, "c", dp)

	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(sc, Rect2(26, 114, 598, 490), "c", -1.0, dp)
	var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; col.add_theme_constant_override("separation", 12)
	sc.add_child(col)
	var detail_text := _format_pkg_detail(pkg)
	if _detail_loading: detail_text += "\n\n（正在向服务器加载完整载荷…）"
	var body_lbl := Lbl.new(); body_lbl.setup(detail_text, 19, "ink", 550)
	body_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(body_lbl)

	var is_fav := pid in h.fav_ids
	var dl_b := btn("下载到管理面板", "download", "secondary", Rect2(26, 622, 290, 62), func(): _download_with_feedback(pkg), "c", -1.0, dp, 20)
	dl_b.name = "CwDetailDownload"
	var imp_b := btn("下载并立即导入", "upload", "primary", Rect2(334, 622, 290, 62), func(): _download_and_import(pkg), "c", -1.0, dp, 20)
	imp_b.name = "CwDetailImportNow"

	var fav_b := btn("已收藏 ★" if is_fav else "收藏作品", "heart", "chip", Rect2(26, 696, 186, 56), func():
		h.toggle_favorite(pid, func(ok_f: bool, now_on: bool, err: String):
			if ok_f: toast("已加入收藏" if now_on else "已取消收藏", "heart")
			else: toast(err, "warn")
		)
	, "c", -1.0, dp, 18)
	fav_b.name = "CwDetailFav"; fav_b.selected = is_fav
	var exp_b := btn("导出 .json", "save", "chip", Rect2(226, 696, 190, 56), func():
		var full_d: Callable = func(ok_d: bool, fp: Dictionary, err_d: String):
			if not ok_d: toast(err_d, "warn"); return
			var saved_path: String = h.export_package_file(fp)
			toast("已导出到：" + saved_path, "save")
		if pkg.get("payload") is Dictionary and not pkg.payload.is_empty(): full_d.call(true, pkg, "")
		else: h.fetch_package_detail(pid, full_d)
	, "c", -1.0, dp, 18)
	exp_b.name = "CwDetailExport"
	var can_del := h.is_logged_in() and (h.is_admin or String(pub.get("discordId", "")) == String(h.user.get("id", "")))
	if can_del:
		var del_b := btn("下架删除", "trash", "danger", Rect2(430, 696, 194, 56), func(): _confirm_delete_cloud(pkg), "c", -1.0, dp, 18)
		del_b.name = "CwDetailDelete"

func _format_pkg_detail(pkg: Dictionary) -> String:
	var cat_k := String(pkg.get("category", pkg.get("type", "")))
	var payload: Dictionary = pkg.get("payload", {}) if pkg.get("payload") is Dictionary else {}
	var extra: Dictionary = payload.get("extra", {}) if payload.get("extra") is Dictionary else {}
	var lines := PackedStringArray(["【作品 ID】" + String(pkg.get("id", "")) + "  （v%d）" % int(pkg.get("revision", 1))])
	if cat_k == "blueprint":
		var arch: Variant = extra.get("sigilArchive", payload.get("sigilArchive", {}))
		var sv: Array = arch.get("saved", []) if arch is Dictionary and arch.get("saved") is Array else []
		lines.append("【效果描述】" + String(extra.get("desc", "无")))
		lines.append("【内含刻印】共 %d 道魔法图纸" % sv.size())
		for s in sv:
			if s is Dictionary:
				lines.append(" · 《%s》 载体：%s · 纹章：%d 枚" % [String(s.get("name", "未命名")), String(s.get("carrier", "未指定")), s.get("parts", []).size()])
	elif cat_k == "character":
		var rns: Array = extra.get("roleNames", []) if extra.get("roleNames") is Array else []
		lines.append("【角色真名】" + ("、".join(PackedStringArray(rns)) if not rns.is_empty() else "未填写"))
		if String(extra.get("overview", "")) != "": lines.append("\n【角色速览】\n" + String(extra.get("overview", "")))
		if String(extra.get("archive", "")) != "": lines.append("\n【角色档案】\n" + String(extra.get("archive", "")))
	elif cat_k == "faction":
		var kws: Array = extra.get("keywords", []) if extra.get("keywords") is Array else []
		lines.append("【触发关键词】" + ("、".join(PackedStringArray(kws)) if not kws.is_empty() else String(pkg.get("title", ""))))
		lines.append("\n【阵营设定】\n" + String(extra.get("content", "")))
	elif cat_k == "event":
		var ens: Array = extra.get("eventNames", []) if extra.get("eventNames") is Array else []
		var rns2: Array = extra.get("roleNames", []) if extra.get("roleNames") is Array else []
		lines.append("【事件标识】" + "、".join(PackedStringArray(ens)))
		lines.append("【绑定角色】" + ("、".join(PackedStringArray(rns2)) if not rns2.is_empty() else "通用"))
		lines.append("\n【剧情内容】\n" + String(extra.get("content", "")))
	else:
		var body_t := String(extra.get("content", extra.get("desc", pkg.get("summary", ""))))
		if body_t != "": lines.append("\n【内容正文】\n" + body_t)
	return "\n".join(lines)

func _download_with_feedback(pkg: Dictionary) -> void:
	hub().download_package(pkg, func(ok_flag: bool, full_pkg: Dictionary, err: String):
		if ok_flag:
			var t := String(full_pkg.get("title", pkg.get("title", "")))
			selected_pkg_full = full_pkg
			toast("已下载《%s》到管理面板，可随时勾选导入" % t, "download")
			UiHub.sfx("confirm")
		else:
			toast(err, "warn")
			UiHub.sfx("deny")
	)

func _download_and_import(pkg: Dictionary) -> void:
	hub().download_package(pkg, func(ok_flag: bool, full_pkg: Dictionary, err: String):
		if not ok_flag:
			toast(err, "warn"); UiHub.sfx("deny"); return
		_run_import_with_feedback([full_pkg])
	)

func _confirm_delete_cloud(pkg: Dictionary) -> void:
	var title := String(pkg.get("title", ""))
	var d = root.dialog({"title": "下架并删除云端作品", "message": "确定从荧荧工坊永久删除《%s》？此操作不可撤回。" % title, "icon": "trash", "tone": "danger", "buttons": [{"id": "cancel", "text": "取消", "icon": "close"}, {"id": "ok", "text": "确认删除", "icon": "trash", "kind": "primary"}]})
	d.chosen.connect(func(id: String):
		if id == "ok":
			hub().delete_cloud_package(String(pkg.get("id", "")), func(ok_d: bool, err: String):
				if ok_d:
					selected_pkg_id = ""; selected_pkg_full = {}
					toast("已从云端删除《%s》" % title, "trash")
				else:
					toast("删除失败：" + err, "warn")
			)
	)

# ================================================================ 管理面板（我的仓库 + 导入）
func _build_repo(h: WorkshopHub) -> void:
	var acc_p := plate(Rect2(36, 118, 1848, 128), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.04)
	if h.is_logged_in():
		text("已登录账号：%s%s" % [h.display_name(), " · 管理员" if h.is_admin else ""], Rect2(28, 18, 720, 42), 25, "accent", 850, "c", acc_p)
		text("你在网页工坊（https://workshop.hotaruworkshop.l.cd/?scope=aethera）点击「下载」的作品会同步到这里。", Rect2(28, 66, 920, 36), 17, "muted", 600, "c", acc_p)
		var sync_b := btn("同步云端下载", "refresh", "primary", Rect2(1010, 26, 206, 68), func():
			h.sync_cloud_downloads(func(ok_s: bool, err: String):
				if ok_s: toast("云端下载列表已同步", "check")
				else: toast("同步失败：" + err, "warn")
			)
		, "c", -1.0, acc_p, 20)
		sync_b.name = "CwSyncCloudBtn"
		var web_b := btn("去网页挑作品", "globe", "secondary", Rect2(1232, 26, 200, 68), func():
			OS.shell_open(h.gateway + "/?scope=aethera")
		, "c", -1.0, acc_p, 19)
		web_b.name = "CwRepoOpenWeb"
		var out_b := btn("退出登录", "power", "ghost", Rect2(1660, 26, 160, 68), func():
			h.logout(); toast("已退出工坊账号", "info")
		, "c", -1.0, acc_p, 19)
		out_b.name = "CwLogoutBtn"
	else:
		text("未登录 Discord 账号 —— 免登录也能「逛工坊直接下载」或「导入网页导出的 .json 文件」", Rect2(28, 18, 1080, 42), 23, "ink", 800, "c", acc_p)
		var note_txt := _oauth_msg if _oauth_msg != "" else "点击右侧「Discord 登录」将打开系统浏览器完成授权并自动传回游戏，之后就能同步云端下载与发布作品。"
		text(note_txt, Rect2(28, 66, 1080, 38), 17, "muted", 600, "c", acc_p)
		var lg_b := btn("Discord 登录", "unlock", "primary", Rect2(1140, 26, 224, 68), func():
			h.begin_discord_login()
		, "c", -1.0, acc_p, 21)
		lg_b.name = "CwLoginDiscordBtn"
		var tk_b := btn("粘贴令牌", "docs", "secondary", Rect2(1380, 26, 174, 68), func():
			modal = "auth"; refresh(false)
		, "c", -1.0, acc_p, 19)
		tk_b.name = "CwManualTokenBtn"
		var wb_b := btn("打开网页工坊", "globe", "chip", Rect2(1570, 26, 250, 68), func():
			OS.shell_open(h.gateway + "/?scope=aethera")
		, "c", -1.0, acc_p, 19)
		wb_b.name = "CwRepoOpenWeb"

	var repo := h.repo_packages()
	var act_p := plate(Rect2(36, 260, 1848, 72), {"shape": "rect", "fill": "surface2", "layered": false}, "c", 0.05)
	var all_checked := not repo.is_empty() and repo.all(func(rp): return bool(repo_selected.get(String(rp.get("id", "")), false)))
	var sel_all_b := btn("取消全选" if all_checked else "全选 (%d)" % repo.size(), "check", "chip", Rect2(18, 12, 168, 48), func():
		var target := not all_checked
		for rp in repo: repo_selected[String(rp.get("id", ""))] = target
		refresh(false)
	, "c", -1.0, act_p, 18)
	sel_all_b.name = "CwRepoSelectAll"
	sel_all_b.disabled = repo.is_empty()

	var sel_list: Array = repo.filter(func(rp): return bool(repo_selected.get(String(rp.get("id", "")), false)))
	var imp_sel := btn("导入选中到游戏 (%d)" % sel_list.size(), "upload", "primary", Rect2(200, 12, 264, 48), func():
		_import_selected_repo(sel_list)
	, "c", -1.0, act_p, 19)
	imp_sel.name = "CwImportSelectedBtn"
	imp_sel.disabled = sel_list.is_empty()

	var imp_file := btn("导入本地文件 (.json)", "download", "secondary", Rect2(478, 12, 246, 48), func():
		_pick_workshop_files()
	, "c", -1.0, act_p, 19)
	imp_file.name = "CwImportFileBtn"

	var go_browse := btn("去逛工坊下载", "globe", "ghost", Rect2(738, 12, 196, 48), func():
		tab = "browse"; refresh(false)
	, "c", -1.0, act_p, 18)
	go_browse.name = "CwRepoGoBrowse"
	text("支持格式：网页工坊导出包（hotaru-*.json）、刻印工坊 v3 存档（.json）", Rect2(960, 18, 860, 36), 16, "muted", 600, "c", act_p, HORIZONTAL_ALIGNMENT_RIGHT)

	var list_p := plate(Rect2(36, 346, 1848, 694), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.06)
	if repo.is_empty():
		text("仓库里还没有待导入的作品。\n可以去「逛工坊」直接下载公开作品，或在网页工坊导出 .json 后点击上方「导入本地文件 (.json)」。", Rect2(140, 210, 1568, 120), 23, "muted", 650, "c", list_p, HORIZONTAL_ALIGNMENT_CENTER)
		var g_b := btn("前往逛工坊挑作品", "globe", "primary", Rect2(760, 360, 328, 70), func(): tab = "browse"; refresh(false), "c", -1.0, list_p, 22)
		g_b.name = "CwRepoEmptyBrowse"
		return

	var sc := ScrollContainer.new(); sc.name = "CwRepoScroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(sc, Rect2(20, 18, 1808, 658), "c", -1.0, list_p)
	var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; col.add_theme_constant_override("separation", 10)
	sc.add_child(col)
	for i in range(repo.size()):
		col.add_child(_make_repo_row(h, repo[i], i))

func _make_repo_row(h: WorkshopHub, pkg: Dictionary, idx: int) -> Control:
	var pid := String(pkg.get("id", ""))
	var is_checked := bool(repo_selected.get(pid, false))
	var is_inst := h.is_installed(pid)
	var row := Plate.new(); row.shape = "rect"; row.fill = "surface2"; row.layered = is_checked
	row.custom_minimum_size = Vector2(1788, 92)
	row.name = "CwRepoRow_%d" % idx

	var chk := btn("✓" if is_checked else "", "", "segment", Rect2(18, 22, 48, 48), func():
		repo_selected[pid] = not is_checked; refresh(false)
	, "c", -1.0, row, 22)
	chk.selected = is_checked; chk.center_text = true; chk.name = "CwRepoChk_%d" % idx

	var cat_k := String(pkg.get("category", pkg.get("type", "")))
	var pub: Dictionary = pkg.get("publisher", {}) if pkg.get("publisher") is Dictionary else {}
	var author := String(pub.get("displayName", pub.get("username", "本地")))
	var src_tag := "云端＋本地" if (bool(pkg.get("_in_cloud", false)) and bool(pkg.get("_in_local", false))) else ("云端下载" if bool(pkg.get("_in_cloud", false)) else "本地仓库")
	var status_tag := " · 已导入 ✓" if is_inst else " · 未导入"

	text(String(pkg.get("title", "未命名")), Rect2(86, 12, 740, 38), 24, "accent" if is_inst else "ink", 850, "c", row)
	text("%s · %s · %s%s" % [h.category_label(cat_k), author, src_tag, status_tag], Rect2(86, 50, 980, 30), 17, "accent" if is_inst else "muted", 650, "c", row)

	var one_imp := btn("重新导入" if is_inst else "导入", "upload", "secondary" if is_inst else "primary", Rect2(1260, 18, 174, 56), func():
		_import_selected_repo([pkg])
	, "c", -1.0, row, 19)
	one_imp.name = "CwRepoImport_%d" % idx
	var det_b := btn("详情", "info", "chip", Rect2(1448, 18, 150, 56), func():
		tab = "browse"; _select_pkg(pkg)
	, "c", -1.0, row, 18)
	det_b.name = "CwRepoDetail_%d" % idx
	var del_b := btn("移除", "trash", "ghost", Rect2(1612, 18, 150, 56), func():
		repo_selected.erase(pid)
		h.remove_repo_package(pid, func(_ok): toast("已从管理面板移除", "trash"))
	, "c", -1.0, row, 18)
	del_b.name = "CwRepoRemove_%d" % idx
	return row

func _import_selected_repo(pkgs: Array) -> void:
	if pkgs.is_empty(): return
	var need_fetch := pkgs.filter(func(p): return not (p.get("payload") is Dictionary) or p.payload.is_empty())
	if need_fetch.is_empty():
		_run_import_with_feedback(pkgs)
		return
	# Fetch missing payloads one by one (e.g. cloud download summaries needing /packages/:id)
	var resolved: Array = pkgs.filter(func(p): return p.get("payload") is Dictionary and not p.payload.is_empty())
	var remaining := need_fetch.size()
	for p in need_fetch:
		hub().fetch_package_detail(String(p.get("id", "")), func(ok_d: bool, full_p: Dictionary, err_d: String):
			if ok_d and not full_p.is_empty():
				hub().upsert_local_packs([full_p])
				resolved.append(full_p)
			else:
				toast("拉取《%s》内容失败：%s" % [String(p.get("title", "")), err_d], "warn")
			remaining -= 1
			if remaining <= 0 and not resolved.is_empty():
				_run_import_with_feedback(resolved)
		)

func _run_import_with_feedback(pkgs: Array) -> void:
	var res := hub().import_packages_into_game(pkgs)
	if bool(res.ok):
		var parts := PackedStringArray()
		if int(res.sigil_added) > 0: parts.append("刻印图纸 +%d（已在「刻印工坊 → 已保存」）" % int(res.sigil_added))
		if int(res.wb_added) > 0: parts.append("世界书 / DLC +%d（已在「设置 → 世界书」生效）" % int(res.wb_added))
		UiHub.sfx("confirm")
		toast("导入成功：" + "；".join(parts), "check")
		for p in pkgs: repo_selected.erase(String(p.get("id", "")))
	else:
		UiHub.sfx("deny")
		var sk: Array = res.get("skipped", [])
		toast("导入失败：" + ("；".join(PackedStringArray(sk)) if not sk.is_empty() else "无有效内容"), "warn")
	refresh(false)

func _pick_workshop_files() -> void:
	if OS.has_feature("web"):
		toast("网页预览暂不支持本地文件选择器，请用电脑版或点击「逛工坊」直接下载", "info")
		return
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json ; 荧荧工坊 / 刻印存档 JSON"])
	fd.use_native_dialog = true
	add_child(fd)
	fd.files_selected.connect(func(paths: PackedStringArray):
		var total_added := 0
		var errs := PackedStringArray()
		for p in paths:
			var r := hub().import_local_file(p)
			if bool(r.ok): total_added += int(r.added)
			else: errs.append(String(r.error))
		if total_added > 0:
			UiHub.sfx("confirm")
			toast("已加入 %d 件作品到管理面板，请勾选后点「导入选中到游戏」" % total_added, "upload")
		if not errs.is_empty():
			toast("；".join(errs), "warn")
		fd.queue_free()
		refresh(false)
	)
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(920, 620))

# ================================================================ 已导入管理
func _build_installed(h: WorkshopHub) -> void:
	var bar_p := plate(Rect2(36, 118, 1848, 92), {"shape": "rect", "corner": "tr", "corner_size": 20}, "c", 0.04)
	var pkgs_map: Dictionary = h.installed.get("packages", {})
	var dlc_map: Dictionary = h.installed.get("dlc_characters", {})
	text("已导入到本机的工坊扩展：%d 项作品 · %d 位 DLC 角色" % [pkgs_map.size(), dlc_map.size()], Rect2(26, 22, 1080, 48), 24, "ink", 800, "c", bar_p)
	var go_ws := btn("打开刻印工坊查看魔法", "seal", "secondary", Rect2(1270, 18, 274, 56), func(): root.go("workshop"), "c", -1.0, bar_p, 19)
	go_ws.name = "CwInstalledGoWorkshop"
	var go_wb := btn("打开世界书查看 DLC", "book", "primary", Rect2(1560, 18, 260, 56), func(): root.go("settings", {"tab": "worldbook"}), "c", -1.0, bar_p, 19)
	go_wb.name = "CwInstalledGoWorldbook"

	var list_p := plate(Rect2(36, 224, 1848, 816), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.06)
	if pkgs_map.is_empty():
		text("当前还没有向游戏内导入过任何工坊作品。\n请到「逛工坊」下载或「管理面板」选中作品导入。", Rect2(140, 260, 1568, 100), 23, "muted", 650, "c", list_p, HORIZONTAL_ALIGNMENT_CENTER)
		return
	var sc := ScrollContainer.new(); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(sc, Rect2(20, 20, 1808, 776), "c", -1.0, list_p)
	var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; col.add_theme_constant_override("separation", 10)
	sc.add_child(col)
	for pid in pkgs_map.keys():
		var rec: Dictionary = pkgs_map[pid]
		var row := Plate.new(); row.shape = "rect"; row.fill = "surface2"; row.layered = false
		row.custom_minimum_size = Vector2(1788, 90)
		text(String(rec.get("title", pid)), Rect2(26, 12, 920, 36), 24, "ink", 850, "c", row)
		var cat_lbl := h.category_label(String(rec.get("category", "")))
		var detail_sub := "%s · 版本 v%d · 导入于 %s" % [cat_lbl, int(rec.get("revision", 1)), String(rec.get("imported_at", ""))]
		if rec.has("sigil_ids"): detail_sub += " · 已写入 %d 道刻印" % rec.sigil_ids.size()
		elif rec.has("dlc_chars"): detail_sub += " · 已接入角色：" + "、".join(PackedStringArray(rec.dlc_chars))
		elif rec.has("wb_ids"): detail_sub += " · 已写入 %d 条世界书" % rec.wb_ids.size()
		text(detail_sub, Rect2(26, 48, 1400, 28), 17, "muted", 600, "c", row)
		var un_b := btn("卸载移除", "trash", "danger", Rect2(1590, 17, 174, 56), func():
			var r := h.uninstall_package(String(pid))
			if bool(r.ok): toast("已从游戏卸载《%s》" % String(rec.get("title", pid)), "trash")
		, "c", -1.0, row, 19)
		un_b.name = "CwUninstall_" + String(pid).replace(".", "_")
		col.add_child(row)

# ================================================================ 发布作品（支持刻印工坊一键上传 + DLC 上传）
func _build_upload(h: WorkshopHub) -> void:
	var p := plate(Rect2(36, 118, 1848, 922), {"shape": "rect", "corner": "tr", "corner_size": 22}, "c", 0.05)
	header("发布作品到荧荧工坊（艾瑟拉世界板块）", Rect2(32, 20, 1100, 50), 30, "c", p)
	if not h.is_logged_in():
		text("需要登录后才可上传", Rect2(1240, 24, 340, 42), 20, "accent", 750, "c", p, HORIZONTAL_ALIGNMENT_RIGHT)
		var qb := btn("去 Discord 登录", "unlock", "primary", Rect2(1600, 18, 220, 52), func(): modal = "auth"; refresh(false), "c", -1.0, p, 19)
		qb.name = "CwUploadLoginBtn"

	var up_cats := [["blueprint", "刻印"], ["character", "角色DLC"], ["faction", "阵营"], ["event", "事件"], ["gameplay", "玩法"], ["rule", "规则"], ["other", "其他"]]
	var ux := 32.0
	for c_it in up_cats:
		var ck := String(c_it[0])
		var cb := btn(String(c_it[1]), "", "segment", Rect2(ux, 82, 146, 48), func(): upload_cat = ck; refresh(false), "c", -1.0, p, 19)
		cb.selected = upload_cat == ck; cb.center_text = true; cb.name = "CwUpCat_" + ck
		ux += 156.0

	text("作品标题", Rect2(32, 154, 180, 54), 23, "ink", 800, "c", p)
	var te_title := LineEdit.new(); te_title.name = "CwUpTitle"; te_title.text = upload_title; te_title.placeholder_text = "输入作品标题（刻印即魔法名）"
	put(te_title, Rect2(220, 154, 740, 54), "c", -1.0, p)
	te_title.text_changed.connect(func(v): upload_title = v)

	if upload_cat == "blueprint":
		text("魔法效果描述", Rect2(32, 228, 180, 54), 23, "ink", 800, "c", p)
		var te_desc := TextEdit.new(); te_desc.name = "CwUpSigilDesc"; te_desc.text = upload_desc; te_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te_desc.placeholder_text = "描述这道刻印魔法能做什么…"
		put(te_desc, Rect2(220, 228, 1580, 160), "c", -1.0, p)
		te_desc.text_changed.connect(func(): upload_desc = te_desc.text)

		var pack_box := plate(Rect2(32, 414, 1768, 290), {"shape": "rect", "fill": "surface2", "layered": false}, "c", -1.0, p)
		header("附带的刻印存档 (v3)", Rect2(24, 18, 600, 44), 24, "c", pack_box)
		var saved_arr: Array = upload_sigil_archive.get("saved", []) if upload_sigil_archive.get("saved") is Array else []
		if saved_arr.is_empty():
			text("尚未附带刻印图纸。你可以先去「刻印工坊」拼好一道魔法再点「上传工坊」，或点击右侧选择导出的 .json 存档。", Rect2(24, 78, 1280, 80), 20, "muted", 600, "c", pack_box)
		else:
			var s0: Dictionary = saved_arr[0]
			var summary_s := "魔法：%s\n载体：%s\n包含纹章：%d 枚\n效果：%s" % [
				String(s0.get("name", "未命名")), String(s0.get("carrier", "未指定")), s0.get("parts", []).size(), String(s0.get("effect", ""))
			]
			text(summary_s, Rect2(24, 78, 1280, 160), 21, "ink", 650, "c", pack_box)
		var pick_s := btn("选择 .json 存档文件", "upload", "secondary", Rect2(1420, 90, 310, 64), func(): _pick_sigil_json_for_upload(), "c", -1.0, pack_box, 20)
		pick_s.name = "CwPickSigilFileBtn"
		var back_ws := btn("去刻印工坊现拼一道", "seal", "chip", Rect2(1420, 170, 310, 60), func(): root.go("workshop"), "c", -1.0, pack_box, 19)
		back_ws.name = "CwUploadGoWorkshop"
	elif upload_cat == "character":
		text("角色真名 *", Rect2(32, 224, 180, 50), 22, "ink", 800, "c", p)
		var rn_e := LineEdit.new(); rn_e.name = "CwUpRoleName"; rn_e.text = upload_role_name; rn_e.placeholder_text = "例如：莉莉（不可与原卡 13 名主角重名）"
		put(rn_e, Rect2(220, 224, 520, 50), "c", -1.0, p); rn_e.text_changed.connect(func(v): upload_role_name = v)
		text("日常立绘 URL", Rect2(780, 224, 180, 50), 21, "ink", 700, "c", p)
		var d_u := LineEdit.new(); d_u.text = upload_role_daily_url; d_u.placeholder_text = "https://...（可选）"
		put(d_u, Rect2(960, 224, 840, 50), "c", -1.0, p); d_u.text_changed.connect(func(v): upload_role_daily_url = v)

		text("解放立绘 URL", Rect2(32, 290, 180, 50), 21, "ink", 700, "c", p)
		var f_u := LineEdit.new(); f_u.text = upload_role_form_url; f_u.placeholder_text = "https://...（可选）"
		put(f_u, Rect2(220, 290, 680, 50), "c", -1.0, p); f_u.text_changed.connect(func(v): upload_role_form_url = v)
		text("角色头像 URL", Rect2(940, 290, 180, 50), 21, "ink", 700, "c", p)
		var a_u := LineEdit.new(); a_u.text = upload_role_avatar_url; a_u.placeholder_text = "https://...（可选）"
		put(a_u, Rect2(1120, 290, 680, 50), "c", -1.0, p); a_u.text_changed.connect(func(v): upload_role_avatar_url = v)

		text("角色速览", Rect2(32, 360, 180, 44), 22, "ink", 800, "c", p)
		var ov_e := TextEdit.new(); ov_e.text = upload_role_overview; ov_e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; ov_e.placeholder_text = "角色简介、邂逅解锁条件、形态…"
		put(ov_e, Rect2(220, 360, 1580, 160), "c", -1.0, p); ov_e.text_changed.connect(func(): upload_role_overview = ov_e.text)

		text("角色档案", Rect2(32, 536, 180, 44), 22, "ink", 800, "c", p)
		var ar_e := TextEdit.new(); ar_e.text = upload_role_archive; ar_e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; ar_e.placeholder_text = "自由书写完整角色设定…"
		put(ar_e, Rect2(220, 536, 1580, 240), "c", -1.0, p); ar_e.text_changed.connect(func(): upload_role_archive = ar_e.text)
	else:
		text("封面图 URL", Rect2(990, 154, 150, 54), 21, "ink", 700, "c", p)
		var cv_e := LineEdit.new(); cv_e.text = upload_cover; cv_e.placeholder_text = "https://...（可选）"
		put(cv_e, Rect2(1150, 154, 650, 54), "c", -1.0, p); cv_e.text_changed.connect(func(v): upload_cover = v)
		var body_top := 228.0
		if upload_cat == "faction":
			text("阵营关键词", Rect2(32, 224, 180, 50), 22, "ink", 800, "c", p)
			var kw_e := LineEdit.new(); kw_e.text = upload_keywords; kw_e.placeholder_text = "多个关键词用逗号分隔（用于绿灯触发世界书）"
			put(kw_e, Rect2(220, 224, 1580, 50), "c", -1.0, p); kw_e.text_changed.connect(func(v): upload_keywords = v)
			body_top = 294.0
		elif upload_cat == "event":
			text("事件标识名", Rect2(32, 224, 180, 50), 22, "ink", 800, "c", p)
			var en_e := LineEdit.new(); en_e.text = upload_event_names; en_e.placeholder_text = "事件 ID 或名称（留空则用作品标题）"
			put(en_e, Rect2(220, 224, 680, 50), "c", -1.0, p); en_e.text_changed.connect(func(v): upload_event_names = v)
			text("绑定角色名", Rect2(940, 224, 180, 50), 22, "ink", 800, "c", p)
			var er_e := LineEdit.new(); er_e.text = upload_event_roles; er_e.placeholder_text = "触发该事件需要关联的角色名（可选）"
			put(er_e, Rect2(1120, 224, 680, 50), "c", -1.0, p); er_e.text_changed.connect(func(v): upload_event_roles = v)
			body_top = 294.0
		text("正文内容", Rect2(32, body_top, 180, 50), 22, "ink", 800, "c", p)
		var bd_e := TextEdit.new(); bd_e.text = upload_body; bd_e.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; bd_e.placeholder_text = "输入世界书词条正文…"
		put(bd_e, Rect2(220, body_top, 1580, 770.0 - body_top), "c", -1.0, p); bd_e.text_changed.connect(func(): upload_body = bd_e.text)

	var sub_b := btn("发布到荧荧工坊", "cloud", "primary", Rect2(1420, 814, 380, 74), func(): _submit_upload(), "c", -1.0, p, 24)
	sub_b.name = "CwPublishBtn"

func _pick_sigil_json_for_upload() -> void:
	if OS.has_feature("web"): toast("网页预览暂不支持选本地文件", "info"); return
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE; fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json ; 刻印工坊存档 v3"]); fd.use_native_dialog = true; add_child(fd)
	fd.file_selected.connect(func(path: String):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and String(d.get("format", "")) == "academy-sigil-archive" and int(d.get("version", 0)) == 3 and d.get("saved") is Array and not d.saved.is_empty():
			upload_sigil_archive = d
			if upload_title == "": upload_title = String(d.saved[0].get("name", ""))
			if upload_desc == "": upload_desc = String(d.saved[0].get("effect", ""))
			toast("已载入刻印存档：%d 道魔法" % d.saved.size(), "check")
		else:
			toast("请选择刻印工坊导出的 v3 存档文件", "warn")
		fd.queue_free(); refresh(false)
	)
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(900, 600))

func _submit_upload() -> void:
	if not hub().is_logged_in():
		toast("发布作品需要先登录 Discord 账号", "lock"); modal = "auth"; refresh(false); return
	var t := upload_title.strip_edges()
	if t == "": toast("请先填写作品标题", "warn"); return
	var body := {"category": upload_cat, "type": upload_cat, "title": t, "imageUrl": upload_cover.strip_edges(), "payload": {"extra": {}}}
	var extra: Dictionary = body.payload.extra
	if upload_cat == "blueprint":
		if upload_sigil_archive.is_empty() or not (upload_sigil_archive.get("saved") is Array) or upload_sigil_archive.saved.is_empty():
			toast("请先附带一道刻印存档再发布", "warn"); return
		extra["desc"] = upload_desc.strip_edges()
		extra["sigilArchive"] = upload_sigil_archive
	elif upload_cat == "character":
		var rn := upload_role_name.strip_edges()
		if rn == "": toast("请先填写角色真名（控制器）", "warn"); return
		extra["roleNames"] = [rn]
		extra["overview"] = upload_role_overview.strip_edges()
		extra["archive"] = upload_role_archive.strip_edges()
		extra["summary"] = "\n".join(PackedStringArray([extra.overview, extra.archive].filter(func(s): return s != "")))
		if upload_role_daily_url.strip_edges() != "": extra["imageDailyUrl"] = upload_role_daily_url.strip_edges()
		if upload_role_form_url.strip_edges() != "": extra["imageFormUrl"] = upload_role_form_url.strip_edges()
		if upload_role_avatar_url.strip_edges() != "": extra["imageAvatarUrl"] = upload_role_avatar_url.strip_edges()
		body["imageUrl"] = String(extra.get("imageDailyUrl", extra.get("imageFormUrl", "")))
	elif upload_cat == "faction":
		var kws: Array = []
		for p in upload_keywords.replace("，", ",").split(",", false):
			var k := String(p).strip_edges()
			if k != "": kws.append(k)
		extra["keywords"] = kws
		extra["content"] = upload_body.strip_edges()
	elif upload_cat == "event":
		extra["eventNames"] = [upload_event_names.strip_edges() if upload_event_names.strip_edges() != "" else t]
		extra["roleNames"] = [upload_event_roles.strip_edges()] if upload_event_roles.strip_edges() != "" else []
		extra["content"] = upload_body.strip_edges()
	else:
		extra["content"] = upload_body.strip_edges()

	hub().publish_package(body, func(ok_p: bool, _created: Dictionary, err: String):
		if ok_p:
			UiHub.sfx("confirm")
			toast("发布成功！《%s》已上线荧荧工坊" % t, "cloud")
			tab = "browse"; cat_filter = upload_cat
			refresh(false)
		else:
			UiHub.sfx("deny")
			toast("发布失败：" + err, "warn")
	)

# ================================================================ 登录弹窗（浏览器回环 OAuth + 手动令牌兜底）
func _build_auth_modal(h: WorkshopHub) -> void:
	var shade := ColorRect.new(); shade.name = "CwAuthShade"; shade.color = UiHub.c("shade"); shade.mouse_filter = Control.MOUSE_FILTER_STOP
	put(shade, Rect2(Vector2.ZERO, size), "c")
	shade.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: modal = ""; refresh(false))

	var box := plate(Rect2(450, 210, 1020, 620), {"shape": "cut", "slant": 36, "corner": "tr", "hatch": true}, "c", -1.0)
	box.name = "CwAuthModal"; box.mouse_filter = Control.MOUSE_FILTER_STOP
	header("荧荧工坊账号连接（Discord）", Rect2(42, 26, 860, 52), 32, "c", box)
	var cls := btn("", "close", "icon", Rect2(928, 22, 64, 64), func(): modal = ""; refresh(false), "c", -1.0, box)
	cls.name = "CwAuthClose"

	if h.is_logged_in():
		text("当前已登录：%s（ID: %s）%s" % [h.display_name(), String(h.user.get("id", "")), " · 管理员" if h.is_admin else ""], Rect2(46, 110, 928, 44), 24, "accent", 850, "c", box)
		text("当前网关：" + h.gateway, Rect2(46, 160, 928, 36), 18, "muted", 600, "c", box)
		var out_b := btn("退出登录（注销本机与云端会话）", "power", "danger", Rect2(46, 486, 420, 74), func():
			h.logout(); modal = ""; toast("已退出登录", "info"); refresh(false)
		, "c", -1.0, box, 21)
		out_b.name = "CwModalLogout"
		var done_b := btn("完成", "check", "primary", Rect2(740, 486, 234, 74), func(): modal = ""; refresh(false), "c", -1.0, box, 22)
		done_b.name = "CwModalDone"
	else:
		var explain := "点击下方「一键浏览器 Discord 登录」将在系统默认浏览器中打开授权页面；完成授权后页面会自动将登录凭据传回游戏并同步你的「我的仓库」云端下载清单。\n\n如果不便跳转，也可直接在网页工坊导出 .json 后在管理面板免登录导入，或在下方粘贴浏览器里的 hwToken 令牌。"
		var ex_l := text(explain, Rect2(46, 98, 928, 128), 19, "muted", 600, "c", box)
		ex_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		var oa_b := btn("一键浏览器 Discord 登录", "unlock", "primary", Rect2(46, 240, 440, 72), func():
			h.begin_discord_login()
		, "c", -1.0, box, 22)
		oa_b.name = "CwAuthOAuthBtn"
		var wb_b := btn("先在浏览器打开网页工坊", "globe", "secondary", Rect2(506, 240, 468, 72), func():
			OS.shell_open(h.gateway + "/?scope=aethera")
		, "c", -1.0, box, 21)
		wb_b.name = "CwAuthOpenWeb"
		if _oauth_msg != "":
			text(_oauth_msg, Rect2(46, 322, 928, 34), 17, "accent", 700, "c", box)

		text("备用 · 手动粘贴会话令牌（hwToken）", Rect2(46, 376, 928, 34), 20, "ink", 750, "c", box)
		var tk_e := LineEdit.new(); tk_e.name = "CwTokenInput"; tk_e.secret = true; tk_e.text = _token_draft; tk_e.placeholder_text = "粘贴来自 workshop.hotaruworkshop.l.cd 的 hwToken…"
		put(tk_e, Rect2(46, 418, 700, 56), "c", -1.0, box); tk_e.text_changed.connect(func(v): _token_draft = v)
		var tk_ok := btn("验证并绑定", "check", "secondary", Rect2(760, 418, 214, 56), func():
			h.set_manual_token(tk_e.text, func(ok_t: bool, err: String):
				if ok_t:
					toast("令牌验证成功 · " + h.display_name(), "check")
					_token_draft = ""; modal = ""; refresh(false)
				else:
					toast("验证失败：" + err, "warn")
			)
		, "c", -1.0, box, 20)
		tk_ok.name = "CwTokenSubmitBtn"

		var cancel_b := btn("关闭", "close", "ghost", Rect2(46, 514, 180, 62), func():
			h.cancel_login(); modal = ""; refresh(false)
		, "c", -1.0, box, 20)
		cancel_b.name = "CwAuthCancelBtn"

func on_back() -> bool:
	if modal != "":
		hub().cancel_login()
		modal = ""; refresh(false); return true
	return false
