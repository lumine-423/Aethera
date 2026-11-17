extends RefCounted
const Ui = preload("res://scripts/ui_components.gd")
const Palette = preload("res://scripts/ui_theme.gd")
static func result(app,parent: Node) -> void:
	if app.records.is_empty(): Ui.empty(app,parent,"暂无行动结果","完成一次行动后在这里查看结果。"); return
	var record: Dictionary = app.records[0]
	var columns := Ui.split(app,parent,0.85)
	var actor_id: String = record.get("party",["rin"])[0]
	columns[0].add_child(Ui.art("portrait",500 if not app.compact else 280,actor_id))
	Ui.title(app,columns[1],"行动"+app.outcome_label(record.outcome),app.rules.config.missions.get(record.mission,{}).get("name",record.mission))
	var metrics := HBoxContainer.new(); columns[1].add_child(metrics)
	Ui.metric(app,metrics,str(record.rounds),"回合"); Ui.metric(app,metrics,str(record.actions),"行动次数")
	var panel = app._panel(columns[1],"队伍状态")
	for member in app.rules.state.allies: panel.add_child(app._label("%s   生命 %d / %d" % [member.name,member.hp,member.max_hp]))
	panel.add_child(app._label("结果已记录。本次演练不产生正式奖励或永久剧情后果。",16,Palette.color("muted")))
	columns[1].add_child(Ui.primary(app,"查看详细战报    →",func(): app.selected_report = 0; app._navigate("report_detail")))
	columns[1].add_child(app._button("重新准备",func(): app.mission = record.mission; app._navigate("prepare")))
	columns[1].add_child(app._button("返回行动室",func(): app._navigate("home")))

static func listing(app,parent: Node) -> void:
	Ui.title(app,parent,"行动战报","保留最近 20 次行动的结果与过程。")
	if app.records.is_empty():
		Ui.empty(app,parent,"战报尚未写下","完成或撤退后，行动会留存在这里。")
		parent.add_child(Ui.primary(app,"前往作战终端",func(): app._navigate("missions")))
	for index in range(app.records.size()):
		var selected: int = index
		var record: Dictionary = app.records[index]
		var name: String = app.rules.config.missions.get(record.mission,{}).get("name",record.mission)
		parent.add_child(Ui.tile(app,name+"  /  "+app.outcome_label(record.outcome),"%d 回合 · %d 次行动" % [record.rounds,record.actions],func(): app.selected_report = selected; app._navigate("report_detail")))

static func detail(app,parent: Node) -> void:
	if app.selected_report < 0 or app.selected_report >= app.records.size(): Ui.empty(app,parent,"战报不存在","请返回列表选择其他战报。"); return
	var record: Dictionary = app.records[app.selected_report]
	Ui.title(app,parent,"战报详情",app.rules.config.missions.get(record.mission,{}).get("name",record.mission)+" / "+app.outcome_label(record.outcome))
	var columns := Ui.split(app,parent,0.6)
	var info = app._panel(columns[0],"行动摘要")
	var metrics := HBoxContainer.new(); info.add_child(metrics)
	Ui.metric(app,metrics,str(record.rounds),"回合"); Ui.metric(app,metrics,str(record.actions),"行动次数")
	for id in record.get("party",[]): info.add_child(app._label(app.actor_catalog.actors.get(id,{}).get("name",id),22))
	info.add_child(Ui.art("sigil",150))
	var panel = app._panel(columns[1],"行动过程")
	for line in record.get("log",[]): panel.add_child(app._label(str(line),17,Palette.color("muted")))
	if not record.has("log"): panel.add_child(app._label("旧版战报只保存摘要。",17))
