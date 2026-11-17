extends RefCounted
## Deterministic fixture for the two-entry integration probe. No formal game values.

const TASK_ID := "probe.basic"
const CONTENT_VERSION := "technical-fixture-02"
const LEGACY_VERSION := "technical-fixture-01"
const Catalog = preload("res://scripts/actor_catalog.gd")
const MAX_REMEMBERED_REQUESTS := 32
var catalog = Catalog.new()
var current: Dictionary = {}
var completed: Dictionary = {}
var command_history: Array = []

func start(request: Dictionary, fixture_version: String = CONTENT_VERSION) -> Dictionary:
	if fixture_version not in [CONTENT_VERSION, LEGACY_VERSION]:
		return {"ok": false, "error": "unsupported_content_version"}
	var reason := validate_request(request)
	if not reason.is_empty():
		return {"ok": false, "error": reason}
	var request_id: String = request["request_id"]
	if completed.has(request_id):
		if completed[request_id]["source"] != request["source"] or completed[request_id]["task_id"] != request["task_id"]:
			return {"ok": false, "error": "request_conflict"}
		return {"ok": true, "duplicate": true, "result": completed[request_id].duplicate(true)}
	if not current.is_empty():
		if current["request_id"] == request_id:
			if current["source"] != request["source"] or current["task_id"] != request["task_id"]:
				return {"ok": false, "error": "request_conflict"}
			return {"ok": true, "duplicate": true, "state": current.duplicate(true)}
		return {"ok": false, "error": "battle_busy"}
	current = {"request_id": request_id, "task_id": TASK_ID, "source": request["source"],
		"content_version": fixture_version, "player_hp": 10, "enemy_hp": 9,
		"turn": 0, "status": "active"}
	if fixture_version == CONTENT_VERSION:
		current["player_hp"] = int(catalog.fixture["player_max_hp"])
		current["enemy_hp"] = int(catalog.fixture["enemy_max_hp"])
		current.merge({"actor_id": catalog.fixture["actor_id"], "form_id": "base", "energy": catalog.fixture["initial_energy"]})
	command_history = []
	return {"ok": true, "duplicate": false, "state": current.duplicate(true)}

func act(command: String, expected_turn: int) -> Dictionary:
	if current.is_empty() or current.get("status") != "active":
		return {"ok": false, "error": "no_active_battle"}
	if expected_turn != current["turn"]:
		return {"ok": false, "error": "stale_command"}
	if command not in ["attack", "guard", "liberate", "ultimate"]:
		return {"ok": false, "error": "unknown_command"}
	var modern: bool = current["content_version"] == CONTENT_VERSION
	var from_form: String = current.get("form_id", "base")
	if command in ["liberate", "ultimate"]:
		if not modern:
			return {"ok": false, "error": "legacy_action_unavailable"}
		if (command == "liberate" and from_form != "base") or (command == "ultimate" and from_form != "released"):
			return {"ok": false, "error": "wrong_form"}
		var cost: int = catalog.fixture["liberate_cost" if command == "liberate" else "ultimate_cost"]
		if current["energy"] < cost:
			return {"ok": false, "error": "insufficient_energy"}
		current["energy"] -= cost
		if command == "liberate":
			current["form_id"] = "released"
	command_history.append(command)
	current["turn"] += 1
	if command == "attack":
		current["enemy_hp"] = maxi(0, current["enemy_hp"] - (int(catalog.fixture["attack_damage"]) if modern else 3))
	elif command == "ultimate":
		current["enemy_hp"] = maxi(0, current["enemy_hp"] - int(catalog.fixture["ultimate_damage"]))
	var presentation := {"action_id": command, "from_form": from_form, "to_form": current.get("form_id", "base"), "actor_id": current.get("actor_id", "rin"), "action_instance_id": current["request_id"] + ":" + str(current["turn"])}
	if current["enemy_hp"] == 0:
		var finished := _finish("victory")
		finished["presentation"] = presentation
		return finished
	var retaliation: int = int(catalog.fixture["guard_retaliation_damage"] if command == "guard" else catalog.fixture["retaliation_damage"]) if modern else (1 if command == "guard" else 3)
	current["player_hp"] = maxi(0, current["player_hp"] - retaliation)
	if current["player_hp"] == 0:
		var finished := _finish("defeat")
		finished["presentation"] = presentation
		return finished
	return {"ok": true, "state": current.duplicate(true), "presentation": presentation}

func cancel() -> Dictionary:
	if current.is_empty() or current.get("status") != "active":
		return {"ok": false, "error": "no_active_battle"}
	return _finish("cancelled")

func clear_finished() -> void:
	if current.get("status") == "finished":
		current = {}
		command_history = []

func checkpoint() -> Dictionary:
	if current.is_empty():
		return {}
	return {"content_version": current["content_version"],
		"request": {"protocol_version": 1, "request_id": current["request_id"], "task_id": TASK_ID, "source": current["source"]},
		"commands": command_history.duplicate(),
		"terminal": "cancelled" if completed.get(current["request_id"], {}).get("outcome") == "cancelled" else ""}

func restore_checkpoint(saved: Dictionary) -> Dictionary:
	for key in saved:
		if key not in ["content_version", "request", "commands", "terminal"]:
			return {"ok": false, "error": "invalid_checkpoint"}
	if saved.get("content_version") not in [CONTENT_VERSION, LEGACY_VERSION] or not saved.get("request") is Dictionary or not saved.get("commands") is Array:
		return {"ok": false, "error": "invalid_checkpoint"}
	if saved["commands"].size() > 32 or saved.get("terminal", "") not in ["", "cancelled"]:
		return {"ok": false, "error": "invalid_checkpoint"}
	if not current.is_empty() and current.get("status") == "active":
		return {"ok": false, "error": "battle_busy"}
	var scratch = get_script().new()
	var response: Dictionary = scratch.start(saved["request"], saved["content_version"])
	if not response["ok"]:
		return response
	for index in range(saved["commands"].size()):
		if not saved["commands"][index] is String:
			return {"ok": false, "error": "invalid_checkpoint"}
		response = scratch.act(saved["commands"][index], index)
		if not response["ok"]:
			return {"ok": false, "error": "invalid_checkpoint_history"}
	if saved.get("terminal", "") == "cancelled":
		response = scratch.cancel()
		if not response["ok"]:
			return {"ok": false, "error": "invalid_checkpoint_terminal"}
	current = scratch.current.duplicate(true)
	command_history = scratch.command_history.duplicate()
	for request_id in scratch.completed:
		completed[request_id] = scratch.completed[request_id].duplicate(true)
	return response

func _finish(outcome: String) -> Dictionary:
	current["status"] = "finished"
	var result := {"request_id": current["request_id"], "task_id": TASK_ID,
		"source": current["source"], "result_id": current["request_id"] + ":result",
		"content_version": current["content_version"], "outcome": outcome,
		"turns": current["turn"], "player_hp": current["player_hp"], "enemy_hp": current["enemy_hp"]}
	if current["content_version"] == CONTENT_VERSION:
		result.merge({"actor_id": current["actor_id"], "form_id": current["form_id"], "energy": current["energy"]})
	completed[current["request_id"]] = result.duplicate(true)
	while completed.size() > MAX_REMEMBERED_REQUESTS:
		completed.erase(completed.keys()[0])
	return {"ok": true, "state": current.duplicate(true), "result": result}

static func validate_request(request: Dictionary) -> String:
	for key in request:
		if key not in ["protocol_version", "request_id", "task_id", "source"]:
			return "unexpected_request_field"
	if request.get("protocol_version") != 1:
		return "unsupported_protocol"
	if request.get("task_id") != TASK_ID:
		return "unknown_task"
	if request.get("source") not in ["manual", "story"]:
		return "invalid_source"
	var request_id: Variant = request.get("request_id")
	if not request_id is String or request_id.length() < 1 or request_id.length() > 96:
		return "invalid_request_id"
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9._:-]+$")
	if pattern.search(request_id) == null:
		return "invalid_request_id"
	return ""
