extends RefCounted
## Dialogs, toasts and reward popups that sit above any screen.
const Kit = preload("res://scripts/ui/ui_kit.gd")
const Plate = preload("res://scripts/ui/ui_plate.gd")
const Btn = preload("res://scripts/ui/ui_button.gd")
const Lbl = preload("res://scripts/ui/ui_label.gd")
const Icon = preload("res://scripts/ui/ui_icon.gd")
const W = preload("res://scripts/ui/ui_widgets.gd")


## Layered confirm dialog. spec keys: title, message, icon, buttons[{id,text,icon,kind}], cancel_id, width.
class Dialog extends Control:
	signal chosen(id: String)
	var spec: Dictionary = {}
	var shade: ColorRect
	var group: Control
	var plates: Array = []
	var closing := false
	var input_edit: LineEdit

	func get_input_text() -> String:
		return input_edit.text if is_instance_valid(input_edit) else ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		shade = ColorRect.new(); shade.color = UiHub.c("shade"); add_child(shade); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		Kit.frost(shade)
		var w: float = spec.get("width", 1000.0)
		var buttons: Array = spec.get("buttons", [])
		var has_icon: bool = spec.get("icon", "") != ""
		var has_input: bool = spec.has("input")
		var h: float = 300.0 + (90.0 if has_icon else 0.0) + (40.0 if spec.get("message", "") != "" else 0.0) + (76.0 if has_input else 0.0)
		group = Control.new(); group.size = Vector2(w, h); group.position = (size - group.size) * 0.5; add_child(group)
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var back := Plate.new(); back.shape = "slant"; back.slant = 70; back.fill = "surface2"; back.fill_alpha = 0.7; back.layered = false; back.border = ""
		group.add_child(back); back.position = Vector2(-36, 26); back.size = Vector2(w + 30, h - 30); plates.append(back)
		back.fill = "surface"; back.fill_alpha = 0.0; back.border = "line"; back.border_alpha = 0.6; back.detail = false; back.bead = false
		var flag := Control.new(); flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(flag); flag.position = Vector2(-40, -40); flag.size = Vector2(120, 120); plates.append(flag)
		flag.draw.connect(func():
			var c := Vector2(60, 60)
			flag.draw_arc(c, 40, 0, TAU, 48, UiHub.c("accent", 0.5), 1.2, true)
			Kit.crescent(flag, c + Vector2(4, 0), 39, -PI * 0.45, PI * 0.45, 9, UiHub.c("accent"))
			Kit.star4(flag, c, 15, UiHub.c("accent"), 0.16)
			Kit.line_fade(flag, c + Vector2(-50, 50), c + Vector2(56, -56), UiHub.c("accent", 0.6), 1.0))
		var face := Plate.new(); face.shape = "cut"; face.slant = 48; face.fill_alpha = 0.98; face.corner = "tr"; face.hatch = true; face.layer_offset = Vector2(16, 14)
		group.add_child(face); face.position = Vector2.ZERO; face.size = group.size
		var y := 40.0
		if has_icon:
			var ic := Icon.new(); ic.icon = spec.icon; ic.role = "accent" if spec.get("tone", "") == "danger" else "ink"
			group.add_child(ic); ic.position = Vector2(w * 0.5 - 40, y); ic.size = Vector2(80, 80); y += 92
		var t := Lbl.new(); t.setup(spec.get("title", ""), 46, "ink", 850); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		group.add_child(t); t.position = Vector2(0, y); t.size = Vector2(w, 64); y += 66
		if spec.get("message", "") != "":
			var m := Lbl.new(); m.setup(spec.message, 24, "muted", 600); m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			group.add_child(m); m.position = Vector2(80, y); m.size = Vector2(w - 160, 40); y += 48
		if has_input:
			var inp: Dictionary = spec.get("input", {})
			input_edit = LineEdit.new(); input_edit.name = "DialogInput"
			input_edit.text = str(inp.get("text", ""))
			input_edit.placeholder_text = str(inp.get("placeholder", "请输入内容…"))
			group.add_child(input_edit)
			input_edit.position = Vector2(100, y)
			input_edit.size = Vector2(w - 200, 58)
			y += 68
			input_edit.text_submitted.connect(func(_val): close(spec.get("confirm_id", "ok")))
			input_edit.call_deferred("grab_focus")
			input_edit.call_deferred("select_all")
		var rule := Control.new(); group.add_child(rule); rule.position = Vector2(w * 0.5 - 90, y + 4); rule.size = Vector2(180, 8)
		var draw_rule := func() -> void:
			Kit.line_fade(rule, Vector2(0, 4), Vector2(180, 4), UiHub.c("hair"), 1.0)
			Kit.star4(rule, Vector2(90, 4), 6, UiHub.c("accent"), 0.18)
		rule.draw.connect(draw_rule)
		y += 38
		var bw := minf(330.0, (w - 120.0 - (buttons.size() - 1) * 24.0) / maxf(buttons.size(), 1))
		var x0 := (w - (bw * buttons.size() + 24.0 * (buttons.size() - 1))) * 0.5
		var first: Button
		for i in range(buttons.size()):
			var spec_b: Dictionary = buttons[i]
			var b := Btn.new(); b.setup(spec_b.text, spec_b.get("icon", ""), spec_b.get("kind", "secondary"), 26)
			b.center_text = spec_b.get("icon", "") == ""
			group.add_child(b); b.position = Vector2(x0 + i * (bw + 24), y); b.size = Vector2(bw, 76)
			var bid: String = spec_b.id
			b.pressed.connect(func(): close(bid))
			if first == null or spec_b.get("kind", "") in ["primary", "danger"]: first = b
		if first: first.call_deferred("grab_focus")
		face.dots = true
		_enter()
	func _enter() -> void:
		if UiHub.reduced_motion: return
		shade.modulate.a = 0.0; group.modulate.a = 0.0
		var target := group.position; group.position.y += 30
		var t := create_tween().set_parallel(true)
		t.tween_property(shade, "modulate:a", 1.0, 0.3)
		t.tween_method(func(v): group.modulate.a = Kit.curve(minf(v / 0.3, 1.0), Kit.Motion.EASE); group.position = target + Vector2(0, 30.0 * (1.0 - Kit.curve(v / 0.4))), 0.0, 0.4, 0.4)
		for i in range(plates.size()):
			var p: Control = plates[i]; var home := p.position
			p.position += Vector2(-60 + i * 30, 0)
			t.tween_property(p, "position", home, 0.5).set_delay(0.06 * (i + 1)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	func cancel() -> void:
		close(spec.get("cancel_id", "cancel"))
	func close(id: String) -> void:
		if closing: return
		closing = true
		UiHub.sfx("close")
		chosen.emit(id)
		if UiHub.reduced_motion:
			queue_free(); return
		var t := create_tween().set_parallel(true)
		t.tween_property(shade, "modulate:a", 0.0, 0.28)
		t.tween_property(group, "modulate:a", 0.0, 0.25)
		t.tween_property(group, "position:y", group.position.y + 24, 0.3)
		t.chain().tween_callback(queue_free)


## Short notice that slides down from the top edge, then leaves.
class Toast extends Control:
	var message := ""
	var icon_name := "info"
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := Kit.text_width(message, UiHub.fs(24)) + 140
		size = Vector2(w, 70)
		var p := Plate.new(); p.slant = 22; p.stripe = "left"; p.fill_alpha = 0.97; add_child(p); p.size = size
		var ic := Icon.new(); ic.icon = icon_name; ic.role = "accent"; add_child(ic); ic.position = Vector2(34, 17); ic.size = Vector2(36, 36)
		var l := Lbl.new(); l.setup(message, 24, "ink", 700); add_child(l); l.position = Vector2(86, 0); l.size = Vector2(w - 100, 70)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	func play(top: float) -> void:
		var target := position.y
		var t := create_tween()
		if not UiHub.reduced_motion:
			position.y = top - 90; modulate.a = 0.0
			t.tween_method(func(v): position.y = lerpf(top - 90, target, Kit.curve(v)); modulate.a = minf(v * 2.0, 1.0), 0.0, 1.0, 0.45)
		t.tween_interval(2.2)
		t.tween_property(self, "modulate:a", 0.0, 0.35)
		t.tween_callback(queue_free)


## "获得物品" popup: item tiles pop in one by one with a light burst.
class Reward extends Control:
	signal closed
	var entries: Array = []
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var shade := ColorRect.new(); add_child(shade); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; Kit.frost(shade)
		var band := Plate.new(); band.shape = "rect"; band.fill_alpha = 0.96; band.layered = false; band.border = ""
		add_child(band); band.position = Vector2(0, size.y * 0.5 - 190); band.size = Vector2(size.x, 380)
		var t := Lbl.new(); t.setup("获得物品", 44, "ink", 850); t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(t); t.position = Vector2(0, size.y * 0.5 - 170); t.size = Vector2(size.x, 70)
		var n := entries.size(); var tw := 170.0; var gap := 30.0
		var x0 := (size.x - (n * tw + (n - 1) * gap)) * 0.5
		for i in range(n):
			var e: Dictionary = entries[i]
			var tile := Control.new(); add_child(tile); tile.position = Vector2(x0 + i * (tw + gap), size.y * 0.5 - 80); tile.size = Vector2(tw, 190)
			var p := Plate.new(); p.shape = "rect"; p.corner = "bl"; p.corner_size = 18; tile.add_child(p); p.size = Vector2(tw, 190)
			var ic := Icon.new(); ic.icon = e.icon; tile.add_child(ic); ic.position = Vector2(30, 14); ic.size = Vector2(110, 110)
			var c := Lbl.new(); c.setup("×%d" % int(e.count), 26, "ink", 800); c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tile.add_child(c); c.position = Vector2(0, 130); c.size = Vector2(tw, 50)
			Kit.pop(tile, 0.15 + i * 0.09)
			var tt := tile.create_tween(); tt.tween_interval(0.15 + i * 0.09); tt.tween_callback(UiHub.sfx.bind("pop", 1.0 + i * 0.06, 0.0))
		var hint := Lbl.new(); hint.setup("点击任意处继续", 22, "muted", 600); hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(hint); hint.position = Vector2(0, size.y * 0.5 + 140); hint.size = Vector2(size.x, 40)
		if not UiHub.reduced_motion:
			band.scale.y = 0.0; band.pivot_offset = band.size * 0.5
			create_tween().tween_property(band, "scale:y", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed) or e.is_action_pressed("ui_accept"):
			UiHub.sfx("close"); closed.emit(); queue_free(); accept_event()


## In-game BGM player ("乐章"): on-demand track selection, story variable follow, seek/volume,
## and complete persistent BGM shutoff ("彻底关闭音乐").
class MusicPlayer extends Control:
	signal closed
	var shade: ColorRect
	var group: Control
	var disc: Control
	var _disc_angle := 0.0
	var state_lbl: Label
	var title_lbl: Label
	var var_lbl: Label
	var now_lbl: Label
	var dur_lbl: Label
	var seek_slider: Control
	var vol_slider: Control
	var vol_pct: Label
	var play_btn: Button
	var shutoff_btn: Button
	var follow_btn: Button
	var track_scroll: ScrollContainer
	var track_grid: Control
	var cat_tabs: Array = []
	var track_btns: Array = []
	var active_cat := "all"
	var closing := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		shade = ColorRect.new(); shade.color = UiHub.c("shade"); add_child(shade)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_STOP
		Kit.frost(shade)
		shade.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				close(); accept_event())
		group = Control.new(); group.name = "MusicPlayerCard"; group.size = Vector2(1140, 790)
		add_child(group); _center(); resized.connect(_center)
		group.mouse_filter = Control.MOUSE_FILTER_STOP
		var back := Plate.new(); back.shape = "slant"; back.slant = 56; back.fill = "surface"; back.fill_alpha = 0.0
		back.border = "line"; back.border_alpha = 0.55; back.detail = false; back.bead = false; back.layered = false
		group.add_child(back); back.position = Vector2(-26, 20); back.size = Vector2(group.size.x + 18, group.size.y - 24)
		var face := Plate.new(); face.shape = "cut"; face.slant = 44; face.fill_alpha = 0.98; face.corner = "tr"; face.hatch = true; face.dots = true; face.layer_offset = Vector2(14, 12)
		face.mouse_filter = Control.MOUSE_FILTER_STOP
		group.add_child(face); face.position = Vector2.ZERO; face.size = group.size
		# Disc emblem in header
		disc = Control.new(); disc.name = "Disc"; disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(disc); disc.position = Vector2(40, 26); disc.size = Vector2(110, 110)
		disc.draw.connect(_draw_disc)
		state_lbl = Lbl.new(); state_lbl.name = "StateLabel"; state_lbl.setup("正在播放", 18, "accent", 800)
		group.add_child(state_lbl); state_lbl.position = Vector2(174, 24); state_lbl.size = Vector2(460, 28)
		title_lbl = Lbl.new(); title_lbl.name = "NowPlayingTitle"; title_lbl.setup("无", 36, "ink", 900)
		title_lbl.clip_text = true
		group.add_child(title_lbl); title_lbl.position = Vector2(174, 52); title_lbl.size = Vector2(820, 48)
		var_lbl = Lbl.new(); var_lbl.name = "StoryVarLabel"; var_lbl.setup("剧情变量 · 无", 20, "muted", 650)
		var_lbl.clip_text = true
		group.add_child(var_lbl); var_lbl.position = Vector2(174, 102); var_lbl.size = Vector2(830, 32)
		var close_b := Btn.new(); close_b.name = "CloseBtn"; close_b.setup("", "close", "icon", 22)
		close_b.press_sfx = "none"; close_b.tooltip_text = "关闭播放器（Esc）"
		group.add_child(close_b); close_b.position = Vector2(1042, 26); close_b.size = Vector2(66, 66)
		close_b.pressed.connect(close)
		# Seek row
		now_lbl = Lbl.new(); now_lbl.name = "NowTime"; now_lbl.setup("0:00", 20, "muted", 700)
		group.add_child(now_lbl); now_lbl.position = Vector2(44, 152); now_lbl.size = Vector2(80, 48)
		now_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seek_slider = W.ValueSlider.new(); seek_slider.name = "SeekSlider"
		seek_slider.min_value = 0.0; seek_slider.max_value = 1.0; seek_slider.value = 0.0; seek_slider.step = 0.25; seek_slider.ticks = 5
		group.add_child(seek_slider); seek_slider.position = Vector2(128, 144); seek_slider.size = Vector2(878, 64)
		seek_slider.value_changed.connect(func(v): UiHub.seek_music(v))
		dur_lbl = Lbl.new(); dur_lbl.name = "DurTime"; dur_lbl.setup("0:00", 20, "muted", 700)
		dur_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; dur_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		group.add_child(dur_lbl); dur_lbl.position = Vector2(1012, 152); dur_lbl.size = Vector2(84, 48)
		# Controls row
		play_btn = Btn.new(); play_btn.name = "PlayPauseBtn"; play_btn.setup("暂停", "pause", "primary", 24)
		play_btn.press_sfx = "chip"
		group.add_child(play_btn); play_btn.position = Vector2(44, 214); play_btn.size = Vector2(166, 62)
		play_btn.pressed.connect(func(): UiHub.toggle_music_pause())
		shutoff_btn = Btn.new(); shutoff_btn.name = "ShutoffBtn"; shutoff_btn.setup("彻底关闭音乐", "mute", "danger", 22)
		shutoff_btn.press_sfx = "none"
		group.add_child(shutoff_btn); shutoff_btn.position = Vector2(226, 214); shutoff_btn.size = Vector2(246, 62)
		shutoff_btn.pressed.connect(func():
			var next_off := not UiHub.music_disabled
			UiHub.set_music_disabled(next_off)
			UiHub.sfx("toggle_off" if next_off else "toggle_on"))
		follow_btn = Btn.new(); follow_btn.name = "FollowVarBtn"; follow_btn.setup("跟随剧情", "refresh", "chip", 21)
		group.add_child(follow_btn); follow_btn.position = Vector2(488, 214); follow_btn.size = Vector2(182, 62)
		follow_btn.pressed.connect(func(): UiHub.clear_music_override())
		var vl := Lbl.new(); vl.setup("音量", 21, "ink", 750); vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		group.add_child(vl); vl.position = Vector2(692, 214); vl.size = Vector2(64, 62)
		vol_slider = W.ValueSlider.new(); vol_slider.name = "VolumeSlider"
		vol_slider.min_value = 0.0; vol_slider.max_value = 1.0; vol_slider.step = 0.01; vol_slider.value = UiHub.volumes.get("music", 0.7)
		group.add_child(vol_slider); vol_slider.position = Vector2(758, 214); vol_slider.size = Vector2(256, 64)
		vol_slider.value_changed.connect(func(v): UiHub.set_volume("music", v))
		vol_pct = Lbl.new(); vol_pct.name = "VolumePct"; vol_pct.setup("70%", 21, "accent", 800)
		vol_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; vol_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		group.add_child(vol_pct); vol_pct.position = Vector2(1018, 214); vol_pct.size = Vector2(78, 62)
		# Track category tabs + scrollable track list (supports 50+ tracks)
		var rule := Control.new(); rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group.add_child(rule); rule.position = Vector2(44, 286); rule.size = Vector2(1052, 8)
		rule.draw.connect(func():
			Kit.line_fade(rule, Vector2(0, 4), Vector2(1052, 4), UiHub.c("hair"), 1.0)
			Kit.star4(rule, Vector2(526, 4), 6, UiHub.c("accent"), 0.18))
		var tracks: Array = UiHub.music_manifest.get("tracks", [])
		var cat_defs := [
			["all", "全部"],
			["world", "势力与地点"],
			["story", "日常与危机"],
			["ui", "界面曲"],
			["original", "原卡14首"],
		]
		cat_tabs.clear()
		var cx := 44.0
		for cd in cat_defs:
			var cid := String(cd[0])
			var cnt := 0
			for tr in tracks:
				if cid == "all" or String(tr.get("category", "original")) == cid:
					cnt += 1
			var cb := Btn.new(); cb.name = "MusicCat_" + cid
			cb.variant = "chip"; cb.font_px = 18; cb.press_sfx = "chip"
			cb.caption = "%s (%d)" % [String(cd[1]), cnt]
			cb.set_meta("cat_id", cid)
			var cw := 162.0 if cid == "all" or cid == "ui" else 206.0
			group.add_child(cb); cb.position = Vector2(cx, 298); cb.size = Vector2(cw, 40)
			var cat_pick := cid
			cb.pressed.connect(func():
				active_cat = cat_pick
				_rebuild_track_list()
				_sync())
			cat_tabs.append(cb)
			cx += cw + 12.0
		track_scroll = ScrollContainer.new(); track_scroll.name = "TrackScroll"
		track_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		track_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		group.add_child(track_scroll); track_scroll.position = Vector2(44, 346); track_scroll.size = Vector2(1052, 382)
		track_grid = Control.new(); track_grid.name = "TrackGrid"
		track_scroll.add_child(track_grid)
		_rebuild_track_list()
		var note := Lbl.new(); note.setup("曲目默认由变量「主角组.当前BGM」或当前界面决定；点下方曲目可随时点播，点「跟随剧情」或剧情变歌时自动切回。", 17, "muted", 600)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		group.add_child(note); note.position = Vector2(44, 734); note.size = Vector2(1052, 40)
		UiHub.music_changed.connect(_sync)
		UiHub.options_changed.connect(_sync)
		UiHub.palette_changed.connect(_repaint)
		Game.changed.connect(_on_game_changed)
		_sync()
		_enter()

	func _rebuild_track_list() -> void:
		if not is_instance_valid(track_grid):
			return
		for ch in track_grid.get_children():
			ch.queue_free()
		track_btns.clear()
		var tracks: Array = UiHub.music_manifest.get("tracks", [])
		var visible_items: Array = []
		for i in range(tracks.size()):
			var t: Dictionary = tracks[i]
			if active_cat == "all" or String(t.get("category", "original")) == active_cat:
				visible_items.append({"idx": i, "track": t})
		var rows := maxi(1, ceili(visible_items.size() / 2.0))
		track_grid.custom_minimum_size = Vector2(1036, rows * 64.0 + 8.0)
		track_grid.size = track_grid.custom_minimum_size
		for pos in range(visible_items.size()):
			var item: Dictionary = visible_items[pos]
			var orig_i := int(item.idx)
			var t: Dictionary = item.track
			var t_title := String(t.get("title", ""))
			var t_role := String(t.get("role", t.get("usage", t.get("scene", ""))))
			var t_artist := String(t.get("artist", ""))
			var sub_txt := t_role if t_artist == "" else "%s · %s" % [t_artist, t_role]
			var col := pos % 2
			var row := pos / 2
			var bx := col * 518.0
			var by := 4.0 + row * 64.0
			var tb := Btn.new(); tb.name = "Track_%d" % orig_i
			tb.variant = "secondary"; tb.slant = 18; tb.divider = false; tb.font_px = 19; tb.press_sfx = "none"
			tb.caption = "%02d  %s" % [orig_i + 1, t_title]
			tb.sub = sub_txt
			tb.tooltip_text = "%s%s" % [t_title, (" · " + sub_txt) if sub_txt != "" else ""]
			tb.set_meta("track_title", t_title)
			track_grid.add_child(tb); tb.position = Vector2(bx, by); tb.size = Vector2(502, 56)
			var tt := t_title
			tb.pressed.connect(func():
				UiHub.sfx("music_pick")
				UiHub.select_music(tt))
			track_btns.append(tb)

	func _exit_tree() -> void:
		if UiHub.music_changed.is_connected(_sync): UiHub.music_changed.disconnect(_sync)
		if UiHub.options_changed.is_connected(_sync): UiHub.options_changed.disconnect(_sync)
		if UiHub.palette_changed.is_connected(_repaint): UiHub.palette_changed.disconnect(_repaint)
		if Game.changed.is_connected(_on_game_changed): Game.changed.disconnect(_on_game_changed)

	func _on_game_changed(part: String) -> void:
		if part == "stat" or part == "session": _sync()

	func _center() -> void:
		if is_instance_valid(group):
			group.position = ((size - group.size) * 0.5).floor()

	func _repaint() -> void:
		if is_instance_valid(disc): disc.queue_redraw()
		_sync()

	func _process(delta: float) -> void:
		if UiHub.is_music_playing() and not UiHub.reduced_motion:
			_disc_angle = fmod(_disc_angle + delta * 1.4, TAU)
			if is_instance_valid(disc): disc.queue_redraw()
		var pos := UiHub.music_position()
		var dur := UiHub.music_duration()
		if is_instance_valid(now_lbl): now_lbl.text = _fmt_time(pos)
		if is_instance_valid(dur_lbl): dur_lbl.text = _fmt_time(dur)
		if is_instance_valid(seek_slider) and not seek_slider.dragging:
			seek_slider.max_value = maxf(dur, 1.0)
			seek_slider.value = clampf(pos, 0.0, seek_slider.max_value)
			seek_slider.queue_redraw()

	func _fmt_time(sec: float) -> String:
		var s := maxi(0, int(floor(sec)))
		return "%d:%02d" % [s / 60, s % 60]

	func _draw_disc() -> void:
		var c := disc.size * 0.5
		var r := minf(c.x, c.y) - 4.0
		var acc := UiHub.c("accent")
		var ink := UiHub.c("ink")
		disc.draw_circle(c, r, UiHub.c("surface2"))
		disc.draw_arc(c, r, 0, TAU, 48, Color(acc if UiHub.is_music_playing() else ink, 0.75), 1.6, true)
		for rr in [0.78, 0.62, 0.46]:
			disc.draw_arc(c, r * rr, 0, TAU, 40, Color(ink, 0.22), 1.0, true)
		var rot := _disc_angle
		Kit.crescent(disc, c, r * 0.88, rot, rot + PI * 0.75, 4.0, Color(acc, 0.85), 24)
		disc.draw_circle(c, r * 0.26, acc if UiHub.is_music_playing() else UiHub.c("muted"))
		Kit.star4(disc, c, r * 0.16, UiHub.c("on_accent"), 0.16, rot)

	func _sync() -> void:
		var off := UiHub.music_disabled
		var cur := UiHub.music_current
		var hv := String(Game.hero().get("当前BGM", "无"))
		if hv == "": hv = "无"
		if is_instance_valid(state_lbl):
			if off: state_lbl.text = "音乐已彻底关闭"
			elif UiHub.music_paused: state_lbl.text = "已暂停"
			elif cur == "": state_lbl.text = "未播放"
			elif UiHub.music_override != "": state_lbl.text = "手动点播中"
			else: state_lbl.text = "正在播放"
		if is_instance_valid(title_lbl):
			title_lbl.text = "已彻底关闭" if off else (cur if cur != "" else "无")
		if is_instance_valid(var_lbl):
			var_lbl.text = "剧情变量 · %s%s" % [hv, "（当前为手动点播，变量变动后自动切回）" if UiHub.music_override != "" else ""]
		if is_instance_valid(play_btn):
			var want_play := off or UiHub.music_paused or cur == ""
			play_btn.caption = "播放" if want_play else "暂停"
			play_btn.icon_name = "play" if want_play else "pause"
			play_btn.queue_redraw()
		if is_instance_valid(shutoff_btn):
			shutoff_btn.caption = "恢复开启音乐" if off else "彻底关闭音乐"
			shutoff_btn.icon_name = "speaker" if off else "mute"
			shutoff_btn.variant = "primary" if off else "danger"
			shutoff_btn.queue_redraw()
		if is_instance_valid(follow_btn):
			follow_btn.disabled = UiHub.music_override == ""
			follow_btn.queue_redraw()
		if is_instance_valid(vol_pct):
			vol_pct.text = "%d%%" % int(round(UiHub.volumes.get("music", 0.7) * 100.0))
		if is_instance_valid(vol_slider) and not vol_slider.dragging:
			vol_slider.value = UiHub.volumes.get("music", 0.7)
			vol_slider.queue_redraw()
		for cb in cat_tabs:
			if not is_instance_valid(cb): continue
			cb.selected = String(cb.get_meta("cat_id", "")) == active_cat
			cb.queue_redraw()
		for tb in track_btns:
			if not is_instance_valid(tb): continue
			var t_title := String(tb.get_meta("track_title", ""))
			var active := (not off and cur == t_title)
			tb.selected = active
			tb.icon_name = "music" if active else ""
			tb.badge = "播放中" if active else ""
			tb.queue_redraw()
		if is_instance_valid(disc): disc.queue_redraw()

	func _enter() -> void:
		if UiHub.reduced_motion: return
		shade.modulate.a = 0.0; group.modulate.a = 0.0
		var target := group.position; group.position.y += 24
		var t := create_tween().set_parallel(true)
		t.tween_property(shade, "modulate:a", 1.0, 0.25)
		t.tween_method(func(v):
			var k := Kit.curve(v, Kit.Motion.EASE)
			group.modulate.a = clampf(v / 0.35, 0.0, 1.0)
			group.position = target + Vector2(0, 24.0 * (1.0 - k)), 0.0, 1.0, 0.36)

	func close() -> void:
		if closing: return
		closing = true
		UiHub.sfx("close")
		closed.emit()
		if UiHub.reduced_motion:
			queue_free(); return
		var t := create_tween().set_parallel(true)
		t.tween_property(shade, "modulate:a", 0.0, 0.22)
		t.tween_property(group, "modulate:a", 0.0, 0.2)
		t.tween_property(group, "position:y", group.position.y + 20, 0.24)
		t.chain().tween_callback(queue_free)

## Shared floating / mobile-portrait text composer modal (used by ActionPanel & Story Oracle).
static func open_text_composer(layer: Node, spec: Dictionary, on_apply: Callable, on_close := Callable()) -> Control:
	if layer == null: return null
	for ch in layer.get_children():
		if is_instance_valid(ch) and ch.name == "FloatingComposerOverlay":
			ch.queue_free()
	var portrait_mode := bool(spec.get("portrait_mode", false))
	UiHub.set_mobile_portrait(portrait_mode)
	var full_sz := Vector2(1920, 1080)
	if layer is Control and (layer as Control).size.x > 100.0:
		full_sz = (layer as Control).size

	var ov := Control.new()
	ov.name = "FloatingComposerOverlay"
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.position = Vector2.ZERO
	ov.size = full_sz
	ov.set_meta("portrait_mode", portrait_mode)
	layer.add_child(ov)

	var shade := ColorRect.new(); shade.size = full_sz
	Kit.frost(shade)
	ov.add_child(shade)

	var pw := minf(680.0, full_sz.x - 48.0) if portrait_mode else minf(1440.0, full_sz.x - 160.0)
	var ph := (full_sz.y - 64.0) if portrait_mode else minf(760.0, full_sz.y - 140.0)
	var card := Plate.new(); card.name = "ComposerCard"
	card.shape = "cut"; card.slant = 28; card.corner = "tr"; card.hatch = true; card.fill_alpha = 0.98
	card.position = Vector2((full_sz.x - pw) * 0.5, (full_sz.y - ph) * 0.5); card.size = Vector2(pw, ph)
	ov.add_child(card)

	var def_title := "手机竖屏输入（确认后填回）" if portrait_mode else "自由输入 · 悬浮大窗（随时可修改）"
	var title_lbl := Lbl.new()
	title_lbl.setup(String(spec.get("title", def_title)), 23 if portrait_mode else 26, "ink", 900)
	title_lbl.position = Vector2(30, 20); title_lbl.size = Vector2(pw - 284.0, 44)
	card.add_child(title_lbl)

	var mode_btn := Btn.new(); mode_btn.name = "TogglePortraitBtn"
	mode_btn.setup("切回悬浮大窗" if portrait_mode else "切到竖屏输入", "swap", "chip", 17)
	mode_btn.position = Vector2(pw - 242.0, 18); mode_btn.size = Vector2(154.0, 44)
	card.add_child(mode_btn)

	var close_x := Btn.new(); close_x.name = "CloseComposerX"
	close_x.setup("", "close", "icon", 18)
	close_x.position = Vector2(pw - 76.0, 16); close_x.size = Vector2(54.0, 48)
	card.add_child(close_x)

	var def_tip := "先在这里舒舒服服写下长段文字；点右下角「确认并填入」后会自动写回输入框，发送前仍可继续微调。"
	var tip_lbl := Lbl.new()
	tip_lbl.setup(String(spec.get("tip", def_tip)), 18, "muted", 600)
	tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.position = Vector2(30, 70); tip_lbl.size = Vector2(pw - 60.0, 48)
	card.add_child(tip_lbl)

	var te := TextEdit.new(); te.name = "ComposerTextEdit"
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.placeholder_text = String(spec.get("placeholder", "请在此输入内容…"))
	te.text = String(spec.get("text", ""))
	te.caret_blink = true
	te.position = Vector2(30, 126); te.size = Vector2(pw - 60.0, ph - 228.0)
	card.add_child(te)

	var count_lbl := Lbl.new()
	count_lbl.setup("%d 字" % te.text.length(), 18, "muted", 700)
	count_lbl.position = Vector2(30, ph - 82.0); count_lbl.size = Vector2(120, 56)
	count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(count_lbl)
	te.text_changed.connect(func(): count_lbl.text = "%d 字" % te.text.length())

	var close_modal := func() -> void:
		if is_instance_valid(ov): ov.queue_free()
		if UiHub.mobile_portrait_input: UiHub.set_mobile_portrait(false)
		UiHub.sfx("collapse")
		if on_close.is_valid(): on_close.call()

	ov.set_meta("close_cb", close_modal)
	close_x.pressed.connect(close_modal)

	mode_btn.pressed.connect(func():
		var nxt := spec.duplicate(true)
		nxt["text"] = te.text
		nxt["portrait_mode"] = not portrait_mode
		open_text_composer(layer, nxt, on_apply, on_close)
	)

	var clr_b := Btn.new(); clr_b.name = "ComposerClearBtn"
	clr_b.setup("清空", "trash", "ghost", 18)
	clr_b.position = Vector2(pw - 422.0, ph - 84.0); clr_b.size = Vector2(102, 58)
	clr_b.pressed.connect(func(): te.text = ""; count_lbl.text = "0 字")
	card.add_child(clr_b)

	var cancel_b := Btn.new(); cancel_b.name = "ComposerCancelBtn"
	cancel_b.setup("取消", "close", "secondary", 19)
	cancel_b.position = Vector2(pw - 310.0, ph - 84.0); cancel_b.size = Vector2(118, 58)
	cancel_b.pressed.connect(close_modal)
	card.add_child(cancel_b)

	var ok_b := Btn.new(); ok_b.name = "ComposerConfirmBtn"
	ok_b.setup("确认并填入", "check", "primary", 19)
	ok_b.position = Vector2(pw - 182.0, ph - 84.0); ok_b.size = Vector2(156, 58)
	ok_b.pressed.connect(func():
		var val := te.text
		if is_instance_valid(ov): ov.queue_free()
		if UiHub.mobile_portrait_input: UiHub.set_mobile_portrait(false)
		UiHub.sfx("confirm")
		if on_apply.is_valid(): on_apply.call(val)
	)
	card.add_child(ok_b)

	if layer is Control:
		var relayout := func() -> void:
			if not is_instance_valid(ov): return
			var nsz := (layer as Control).size
			if nsz.x < 100.0 or nsz.y < 100.0: return
			ov.size = nsz; shade.size = nsz
			var npw := minf(680.0, nsz.x - 48.0) if portrait_mode else minf(1440.0, nsz.x - 160.0)
			var nph := (nsz.y - 64.0) if portrait_mode else minf(760.0, nsz.y - 140.0)
			card.position = Vector2((nsz.x - npw) * 0.5, (nsz.y - nph) * 0.5)
			card.size = Vector2(npw, nph)
			title_lbl.size = Vector2(npw - 284.0, 44)
			mode_btn.position = Vector2(npw - 242.0, 18)
			close_x.position = Vector2(npw - 76.0, 16)
			tip_lbl.size = Vector2(npw - 60.0, 48)
			te.size = Vector2(npw - 60.0, nph - 228.0)
			count_lbl.position = Vector2(30, nph - 82.0)
			clr_b.position = Vector2(npw - 422.0, nph - 84.0)
			cancel_b.position = Vector2(npw - 310.0, nph - 84.0)
			ok_b.position = Vector2(npw - 182.0, nph - 84.0)
		layer.resized.connect(relayout)
		ov.tree_exited.connect(func():
			if is_instance_valid(layer) and layer.resized.is_connected(relayout):
				layer.resized.disconnect(relayout)
		)

	te.call_deferred("grab_focus")
	Kit.pop(card)
	UiHub.sfx("popup")
	return ov
