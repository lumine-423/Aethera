extends "res://scripts/ui/ui_screen.gd"
## 刻印工坊 (concept 22/23/24/42). Port of the live card's workshop (sigil-workbench.html):
## the same 22 patterns (data/workshop/patterns.json, extracted, not redrawn by hand), the same
## port geometry (SCALE 1.45, link gap 38 / 52 core-core, attachedWorld / defaultPlug), the same
## blueprint text (describeCircuit: 刻印 / 载体 / 纹章 with 接口N-① 枝位 / 耗用 / 玩家编写效果) and
## the same cost rule (sum of costs minus same-nature sync). Drafts and saved sigils are stored in
## user://workshop.json in the card's draft shape {name, carrier, effect, parts[]} so exports stay
## interchangeable. The UI never decides an effect: 激活 only sends the blueprint text.

const STORE := "user://workshop.json"
const ActFx = preload("res://scripts/ui/workshop_activation_fx.gd")
const KIND_FULL := {"core": "核纹", "outer": "外纹", "micro": "缀纹"}
const CN := ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
const CIRC := ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩", "⑪", "⑫", "⑬", "⑭", "⑮"]
const NATURE_TONE := {"空间": "9f8cf0", "静止": "5fd8d0", "运动": "e06450", "生命": "9ac47a", "力场": "d8a84e", "构建": "c98f3d", "输出": "f0e3a0", "特殊": "ff5fa2"}

static var catalog: Dictionary = {}
var draft := {"name": "", "carrier": "", "effect": "", "parts": []}
var saved: Array = []
var loaded := false
var tab := "palette"        # palette | saved
var kind_tab := "core"
var selected_id := ""
var zoom := 0.92
var cam := Vector2(590, 330)
var canvas: Control
var name_edit: LineEdit
var carrier_edit: LineEdit
var effect_edit: TextEdit
var zoom_label: Label
var overlay := ""           # "" | codex | result | share
var result_text := ""
var codex_kind := "core"
var burning := 0.0
var _id_seq := 0

func _init() -> void:
	uses_backdrop = true

static func cat() -> Dictionary:
	if catalog.is_empty():
		catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/workshop/patterns.json"))
	return catalog

static func defp(pid: String) -> Dictionary:
	return cat().patterns.get(pid, {})

func build() -> void:
	if not loaded: _load(); loaded = true
	chrome("刻印工坊")
	# top-right tools: creative workshop, upload sigil, zoom pill, blueprint menu
	var cw := btn("创意工坊", "globe", "secondary", Rect2(524, 30, 198, 70), func():
		_persist()
		root.go("creative_workshop", {"tab": "browse", "cat": "blueprint"})
	, "rt", -1.0, null, 21)
	cw.name = "SigilCreativeWorkshop"
	cw.tooltip_text = "打开艾瑟拉创意工坊与管理面板（下载 / 导入他人刻印图纸）"
	var up := btn("上传工坊", "cloud", "chip", Rect2(734, 30, 164, 70), func():
		_open_workshop_upload()
	, "rt", -1.0, null, 21)
	up.name = "SigilUploadWorkshop"
	up.tooltip_text = "将当前绘制的刻印直接上传到荧荧工坊（艾瑟拉板块）"
	var zp := plate(Rect2(912, 30, 256, 70), {"shape": "pill", "detail": false, "layered": false, "bead": false}, "rt")
	var zo := btn("", "minus", "ghost", Rect2(12, 8, 52, 54), func(): _zoom(zoom / 1.2), "c", -1.0, zp)
	zo.name = "ZoomOut"
	zoom_label = text("%d%%" % int(round(zoom / 0.92 * 100.0)), Rect2(68, 0, 120, 70), 23, "ink", 500, "c", zp, HORIZONTAL_ALIGNMENT_CENTER)
	var zi := btn("", "plus", "ghost", Rect2(192, 8, 52, 54), func(): _zoom(zoom * 1.2), "c", -1.0, zp)
	zi.name = "ZoomIn"
	var bp := btn(draft.name if draft.name != "" else "空白图纸", "doc", "chip", Rect2(1182, 30, 318, 70), func(): _new_blank(), "rt", -1.0, null, 24)
	bp.name = "Blueprint"; bp.tooltip_text = "新建空白图纸（当前草稿自动保留在已保存里）"
	_left_panel()
	_right_panel()
	_bottom_bar()
	canvas = Canvas.new(); canvas.screen = self; canvas.name = "Canvas"
	put(canvas, Rect2(380, 128, 1150, 690), "c")
	move_child(canvas, 0)
	match overlay:
		"codex": _codex_overlay()
		"result": _result_overlay()
		"share": _share_overlay()

# ---------------------------------------------------------------- left: 图案图鉴 / 已保存
func _left_panel() -> void:
	var p := plate(Rect2(30, 128, 330, 690), {"slant": 30, "corner": ""}, "l", 0.0)
	var t1 := btn("图案图鉴", "", "tab", Rect2(18, 22, 150, 60), func(): tab = "palette"; refresh(), "c", -1.0, p, 24)
	t1.selected = tab == "palette"; t1.center_text = true
	var t2 := btn("已保存 %d" % saved.size(), "", "tab", Rect2(172, 22, 140, 60), func(): tab = "saved"; refresh(), "c", -1.0, p, 24)
	t2.selected = tab == "saved"; t2.center_text = true
	if tab == "saved":
		_saved_list(p); return
	var y := 100.0
	for k in ["core", "outer", "micro"]:
		var kb := btn(KIND_FULL[k], {"core": "diamond", "outer": "moon", "micro": "star4"}[k], "row", Rect2(14, y, 302, 62), func(): kind_tab = k; refresh(), "c", -1.0, p, 26)
		kb.selected = kind_tab == k; kb.name = "Kind_" + k
		y += 70
	# pattern grid for the open kind
	var ids: Array = []
	for id in cat().order:
		if defp(id).kind == kind_tab: ids.append(id)
	var cols := 3; var cw := 98.0; var ch := 94.0
	for i in range(ids.size()):
		var id: String = ids[i]
		var cell := PatternChip.new(); cell.screen = self; cell.pid = id; cell.name = "Pat_" + id.replace(".", "_")
		cell.tooltip_text = defp(id).name + "\n" + defp(id).desc
		put(cell, Rect2(14 + (i % cols) * (cw + 4), y + 10 + floorf(i / float(cols)) * (ch + 4), cw, ch), "c", -1.0, p)
	text("拖到空接点即连接；单击接到选中纹章。", Rect2(18, 636, 300, 40), 15, "muted", 500, "c", p)

func _saved_list(p: Control) -> void:
	if saved.is_empty():
		text("还没有保存的刻印。拼好之后点「保存」或「激活」，也可从创意工坊导入他人魔法。", Rect2(24, 120, 280, 140), 19, "muted", 500, "c", p)
	else:
		var y := 100.0
		for i in range(mini(saved.size(), 7)):
			var s: Dictionary = saved[i]
			var cost := _cost_of(s.parts)
			var b := btn(str(s.get("name", "未命名")) if str(s.get("name", "")) != "" else "未命名", "seal", "row", Rect2(14, y, 302, 64), func(): _open_saved(i), "c", -1.0, p, 22)
			b.sub = "%d 枚纹章 · 耗用 %d" % [s.parts.size(), cost]; b.name = "Saved%d" % i
			y += 70
	var ws_repo := btn("工坊管理面板", "globe", "secondary", Rect2(14, 552, 302, 56), func():
		_persist()
		root.go("creative_workshop", {"tab": "repo"})
	, "c", -1.0, p, 20)
	ws_repo.name = "SavedWorkshopRepo"
	var ex := btn("分享与本地导入", "upload", "chip", Rect2(14, 618, 302, 56), func(): overlay = "share"; refresh(), "c", -1.0, p, 20)
	ex.name = "Share"

# ---------------------------------------------------------------- right: 选中部件 / 部件检查
func _right_panel() -> void:
	var p := plate(Rect2(1550, 128, 340, 690), {"slant": 30}, "r", 0.05)
	header("选中部件", Rect2(20, 18, 300, 50), 26, "c", p)
	var node := _node(selected_id)
	if node.is_empty():
		text("点画布上的纹章查看与调整。", Rect2(24, 80, 290, 70), 20, "muted", 500, "c", p)
	else:
		var d := defp(node.partId)
		var g := GlyphView.new(); g.pid = node.partId; g.screen = self
		put(g, Rect2(24, 76, 110, 110), "c", -1.0, p)
		text(KIND_FULL[d.kind] + "·" + str(d.shorthand), Rect2(146, 82, 180, 50), 28, "ink", 600, "c", p)
		text(str(d.nature) + " · 耗用 " + str(int(d.cost)), Rect2(146, 132, 180, 36), 18, "muted", 500, "c", p)
		var y := 206.0
		icon("refresh", Rect2(24, y + 10, 34, 34), "ink", "c", p)
		text("旋转", Rect2(70, y, 90, 54), 22, "ink", 500, "c", p)
		var rl := btn("", "back", "ghost", Rect2(170, y + 4, 46, 46), func(): _rotate(-15), "c", -1.0, p)
		rl.name = "RotL"
		text("%d°" % int(node.get("rot", 0)), Rect2(216, y, 70, 54), 22, "ink", 500, "c", p, HORIZONTAL_ALIGNMENT_CENTER)
		var rr := btn("", "next", "ghost", Rect2(282, y + 4, 46, 46), func(): _rotate(15), "c", -1.0, p)
		rr.name = "RotR"
		y += 62
		icon("link", Rect2(24, y + 10, 34, 34), "ink", "c", p)
		var att := str(node.get("parent", "")) != "" and not _node(str(node.parent)).is_empty()
		text("连接", Rect2(70, y, 90, 54), 22, "ink", 500, "c", p)
		text(_attach_text(node) if att else "未连接", Rect2(150, y, 180, 54), 18, "accent" if att else "muted", 500, "c", p)
		y += 62
		if att:
			var dt := btn("断开", "unlink", "chip", Rect2(24, y, 140, 54), func(): _detach(selected_id), "c", -1.0, p, 20)
			dt.name = "Detach"
		var rm := btn("拆除", "close", "chip", Rect2(176 if att else 24, y, 140, 54), func(): _remove(selected_id, false), "c", -1.0, p, 20)
		rm.name = "Remove"
		y += 62
		if not _children(selected_id).is_empty():
			var rs := btn("连同子纹拆除", "close", "chip", Rect2(24, y, 292, 54), func(): _remove(selected_id, true), "c", -1.0, p, 20)
			rs.name = "RemoveTree"
	header("部件检查", Rect2(20, 470, 300, 50), 26, "c", p)
	var cores := 0; var loose := 0
	for q in draft.parts:
		if defp(q.partId).kind == "core": cores += 1
		elif not _in_circuit(q): loose += 1
	var checks := [["连接正常" if loose == 0 else "%d 枚散件未接入" % loose, loose == 0], ["结构完整" if cores > 0 else "缺少核纹", cores > 0]]
	for i in range(checks.size()):
		var ok: bool = checks[i][1]
		icon("check" if ok else "warn", Rect2(24, 536 + i * 56, 34, 34), "accent" if ok else "muted", "c", p)
		text(checks[i][0], Rect2(70, 528 + i * 56, 250, 50), 21, "ink" if ok else "muted", 500, "c", p)
	var cd := btn("纹章图鉴", "book", "chip", Rect2(24, 632, 292, 50), func(): overlay = "codex"; refresh(), "c", -1.0, p, 20)
	cd.name = "Codex"

func _attach_text(node: Dictionary) -> String:
	var br := _branch(node)
	if br.is_empty(): return "已连接"
	return "接口%d-%s" % [br.port, CIRC[clampi(br.depth - 1, 0, CIRC.size() - 1)]]

# ---------------------------------------------------------------- bottom: 名称 / 载体 / 效果 / 激活 保存
func _bottom_bar() -> void:
	var p := plate(Rect2(30, 840, 1860, 214), {"slant": 50}, "b", 0.08)
	text("刻印名称", Rect2(70, 18, 300, 40), 22, "muted", 500, "c", p)
	name_edit = LineEdit.new(); name_edit.name = "MagicName"; name_edit.max_length = 60
	name_edit.placeholder_text = "给这道魔法起个名字…"; name_edit.text = draft.name
	put(name_edit, Rect2(62, 64, 330, 70), "c", -1.0, p)
	name_edit.text_changed.connect(func(t): draft.name = t; _persist())
	text("载体", Rect2(430, 18, 200, 40), 22, "muted", 500, "c", p)
	carrier_edit = LineEdit.new(); carrier_edit.name = "Carrier"; carrier_edit.max_length = 40
	carrier_edit.placeholder_text = "刻在什么物品上？例：戒指内环"; carrier_edit.text = draft.carrier
	put(carrier_edit, Rect2(422, 64, 330, 70), "c", -1.0, p)
	carrier_edit.text_changed.connect(func(t): draft.carrier = t; _persist())
	text("效果", Rect2(790, 18, 200, 40), 22, "muted", 500, "c", p)
	effect_edit = TextEdit.new(); effect_edit.name = "Effect"; effect_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	effect_edit.placeholder_text = "你想让这道魔法做什么？例：戒指内环烧起一圈不灭的冷火，见血就自己亮起来"; effect_edit.text = draft.effect
	put(effect_edit, Rect2(782, 58, 620, 120), "c", -1.0, p)
	effect_edit.text_changed.connect(func(): draft.effect = effect_edit.text.substr(0, 240); _persist())
	var cost := _cost_of(draft.parts)
	text("%d 枚纹章 · 耗用 %d" % [draft.parts.size(), cost], Rect2(790, 176, 600, 32), 17, "muted", 500, "c", p)
	var act := btn("激活", "play", "primary", Rect2(1404, 40, 220, 96), func(): _activate(), "c", -1.0, p, 30)
	act.name = "Activate"; act.press_sfx = "none"; act.disabled = draft.parts.is_empty()
	var sv := btn("保存", "save", "secondary", Rect2(1636, 40, 214, 96), func(): _save(true), "c", -1.0, p, 30)
	sv.name = "Save"; sv.disabled = draft.parts.is_empty()

# ---------------------------------------------------------------- overlays
func _overlay_frame(title: String, w := 1300.0, h := 760.0) -> Control:
	var shade := ColorRect.new(); shade.color = UiHub.c("shade"); shade.mouse_filter = Control.MOUSE_FILTER_STOP
	put(shade, Rect2(0, 0, 1920, 1080), "c")
	shade.position = Vector2.ZERO; shade.size = size
	shade.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: overlay = ""; refresh())
	var p := plate(Rect2((1920 - w) * 0.5, (1080 - h) * 0.5, w, h), {"slant": 60, "corner": "tr"}, "c")
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	header(title, Rect2(40, 26, w - 160, 60), 34, "c", p)
	var x := btn("", "close", "icon", Rect2(w - 100, 24, 64, 64), func(): overlay = ""; refresh(), "c", -1.0, p)
	x.name = "OverlayClose"
	Kit.pop(p, 0.0, 0.3)
	return p

func _codex_overlay() -> void:
	var p := _overlay_frame("纹章图鉴")
	var x := 40.0
	for k in ["core", "outer", "micro"]:
		var b := btn(KIND_FULL[k], "", "tab", Rect2(x, 100, 150, 58), func(): codex_kind = k; refresh(), "c", -1.0, p, 24)
		b.selected = codex_kind == k; b.center_text = true; x += 160
	text("纹章只描述形状。效果由世界书的纹章辞典和你的载体、你写的效果一起决定。", Rect2(540, 100, 720, 58), 18, "muted", 500, "c", p)
	var ids: Array = []
	for id in cat().order:
		if defp(id).kind == codex_kind: ids.append(id)
	for i in range(ids.size()):
		var d := defp(ids[i])
		var col := i % 2; var row := floori(i / 2.0)
		var r := Rect2(40 + col * 615, 178 + row * 140, 600, 128)
		var cell := plate(r, {"slant": 20, "layered": false, "detail": false}, "c", -1.0, p)
		var g := GlyphView.new(); g.pid = ids[i]; g.screen = self
		put(g, Rect2(14, 10, 108, 108), "c", -1.0, cell)
		text(str(d.name), Rect2(136, 8, 450, 44), 24, "ink", 600, "c", cell)
		text(str(d.nature) + " · 耗用 " + str(int(d.cost)) + " · " + ("接口 %d" % d.slots.size()), Rect2(136, 48, 450, 30), 17, "accent", 500, "c", cell)
		text(str(d.desc), Rect2(136, 76, 450, 48), 16, "muted", 500, "c", cell)

func _result_overlay() -> void:
	var p := _overlay_frame("刻印激活", 1200, 780)
	var g := Sigil.new(); g.screen = self
	put(g, Rect2(40, 110, 420, 420), "c", -1.0, p)
	text(draft.name if draft.name != "" else "未命名刻印", Rect2(40, 540, 420, 60), 34, "ink", 600, "c", p, HORIZONTAL_ALIGNMENT_CENTER)
	text("已自动保存 · 图纸说明已发往行动框", Rect2(40, 600, 420, 40), 18, "accent", 500, "c", p, HORIZONTAL_ALIGNMENT_CENTER)
	var body := Lbl.new(); body.setup(result_text, 21, "ink", 500)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	put(body, Rect2(500, 120, 660, 520), "c", -1.0, p)
	var ok := btn("收下", "check", "primary", Rect2(780, 664, 380, 84), func(): UiHub.stop_workshop_activation(true); overlay = ""; refresh(), "c", -1.0, p, 28)
	ok.name = "ResultOk"; ok.center_text = true
	var cp := btn("复制图纸", "doc", "secondary", Rect2(500, 664, 260, 84), func(): DisplayServer.clipboard_set(result_text); toast("已复制到剪贴板", "doc"), "c", -1.0, p, 24)
	cp.name = "CopyBlueprint"

func _share_overlay() -> void:
	var p := _overlay_frame("工坊分享与素材导入", 1200, 680)
	var g := Sigil.new(); g.screen = self
	put(g, Rect2(40, 110, 380, 380), "c", -1.0, p)
	text("当前图纸：" + (draft.name if draft.name != "" else "未命名"), Rect2(40, 500, 400, 44), 22, "ink", 500, "c", p)
	text("导出为原卡标准 v3 存档 JSON（兼容《艾瑟拉》酒馆原卡与荧荧工坊），也可直接发布或前往工坊管理面板导入。", Rect2(480, 110, 680, 90), 20, "muted", 500, "c", p)
	var ex := btn("导出存档 (v3)", "download", "secondary", Rect2(480, 220, 330, 84), func(): _export(), "c", -1.0, p, 24)
	ex.name = "Export"
	var im := btn("导入本地存档", "upload", "secondary", Rect2(830, 220, 330, 84), func(): _import(), "c", -1.0, p, 24)
	im.name = "Import"
	var up := btn("上传到荧荧工坊", "cloud", "primary", Rect2(480, 330, 680, 90), func(): _open_workshop_upload(), "c", -1.0, p, 26)
	up.name = "Upload"; up.disabled = draft.parts.is_empty()
	var mgr := btn("打开创意工坊管理面板（下载 / 导入）", "globe", "chip", Rect2(480, 442, 680, 76), func():
		overlay = ""; _persist(); root.go("creative_workshop", {"tab": "repo"})
	, "c", -1.0, p, 22)
	mgr.name = "OpenWorkshopManager"
	text("快捷本地导入 / 导出位置：" + ProjectSettings.globalize_path("user://workshop_export.json"), Rect2(480, 536, 680, 54), 16, "muted", 500, "c", p)

func _open_workshop_upload() -> void:
	if draft.parts.is_empty():
		toast("图纸还是空的 —— 先拼一道刻印再上传到荧荧工坊", "warn")
		UiHub.sfx("deny")
		return
	_save(false)
	overlay = ""
	root.go("creative_workshop", {
		"tab": "upload",
		"cat": "blueprint",
		"upload_sigil_archive": current_archive_for_draft(draft, _cost_of(draft.parts)),
	})

func on_back() -> bool:
	if overlay != "":
		if overlay == "result":
			UiHub.stop_workshop_activation(true)
		overlay = ""; refresh(); return true
	return false

func on_shown() -> void:
	if FileAccess.file_exists(STORE) and not UiHub.review_mode:
		_load()
		refresh(false)

func _exit_tree() -> void:
	UiHub.stop_workshop_activation(false)

# ---------------------------------------------------------------- model helpers (card logic)
func _node(id: String) -> Dictionary:
	if id == "": return {}
	for p in draft.parts:
		if str(p.id) == id: return p
	return {}

func _children(id: String) -> Array:
	return draft.parts.filter(func(p): return str(p.get("parent", "")) == id)

func _subtree(id: String) -> Array:
	var out := [id]
	for c in _children(id): out.append_array(_subtree(str(c.id)))
	return out

func _attached(p: Dictionary) -> bool:
	return str(p.get("parent", "")) != "" and not _node(str(p.parent)).is_empty()

func _in_circuit(p: Dictionary) -> bool:
	return _attached(p) or not _children(str(p.id)).is_empty()

func _is_desc(id: String, anc: String) -> bool:
	var n := _node(id); var guard := 0
	while not n.is_empty() and str(n.get("parent", "")) != "" and guard < 40:
		if str(n.parent) == anc: return true
		n = _node(str(n.parent)); guard += 1
	return false

static func port(d: Dictionary, pid: String) -> Dictionary:
	for s in d.get("slots", []):
		if str(s.id) == pid: return s
	return {}

static func port_index(d: Dictionary, sid: String) -> int:
	var list: Array = d.get("slots", [])
	for i in range(list.size()):
		if str(list[i].id) == sid: return i + 1
	return 0

static func rot_local(v: Vector2, deg: float) -> Vector2:
	return v.rotated(deg_to_rad(deg))

static func world_port(w: Dictionary, d: Dictionary, pid: String) -> Vector2:
	var p := port(d, pid)
	var v := Vector2(float(p.get("x", 0)), float(p.get("y", 0)))
	return Vector2(w.x, w.y) + rot_local(v, w.a) * float(cat().scale)

static func wrap180(a: float) -> float:
	return fposmod(a + 180.0, 360.0) - 180.0

static func default_plug(cd: Dictionary, face: float) -> String:
	var ports: Array = cd.get("slots", [])
	if ports.is_empty(): return "root"
	if not port(cd, "root").is_empty() and cd.kind != "core": return "root"
	var best: Dictionary = ports[0]; var best_d := 9999.0
	for p in ports:
		var dd := absf(wrap180(face + 180.0 - float(p.a)))
		if dd < best_d: best_d = dd; best = p
	return str(best.id)

static func attached_world(pw: Dictionary, pd: Dictionary, ppid: String, cd: Dictionary, cpid: String, crot: float) -> Dictionary:
	var pp := port(pd, ppid); var cp := port(cd, cpid)
	var face: float = pw.a + float(pp.get("a", 0))
	var child_a: float = face + 180.0 - float(cp.get("a", 0)) + crot
	var ppos := world_port(pw, pd, ppid)
	var gap: float = cat().link_gap_core if pd.kind == "core" and cd.kind == "core" else cat().link_gap
	var fr := deg_to_rad(face)
	var cpos := ppos + Vector2(sin(fr), -cos(fr)) * gap
	var cr := rot_local(Vector2(float(cp.get("x", 0)), float(cp.get("y", 0))), child_a) * float(cat().scale)
	return {"x": cpos.x - cr.x, "y": cpos.y - cr.y, "a": child_a}

## World transform of every part (same recursion as the card's computeWorlds).
func worlds(override := {}) -> Dictionary:
	var map := {}
	for p in draft.parts: _world_of(p, map, [], override)
	return map

func _world_of(p: Dictionary, map: Dictionary, stack: Array, override: Dictionary) -> Dictionary:
	var id := str(p.id)
	if map.has(id): return map[id]
	if id in stack:
		map[id] = {"x": 590.0, "y": 330.0, "a": 0.0}; return map[id]
	if override.get("id", "") == id and override.has("wx"):
		map[id] = {"x": override.wx, "y": override.wy, "a": float(p.get("rot", 0))}; return map[id]
	if _attached(p):
		var pp := _node(str(p.parent))
		var pw := _world_of(pp, map, stack + [id], override)
		var pd := defp(pp.partId); var kd := defp(p.partId)
		if not port(pd, str(p.get("slot", ""))).is_empty():
			var plug := str(p.get("plug", ""))
			if port(kd, plug).is_empty(): plug = default_plug(kd, 0.0)
			map[id] = attached_world(pw, pd, str(p.slot), kd, plug, float(p.get("rot", 0)))
			return map[id]
	map[id] = {"x": float(p.get("x", 590)), "y": float(p.get("y", 330)), "a": float(p.get("rot", 0))}
	return map[id]

func port_busy(nid: String, pid: String, ignore := []) -> bool:
	var n := _node(nid)
	if not n.is_empty() and _attached(n) and str(n.get("plug", "")) == pid and not (str(n.id) in ignore): return true
	for c in draft.parts:
		if str(c.get("parent", "")) == nid and str(c.get("slot", "")) == pid and not (str(c.id) in ignore): return true
	return false

## Nearest free port (of a part not in `exclude`) to world point w, within the card's SNAP_DIST.
func nearest_port(w: Vector2, exclude: Array, max_dist := 88.0) -> Dictionary:
	var ws := worlds()
	var best := {}; var bd := max_dist
	for p in draft.parts:
		var id := str(p.id)
		if id in exclude: continue
		var d := defp(p.partId)
		for s in d.get("slots", []):
			if port_busy(id, str(s.id), exclude): continue
			var pos := world_port(ws[id], d, str(s.id))
			var dist := pos.distance_to(w)
			if dist < bd: bd = dist; best = {"id": id, "slot": str(s.id), "pos": pos}
	return best

func _new_id() -> String:
	_id_seq += 1
	return "p%d%03d" % [Time.get_ticks_msec() % 1000000, _id_seq]

func add_part(pid: String, world: Vector2, snap := true) -> void:
	var d := defp(pid)
	var node := {"id": _new_id(), "partId": pid, "parent": "", "slot": "", "plug": "", "rot": 0}
	var hit := nearest_port(world, []) if snap else {}
	if not hit.is_empty():
		var parent := _node(hit.id); var ws := worlds()
		var face: float = ws[hit.id].a + float(port(defp(parent.partId), hit.slot).get("a", 0))
		node.parent = hit.id; node.slot = hit.slot; node.plug = default_plug(d, face)
		UiHub.sfx("attach", 1.0 + 0.06 * (draft.parts.size() % 6))
	else:
		node.x = roundf(world.x); node.y = roundf(world.y)
		UiHub.sfx("place")
	draft.parts.append(node)
	selected_id = node.id
	_persist(); _after_change(node.id)

## Click on a palette chip: attach to the selected part's first free port, else place near centre.
func quick_add(pid: String) -> void:
	var sel := _node(selected_id)
	if not sel.is_empty():
		var d := defp(sel.partId)
		for s in d.get("slots", []):
			if not port_busy(selected_id, str(s.id)):
				var ws := worlds()
				add_part(pid, world_port(ws[selected_id], d, str(s.id)), true); return
	var n: int = draft.parts.size()
	add_part(pid, Vector2(590, 330) + Vector2(130 * (n % 4), 0).rotated(n * 1.1) * (1 if n else 0), defp(pid).kind != "core")

func move_part(id: String, world: Vector2, snap: bool) -> void:
	var p := _node(id)
	if p.is_empty(): return
	var tree := _subtree(id)
	var hit := nearest_port(world, tree) if snap else {}
	if not hit.is_empty() and not _is_desc(hit.id, id):
		var ws := worlds()
		var face: float = ws[hit.id].a + float(port(defp(_node(hit.id).partId), hit.slot).get("a", 0))
		p.parent = hit.id; p.slot = hit.slot; p.plug = default_plug(defp(p.partId), face); p.rot = 0
		p.erase("x"); p.erase("y")
		UiHub.sfx("attach", 1.06)
	else:
		p.parent = ""; p.slot = ""; p.plug = ""
		p.x = roundf(world.x); p.y = roundf(world.y)
		UiHub.sfx("place", 0.94)
	_persist(); _after_change(id)

func _rotate(step: int) -> void:
	var p := _node(selected_id)
	if p.is_empty(): return
	p.rot = int(roundf((float(p.get("rot", 0)) + step) / 15.0) * 15) % 360
	UiHub.sfx("tick", 1.0 + step / 100.0)
	_persist(); refresh()

func _detach(id: String) -> void:
	var p := _node(id)
	if p.is_empty(): return
	var w: Dictionary = worlds()[id]
	p.parent = ""; p.slot = ""; p.plug = ""; p.x = roundf(w.x + 40); p.y = roundf(w.y + 40); p.rot = int(w.a) % 360
	UiHub.sfx("detach"); _persist(); refresh()

func _remove(id: String, with_children: bool) -> void:
	var gone := _subtree(id) if with_children else [id]
	var ws := worlds()
	for c in _children(id):
		if not with_children:
			var w: Dictionary = ws[str(c.id)]
			c.parent = ""; c.slot = ""; c.plug = ""; c.x = roundf(w.x); c.y = roundf(w.y); c.rot = int(w.a) % 360
	draft.parts = draft.parts.filter(func(p): return not (str(p.id) in gone))
	selected_id = ""
	UiHub.sfx("erase"); UiHub.haptic(18)
	if canvas: canvas.flash_at(Vector2(ws[id].x, ws[id].y))
	_persist(); refresh()

func _after_change(id: String) -> void:
	if canvas:
		var w: Dictionary = worlds().get(id, {})
		if not w.is_empty(): canvas.flash_at(Vector2(w.x, w.y))
	refresh()

func _zoom(z: float) -> void:
	zoom = clampf(z, 0.45, 2.4)
	UiHub.sfx("tick", 0.9 + zoom * 0.2)
	if zoom_label: zoom_label.text = "%d%%" % int(round(zoom / 0.92 * 100.0))
	if canvas: canvas.queue_redraw()

func _new_blank() -> void:
	if not draft.parts.is_empty(): _save(false)
	draft = {"name": "", "carrier": "", "effect": "", "parts": []}
	selected_id = ""; cam = Vector2(590, 330)
	UiHub.sfx("page"); _persist(); refresh(true)

func _open_saved(i: int) -> void:
	if i < 0 or i >= saved.size(): return
	draft = saved[i].duplicate(true)
	selected_id = ""; tab = "palette"
	UiHub.sfx("page"); _persist(); refresh(true)

# ---------------------------------------------------------------- blueprint text (describeCircuit)
func _cost_of(parts: Array) -> int:
	var raw := 0
	var natures: Array = []
	var cores := []; var outers := []; var micros := []
	for p in parts:
		var d := defp(p.partId)
		raw += int(d.get("cost", 0))
	# sync only counts parts in the circuit (cores always count), same as the card
	var keep: Array = parts
	var save: Array = draft.parts
	draft.parts = keep
	for p in parts:
		var d := defp(p.partId)
		if d.kind == "core": cores.append(d.nature)
		elif _in_circuit(p):
			if d.kind == "outer": outers.append(d.nature)
			else: micros.append(d.nature)
	draft.parts = save
	natures = [cores[0] if not cores.is_empty() else ""] + outers + micros
	var best := 0
	for n in NATURE_TONE.keys():
		best = maxi(best, natures.count(n))
	var sync := best if best >= 2 else 0
	return maxi(0, raw - sync)

func _branch(p: Dictionary) -> Dictionary:
	var depth := 0; var node := p
	while not node.is_empty() and depth < 64:
		var par := _node(str(node.get("parent", "")))
		if par.is_empty(): return {}
		depth += 1
		var pd := defp(par.partId)
		if pd.kind == "core": return {"core": str(par.id), "port": port_index(pd, str(node.slot)), "depth": depth}
		node = par
	return {}

func _cn(i: int) -> String:
	return CN[i] if i >= 1 and i <= 10 else str(i)

func _describe() -> Dictionary:
	var parts: Array = draft.parts.filter(func(p): return defp(p.partId).kind == "core" or _in_circuit(p))
	var cores: Array = parts.filter(func(p): return defp(p.partId).kind == "core")
	var multi := cores.size() > 1
	var num := {}
	for i in range(cores.size()): num[str(cores[i].id)] = i + 1
	var ent: Array = []
	for c in cores:
		var d := defp(c.partId)
		var label: String = "核纹" + (_cn(num[str(c.id)]) if multi else "") + "·" + str(d.nature) + "【" + str(d.shorthand) + "】"
		var conns: Array = []
		for x in _children(str(c.id)): conns.append({"port": port_index(d, str(x.slot)), "x": x})
		var par := _node(str(c.get("parent", "")))
		if not par.is_empty() and defp(par.partId).kind == "core": conns.append({"port": port_index(d, str(c.get("plug", ""))), "x": par})
		conns.sort_custom(func(a, b): return a.port < b.port)
		var ports: Array = []; var links: Array = []
		for cn in conns:
			if cn.port and not (cn.port in ports): ports.append(cn.port)
			if defp(cn.x.partId).kind == "core": links.append("核纹" + _cn(int(num.get(str(cn.x.id), 0))))
		var detail := ""
		if not ports.is_empty(): detail += "（接口" + "、".join(PackedStringArray(ports.map(func(v): return str(v)))) + "已启用）"
		if not links.is_empty(): detail += "（链接" + "，".join(PackedStringArray(links)) + "）"
		ent.append({"kind": 0, "nature": str(d.nature), "ord": num[str(c.id)], "text": label + detail + "×1"})
	var groups := {}
	var group_order: Array = []
	for p in parts:
		var d := defp(p.partId)
		if d.kind == "core": continue
		if not groups.has(p.partId):
			groups[p.partId] = {"kind": 1 if d.kind == "outer" else 2, "nature": str(d.nature), "label": KIND_FULL[d.kind] + "·" + str(d.nature) + "【" + str(d.shorthand) + "】", "insts": []}
			group_order.append(p.partId)
		var br := _branch(p)
		if br.is_empty() or br.port == 0: continue
		var ref: String = ("核纹" + _cn(int(num.get(br.core, 0))) + "·" if multi else "") + "接口%d-%s" % [br.port, CIRC[clampi(br.depth - 1, 0, CIRC.size() - 1)]]
		var inner: String = (("逆位" if str(p.get("plug", "")) == "exit" else "正位") + "，" if d.kind == "outer" else "") + ref
		groups[p.partId].insts.append({"inner": inner, "core": int(num.get(br.core, 0)), "port": br.port, "depth": br.depth})
	for k in group_order:
		var g: Dictionary = groups[k]
		if g.insts.is_empty(): continue
		g.insts.sort_custom(func(a, b): return a.core < b.core if a.core != b.core else (a.port < b.port if a.port != b.port else a.depth < b.depth))
		ent.append({"kind": g.kind, "nature": g.nature, "ord": 0, "text": g.label + "（" + "；".join(PackedStringArray(g.insts.map(func(t): return t.inner))) + "）×%d" % g.insts.size()})
	ent.sort_custom(func(a, b):
		if a.kind != b.kind: return a.kind < b.kind
		if a.kind == 0: return a.ord < b.ord
		return a.nature < b.nature)
	var cost := _cost_of(draft.parts)
	var title: String = draft.name.strip_edges() if draft.name.strip_edges() != "" else "未命名"
	var carrier: String = draft.carrier.strip_edges()
	var eff := _effect_text()
	var lines: Array = ent.map(func(e): return "  " + e.text)
	var txt := "【刻印】" + title + "\n" + "【载体】" + (carrier if carrier != "" else "未指定") + "\n" + "【纹章】共 %d 枚" % parts.size() + "\n" \
		+ ("\n".join(PackedStringArray(lines)) if not lines.is_empty() else "  （未成回路）") + "\n" + "【耗用】%d" % cost + "\n" + "玩家编写效果：" + (eff if eff != "" else "（未填写）")
	return {"text": txt, "count": parts.size(), "cost": cost, "title": title}

## Player effect, one line: newlines/whitespace collapse, spaces between CJK characters dropped, 240 chars.
func _effect_text() -> String:
	var t := str(draft.get("effect", ""))
	var rx := RegEx.new(); rx.compile("\\s+")
	t = rx.sub(t, " ", true).strip_edges()
	var cj := RegEx.new(); cj.compile("([\\x{3000}-\\x{303f}\\x{4e00}-\\x{9fff}\\x{ff00}-\\x{ffef}]) (?=[\\x{3000}-\\x{303f}\\x{4e00}-\\x{9fff}\\x{ff00}-\\x{ffef}])")
	t = cj.sub(t, "$1", true)
	return t.substr(0, 240)

func _activate() -> void:
	if draft.parts.is_empty(): return
	_save(false)
	var bp := _describe()
	result_text = bp.text
	UiHub.set_meta("workshop_spell", bp.text)
	request("craft.activate", {"blueprint": bp.text, "name": bp.title, "cost": bp.cost, "draft": draft.duplicate(true)})
	if not UiHub.reduced_motion:
		# 2026-11-17: full-screen ceremony locked to the activation music (scripts/ui/workshop_activation_fx.gd).
		# 03 -> 04 -> 05 -> 06 play in order, same day and night, no other sound until it ends.
		UiHub.start_workshop_activation()
		var fx := ActFx.new(); fx.name = "ActivationFx"
		fx.screen = self; fx.title = bp.title; fx.blueprint = bp.text
		add_child(fx); fx.position = Vector2.ZERO; fx.size = size
		fx.finished.connect(func(): UiHub.sfx_quiet = false; overlay = "result"; refresh())
		fx.play()
	else:
		UiHub.finish_workshop_activation()
		overlay = "result"; refresh()

func _save(announce: bool) -> void:
	if draft.parts.is_empty(): return
	var copy := draft.duplicate(true)
	var title := str(copy.name).strip_edges()
	var found := -1
	for i in range(saved.size()):
		if title != "" and str(saved[i].get("name", "")).strip_edges() == title: found = i
	if found >= 0: saved[found] = copy
	else: saved.push_front(copy)
	_persist()
	if announce:
		UiHub.sfx("save"); toast("已保存：" + (title if title != "" else "未命名"), "save"); refresh()

func _export() -> void:
	var f := FileAccess.open("user://workshop_export.json", FileAccess.WRITE)
	if f == null: toast("导出失败", "warn"); return
	var clean_saved := []
	for s in saved:
		if s is Dictionary: clean_saved.append(clean_sigil_record(s))
	f.store_string(JSON.stringify({
		"format": "academy-sigil-archive",
		"version": 3,
		"exportedAt": Time.get_datetime_string_from_system(false, true),
		"draft": clean_sigil_record(draft),
		"saved": clean_saved,
	}, "  "))
	UiHub.sfx("save"); toast("已导出 v3 存档到 user://workshop_export.json", "download")

func _import() -> void:
	if not FileAccess.file_exists("user://workshop_export.json"):
		toast("没有找到 user://workshop_export.json", "warn"); UiHub.sfx("deny"); return
	var data = JSON.parse_string(FileAccess.get_file_as_string("user://workshop_export.json"))
	if not data is Dictionary: toast("文件格式不对", "warn"); return
	for s in data.get("saved", []):
		if s is Dictionary and s.get("parts", null) is Array: saved.append(_clean(s))
	if data.get("draft", null) is Dictionary: draft = _clean(data.draft)
	UiHub.sfx("confirm"); toast("已导入", "upload"); _persist(); refresh(true)

static func clean_sigil_record(s: Dictionary) -> Dictionary:
	var parts: Array = []
	for p in s.get("parts", []):
		if p is Dictionary and cat().patterns.has(str(p.get("partId", ""))): parts.append(p)
	var out := {
		"name": str(s.get("name", "")),
		"carrier": str(s.get("carrier", "")),
		"effect": str(s.get("effect", "")),
		"parts": parts,
	}
	if s.has("id") and str(s.get("id", "")) != "": out["id"] = str(s.get("id", ""))
	if s.has("cost"): out["cost"] = int(s.get("cost", 0))
	if s.has("updatedAt"): out["updatedAt"] = str(s.get("updatedAt", ""))
	return out

static func current_archive_for_draft(d: Dictionary, cost := 0) -> Dictionary:
	var rec := clean_sigil_record(d)
	if str(rec.get("name", "")).strip_edges() == "": rec["name"] = "未命名符印"
	if str(rec.get("id", "")) == "":
		rec["id"] = "magic_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000)
	rec["cost"] = cost
	rec["updatedAt"] = Time.get_datetime_string_from_system(false, true)
	return {
		"format": "academy-sigil-archive",
		"version": 3,
		"exportedAt": Time.get_datetime_string_from_system(false, true),
		"draft": {"name": rec.name, "carrier": rec.carrier, "effect": rec.effect, "parts": rec.parts.duplicate(true)},
		"saved": [rec],
	}

func _clean(s: Dictionary) -> Dictionary:
	return clean_sigil_record(s)

func _load() -> void:
	if not FileAccess.file_exists(STORE): return
	var data = JSON.parse_string(FileAccess.get_file_as_string(STORE))
	if not data is Dictionary: return
	if data.get("draft", null) is Dictionary: draft = _clean(data.draft)
	saved.clear()
	for s in data.get("saved", []):
		if s is Dictionary: saved.append(_clean(s))

func _persist() -> void:
	if UiHub.review_mode: return
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f: f.store_string(JSON.stringify({"draft": draft, "saved": saved}))


# ================================================================ drawing
## Paint one pattern glyph at a world transform. ink: rims/lines, acc: fills, k: px per glyph unit.
static func paint_glyph(ci: CanvasItem, pid: String, center: Vector2, ang_deg: float, k: float, ink: Color, acc: Color, hole: Color, lit := 0.0) -> void:
	var d: Dictionary = defp(pid)
	if d.is_empty(): return
	var a := deg_to_rad(ang_deg)
	var special: bool = d.nature == "特殊"
	var fillc: Color = Color(NATURE_TONE["特殊"]) if special else acc
	var tf := func(x: float, y: float) -> Vector2: return center + Vector2(x, y).rotated(a) * k
	for g in d.glyph:
		var cls: Array = g.get("cls", [])
		var is_rim := "rim" in cls; var is_ln := "ln" in cls or "tick" in cls
		var thin := "thin" in cls; var dash := "dash" in cls
		var w := (1.0 if thin or dash else 1.7) * clampf(k / 1.3, 0.7, 1.6)
		var line_c := ink if not special else Color(fillc, 0.95)
		if lit > 0.0: line_c = line_c.lerp(acc, lit)
		match g.t:
			"circle":
				var c: Vector2 = tf.call(float(g.cx), float(g.cy)); var r: float = float(g.r) * k
				if "halo" in cls: ci.draw_circle(c, r, Color(fillc, 0.07 + 0.12 * lit))
				elif g.get("card", false): ci.draw_circle(c, r, hole)
				elif "dot" in cls: ci.draw_circle(c, maxf(r, 1.3), Color(fillc if lit > 0.0 or special else ink, 0.9))
				elif is_rim:
					if dash: _dashed_arc(ci, c, r, line_c, w)
					else: ci.draw_arc(c, r, 0, TAU, 40, line_c, w, true)
				else:
					ci.draw_circle(c, r, Color(fillc, 0.9))
			"ellipse":
				var pts := PackedVector2Array()
				for i in range(41):
					var t := TAU * i / 40.0
					var e := Vector2(cos(t) * float(g.rx), sin(t) * float(g.ry)).rotated(deg_to_rad(float(g.rot))) + Vector2(float(g.cx), float(g.cy))
					pts.append(tf.call(e.x, e.y))
				if dash: _dashed_poly(ci, pts, line_c, w)
				else: ci.draw_polyline(pts, line_c, w, true)
			"path":
				for poly in g.polys:
					var pts := PackedVector2Array()
					for q in poly.pts: pts.append(tf.call(float(q[0]), float(q[1])))
					if pts.size() < 2: continue
					if is_rim or is_ln:
						if dash: _dashed_poly(ci, pts, line_c, w)
						else: ci.draw_polyline(pts, line_c, w, true)
					else:
						if pts.size() >= 3 and not Geometry2D.triangulate_polygon(pts).is_empty():
							ci.draw_colored_polygon(pts, Color(fillc, 0.92))
						else:
							ci.draw_polyline(pts, Color(fillc, 0.92), w, true)

static func _dashed_poly(ci: CanvasItem, pts: PackedVector2Array, c: Color, w: float, on := 6.0, off := 6.0) -> void:
	var carry := 0.0; var draw_on := true
	for i in range(pts.size() - 1):
		var a := pts[i]; var b := pts[i + 1]; var L := a.distance_to(b); var pos := 0.0
		while pos < L:
			var seg := minf((on if draw_on else off) - carry, L - pos)
			if draw_on: ci.draw_line(a.lerp(b, pos / L), a.lerp(b, (pos + seg) / L), c, w, true)
			pos += seg; carry += seg
			if carry >= (on if draw_on else off) - 0.01: carry = 0.0; draw_on = not draw_on

static func _dashed_arc(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float) -> void:
	var n := maxi(8, int(TAU * r / 12.0))
	for i in range(n):
		if i % 2 == 0: ci.draw_arc(c, r, TAU * i / n, TAU * (i + 1) / n, 4, col, w, true)


## Palette chip: glyph + short name. Press-and-drag drops onto the canvas; a plain click quick-adds.
class PatternChip extends Control:
	var screen
	var pid := ""
	var hover := 0.0
	var _down := false
	var _start := Vector2.ZERO
	func _ready() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): hover = 1.0; queue_redraw(); UiHub.sfx("hover", 1.1 + randf() * 0.1))
		mouse_exited.connect(func(): hover = 0.0; queue_redraw())
		UiHub.palette_changed.connect(queue_redraw)
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed: _down = true; _start = e.global_position; UiHub.sfx("select")
			elif _down:
				_down = false
				var cv: Control = screen.canvas
				if is_instance_valid(cv) and cv.dragging_new != "":
					cv.drop_new(cv.get_local_mouse_position())
				else:
					screen.quick_add(pid)
			accept_event()
		elif e is InputEventMouseMotion and _down:
			var cv: Control = screen.canvas
			if is_instance_valid(cv) and e.global_position.distance_to(_start) > 14.0:
				cv.begin_new(pid)
				cv.queue_redraw()
	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		var poly := Kit.rrect(r, 18, 6)
		draw_colored_polygon(poly, UiHub.c("surface", 0.85))
		if hover > 0.0: draw_colored_polygon(poly, UiHub.c("accent", 0.06))
		draw_polyline(Kit.closed(poly), UiHub.c("accent" if hover > 0.0 else "line"), 1.2, true)
		var d: Dictionary = screen.defp(pid)
		var k := 0.95 if d.kind == "core" else 1.05
		var c := Vector2(size.x * 0.5, size.y * 0.42 + (12.0 if d.kind != "core" else 0.0))
		screen.paint_glyph(self, pid, c, 0.0, k, UiHub.c("ink"), UiHub.c("accent"), UiHub.c("surface"), hover * 0.4)
		Kit.text(self, Rect2(0, size.y - 34, size.x, 26), str(d.shorthand), UiHub.fs(18), UiHub.c("ink"), HORIZONTAL_ALIGNMENT_CENTER, 600)


## Static glyph preview (right panel, codex).
class GlyphView extends Control:
	var screen
	var pid := ""
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE; UiHub.palette_changed.connect(queue_redraw)
	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, size.x * 0.46, 0, TAU, 48, UiHub.c("line"), 1.0, true)
		var d: Dictionary = screen.defp(pid)
		var k := size.x / (80.0 if d.kind == "core" else 66.0)
		var off := Vector2(0, 0 if d.kind == "core" else 22.0 * k * 0.6)
		screen.paint_glyph(self, pid, c + off, 0.0, k, UiHub.c("ink"), UiHub.c("accent"), UiHub.c("surface"))


## Finished sigil preview (activation result, share page): the whole draft fitted into the box,
## with a slowly turning construction ring.
class Sigil extends Control:
	var screen
	var clock := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE; UiHub.palette_changed.connect(queue_redraw)
	func _process(d: float) -> void:
		if UiHub.reduced_motion: return
		clock += d; queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var acc := UiHub.c("accent")
		draw_arc(c, size.x * 0.47, 0, TAU, 72, UiHub.c("line"), 1.0, true)
		Kit.arc_fade(self, c, size.x * 0.42, clock * 0.3, clock * 0.3 + PI * 1.2, acc, 1.6, 48, 0.2)
		Kit.crescent(self, c, size.x * 0.44, clock * 0.3 + PI, clock * 0.3 + PI * 1.6, 5.0, acc)
		var ws: Dictionary = screen.worlds()
		if ws.is_empty():
			Kit.star4(self, c, 30, acc, 0.16); return
		var bb := Rect2(Vector2(ws.values()[0].x, ws.values()[0].y), Vector2.ZERO)
		for w in ws.values(): bb = bb.expand(Vector2(w.x, w.y))
		bb = bb.grow(80)
		var k := minf(size.x * 0.8 / bb.size.x, size.y * 0.8 / bb.size.y)
		for p in screen.draft.parts:
			var w: Dictionary = ws[str(p.id)]
			var sp := c + (Vector2(w.x, w.y) - bb.get_center()) * k
			screen.paint_glyph(self, p.partId, sp, w.a, screen.cat().scale * k, UiHub.c("ink"), acc, UiHub.c("surface"), 0.6)


## The drawing board: construction rings, links, parts, free ports, pan / zoom, drag to connect.
class Canvas extends Control:
	var screen
	var clock := 0.0
	var dragging_new := ""
	var drag_id := ""
	var drag_world := Vector2.ZERO
	var drag_offset := Vector2.ZERO
	var panning := false
	var pan_start := Vector2.ZERO
	var cam_start := Vector2.ZERO
	var press_pos := Vector2.ZERO
	var moved := false
	var flashes: Array = []
	var lit: Dictionary = {}
	var ignite_t := -1.0
	var ignite_order: Array = []
	var ignite_done: Callable
	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		UiHub.palette_changed.connect(queue_redraw)
	func to_screen(w: Vector2) -> Vector2:
		return (w - screen.cam) * screen.zoom + size * 0.5
	func to_world(s: Vector2) -> Vector2:
		return (s - size * 0.5) / screen.zoom + screen.cam
	func begin_new(pid: String) -> void:
		if dragging_new == "": UiHub.sfx("pick")
		dragging_new = pid
	func drop_new(local: Vector2) -> void:
		var pid := dragging_new; dragging_new = ""
		if Rect2(Vector2.ZERO, size).has_point(local): screen.add_part(pid, to_world(local), true)
		else: UiHub.sfx("back", 1.2); queue_redraw()
	func flash_at(w: Vector2) -> void:
		if UiHub.reduced_motion: return
		flashes.append({"w": w, "t": 0.0})
	func ignite(done: Callable) -> void:
		# light parts from each core outward, breadth first (card: lit / flicker sequence)
		ignite_order.clear(); lit.clear()
		var frontier: Array = screen.draft.parts.filter(func(p): return screen.defp(p.partId).kind == "core" or not screen._attached(p))
		var seen := {}
		while not frontier.is_empty():
			var nxt: Array = []
			for p in frontier:
				if seen.has(str(p.id)): continue
				seen[str(p.id)] = true; ignite_order.append(str(p.id))
				nxt.append_array(screen._children(str(p.id)))
			frontier = nxt
		ignite_t = 0.0; ignite_done = done
	func _process(d: float) -> void:
		if not is_visible_in_tree(): return
		if not UiHub.reduced_motion: clock += d
		for f in flashes: f.t += d / 0.6
		flashes = flashes.filter(func(f): return f.t < 1.0)
		if ignite_t >= 0.0:
			ignite_t += d
			var step := 0.28
			for i in range(ignite_order.size()):
				var id: String = ignite_order[i]
				if ignite_t >= i * step and not lit.has(id):
					lit[id] = 0.0
					var w: Dictionary = screen.worlds().get(id, {})
					if not w.is_empty(): flash_at(Vector2(w.x, w.y))
			for id in lit: lit[id] = minf(1.0, lit[id] + d * 4.0)
			if ignite_t > maxf(ignite_order.size() * step + 1.1, 2.2):
				ignite_t = -1.0
				var cb := ignite_done; ignite_done = Callable()
				if cb.is_valid(): cb.call()
		queue_redraw()
	func _hit(local: Vector2) -> String:
		var ws: Dictionary = screen.worlds()
		var best := ""; var bd: float = 34.0 * screen.zoom * 1.6
		for p in screen.draft.parts:
			var w: Dictionary = ws[str(p.id)]
			var dd := to_screen(Vector2(w.x, w.y)).distance_to(local)
			if dd < bd: bd = dd; best = str(p.id)
		return best
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: _zoom_at(e.position, 1.1); accept_event(); return
			if e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: _zoom_at(e.position, 1.0 / 1.1); accept_event(); return
			if e.button_index != MOUSE_BUTTON_LEFT: return
			if e.pressed:
				press_pos = e.position; moved = false
				var id := _hit(e.position)
				if id != "":
					drag_id = id
					var w: Dictionary = screen.worlds()[id]
					drag_offset = Vector2(w.x, w.y) - to_world(e.position)
					drag_world = Vector2(w.x, w.y)
				else:
					panning = true; pan_start = e.position; cam_start = screen.cam
			else:
				if drag_id != "":
					var id := drag_id; drag_id = ""
					if moved: screen.move_part(id, drag_world, true)
					else:
						screen.selected_id = id; UiHub.sfx("select"); screen.refresh()
				elif panning:
					panning = false
					if not moved and screen.selected_id != "":
						screen.selected_id = ""; UiHub.sfx("tick"); screen.refresh()
			accept_event()
		elif e is InputEventMouseMotion:
			if drag_id != "":
				if e.position.distance_to(press_pos) > 6.0:
					if not moved: UiHub.sfx("pick")
					moved = true
				drag_world = to_world(e.position) + drag_offset
				queue_redraw()
			elif panning:
				if e.position.distance_to(press_pos) > 6.0: moved = true
				screen.cam = cam_start - (e.position - pan_start) / screen.zoom
				queue_redraw()
			elif dragging_new != "":
				queue_redraw()
	func _zoom_at(local: Vector2, f: float) -> void:
		var before := to_world(local)
		screen._zoom(screen.zoom * f)
		screen.cam += before - to_world(local)
	func _draw() -> void:
		var acc := UiHub.c("accent"); var ink := UiHub.c("ink"); var line := UiHub.c("line")
		var z: float = screen.zoom
		var sc: float = screen.cat().scale
		var override := {}
		if drag_id != "" and moved: override = {"id": drag_id, "wx": drag_world.x, "wy": drag_world.y}
		var ws: Dictionary = screen.worlds(override)
		# construction rings around the first core (or the centre of an empty board)
		var center := Vector2(590, 330)
		for p in screen.draft.parts:
			if screen.defp(p.partId).kind == "core": center = Vector2(ws[str(p.id)].x, ws[str(p.id)].y); break
		var c := to_screen(center)
		var spin := clock * 0.12
		var glow := 1.0 if ignite_t >= 0.0 else 0.0
		for i in range(3):
			var r := (150.0 + i * 70.0) * z
			Kit.arc_fade(self, c, r, spin * (1 if i % 2 == 0 else -1) + i, spin * (1 if i % 2 == 0 else -1) + i + PI * 1.6, Color(line, 0.9), 1.0, 80, 0.1)
		Kit.crescent(self, c, 220.0 * z, -PI * 0.55 + spin, PI * 0.15 + spin, 5.0 * z + 2.0 * glow, Color(acc, 0.7 + 0.3 * glow))
		Kit.line_fade(self, c + Vector2(-260, 300) * z, c + Vector2(260, -300) * z, Color(acc, 0.45), 1.0)
		draw_line(c + Vector2(-340 * z, 0), c + Vector2(340 * z, 0), Color(line, 0.6), 1.0, true)
		draw_line(c + Vector2(0, -280 * z), c + Vector2(0, 280 * z), Color(line, 0.6), 1.0, true)
		for q in [Vector2(-340, 0), Vector2(340, 0), Vector2(0, -280), Vector2(0, 280)]:
			draw_arc(c + q * z, 6.0, 0, TAU, 16, Color(acc, 0.8), 1.2, true)
		if screen.draft.parts.is_empty():
			Kit.text(self, Rect2(0, size.y * 0.5 + 250 * z * 0.5, size.x, 40), "从左侧把核纹拖到这里开始", UiHub.fs(22), UiHub.c("muted"), HORIZONTAL_ALIGNMENT_CENTER, 500)
		# links
		for p in screen.draft.parts:
			if not screen._attached(p): continue
			var par: Dictionary = screen._node(str(p.parent))
			var pw: Dictionary = ws[str(par.id)]; var cw: Dictionary = ws[str(p.id)]
			var a := to_screen(screen.world_port(pw, screen.defp(par.partId), str(p.slot)))
			var b := to_screen(screen.world_port(cw, screen.defp(p.partId), str(p.get("plug", "root"))))
			var lv: float = lit.get(str(p.id), 0.0)
			draw_line(a, b, Color(ink, 0.55).lerp(acc, lv), 1.4 + lv, true)
			draw_circle(a, 2.6, acc); draw_circle(b, 2.0, ink)
		# parts
		var hole := UiHub.c("surface")
		for p in screen.draft.parts:
			var w: Dictionary = ws[str(p.id)]
			var sp := to_screen(Vector2(w.x, w.y))
			var lv: float = lit.get(str(p.id), 0.0)
			var sel: bool = str(p.id) == screen.selected_id
			var loose: bool = screen.defp(p.partId).kind != "core" and not screen._in_circuit(p)
			if sel:
				draw_arc(sp, 44.0 * z * 1.2, 0, TAU, 40, Color(acc, 0.85), 1.4, true)
				Kit.star4(self, sp + Vector2(44.0 * z * 1.2, -44.0 * z * 1.2) * 0.71, 6.0, acc, 0.18)
			screen.paint_glyph(self, p.partId, sp, w.a, sc * z, Color(ink, 0.55 if loose else 1.0), acc, hole, lv)
			if lv > 0.0 and lv < 1.0: draw_arc(sp, (20.0 + 60.0 * lv) * z, 0, TAU, 40, Color(acc, 1.0 - lv), 1.4, true)
		# free ports (all when dragging, else only the selected part's)
		var show_all := drag_id != "" or dragging_new != ""
		var exclude: Array = screen._subtree(drag_id) if drag_id != "" else []
		var target := {}
		if show_all:
			var wpt := drag_world if drag_id != "" else to_world(get_local_mouse_position())
			target = screen.nearest_port(wpt, exclude)
		for p in screen.draft.parts:
			var id := str(p.id)
			if id in exclude: continue
			if not show_all and id != screen.selected_id: continue
			var d: Dictionary = screen.defp(p.partId)
			for s in d.get("slots", []):
				if screen.port_busy(id, str(s.id), exclude): continue
				var pos := to_screen(screen.world_port(ws[id], d, str(s.id)))
				var on: bool = not target.is_empty() and target.id == id and target.slot == str(s.id)
				draw_arc(pos, 7.0 if on else 5.0, 0, TAU, 20, acc if on else Color(ink, 0.6), 1.6 if on else 1.0, true)
				if on: draw_circle(pos, 3.0, acc)
		# palette drag ghost
		if dragging_new != "":
			var m := get_local_mouse_position()
			screen.paint_glyph(self, dragging_new, m, 0.0, sc * z, Color(ink, 0.5), Color(acc, 0.7), hole)
			if not target.is_empty(): draw_line(m, to_screen(target.pos), Color(acc, 0.6), 1.0, true)
		for f in flashes:
			var fp := to_screen(f.w)
			draw_arc(fp, (14.0 + 70.0 * f.t) * z, 0, TAU, 40, Color(acc, 0.8 * (1.0 - f.t)), 1.6, true)
			for j in range(8):
				var dir := Vector2.from_angle(TAU * j / 8.0 + 0.4)
				var r0: float = (18.0 + 60.0 * f.t) * z
				draw_line(fp + dir * r0, fp + dir * (r0 + 8.0 * (1.0 - f.t)), Color(acc, 1.0 - f.t), 1.4, true)
