extends Node2D
## One still defensive pose; no invented shield or combat rules.
var elapsed := 0.0
var idle: Node2D
var pose: Sprite2D
var hitfx: Node2D
func _ready() -> void:
	idle = load("res://scenes/rin_idle_mad_01.tscn").instantiate()
	idle.character_path = "res://assets/characters/rin-idle-mad-02/rin-base.png"
	idle.position = Vector2(480, 660); add_child(idle)
	var image := Image.load_from_file(ProjectSettings.globalize_path("res://assets/characters/rin-guard-02/guard.png"))
	if image == null or image.is_empty(): push_error("Guard pose missing"); return
	pose = Sprite2D.new(); pose.texture = ImageTexture.create_from_image(image)
	pose.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pose.scale = Vector2.ONE * 580.0 / image.get_height()
	pose.position = Vector2(480, 660 - 290); add_child(pose)
	var holder := Node2D.new(); holder.position = Vector2(480, 365); holder.z_index = 2; add_child(holder)
	hitfx = load("res://scripts/battle_art/hit_feedback.gd").new()
	hitfx.effect_size = Vector2(680, 650); holder.add_child(hitfx)
	seek(0.0)
func _process(delta: float) -> void:
	seek(fposmod(elapsed + delta, 3.6))
func seek(t: float) -> void:
	elapsed = t
	if pose == null: return
	pose.visible = elapsed >= 0.8 and elapsed < 2.5
	idle.visible = not pose.visible
	var offset: Vector2 = hitfx.seek(elapsed - 1.2)
	pose.position = Vector2(480, 660 - 290) + offset
func _draw() -> void:
	draw_rect(Rect2(0, 0, 960, 720), Color("e8edf2"))
	draw_line(Vector2(0, 660), Vector2(960, 660), Color("a6b3c0"), 2.0)
