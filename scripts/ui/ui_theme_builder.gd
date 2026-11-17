extends RefCounted
## Builds the Godot Theme for native input controls (text fields, dropdowns, popups, scrollbars,
## tooltips) from the live palette. The root re-applies it on every day/night change.
const Kit = preload("res://scripts/ui/ui_kit.gd")

static func _box(fill: Color, border: Color, bw := 1, skew := 0.0, pad := Vector4(16, 8, 16, 8)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill; s.border_color = border
	# mystic pass: hairline borders, soft round corners, no skew
	s.set_border_width_all(mini(bw, 1)); s.set_corner_radius_all(14 if skew != 0.0 else 10)
	if bw >= 2: s.border_width_bottom = 2
	s.corner_detail = 8
	s.content_margin_left = pad.x; s.content_margin_top = pad.y; s.content_margin_right = pad.z; s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = Kit.font(600)
	t.default_font_size = UiHub.fs(26)
	var ink := UiHub.c("ink"); var muted := UiHub.c("muted"); var acc := UiHub.c("accent")
	var field := _box(UiHub.c("surface2", 0.95), UiHub.c("line"), 1, -0.12, Vector4(20, 10, 20, 10))
	var focus := _box(UiHub.c("surface", 0.98), acc, 2, -0.12, Vector4(20, 10, 20, 10))
	for kind in ["LineEdit", "TextEdit"]:
		var sk := -0.12 if kind == "LineEdit" else 0.0
		t.set_stylebox("normal", kind, _box(UiHub.c("surface2", 0.95), UiHub.c("line"), 1, sk, Vector4(20, 10, 20, 10)))
		t.set_stylebox("focus", kind, _box(UiHub.c("surface", 0.98), UiHub.c("accent"), 2, sk, Vector4(20, 10, 20, 10)))
		t.set_stylebox("read_only", kind, _box(UiHub.c("surface2", 0.6), UiHub.c("line", 0.6), 1, -0.12))
		t.set_color("font_color", kind, ink); t.set_color("font_placeholder_color", kind, muted)
		t.set_color("caret_color", kind, acc); t.set_color("selection_color", kind, UiHub.c("accent", 0.3))
		t.set_color("font_selected_color", kind, ink)
		t.set_font_size("font_size", kind, UiHub.fs(26))
	for kind in ["OptionButton", "MenuButton"]:
		t.set_stylebox("normal", kind, field); t.set_stylebox("hover", kind, _box(UiHub.c("surface", 0.98), UiHub.c("line"), 1, -0.12, Vector4(20, 10, 20, 10)))
		t.set_stylebox("pressed", kind, focus); t.set_stylebox("focus", kind, focus); t.set_stylebox("disabled", kind, field)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: t.set_color(c, kind, ink)
		t.set_font_size("font_size", kind, UiHub.fs(26))
	var popup := _box(UiHub.c("surface", 0.99), UiHub.c("line"), 1, 0.0, Vector4(8, 8, 8, 8))
	popup.shadow_color = UiHub.c("shade", 0.5); popup.shadow_size = 12
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(UiHub.c("accent", 0.1), UiHub.c("accent", 0.6), 1, -0.1))
	t.set_color("font_color", "PopupMenu", ink); t.set_color("font_hover_color", "PopupMenu", UiHub.c("on_accent"))
	t.set_font_size("font_size", "PopupMenu", UiHub.fs(24))
	t.set_constant("v_separation", "PopupMenu", 14)
	var tip := _box(UiHub.c("ink", 0.92), Color(0, 0, 0, 0), 0, 0.0, Vector4(12, 6, 12, 6))
	t.set_stylebox("panel", "TooltipPanel", tip); t.set_color("font_color", "TooltipLabel", UiHub.c("background"))
	t.set_font_size("font_size", "TooltipLabel", UiHub.fs(20))
	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", bar, _box(UiHub.c("line", 0.35), Color(0, 0, 0, 0), 0, 0.0, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber", bar, _box(UiHub.c("muted", 0.8), Color(0, 0, 0, 0), 0, 0.0, Vector4(3, 3, 3, 3)))
		t.set_stylebox("grabber_highlight", bar, _box(acc, Color(0, 0, 0, 0), 0))
		t.set_stylebox("grabber_pressed", bar, _box(acc, Color(0, 0, 0, 0), 0))
	t.set_color("font_color", "Label", ink)
	t.set_stylebox("panel", "PanelContainer", StyleBoxEmpty.new())
	return t
