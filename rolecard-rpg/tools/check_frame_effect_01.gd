extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var specs := [["shared_speedline_neutral.json",16],["rin_base_attack_body_trail.json",11],["rin_base_attack_space_cut.json",15]]
    for spec in specs:
        var fx = load("res://scripts/battle_art/frame_effect.gd").new()
        if not fx.configure_manifest("res://data/battle_presentation/"+spec[0]): push_error("manifest failed: "+spec[0]);fx.free();quit(1);return
        if fx.frames.size()!=spec[1]:push_error("wrong frame count");fx.free();quit(1);return
        for i in range(spec[1]):
            if fx.seek((float(i)+0.25)/24.0)!=i:push_error("frame order failed");fx.free();quit(1);return
        if fx.seek(float(spec[1])/24.0)!=-1 or fx.seek(-0.01)!=-1:push_error("boundary failed");fx.free();quit(1);return
        fx.free()
    print("PASS: three 24fps effects; 16, 11, 15 frames, boundaries and sequence validated")
    quit()
