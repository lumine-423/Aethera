extends "res://scripts/ui/ui_screen.gd"
## 剧情 hub: continue the current story, start a new one, saves, event archive, and the separate
## 改原文 page. Everything reads the real chat through Game (no sample chapters).

func build() -> void:
	chrome("剧情")
	decor(31, Rect2(Vector2.ZERO, size), 0.7)
	var has: bool = Game.has_story()
	var h: Dictionary = Game.hero()
	var hero := plate(Rect2(120, 150, 1100, 420), {"shape": "cut", "slant": 60, "corner": "tr", "hatch": true, "dots": true}, "c", 0.05)
	var art := W.Portrait.new(); art.kind = "scene"; art.frame = false
	put(art, Rect2(560, 30, 500, 280), "c", -1.0, hero)
	var bg: Dictionary = Data.scene_for("", h.get("当前地点", ""), h.get("时间", ""))
	if not bg.is_empty(): art.set_texture(load(bg.res), false)
	if has:
		text("当前故事", Rect2(60, 40, 200, 40), 22, "accent", 800, "c", hero)
		var ren := btn("命名故事", "docs", "chip", Rect2(290, 32, 196, 48), func(): _rename_story(), "c", -1.0, hero, 19)
		ren.name = "RenameStory"
		text(String(Game.persona.get("name", "未署名")), Rect2(60, 88, 488, 72), 42, "ink", 900, "c", hero)
		text("%s · %s" % [h.get("当前地点", "—"), h.get("时间", "—")], Rect2(60, 170, 480, 40), 22, "muted", 700, "c", hero)
		text("共 %d 条记录" % Game.messages.size(), Rect2(60, 214, 480, 40), 22, "muted", 700, "c", hero)
		var go := btn("继续阅读", "play", "primary", Rect2(60, 300, 460, 92), func(): root.go("story", {}, "wipe"), "c", -1.0, hero, 32)
		go.arrow = true; go.name = "ContinueStory"; go.call_deferred("grab_focus")
	else:
		text("还没有开始故事", Rect2(60, 84, 480, 80), 44, "ink", 900, "c", hero)
		text("选择出身、写下你的角色，就能开始。", Rect2(60, 170, 480, 60), 22, "muted", 700, "c", hero)
		var go2 := btn("新的开始", "star4", "primary", Rect2(60, 300, 460, 92), func(): _new(), "c", -1.0, hero, 32)
		go2.arrow = true; go2.name = "NewStory"
	var tiles := [
		["新的开始", "重新选择出身与角色", "star4", func(): _new()],
		["存档与读档", "多个存档位、分支与导入导出", "save", func(): root.go("saves", {"mode": "save" if has else "load"})],
		["事件档案", "进行中、即将发生、已归档", "bookmark", func(): root.go("events")],
		["改原文", "单独修改任意一条的原文", "docs", func(): root.go("edit")],
	]
	for i in range(tiles.size()):
		var t: Array = tiles[i]
		var r := Rect2(1260 - (i % 2) * 0, 150 + i * g(210), 600, 190)
		var card := Btn.new(); card.variant = "secondary"; card.slant = 40; card.name = "Tile%d" % i
		put(card, r, "c", 0.1 + i * 0.06)
		card.pressed.connect(t[3])
		card.disabled = (i == 3 and not has)
		var blk := Plate.new(); blk.shape = "slant"; blk.slant = 40; blk.fill = "block"; blk.fill_alpha = 1.0; blk.border = ""; blk.glass = false; blk.layered = false
		put(blk, Rect2(50, 30, 150, 130), "c", -1.0, card)
		var ic := Icon.new(); ic.icon = t[2]; ic.role = "on_block"; ic.accent_role = "accent"; ic.hole_role = "block"
		put(ic, Rect2(40, 26, 76, 76), "c", -1.0, blk)
		text(t[0], Rect2(230, 40, 340, 60), 36, "ink", 850, "c", card)
		text(t[1], Rect2(230, 106, 340, 40), 20, "muted", 600, "c", card)
	text("演示模式：剧情回复是格式样例，接入AI后换成真正的故事。" if Game.demo else "", Rect2(120, 620, 1100, 40), 20, "muted", 600)

func _new() -> void:
	if not Game.has_story():
		if Game.connection.get("has_key", false): root.go("origin", {}, "wipe")
		else: root.go("connect", {"next": "origin", "first": true}, "wipe")
		return
	var d = root.dialog({"title": "新的开始", "message": "开始新的进度。自动存档会被新进度覆盖，手动存档不受影响。", "icon": "star4", "buttons": [{"id": "cancel", "text": "取消", "icon": "close"}, {"id": "ok", "text": "开始", "icon": "play", "kind": "primary"}]})
	var on_choice := func(id: String) -> void:
		if id == "ok":
			if Game.connection.get("has_key", false): root.go("origin", {}, "wipe")
			else: root.go("connect", {"next": "origin", "first": true}, "wipe")
	d.chosen.connect(on_choice)

func _rename_story() -> void:
	var cur_name := String(Game.persona.get("name", "未署名"))
	root.prompt({
		"title": "命名当前故事",
		"message": "为当前故事与主角设定名字（保存后存档与档案将同步更新）：",
		"icon": "docs",
		"input": {"text": cur_name, "placeholder": "输入故事或主角名称"}
	}, func(new_name: String):
		new_name = new_name.strip_edges()
		if new_name == "": return
		var p: Dictionary = Game.persona.duplicate(true)
		p["name"] = new_name
		Game.update_persona(p)
		UiHub.sfx("save")
		refresh(false)
	)
