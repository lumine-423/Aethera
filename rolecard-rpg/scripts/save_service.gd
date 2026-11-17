extends RefCounted
const Rules = preload("res://scripts/combat_rules.gd")
var path: String
var blocked := false
var last_error := ""

func _init(target: String = "user://playable_08.json") -> void:
	path = target

func validate(payload: Variant) -> String:
	if not payload is Dictionary or payload.get("schema") != 1 or not payload.get("party") is Array or not payload.get("settings") is Dictionary or not payload.get("battle") is Dictionary or not payload.get("records") is Array: return "记录结构或版本不支持"
	var rules = Rules.new()
	if payload.party.is_empty() or payload.party.size() > 2: return "编队数量无效"
	var seen := {}
	for id in payload.party:
		if not id is String or not rules.config.actors.has(id) or seen.has(id): return "编队角色无效或重复"
		seen[id] = true
	if payload.records.size() > 20: return "战报数量超限"
	seen = {}
	for record in payload.records:
		if not record is Dictionary or not record.get("request_id") is String or not record.get("mission") is String or record.get("outcome") not in ["victory","defeat","retreat","draw"]: return "战报结构无效"
		if seen.has(record.request_id): return "战报重复"
		seen[record.request_id] = true
		for key in ["rounds","actions"]:
			var number: Variant = record.get(key)
			if not (number is int or number is float) or number != floor(number) or number < 0 or number > 201: return "战报计数无效"
	if not payload.battle.is_empty():
		var response: Dictionary = rules.restore(payload.battle)
		if not response.ok: return "战斗恢复记录无效："+response.error
	for key in ["large_text","motion"]:
		if payload.settings.has(key) and not payload.settings[key] is bool: return "显示设置无效"
	if payload.settings.has("sfx_volume"):
		var volume: Variant = payload.settings.sfx_volume
		if not (volume is int or volume is float) or volume < 0 or volume > 1: return "音量设置无效"
	return ""

func decode(raw: String) -> Dictionary:
	if raw.length() > 2000000: return {"ok":false,"error":"记录超过大小限制"}
	var payload: Variant = JSON.parse_string(raw)
	var error := validate(payload)
	if not error.is_empty(): return {"ok":false,"error":error}
	return {"ok":true,"data":payload}

func read() -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":true,"data":{},"missing":true}
	var response := decode(FileAccess.get_file_as_string(path))
	blocked = not response.ok
	last_error = response.get("error","")
	return response

func write(payload: Dictionary, replace_bad: bool = false) -> bool:
	last_error = validate(payload)
	if not last_error.is_empty(): return false
	if blocked and not replace_bad: last_error = "异常原档已保护，请先导出或明确清除/导入"; return false
	var old := ""
	if FileAccess.file_exists(path): old = FileAccess.get_file_as_string(path)
	if not old.is_empty() and decode(old).ok:
		var backup := FileAccess.open(path+".bak",FileAccess.WRITE)
		if backup == null: last_error = "无法保留上一好档，已停止覆盖"; return false
		backup.store_string(old); backup.close()
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: last_error = "无法写入恢复点"; return false
	file.store_string(JSON.stringify(payload)); file.close()
	if DirAccess.rename_absolute(path+".tmp",path) != OK: last_error = "恢复点替换失败"; return false
	blocked = false
	return true

func backup_data() -> Dictionary:
	if not FileAccess.file_exists(path+".bak"): return {"ok":false,"error":"尚无上一好档"}
	return decode(FileAccess.get_file_as_string(path+".bak"))

func export_raw() -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
