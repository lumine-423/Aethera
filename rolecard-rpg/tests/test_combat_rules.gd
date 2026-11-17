extends SceneTree
const Rules = preload("res://scripts/combat_rules.gd")
var count := 0
var failures := 0
func check(value: bool, label: String) -> void:
	if not value: push_error("FAILED: "+label); failures += 1
	count += 1

func _initialize() -> void:
	var rules = Rules.new()
	check(not rules.start("unknown",["rin"]).ok,"unknown mission")
	check(not rules.start("training.basic",["rin","rin"]).ok,"duplicate party")
	check(rules.start("training.basic",["rin","mingkong"]).ok,"party start")
	var snapshot: String = JSON.stringify(rules.state)
	check(not rules.act("rin","attack","mingkong",0).ok and JSON.stringify(rules.state)==snapshot,"wrong side doesn't mutate")
	check(not rules.act("rin","ultimate","sentinel",0).ok,"release required")
	check(rules.act("rin","attack","sentinel",0).ok,"legal attack")
	check(rules.unit("sentinel").hp==25 and rules.state.round==1,"enemy waits for all allies")
	snapshot = JSON.stringify(rules.state)
	check(not rules.act("rin","attack","sentinel",0).ok and JSON.stringify(rules.state)==snapshot,"stale duplicate no mutation")
	check(not rules.act("rin","guard","rin",1).ok,"one action per round")
	check(rules.act("mingkong","skill_2","rin",1).ok,"support shields ally")
	check(rules.state.round==2 and rules.unit("rin").hp==46 and rules.unit("rin").shield==7,"shield absorbs enemy phase")
	var saved: Dictionary = rules.checkpoint()
	var restored = Rules.new()
	check(restored.restore(saved).ok and JSON.stringify(restored.state)==JSON.stringify(rules.state),"exact replay incl energy/status/log")
	var malformed: Dictionary = saved.duplicate(true); malformed.commands.append({"actor":"rin","action":"ultimate","target":"sentinel"})
	snapshot = JSON.stringify(restored.state)
	check(not restored.restore(malformed).ok and JSON.stringify(restored.state)==snapshot,"bad replay atomic")
	rules.unit("rin").energy = 0
	snapshot = JSON.stringify(rules.state)
	check(not rules.act("rin","skill_1","sentinel",2).ok and JSON.stringify(rules.state)==snapshot,"insufficient resource atomic")
	check(rules.act("rin","guard","rin",2).ok,"guard recovers energy")
	check(rules.unit("rin").energy==20,"guard energy once")
	check(rules.act("mingkong","attack","rin",3).ok,"support energy")
	check(rules.unit("rin").hp==46 and rules.unit("rin").shield==7 and rules.unit("mingkong").hp==18,"public round intent targets second ally")
	rules.act("rin","guard","rin",4); rules.act("mingkong","guard","mingkong",5)
	check(rules.unit("rin").hp==46 and rules.unit("rin").shield==2,"guard halves damage before shield")
	rules.unit("mingkong").hp = 0
	check("mingkong" not in rules.targets("rin","skill_2"),"dead ally not targetable")
	var solo = Rules.new(); solo.start("training.basic",["rin"])
	check(solo.act("rin","liberate","rin",0).ok,"liberation")
	check(solo.unit("rin").form=="released" and not solo.reason("rin","liberate").is_empty(),"release state unique")
	solo.act("rin","guard","rin",1)
	check(solo.act("rin","ultimate","sentinel",2).ok and solo.unit("sentinel").hp==0,"flying star kill")
	check(solo.targets("rin","attack")==["drone"],"dead enemy excluded")
	var healer = Rules.new(); healer.start("training.basic",["mingkong"])
	healer.act("mingkong","skill_1","mingkong",0)
	check(healer.unit("mingkong").hp==27,"heal max cap before enemy attack")
	var cooling = Rules.new(); cooling.start("training.basic",["rin"])
	cooling.act("rin","skill_1","sentinel",0)
	check(cooling.reason("rin","skill_1")=="技能冷却中","cooldown prevents adjacent round cast")
	cooling.act("rin","guard","rin",1)
	check(cooling.reason("rin","skill_1").is_empty(),"cooldown expires")
	var buffer = Rules.new(); buffer.start("training.basic",["rin","ye"])
	buffer.act("ye","skill_1","rin",0);buffer.act("rin","attack","sentinel",1)
	check(buffer.unit("sentinel").hp==20 and buffer.unit("rin").buff==0,"buff consumed once")
	# Play complete battles via legal player commands, then replay terminal histories.
	for ids in [["rin","mingkong"],["rin","ye"],["rin"],["mingkong"]]:
		var battle = Rules.new();battle.start("training.basic",ids)
		for step in range(200):
			if battle.state.status!="active": break
			for member in battle.state.allies:
				if member.hp<=0 or member.id in battle.state.acted: continue
				var move := "attack" if member.id=="rin" else "guard"
				var target_list: Array = battle.targets(member.id,move)
				check(battle.act(member.id,move,target_list[0],battle.state.revision).ok,"complete battle legal action")
				break
		check(battle.state.status in ["victory","defeat","draw"],"battle reaches terminal")
		var replay = Rules.new()
		check(replay.restore(battle.checkpoint()).ok and JSON.stringify(replay.state)==JSON.stringify(battle.state),"terminal replay exact")
	print("COMBAT_08_PASS " if failures == 0 else "COMBAT_08_FAIL ",count," checks / ",failures," failures")
	quit(0 if failures == 0 else 1)
