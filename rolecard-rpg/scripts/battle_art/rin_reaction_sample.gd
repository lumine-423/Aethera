extends Node2D
const DURATION := 6.0
var t := 0.0
var idle: Node2D
var figure: Sprite2D
var poses: Dictionary = {}
var hitfx: Node2D
var hit_origin := Vector2(480,365)
func load_texture(path:String) -> Texture2D:
    var im:=Image.load_from_file(ProjectSettings.globalize_path(path))
    if im==null or im.is_empty():push_error("missing "+path);return null
    return ImageTexture.create_from_image(im)
func _ready() -> void:
    idle=load("res://scenes/rin_idle_mad_01.tscn").instantiate();idle.character_path="res://assets/characters/rin-idle-mad-02/rin-base.png";idle.position=Vector2(480,660);add_child(idle)
    poses["hit"]=load_texture("res://assets/characters/rin-reactions-01/hit.png")
    poses["victory"]=load_texture("res://assets/characters/rin-reactions-01/victory.png")
    # Down source is an unaccepted candidate and may retain background.
    poses["down"]=load_texture("res://assets/characters/rin-reactions-01/down.png")
    if poses.values().has(null):return
    figure=Sprite2D.new();figure.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR;figure.centered=false;figure.z_index=2;add_child(figure)
    var holder:=Node2D.new();holder.position=hit_origin;holder.z_index=1;add_child(holder)
    hitfx=load("res://scripts/battle_art/hit_feedback.gd").new();hitfx.effect_size=Vector2(680,650);holder.add_child(hitfx)
    set_time(0.0)
func _process(delta:float) -> void:
    t=fposmod(t+delta,DURATION);set_time(t)
func set_time(seconds:float) -> void:
    if figure==null or hitfx==null:return
    t=fposmod(seconds,DURATION);var name:=""
    if t>=1.0 and t<1.48:name="hit"
    elif t>=2.2 and t<3.7:name="down"
    elif t>=4.2 and t<5.55:name="victory"
    idle.visible=name.is_empty();figure.visible=not name.is_empty()
    if figure.visible:
        var tex:Texture2D=poses[name];figure.texture=tex
        figure.offset=Vector2(-tex.get_width()/2.0,-tex.get_height())
        figure.scale=Vector2.ONE * (520.0/tex.get_width() if name=="down" else 580.0/tex.get_height())
        figure.position=Vector2(480,680 if name=="down" else 660)
    var shift:Vector2=hitfx.seek(t-1.0)
    if name=="hit":figure.position+=shift
    queue_redraw()
func _draw() -> void:
    draw_rect(Rect2(0,0,960,720),Color("e8edf2"))
    draw_line(Vector2(0,660),Vector2(960,660),Color("a6b3c0"),2.0)



