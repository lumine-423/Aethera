extends Control
## Floating in-game Story Oracle window (故事神谕悬浮窗) mounted on UiRoot.overlay_layer.
## Draggable in floating mode, supports fullscreen toggle, 6 analysis/mutation modes,
## bidirectional game data channel, remote GitHub update pulling, and mobile portrait input.

const Kit = preload("res://scripts/ui/ui_kit.gd")
const Plate = preload("res://scripts/ui/ui_plate.gd")
const Btn = preload("res://scripts/ui/ui_button.gd")
const Lbl = preload("res://scripts/ui/ui_label.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")

signal closed

var closing := false
var show_settings := false
var show_debug := false
var wb_filter_text := ""
var draft_text := ""

var shade: ColorRect
var win: Control
var header_drag_bar: Control
var scroll: ScrollContainer
var feed_box: VBoxContainer
var input_edit: TextEdit
var send_btn: Button
var expand_btn: Button
var portrait_btn: Button

var _dragging := false
var _drag_off := Vector2.ZERO
var _suppress_auto_portrait := false

func _hub() -> Node:
	return UiHub.story_oracle()

func _ready() -> void:
	name = "StoryOracleOverlay"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_meta("story_oracle_modal", true)
	var h := _hub()
	if not h.changed.is_connected(_rebuild_body): h.changed.connect(_rebuild_body)
	if not h.update_status_changed.is_connected(_rebuild_body): h.update_status_changed.connect(_rebuild_body)
	UiHub.palette_changed.connect(_restyle)
	if not UiHub.review_mode and bool(h.settings.get("auto_check_update", true)) and h.latest_version == "":
		h.check_for_updates()
	_build_shell()

func _exit_tree() -> void:
	var h := _hub()
	if is_instance_valid(h):
		if h.changed.is_connected(_rebuild_body): h.changed.disconnect(_rebuild_body)
		if h.update_status_changed.is_connected(_rebuild_body): h.update_status_changed.disconnect(_rebuild_body)
	if UiHub.mobile_portrait_input:
		UiHub.set_mobile_portrait(false)

func _restyle() -> void:
	_build_shell()

func _host_root() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.get("overlay_layer") != null and n.has_method("open_text_composer"):
			return n
		n = n.get_parent()
	return null

func _win_rect() -> Rect2:
	var h := _hub()
	var full_sz := size if size.x > 100.0 else Vector2(1920, 1080)
	if bool(h.settings.get("fullscreen", false)):
		return Rect2(Vector2(28, 24), full_sz - Vector2(56, 48))
	var fr: Dictionary = h.settings.get("float_rect", {}) if h.settings.get("float_rect") is Dictionary else {}
	var w := clampf(float(fr.get("w", 1040.0)), 640.0, full_sz.x - 48.0)
	var ht := clampf(float(fr.get("h", 830.0)), 520.0, full_sz.y - 48.0)
	var x := clampf(float(fr.get("x", (full_sz.x - w) * 0.5)), 20.0, full_sz.x - w - 20.0)
	var y := clampf(float(fr.get("y", (full_sz.y - ht) * 0.5)), 20.0, full_sz.y - ht - 20.0)
	return Rect2(x, y, w, ht)

func _build_shell() -> void:
	var prev_draft := input_edit.text if is_instance_valid(input_edit) else draft_text
	draft_text = prev_draft
	for c in get_children():
		c.queue_free()

	shade = ColorRect.new()
	shade.size = size
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	Kit.frost(shade)
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			close()
	)
	add_child(shade)

	var wr := _win_rect()
	win = Control.new()
	win.name = "OracleWindow"
	win.position = wr.position
	win.size = wr.size
	win.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(win)

	var bg := Plate.new()
	bg.shape = "cut"; bg.slant = 28; bg.corner = "tr"; bg.hatch = true; bg.fill_alpha = 0.98
	bg.size = wr.size
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	win.add_child(bg)

	_rebuild_contents()

func _rebuild_body() -> void:
	if is_inside_tree() and is_instance_valid(win):
		if is_instance_valid(input_edit): draft_text = input_edit.text
		_rebuild_contents()

func _rebuild_contents() -> void:
	if not is_instance_valid(win): return
	for c in win.get_children():
		if not (c is Plate and c.position == Vector2.ZERO and c.size == win.size):
			c.queue_free()

	var h := _hub()
	var w := win.size.x
	var ht := win.size.y
	var pad := 22.0

	# Draggable Header Bar
	header_drag_bar = Control.new()
	header_drag_bar.name = "OracleHeader"
	header_drag_bar.position = Vector2(0, 0)
	header_drag_bar.size = Vector2(w, 64)
	header_drag_bar.mouse_default_cursor_shape = Control.CURSOR_MOVE if not bool(h.settings.get("fullscreen", false)) else Control.CURSOR_ARROW
	header_drag_bar.gui_input.connect(_on_header_drag)
	win.add_child(header_drag_bar)

	var h_line := Control.new(); h_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h_line.position = Vector2(pad, 62); h_line.size = Vector2(w - pad * 2.0, 2)
	h_line.draw.connect(func(): h_line.draw_line(Vector2.ZERO, Vector2(w - pad * 2.0, 0), UiHub.c("line"), 1.2))
	win.add_child(h_line)

	var ic := Icon.new(); ic.icon = "compass"; ic.role = "accent"
	ic.position = Vector2(pad, 14); ic.size = Vector2(36, 36); ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(ic)

	var ver_tag := "v" + String(h.installed_version) + (" · 有更新!" if h.update_available else "")
	var title_lbl := Lbl.new()
	title_lbl.setup("故事神谕  " + ver_tag, 24, "accent" if h.update_available else "ink", 900)
	title_lbl.position = Vector2(pad + 44.0, 14); title_lbl.size = Vector2(360, 36)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.add_child(title_lbl)

	var hdr_specs := [
		["OracleCloseBtn", "", "close", 52.0, false, "close"],
		["OracleFullBtn", "窗口" if bool(h.settings.get("fullscreen", false)) else "全屏", "monitor", 98.0, bool(h.settings.get("fullscreen", false)), "fullscreen"],
		["OracleSetBtn", "设置" + ("●" if h.update_available else ""), "gear", 110.0, show_settings, "settings"],
		["OracleDebugBtn", "提示词", "docs", 112.0, show_debug, "debug"],
		["OracleClearBtn", "清空", "trash", 96.0, false, "clear"],
	]
	var btn_x := w - pad
	for sp in hdr_specs:
		var bw := float(sp[3])
		var act := String(sp[5])
		btn_x -= bw
		var b := Btn.new(); b.name = String(sp[0])
		b.setup(String(sp[1]), String(sp[2]), "chip" if not bool(sp[4]) else "primary", 16)
		b.selected = bool(sp[4])
		b.position = Vector2(btn_x, 12); b.size = Vector2(bw - 8.0, 40)
		b.pressed.connect(func(): _on_hdr_action(act))
		win.add_child(b)

	# 6 Mode Tabs Row
	var mx := pad
	var mw := (w - pad * 2.0 - 50.0) / float(h.MODES.size())
	for idx in range(h.MODES.size()):
		var md: Dictionary = h.MODES[idx]
		var mid := String(md.id)
		var is_cur: bool = String(h.current_mode) == mid
		var mb := Btn.new(); mb.name = "OracleMode_" + mid
		mb.setup(String(md.label), String(md.icon), "tab", 17)
		mb.selected = is_cur
		mb.position = Vector2(mx, 72); mb.size = Vector2(mw, 46)
		mb.tooltip_text = String(md.hint)
		mb.pressed.connect(func():
			show_settings = false; show_debug = false
			h.set_mode(mid)
		)
		win.add_child(mb)
		mx += mw + 10.0

	# Data Channel Live Strip
	var snap: Dictionary = h.read_channel_snapshot()
	var strip := Plate.new(); strip.shape = "rect"; strip.fill = "surface2"; strip.layered = false
	strip.position = Vector2(pad, 126); strip.size = Vector2(w - pad * 2.0, 36)
	win.add_child(strip)
	var loc_s := String(snap.get("stat_data", {}).get("主角组", {}).get("当前地点", "未开启故事"))
	var strip_lbl := Lbl.new()
	strip_lbl.setup("数据通道已连接｜地点：%s｜已解锁：%d 人｜主线：%d 条｜世界书：%d 条｜%s" % [
		loc_s, int(snap.get("known_count", 0)), int(snap.get("message_count", 0)),
		(snap.get("worldbook_entries", []) as Array).size(), String(snap.get("conn_label", ""))
	], 15, "muted", 650)
	strip_lbl.position = Vector2(14, 4); strip_lbl.size = Vector2(strip.size.x - 28.0, 28)
	strip_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	strip.add_child(strip_lbl)

	var body_top := 170.0
	# Active Advisor Guidance Bar (when Plan or Sequence is running)
	if h.has_active_guidance():
		var gbar := Plate.new(); gbar.shape = "rect"; gbar.fill = "surface"; gbar.border = "accent"; gbar.layered = false
		gbar.position = Vector2(pad, body_top); gbar.size = Vector2(w - pad * 2.0, 60)
		win.add_child(gbar)
		var g_txt := String(h.active_guidance_summary()).replace("\n", " ｜ ")
		if bool(h.guidance_seq.get("beat_ready", false)):
			g_txt = "【落拍感应：本拍可能已演完】 " + g_txt
		var glbl := Lbl.new(); glbl.setup(g_txt, 15, "accent", 750)
		glbl.position = Vector2(14, 8); glbl.size = Vector2(gbar.size.x - 310.0, 44)
		glbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gbar.add_child(glbl)
		if not h.guidance_seq.is_empty():
			var b_done := Btn.new(); b_done.name = "OracleBeatDone"; b_done.setup("完成下一拍", "check", "primary", 15)
			b_done.position = Vector2(gbar.size.x - 284.0, 10); b_done.size = Vector2(134, 40)
			b_done.pressed.connect(func(): h.advance_sequence(false))
			gbar.add_child(b_done)
		var b_clr := Btn.new(); b_clr.name = "OracleGuideClear"; b_clr.setup("撤除引导", "close", "ghost", 15)
		b_clr.position = Vector2(gbar.size.x - 138.0, 10); b_clr.size = Vector2(124, 40)
		b_clr.pressed.connect(func(): h.clear_guidance())
		gbar.add_child(b_clr)
		body_top += 68.0

	var bottom_h := 136.0
	var area_h := maxf(180.0, ht - body_top - bottom_h - 14.0)
	var area_rect := Rect2(pad, body_top, w - pad * 2.0, area_h)

	if show_settings:
		_build_settings_panel(area_rect)
	elif show_debug:
		_build_debug_panel(area_rect)
	else:
		_build_chat_feed(area_rect)

	_build_input_bar(Rect2(pad, ht - bottom_h, w - pad * 2.0, bottom_h - 16.0))

func _build_chat_feed(rect: Rect2) -> void:
	var h := _hub()
	var frame := Plate.new(); frame.shape = "rect"; frame.fill = "background"; frame.fill_alpha = 0.65; frame.layered = false
	frame.position = rect.position; frame.size = rect.size
	win.add_child(frame)

	scroll = ScrollContainer.new(); scroll.name = "OracleScroll"
	scroll.position = Vector2(10, 10); scroll.size = rect.size - Vector2(20, 20)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)

	feed_box = VBoxContainer.new(); feed_box.name = "OracleFeed"
	feed_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_box.add_theme_constant_override("separation", 12)
	scroll.add_child(feed_box)

	var m_info: Dictionary = h.mode_info(String(h.current_mode))
	var mode_msgs: Array = []
	for r in h.chat_history:
		if r is Dictionary and String(r.get("mode", "")) == String(h.current_mode):
			mode_msgs.append(r)

	if mode_msgs.is_empty():
		var intro := Lbl.new()
		intro.setup("当前模式：%s —— %s\n\n点击底部输入框可直接提问；手机端或长段编辑可使用右下「悬浮大窗 / 竖屏输入」。" % [String(m_info.label), String(m_info.hint)], 19, "muted", 600)
		intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		feed_box.add_child(intro)
		return

	var host := _host_root()
	for r in mode_msgs:
		var is_u := String(r.get("role", "")) == "user"
		var card := Plate.new(); card.shape = "rect"
		card.fill = "surface2" if is_u else "surface"
		card.border = "accent" if (not is_u and not (r.get("actions", {}) as Dictionary).is_empty()) else "line"
		card.layered = false
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vb := VBoxContainer.new()
		vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
		vb.add_theme_constant_override("separation", 8)
		card.add_child(vb)

		var who_lbl := Lbl.new()
		who_lbl.setup(("你 · " if is_u else "故事神谕 · ") + String(r.get("time", "")), 14, "accent" if not is_u else "muted", 800)
		who_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(who_lbl)

		var txt_lbl := Lbl.new()
		txt_lbl.setup(String(r.get("text", "")), 18, "ink", 550)
		txt_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_child(txt_lbl)

		if not is_u:
			_mount_action_buttons(vb, r, host)

		var min_h := vb.get_combined_minimum_size().y + 34.0
		card.custom_minimum_size = Vector2(0, maxf(72.0, min_h))
		feed_box.add_child(card)
		vb.resized.connect(func():
			if is_instance_valid(card) and is_instance_valid(vb):
				card.custom_minimum_size.y = maxf(72.0, vb.get_combined_minimum_size().y + 34.0)
		)

	scroll.call_deferred("set_v_scroll", 999999)

func _mount_action_buttons(vb: VBoxContainer, rec: Dictionary, host: Node) -> void:
	var h := _hub()
	var actions: Dictionary = rec.get("actions", {}) if rec.get("actions") is Dictionary else {}
	if actions.is_empty(): return
	var rid := int(rec.get("id", 0))
	var applied := bool(rec.get("applied", false))

	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	vb.add_child(row)

	var add_act_btn := func(nm: String, caption: String, kind_s: String, cb: Callable) -> void:
		var b := Btn.new(); b.name = nm
		b.setup(caption, "check" if kind_s == "primary" else "docs", kind_s, 15)
		b.custom_minimum_size = Vector2(maxf(148.0, float(caption.length()) * 16.0 + 52.0), 38.0)
		b.pressed.connect(cb)
		row.add_child(b)

	if actions.has("patch_ops"):
		if applied:
			add_act_btn.call("OracleUndoBtn_%d" % rid, "撤销此诊断修正", "secondary", func():
				var ur: Dictionary = h.undo_message_action(rid)
				if host and host.has_method("toast"): host.toast("已撤销变量补丁" if bool(ur.ok) else String(ur.get("error", "")), "info")
			)
		else:
			var ops_cnt := (actions.patch_ops as Array).size()
			add_act_btn.call("OracleApplyDiag_%d" % rid, "应用诊断补丁 (%d 项)" % ops_cnt, "primary", func():
				var res: Dictionary = h.apply_message_diagnose(rid)
				if host and host.has_method("toast"): host.toast("已写入当前游戏状态" if bool(res.ok) else String(res.get("error", "")), "confirm")
			)

	if actions.has("lore_ops"):
		if applied:
			add_act_btn.call("OracleUndoLore_%d" % rid, "撤销世界书修改", "secondary", func():
				var ur: Dictionary = h.undo_message_action(rid)
				if host and host.has_method("toast"): host.toast("已恢复世界书" if bool(ur.ok) else String(ur.get("error", "")), "info")
			)
		else:
			var l_cnt := (actions.lore_ops as Array).size()
			add_act_btn.call("OracleApplyLore_%d" % rid, "应用世界书修改 (%d 处)" % l_cnt, "primary", func():
				var res: Dictionary = h.apply_message_lorebook(rid)
				if host and host.has_method("toast"): host.toast("已同步至游戏世界书" if bool(res.ok) else String(res.get("error", "")), "confirm")
			)

	if actions.has("plans"):
		var plans: Array = actions.plans
		for pi in range(plans.size()):
			var pl: Dictionary = plans[pi]
			add_act_btn.call("OracleAdoptPlan_%d_%d" % [rid, pi], "采用引导：%s" % String(pl.get("title", "方案 %d" % (pi + 1))), "primary", func():
				h.adopt_story_plan(pl)
				if host and host.has_method("toast"): host.toast("已采用剧情引导，将在主线发包时注入", "confirm")
			)

	if actions.has("sequences"):
		var seqs: Array = actions.sequences
		for si in range(seqs.size()):
			var sq: Dictionary = seqs[si]
			add_act_btn.call("OracleAdoptSeq_%d_%d" % [rid, si], "采用序列：%s (%d 拍)" % [String(sq.get("title", "序列")), (sq.get("beats", []) as Array).size()], "primary", func():
				h.adopt_story_sequence(sq)
				if host and host.has_method("toast"): host.toast("已采用多拍序列引导", "confirm")
			)

	if actions.has("fixed_reply"):
		if applied:
			add_act_btn.call("OracleUndoFix_%d" % rid, "切回校正前原文", "secondary", func():
				var ur: Dictionary = h.undo_message_action(rid)
				if host and host.has_method("toast"): host.toast("已切回原 Swipe" if bool(ur.ok) else String(ur.get("error", "")), "info")
			)
		else:
			add_act_btn.call("OracleApplyFix_%d" % rid, "写回为新 Swipe（保留原文）", "primary", func():
				var res: Dictionary = h.apply_message_fix(rid)
				if host and host.has_method("toast"): host.toast("已新增校正版 Swipe，主界面可随时左右切回" if bool(res.ok) else String(res.get("error", "")), "confirm")
			)

	if actions.has("char_draft") and not applied:
		add_act_btn.call("OracleApplyForge_%d" % rid, "写入游戏（世界书 DLC / 人设）", "primary", func():
			var res: Dictionary = h.apply_message_forge(rid)
			if host and host.has_method("toast"): host.toast("已写入：%s" % String(res.get("name", "")) if bool(res.ok) else String(res.get("error", "")), "confirm")
		)

func _build_settings_panel(rect: Rect2) -> void:
	var h := _hub()
	var frame := Plate.new(); frame.shape = "rect"; frame.fill = "background"; frame.fill_alpha = 0.72; frame.layered = false
	frame.position = rect.position; frame.size = rect.size
	win.add_child(frame)

	var sc := ScrollContainer.new(); sc.position = Vector2(14, 14); sc.size = rect.size - Vector2(28, 28)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(sc)

	var vb := VBoxContainer.new(); vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 14)
	sc.add_child(vb)

	# 1. Remote GitHub Update Panel
	var u_head := Lbl.new(); u_head.setup("版本与远端更新（GitHub namelessone88/story-oracle）", 21, "ink", 900); vb.add_child(u_head)
	var u_stat := Lbl.new(); u_stat.name = "OracleUpdateStatus"
	u_stat.setup("当前内置版本：v%s  ｜  远端状态：%s" % [String(h.installed_version), String(h.update_status_text)], 17, "accent" if h.update_available else "muted", 700)
	u_stat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; u_stat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(u_stat)

	var u_row := HBoxContainer.new(); u_row.add_theme_constant_override("separation", 12); vb.add_child(u_row)
	var host := _host_root()
	var b_chk := Btn.new(); b_chk.name = "OracleCheckUpdateBtn"; b_chk.setup("检查远端更新", "refresh", "secondary", 17)
	b_chk.custom_minimum_size = Vector2(190, 44)
	b_chk.pressed.connect(func():
		h.check_for_updates(func(_ok: bool, _v: String, msg: String):
			if host and host.has_method("toast"): host.toast(msg, "info")
		)
	)
	u_row.add_child(b_chk)
	var b_pull := Btn.new(); b_pull.name = "OraclePullUpdateBtn"; b_pull.setup("立即拉取更新（含提示词规则）", "download", "primary", 17)
	b_pull.custom_minimum_size = Vector2(280, 44)
	b_pull.pressed.connect(func():
		h.pull_update(func(ok_p: bool, msg: String):
			if host and host.has_method("toast"): host.toast(msg, "confirm" if ok_p else "warn")
		)
	)
	u_row.add_child(b_pull)

	# 2. API Mode & Model Endpoint
	var c_head := Lbl.new(); c_head.setup("API 连接与参数设置", 21, "ink", 900); vb.add_child(c_head)
	var c_row := HBoxContainer.new(); c_row.add_theme_constant_override("separation", 10); vb.add_child(c_row)
	var b_follow := Btn.new(); b_follow.name = "OracleConnGame"; b_follow.setup("跟随游戏当前 API", "link", "chip", 16)
	b_follow.selected = String(h.settings.get("conn_mode", "game")) == "game"; b_follow.custom_minimum_size = Vector2(210, 42)
	b_follow.pressed.connect(func(): h.settings["conn_mode"] = "game"; h.save_settings(); _rebuild_contents())
	c_row.add_child(b_follow)
	var b_cust := Btn.new(); b_cust.name = "OracleConnCustom"; b_cust.setup("使用故事神谕独立端点", "gear", "chip", 16)
	b_cust.selected = String(h.settings.get("conn_mode", "game")) == "custom"; b_cust.custom_minimum_size = Vector2(230, 42)
	b_cust.pressed.connect(func(): h.settings["conn_mode"] = "custom"; h.save_settings(); _rebuild_contents())
	c_row.add_child(b_cust)

	if String(h.settings.get("conn_mode", "game")) == "custom":
		var u_in := LineEdit.new(); u_in.placeholder_text = "OpenAI 兼容地址 (例 https://api.openai.com/v1)"; u_in.text = String(h.settings.get("custom_url", ""))
		u_in.custom_minimum_size = Vector2(600, 42)
		u_in.text_changed.connect(func(t: String): h.settings["custom_url"] = t; h.save_settings())
		vb.add_child(u_in)
		var m_in := LineEdit.new(); m_in.placeholder_text = "模型名称 (例 deepseek-chat / gpt-4o)"; m_in.text = String(h.settings.get("custom_model", ""))
		m_in.custom_minimum_size = Vector2(600, 42)
		m_in.text_changed.connect(func(t: String): h.settings["custom_model"] = t; h.save_settings())
		vb.add_child(m_in)
		var k_in := LineEdit.new(); k_in.secret = true; k_in.placeholder_text = "API 密钥 (sk-...)"; k_in.text = String(h.settings.get("custom_key", ""))
		k_in.custom_minimum_size = Vector2(600, 42)
		k_in.text_changed.connect(func(t: String): h.settings["custom_key"] = t; h.save_settings())
		vb.add_child(k_in)

	# 3. Speaking Persona
	var p_head := Lbl.new(); p_head.setup("说话人格风格", 21, "ink", 900); vb.add_child(p_head)
	var p_row := HFlowContainer.new(); p_row.add_theme_constant_override("h_separation", 8); vb.add_child(p_row)
	for pers in h.BUILTIN_PERSONAS:
		var pid := String(pers.id)
		var pb := Btn.new(); pb.setup(String(pers.name), "", "chip", 15)
		pb.selected = String(h.settings.get("persona_id", "none")) == pid
		pb.custom_minimum_size = Vector2(148, 38)
		pb.pressed.connect(func(): h.settings["persona_id"] = pid; h.save_settings(); _rebuild_contents())
		p_row.add_child(pb)

	# 4. Context depth
	var d_row := HBoxContainer.new(); d_row.add_theme_constant_override("separation", 10); vb.add_child(d_row)
	var d_lbl := Lbl.new(); d_lbl.setup("上下文读取楼层数：", 18, "ink", 700); d_row.add_child(d_lbl)
	for dep in [12, 24, -1]:
		var db := Btn.new(); db.setup("全部历史" if dep < 0 else "最近 %d 条" % dep, "", "chip", 15)
		db.selected = int(h.settings.get("context_depth", 12)) == dep
		db.custom_minimum_size = Vector2(118, 38)
		db.pressed.connect(func(): h.settings["context_depth"] = dep; h.save_settings(); _rebuild_contents())
		d_row.add_child(db)

func _build_debug_panel(rect: Rect2) -> void:
	var h := _hub()
	var frame := Plate.new(); frame.shape = "rect"; frame.fill = "background"; frame.fill_alpha = 0.72; frame.layered = false
	frame.position = rect.position; frame.size = rect.size
	win.add_child(frame)
	var te := TextEdit.new(); te.name = "OracleDebugText"
	te.editable = false; te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.text = h.last_debug_prompt if h.last_debug_prompt != "" else "（尚未发起过询问；发送一条消息后可在此查看完整注入到故事神谕的系统提示词、世界书与数据通道快照。）"
	te.position = Vector2(12, 12); te.size = rect.size - Vector2(24, 24)
	frame.add_child(te)

func _build_input_bar(rect: Rect2) -> void:
	var h := _hub()
	var host := _host_root()
	var bar := Plate.new(); bar.shape = "rect"; bar.fill = "surface"; bar.border = "line"; bar.layered = false
	bar.position = rect.position; bar.size = rect.size
	win.add_child(bar)

	var right_w := 304.0
	input_edit = TextEdit.new(); input_edit.name = "OracleInput"
	input_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input_edit.placeholder_text = "问问故事神谕，或让它诊断变量 / 改世界书 / 参谋剧情 / 校正文风…"
	input_edit.text = draft_text
	input_edit.position = Vector2(12, 10); input_edit.size = Vector2(rect.size.x - right_w - 22.0, rect.size.y - 20.0)
	input_edit.text_changed.connect(func(): draft_text = input_edit.text)
	input_edit.focus_entered.connect(func():
		if OS.has_feature("mobile") and not _suppress_auto_portrait:
			call_deferred("_open_composer", true)
		_suppress_auto_portrait = false
	)
	input_edit.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and e.pressed and e.keycode == KEY_ENTER and e.ctrl_pressed:
			_send_current(); input_edit.accept_event()
	)
	bar.add_child(input_edit)

	var bx := rect.size.x - right_w - 2.0
	expand_btn = Btn.new(); expand_btn.name = "OracleExpandBtn"
	expand_btn.setup("悬浮窗", "chat", "chip", 15)
	expand_btn.position = Vector2(bx, 10); expand_btn.size = Vector2(142, 42)
	expand_btn.tooltip_text = "展开独立悬浮大窗输入（确认后自动填回）"
	expand_btn.pressed.connect(func(): _open_composer(false))
	bar.add_child(expand_btn)

	portrait_btn = Btn.new(); portrait_btn.name = "OraclePortraitBtn"
	portrait_btn.setup("竖屏输入", "swap", "chip", 15)
	portrait_btn.position = Vector2(bx + 150.0, 10); portrait_btn.size = Vector2(142, 42)
	portrait_btn.tooltip_text = "切换手机竖屏大图输入框（确认后自动填回并切回横屏）"
	portrait_btn.pressed.connect(func(): _open_composer(true))
	bar.add_child(portrait_btn)

	send_btn = Btn.new(); send_btn.name = "OracleSendBtn"
	send_btn.setup("停止" if h.busy else "发送给神谕", "pause" if h.busy else "send", "secondary" if h.busy else "primary", 18)
	send_btn.position = Vector2(bx, 60); send_btn.size = Vector2(292, rect.size.y - 70.0)
	send_btn.pressed.connect(func():
		if h.busy: h.stop_request()
		else: _send_current()
	)
	bar.add_child(send_btn)

func _open_composer(portrait_mode: bool) -> void:
	var host := _host_root()
	if host == null or not host.has_method("open_text_composer"): return
	var cur := input_edit.text if is_instance_valid(input_edit) else draft_text
	host.open_text_composer({
		"title": "故事神谕 · 竖屏输入（确认后填回）" if portrait_mode else "故事神谕 · 悬浮大窗输入",
		"tip": "写好询问、修改要求或世界书内容后点「确认并填入」，会自动回填到故事神谕输入框，随时可继续修改再发送。",
		"placeholder": "写下想让故事神谕处理的内容…",
		"text": cur,
		"portrait_mode": portrait_mode,
	}, func(val: String) -> void:
		draft_text = val
		if is_instance_valid(input_edit):
			_suppress_auto_portrait = true
			input_edit.text = val
	)

func _send_current() -> void:
	var h := _hub()
	var txt := (input_edit.text if is_instance_valid(input_edit) else draft_text).strip_edges()
	if txt == "":
		var host := _host_root()
		if host and host.has_method("toast"): host.toast("请先输入想问或想让故事神谕处理的内容", "info")
		return
	draft_text = ""
	if is_instance_valid(input_edit): input_edit.text = ""
	h.send_oracle_message(String(h.current_mode), txt)

func _on_header_drag(e: InputEvent) -> void:
	var h := _hub()
	if bool(h.settings.get("fullscreen", false)): return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_dragging = true
			_drag_off = get_local_mouse_position() - win.position
		else:
			_dragging = false
			h.settings["float_rect"] = {"x": win.position.x, "y": win.position.y, "w": win.size.x, "h": win.size.y}
			h.save_settings()
	elif e is InputEventMouseMotion and _dragging:
		var np := get_local_mouse_position() - _drag_off
		var max_p := size - win.size - Vector2(12, 12)
		win.position = Vector2(clampf(np.x, 12.0, maxf(12.0, max_p.x)), clampf(np.y, 12.0, maxf(12.0, max_p.y)))

func _on_hdr_action(act: String) -> void:
	var h := _hub()
	match act:
		"close": close()
		"fullscreen":
			h.settings["fullscreen"] = not bool(h.settings.get("fullscreen", false))
			h.save_settings()
			_build_shell()
		"settings":
			show_settings = not show_settings; show_debug = false; _rebuild_contents()
		"debug":
			show_debug = not show_debug; show_settings = false; _rebuild_contents()
		"clear":
			h.clear_history()

func close() -> void:
	if closing: return
	closing = true
	if UiHub.mobile_portrait_input:
		UiHub.set_mobile_portrait(false)
	UiHub.sfx("close")
	closed.emit()
	queue_free()
