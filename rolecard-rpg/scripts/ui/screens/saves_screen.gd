extends "res://scripts/ui/ui_screen.gd"
## 存档 / 读档: nine slots from Game.saves (slot 0 = 自动存档). Branches made in 回看 land here with
## their parent slot shown. Export / import go through Game. params: mode (save | load).

var mode := "load"

func build() -> void:
	mode = params.get("mode", mode)
	params.erase("mode")
	chrome("存档与读档")
	decor(91, Rect2(Vector2.ZERO, size), 0.6)
	if not Game.changed.is_connected(_on_game): Game.changed.connect(_on_game)
	for k in range(2):
		var id: String = ["save", "load"][k]
		var b := btn(["存档", "读档"][k], ["save", "upload"][k], "tab", Rect2(80 + k * 300, 130, 280, 76), func(): mode = id; refresh(false), "c", 0.0, null, 28)
		b.selected = mode == id; b.divider = false; b.name = "Mode_" + id
		if id == "save": b.disabled = not Game.has_story()
	var ex := btn("导出当前进度", "upload", "secondary", Rect2(1230, 130, 300, 76), func(): Game.export_save(), "c", 0.0, null, 22)
	ex.name = "Export"; ex.disabled = not Game.has_story()
	var im := btn("导入存档文件", "download", "secondary", Rect2(1550, 130, 300, 76), func(): _import(), "c", 0.0, null, 22)
	im.name = "Import"
	var slots: Array = Game.saves
	for k in range(slots.size()):
		var s: Dictionary = slots[k]
		var r := Rect2(80 + (k % 3) * 600 - (k / 3) * 30, 240 + (k / 3) * g(270), 570, 250)
		var b := Btn.new(); b.variant = "secondary"; b.slant = 40; b.name = "Slot%d" % int(s.slot)
		b.disabled = (mode == "load" and not s.used) or (mode == "save" and int(s.slot) == 0)
		put(b, r, "c", 0.06 + k * 0.04)
		b.pressed.connect(func(): _pick(s))
		var num := plate(Rect2(36, 16, 120, 56), {"slant": 18, "fill": "accent" if s.used else "block", "fill_alpha": 1.0, "border": "", "layered": false, "glass": false}, "c", -1.0, b)
		text("自动" if int(s.slot) == 0 else "%02d" % int(s.slot), Rect2(10, 0, 100, 56), 26, "on_accent" if s.used else "on_block", 900, "c", num, HORIZONTAL_ALIGNMENT_CENTER)
		if s.used:
			text(s.title, Rect2(180, 16, 330, 56), 28, "ink", 850, "c", b)
			text(s.time, Rect2(60, 96, 440, 40), 20, "muted", 600, "c", b)
			text("%d 条记录" % int(s.get("count", 0)) + ("  ·  分支自 %s" % ("自动存档" if int(s.parent) == 0 else "存档 %d" % int(s.parent)) if int(s.get("parent", -1)) >= 0 else ""), Rect2(60, 140, 440, 40), 20, "accent", 700, "c", b)
			if int(s.slot) != 0:
				var ren := btn("", "docs", "icon", Rect2(380, 170, 80, 64), func(): _rename_slot(s), "c", -1.0, b)
				ren.tooltip_text = "修改存档名称"
				var del := btn("", "trash", "icon", Rect2(470, 170, 80, 64), func(): _delete(s), "c", -1.0, b)
				del.tooltip_text = "删除存档"
		else:
			text("空存档位", Rect2(180, 16, 330, 56), 28, "muted", 700, "c", b)
	text("自动存档在每次回复后更新，不能手动覆盖；支持导入本机 .json 存档与 SillyTavern 酒馆旧聊天 .jsonl 记录。", Rect2(80, 1010, 1500, 40), 19, "muted", 600)

func _exit_tree() -> void:
	if Game.changed.is_connected(_on_game): Game.changed.disconnect(_on_game)

func _on_game(part: String) -> void:
	if part == "saves": refresh(false)

func _pick(s: Dictionary) -> void:
	if mode == "load":
		Game.load_slot(int(s.slot))
		root.go("loading", {"next": "home", "label": "载入存档"}, "wipe", "reset")
		return
	var slot_num := int(s.slot)
	if slot_num == 0: return
	var default_title := str(s.get("title", ""))
	if default_title == "":
		default_title = "%s · %s" % [Game.persona.get("name", "未署名"), Game.hero().get("当前地点", "塞蕾特公国")]
	var msg := "为存档位 %02d 命名并保存：" % slot_num
	if s.used:
		msg = "存档位 %02d 已有存档，确定覆盖并可以修改名称：" % slot_num
	root.prompt({
		"title": "保存并命名存档",
		"message": msg,
		"icon": "save",
		"input": {"text": default_title, "placeholder": "输入存档名称"},
		"buttons": [
			{"id": "cancel", "text": "取消", "icon": "close"},
			{"id": "ok", "text": "确定保存", "icon": "save", "kind": "primary"}
		]
	}, func(custom_title: String):
		Game.save_slot(slot_num, custom_title.strip_edges())
		UiHub.sfx("save")
		refresh(false)
	)

func _rename_slot(s: Dictionary) -> void:
	var slot_num := int(s.slot)
	var cur_title := str(s.get("title", ""))
	root.prompt({
		"title": "修改存档名称",
		"message": "修改存档位 %02d 的标题：" % slot_num,
		"icon": "docs",
		"input": {"text": cur_title, "placeholder": "输入新的存档名称"},
		"buttons": [
			{"id": "cancel", "text": "取消", "icon": "close"},
			{"id": "ok", "text": "保存名称", "icon": "docs", "kind": "primary"}
		]
	}, func(new_title: String):
		new_title = new_title.strip_edges()
		if new_title == "": return
		Game.rename_slot(slot_num, new_title)
		UiHub.sfx("save")
		refresh(false)
	)

func _delete(s: Dictionary) -> void:
	var d = root.dialog({"title": "删除存档", "message": "删除后无法恢复。", "icon": "warn", "tone": "danger", "buttons": [{"id": "cancel", "text": "取消", "icon": "close"}, {"id": "ok", "text": "删除", "icon": "trash", "kind": "primary"}]})
	d.chosen.connect(func(id): if id == "ok": Game.delete_slot(int(s.slot)); UiHub.sfx("delete"))

func _import() -> void:
	if OS.has_feature("web") and not Game.demo: Game.import_save(""); return
	if OS.has_feature("web"): toast("网页版暂不支持选择本地文件，请用电脑版导入", "info"); return
	var fd := FileDialog.new(); fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE; fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.json,*.jsonl ; 游戏存档与酒馆记录 (.json / .jsonl)"]); fd.use_native_dialog = true
	add_child(fd)
	fd.file_selected.connect(func(path): Game.import_save(path); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered(Vector2i(900, 600))
