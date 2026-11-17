extends "res://scripts/ui/ui_screen.gd"
## 预设条目管理：展示当前预设的所有条目，支持搜索/筛选、单独开启或关闭、修改条目正文、还原默认或导入预设。

const PER_PAGE := 9

var query := ""
var filter_mode := "all" # all | enabled | disabled | modified
var page := 0
var picked_id := ""
var draft_content := ""
var _draft_for_id := ""

func build() -> void:
	chrome("预设条目管理")
	decor(73, Rect2(Vector2.ZERO, size), 0.5)
	if not Game.changed.is_connected(_on_game): Game.changed.connect(_on_game)

	var all_entries: Array = Game.preset_entries()
	var preset_name := "【Hotaru预设】v1.0"
	if not Game.presets.is_empty() and Game.presets[0] is Dictionary:
		preset_name = String(Game.presets[0].get("name", preset_name))

	var en_cnt := 0
	var mod_cnt := 0
	for e in all_entries:
		if bool(e.get("enabled", false)): en_cnt += 1
		if bool(e.get("modified", false)): mod_cnt += 1

	# 顶部信息条
	text("%s · %d/%d 启用" % [preset_name.get_slice("（", 0), en_cnt, all_entries.size()], Rect2(470, 42, 620, 44), 20, "muted", 700, "lt")
	var imp_b := btn("导入预设", "download", "chip", Rect2(1136, 34, 174, 62), func(): _pick_preset_file(), "rt", -1.0, null, 19)
	imp_b.name = "PresetImportBtn"
	var reset_all_b := btn("全部还原", "refresh", "secondary", Rect2(1320, 34, 178, 62), func():
		Game.reset_preset_overrides()
		_draft_for_id = ""
		refresh(false)
	, "rt", -1.0, null, 19)
	reset_all_b.name = "PresetResetAllBtn"
	reset_all_b.disabled = mod_cnt <= 0

	# 筛选与检索栏（左侧面板）
	var lp := plate(Rect2(34, 126, 650, 910), {"shape": "rect", "corner": "tr", "corner_size": 20}, "l", 0.05)
	var search := LineEdit.new(); search.name = "PresetSearch"; search.placeholder_text = "搜索预设条目名称、ID 或正文（回车）"; search.text = query
	put(search, Rect2(20, 20, 470, 50), "c", -1.0, lp)
	search.text_submitted.connect(func(t): query = t; page = 0; refresh(false))
	btn("查找", "", "secondary", Rect2(500, 20, 72, 50), func(): query = search.text; page = 0; refresh(false), "c", -1.0, lp, 18)
	btn("清空", "", "ghost", Rect2(578, 20, 56, 50), func(): query = ""; page = 0; refresh(false), "c", -1.0, lp, 17)

	var filters := [["all", "全部"], ["enabled", "已启用"], ["disabled", "已关闭"], ["modified", "已修改"]]
	for k in range(filters.size()):
		var fspec: Array = filters[k]
		var fk: String = fspec[0]
		var fb := btn(fspec[1], "", "segment", Rect2(20 + k * 154, 82, 146, 44), func():
			if filter_mode != fk:
				filter_mode = fk; page = 0; refresh(false)
		, "c", -1.0, lp, 17)
		fb.center_text = true; fb.selected = filter_mode == fk; fb.name = "PresetFilter_" + fk

	var q := query.strip_edges().to_lower()
	var filtered: Array = []
	for e in all_entries:
		var en := bool(e.get("enabled", false))
		var is_mod := bool(e.get("modified", false))
		if filter_mode == "enabled" and not en: continue
		if filter_mode == "disabled" and en: continue
		if filter_mode == "modified" and not is_mod: continue
		if q != "":
			var hay := (String(e.get("name", "")) + " " + String(e.get("identifier", "")) + " " + String(e.get("content", ""))).to_lower()
			if not hay.contains(q): continue
		filtered.append(e)

	var pages := maxi(1, ceili(float(filtered.size()) / float(PER_PAGE)))
	page = clampi(page, 0, pages - 1)

	var picked_entry: Dictionary = {}
	if picked_id != "":
		for e in filtered:
			if String(e.get("identifier", "")) == picked_id:
				picked_entry = e; break
	if picked_entry.is_empty() and not filtered.is_empty():
		var first_on_page := mini(page * PER_PAGE, filtered.size() - 1)
		picked_entry = filtered[first_on_page]
		picked_id = String(picked_entry.get("identifier", ""))
	elif not picked_entry.is_empty():
		var idx_found := filtered.find(picked_entry)
		if idx_found >= 0:
			page = idx_found / PER_PAGE

	if filtered.is_empty():
		text("没有匹配的预设条目。", Rect2(30, 180, 590, 60), 22, "muted", 700, "c", lp, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		var lo := page * PER_PAGE
		var hi := mini(filtered.size(), lo + PER_PAGE)
		for idx in range(lo, hi):
			var row_i := idx - lo
			var e: Dictionary = filtered[idx]
			var pid := String(e.get("identifier", ""))
			var en := bool(e.get("enabled", false))
			var is_mod := bool(e.get("modified", false))
			var is_marker := bool(e.get("marker", false))
			var prefix := "[锚点] " if is_marker else ("[开] " if en else "[关] ")
			var suffix := " · 已改" if is_mod else ""
			var label := prefix + String(e.get("name", pid))
			if label.length() > 21: label = label.substr(0, 20) + "…"
			label += suffix
			var rb := btn(label, "", "row", Rect2(20, 140 + row_i * 76, 610, 66), func():
				picked_id = pid
				_draft_for_id = ""
				refresh(false)
			, "c", -1.0, lp, 18)
			rb.selected = pid == picked_id
			rb.divider = false
			rb.name = "PresetRow_" + str(row_i)

	var prev_b := btn("上一页", "back", "ghost", Rect2(20, 836, 170, 54), func():
		page = maxi(0, page - 1); picked_id = ""; _draft_for_id = ""; refresh(false)
	, "c", -1.0, lp, 18)
	prev_b.name = "PresetPrev"; prev_b.disabled = page <= 0
	text("%d / %d 页（%d 条）" % [page + 1, pages, filtered.size()], Rect2(200, 842, 240, 42), 18, "muted", 700, "c", lp, HORIZONTAL_ALIGNMENT_CENTER)
	var next_b := btn("下一页", "next", "ghost", Rect2(458, 836, 170, 54), func():
		page = mini(pages - 1, page + 1); picked_id = ""; _draft_for_id = ""; refresh(false)
	, "c", -1.0, lp, 18)
	next_b.name = "PresetNext"; next_b.disabled = page >= pages - 1

	# 右侧条目详情与编辑面板
	var rp := plate(Rect2(704, 126, 1182, 910), {"shape": "cut", "slant": 36, "corner": "tr", "hatch": true}, "c", 0.08)
	if picked_entry.is_empty():
		text("请在左侧选择一条预设条目查看或编辑。", Rect2(60, 80, 800, 60), 26, "muted", 700, "c", rp)
		return

	var eid := String(picked_entry.get("identifier", ""))
	var ename := String(picked_entry.get("name", eid))
	var erole := String(picked_entry.get("role", "system"))
	var enabled_now := bool(picked_entry.get("enabled", false))
	var def_en := bool(picked_entry.get("default_enabled", false))
	var is_marker := bool(picked_entry.get("marker", false))
	var mod_now := bool(picked_entry.get("modified", false))

	if _draft_for_id != eid:
		_draft_for_id = eid
		draft_content = String(picked_entry.get("content", ""))

	header(ename, Rect2(32, 20, 760, 56), 28, "c", rp)
	var toggle_b := btn("状态：已开启（点此关闭）" if enabled_now else "状态：已关闭（点此开启）", "toggle_on" if enabled_now else "toggle_off", "primary" if enabled_now else "secondary", Rect2(812, 20, 336, 58), func():
		Game.set_preset_entry(eid, {"enabled": not enabled_now})
		UiHub.sfx("toggle")
	, "c", -1.0, rp, 19)
	toggle_b.name = "PresetToggleBtn"
	toggle_b.disabled = is_marker

	var meta_s := "ID: %s  ·  角色: %s  ·  默认: %s%s" % [eid, erole, "开启" if def_en else "关闭", "  ·  [已自定义]" if mod_now else ""]
	text(meta_s, Rect2(34, 82, 1110, 34), 18, "accent" if mod_now else "muted", 650, "c", rp)

	if is_marker:
		var mnote := plate(Rect2(34, 134, 1114, 180), {"shape": "rect", "fill": "surface2", "layered": false}, "c", -1.0, rp)
		var ml := text("此条目为预设结构占位锚点（例如世界书前后插入位 / 玩家与角色档案注入位置），本身不包含可编辑正文。\n其余所有规则、文风、语言、联机约束条目均可自由开启、关闭与修改正文。", Rect2(30, 30, 1054, 120), 21, "ink", 600, "c", mnote)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return

	var te := TextEdit.new(); te.name = "PresetContentEdit"
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.placeholder_text = "此条目当前无文本内容，可在此编写自定义提示词规则…"
	te.text = draft_content
	te.caret_blink = true
	te.text_changed.connect(func(): draft_content = te.text)
	put(te, Rect2(34, 128, 1114, 676), "c", -1.0, rp)

	var hint_s := "正文共有 %d 字；修改保存后会立即用于主线剧情与私聊请求拼装。" % draft_content.length()
	text(hint_s, Rect2(34, 824, 580, 62), 18, "muted", 600, "c", rp)

	var reset_one_b := btn("还原此条默认", "refresh", "secondary", Rect2(640, 822, 236, 64), func():
		Game.set_preset_entry(eid, {"reset": true})
		_draft_for_id = ""
		UiHub.sfx("reset")
		refresh(false)
	, "c", -1.0, rp, 20)
	reset_one_b.name = "PresetResetOneBtn"
	reset_one_b.disabled = not mod_now

	var save_b := btn("保存正文修改", "save", "primary", Rect2(892, 822, 256, 64), func():
		var final_txt := te.text if is_instance_valid(te) else draft_content
		Game.set_preset_entry(eid, {"content": final_txt})
		UiHub.sfx("save")
	, "c", -1.0, rp, 21)
	save_b.name = "PresetSaveBtn"

func _on_game(part: String) -> void:
	if part == "presets":
		refresh(false)

func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game): Game.changed.disconnect(_on_game)

func _pick_preset_file() -> void:
	if OS.has_feature("web") and not Game.demo: return
	if OS.has_feature("web"): toast("网页版暂不支持选择本地文件，请用电脑版", "info"); return
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE; fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json ; JSON 预设文件"]); fd.use_native_dialog = true
	add_child(fd)
	fd.file_selected.connect(func(path): Game.import_preset(path); _draft_for_id = ""; fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(900, 600))
