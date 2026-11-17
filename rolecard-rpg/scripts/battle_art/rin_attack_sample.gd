extends Node2D
## Standalone presentation sample: no battle rules, damage, or persistent state.
const DURATION := 4.4
const VFX := "res://assets/effects/rin-space-cut-01/"
var time := 0.0
var idle: Node2D
var pose: Sprite2D
var effect: Sprite2D
var lines: Sprite2D
var cut_frames: Array[Texture2D] = []
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
    idle=load("res://scenes/rin_idle_mad_01.tscn").instantiate(); idle.position=Vector2(340,646); idle.scale=Vector2.ONE*0.87; add_child(idle)
    var attack_tex := texture_from("res://assets/characters/rin-attack-mad-01/attack.png")
    if attack_tex == null: return
    pose=make_sprite(attack_tex,Vector2(340,646),505); add_child(pose); pose.visible=false
    for name in ["01-open.png","02-impact.png","03-fade.png"]:
        var t := texture_from(VFX+name)
        if t == null: return
        cut_frames.append(t)
    effect=Sprite2D.new();effect.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;effect.position=Vector2(885,376);effect.scale=Vector2.ONE*0.38;effect.z_index=3;add_child(effect)
    var speedtex:=texture_from("res://assets/effects/shared-speedline-01/speedline.png")
    if speedtex == null:return
    lines=Sprite2D.new();lines.texture=speedtex;lines.centered=false;lines.scale=Vector2(1280.0/speedtex.get_width(),720.0/speedtex.get_height());lines.z_index=2;add_child(lines)
    flash=ColorRect.new();flash.size=Vector2(1280,720);flash.color=Color(1,1,1,0);flash.mouse_filter=Control.MOUSE_FILTER_IGNORE;flash.z_index=4;add_child(flash)
    set_time(0)
func _process(delta:float) -> void:
    time=fposmod(time+delta,DURATION);set_time(time)
func set_time(t:float) -> void:
    if pose == null or effect == null or lines == null or flash == null or cut_frames.size()!=3:return
    time=fposmod(t,DURATION)
    var attacking := time>=1.05 and time<2.18
    idle.visible=not attacking;pose.visible=attacking
    lines.visible=time>=1.0 and time<1.65;lines.modulate.a=0.55
    effect.visible=time>=1.30 and time<1.90
    if effect.visible:
        var idx:=0 if time<1.45 else (1 if time<1.64 else 2)
        effect.texture=cut_frames[idx]
    flash.color=Color(1,1,1,0.35 if time>=1.45 and time<1.50 else 0.0)
    # A short framing push and hit shake affect the whole sample stage.
    var intensity := 1.015 if time>=1.30 and time<1.72 else 1.0
    scale=Vector2.ONE*intensity
    var shake_x := 3.0 * sin((time-1.45)*95.0) if time>=1.45 and time<1.60 else 0.0
    position=Vector2((1.0-intensity)*640.0+shake_x,(1.0-intensity)*360.0)
    # A slight forward push of the attacking pose.
    pose.position=Vector2(340 + (12 if time>=1.31 and time<1.48 else 0),646)
    queue_redraw()
func _draw() -> void:
    draw_rect(Rect2(0,0,1280,720),Color("172236"))
    draw_rect(Rect2(0,504,1280,216),Color("263649"))
    draw_line(Vector2(0,504),Vector2(1280,504),Color("50677a"),2)
    # Clearly temporary training target.
    var hit:= time>=1.45 and time<1.65
    var pos:=Vector2(890 + (12 if hit else 0),438)
    draw_circle(pos,72,Color("d4e0e9") if hit else Color("536d80"))
    draw_arc(pos,72,0,TAU,64,Color("b8d4e5"),5)
    draw_arc(pos,38,0,TAU,64,Color("263f51"),5)
    draw_line(pos+Vector2(0,72),pos+Vector2(0,130),Color("8aa4b4"),8)

