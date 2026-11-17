extends RefCounted
## Versioned, deterministic party rules. Presentation never applies game effects.
const VERSION := "playable-rules-08"
var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay_08.json"))
var state: Dictionary = {}
var history: Array = []
var setup: Dictionary = {}

func start(mission: String, party: Array, request_id: String = "local") -> Dictionary:
	if not config.missions.has(mission) or party.is_empty() or party.size() > config.party_limit:
		return {"ok":false,"error":"无效的任务或编队"}
	var seen := {}
	for id in party:
		if not id is String or not config.actors.has(id) or seen.has(id):
			return {"ok":false,"error":"编队包含重复或未开放角色"}
		seen[id] = true
	setup = {"mission":mission,"party":party.duplicate(),"request_id":request_id}
	state = {"mission":mission,"request_id":request_id,"round":1,"revision":0,"status":"active","allies":[],"enemies":[],"log":[],"acted":[]}
	for id in party:
		var def: Dictionary = config.actors[id]
		state.allies.append({"id":id,"name":def.name,"hp":def.hp,"max_hp":def.hp,"energy":def.energy,"shield":0,"guard":false,"buff":0,"form":"base","cooldowns":{}})
	for enemy in config.missions[mission].enemies:
		var unit: Dictionary = enemy.duplicate(true)
		unit["max_hp"] = unit.hp
		state.enemies.append(unit)
	history = []
	_log("行动开始。每名存活队友每回合可行动一次。")
	return {"ok":true}

func unit(id: String) -> Dictionary:
	for member in state.get("allies", []) + state.get("enemies", []):
		if member.id == id:
			return member
	return {}

func action(actor_id: String, action_id: String) -> Dictionary:
	return config.actors.get(actor_id, {}).get("actions", {}).get(action_id, {})

func reason(actor_id: String, action_id: String) -> String:
	if state.get("status") != "active": return "战斗已经结束"
	var actor := unit(actor_id)
	var move := action(actor_id, action_id)
	if actor.is_empty() or move.is_empty(): return "行动不可用"
	if actor.hp <= 0: return "角色已倒地"
	if actor_id in state.acted: return "本回合已行动"
	if actor.energy < move.cost: return "能量不足"
	if actor.cooldowns.get(action_id, 0) > 0: return "技能冷却中"
	if action_id == "liberate" and actor.form != "base": return "已处于解放形态"
	if move.get("released", false) and actor.form != "released": return "需要鸟羽形态"
	return ""

func targets(actor_id: String, action_id: String) -> Array:
	var move := action(actor_id, action_id)
	if move.is_empty(): return []
	if move.target == "self": return [actor_id]
	if move.target == "all_allies": return ["all_allies"]
	var result: Array = []
	for member in state.enemies if move.target == "enemy" else state.allies:
		if member.hp > 0: result.append(member.id)
	return result

func act(actor_id: String, action_id: String, target_id: String, revision: int) -> Dictionary:
	if revision != state.get("revision", -1): return {"ok":false,"error":"行动已变化，请重新选择"}
	var error := reason(actor_id, action_id)
	if not error.is_empty(): return {"ok":false,"error":error}
	if target_id not in targets(actor_id, action_id): return {"ok":false,"error":"目标不可用"}
	var actor := unit(actor_id)
	var move := action(actor_id, action_id)
	actor.energy = clampi(actor.energy - move.cost + move.get("gain", 0), 0, 100)
	var affected: Array = []
	if target_id == "all_allies":
		for member in state.allies:
			if member.hp > 0: affected.append(member)
	else: affected = [unit(target_id)]
	for target in affected:
		match move.effect:
			"damage":
				var damage: int = move.power + actor.buff
				target.hp = maxi(0, target.hp - damage)
				actor.buff = 0
				_log("%s → %s：%s，伤害%d" % [actor.name,target.name,move.name,damage])
			"heal":
				var healed: int = mini(move.power, target.max_hp - target.hp)
				target.hp += healed
				_log("%s → %s：恢复%d生命" % [actor.name,target.name,healed])
			"shield": target.shield = mini(40, target.shield + move.power); _log("%s获得%d护盾" % [target.name,move.power])
			"energy": target.energy = mini(100, target.energy + move.power); _log("%s获得%d能量" % [target.name,move.power])
			"buff": target.buff = maxi(target.buff, move.power); _log("%s下次伤害增加%d" % [target.name,move.power])
			"guard": actor.guard = true; _log("%s进入防御" % actor.name)
			"liberate": actor.form = "released"; _log("凛零解放为鸟羽形态")
			"energize": target.energy = mini(100,target.energy+move.power); target.buff = maxi(target.buff,5); _log("%s获得能量与协同增益" % target.name)
	if move.get("cooldown", 0) > 0: actor.cooldowns[action_id] = move.cooldown + 1
	state.acted.append(actor_id)
	history.append({"actor":actor_id,"action":action_id,"target":target_id})
	state.revision += 1
	if _living(state.enemies).is_empty(): state.status = "victory"
	elif _all_acted(): _enemy_phase()
	if history.size() >= 200 and state.status == "active": state.status = "draw"; _log("达到行动上限，本场以平局结束。")
	return {"ok":true,"action":action_id,"actor":actor_id,"target":target_id,"status":state.status,"revision":state.revision}

func _living(units: Array) -> Array:
	return units.filter(func(member): return member.hp > 0)

func _all_acted() -> bool:
	for member in _living(state.allies):
		if member.id not in state.acted: return false
	return true

func _enemy_phase() -> void:
	for enemy in _living(state.enemies):
		var alive := _living(state.allies)
		if alive.is_empty(): break
		# Intent/target is predictable from public round and living order.
		var target: Dictionary = alive[(state.round - 1) % alive.size()]
		var damage: int = enemy.damage * (2 if state.round % 2 == 0 else 1)
		if target.guard: damage = ceili(damage / 2.0)
		var absorbed: int = mini(target.shield, damage)
		target.shield -= absorbed
		target.hp = maxi(0,target.hp - damage + absorbed)
		_log("%s → %s：%s%d，护盾吸收%d" % [enemy.name,target.name,"重击" if state.round % 2 == 0 else "攻击",damage,absorbed])
	if _living(state.allies).is_empty(): state.status = "defeat"; return
	state.round += 1
	state.acted = []
	for member in state.allies:
		member.guard = false
		if member.hp <= 0: continue
		member.energy = mini(100,member.energy+8)
		for key in member.cooldowns: member.cooldowns[key] = maxi(0,member.cooldowns[key]-1)
	_log("第%d回合：敌方将%s。" % [state.round,"重击" if state.round % 2 == 0 else "普通攻击"])

func _log(message: String) -> void:
	state.log.append(message)
	if state.log.size() > 30: state.log.pop_front()

func checkpoint() -> Dictionary:
	return {"version":VERSION,"setup":setup.duplicate(true),"commands":history.duplicate(true)}

func restore(saved: Dictionary) -> Dictionary:
	if saved.keys().size() != 3 or saved.get("version") != VERSION or not saved.get("setup") is Dictionary or not saved.get("commands") is Array or saved.commands.size() > 200:
		return {"ok":false,"error":"存档版本或结构不支持"}
	var input: Dictionary = saved.setup
	if not input.get("mission") is String or not input.get("party") is Array or not input.get("request_id") is String:
		return {"ok":false,"error":"存档准备信息无效"}
	var scratch = get_script().new()
	var response: Dictionary = scratch.start(input.mission,input.party,input.request_id)
	if not response.ok: return response
	for command in saved.commands:
		if not command is Dictionary or command.keys().size() != 3 or not command.get("actor") is String or not command.get("action") is String or not command.get("target") is String:
			return {"ok":false,"error":"存档行动无效"}
		response = scratch.act(command.actor,command.action,command.target,scratch.state.revision)
		if not response.ok: return {"ok":false,"error":"存档行动无法重建"}
	state = scratch.state.duplicate(true)
	setup = scratch.setup.duplicate(true)
	history = scratch.history.duplicate(true)
	return {"ok":true}
