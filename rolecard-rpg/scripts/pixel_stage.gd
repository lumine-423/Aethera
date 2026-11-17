extends Control
## Unapproved coherence draft. Released form remains an explicit diagnostic marker.
const SHEET = preload("res://assets/characters/rin-motion-v2/motion.png")
const PREVIOUS_ATTACK = preload("res://assets/characters/rin-study/cast-study.png")
var actor: AnimatedSprite2D
var cast_duration := 1.0
var form_id := "base"
var phase := "idle"
var elapsed := 0.0
var phase_duration := 0.0
var paused := false
var form_notice: Label

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	actor = AnimatedSprite2D.new()
	actor.centered = false
	actor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	actor.sprite_frames = SpriteFrames.new()
	actor.sprite_frames.remove_animation("default")
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/rin-motion-v2/motion.json"))
	assert(data is Dictionary and data.get("frames") is Array, "Missing Aseprite metadata")
	cast_duration = 0.0
	for tag in data["meta"]["frameTags"]:
		var name: String = tag["name"]
		if name != "idle":
			continue # New generated attack failed the planted-foot gate; preview only.
		actor.sprite_frames.add_animation(name)
		actor.sprite_frames.set_animation_loop(name, name == "idle")
		actor.sprite_frames.set_animation_speed(name, 1000.0)
		for index in range(int(tag["from"]), int(tag["to"]) + 1):
			var item: Dictionary = data["frames"][index]
			var bounds: Dictionary = item["frame"]
			var region := AtlasTexture.new()
			region.atlas = SHEET
			region.region = Rect2(bounds["x"], bounds["y"], bounds["w"], bounds["h"])
			actor.sprite_frames.add_frame(name, region, float(item["duration"]))
	actor.sprite_frames.add_animation("attack")
	actor.sprite_frames.set_animation_loop("attack", false)
	actor.sprite_frames.set_animation_speed("attack", 1000.0)
	var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/rin-study/cast-study.json"))
	for item in previous["frames"]:
		var bounds: Dictionary = item["frame"]
		var region := AtlasTexture.new()
		region.atlas = PREVIOUS_ATTACK
		region.region = Rect2(bounds["x"], bounds["y"], bounds["w"], bounds["h"])
		actor.sprite_frames.add_frame("attack", region, float(item["duration"]))
		cast_duration += float(item["duration"]) / 1000.0
	add_child(actor)
	form_notice = Label.new()
	form_notice.position = Vector2(8, 8)
	form_notice.add_theme_font_size_override("font_size", 15)
	form_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(form_notice)
	set_form("base")
	actor.play("idle")
	resized.connect(_position_actor)
	_position_actor()

func _position_actor() -> void:
	if actor == null:
		return
	var multiplier := 2.0 if size.x >= 650 else 1.0
	actor.scale = Vector2.ONE * multiplier
	actor.position = Vector2(floorf(size.x * 0.25) - 58 * multiplier, floorf(size.y * 0.87) - 144 * multiplier)
	queue_redraw()

func set_form(value: String) -> void:
	form_id = value
	actor.visible = form_id == "base"
	form_notice.text = "基础形态 · 新待机候选/旧普攻草稿，尚未验收" if form_id == "base" else "鸟羽形态 · 正式素材待制作；仅验证形态与规则"
	queue_redraw()

func play_action(command: String, presentation: Dictionary = {}) -> float:
	set_form(presentation.get("from_form", form_id))
	phase = command
	elapsed = 0.0
	phase_duration = cast_duration if command == "attack" and form_id == "base" else (0.8 if command in ["liberate", "ultimate"] else 0.35)
	if command == "attack" and form_id == "base":
		actor.play("attack")
		actor.set_frame_and_progress(0, 0.0)
	return phase_duration

func finish_action() -> void:
	actor.play("idle")
	actor.frame = 0
	phase = "idle"
	queue_redraw()

func set_paused(value: bool) -> void:
	paused = value
	if actor != null:
		actor.speed_scale = 0.0 if value else 1.0

func _process(delta: float) -> void:
	if not paused and phase != "idle":
		elapsed += delta
		queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("182332"))
	var ground := floorf(size.y * 0.87)
	draw_rect(Rect2(0, ground, size.x, 2), Color("597080"))
	var origin := Vector2(floorf(size.x * 0.74), ground)
	draw_rect(Rect2(origin + Vector2(-20,-76), Vector2(40,58)), Color("7895a8"))
	draw_rect(Rect2(origin + Vector2(-5,-18), Vector2(10,18)), Color("4c6479"))
	draw_circle(origin + Vector2(0,-50), 12, Color("293a50"))
	var root := Vector2(floorf(size.x * 0.25), ground)
	if form_id == "released":
		draw_rect(Rect2(root + Vector2(-25,-130), Vector2(50,130)), Color("5c849c"), false, 2)
		draw_line(root + Vector2(-40,-90), root + Vector2(40,-90), Color("83bfd3"), 2)
	if phase == "guard":
		draw_rect(Rect2(root + Vector2(52,-100), Vector2(5,95)), Color("8bbdce"))
	elif phase == "liberate":
		var step := int(elapsed * 12) % 6
		for index in range(6):
			draw_rect(Rect2(root + Vector2(-48 + index * 16, -40 - ((index + step) % 6) * 18), Vector2(8,8)), Color("a6d8ef"))
	elif phase == "ultimate":
		var x := lerpf(root.x, origin.x, clampf(elapsed / 0.35, 0, 1))
		for index in range(4):
			draw_rect(Rect2(Vector2(floorf(x) - index * 18, ground - 75), Vector2(12,3)), Color("83bfd3"))
