extends SceneTree
const Flow = preload("res://scripts/app_flow.gd")
const Saves = preload("res://scripts/save_service.gd")
const Presentation = preload("res://scripts/presentation_state.gd")
const Library = preload("res://scripts/animation_library.gd")
var checks := 0
var failures := 0
func check(value: bool,title: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(title)
func _initialize() -> void:
	var flow = Flow.new()
	check(not flow.open("shop"),"unadopted page rejected")
	check(flow.open("missions") and flow.open("mission_detail") and flow.open("prepare"),"page hierarchy")
	check(flow.back() and flow.current=="mission_detail","back restores prior page")
	check(flow.show_modal("import") and not flow.show_modal("clear"),"single modal")
	check(not flow.open("home"),"modal owns input")
	check(flow.back() and flow.modal.is_empty(),"back closes modal first")
	flow.open("battle")
	check(not flow.open("roster") and not flow.back(),"battle back needs pause decision")
	check(flow.open("result") and flow.open("home") and flow.history.is_empty(),"result returns home")
	var target := "res://.tmp/save-test-09-%d.json" % Time.get_ticks_usec()
	var store = Saves.new(target)
	var data := {"schema":1,"party":["rin","mingkong"],"settings":{"large_text":false,"motion":true,"sfx_volume":0.5},"battle":{},"records":[]}
	check(store.read().get("missing",false),"missing save is explicit")
	check(store.write(data) and store.read().ok,"save roundtrip")
	data.party = ["rin","ye"]
	check(store.write(data) and store.backup_data().data.party==["rin","mingkong"],"previous good backup")
	check(not store.decode('{broken').ok,"bad JSON rejected")
	var bad: Dictionary = data.duplicate(true); bad.party = ["rin","rin"]
	check(not store.write(bad) and store.read().data.party==["rin","ye"],"invalid save does not overwrite")
	var file := FileAccess.open(target,FileAccess.WRITE); file.store_string("broken"); file.close()
	check(not store.read().ok and store.blocked,"bad original protected")
	check(not store.write(data) and store.export_raw()=="broken","ordinary writes cannot erase bad original")
	check(store.write(data,true) and store.read().ok,"explicit replacement allowed")
	var unavailable = Saves.new("res://.tmp/nonexistent-09/sub/save.json")
	check(not unavailable.write(data),"unwritable path visible")
	var presentation = Presentation.new(); presentation.begin({"action":"ultimate"},false)
	check(not presentation.tick(1,true) and presentation.active,"pause freezes presentation")
	check(presentation.skip() and not presentation.skip(),"skip completes once")
	presentation.begin({"action":"attack"},true)
	check(presentation.tick(0,false) and not presentation.tick(1,false),"reduced presentation completes once")
	var library = Library.new()
	check(library.resolve_clip("rin","base","attack").get("missing",false),"missing art explicit fallback")
	check(not library.load_atlas("res://missing.json").ok,"missing metadata rejected")
	print("FRAMEWORK_09 ",checks," checks / ",failures," failures")
	quit(0 if failures==0 else 1)
