extends RefCounted
const Ui = preload("res://scripts/ui_components.gd")
const Palette = preload("res://scripts/ui_theme.gd")
static func settings(app,parent: Node) -> void:
	Ui.title(app,parent,"设置与恢复","按照你的习惯调整行动室。")
	var columns := Ui.split(app,parent)
	var panel = app._panel(columns[0],"显示与反馈")
	panel.add_child(app._label("界面配色",20))
	panel.add_child(app._button("哑光日间  →  切换夜间" if Palette.mode == "day" else "暖色夜间  →  切换日间",app._toggle_appearance))
	var large := CheckButton.new(); large.text = "放大界面文字"; large.button_pressed = app.settings.large_text; large.custom_minimum_size.y = 48; large.toggled.connect(func(value): app.settings.large_text = value; app._save(); app._render()); panel.add_child(large)
	var motion := CheckButton.new(); motion.text = "减弱动态效果"; motion.button_pressed = not app.settings.motion; motion.custom_minimum_size.y = 48; motion.toggled.connect(func(value): app.settings.motion = not value; app._save()); panel.add_child(motion)
	panel.add_child(app._label("音效音量",17))
	var volume := HSlider.new(); volume.min_value = 0; volume.max_value = 1; volume.step = 0.05; volume.value = app.settings.sfx_volume; volume.custom_minimum_size.y = 44; volume.value_changed.connect(app._set_volume); panel.add_child(volume)
	panel.add_child(app._button("全屏 / 退出全屏",app._fullscreen))
	var recovery = app._panel(columns[1],"本机恢复点","演练记录可导出备份；角色卡正式进度由宿主负责。")
	recovery.add_child(Ui.primary(app,"导出备份",app._export_save))
	recovery.add_child(app._button("导入备份",app._pick_import,app.read_only))
	recovery.add_child(app._button("恢复上一好档",app._restore_backup,app.read_only))
	recovery.add_child(app._label("清除恢复点会结束本机未完成的行动，请先保存需要的备份。",16,Palette.color("warning")))
	recovery.add_child(app._button("清除本机恢复点",app._request_clear,app.read_only))
	columns[0].add_child(app._button("操作说明",func(): app._navigate("help")))

static func help(app,parent: Node) -> void:
	Ui.title(app,parent,"操作说明","从一次行动开始，熟悉你的队伍。")
	var grid := GridContainer.new(); grid.columns = 1 if app.compact else 2; grid.add_theme_constant_override("h_separation",20); grid.add_theme_constant_override("v_separation",20); parent.add_child(grid)
	for pair in [["行动顺序","每名存活队友每回合行动一次，然后存活敌方行动。确认前可取消选择，不消耗资源。"],["目标与资源","治疗不复活倒地者。护盾先吸收伤害；防御使敌方阶段伤害减半。能量最多100，增益按技能说明消耗。"],["中断与恢复","失焦和恢复后暂停。Esc优先关闭弹层，再取消目标选择或返回上一页；战斗中打开暂停。"],["保存边界","导入先校验并确认，原异常文件不会默默覆盖。另一个窗口正在使用同一份记录时，本窗口只读。"]]:
		app._panel(grid,pair[0],pair[1])
