extends Node2D
## Configured demonstration only. No combat damage, resources or game-state writes.
@export_file("*.json") var config_path := "res://data/battle_presentation/rin_base_ultimate_demo.json"
var data: Dictionary = {}
var elapsed := 0.0
var paused := false
var ready_ok := false
var world: Node2D
var idle: Node2D
var pose: Sprite2D
var target: Node2D
var hitfx: Node2D
var eyes: Sprite2D
var frame: Sprite2D
var strikes: Array[Sprite2D] = []
var frame_textures: Array[Texture2D] = []
var cut_textures: Array[Texture2D] = []

func read_image(path: String) -> Texture2D:
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		push_error("Missing presentation image: " + path)
		return null
	return ImageTexture.create_from_image(image)

func read_frames(paths: Array, dest: Array[Texture2D]) -> bool:
	for path in paths:
		var tex := read_image(str(path))
		if tex == null: return false
		dest.append(tex)
	return true

func sprite_with_texture(tex: Texture2D, size: Vector2) -> Sprite2D:
	var item := Sprite2D.new()
	item.texture = tex
	item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	item.scale = size / tex.get_size()
	return item

func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not parsed is Dictionary:
		push_error("Invalid ultimate configuration: " + config_path); return
	data = parsed
	if not read_frames(data.frame_images, frame_textures) or not read_frames(data.cut_images, cut_textures): return
	if frame_textures.size() != 6 or cut_textures.size() != 12:
		push_error("Unexpected sequence length"); return
	var pose_tex := read_image(data.pose_image)
	var eyes_tex := read_image(data.eye_image)
	if pose_tex == null or eyes_tex == null: return
	world = Node2D.new(); add_child(world)
	idle = load("res://scenes/rin_idle_mad_01.tscn").instantiate()
	idle.character_path = data.idle_image
	idle.position = Vector2(355, 640); idle.scale = Vector2.ONE * 495.0 / 580.0
	world.add_child(idle)
	pose = sprite_with_texture(pose_tex, Vector2(505.0 * pose_tex.get_width() / pose_tex.get_height(), 505))
	pose.position = Vector2(355, 640 - 505.0 / 2.0); world.add_child(pose)
	target = load("res://scripts/battle_art/demo_target.gd").new()
	target.position = Vector2(900, 425); world.add_child(target)
	for i in range(data.strikes.size() + 1):
		var item := sprite_with_texture(cut_textures[0], Vector2(490, 235))
		item.z_index = 2; item.visible = false; world.add_child(item); strikes.append(item)
	var holder := Node2D.new(); holder.position = Vector2(900, 425); holder.z_index = 4; world.add_child(holder)
	hitfx = load("res://scripts/battle_art/hit_feedback.gd").new(); hitfx.effect_size = Vector2(260, 260); holder.add_child(hitfx)
	eyes = sprite_with_texture(eyes_tex, Vector2(1280, 450)); eyes.position = Vector2(640, 375); eyes.z_index = 10
	var mat := ShaderMaterial.new(); mat.shader = load("res://scripts/battle_art/geometric_eye_mask.gdshader"); eyes.material = mat; add_child(eyes)
	frame = sprite_with_texture(frame_textures[0], Vector2(1280, 510)); frame.position = Vector2(640, 360); frame.z_index = 11; add_child(frame)
	ready_ok = true; seek(0.0)

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("172637"))
	draw_rect(Rect2(0, 530, 1280, 190), Color("263b4a"))
	draw_line(Vector2(0, 530), Vector2(1280, 530), Color("577083"), 2)

func _process(delta: float) -> void:
	if ready_ok and not paused:
		seek(fposmod(elapsed + delta, float(data.duration)))

func seek(seconds: float) -> void:
	if not ready_ok: return
	elapsed = clampf(seconds, 0.0, float(data.duration))
	var zoom := 1.25 if elapsed < 1.542 else lerpf(1.25, 1.0, clampf((elapsed - 1.542) / 0.958, 0.0, 1.0))
	world.scale = Vector2.ONE * zoom
	world.position = Vector2(640, 360) * (1.0 - zoom)
	var in_pose := elapsed >= 0.72 and elapsed < 4.32
	pose.visible = in_pose; idle.visible = not in_pose
	var eye_dt := elapsed - 1.12
	var cutin_index := int(floor(eye_dt * 24.0))
	var cutin_order: Array = data.cutin_order
	frame.visible = cutin_index >= 0 and cutin_index < cutin_order.size()
	eyes.visible = elapsed >= 1.12 and elapsed < 1.45
	if frame.visible:
		frame.texture = frame_textures[int(cutin_order[cutin_index]) - 1]
		frame.scale = Vector2(1280, 510) / frame.texture.get_size()
	for i in range(data.strikes.size()):
		var spec: Dictionary = data.strikes[i]
		var index := int(floor((elapsed - float(spec.start)) / float(spec.speed) * 24.0))
		var item := strikes[i]; item.visible = elapsed >= float(spec.start) and index >= 0 and index < cut_textures.size()
		if item.visible:
			item.texture = cut_textures[index]; item.scale = Vector2(490, 235) / item.texture.get_size()
			item.position = Vector2(float(spec.x), float(spec.y)); item.rotation = float(spec.angle)
	var final_index := int(floor((elapsed - float(data.final_start)) * 24.0))
	var order: Array = data.final_order
	var last := strikes[-1]; last.visible = elapsed >= float(data.final_start) and final_index >= 0 and final_index < order.size()
	if last.visible:
		last.texture = cut_textures[int(order[final_index]) - 1]; last.scale = Vector2(1556, 750) / last.texture.get_size()
		last.position = Vector2(900, 425); last.rotation = 0.0
	var offset: Vector2 = hitfx.seek(elapsed - float(data.hit_time))
	target.position = Vector2(900, 425) + offset

func set_paused(value: bool) -> void:
	paused = value
	if idle != null: idle.set_process(not value)

func restart() -> void:
	seek(0.0); set_paused(false)

func skip() -> void:
	seek(float(data.duration)); set_paused(true)
