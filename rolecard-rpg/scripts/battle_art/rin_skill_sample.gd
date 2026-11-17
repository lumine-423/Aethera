extends Node2D
## Concept-only presentation: no battle damage/skills state.
@export_range(1,2) var skill_id := 1
const DURATION := 7.2 # two exact 3.6-second idle periods for captured loop
var time := 0.0
var idle: Node2D
var pose: Sprite2D
var fx: Sprite2D
var hit_holder: Node2D
var hitfx: Node2D
var target_offset:=Vector2.ZERO
func texture_from(path: String) -> Texture2D:
    var img:=Image.load_from_file(ProjectSettings.globalize_path(path))
    if img == null or img.is_empty():return null
    return ImageTexture.create_from_image(img)
func _ready() -> void:
    idle=load("res://scenes/rin_idle_mad_01.tscn").instantiate();idle.character_path="res://assets/characters/rin-idle-mad-02/rin-base.png";idle.position=Vector2(340,646);idle.scale=Vector2.ONE*0.87;add_child(idle)
    var tex:=texture_from("res://assets/characters/rin-skills-01/s%dpose.png"%skill_id)
    if tex==null:push_error("missing skill pose");return
    pose=Sprite2D.new();pose.texture=tex;pose.centered=false;pose.offset=Vector2(-tex.get_width()/2.0,-tex.get_height());pose.scale=Vector2.ONE*505.0/tex.get_height();pose.position=Vector2(340,646);pose.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;add_child(pose)
    fx=load("res://scripts/battle_art/frame_effect.gd").new()
    if not fx.configure_manifest("res://data/battle_presentation/rin_base_skill_%d_sample01.json"%skill_id):push_error("missing skill frames");return
    fx.position=Vector2(890,410);fx.z_index=2;add_child(fx)
    hit_holder=Node2D.new();hit_holder.position=Vector2(890,438);hit_holder.z_index=3;add_child(hit_holder)
    hitfx=load("res://scripts/battle_art/hit_feedback.gd").new();hit_holder.add_child(hitfx)
    set_time(0.0)
func _process(delta:float) -> void:
    time=fposmod(time+delta,DURATION);set_time(time)
func set_time(t:float) -> void:
    if fx==null or pose==null or hitfx==null:return
    time=fposmod(t,DURATION)
    pose.visible=time>=0.95 and time<2.15;idle.visible=not pose.visible
    var dt:=time-1.20
    fx.seek(dt)
    if fx.visible:
        # The images are actual individual frames; transforms add coherent motion, not extra frames.
        var phase:=clampf(dt/0.5,0.0,1.0)
        # Readable lifecycle: appear, expand, hold/impact, then contract and vanish.
        var appear:=clampf(phase/0.32,0.0,1.0)
        var disappear:=clampf((1.0-phase)/0.28,0.0,1.0)
        var extent:=minf(appear,disappear)
        fx.modulate.a=minf(clampf(phase/0.12,0.0,1.0),clampf((1.0-phase)/0.18,0.0,1.0))
        if skill_id==1:
            fx.scale=Vector2(0.34*lerpf(0.16,1.0,extent),0.32*lerpf(0.16,1.0,extent))
            fx.rotation=0.0
        else:
            fx.scale=Vector2.ONE*0.36*lerpf(0.16,1.0,extent)
            fx.rotation=lerpf(-0.14,0.16,phase)
    target_offset=hitfx.seek(time-1.48)
    queue_redraw()
func _draw() -> void:
    draw_rect(Rect2(0,0,1280,720),Color("172236"))
    draw_rect(Rect2(0,504,1280,216),Color("263649"));draw_line(Vector2(0,504),Vector2(1280,504),Color("50677a"),2)
    var hit:=time>=1.48 and time<1.70
    var p:=Vector2(890,438)+target_offset
    draw_circle(p,72,Color("d4e0e9") if hit else Color("536d80"));draw_arc(p,72,0,TAU,64,Color("b8d4e5"),5);draw_arc(p,38,0,TAU,64,Color("263f51"),5);draw_line(p+Vector2(0,72),p+Vector2(0,130),Color("8aa4b4"),8)

