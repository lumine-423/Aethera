extends SceneTree
func _initialize() -> void:call_deferred("run")
func run() -> void:
    var fx=load("res://scripts/battle_art/frame_effect.gd").new()
    if not fx.configure_manifest("res://data/battle_presentation/rin_base_attack_space_cut_minimal.json"):push_error("manifest invalid");fx.free();quit(1);return
    if fx.frames.size()!=15:push_error("expected 15 frames");fx.free();quit(1);return
    for i in range(15):
        if fx.seek((float(i)+0.25)/24.0)!=i:push_error("frame order failed");fx.free();quit(1);return
    if fx.seek(15.0/24.0)!=-1:push_error("end boundary failed");fx.free();quit(1);return
    fx.free();print("PASS: 15 independent source images ordered at 24fps, duration 0.625s");quit()
