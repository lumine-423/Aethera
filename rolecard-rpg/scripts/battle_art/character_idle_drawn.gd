extends Node2D
## Five independently illustrated stills, played in explicit timed sequence.
const DIR := "res://assets/characters/rin-idle-drawn-01/"
const FILES := ["neutral.png", "breath-middle.png", "breath-peak.png", "blink-half.png", "blink-closed.png"]
# Seconds and frame indices; open -> breath -> blink -> open. No interpolation.
const STEPS := [[0,0.55],[1,0.30],[2,0.45],[1,0.30],[0,0.65],[3,0.08],[4,0.12],[3,0.08],[0,0.87]]
var textures: Array[Texture2D] = []
var sprite: Sprite2D
var elapsed := 0.0
var duration := 0.0
var current_index := -1
func _ready() -> void:
    for filename in FILES:
        var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + filename))
        if img == null or img.is_empty(): push_error("Missing idle image: " + filename); return
        textures.append(ImageTexture.create_from_image(img))
    for step in STEPS: duration += step[1]
    sprite = Sprite2D.new(); sprite.centered = false; sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    sprite.offset = Vector2(-textures[0].get_width() * 0.5, -textures[0].get_height())
    sprite.scale = Vector2.ONE * 580.0 / textures[0].get_height()
    add_child(sprite); set_time(0.0)
func set_time(seconds: float) -> void:
    if sprite == null or duration <= 0.0: return
    var t := fposmod(seconds,duration)
    for step in STEPS:
        if t < step[1]:
            current_index = step[0]; sprite.texture = textures[current_index]; return
        t -= step[1]
func _process(delta: float) -> void:
    elapsed += delta
    set_time(elapsed)

