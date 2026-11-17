extends RefCounted
## Runtime contract, independent of nodes, story stages and unfinished sprite files.
const ACTIONS := ["attack", "skill_1", "skill_2", "ultimate", "hit", "guard", "down", "settlement", "idle"]
var actors: Dictionary = {}
var fixture: Dictionary = {}

func _init() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors.json"))
	assert(data is Dictionary and data.get("schema_version") == 1, "Invalid actor catalog")
	actors = data["actors"]
	for actor_id in actors:
		for form_id in actors[actor_id]["forms"]:
			var actions: Dictionary = actors[actor_id]["forms"][form_id]["actions"]
			assert(actions.size() == ACTIONS.size(), "Incomplete actor form")
			for action in ACTIONS:
				assert(actions.has(action), "Required action missing: " + action)
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/battle_fixture.json"))
	assert(rules is Dictionary and rules.get("schema_version") == 1, "Invalid fixture rules")
	fixture = rules

func form(actor_id: String, form_id: String) -> Dictionary:
	return actors.get(actor_id, {}).get("forms", {}).get(form_id, {}).duplicate(true)

func action(actor_id: String, form_id: String, action_id: String) -> Dictionary:
	return form(actor_id, form_id).get("actions", {}).get(action_id, {}).duplicate(true)

func transition(actor_id: String, transition_id: String) -> Dictionary:
	return actors.get(actor_id, {}).get("transitions", {}).get(transition_id, {}).duplicate(true)
