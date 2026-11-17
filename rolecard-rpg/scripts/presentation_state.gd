extends RefCounted
## Only controls presentation time; never applies rules/rewards/host writes.
var remaining := 0.0
var active := false
var event: Dictionary = {}

func begin(value: Dictionary, reduced: bool) -> void:
	event = value.duplicate(true)
	remaining = 0.0 if reduced else (0.65 if value.get("action")=="ultimate" else 0.16)
	active = true

func tick(delta: float, paused: bool) -> bool:
	if not active or paused: return false
	remaining = maxf(0,remaining-delta)
	if remaining > 0: return false
	active = false
	return true

func skip() -> bool:
	if not active: return false
	remaining = 0; active = false
	return true
