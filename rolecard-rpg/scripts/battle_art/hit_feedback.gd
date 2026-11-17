extends Node2D
## Single reusable hit image and local shake. No full-screen effect or battle rules.
@export var effect_path := "res://assets/effects/shared-hit-outline-02/impact.png"
@export var effect_size := Vector2(250.0, 250.0)
@export var duration := 0.22
@export var displacement := 4.0
var image: Sprite2D
func _ready() -> void:
    var raw := Image.load_from_file(ProjectSettings.globalize_path(effect_path))
    if raw == null or raw.is_empty(): push_error("hit image missing"); return
    image = Sprite2D.new(); image.texture=ImageTexture.create_from_image(raw)
    image.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
    image.scale=Vector2(effect_size.x/raw.get_width(), effect_size.y/raw.get_height());add_child(image);visible=false
func seek(seconds: float) -> Vector2:
    visible=seconds>=0.0 and seconds<duration
    if not visible: position=Vector2.ZERO;return Vector2.ZERO
    var strength := 1.0-seconds/duration
    var offset := Vector2(sin(seconds*85.0)*displacement*strength,0)
    position=offset
    return offset

