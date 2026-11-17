extends SceneTree

const Session = preload("res://scripts/battle_session.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	var manual := _request("manual-1", "manual")
	var story := _request("story-1", "story")
	var first = Session.new()
	_check(first.start(manual).get("ok"), "manual request accepted")
	_check(first.start(manual).get("duplicate"), "duplicate start is idempotent")
	_check(first.current["turn"] == 0, "duplicate start does not advance")
	_check(first.start(story).get("error") == "battle_busy", "different request rejected while busy")
	_check(first.act("attack", 0).get("ok"), "first action accepted")
	var before: Dictionary = first.current.duplicate(true)
	_check(first.act("attack", 0).get("error") == "stale_command", "stale action rejected")
	_check(first.current == before, "stale action leaves state unchanged")
	first.act("attack", 1)
	var victory: Dictionary = first.act("attack", 2)
	_check(victory.get("result", {}).get("outcome") == "victory", "fixture victory reachable")
	_check(first.act("attack", 3).get("error") == "no_active_battle", "no action after completion")
	_check(first.start(manual).get("result") == victory["result"], "repeated request replays same result")
	_check(first.start(_request("manual-1", "story")).get("error") == "request_conflict", "completed ID cannot be reused with different source")
	first.clear_finished()
	_check(first.start(story).get("ok"), "story request uses same session implementation")
	for turn in range(10):
		var response: Dictionary = first.act("guard", turn)
		if response.has("result"):
			_check(response["result"]["outcome"] == "defeat", "fixture defeat reachable")
			break
	first.clear_finished()
	first.start(_request("cancel-1", "story"))
	_check(first.cancel()["result"]["outcome"] == "cancelled", "cancel has explicit terminal result")
	var invalid = Session.new()
	_check(invalid.start({}).get("error") == "unsupported_protocol", "empty request rejected")
	var bad := manual.duplicate()
	bad["task_id"] = "arbitrary-task"
	_check(invalid.start(bad).get("error") == "unknown_task", "unknown task rejected")
	bad = manual.duplicate()
	bad["request_id"] = "<script>"
	_check(invalid.start(bad).get("error") == "invalid_request_id", "unsafe request ID rejected")
	bad = manual.duplicate()
	bad["enemy_hp"] = 0
	_check(invalid.start(bad).get("error") == "unexpected_request_field", "external request cannot override fixture rules")
	var other = Session.new()
	other.start(_request("equivalent", "story"))
	other.act("attack", 0)
	other.act("attack", 1)
	var other_result: Dictionary = other.act("attack", 2)["result"]
	_check(other_result["player_hp"] == victory["result"]["player_hp"] and other_result["turns"] == 3,
		"both sources produce same rule result")
	var saved_session = Session.new()
	saved_session.start(_request("restore-1", "manual"))
	saved_session.act("attack", 0)
	var saved: Dictionary = saved_session.checkpoint()
	var resumed = Session.new()
	_check(resumed.restore_checkpoint(saved).get("ok"), "valid checkpoint restored")
	_check(resumed.current == saved_session.current, "replayed state equals saved state")
	resumed.act("attack", 1)
	_check(resumed.act("attack", 2).get("result", {}).get("outcome") == "victory", "restored battle can finish")
	var terminal = Session.new()
	_check(terminal.restore_checkpoint(resumed.checkpoint()).get("result", {}).get("outcome") == "victory", "terminal checkpoint replays same result")
	var reject = Session.new()
	var invalid_save := saved.duplicate(true)
	invalid_save["player_hp"] = 999
	_check(not reject.restore_checkpoint(invalid_save).get("ok"), "checkpoint cannot inject HP")
	_check(reject.current.is_empty(), "invalid restore is nonmutating")
	invalid_save = saved.duplicate(true)
	invalid_save["commands"] = ["attack", "unknown"]
	_check(not reject.restore_checkpoint(invalid_save).get("ok"), "invalid replay command rejected")
	_check(reject.current.is_empty(), "failed replay leaves current state untouched")
	var cancel_source = Session.new()
	cancel_source.start(_request("restore-cancel", "story"))
	cancel_source.cancel()
	_check(reject.restore_checkpoint(cancel_source.checkpoint()).get("result", {}).get("outcome") == "cancelled", "cancel checkpoint restores terminal result")
	var forms = Session.new()
	forms.start(_request("forms", "manual"))
	var original: Dictionary = forms.current.duplicate(true)
	_check(forms.act("ultimate", 0).get("error") == "wrong_form", "flying star requires released form")
	_check(forms.current == original, "unavailable ultimate is nonmutating")
	var release: Dictionary = forms.act("liberate", 0)
	_check(release.get("ok") and forms.current["form_id"] == "released" and forms.current["energy"] == 80, "liberation commits form and cost once")
	_check(release["presentation"]["from_form"] == "base" and release["presentation"]["to_form"] == "released", "presentation carries explicit from/to forms")
	var after_release: Dictionary = forms.current.duplicate(true)
	_check(forms.act("liberate", 0).get("error") == "stale_command" and forms.current == after_release, "duplicate liberation cannot charge again")
	_check(forms.act("liberate", 1).get("error") == "wrong_form" and forms.current == after_release, "released actor cannot liberate twice")
	var form_restored = Session.new()
	_check(form_restored.restore_checkpoint(forms.checkpoint()).get("ok") and form_restored.current == forms.current, "reload restores logical form and paid cost")
	var star: Dictionary = form_restored.act("ultimate", 1)
	_check(star.get("ok") and form_restored.current["energy"] == 20 and form_restored.current["enemy_hp"] == 1, "flying star consumes energy and applies fixture damage")
	var no_energy: Dictionary = form_restored.current.duplicate(true)
	_check(form_restored.act("ultimate", 2).get("error") == "insufficient_energy" and form_restored.current == no_energy, "insufficient resource does not partially commit")
	var finished_star: Dictionary = form_restored.act("attack", 2)["result"]
	_check(finished_star["form_id"] == "released" and finished_star["energy"] == 20, "terminal result retains final form and resource")
	var legacy = Session.new()
	legacy.start(_request("legacy", "story"), Session.LEGACY_VERSION)
	legacy.act("attack", 0)
	var legacy_restored = Session.new()
	_check(legacy_restored.restore_checkpoint(legacy.checkpoint()).get("ok") and legacy_restored.current == legacy.current, "v1 checkpoint restores v1 rules unchanged")
	_check(legacy_restored.act("liberate", 1).get("error") == "legacy_action_unavailable", "v1 does not silently gain v2 actions")
	var data = forms.catalog
	_check(data.action("mingkong", "base", "attack").get("label") == "基础援护", "support basic action has support semantics")
	var full_coverage := true
	for actor_id in data.actors:
		for form_id in data.actors[actor_id]["forms"]:
			full_coverage = full_coverage and data.form(actor_id, form_id)["actions"].size() == 9
	_check(full_coverage and data.actors.size() == 17, "all source actors and both sin forms declare nine actions including idle")
	print(JSON.stringify({"suite": "battle_session", "checks": checks, "failures": failures}))
	quit(1 if failures else 0)

func _request(id: String, source: String) -> Dictionary:
	return {"protocol_version": 1, "request_id": id, "task_id": "probe.basic", "source": source}

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)
