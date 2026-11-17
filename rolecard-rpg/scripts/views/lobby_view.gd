extends RefCounted
const Ui = preload("res://scripts/ui_components.gd")
const Palette = preload("res://scripts/ui_theme.gd")
static func build(app, parent: Node) -> void:
	var columns := Ui.split(app,parent,1.4)
	var left: VBoxContainer = columns[0]; var right: VBoxContainer = columns[1]
	var hero := Control.new(); hero.custom_minimum_size.y = 390 if app.compact else 585
	hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hero.clip_contents = true; left.add_child(hero)
	var portrait := Ui.art("portrait",0,"rin"); portrait.wash = true
	hero.add_child(portrait); portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var caption := PanelContainer.new(); hero.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -118; caption.offset_left = 20; caption.offset_right = -38; caption.offset_bottom = -20
	var style := Palette.panel(); style.bg_color = Color(Palette.color("surface"),0.96); style.border_width_left = 4; style.border_color = Palette.color("accent"); style.skew = Vector2(-0.06,0); caption.add_theme_stylebox_override("panel",style)
	var text := VBoxContainer.new(); caption.add_child(text)
	var name_row := HBoxContainer.new(); text.add_child(name_row)
	name_row.add_child(app._label("凛零",36)); name_row.add_child(Ui.chip(app,"突击 / 解放"))
	text.add_child(app._label("安静的锋芒，等待下一次出击。",16,Palette.color("muted")))
	Ui.title(app,right,"行动室","整备已就绪。选择你的下一步。")
	right.add_child(Ui.tile(app,"作战终端","选择任务，开始协同行动",func(): app._navigate("missions"),true,185))
	if not app.saved_battle.is_empty():
		var name: String = app.rules.config.missions.get(app.saved_battle.get("setup",{}).get("mission",""),{}).get("name","未结束行动")
		right.add_child(app._button("继续 · "+name,app._continue,app.read_only))
	var team = app._panel(right,"出战编队")
	var names := HBoxContainer.new(); names.add_theme_constant_override("separation",12); team.add_child(names)
	for id in app.party:
		var row := HBoxContainer.new(); row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; names.add_child(row)
		var photo := Ui.art("avatar",62,id); photo.custom_minimum_size.x = 62; photo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN; row.add_child(photo)
		row.add_child(app._label(app.rules.config.actors[id].name,20))
	team.add_child(app._button("调整编队    ↗",func(): app._navigate("party")))
	right.add_child(Ui.tile(app,"行动战报","回看每一次行动",func(): app._navigate("records"),false,100))
	var bottom := GridContainer.new(); bottom.columns = 1 if app.compact else 3; bottom.add_theme_constant_override("h_separation",16); bottom.add_theme_constant_override("v_separation",12); parent.add_child(bottom)
	for item in [["roster","角色档案","17 位角色 · 查看能力与形态"],["settings","设置与恢复","显示、声音与本机备份"],["help","操作说明","行动顺序与协同规则"]]:
		var destination: String = item[0]
		bottom.add_child(Ui.tile(app,item[1],item[2],func(): app._navigate(destination)))
