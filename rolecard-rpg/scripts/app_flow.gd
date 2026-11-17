extends RefCounted
var registry: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_routes.json"))["routes"]
var current := "home"
var history: Array[String] = []
var modal := ""

func open(target: String) -> bool:
	if not registry.has(target): return false
	if not modal.is_empty(): return false
	if current == target: return true
	if current == "battle" and target not in ["home","result"]: return false
	if target == "result" and current != "battle": return false
	if target == "home": history.clear()
	else: history.append(current)
	if history.size() > 24: history.pop_front()
	current = target
	return true

func back() -> bool:
	if not modal.is_empty(): modal = ""; return true
	if current == "battle": return false
	if history.is_empty(): return open("home")
	current = history.pop_back()
	return true

func show_modal(id: String) -> bool:
	if not modal.is_empty() or id not in ["pause","replace","retreat","import","clear"]: return false
	modal = id
	return true

func close_modal() -> void:
	modal = ""
