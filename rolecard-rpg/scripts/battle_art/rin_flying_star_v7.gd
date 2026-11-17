extends Node2D
## Visual-only particle-accelerator presentation, not battle state.
var elapsed := 0.0
var ready_ok := false
var idle: Texture2D
var trail: Texture2D
var kick: Texture2D
var ring_frames: Array[Texture2D] = []
var impact_frames: Array[Texture2D] = []
var actor: Sprite2D
var accelerator: Sprite2D
var impact: Sprite2D
var target: Node2D
var feedback: Node2D
var ghost: Array[Sprite2D] = []
func tex(path: String) -> Texture2D:
    var im := Image.load_from_file(ProjectSettings.globalize_path(path))
    if im == null or im.is_empty(): push_error("Missing " + path); return null
    return ImageTexture.create_from_image(im)
func make_sprite(img: Texture2D, z: int) -> Sprite2D:
    var s := Sprite2D.new(); s.texture=img; s.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR; s.z_index=z; add_child(s); return s
func _ready() -> void:
    idle=tex("res://assets/characters/rin-release-03/release.png")
    trail=tex("res://assets/characters/rin-release-motion-01/flight-trail-ultimate.png")
    kick=tex("res://assets/characters/rin-release-flying-star-06/rider-kick.png")
    if idle == null or trail == null or kick == null: return
    for i in range(1,13):
        var a:=tex("res://assets/effects/rin-release-accelerator-01/frame-%02d.png" % i)
        var b:=tex("res://assets/effects/rin-release-kick-impact-01/frame-%02d.png" % i)
        if a==null or b==null: return
        ring_frames.append(a); impact_frames.append(b)
    accelerator=make_sprite(ring_frames[0],1)
    for i in range(4): ghost.append(make_sprite(trail,2))
    target=load("res://scripts/battle_art/demo_target.gd").new(); target.position=Vector2(1040,405); add_child(target)
    actor=make_sprite(idle,3); impact=make_sprite(impact_frames[0],4)
    var holder:=Node2D.new(); holder.position=Vector2(1040,405); holder.z_index=5; add_child(holder)
    feedback=load("res://scripts/battle_art/hit_feedback.gd").new(); feedback.displacement=10.0; holder.add_child(feedback)
    ready_ok=true; seek(0.0)
func _draw() -> void:
    draw_rect(Rect2(0,0,1280,720),Color("172637"))
    draw_rect(Rect2(0,650,1280,70),Color("263b4a"))
    draw_line(Vector2(0,650),Vector2(1280,650),Color("577083"),2.0)
func _process(delta: float) -> void:
    if ready_ok: seek(fposmod(elapsed+delta,3.75))
func flight_position(t: float) -> Vector2:
    # One continuous left-to-right path with increasing speed.
    var u := clampf((t - 0.65) / 1.10, 0.0, 1.0)
    return Vector2(180.0 + 480.0 * u * u, 390.0)
func seek(t: float) -> void:
    if not ready_ok: return
    elapsed=t
    var charging:=t>=0.65 and t<1.75
    var kicking:=t>=1.75 and t<2.73
    accelerator.visible=t>=0.65 and t<2.15
    if accelerator.visible:
        var dt:=t-0.65; var n:=int(dt*24.0)%12
        accelerator.texture=ring_frames[n]
        var expansion := minf(1.0, 0.35 + float(n)*0.14)
        accelerator.scale=Vector2(1100,350)/accelerator.texture.get_size()*expansion
        accelerator.position=Vector2(640,390)
        var fade := 1.0 if n<8 else maxf(0.0,(11.0-n)/3.0)
        accelerator.modulate.a=0.65*fade*(1.0 if t<1.75 else maxf(0.0,1.0-(t-1.75)/0.4))
    actor.texture=trail if charging else (kick if kicking else idle)
    actor.scale=Vector2.ONE*(230.0 if charging else (420.0 if kicking else 470.0))/actor.texture.get_height()
    actor.position=flight_position(t) if charging else (Vector2(lerpf(660.0,760.0,clampf((t-1.75)/0.12,0.0,1.0)),405) if kicking else Vector2(350,320))
    actor.flip_h=false
    for i in range(ghost.size()):
        var gt:=t-float(i+1)*0.035; var g:=ghost[i]; g.visible=charging and gt>=0.65
        if g.visible:
            g.scale=Vector2.ONE*230.0/trail.get_height(); g.position=flight_position(gt)
            g.flip_h=false
            g.modulate=Color(0.45,0.85,1.0,0.25-0.04*i)
    var raw_idx:=int((t-1.87)*24.0); impact.visible=t>=1.87 and raw_idx>=0 and raw_idx<14
    if impact.visible:
        var si:=raw_idx if raw_idx<6 else (5 if raw_idx<8 else raw_idx-2)
        impact.texture=impact_frames[si]; impact.scale=Vector2.ONE*430.0/impact.texture.get_height()*minf(1.0,0.3+si*0.16)
        impact.modulate.a=1.0 if si<7 else clampf((11.0-si)/4.0,0,1)
    var off:Vector2=feedback.seek(t-1.94)
    target.position=Vector2(1040,405)+off
    impact.position=Vector2(1040,405)+off
