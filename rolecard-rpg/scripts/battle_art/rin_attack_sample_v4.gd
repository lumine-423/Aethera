extends Node2D
## Standalone presentation sample: no battle rules, damage, or persistent state.
const DURATION := 4.4
const VFX := "res://assets/effects/rin-space-cut-24fps-01/"
var time := 0.0
var idle: Node2D
var pose: Sprite2D
var effect: Sprite2D
var lines: Sprite2D
var cut_frames: Array[Texture2D] = []
var trail: Sprite2D
var hit_feedback: Node2D
var hit_holder: Node2D
var target_offset := Vector2.ZERO
var flash: ColorRect
func texture_from(path: String) -> Texture2D:
    var img := Image.load_from_file(ProjectSettings.globalize_path(path))
    if img == null or img.is_empty(): push_error("Missing image: " + path); return null
    return ImageTexture.create_from_image(img)
func make_sprite(texture: Texture2D, pos: Vector2, height: float) -> Sprite2D:
    var n := Sprite2D.new(); n.texture=texture; n.position=pos; n.centered=false
    n.offset=Vector2(-texture.get_width()/2.0,-texture.get_height())
    n.scale=Vector2.ONE * height / texture.get_height(); n.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
    return n
func _ready() -> void:
    idle=load("res://scenes/rin_idle_mad_01.tscn").instantiate(); idle.position=Vector2(340,646); idle.scale=Vector2.ONE*0.87; idle.character_path="res://assets/characters/rin-idle-mad-02/rin-base.png"; add_child(idle)
    var attack_tex := texture_from("res://assets/characters/rin-attack-mad-01/attack.png")
    if attack_tex == null: return
    pose=make_sprite(attack_tex,Vector2(340,646),505); add_child(pose); pose.visible=false
    effect = load("res://scripts/battle_art/frame_effect.gd").new()
    if not effect.configure_manifest("res://data/battle_presentation/rin_base_attack_space_cut_minimal.json"): push_error("Effect frame setup failed"); return
    cut_frames = effect.frames
    effect.position=Vector2(885,376);effect.scale=Vector2.ONE*0.38;effect.z_index=3;add_child(effect)
    trail=load("res://scripts/battle_art/frame_effect.gd").new()
    if not trail.configure_manifest("res://data/battle_presentation/rin_base_attack_body_trail.json"):return
    trail.position=Vector2(481,361);trail.scale=Vector2.ONE*0.21;trail.z_index=1;add_child(trail)
    lines=load("res://scripts/battle_art/frame_effect.gd").new()
    if not lines.configure_manifest("res://data/battle_presentation/shared_speedline_neutral.json"):return
    lines.centered=false;lines.scale=Vector2(1280.0/lines.frames[0].get_width(),720.0/lines.frames[0].get_height());lines.z_index=2;add_child(lines)
    flash=ColorRect.new();flash.size=Vector2(1280,720);flash.color=Color(1,1,1,0);flash.mouse_filter=Control.MOUSE_FILTER_IGNORE;flash.z_index=4;add_child(flash)
    hit_holder=Node2D.new();hit_holder.position=Vector2(890,438);hit_holder.z_index=4;add_child(hit_holder)
    hit_feedback=load("res://scripts/battle_art/hit_feedback.gd").new();hit_holder.add_child(hit_feedback)
    set_time(0)
func _process(delta:float) -> void:
    time=fposmod(time+delta,DURATION);set_time(time)
func set_time(t:float) -> void:
    if pose == null or effect == null or lines == null or flash == null or trail == null or cut_frames.size()!=15:return
    time=fposmod(t,DURATION)
    var attacking := time>=1.05 and time<2.18
    idle.visible=not attacking;pose.visible=attacking
    lines.visible=false
    effect.seek(time - 1.30)
    trail.visible=false
    flash.color=Color(1,1,1,0.0)
    target_offset=hit_feedback.seek(time - 1.45)
    # A short framing push and hit shake affect the whole sample stage.
    scale=Vector2.ONE; position=Vector2.ZERO
    # A slight forward push of the attacking pose.
    pose.position=Vector2(340 + (12 if time>=1.31 and time<1.48 else 0),646)
    queue_redraw()
func _draw() -> void:
    draw_rect(Rect2(0,0,1280,720),Color("172236"))
    draw_rect(Rect2(0,504,1280,216),Color("263649"))
    draw_line(Vector2(0,504),Vector2(1280,504),Color("50677a"),2)
    # Clearly temporary training target.
    var hit:= time>=1.45 and time<1.65
    var pos:=Vector2(890,438)+target_offset
    draw_circle(pos,72,Color("d4e0e9") if hit else Color("536d80"))
    draw_arc(pos,72,0,TAU,64,Color("b8d4e5"),5)
    draw_arc(pos,38,0,TAU,64,Color("263f51"),5)
    draw_line(pos+Vector2(0,72),pos+Vector2(0,130),Color("8aa4b4"),8)






