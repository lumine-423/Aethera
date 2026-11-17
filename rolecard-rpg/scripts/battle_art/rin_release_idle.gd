extends Node2D
## Single image and procedural float, not drawn animation frames.
const PERIOD := 4.0
var elapsed := 0.0
var actor: Sprite2D
var breath: ShaderMaterial
var ready_ok := false
func _ready() -> void:
    var im := Image.load_from_file(ProjectSettings.globalize_path("res://assets/characters/rin-release-03/release.png"))
    if im == null or im.is_empty(): push_error("Missing release source"); return
    actor = Sprite2D.new()
    actor.texture = ImageTexture.create_from_image(im)
    actor.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
    actor.scale = Vector2.ONE * 550.0 / im.get_height()
    actor.position = Vector2(640, 325)
    breath = ShaderMaterial.new()
    breath.shader = load("res://scripts/battle_art/idle_breath.gdshader")
    actor.material = breath
    add_child(actor)
    ready_ok = true
    seek(0.0)
func _draw() -> void:
    draw_rect(Rect2(0, 0, 1280, 720), Color("172637"))
    draw_rect(Rect2(0, 650, 1280, 70), Color("263b4a"))
    draw_line(Vector2(0, 650), Vector2(1280, 650), Color("577083"), 2.0)
func _process(delta: float) -> void:
    if ready_ok: seek(elapsed + delta)
func seek(t: float) -> void:
    elapsed = fposmod(t, PERIOD)
    var phase := elapsed / PERIOD * TAU
    actor.position.y = 325.0 + 5.0 * sin(phase)
    breath.set_shader_parameter("phase", phase)
