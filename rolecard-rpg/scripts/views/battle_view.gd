extends RefCounted
const Field = preload("res://scripts/views/battlefield_view.gd")
const Ui = preload("res://scripts/ui_components.gd")
const Palette = preload("res://scripts/ui_theme.gd")
static func unit_card(app,parent: Node,member: Dictionary,ally: bool) -> void:
	var suffix := " · 倒地" if member.hp<=0 else ""
	if ally and member.id in app.rules.state.acted: suffix += " · 已行动"
	var card = app._panel(parent,member.name+suffix)
	var bar := ProgressBar.new(); bar.max_value = member.max_hp; bar.value = member.hp; bar.custom_minimum_size.y = 7; bar.show_percentage = false; card.add_child(bar)
	var fill := StyleBoxFlat.new(); fill.bg_color = Palette.color("ally" if ally else "enemy"); bar.add_theme_stylebox_override("fill",fill)
	var bg := StyleBoxFlat.new(); bg.bg_color = Palette.color("soft"); bar.add_theme_stylebox_override("background",bg)
	card.add_child(app._label("生命 %d / %d" % [member.hp,member.max_hp],16))
	if ally:
		card.add_child(app._label("能量 %d   护盾 %d" % [member.energy,member.shield],15,Palette.color("ally")))
		var flags := "鸟羽" if member.form=="released" else "基础"
		if member.guard: flags += " / 防御"
		if member.buff>0: flags += " / 伤害+%d" % member.buff
		card.add_child(app._label(flags,14,Palette.color("muted")))
		var id: String = member.id
		var b: Button = app._button("选择行动" if id!=app.selected_actor else "当前角色",func(): app.selected_actor = id; app.selected_action = ""; app.selected_target = ""; app._render(),app.paused or app.busy or app.read_only or member.hp<=0 or id in app.rules.state.acted)
		if id == app.selected_actor: Palette.apply_button(b,"selected")
		card.add_child(b)
	elif member.hp>0:
		var alive: Array = app.rules.state.allies.filter(func(ally_unit): return ally_unit.hp>0)
		var target_name: String = alive[(app.rules.state.round-1)%alive.size()].name if not alive.is_empty() else "—"
		card.add_child(app._label("%s %d → %s" % ["重击" if app.rules.state.round%2==0 else "攻击",member.damage*(2 if app.rules.state.round%2==0 else 1),target_name],16,Palette.color("enemy")))
	else: card.add_child(app._label("已失去行动能力",16,Palette.color("muted")))

static func build(app,parent: Node) -> void:
	Ui.title(app,parent,app.rules.config.missions[app.rules.state.mission].name,"第 %d 回合 · 观察敌方意图后行动" % app.rules.state.round)
	var system := HFlowContainer.new(); system.add_theme_constant_override("h_separation",10); parent.add_child(system)
	system.add_child(app._button("继续行动" if app.paused else "暂停",app._pause_menu))
	system.add_child(app._button("保存并返回",app._save_and_leave,app.busy or app.read_only))
	system.add_child(app._button("撤退",app._retreat,app.busy or app.read_only))
	if app.busy: system.add_child(app._button("跳过反馈",app._skip_presentation))
	if app.paused: parent.add_child(app._label("已暂停，按继续恢复操作。",19,Palette.color("warning")))
	var columns := Ui.split(app,parent,1.6)
	var stage: VBoxContainer = columns[0]; var command_column: VBoxContainer = columns[1]
	var enemies := HBoxContainer.new(); enemies.add_theme_constant_override("separation",12); stage.add_child(enemies)
	for member in app.rules.state.enemies: unit_card(app,enemies,member,false)
	app.battlefield = Field.new(); app.battlefield.custom_minimum_size.y = 170 if app.compact else 225; stage.add_child(app.battlefield); app.battlefield.set_state(app.rules.state,app.selected_actor)
	var allies := HBoxContainer.new(); allies.add_theme_constant_override("separation",12); stage.add_child(allies)
	for member in app.rules.state.allies: unit_card(app,allies,member,true)
	var actor: Dictionary = app.rules.unit(app.selected_actor)
	var commands = app._panel(command_column,actor.name+"的行动","选择指令 → 选择目标 → 确认")
	var action_grid := GridContainer.new(); action_grid.columns = 2; action_grid.add_theme_constant_override("h_separation",8); action_grid.add_theme_constant_override("v_separation",8); commands.add_child(action_grid)
	for key in app.rules.config.actors[app.selected_actor].actions:
		var action_id: String = key
		var move: Dictionary = app.rules.action(app.selected_actor,key)
		var reason: String = app.rules.reason(app.selected_actor,key)
		var button: Button = app._button(move.name+"\n%d 能量" % move.cost,func(): app._select_action(action_id),app.paused or app.busy or app.read_only or not reason.is_empty())
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = move.hint+("\n"+reason if not reason.is_empty() else "")
		if app.selected_action == key: Palette.apply_button(button,"selected")
		action_grid.add_child(button)
	if not app.selected_action.is_empty():
		var move: Dictionary = app.rules.action(app.selected_actor,app.selected_action)
		commands.add_child(app._label(move.hint,16,Palette.color("muted")))
		var choices := HFlowContainer.new(); commands.add_child(choices)
		for id in app.rules.targets(app.selected_actor,app.selected_action):
			var target_id: String = id
			var title: String = "全体存活队友" if id=="all_allies" else app.rules.unit(id).name
			choices.add_child(app._button(("✓ " if app.selected_target==id else "")+title,func(): app.selected_target = target_id; app._render(),app.paused or app.busy or app.read_only))
		commands.add_child(Ui.primary(app,"确认行动",app._commit,app.paused or app.busy or app.read_only or app.selected_target.is_empty()))
		commands.add_child(app._button("取消选择",func(): app.selected_action = ""; app.selected_target = ""; app._render(),app.busy))
	var log_panel = app._panel(parent,"最新战况")
	for index in range(maxi(0,app.rules.state.log.size()-3),app.rules.state.log.size()): log_panel.add_child(app._label(app.rules.state.log[index],16,Palette.color("muted")))
