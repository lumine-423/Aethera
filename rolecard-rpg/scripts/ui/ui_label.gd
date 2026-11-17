extends Label
## Label bound to a palette role and the global text-size slider.
## Automatically fits overly wide single-line strings and non-scrolling fixed boxes so text is never sliced off.
const Kit = preload("res://scripts/ui/ui_kit.gd")
var role := "ink"
var base_px := 26
var weight := 600
var alpha := 1.0
var fit_to_box := true
var _fitting := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiHub.palette_changed.connect(refresh)
	UiHub.options_changed.connect(refresh)
	resized.connect(_on_resized)
	refresh()

func setup(value: String, px := 26, color_role := "ink", w := 600) -> Label:
	text = value; base_px = px; role = color_role; weight = w
	if is_inside_tree(): refresh()
	return self

func _on_resized() -> void:
	if not _fitting and is_inside_tree():
		refresh()

func refresh() -> void:
	if _fitting: return
	_fitting = true
	var f := Kit.font(weight)
	var target_px := UiHub.fs(base_px)
	var in_container := get_parent() is Container
	if fit_to_box and not in_container and size.x > 20.0 and text.strip_edges() != "":
		if autowrap_mode == TextServer.AUTOWRAP_OFF:
			var max_w := 0.0
			for line in text.split("\n"):
				max_w = maxf(max_w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, target_px).x)
			if max_w > size.x - 2.0:
				var lo := mini(13, target_px)
				var fit := clampi(int(floor(float(target_px) * (size.x - 2.0) / maxf(max_w, 1.0))), lo, target_px)
				while fit > lo:
					var cur_w := 0.0
					for line in text.split("\n"):
						cur_w = maxf(cur_w, f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fit).x)
					if cur_w <= size.x - 2.0: break
					fit -= 1
				target_px = fit
				text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		elif size.y > 24.0:
			var min_px := mini(14, target_px)
			while target_px > min_px:
				add_theme_font_override("font", f)
				add_theme_font_size_override("font_size", target_px)
				add_theme_constant_override("line_spacing", maxi(2, int(target_px * 0.28)))
				var lines := get_line_count()
				var est_h := float(lines) * (float(target_px) * 1.28 + float(maxi(2, int(target_px * 0.28))))
				if est_h <= size.y + 2.0: break
				target_px -= 1
	add_theme_font_override("font", f)
	add_theme_font_size_override("font_size", target_px)
	add_theme_color_override("font_color", UiHub.c(role, alpha))
	add_theme_constant_override("line_spacing", maxi(2, int(target_px * 0.28)))
	_fitting = false
