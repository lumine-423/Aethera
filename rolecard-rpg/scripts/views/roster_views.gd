extends RefCounted
const Ui = preload("res://scripts/ui_components.gd")
const Palette = preload("res://scripts/ui_theme.gd")
static func roster(app,parent: Node) -> void:
	Ui.title(app,parent,"角色档案","17 位来源角色 · 3 位已配置演练能力")
	var grid := GridContainer.new(); grid.columns = 2 if app.compact else (3 if app.size.x < 1100 else 4)
	grid.add_theme_constant_override("h_separation",16); grid.add_theme_constant_override("v_separation",16); parent.add_child(grid)
	for id in app.actor_catalog.actors:
		var actor_id: String = id
		var definition: Dictionary = app.actor_catalog.actors[id]
		var playable: bool = app.rules.config.actors.has(id)
		var panel := Ui.portrait_card(app,grid,id,180 if app.compact else 220)
		panel.add_child(app._label(definition.name,25))
		panel.add_child(Ui.chip(app,"可参与演练" if playable else "档案已收录",playable))
		panel.add_child(app._button("查看详情  ↗",func(): app.selected_profile = actor_id; app._navigate("actor_detail")))

static func detail(app,parent: Node) -> void:
	var id: String = app.selected_profile
	var definition: Dictionary = app.actor_catalog.actors[id]
	Ui.title(app,parent,definition.name,"角色档案")
	var columns := Ui.split(app,parent,0.9)
	columns[0].add_child(Ui.art("portrait",520 if not app.compact else 360,id))
	var personality: Dictionary = app.personality.get(id,{})
	var profile = app._panel(columns[1],"角色气质",personality.get("tone","待核对来源设定"))
	var labels: Array = []
	for form in definition.forms.values(): labels.append(form.label)
	profile.add_child(app._label("形态："+" / ".join(labels),17))
	if app.rules.config.actors.has(id):
		var combat: Dictionary = app.rules.config.actors[id]
		var panel = app._panel(columns[1],"演练能力",combat.role+"  ·  生命%d" % combat.hp)
		for move in combat.actions.values():
			panel.add_child(app._label(move.name,20)); panel.add_child(app._label(move.hint,16,Palette.color("muted")))
		columns[1].add_child(Ui.primary(app,"移出编队" if id in app.party else "加入编队",func(): app._toggle_member(id),app.read_only or (id not in app.party and app.party.size()>=2)))
	else: profile.add_child(app._label("战斗规则待配置，当前仅可查看档案。",17,Palette.color("muted")))

static func squad(app,parent: Node) -> void:
	Ui.title(app,parent,"出战编队  %d / 2" % app.party.size(),"至少保留一人。调整仅用于下一次行动。")
	var grid := GridContainer.new(); grid.columns = 1 if app.compact else 3; grid.add_theme_constant_override("h_separation",18); grid.add_theme_constant_override("v_separation",18); parent.add_child(grid)
	for id in app.rules.config.actors:
		var actor_id: String = id
		var definition: Dictionary = app.rules.config.actors[id]
		var panel := Ui.portrait_card(app,grid,id,220)
		panel.add_child(Ui.chip(app,"已编入" if id in app.party else "待命",id in app.party))
		panel.add_child(app._label(definition.name,30)); panel.add_child(app._label(definition.role,16,Palette.color("muted")))
		var row := HBoxContainer.new(); panel.add_child(row)
		Ui.metric(app,row,str(definition.hp),"生命"); Ui.metric(app,row,str(definition.energy),"初始能量")
		panel.add_child(Ui.primary(app,"移出编队" if id in app.party else "加入编队",func(): app._toggle_member(actor_id),app.read_only or (id not in app.party and app.party.size()>=2)))
		panel.add_child(app._button("角色详情",func(): app.selected_profile = actor_id; app._navigate("actor_detail")))
	parent.add_child(Ui.primary(app,"前往出击准备    →",func(): app._navigate("prepare")))

