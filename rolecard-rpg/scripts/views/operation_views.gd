extends RefCounted
const Ui = preload("res://scripts/ui_components.gd")
const Palette = preload("res://scripts/ui_theme.gd")
static func listing(app,parent: Node) -> void:
	Ui.title(app,parent,"选择行动","观察敌方配置，再决定你的出战组合。")
	var columns := Ui.split(app,parent)
	var index := 0
	for id in app.rules.config.missions:
		var mission_id: String = id
		var definition: Dictionary = app.rules.config.missions[id]
		var panel = app._panel(columns[index],definition.name,definition.description)
		panel.add_child(Ui.art("mission",220 if not app.compact else 150))
		var stats := HBoxContainer.new(); panel.add_child(stats)
		Ui.metric(app,stats,str(definition.enemies.size()),"敌方单位")
		Ui.metric(app,stats,"1—2","出战人数")
		panel.add_child(app._label(" / ".join(definition.enemies.map(func(enemy): return enemy.name)),17,Palette.color("muted")))
		panel.add_child(Ui.primary(app,"查看行动情报    →",func(): app.mission = mission_id; app._navigate("mission_detail")))
		index += 1

static func detail(app,parent: Node) -> void:
	var definition: Dictionary = app.rules.config.missions[app.mission]
	Ui.title(app,parent,definition.name,"行动情报")
	var columns := Ui.split(app,parent,1.15)
	columns[0].add_child(Ui.art("mission",310 if not app.compact else 180))
	var brief = app._panel(columns[0],"任务目标",definition.description)
	brief.add_child(app._label("击败全部敌方单位。演练可撤退，没有正式奖励或剧情后果。",17,Palette.color("muted")))
	var panel = app._panel(columns[1],"敌方配置")
	for enemy in definition.enemies:
		panel.add_child(app._label(enemy.name,24))
		var row := HBoxContainer.new(); panel.add_child(row)
		Ui.metric(app,row,str(enemy.hp),"生命")
		Ui.metric(app,row,str(enemy.damage),"普通伤害")
	panel.add_child(app._label("偶数回合发动双倍伤害重击。倒地敌人停止行动。",17,Palette.color("warning")))
	columns[1].add_child(Ui.primary(app,"编队与准备    →",func(): app._navigate("prepare")))

static func prepare(app,parent: Node) -> void:
	var definition: Dictionary = app.rules.config.missions[app.mission]
	Ui.title(app,parent,"出击准备",definition.name)
	var columns := Ui.split(app,parent,1.45)
	var squad := HBoxContainer.new(); squad.add_theme_constant_override("separation",14); columns[0].add_child(squad)
	for id in app.party:
		var card := Ui.portrait_card(app,squad,id,280 if not app.compact else 190)
		card.add_child(app._label(app.rules.config.actors[id].name,26)); card.add_child(Ui.chip(app,app.rules.config.actors[id].role))
	columns[0].add_child(app._button("调整编队",func(): app._navigate("party")))
	var panel = app._panel(columns[1],"行动确认",definition.description)
	panel.add_child(app._label("每名存活队友每回合行动一次，之后敌方行动。",18))
	panel.add_child(app._label("观察重击预告，合理安排防御、治疗和能量。",17,Palette.color("muted")))
	panel.add_child(Ui.art("sigil",108))
	panel.add_child(Ui.primary(app,"确认出击    →",app._request_begin,app.read_only))

