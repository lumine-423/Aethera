extends Control

const Session = preload("res://scripts/battle_session.gd")
const Stage = preload("res://scripts/pixel_stage.gd")
var session = Session.new()
var bridge: Variant
var title: Label
var state_label: Label
var feedback: Label
var attack: Button
var guard: Button
var liberate: Button
var ultimate: Button
var cancel_button: Button
var pause_button: Button
var stage: Control
var player: AudioStreamPlayer
var pending: Dictionary = {}
var animation_left := 0.0
var poll_left := 0.0
var paused := false
var native_sequence := 0

func _ready() -> void:
	_build_ui()
	if OS.has_feature("web"):
		bridge = JavaScriptBridge.get_interface("rolecardRpgBridge")
		if bridge != null:
			_emit({"type": "engine_ready", "content_version": Session.CONTENT_VERSION})
		else:
			feedback.text = "未找到卡片桥接。请从技术验证宿主页打开。"
	_refresh()

func _build_ui() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 19
	if ResourceLoader.exists("res://assets/fonts/NotoSansSC.ttf"):
		ui_theme.default_font = load("res://assets/fonts/NotoSansSC.ttf")
	theme = ui_theme
	var background := ColorRect.new()
	background.color = Color("101722")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	scroll.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	title = _label("等待角色卡战斗请求", 26)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(title)
	var notice := _label("技术验证 · 各角色/形态均需待机；当前为凛零基础修稿。解放/飞星为规则占位演出，数值未定稿", 16, Color("aebaca"))
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(notice)
	stage = Stage.new()
	stage.custom_minimum_size = Vector2(0, 300)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(stage)
	state_label = _label("", 20)
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(state_label)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.add_theme_constant_override("h_separation", 12)
	actions.add_theme_constant_override("v_separation", 10)
	column.add_child(actions)
	attack = _button("普通攻击", func(): _act("attack"))
	guard = _button("防御", func(): _act("guard"))
	liberate = _button("解放 · 测试消耗20", func(): _act("liberate"))
	ultimate = _button("飞星 · 测试消耗60", func(): _act("ultimate"))
	cancel_button = _button("取消验证", _cancel)
	for button in [attack, guard, liberate, ultimate, cancel_button]:
		actions.add_child(button)
	var missing := _label("技能1/技能2、受击、倒地、结算及鸟羽全套美术待制作；当前靶和效果均为测试占位。", 15, Color("aebaca"))
	missing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(missing)
	var system_row := HFlowContainer.new()
	system_row.add_theme_constant_override("separation", 12)
	system_row.add_theme_constant_override("h_separation", 12)
	system_row.add_theme_constant_override("v_separation", 10)
	column.add_child(system_row)
	pause_button = _button("暂停", _toggle_pause)
	system_row.add_child(pause_button)
	system_row.add_child(_button("跳过当前演出", _finish_presentation))
	system_row.add_child(_button("测试音效", _play_sound))
	if not OS.has_feature("web"):
		system_row.add_child(_button("本机手动入口", func(): _native_start("manual")))
		system_row.add_child(_button("本机剧情入口", func(): _native_start("story")))
	feedback = _label("准备就绪后，由外层板块按钮或剧情指令发送同一种任务请求。", 17, Color("c4d0de"))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(feedback)
	player = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/audio/probe-confirm.wav"):
		player.stream = load("res://assets/audio/probe-confirm.wav")
	player.volume_db = -12.0
	add_child(player)

func _label(text_value: String, font_size: int, color: Color = Color("edf1f6")) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text_value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(116, 44)
	button.pressed.connect(action)
	return button

func _process(delta: float) -> void:
	poll_left -= delta
	if bridge != null and poll_left <= 0.0:
		poll_left = 0.1
		var raw: String = bridge.drain_commands()
		var requests: Variant = JSON.parse_string(raw)
		if requests is Array:
			for command in requests:
				if command is Dictionary:
					if command.get("type") == "restore_task":
						_restore(command.get("checkpoint", {}))
					else:
						_start(command.get("request", {}))
	if animation_left > 0.0 and not paused:
		animation_left -= delta
		if animation_left <= 0.0:
			_finish_presentation()

func _start(request: Dictionary) -> void:
	var response: Dictionary = session.start(request)
	if not response["ok"]:
		feedback.text = "请求未执行：" + str(response["error"])
		_emit({"type": "request_rejected", "request_id": request.get("request_id", ""), "reason": response["error"]})
		return
	_emit({"type": "task_ack", "request_id": request["request_id"], "duplicate": response.get("duplicate", false)})
	if response.has("result"):
		_emit({"type": "task_result", "result": response["result"]})
		feedback.text = "这是已经结束的同一请求，已回传原结果。"
		return
	if not response.get("duplicate", false):
		paused = false
		stage.set_paused(false)
		feedback.text = "同一测试任务已从%s入口进入。" % ("剧情" if request["source"] == "story" else "主动")
	else:
		feedback.text = "重复请求已识别，没有重置战斗。"
	_refresh()
	if not response.get("duplicate", false):
		_emit_checkpoint()
		attack.grab_focus()

func _restore(saved: Dictionary) -> void:
	var response: Dictionary = session.restore_checkpoint(saved)
	if not response.get("ok", false):
		feedback.text = "恢复未执行：" + str(response.get("error"))
		_emit({"type": "request_rejected", "reason": response.get("error")})
		return
	_emit({"type": "task_ack", "request_id": session.current["request_id"], "restored": true})
	if response.has("result"):
		_emit({"type": "task_result", "result": response["result"]})
		session.clear_finished()
		feedback.text = "已重建结束状态，回传同一结果供宿主去重。"
	else:
		paused = true
		stage.set_paused(true)
		feedback.text = "局内操作已恢复，按“继续”恢复操作。"
	_refresh()

func _emit_checkpoint() -> void:
	var saved: Dictionary = session.checkpoint()
	if not saved.is_empty():
		_emit({"type": "checkpoint", "request_id": saved["request"]["request_id"], "checkpoint": saved})

func _act(command: String) -> void:
	if paused or animation_left > 0.0 or session.current.get("status") != "active":
		return
	var response: Dictionary = session.act(command, session.current["turn"])
	if not response["ok"]:
		feedback.text = "行动未执行：" + str(response["error"])
		return
	pending = response
	_emit_checkpoint()
	animation_left = stage.play_action(command, response.get("presentation", {}))
	feedback.text = "行动已提交一次；跳过/重载保留已提交形态、测试资源和结果。"
	_play_sound()
	_refresh_buttons()

func _finish_presentation() -> void:
	if pending.is_empty():
		return
	animation_left = 0.0
	stage.finish_action()
	if pending.has("result"):
		var result: Dictionary = pending["result"]
		_emit({"type": "task_result", "result": result})
		feedback.text = {"victory": "验证胜利，已回传任务结果。", "defeat": "验证失败，已回传任务结果。", "cancelled": "验证已取消。"}.get(result["outcome"], "任务结束。")
	pending = {}
	_refresh()
	if session.current.get("status") == "finished":
		session.clear_finished()

func _cancel() -> void:
	if animation_left > 0.0:
		return
	var response: Dictionary = session.cancel()
	if response["ok"]:
		pending = response
		_emit_checkpoint()
		_finish_presentation()

func _refresh() -> void:
	if not session.current.is_empty():
		title.text = "测试任务 · 同一战斗，两个入口"
		state_label.text = "测试单位 %d / 10    对手 %d / 9    已提交行动 %d" % [session.current["player_hp"], session.current["enemy_hp"], session.current["turn"]]
		if session.current["content_version"] == Session.CONTENT_VERSION:
			var form_id: String = session.current["form_id"]
			var form: Dictionary = session.catalog.form(session.current["actor_id"], form_id)
			state_label.text += "\n凛零 · %s    测试能量 %d / 100" % [form["label"], session.current["energy"]]
			stage.set_form(form_id)
		else:
			state_label.text += "\n旧版任务按01规则恢复；完成后新开任务可验证解放。"
			stage.set_form("base")
	else:
		state_label.text = "暂无活动任务。正式剧情与角色数据尚未接入。"
	_refresh_buttons()

func _refresh_buttons() -> void:
	var enabled: bool = not paused and animation_left <= 0.0 and session.current.get("status") == "active"
	attack.disabled = not enabled
	guard.disabled = not enabled
	var modern: bool = session.current.get("content_version") == Session.CONTENT_VERSION
	liberate.disabled = not enabled or not modern or session.current.get("form_id") != "base" or session.current.get("energy", 0) < 20
	ultimate.disabled = not enabled or not modern or session.current.get("form_id") != "released" or session.current.get("energy", 0) < 60
	liberate.tooltip_text = "规则测试：消耗20能量和一次行动；鸟羽美术仍待制作。旧任务不改变规则。"
	ultimate.tooltip_text = "规则测试：需要鸟羽形态和60能量；当前伤害8，正式数值待设计。"
	cancel_button.disabled = not enabled
	pause_button.text = "继续" if paused else "暂停"

func _toggle_pause() -> void:
	paused = not paused
	stage.set_paused(paused)
	_refresh_buttons()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(pause_button):
		paused = true
		stage.set_paused(true)
		_refresh_buttons()

func _play_sound() -> void:
	if player.stream != null:
		player.play()

func _native_start(source: String) -> void:
	native_sequence += 1
	_start({"protocol_version": 1, "request_id": "native-%d" % native_sequence,
		"task_id": Session.TASK_ID, "source": source})

func _emit(response: Dictionary) -> void:
	if bridge != null:
		bridge.emit_response(JSON.stringify(response))
	else:
		print("PROBE_EVENT " + JSON.stringify(response))

