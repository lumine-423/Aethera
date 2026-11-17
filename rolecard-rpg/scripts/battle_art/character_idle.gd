extends Node2D
## Independent single-image idle prototype. No battle rules or host state.
@export var character_path := "res://assets/characters/rin-idle-mad-01/rin-base.png"
@export var loop_seconds := 3.6
@export var motion_enabled := true
var elapsed := 0.0
var sprite: Sprite2D
var material_ref: ShaderMaterial
func _ready() -> void:
    var image := Image.load_from_file(ProjectSettings.globalize_path(character_path))
    if image == null or image.is_empty():
        push_error("Idle source image missing: " + character_path)
        return
    sprite = Sprite2D.new()
    sprite.texture = ImageTexture.create_from_image(image)
    sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    sprite.centered = false
    sprite.offset = Vector2(-image.get_width() * 0.5, -image.get_height())
    var target_height := 580.0
    sprite.scale = Vector2.ONE * target_height / image.get_height()
    material_ref = ShaderMaterial.new()
    material_ref.shader = load("res://scripts/battle_art/idle_breath.gdshader")
    sprite.material = material_ref
    add_child(sprite)
func _process(delta: float) -> void:
    if material_ref == null or not motion_enabled: return
    elapsed = fposmod(elapsed + delta, maxf(loop_seconds, 0.01))
    material_ref.set_shader_parameter("phase", elapsed / loop_seconds * TAU)
func set_motion_enabled(value: bool) -> void:
    motion_enabled = value
    if not value and material_ref != null: material_ref.set_shader_parameter("phase", 0.0)
