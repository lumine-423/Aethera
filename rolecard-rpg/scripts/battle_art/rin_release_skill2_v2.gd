extends Node2D
## Shared presentation prototype. Uses fixed poses and repeated images as afterimages.
@export var ultimate := false
var elapsed := 0.0
var action_time := 0.0
var ready_ok := false
var flying: Texture2D
var finishing: Texture2D
var trail_art: Texture2D
var idle: Texture2D
var cuts: Array[Texture2D] = []
var impact: Array[Texture2D] = []
var actor: Sprite2D
var ghost: Array[Sprite2D] = []
var cut: Sprite2D
var burst: Sprite2D
var target: Node2D
var hitfx: Node2D
func read_tex(path: String) -> Texture2D:
    var im := Image.load_from_file(ProjectSettings.globalize_path(path))
    if im == null or im.is_empty(): push_error("Missing " + path); return null
    return ImageTexture.create_from_image(im)
func make_sprite(tex: Texture2D, height: float, layer: int) -> Sprite2D:
    var s := Sprite2D.new(); s.texture=tex; s.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
    s.scale=Vector2.ONE * height / tex.get_height(); s.z_index=layer; add_child(s); return s
func _ready() -> void:
    flying=read_tex("res://assets/characters/rin-release-motion-01/flight.png")
    finishing=read_tex("res://assets/characters/rin-release-motion-01/" + ("kick.png" if ultimate else "punch.png"))
    idle=read_tex("res://assets/characters/rin-release-03/release.png")
    trail_art=read_tex("res://assets/characters/rin-release-motion-01/flight-trail-ultimate.png")
    if flying == null or finishing == null or idle == null or trail_art == null: return
    for i in range(1,13):
        var a:=read_tex("res://assets/effects/rin-ultimate-space-01/frame-%02d.png" % i)
        var b:=read_tex("res://assets/effects/rin-release-kick-impact-01/frame-%02d.png" % i)
        if a == null or b == null: return
        cuts.append(a); impact.append(b)
    target=load("res://scripts/battle_art/demo_target.gd").new(); target.position=Vector2(960,405); add_child(target)
    var holder := Node2D.new(); holder.position=Vector2(960,405); holder.z_index=6; add_child(holder)
    hitfx=load("res://scripts/battle_art/hit_feedback.gd").new(); hitfx.displacement=14.0; holder.add_child(hitfx)
    for i in range(3):
        var g := make_sprite(flying,470,2)
        g.scale = Vector2.ONE * (470.0 / 1312.0)
        ghost.append(g)
    actor=make_sprite(idle,470,3); cut=make_sprite(cuts[0],250,4); burst=make_sprite(impact[0],400,5)
    ready_ok=true; seek(0.0)
func _draw() -> void:
    draw_rect(Rect2(0,0,1280,720),Color("172637"))
    draw_rect(Rect2(0,650,1280,70),Color("263b4a"))
    draw_line(Vector2(0,650),Vector2(1280,650),Color("577083"),2.0)
func _process(delta: float) -> void:
    if ready_ok: seek(fposmod(elapsed+delta,5.0))
func move_at(t: float) -> Vector2:
    var start_times := [0.65, 1.20, 1.63, 1.96, 2.21, 2.40, 2.55, 2.68, 2.79, 2.89]
    var locations := [Vector2(330,365),Vector2(850,340),Vector2(1000,430),Vector2(810,470),Vector2(1000,325),Vector2(800,370),Vector2(1000,450),Vector2(820,315),Vector2(1000,370),Vector2(800,390)]
    for i in range(start_times.size()-1):
        if t >= start_times[i] and t < start_times[i+1]:
            var u: float = (t-start_times[i])/(start_times[i+1]-start_times[i])
            if ultimate: return Vector2(lerpf(locations[i].x,locations[i+1].x,u), lerpf(locations[i].y,locations[i+1].y,u))
            return locations[i].lerp(locations[i+1],u)
    return locations[-1]
func seek(t: float) -> void:
    if not ready_ok: return
    elapsed=t
    var real_t := t
    if t >= 0.65 and t < 2.13125: t = 0.65 + (t - 0.65) * 1.6
    elif t >= 2.13125: t += 3.02 - 2.13125
    action_time=t
    var moving := t>=0.65 and t<3.02
    var fin := t>=3.02 and t<3.72
    actor.texture=finishing if fin else ((trail_art if ultimate else flying) if moving else idle)
    actor.scale = Vector2.ONE * (470.0 / 1312.0)
    actor.position=Vector2(355,320) if not moving and not fin else (Vector2(720,455) if fin else move_at(t))
    for i in range(ghost.size()):
        var g:=ghost[i]; var gt:=t-0.055*float(i+1); g.visible=moving and gt>=0.65
        if g.visible:
            g.position=move_at(gt); g.modulate=Color(0.45,0.8,1.0,0.35-0.05*float(i)); g.flip_h=ultimate and move_at(gt).x < move_at(maxf(0.65,gt-0.02)).x
    actor.flip_h=moving and ultimate and move_at(t).x < move_at(maxf(0.65,t-0.02)).x
    var beat := [1.20,1.63,1.96,2.21,2.40,2.55,2.68,2.79,2.89]
    var latest := -10.0
    for v in beat:
        if t>=v: latest=v
    var idx := int((t-latest)*24.0)
    cut.visible=moving and idx>=0 and idx<12
    if cut.visible:
        cut.texture=cuts[idx]; cut.scale=Vector2(430,180)/cut.texture.get_size(); cut.position=Vector2(960,405); cut.rotation=sin(latest*12.0)*0.75
    var impact_idx := int((t-3.27)*24.0)
    burst.visible=t>=3.27 and impact_idx>=0 and impact_idx<14
    if burst.visible:
        var source_idx := impact_idx if impact_idx < 6 else (5 if impact_idx < 8 else impact_idx - 2)
        burst.texture=impact[source_idx]; burst.scale=Vector2.ONE*(500.0 if ultimate else 360.0)/burst.texture.get_height(); burst.position=Vector2(960,405)
        var scale_factor := minf(1.0, 0.34 + float(source_idx) * 0.15)
        burst.scale *= scale_factor
        burst.modulate.a = 1.0 if source_idx < 7 else clampf(float(11-source_idx)/4.0, 0.0, 1.0)
    var hit_time := 3.32
    var off: Vector2=hitfx.seek(real_t - (hit_time - (3.02 - 2.13125)))
    target.position=Vector2(960,405)+off
    if burst.visible: burst.position += off
