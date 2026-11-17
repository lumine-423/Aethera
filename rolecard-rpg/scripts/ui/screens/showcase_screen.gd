extends "res://scripts/ui/ui_screen.gd"
## 界面总览: review launcher for every screen, state and overlay. Not part of the player flow
## (reached from the title menu); remove the title entry before release if wanted.

func build() -> void:
	chrome("界面总览")
	decor(5, Rect2(Vector2.ZERO, size), 0.6)
	var groups := [
		["主流程", [["标题", "title", {}], ["标题 · 解锁", "title", {"locked": true}], ["载入", "loading", {"next": "showcase"}], ["主页", "home", {}], ["存档 / 读档", "saves", {"mode": "save"}]]],
		["剧情", [["剧情目录", "story_hub", {}], ["剧情事件", "story", {"chapter": "ch1"}], ["剧情回放", "story", {"replay": true}]]],
		["资料库", [["资料库", "archive", {}], ["角色档案", "characters", {}], ["插画鉴赏", "gallery", {}], ["世界书", "settings", {"tab": "worldbook"}]]],
		["世界与开局", [["出身选择", "origin", {}], ["角色创建", "create", {"origin": "sereth"}], ["世界地图", "map", {}], ["事件档案", "events", {}], ["看板交谈", "talk", {}], ["艾瑟拉的忠告", "help", {}]]],
		["仓库与制作", [["仓库", "inventory", {}], ["刻印制作", "crafting", {}]]],
		["设置", [["显示", "settings", {"tab": "display"}], ["声音", "settings", {"tab": "audio"}], ["API连接", "settings", {"tab": "ai"}], ["存档与恢复", "settings", {"tab": "backup"}]]],
	]
	var y := 128.0
	var gi := 0
	for group in groups:
		header(group[0], Rect2(90, y, 1700, 44), 26, "c", null, gi * 0.04)
		y += 48
		var x := 110.0
		for entry in group[1]:
			var e: Array = entry
			var b := btn(e[0], "", "secondary", Rect2(x, y, 222, 62), func(): root.go(e[1], e[2]), "c", gi * 0.04 + 0.05, null, 23)
			b.arrow = true
			x += 238
		y += 82; gi += 1
	header("弹窗与反馈", Rect2(90, y, 1700, 44), 26)
	y += 48
	var x2 := 90.0
	var pops := [
		["行动暂停", func(): root.dialog(_pause_spec())],
		["确认撤退", func(): root.dialog({"title": "确认撤退", "message": "撤退后将结束本次行动。", "icon": "warn", "tone": "danger", "buttons": [{"id": "cancel", "text": "继续行动", "icon": "play"}, {"id": "ok", "text": "确认撤退", "icon": "warn_fill", "kind": "primary"}]})],
		["连接中断", func(): root.error("network")],
		["资源未载入", func(): root.error("resource")],
		["未能保存", func(): root.error("save")],
		["获得物品", func(): root.reward([{"icon": "item_prism", "count": 120}, {"icon": "item_chip", "count": 6}, {"icon": "item_tetra", "count": 3}])],
		["提示条", func(): toast("已保存到存档 1", "save")],
	]
	for p in pops:
		var item: Array = p
		btn(item[0], "", "chip", Rect2(x2, y, 230, 64), item[1], "c", -1.0, null, 22).center_text = true
		x2 += 244

func _pause_spec() -> Dictionary:
	return {"title": "行动暂停", "buttons": [{"id": "resume", "text": "继续行动", "icon": "play", "kind": "primary"}, {"id": "settings", "text": "设置", "icon": "gear"}, {"id": "save", "text": "保存并返回", "icon": "docs"}], "cancel_id": "resume"}
