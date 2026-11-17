extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
    root.size=Vector2i(960,640)
    var bg:=ColorRect.new();bg.size=Vector2(960,640);bg.color=Color("172236");root.add_child(bg)
    var fx=load("res://scripts/battle_art/frame_effect.gd").new()
    if not fx.configure_manifest("res://data/battle_presentation/rin_base_attack_space_cut_minimal.json"):push_error("effect invalid");quit(1);return
    fx.position=Vector2(480,320);fx.scale=Vector2.ONE*0.52;root.add_child(fx)
    var mat:=ShaderMaterial.new();mat.shader=load("res://scripts/battle_art/spatial_cut_reveal.gdshader");fx.material=mat
    for i in range(15):
        var tm=(float(i)+0.5)/24.0
        if fx.seek(tm)!=i:push_error("wrong index");quit(1);return
        var opening:=clampf(tm/0.21,0.0,1.0)
        var closing:=clampf((0.625-tm)/0.23,0.0,1.0)
        mat.set_shader_parameter("spread",minf(opening,closing))
        mat.set_shader_parameter("opacity",clampf((0.625-tm)/0.10,0.0,1.0))
        await RenderingServer.frame_post_draw
        var err=root.get_texture().get_image().save_png("res://evidence/rin-space-minimal-02/effect-%02d.png"%i)
        if err!=OK:push_error("capture failed");quit(1);return
    print("PASS: 15 original images + timed reveal and fade rendered at 24fps")
    quit()
