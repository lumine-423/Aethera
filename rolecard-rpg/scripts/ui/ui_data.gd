extends RefCounted
## Read-only content for screens. Contest text comes from data/content/contest_content.json
## (copied verbatim from the original card by tools/build_contest_content.py); live game state
## (items, affection, events) comes from the Game autoload.

const WORLDBOOK_OVERRIDES_PATH := "user://worldbook_overrides.json"
const CUSTOM_WORLDBOOK_PATH := "user://worldbook_custom.json"
const CHAR_GALLERIES_PATH := "res://data/content/character_galleries.json"

static var _demo: Dictionary = {}
static var _profiles: Dictionary = {}
static var _content: Dictionary = {}
static var _worldbook: Dictionary = {}
static var _wb_overrides: Dictionary = {}
static var _wb_overrides_loaded := false
static var _wb_custom: Array = []
static var _wb_custom_loaded := false
static var custom_worldbook_path_override := ""
static var _char_galleries: Dictionary = {}

static func demo() -> Dictionary:
	if _demo.is_empty(): _demo = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/ui_demo_content.json"))
	return _demo

static func content() -> Dictionary:
	if _content.is_empty(): _content = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/contest_content.json"))
	return _content

static func edition() -> String:
	return content().get("edition", "contest")

static func profiles() -> Dictionary:
	if _profiles.is_empty(): _profiles = JSON.parse_string(FileAccess.get_file_as_string("res://data/character_profiles.json"))
	return _profiles

static func cast() -> Array:
	return content().get("cast", [])

static func cast_entry(id: String) -> Dictionary:
	for c in cast():
		if c.id == id: return c
	for n in npcs():
		if n.id == id: return n
	return {}

static func name_of(id: String) -> String:
	var c := cast_entry(id)
	if not c.is_empty(): return c.name
	return profiles().get(id, {}).get("name", id)

## Chinese name -> id for cast & NPCs; "" for the player.
static func id_of(zh: String) -> String:
	for c in cast():
		if c.name == zh: return c.id
	for n in npcs():
		if n.name == zh: return n.id
	if zh == "叶子": return "ye"
	if zh == "德拉贡" or zh == "德拉戈": return "drago"
	if zh == "埃德加": return "edgar"
	return ""

static func npcs() -> Array:
	return content().get("npcs", [])

static func origin_by_key(key: String) -> Dictionary:
	var list: Array = content().get("origins", [])
	for o in list:
		if String(o.get("key", "")) == key: return o
	return list[0] if not list.is_empty() else {}

static func worldbook() -> Dictionary:
	if _worldbook.is_empty():
		var txt := FileAccess.get_file_as_string("res://data/content/worldbook_full.json")
		var parsed = JSON.parse_string(txt)
		_worldbook = parsed.duplicate(true) if parsed is Dictionary else {}
		var custom_list := custom_worldbook_entries()
		if not custom_list.is_empty():
			var cats: Array = _worldbook.get("categories", []).duplicate()
			var entries: Array = _worldbook.get("entries", []).duplicate()
			for ce in custom_list:
				if not ce is Dictionary: continue
				var cat := String(ce.get("category", "创意工坊DLC"))
				if cat != "" and not (cat in cats): cats.append(cat)
				var replaced := false
				var cid := String(ce.get("id", ""))
				if cid != "":
					for i in range(entries.size()):
						if entries[i] is Dictionary and String(entries[i].get("id", "")) == cid:
							entries[i] = ce.duplicate(true)
							replaced = true
							break
				if not replaced:
					entries.append(ce.duplicate(true))
			_worldbook["categories"] = cats
			_worldbook["entries"] = entries
		_apply_worldbook_overrides(_worldbook)
	return _worldbook

static func _custom_wb_path() -> String:
	return custom_worldbook_path_override if custom_worldbook_path_override != "" else CUSTOM_WORLDBOOK_PATH

static func custom_worldbook_entries() -> Array:
	if _wb_custom_loaded:
		return _wb_custom
	_wb_custom_loaded = true
	_wb_custom = []
	var p := _custom_wb_path()
	if FileAccess.file_exists(p):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Array:
			for item in parsed:
				if item is Dictionary: _wb_custom.append(item)
	return _wb_custom

static func save_custom_worldbook_entries(entries: Array) -> void:
	_wb_custom_loaded = true
	_wb_custom = entries.duplicate(true)
	var f := FileAccess.open(_custom_wb_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_wb_custom, "\t"))
		f.close()
	_worldbook.clear()
	worldbook()

static func reset_custom_worldbook_cache() -> void:
	_wb_custom_loaded = false
	_wb_custom = []
	_worldbook.clear()

static func _load_worldbook_overrides() -> Dictionary:
	if _wb_overrides_loaded:
		return _wb_overrides
	_wb_overrides_loaded = true
	_wb_overrides = {}
	if FileAccess.file_exists(WORLDBOOK_OVERRIDES_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(WORLDBOOK_OVERRIDES_PATH))
		if parsed is Dictionary:
			_wb_overrides = parsed
	return _wb_overrides

static func _save_worldbook_overrides() -> void:
	var f := FileAccess.open(WORLDBOOK_OVERRIDES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_wb_overrides, "\t"))
		f.close()

static func _apply_worldbook_overrides(book: Dictionary) -> void:
	var ov := _load_worldbook_overrides()
	if ov.is_empty(): return
	var entries: Array = book.get("entries", [])
	for i in range(entries.size()):
		if not entries[i] is Dictionary: continue
		var e: Dictionary = entries[i]
		var eid := String(e.get("id", e.get("title", "")))
		if ov.has(eid) and ov[eid] is Dictionary:
			var patch: Dictionary = ov[eid]
			if not e.has("_orig_title"): e["_orig_title"] = String(e.get("title", ""))
			if not e.has("_orig_body"): e["_orig_body"] = String(e.get("body", ""))
			if patch.has("title"): e["title"] = String(patch.get("title", e.get("title", "")))
			if patch.has("body"): e["body"] = String(patch.get("body", ""))
			e["_modified"] = true
			entries[i] = e

static func has_worldbook_override(entry_id: String) -> bool:
	return _load_worldbook_overrides().has(entry_id)

static func save_worldbook_entry(entry_id: String, new_title: String, new_body: String) -> bool:
	var clean_id := entry_id.strip_edges()
	if clean_id == "": return false
	_load_worldbook_overrides()
	_wb_overrides[clean_id] = {"title": new_title.strip_edges(), "body": new_body}
	_save_worldbook_overrides()
	_worldbook.clear()
	worldbook()
	return true

static func reset_worldbook_entry(entry_id: String) -> void:
	_load_worldbook_overrides()
	_wb_overrides.erase(entry_id)
	_save_worldbook_overrides()
	_worldbook.clear()
	worldbook()

static func character_galleries() -> Dictionary:
	if _char_galleries.is_empty() and FileAccess.file_exists(CHAR_GALLERIES_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CHAR_GALLERIES_PATH))
		if parsed is Dictionary: _char_galleries = parsed
	return _char_galleries.get("characters", {})

static func character_gallery(id: String) -> Dictionary:
	var all: Dictionary = character_galleries()
	return all.get(id, {}) if all.get(id) is Dictionary else {}

static func roster(include_npcs := true) -> Array:
	var out: Array = []
	for c in cast(): out.append(c.id)
	if include_npcs:
		for n in npcs(): out.append(n.id)
	return out

static func cast_ids() -> Array:
	return roster(false)

static func npc_ids() -> Array:
	var out: Array = []
	for n in npcs(): out.append(n.id)
	return out

static func is_npc(id: String) -> bool:
	for n in npcs():
		if String(n.get("id", "")) == id: return true
	return false

static func pose_groups(id: String, outfit_cat := "") -> Array:
	var groups: Array = content().get("pose_groups", {}).get(id, [])
	if outfit_cat == "": return groups
	var out: Array = []
	for g in groups:
		if str(g.get("category", "")) == outfit_cat: out.append(g)
	return out

static func actor(id: String) -> Dictionary:
	var p: Dictionary = profiles().get(id, {})
	var c := cast_entry(id)
	var r := rules_actor(id)
	return {"id": id, "name": name_of(id), "role": c.get("body", p.get("role", "人物资料待整理")), "tone": p.get("tone", ""), "skills": r.skills, "hp": r.hp, "energy": r.energy, "fields": c.get("fields", [])}

static func silhouette_key(raw_cat: String) -> String:
	var s := raw_cat.strip_edges().to_lower()
	match s:
		"child", "小孩", "孩子", "儿童", "幼童", "男童", "女童", "小男孩", "小女孩": return "sil_child"
		"woman", "女人", "女性", "女子", "少女", "妇人", "女士", "阿姨", "老板娘", "大姐", "修女", "女仆": return "sil_woman"
		"man", "男人", "男性", "男子", "大叔", "青年", "男子汉", "先生", "路人": return "sil_man"
		"elder", "老人", "老者", "老伯", "老爷爷", "老奶奶", "老婆婆", "长老", "老太", "老爷子": return "sil_elder"
		"monster", "魔物", "异兽", "魔兽", "怪物", "野兽", "兽", "魔物娘": return "sil_monster"
	return ""

static func silhouette_key_fallback(speaker_name: String) -> String:
	var nm := speaker_name.strip_edges()
	if nm == "": return ""
	for kw in ["魔物", "异兽", "魔兽", "灾兽", "黑狼", "灰狼", "野兽", "地虫", "史莱姆", "怪物"]:
		if kw in nm: return "sil_monster"
	for kw in ["老伯", "老人", "老爷爷", "老奶奶", "老婆婆", "长老", "老者", "大爷", "太婆", "老太", "老汉"]:
		if kw in nm: return "sil_elder"
	for kw in ["小女孩", "小男孩", "小孩", "孩童", "幼童", "儿童", "报童", "小鬼"]:
		if kw in nm: return "sil_child"
	for kw in ["老板娘", "女人", "女子", "女性", "阿姨", "大姐", "夫人", "女士", "修女", "女仆", "女孩", "少女", "大妈"]:
		if kw in nm: return "sil_woman"
	for kw in ["卫兵", "守卫", "护卫", "士兵", "商人", "男人", "男子", "大叔", "伙计", "车夫", "骑士", "先生", "男孩", "少年"]:
		if kw in nm: return "sil_man"
	return ""

## Full-body art: whole expression image per outfit/pose group, switched directly (no layering, no fade), with portrait fallback.
static func art_path(id: String, outfit := "daily", expr := "neutral") -> String:
	if id.begins_with("sil_"):
		var sil_p := "res://assets/characters/silhouettes/%s.webp" % id.trim_prefix("sil_")
		return sil_p if ResourceLoader.exists(sil_p) else ""
	var key := outfit if outfit != "" else "daily"
	var p := "res://assets/characters/%s/%s/%s.webp" % [id, key, expr]
	if ResourceLoader.exists(p): return p
	p = "res://assets/characters/%s/%s/neutral.webp" % [id, key]
	if ResourceLoader.exists(p): return p
	var cat := key.split("_")[0]
	if cat != key:
		p = "res://assets/characters/%s/%s/%s.webp" % [id, cat, expr]
		if ResourceLoader.exists(p): return p
		p = "res://assets/characters/%s/%s/neutral.webp" % [id, cat]
		if ResourceLoader.exists(p): return p
	for g in pose_groups(id, cat):
		var gk := str(g.get("key", ""))
		if gk != "":
			p = "res://assets/characters/%s/%s/%s.webp" % [id, gk, expr]
			if ResourceLoader.exists(p): return p
			p = "res://assets/characters/%s/%s/neutral.webp" % [id, gk]
			if ResourceLoader.exists(p): return p
	p = "res://assets/characters/%s/daily/%s.webp" % [id, expr]
	if ResourceLoader.exists(p): return p
	p = "res://assets/characters/%s/daily/neutral.webp" % [id]
	if ResourceLoader.exists(p): return p
	p = "res://assets/ui/portraits/%s.webp" % id
	return p if ResourceLoader.exists(p) else ""

static func avatar_path(id: String) -> String:
	for p in ["res://assets/characters/%s/avatar.webp" % id, "res://assets/ui/portraits/%s-avatar.webp" % id, "res://assets/ui/portraits/%s.webp" % id]:
		if ResourceLoader.exists(p): return p
	return ""

## Background for a <场景> tag / 当前地点, with 黄昏 / 夜间 variants picked from the hour.
static func scene_for(tag: String, place: String, time_text: String) -> Dictionary:
	var scenes: Array = content().get("scenes", [])
	var base: Dictionary = {}
	if tag != "":
		for s in scenes:
			if s.kind == "base" and String(s.name).split("／")[0] in tag and (s.area in tag or s.country in tag or not "·" in tag):
				base = s; break
		if base.is_empty():
			for s in scenes:
				if s.kind == "base" and s.area in tag: base = s; break
	if base.is_empty():
		var area := place.split("·")[-1] if place != "" else ""
		for s in scenes:
			if s.kind == "base" and area != "" and (area in s.area or s.area in area): base = s; break
		if base.is_empty() and "蛇杖" in place:
			for s in scenes:
				if s.kind == "base" and s.area == "公国蛇杖分部": base = s; break
	if base.is_empty(): return {}
	var hour := -1
	var rx := RegEx.new(); rx.compile("(\\d{1,2})\\s*[:：]\\s*\\d{2}")
	var m := rx.search(time_text)
	if m: hour = int(m.get_string(1))
	var want := ""
	if hour >= 17 and hour < 19: want = "黄昏"
	elif hour >= 19 or (hour >= 0 and hour < 5): want = "夜"
	if want != "":
		for s in scenes:
			if s.kind == "variant" and s.scene == base.scene and want in String(s.name).split("／")[-1]: return s
	return base

## ---- full-version additions (merged back from the original UI-FULL-01 facade, 2026-11-14) ----
static var _rules: Dictionary = {}

static func rules() -> Dictionary:
	if _rules.is_empty(): _rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay_08.json"))
	return _rules

static func rules_actor(id: String) -> Dictionary:
	var a: Dictionary = rules().get("actors", {}).get(id, {})
	var out := {"id": id, "name": name_of(id), "role": a.get("role", "待定"), "hp": a.get("hp", 40), "energy": a.get("energy", 60), "tone": profiles().get(id, {}).get("tone", "")}
	var skills: Array = []
	var icons := {"attack": "sword", "skill_1": "burst", "skill_2": "cover", "guard": "shield", "liberate": "release", "ultimate": "comet"}
	for key in ["attack", "skill_1", "skill_2", "guard", "liberate", "ultimate"]:
		if a.get("actions", {}).has(key):
			var s: Dictionary = a.actions[key]
			skills.append({"key": key, "name": s.name, "hint": s.get("hint", ""), "cost": s.get("cost", 0), "power": s.get("power", 0), "target": s.get("target", "enemy"), "icon": icons[key]})
	if skills.is_empty():
		for key in ["attack", "skill_1", "skill_2", "guard"]:
			skills.append({"key": key, "name": {"attack": "普攻", "skill_1": "技能一", "skill_2": "技能二", "guard": "防御"}[key], "hint": "技能数据待接入。", "cost": 0, "power": 0, "target": "enemy", "icon": icons[key]})
	out["skills"] = skills
	return out

static func party() -> Array:
	return demo().party_order

static func items(tab := "") -> Array:
	return demo().items.filter(func(i): return tab == "" or i.tab == tab)

static func item(id: String) -> Dictionary:
	for i in demo().items:
		if i.id == id: return i
	return {"id": id, "name": id, "icon": "item_shards", "count": 0, "desc": ""}

static var _portrait_reg: Dictionary = {}

static func portrait_registry() -> Dictionary:
	if _portrait_reg.is_empty() and FileAccess.file_exists("res://data/ui/portrait_registry.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/portrait_registry.json"))
		if parsed is Dictionary: _portrait_reg = parsed
	return _portrait_reg

static func _norm_cg_key(s: String) -> String:
	var out := s.strip_edges()
	for ch in ["《", "》", "「", "」", "【", "】", "\"", "'", " "]:
		out = out.replace(ch, "")
	return out

static func illustration_spec(key_or_title: String, override_map: Dictionary = {}) -> Dictionary:
	var raw := key_or_title.strip_edges()
	if raw == "": return {}
	var cg_map: Dictionary = override_map if not override_map.is_empty() else portrait_registry().get("cg", {})
	if not cg_map is Dictionary or cg_map.is_empty(): return {}
	var norm_q := _norm_cg_key(raw)
	var keys := cg_map.keys()
	for pass_idx in range(3):
		for k_raw in keys:
			var k := String(k_raw)
			var val = cg_map[k_raw]
			var title := String(val.get("title", k)) if val is Dictionary else k
			var aliases: Array = val.get("aliases", []) if val is Dictionary and val.get("aliases") is Array else []
			var hit := false
			if pass_idx == 0:
				hit = (k == raw or title == raw)
			elif pass_idx == 1:
				hit = (_norm_cg_key(k) == norm_q or _norm_cg_key(title) == norm_q)
			else:
				for al in aliases:
					if String(al) == raw or _norm_cg_key(String(al)) == norm_q:
						hit = true; break
			if hit:
				var path := String(val.get("res", val.get("path", ""))) if val is Dictionary else String(val)
				if path == "" or not ResourceLoader.exists(path):
					return {}
				return {
					"id": String(val.get("id", k)) if val is Dictionary else k,
					"title": title,
					"category": String(val.get("category", "daily")) if val is Dictionary else "daily",
					"res": path,
				}
	return {}

static func gallery_catalog(unlocked_list: Array = [], override_map: Dictionary = {}) -> Array:
	var cg_map: Dictionary = override_map if not override_map.is_empty() else portrait_registry().get("cg", {})
	if cg_map is Dictionary and not cg_map.is_empty():
		var out: Array = []
		for k_raw in cg_map.keys():
			var spec := illustration_spec(String(k_raw), cg_map)
			if not spec.is_empty():
				var unlocked: bool = (String(spec.get("id", "")) in unlocked_list) or (String(spec.get("title", "")) in unlocked_list)
				out.append({
					"id": spec.id,
					"title": spec.title,
					"category": spec.category,
					"res": spec.res,
					"unlocked": unlocked,
				})
		if not out.is_empty():
			return out
	return demo().get("gallery", [])
