extends Node2D
## Visual-only transition: no combat-state mutation. Uses independent 24fps images.
@export_file("*.json") var config_path := "res://data/battle_presentation/rin_release_transition_01.json"
var config: Dictionary = {}
var elapsed := 0.0
var playing := true
var ready_ok := false
var base: Sprite2D
var released: Sprite2D
var chain: Sprite2D
var flash: ColorRect
var frames: Array[Texture2D] = []

func load_image(path: String) -> Texture2D:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		push_error("Missing image: " + path); return null
	return ImageTexture.create_from_image(image)

func character(tex: Texture2D, height: float) -> Sprite2D:
	var s := Sprite2D.new(); s.texture = tex; s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	s.scale = Vector2.ONE * height / tex.get_height()
	s.position = Vector2(640, 650 - height / 2.0)
	return s

func _ready() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not data is Dictionary: push_error("Invalid transition config"); return
	config = data
	var before := load_image(config.base_image)
	var after := load_image(config.release_image)
	if before == null or after == null: return
	for path in config.chain_frames:
		var frame := load_image(str(path))
		if frame == null: return
		frames.append(frame)
	if frames.size() != 24: push_error("Expected 24 independent chain frames"); return
	base = character(before, 505.0); add_child(base)
	# Wings widen the image bounds; a slightly taller canvas keeps the body visually comparable.
	released = character(after, 550.0); released.position.y -= 50.0; add_child(released)
	chain = Sprite2D.new(); chain.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	chain.position = Vector2(640, 100); chain.z_index = 2; add_child(chain)
	flash = ColorRect.new(); flash.size = Vector2(1280, 720); flash.color = Color(1, 1, 1, 0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE; flash.z_index = 3; add_child(flash)
	ready_ok = true; seek(0.0)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("172637"))
	draw_rect(Rect2(0, 650, 1280, 70), Color("263b4a"))
	draw_line(Vector2(0, 650), Vector2(1280, 650), Color("577083"), 2.0)

func _process(delta: float) -> void:
	if ready_ok and playing:
		seek(minf(elapsed + delta, float(config.duration)))
		if elapsed >= float(config.duration): playing = false

func seek(seconds: float) -> void:
	if not ready_ok: return
	elapsed = clampf(seconds, 0.0, float(config.duration))
	base.visible = elapsed < float(config.switch_time)
	released.visible = not base.visible
	var d := elapsed - float(config.chain_start)
	var i := int(floor(d * 24.0))
	chain.visible = d >= 0 and i >= 0 and i < frames.size()
	if chain.visible:
		chain.texture = frames[i]
		# The independently drawn frames are additionally revealed downward from the top.
		var extent := lerpf(0.18, 1.0, clampf(d / 0.30, 0.0, 1.0))
		chain.scale = Vector2(1000, 400 * extent) / chain.texture.get_size()
		chain.position = Vector2(640, -100 + 200 * extent)
		chain.modulate.a = clampf((1.0 - d) / 0.22, 0.0, 1.0)
	var f := elapsed - float(config.flash_start)
	var alpha := 0.0
	if f >= 0.0 and f < float(config.flash_duration):
		if f < 0.06:
			alpha = clampf(f / 0.06, 0.0, 1.0)
		elif f < 0.14:
			alpha = 1.0
		else:
			alpha = clampf((float(config.flash_duration) - f) / (float(config.flash_duration) - 0.14), 0.0, 1.0)
	flash.color = Color(1, 1, 1, alpha)

func restart() -> void:
	seek(0.0); playing = true
func set_paused(value: bool) -> void:
	playing = not value
func skip() -> void:
	seek(float(config.duration)); playing = false
