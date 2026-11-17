extends "res://scripts/ui/ui_screen.gd"
## 刻印制作. Narrow recipe column (left) and preview column (right); the whole center is a
## replaceable image slot (registry key "crafting_center") until the role-card workshop is migrated.
## The UI never deducts materials: it sends craft.make and shows what the service returns.

var selected := 0
var center: Control

class SigilStage extends Control:
	const I = preload("res://scripts/ui/ui_icon.gd")
	const K = preload("res://scripts/ui/ui_kit.gd")
	var sigil := "sigil_a"
	var texture: Texture2D
	var clock := 0.0
	var pulse := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE; UiHub.palette_changed.connect(queue_redraw)
	func _process(d: float) -> void:
		if UiHub.reduced_motion: return
		clock += d; queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		if texture:
			var ts := texture.get_size(); var sc := minf(size.x / ts.x, size.y / ts.y)
			draw_texture_rect(texture, Rect2(c - ts * sc * 0.5, ts * sc), false); return
		K.diamond(self, c, 330, UiHub.c("line"), 1.5)
		K.diamond(self, c, 300 + sin(clock * 0.8) * 4, UiHub.c("line", 0.7), 1.0)
		for j in range(4):
			var d := Vector2.from_angle(PI * 0.5 * j)
			K.diamond(self, c + d * 330, 7, UiHub.c("accent"), 2.0)
			draw_line(c + d * 120, c + d * 250, UiHub.c("accent", 0.8), 2.0)
			var n := Vector2(-d.y, d.x)
			for s in [-1, 1]:
				K.tri(self, c + d * 210 + n * 90 * s, 9, (j + (1 if s > 0 else 3)) % 4, UiHub.c("accent"))
		var k := 360.0 * (1.0 + pulse * 0.08)
		draw_set_transform(c, sin(clock * 0.3) * 0.03)
		I.paint(self, sigil, Rect2(-Vector2(k, k) * 0.5, Vector2(k, k)), UiHub.c("ink"), UiHub.c("accent"), UiHub.c("background"))
		draw_set_transform(Vector2.ZERO)
		if pulse > 0.0:
			draw_arc(c, 200 + (1.0 - pulse) * 220, 0, TAU, 64, UiHub.c("accent", pulse), 6.0 * pulse + 1.0, true)
		K.text(self, Rect2(0, size.y - 40, size.x, 30), "中央为可替换图片位 · 刻印工坊迁入后替换", UiHub.fs(17), UiHub.c("muted", 0.8), HORIZONTAL_ALIGNMENT_CENTER, 600)
	func burst() -> void:
		if UiHub.reduced_motion: return
		var t := create_tween(); t.tween_method(func(v): pulse = v; queue_redraw(), 1.0, 0.0, 0.7)

func build() -> void:
	chrome("刻印制作")
	var recipes: Array = Data.demo().recipes
	selected = clampi(selected, 0, recipes.size() - 1)
	var rc: Dictionary = recipes[selected]
	# left: recipes
	var head := plate(Rect2(30, 140, 330, 80), {"slant": 20, "stripe": "left", "hatch": true}, "l", 0.0)
	text("配方", Rect2(40, 0, 200, 80), 30, "ink", 850, "c", head)
	for i in range(recipes.size()):
		var r: Dictionary = recipes[i]
		var b := btn(r.name, r.icon, "secondary", Rect2(30, 240 + i * g(140), 340, 120), func(): selected = i; refresh(), "l", 0.05 + i * 0.05, null, 26)
		b.selected = i == selected; b.slant = 28; b.divider = false; b.press_sfx = "recipe"
		if i == selected: b.hatch = true
	# center
	center = SigilStage.new(); center.sigil = rc.icon
	var path: String = W.Portrait.registry.get("crafting_center", "")
	if path != "" and ResourceLoader.exists(path): center.texture = load(path)
	put(center, Rect2(420, 130, 1000, 900), "c", -1.0)
	(func(): Kit.pop(center, 0.05, 0.4)).call_deferred()
	# right: preview
	var ph := plate(Rect2(1500, 140, 390, 80), {"slant": 30, "fill": "accent", "fill_alpha": 1.0, "border": "", "glass": false, "hatch": false}, "r", 0.05)
	text("成品预览", Rect2(50, 0, 280, 80), 30, "on_accent", 850, "c", ph)
	var pv := plate(Rect2(1500, 240, 390, 260), {"shape": "rect", "corner": "br", "corner_size": 18}, "r", 0.1)
	icon(rc.icon, Rect2(30, 50, 160, 160), "ink", "c", pv)
	text(rc.result, Rect2(220, 50, 150, 50), 26, "accent", 800, "c", pv)
	text(rc.use, Rect2(220, 130, 160, 50), 24, "ink", 800, "c", pv)
	var pe := plate(Rect2(1500, 520, 390, 330), {"shape": "rect", "corner": "br", "corner_size": 18}, "r", 0.15)
	header("效果说明", Rect2(20, 14, 350, 44), 22, "c", pe)
	text(rc.desc, Rect2(30, 64, 330, 80), 20, "muted", 600, "c", pe)
	header("所需材料", Rect2(20, 150, 350, 44), 22, "c", pe)
	var enough := true
	for k in range(rc.needs.size()):
		var need: Array = rc.needs[k]
		var it := Data.item(need[0])
		var have: int = it.count
		if have < int(need[1]): enough = false
		icon(it.icon, Rect2(30, 202 + k * 56, 44, 44), "ink", "c", pe)
		text(it.name, Rect2(86, 200 + k * 56, 160, 48), 20, "ink", 700, "c", pe)
		text("%d / %d" % [have, int(need[1])], Rect2(240, 200 + k * 56, 120, 48), 20, "ink" if have >= int(need[1]) else "accent", 800, "c", pe, HORIZONTAL_ALIGNMENT_RIGHT)
	var make := btn("制作", "next", "primary", Rect2(1480, 880, 410, 130), func(): _make(rc), "r", 0.25, null, 44)
	make.center_text = true; make.disabled = not enough; make.hatch = true; make.name = "Make"; make.press_sfx = "none"

func _make(rc: Dictionary) -> void:
	request("craft.make", {"recipe": rc.id})
	UiHub.sfx("craft"); UiHub.haptic(30)
	center.burst()
	var b := W.Burst.new(); b.size = Vector2(700, 700); b.count = 18; b.spread = 420.0
	center.add_child(b); b.position = center.size * 0.5 - b.size * 0.5
	var t := create_tween(); t.tween_interval(0.5)
	t.tween_callback(func(): root.reward([{"icon": rc.icon, "count": 1}]))
