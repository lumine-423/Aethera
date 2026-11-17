extends RefCounted
## Built-in Rolecard RPG Database Engine (7 core tables synced with Hotaru V8 <sumUp> & <dbNote>).
## Contract: F:/sigil-circuit/preset/Hotaru预设与游戏数据库联动规范.md

const Data = preload("res://scripts/ui/ui_data.gd")
const Parser = preload("res://scripts/game/reply_parser.gd")

const SECRET_KEYWORDS := [
	"七罪", "龙种", "特异点", "Project L", "终焉", "深渊", "神之半身",
	"明空的克隆", "克隆体", "七原罪", "黑箱", "核心秘密",
]

var player_state: Dictionary = {
	"name": "你",
	"race": "",
	"origin": "",
	"current_time": "",
	"current_location": "",
	"mana": "待初始化",
	"mana_max": "待初始化",
	"titles": [],
	"appearance": "",
	"bio": "",
	"summary": "",
}
var timeline_summaries: Array = []          # Array[Dictionary]
var character_states: Dictionary = {}        # cid -> Dictionary
var character_knowledge_facts: Array = []    # Array[Dictionary]
var bridge_dialogues: Dictionary = {}        # cid -> {summary: String, messages: Array}
var inventory_and_sigils: Array = []         # Array[Dictionary]
var plot_events_and_world_flags: Array = []  # Array[Dictionary]
var unlocked_illustrations: Array = []       # Array[String] unlocked <插画> IDs

var _fact_seq := 1
var _sum_seq := 1
var _bridge_seq := 1
var _last_branch_id := "main"

func _init() -> void:
	_ensure_all_characters()

func reset_all() -> void:
	timeline_summaries.clear()
	character_states.clear()
	character_knowledge_facts.clear()
	bridge_dialogues.clear()
	inventory_and_sigils.clear()
	plot_events_and_world_flags.clear()
	unlocked_illustrations.clear()
	_fact_seq = 1
	_sum_seq = 1
	_bridge_seq = 1
	_ensure_all_characters()

func _ensure_all_characters() -> void:
	var profiles := Data.profiles()
	for cid_raw in Data.roster():
		var cid := String(cid_raw)
		if not character_states.has(cid):
			var c := Data.cast_entry(cid)
			var p: Dictionary = profiles.get(cid, {})
			var homeland := ""
			for f in c.get("fields", []):
				if f is Array and f.size() >= 2 and String(f[0]) == "所属":
					homeland = String(f[1])
					break
			character_states[cid] = {
				"id": cid,
				"name": Data.name_of(cid),
				"role_group": "npc" if Data.is_npc(cid) else "cast",
				"homeland": homeland,
				"met": false,
				"affection": 0,
				"lewdness": 0,
				"lewd_stage": "纯净",
				"fetishes": [],
				"stage": "未邂逅",
				"form": "日常",
				"outfit": "daily",
				"last_known_location": "",
				"last_seen_time": "",
				"relationship_note": "",
				"attitude_memo": "",
				"pending_promises": [],
				"intro": String(c.get("body", "")),
				"tone": String(p.get("tone", "")),
			}
		if not bridge_dialogues.has(cid):
			bridge_dialogues[cid] = {"summary": "", "messages": []}

static func stage_for_affection(aff: float, met: bool) -> String:
	if not met: return "未邂逅"
	if aff >= 90.0: return "羁绊"
	if aff >= 70.0: return "亲密"
	if aff >= 45.0: return "信赖"
	if aff >= 20.0: return "熟稔"
	return "初识"

static func stage_for_lewdness(val: float, met: bool) -> String:
	if not met: return "纯净"
	if val >= 85.0: return "沉溺"
	if val >= 65.0: return "迷醉"
	if val >= 40.0: return "悸动"
	if val >= 20.0: return "敏感"
	return "纯净"

## Resolve human name / alias to character id; returns "" for narrator/player/unknown.
func resolve_character_id(raw_name: String, player_name := "你") -> String:
	var nm := raw_name.strip_edges()
	if nm == "" or nm in ["你", "我", "主角", "玩家", "{{user}}", player_name]:
		return ""
	var cid := Data.id_of(nm)
	if cid != "": return cid
	for k in character_states.keys():
		var cname := String(character_states[k].get("name", ""))
		if cname != "" and (nm == cname or (cname.length() >= 2 and cname in nm)):
			return String(k)
	return ""

## Rebuild deterministic tables from current main-story messages + stat_data + persona,
## while preserving manual entries, bridge dialogues, and private bridge/manual knowledge.
func sync_from_game(branch_id: String, messages: Array, stat_data: Dictionary, persona_data: Dictionary) -> void:
	_last_branch_id = branch_id if branch_id != "" else "main"
	_ensure_all_characters()
	var pname := String(persona_data.get("name", "你"))
	if pname.strip_edges() == "": pname = "你"
	var hero: Dictionary = stat_data.get("主角组", {})
	player_state = {
		"name": pname,
		"race": String(persona_data.get("race", "")),
		"origin": String(persona_data.get("origin", "")),
		"current_time": String(hero.get("时间", "")),
		"current_location": String(hero.get("当前地点", "")),
		"mana": hero.get("魔力", "待初始化"),
		"mana_max": hero.get("魔力上限", "待初始化"),
		"bgm": String(hero.get("当前BGM", "")),
		"present_cast": hero.get("当前在场角色", []).duplicate() if hero.get("当前在场角色") is Array else [],
		"slain_anomalies": hero.get("已讨伐异危", []).duplicate() if hero.get("已讨伐异危") is Array else [],
		"titles": player_state.get("titles", []).duplicate(),
		"appearance": String(persona_data.get("appearance", "")),
		"bio": String(persona_data.get("bio", "")),
		"summary": String(hero.get("简介", "")),
	}

	# Preserve user/bridge authored data across main replay
	var kept_manual_sums: Array = []
	for s in timeline_summaries:
		if s is Dictionary and bool(s.get("manual", false)):
			kept_manual_sums.append(s)
	var kept_facts: Array = []
	for f in character_knowledge_facts:
		if f is Dictionary and String(f.get("source", "")) in ["bridge", "manual"]:
			kept_facts.append(f)

	timeline_summaries = kept_manual_sums
	character_knowledge_facts = kept_facts

	# Sync known character baseline from MVU / stat_data.角色组
	var known_group: Dictionary = stat_data.get("角色组", {})
	for cid in character_states.keys():
		var st: Dictionary = character_states[cid]
		var cname := String(st.get("name", ""))
		if known_group.has(cname) and known_group[cname] is Dictionary:
			var kd: Dictionary = known_group[cname]
			var aff := float(kd.get("好感度", st.get("affection", 0)))
			var lewd := float(kd.get("色情值", st.get("lewdness", 0)))
			st["met"] = true
			st["affection"] = int(round(clampf(aff, 0.0, 100.0)))
			st["lewdness"] = int(round(clampf(lewd, 0.0, 100.0)))
			st["stage"] = stage_for_affection(aff, true)
			st["lewd_stage"] = stage_for_lewdness(lewd, true)
			if kd.get("已解锁性癖") is Array:
				st["fetishes"] = kd.get("已解锁性癖", []).duplicate()
			if String(kd.get("简介", "")).strip_edges() != "":
				st["intro"] = String(kd.get("简介", ""))
			if String(kd.get("当前形态", "")).strip_edges() != "":
				st["form"] = String(kd.get("当前形态", "日常"))
			elif String(kd.get("状态", "")).strip_edges() != "":
				st["form"] = String(kd.get("状态", ""))
		else:
			if String(st.get("attitude_memo", "")) == "":
				st["met"] = false
				st["stage"] = "未邂逅"
				st["lewd_stage"] = "纯净"
		character_states[cid] = st

	# Sync inventory & sigils from stat_data.主角组
	inventory_and_sigils.clear()
	var items_dict = hero.get("持有物品", {})
	if items_dict is Dictionary:
		for item_name in items_dict.keys():
			var iv = items_dict[item_name]
			var desc := String(iv.get("描述", "")) if iv is Dictionary else str(iv)
			var cnt := int(iv.get("数量", 1)) if iv is Dictionary else 1
			inventory_and_sigils.append({
				"id": "item_" + String(item_name),
				"kind": "item",
				"name": String(item_name),
				"tier": "",
				"description": desc,
				"count": cnt,
				"holder": "hero",
				"source_msg_id": 0,
			})
	var magics_dict = hero.get("魔法", {})
	if magics_dict is Dictionary:
		for mname in magics_dict.keys():
			var mv = magics_dict[mname]
			var mdesc := ""
			if mv is Dictionary:
				mdesc = "载体：%s · 效果：%s · 耗用：%s" % [String(mv.get("载体", "")), String(mv.get("效果", "")), str(mv.get("耗用", ""))]
			else:
				mdesc = str(mv)
			inventory_and_sigils.append({
				"id": "magic_" + String(mname),
				"kind": "magic",
				"name": String(mname),
				"tier": "刻印魔法",
				"description": mdesc,
				"count": 1,
				"holder": "hero",
				"source_msg_id": 0,
			})

	# Sync plot events from MVU 剧情事件
	plot_events_and_world_flags.clear()
	var ev_root: Dictionary = stat_data.get("剧情事件", {})
	var live_ev = ev_root.get("当前触发事件", {})
	if live_ev is Dictionary:
		for ename in live_ev.keys():
			plot_events_and_world_flags.append({
				"id": "ev_live_" + String(ename),
				"title": String(ename),
				"status": "live",
				"location": player_state.get("current_location", ""),
				"participants": [],
				"description": String(live_ev[ename]),
				"visibility": "world_public",
			})
	var done_ev = ev_root.get("已完成事件", [])
	if done_ev is Array:
		for ename in done_ev:
			plot_events_and_world_flags.append({
				"id": "ev_done_" + String(ename),
				"title": String(ename),
				"status": "done",
				"location": "",
				"participants": [],
				"description": "已完成主线事件",
				"visibility": "world_public",
			})

	# Replay main story floors idempotently into timeline_summaries & main_story_witnessed
	var seen_keys := {}
	for ms in timeline_summaries:
		if ms is Dictionary and int(ms.get("source_msg_id", -1)) >= 0:
			var m_br := String(ms.get("branch_id", _last_branch_id))
			seen_keys["%s:%d:%d" % [m_br, int(ms.get("source_msg_id", -1)), int(ms.get("swipe_idx", 0))]] = true
	var last_scene := String(hero.get("当前地点", ""))
	var last_time := String(hero.get("时间", ""))
	for m in messages:
		if not m is Dictionary or String(m.get("role", "")) != "assistant":
			continue
		var mid := int(m.get("id", 0))
		var swipe_idx := int(m.get("swipe", 0))
		var swipes: Array = m.get("swipes", [""])
		if swipes.is_empty(): continue
		var raw := String(swipes[clampi(swipe_idx, 0, swipes.size() - 1)])
		var parsed: Dictionary = Parser.parse(raw, pname)
		if String(parsed.get("scene", "")) != "":
			last_scene = String(parsed.get("scene", ""))
		# Update pose / cast location tracking
		var present_ids: Array = []
		var present_names: Array = []
		for c_entry in parsed.get("cast", []):
			var cname := String(c_entry.get("name", ""))
			var cid := resolve_character_id(cname, pname)
			if cid != "":
				if not cid in present_ids: present_ids.append(cid)
				if not cname in present_names: present_names.append(cname)
				var cst: Dictionary = character_states[cid]
				cst["met"] = true
				if String(c_entry.get("outfit", "")) != "":
					cst["outfit"] = String(c_entry.get("outfit", ""))
				if last_scene != "": cst["last_known_location"] = last_scene
				if cst["stage"] == "未邂逅": cst["stage"] = stage_for_affection(float(cst["affection"]), true)
				character_states[cid] = cst
		var pose_d: Dictionary = parsed.get("pose", {})
		if not pose_d.is_empty():
			var pid := resolve_character_id(String(pose_d.get("character", "")), pname)
			if pid != "" and character_states.has(pid):
				var form_str := String(pose_d.get("pose", ""))
				if String(pose_d.get("state", "")) != "":
					form_str += (" · " + String(pose_d.get("state", ""))) if form_str != "" else String(pose_d.get("state", ""))
				if form_str != "":
					character_states[pid]["form"] = form_str

		var cg_raw := String(parsed.get("cg", "")).strip_edges()
		if cg_raw != "":
			var cg_spec := Data.illustration_spec(cg_raw)
			if not cg_spec.is_empty():
				unlock_illustration(String(cg_spec.get("id", cg_raw)))

		var su: Dictionary = parsed.get("sum_up", {})
		if su.is_empty(): continue
		var dedupe_key := "%s:%d:%d" % [_last_branch_id, mid, swipe_idx]
		if seen_keys.has(dedupe_key): continue
		seen_keys[dedupe_key] = true

		var s_time := String(su.get("time", ""))
		if s_time == "": s_time = last_time
		else: last_time = s_time
		var s_loc := String(su.get("location", ""))
		if s_loc == "": s_loc = last_scene

		var sum_ids: Array = []
		var sum_names: Array = []
		for rn in su.get("role_names", []):
			var rname := String(rn)
			var rcid := resolve_character_id(rname, pname)
			if rcid != "":
				if not rcid in sum_ids: sum_ids.append(rcid)
				var canonical := String(character_states[rcid].get("name", rname))
				if not canonical in sum_names: sum_names.append(canonical)
		# Fallback to <在场> cast if <sumUp> didn't list specific character names
		if sum_ids.is_empty() and not present_ids.is_empty():
			sum_ids = present_ids.duplicate()
			sum_names = present_names.duplicate()

		var vis := String(su.get("visibility", "present_only"))
		var vis_label := "公开传闻" if vis == "world_public" else "在场私密"
		var event_txt := String(su.get("event", "")).strip_edges()
		var clues_txt := String(su.get("clues", "")).strip_edges()
		var changes_txt := String(su.get("changes", "")).strip_edges()

		timeline_summaries.append({
			"id": "sum_%s_%d_%d" % [_last_branch_id, mid, swipe_idx],
			"branch_id": _last_branch_id,
			"source_msg_id": mid,
			"swipe_idx": swipe_idx,
			"game_time": s_time,
			"location": s_loc,
			"participants": sum_ids,
			"participant_names": sum_names,
			"visibility": vis,
			"visibility_label": vis_label,
			"event": event_txt,
			"clues": clues_txt,
			"changes": changes_txt,
			"manual": false,
		})

		# Update participants' known location & witnessed facts
		for pid in sum_ids:
			var pst: Dictionary = character_states[pid]
			pst["met"] = true
			if s_loc != "": pst["last_known_location"] = s_loc
			if s_time != "": pst["last_seen_time"] = s_time
			if pst["stage"] == "未邂逅": pst["stage"] = stage_for_affection(float(pst["affection"]), true)
			if changes_txt != "" and (String(pst["name"]) in changes_txt or "态度" in changes_txt or "关系" in changes_txt):
				pst["relationship_note"] = changes_txt
			character_states[pid] = pst
			character_knowledge_facts.append({
				"id": "fact_msg_%d_%s" % [mid, pid],
				"character_id": pid,
				"fact_type": "main_story_witnessed",
				"game_time": s_time,
				"content": "%s（地点：%s）" % [event_txt, s_loc if s_loc != "" else "未知"],
				"source": "msg:%d" % mid,
				"importance": 4,
			})
		if vis == "world_public" and event_txt != "":
			plot_events_and_world_flags.append({
				"id": "rumor_%d" % mid,
				"title": "公开传闻 · " + (s_loc if s_loc != "" else "艾瑟拉"),
				"status": "rumor",
				"location": s_loc,
				"participants": sum_names,
				"description": event_txt,
				"visibility": "world_public",
			})

## Return summaries visible from a single character's perspective + hidden private count.
func summaries_for_character(cid: String) -> Dictionary:
	var visible: Array = []
	var hidden_count := 0
	for s in timeline_summaries:
		if not s is Dictionary: continue
		var vis := String(s.get("visibility", "present_only"))
		var parts: Array = s.get("participants", [])
		if vis == "world_public" or cid in parts:
			visible.append(s)
		else:
			hidden_count += 1
	return {"visible": visible, "hidden_private_count": hidden_count}

func facts_for_character(cid: String) -> Array:
	var out: Array = []
	for f in character_knowledge_facts:
		if f is Dictionary and String(f.get("character_id", "")) == cid:
			out.append(f)
	return out

func _is_high_secret_entry(entry: Dictionary, cid: String, cname: String, known_text: String) -> bool:
	var title := String(entry.get("title", ""))
	var path := String(entry.get("path", ""))
	var combined := title + " " + path
	# If this worldbook entry specifically names the target character, she knows her own surface/stage lore unless flagged secret
	if cname != "" and cname in title and not ("秘密" in combined or "真相" in combined or "底层" in combined):
		return false
	for kw in SECRET_KEYWORDS:
		if kw in combined:
			# Allow only if character already unlocked a fact mentioning this secret keyword
			if kw in known_text:
				return false
			# Or if character is a known primal dragon / singularity holder asking about their own domain name
			if cid in ["lufa", "washake"] and kw == "龙种":
				return false
			return true
	return false

func _character_full_setting(cid: String, cname: String, cur_form := "日常") -> String:
	var c: Dictionary = Data.cast_entry(cid)
	var p: Dictionary = Data.profiles().get(cid, {})
	var parts := PackedStringArray()
	var tone := String(p.get("tone", "")).strip_edges()
	if tone != "":
		parts.append("口吻定位：%s" % tone)
	var body := String(c.get("body", "")).strip_edges()
	if body != "":
		parts.append("人物概览：%s" % body)
	var fields: Array = c.get("fields", [])
	if not fields.is_empty():
		var flines := PackedStringArray()
		for f in fields:
			if f is Array and f.size() >= 2:
				flines.append("%s：%s" % [String(f[0]), String(f[1])])
		if not flines.is_empty():
			parts.append(" · ".join(flines))
	var stages_val = c.get("stages", {})
	if stages_val is Dictionary and not (stages_val as Dictionary).is_empty():
		var stages: Dictionary = stages_val
		var picked_keys: Array = []
		if stages.has("日常"): picked_keys.append("日常")
		elif stages.has("其一"): picked_keys.append("其一")
		else: picked_keys.append(stages.keys()[0])
		if ("解放" in cur_form) and stages.has("解放") and not ("解放" in picked_keys):
			picked_keys.append("解放")
		elif ("其二" in cur_form) and stages.has("其二") and not ("其二" in picked_keys):
			picked_keys.append("其二")
		for sk in picked_keys:
			var stxt := String(stages.get(sk, "")).strip_edges()
			if stxt != "":
				parts.append(stxt)
	else:
		# Fallback for NPCs or characters whose full profile lives in worldbook
		var wb_entries: Array = Data.worldbook().get("entries", [])
		for e in wb_entries:
			if e is Dictionary and cname != "" and ("角色 · %s" % cname) in String(e.get("title", "")):
				var b := String(e.get("body", "")).strip_edges()
				if b != "": parts.append(b)
	return "\n".join(parts)

## Assemble the isolated context package for 1-on-1 Single-Character Bridge Chat.
## Guarantees full main-story chatHistory is NEVER sent, injects the target character's
## complete profile, and enforces 1-5 spoken-line IM replies.
func build_bridge_context(cid: String, user_input := "") -> Dictionary:
	_ensure_all_characters()
	var st: Dictionary = character_states.get(cid, {})
	var cname := String(st.get("name", Data.name_of(cid)))
	var homeland := String(st.get("homeland", ""))
	var last_loc := String(st.get("last_known_location", ""))
	var hero_loc := String(player_state.get("current_location", ""))
	var cur_form := String(st.get("form", "日常"))
	var c_facts := facts_for_character(cid)
	var known_blob := ""
	for f in c_facts:
		known_blob += String(f.get("content", "")) + "\n"

	var full_persona_sheet := _character_full_setting(cid, cname, cur_form)

	var vis_info := summaries_for_character(cid)
	var visible_sums: Array = vis_info.get("visible", [])
	var hidden_private_count := int(vis_info.get("hidden_private_count", 0))
	if visible_sums.size() > 8:
		visible_sums = visible_sums.slice(visible_sums.size() - 8, visible_sums.size())

	# Step 1: Query Worldbook selectively & enforce secrecy boundary
	var wb: Dictionary = Data.worldbook()
	var wb_entries: Array = wb.get("entries", [])
	var matched_entries: Array = []
	var matched_titles: Array = []
	var filtered_secrets: Array = []
	var uq := user_input.strip_edges()
	for e in wb_entries:
		if not e is Dictionary: continue
		var cat := String(e.get("category", ""))
		var title := String(e.get("title", ""))
		# Never inject raw MVU patch specs or initvar into 1-on-1 bridge chat
		if cat == "系统与叙事规则" or "[mvu_" in title or "[initvar]" in title:
			continue
		# Character's own core profile is already injected cleanly via full_persona_sheet
		if cname != "" and ("角色 · %s" % cname) in title:
			if not title in matched_titles: matched_titles.append(title)
			continue
		if _is_high_secret_entry(e, cid, cname, known_blob):
			filtered_secrets.append(title)
			continue
		var hit := false
		if cname != "" and cname in title:
			hit = true
		elif homeland != "" and (homeland in title or homeland in cat or homeland in String(e.get("body", "")).substr(0, 120)):
			if cat in ["国家与组织", "地点设定", "后剧情动态"]: hit = true
		elif last_loc != "" and last_loc.split("·")[-1] in title:
			hit = true
		elif cat == "世界设定" and ("魔力" in title or "刻印" in title or "货币" in title or "历法" in title):
			hit = true
		elif uq != "" and uq.length() >= 2:
			for token in [uq, hero_loc.split("·")[-1]]:
				if token.length() >= 2 and token in (title + " " + String(e.get("summary", ""))):
					hit = true
					break
		if hit and matched_entries.size() < 8:
			matched_entries.append(e)
			matched_titles.append(title)

	# Step 2: Relevant inventory (gifted to this character or visible on hero)
	var rel_items: Array = []
	for item in inventory_and_sigils:
		if not item is Dictionary: continue
		var holder := String(item.get("holder", "hero"))
		if holder == "hero" or holder == ("gifted:" + cid):
			rel_items.append("%s（%s）" % [String(item.get("name", "")), "已赠予" + cname if holder.begins_with("gifted:") else "主角随身携带"])

	# Step 3: Recent isolated bridge dialogue window (last 14 bubbles)
	var b_rec: Dictionary = bridge_dialogues.get(cid, {"summary": "", "messages": []})
	var b_sum := String(b_rec.get("summary", "")).strip_edges()
	var b_msgs_all: Array = b_rec.get("messages", [])
	var recent_msgs: Array = b_msgs_all.slice(maxi(0, b_msgs_all.size() - 14), b_msgs_all.size())

	# Step 4: Assemble formatted prompt blocks strictly enforcing 1-on-1 character lock + 1~5 spoken msgs
	var lines := PackedStringArray()
	lines.append("=== [Hotaru 预设联动模式：🗣️ 联动-角色单独对话模式 (hotaru_opt_bridge_chat = ON)] ===")
	lines.append("【绝对单聊规则 · 与主线小说完全隔离】")
	lines.append("1. 你现在只能扮演【%s】本人，只能以她的第一人称口癖亲自说话；严禁出现任何其他角色发言或行动。" % cname)
	lines.append("2. 严禁写第三人称旁白、动作描写、神态描写、心理描写或环境描写（不要写“她笑了笑”“*歪头*”“（叹气）”等）；情绪只通过台词口癖、停顿和措辞传达。")
	lines.append("3. 每次回复必须在 <content>...</content> 内输出 1～5 条短消息，每条单独用 <msg>...</msg> 包裹；每条 <msg> 仅写她嘴里说出的原话，不要带【%s】：前缀或外层引号，也绝不代写主角回应。" % cname)
	lines.append("4. 结尾仅附带 <dbNote>\\n态度: ...\\n记忆: ...\\n</dbNote>；严禁输出 <sumUp>/<pose>/<choices>/<UpdateVariable>/<BTS>；严禁泄露未被注入的他人私密剧情或未解锁机密。")
	lines.append("")
	lines.append("=== [当前交互对象与实时数值状态] ===")
	var f_list: Array = st.get("fetishes", [])
	var f_str := "、".join(PackedStringArray(f_list)) if not f_list.is_empty() else "无"
	lines.append("角色：%s（%s）｜所属：%s｜当前形态：%s｜关系：%s（好感 %d / 色情 %d · %s）" % [
		cname, cid, homeland if homeland != "" else "未知", cur_form,
		String(st.get("stage", "未邂逅")), int(st.get("affection", 0)), int(st.get("lewdness", 0)), String(st.get("lewd_stage", "纯净"))
	])
	if not f_list.is_empty():
		lines.append("已解锁性癖：%s" % f_str)
	lines.append("最后已知时间/地点：%s · %s" % [String(st.get("last_seen_time", "未知")), last_loc if last_loc != "" else "未知"])
	if String(st.get("attitude_memo", "")) != "":
		lines.append("最新态度备忘：%s" % String(st.get("attitude_memo", "")))
	if String(st.get("relationship_note", "")) != "":
		lines.append("关系变动记要：%s" % String(st.get("relationship_note", "")))
	lines.append("")
	lines.append("=== [唯一扮演对象 · 完整角色设定档案（必须 100% 遵循）] ===")
	lines.append(full_persona_sheet)
	lines.append("【保密与认知约束】只以 %s 当前视角已知的事情说话；其设定里注明本人不知情的身世秘密及未解锁高密世界词条一律不得泄露。" % cname)
	lines.append("")
	lines.append("=== [主角状态快照] ===")
	lines.append("主角：%s（出身：%s，当前所在：%s，时间：%s）" % [String(player_state.get("name", "你")), String(player_state.get("origin", "")), hero_loc if hero_loc != "" else "未知", String(player_state.get("current_time", "未知"))])
	if not rel_items.is_empty():
		lines.append("相关物品/魔法：%s" % "、".join(PackedStringArray(rel_items)))
	lines.append("")
	lines.append("=== [按需检索的世界书辅助词条（%d 条环境/地理已注入；%d 条高密词条已隔离）] ===" % [matched_entries.size(), filtered_secrets.size()])
	for e in matched_entries:
		var snippet := String(e.get("body", "")).strip_edges()
		if snippet.length() > 600: snippet = snippet.substr(0, 600) + "……"
		lines.append("· [%s] %s：%s" % [String(e.get("category", "")), String(e.get("title", "")), snippet.replace("\n", " ")])
	lines.append("")
	lines.append("=== [%s 知情的时间线纪要（共 %d 条；已自动隔离 %d 条不在场私密事件）] ===" % [cname, visible_sums.size(), hidden_private_count])
	if visible_sums.is_empty():
		lines.append("（主线中暂未与 %s 共历已入库事件，亦无相关公开传闻）" % cname)
	else:
		for s in visible_sums:
			lines.append("· [%s｜%s｜%s] %s%s" % [
				String(s.get("game_time", "未知时间")),
				String(s.get("location", "未知地点")),
				String(s.get("visibility_label", "在场私密")),
				String(s.get("event", "")),
				("（线索：" + String(s.get("clues", "")) + "）") if String(s.get("clues", "")) != "" else ""
			])
	lines.append("")
	lines.append("=== [%s 专属记忆片段（character_knowledge_facts）] ===" % cname)
	if c_facts.is_empty():
		lines.append("（暂无额外专属记忆）")
	else:
		var start_idx := maxi(0, c_facts.size() - 10)
		for idx in range(start_idx, c_facts.size()):
			var f: Dictionary = c_facts[idx]
			lines.append("· [%s] %s" % [String(f.get("fact_type", "")), String(f.get("content", ""))])
	if b_sum != "":
		lines.append("")
		lines.append("=== [既往单聊远期摘要] ===")
		lines.append(b_sum)

	var system_prompt := "\n".join(lines)
	var api_messages: Array = [{"role": "system", "content": system_prompt}]
	# Group consecutive assistant bubbles into clean <content><msg>...</msg></content> turns for strict role alternation
	var pending_ai := PackedStringArray()
	for bm in recent_msgs:
		var r_role := String(bm.get("role", "user"))
		var r_txt := String(bm.get("text", "")).strip_edges()
		if r_role == "assistant":
			if r_txt != "": pending_ai.append("<msg>%s</msg>" % r_txt)
		else:
			if not pending_ai.is_empty():
				api_messages.append({"role": "assistant", "content": "<content>\n%s\n</content>" % "\n".join(pending_ai)})
				pending_ai = PackedStringArray()
			api_messages.append({"role": "user", "content": r_txt})
	if not pending_ai.is_empty():
		api_messages.append({"role": "assistant", "content": "<content>\n%s\n</content>" % "\n".join(pending_ai)})
	if uq != "":
		api_messages.append({"role": "user", "content": uq})

	return {
		"character_id": cid,
		"character_name": cname,
		"preset_mode": "hotaru_opt_bridge_chat (🗣️ 联动-角色单独对话模式 · 纯台词 1-5 条)",
		"persona_sheet_included": full_persona_sheet != "",
		"persona_sheet_chars": full_persona_sheet.length(),
		"main_chat_history_sent": false,
		"worldbook_matched": matched_titles,
		"worldbook_filtered_secrets": filtered_secrets,
		"visible_summaries": visible_sums,
		"isolated_private_summaries_count": hidden_private_count,
		"character_facts": c_facts,
		"recent_bridge_messages": recent_msgs,
		"bridge_summary": b_sum,
		"assembled_prompt_preview": system_prompt,
		"api_messages": api_messages,
	}

## Append ONLY the player's outgoing bridge message immediately so live-API turns show right away in UI.
func append_bridge_user(cid: String, user_text: String) -> void:
	_ensure_all_characters()
	var cur_time := String(player_state.get("current_time", ""))
	var rec: Dictionary = bridge_dialogues.get(cid, {"summary": "", "messages": []})
	var msgs: Array = rec.get("messages", [])
	msgs.append({"id": _bridge_seq, "turn_id": _bridge_seq, "role": "user", "text": user_text, "game_time": cur_time, "db_note": {}})
	_bridge_seq += 1
	rec["messages"] = msgs
	bridge_dialogues[cid] = rec

## Append 1..5 parsed assistant speech bubbles + write back <dbNote> attitude & memory.
func append_bridge_reply(cid: String, raw_ai_reply: String) -> Dictionary:
	_ensure_all_characters()
	var pname := String(player_state.get("name", "你"))
	var cname := String(character_states.get(cid, {}).get("name", Data.name_of(cid)))
	var parsed := Parser.bridge_plain(raw_ai_reply, pname, cname)
	var bubble_list: Array = parsed.get("messages", [])
	if bubble_list.is_empty():
		var fb := String(parsed.get("text", "")).strip_edges()
		if fb == "": fb = raw_ai_reply.strip_edges()
		if fb != "": bubble_list.append(fb)
	var db_note: Dictionary = parsed.get("db_note", {})
	var cur_time := String(player_state.get("current_time", ""))

	var rec: Dictionary = bridge_dialogues.get(cid, {"summary": "", "messages": []})
	var msgs: Array = rec.get("messages", [])
	var turn_id := _bridge_seq - 1
	if not msgs.is_empty() and String(msgs.back().get("role", "")) == "user":
		turn_id = int(msgs.back().get("turn_id", turn_id))
	for bi in range(bubble_list.size()):
		var b_txt := String(bubble_list[bi]).strip_edges()
		if b_txt == "": continue
		msgs.append({
			"id": _bridge_seq,
			"turn_id": turn_id,
			"role": "assistant",
			"text": b_txt,
			"game_time": cur_time,
			"db_note": db_note if bi == bubble_list.size() - 1 else {},
		})
		_bridge_seq += 1
	rec["messages"] = msgs
	bridge_dialogues[cid] = rec

	# Write back <dbNote> attitude & memory
	var att := String(db_note.get("attitude", "")).strip_edges()
	var mem := String(db_note.get("memory", "")).strip_edges()
	var st: Dictionary = character_states[cid]
	st["met"] = true
	if st["stage"] == "未邂逅": st["stage"] = stage_for_affection(float(st["affection"]), true)
	if att != "" and att != "无":
		st["attitude_memo"] = att
	character_states[cid] = st

	if mem != "" and mem != "无":
		character_knowledge_facts.append({
			"id": "fact_bridge_%d" % _fact_seq,
			"character_id": cid,
			"fact_type": "bridge_memory",
			"game_time": cur_time,
			"content": mem,
			"source": "bridge",
			"importance": 4,
		})
		_fact_seq += 1

	if msgs.size() > 24:
		compress_bridge_history(cid)

	return {"clean_text": String(parsed.get("text", "")), "messages": bubble_list, "db_note": db_note}

## Record one completed 1-on-1 bridge chat turn (1 user message + 1..5 spoken assistant bubbles)
## and parse <dbNote> updates back to DB.
func record_bridge_turn(cid: String, user_text: String, raw_ai_reply: String) -> Dictionary:
	append_bridge_user(cid, user_text)
	return append_bridge_reply(cid, raw_ai_reply)

## Assemble Main-Story runtime context (Hero Persona + Live stat_data + Active Character Sheets + MVU/Format/Location Worldbook).
func build_main_story_world_context(stat_data: Dictionary, persona_data: Dictionary, recent_chat_text := "") -> String:
	var lines := PackedStringArray()
	var hero: Dictionary = stat_data.get("主角组", {})
	var cur_loc := String(hero.get("当前地点", ""))
	lines.append("=== [玩家与当前主角档案] ===")
	lines.append("姓名：%s｜种族：%s｜出身：%s" % [
		String(persona_data.get("name", "你")),
		String(persona_data.get("race", "未定")),
		String(persona_data.get("origin", "")),
	])
	if String(persona_data.get("appearance", "")) != "":
		lines.append("外貌：%s" % String(persona_data.get("appearance", "")))
	if String(persona_data.get("bio", "")) != "":
		lines.append("背景：%s" % String(persona_data.get("bio", "")))
	lines.append("")
	lines.append("=== [当前 MVU 变量快照 stat_data（请据此在末尾用 <UpdateVariable><JSONPatch> 更新变动）] ===")
	lines.append(JSON.stringify(stat_data))
	lines.append("")

	# Active / mentioned characters full setting
	var mentioned_ids: Array = []
	var known_group: Dictionary = stat_data.get("角色组", {})
	for rname in known_group.keys():
		var cid := Data.id_of(String(rname))
		if cid != "" and not cid in mentioned_ids: mentioned_ids.append(cid)
	for cid_raw in Data.roster(true):
		var cid := String(cid_raw)
		var cname := Data.name_of(cid)
		if cname != "" and (cname in recent_chat_text or cname in cur_loc) and not cid in mentioned_ids:
			mentioned_ids.append(cid)
		if mentioned_ids.size() >= 6: break

	if not mentioned_ids.is_empty():
		lines.append("=== [当前在场与关联角色设定档案] ===")
		for cid in mentioned_ids:
			var cname := Data.name_of(String(cid))
			var st: Dictionary = character_states.get(cid, {})
			lines.append(_character_full_setting(String(cid), cname, String(st.get("form", "日常"))))
			lines.append("---")
		lines.append("")

	# Pass 1: Core MVU rules, dialogue format rules, and world overviews (guaranteed never dropped by entry cap)
	var core_titles := [
		"规则 · 世界叙述指南", "规则 · 对话格式规则",
		"[mvu_update]变量输出格式", "[mvu_update]角色组更新规则",
		"[mvu_update]主角状态规则", "[mvu_update]BGM选择规则",
		"[mvu_plot]剧情事件规则", "国家速览", "地区速览", "NPC角色速览"
	]
	var wb_entries: Array = Data.worldbook().get("entries", [])
	var injected: Array = []
	for e in wb_entries:
		if not e is Dictionary: continue
		var t := String(e.get("title", ""))
		var body := String(e.get("body", "")).strip_edges()
		var ws_const := bool(e.get("_workshop", false)) and bool(e.get("constant", false))
		if body != "" and ((t in core_titles) or ws_const) and not (t in injected):
			injected.append(t)
			lines.append("【%s｜%s】\n%s" % [String(e.get("category", "")), t, body])

	# Pass 2: Supplemental location / keyword-matched Worldbook lore & active Workshop DLC entries
	var extra_cnt := 0
	var loc_tail := cur_loc.split("·")[-1]
	var loc_country := cur_loc.split("·")[0]
	var hay_lower := (recent_chat_text + " " + cur_loc).to_lower()
	for e in wb_entries:
		if not e is Dictionary: continue
		var t := String(e.get("title", ""))
		if (t in injected) or t == "[initvar]变量初始化勿开" or t == "[mvu_update]备用输出提醒" or t.begins_with("角色 · "):
			continue
		var body := String(e.get("body", "")).strip_edges()
		if body == "": continue
		if bool(e.get("_workshop", false)):
			var ws_type := String(e.get("_workshop_type", ""))
			var ws_hit := false
			if ws_type == "character" and t.begins_with("DLC/"):
				var rn := t.trim_prefix("DLC/")
				if known_group.has(rn) or (rn != "" and rn in recent_chat_text):
					ws_hit = true
			elif ws_type == "faction":
				for kw_raw in e.get("keywords", []):
					var kw := String(kw_raw).strip_edges().to_lower()
					if kw != "" and hay_lower.contains(kw):
						ws_hit = true; break
			elif ws_type == "event":
				var bound: Array = e.get("role_names", []) if e.get("role_names") is Array else []
				if bound.is_empty() or bound.any(func(rn): return known_group.has(String(rn)) or String(rn) in recent_chat_text):
					ws_hit = true
			if ws_hit:
				injected.append(t)
				lines.append("<rule_动态内容_%s>\n%s\n</rule_动态内容_%s>" % [t, body, t])
			continue
		if extra_cnt >= 10:
			continue
		var hit := false
		if loc_tail.length() >= 2 and (loc_tail in t or loc_tail in String(e.get("summary", ""))):
			hit = true
		elif String(e.get("category", "")) in ["世界设定", "国家与组织", "地点设定", "后剧情动态", "剧情事件"]:
			for kw in [loc_tail, loc_country]:
				if kw.length() >= 2 and kw in (t + " " + body.substr(0, 120)):
					hit = true; break
			if not hit and recent_chat_text != "" and (t.split(" · ")[-1] in recent_chat_text):
				hit = true
		if hit:
			injected.append(t)
			lines.append("【%s｜%s】\n%s" % [String(e.get("category", "")), t, body])
			extra_cnt += 1
	return "\n".join(lines)

func compress_bridge_history(cid: String) -> void:
	if not bridge_dialogues.has(cid): return
	var rec: Dictionary = bridge_dialogues[cid]
	var msgs: Array = rec.get("messages", [])
	if msgs.size() <= 6: return
	var fold_count := maxi(2, msgs.size() - 8)
	var snippets := PackedStringArray()
	var old_sum := String(rec.get("summary", "")).strip_edges()
	if old_sum != "": snippets.append(old_sum)
	var pname := String(player_state.get("name", "你"))
	var cname := String(character_states.get(cid, {}).get("name", cid))
	for i in range(fold_count):
		var m: Dictionary = msgs[i]
		var who := pname if String(m.get("role", "")) == "user" else cname
		var txt := String(m.get("text", "")).replace("\n", " ")
		if txt.length() > 80: txt = txt.substr(0, 80) + "…"
		snippets.append("%s：%s" % [who, txt])
	rec["summary"] = "\n".join(snippets)
	rec["messages"] = msgs.slice(fold_count, msgs.size())
	bridge_dialogues[cid] = rec

func clear_bridge_history(cid: String) -> void:
	bridge_dialogues[cid] = {"summary": "", "messages": []}

func add_character_fact(cid: String, content: String, fact_type := "manual") -> void:
	var clean := content.strip_edges()
	if cid == "" or clean == "": return
	character_knowledge_facts.append({
		"id": "fact_manual_%d" % _fact_seq,
		"character_id": cid,
		"fact_type": fact_type,
		"game_time": String(player_state.get("current_time", "")),
		"content": clean,
		"source": "manual",
		"importance": 5,
	})
	_fact_seq += 1

func delete_character_fact(fact_id: String) -> void:
	character_knowledge_facts = character_knowledge_facts.filter(func(f): return String(f.get("id", "")) != fact_id)

func save_manual_summary(entry: Dictionary) -> void:
	var sid := String(entry.get("id", "")).strip_edges()
	var pname := String(player_state.get("name", "你"))
	var roles_raw := String(entry.get("roles_raw", "")).strip_edges()
	var p_ids: Array = entry.get("participants", []).duplicate() if entry.get("participants") is Array else []
	var p_names: Array = entry.get("participant_names", []).duplicate() if entry.get("participant_names") is Array else []
	if roles_raw != "" and p_ids.is_empty():
		for part in roles_raw.replace("，", "、").replace(",", "、").split("、", false):
			var nm := String(part).strip_edges()
			var cid := resolve_character_id(nm, pname)
			if cid != "":
				if not cid in p_ids: p_ids.append(cid)
				if not Data.name_of(cid) in p_names: p_names.append(Data.name_of(cid))
	var vis := String(entry.get("visibility", "present_only"))
	if sid == "":
		sid = "sum_manual_%d" % _sum_seq
		_sum_seq += 1
	var normalized := {
		"id": sid,
		"branch_id": _last_branch_id,
		"source_msg_id": int(entry.get("source_msg_id", -1)),
		"swipe_idx": int(entry.get("swipe_idx", 0)),
		"game_time": String(entry.get("game_time", player_state.get("current_time", ""))),
		"location": String(entry.get("location", player_state.get("current_location", ""))),
		"participants": p_ids,
		"participant_names": p_names,
		"visibility": vis,
		"visibility_label": "公开传闻" if vis == "world_public" else "在场私密",
		"event": String(entry.get("event", "")).strip_edges(),
		"clues": String(entry.get("clues", "")).strip_edges(),
		"changes": String(entry.get("changes", "")).strip_edges(),
		"manual": true,
	}
	for i in range(timeline_summaries.size()):
		if String(timeline_summaries[i].get("id", "")) == sid:
			timeline_summaries[i] = normalized
			return
	timeline_summaries.append(normalized)

func delete_summary(sum_id: String) -> void:
	timeline_summaries = timeline_summaries.filter(func(s): return String(s.get("id", "")) != sum_id)

func update_character_state(cid: String, patch: Dictionary) -> void:
	_ensure_all_characters()
	if not character_states.has(cid): return
	var st: Dictionary = character_states[cid]
	for k in ["affection", "lewdness", "fetishes", "stage", "lewd_stage", "form", "last_known_location", "relationship_note", "attitude_memo", "met"]:
		if patch.has(k): st[k] = patch[k]
	if patch.has("affection") and not patch.has("stage"):
		st["stage"] = stage_for_affection(float(st["affection"]), bool(st.get("met", true)))
	if patch.has("lewdness") and not patch.has("lewd_stage"):
		st["lewd_stage"] = stage_for_lewdness(float(st["lewdness"]), bool(st.get("met", true)))
	character_states[cid] = st

func unlock_illustration(cg_id: String) -> bool:
	var clean := cg_id.strip_edges()
	if clean == "" or clean in unlocked_illustrations:
		return false
	unlocked_illustrations.append(clean)
	return true

func snapshot() -> Dictionary:
	return {
		"player_state": player_state.duplicate(true),
		"timeline_summaries": timeline_summaries.duplicate(true),
		"character_states": character_states.duplicate(true),
		"character_knowledge_facts": character_knowledge_facts.duplicate(true),
		"bridge_dialogues": bridge_dialogues.duplicate(true),
		"inventory_and_sigils": inventory_and_sigils.duplicate(true),
		"plot_events_and_world_flags": plot_events_and_world_flags.duplicate(true),
		"unlocked_illustrations": unlocked_illustrations.duplicate(),
		"stats": {
			"summaries": timeline_summaries.size(),
			"facts": character_knowledge_facts.size(),
			"characters": character_states.size(),
			"items": inventory_and_sigils.size(),
			"events": plot_events_and_world_flags.size(),
			"illustrations": unlocked_illustrations.size(),
		},
	}

func serialize() -> Dictionary:
	return {
		"format": "sigil-db/1",
		"timeline_summaries": timeline_summaries.duplicate(true),
		"character_states": character_states.duplicate(true),
		"character_knowledge_facts": character_knowledge_facts.duplicate(true),
		"bridge_dialogues": bridge_dialogues.duplicate(true),
		"unlocked_illustrations": unlocked_illustrations.duplicate(),
		"sequences": {"fact": _fact_seq, "sum": _sum_seq, "bridge": _bridge_seq},
	}

func deserialize(data: Dictionary) -> void:
	reset_all()
	if not data is Dictionary or data.is_empty(): return
	if data.get("timeline_summaries") is Array:
		timeline_summaries = data.timeline_summaries.duplicate(true)
	if data.get("character_states") is Dictionary:
		for k in data.character_states.keys():
			if character_states.has(k) and data.character_states[k] is Dictionary:
				for fk in data.character_states[k].keys():
					character_states[k][fk] = data.character_states[k][fk]
	if data.get("character_knowledge_facts") is Array:
		character_knowledge_facts = data.character_knowledge_facts.duplicate(true)
	if data.get("bridge_dialogues") is Dictionary:
		for k in data.bridge_dialogues.keys():
			bridge_dialogues[k] = data.bridge_dialogues[k].duplicate(true)
	if data.get("unlocked_illustrations") is Array:
		for u in data.unlocked_illustrations:
			unlock_illustration(String(u))
	var seq: Dictionary = data.get("sequences", {}) if data.get("sequences") is Dictionary else {}
	_fact_seq = int(seq.get("fact", 1))
	_sum_seq = int(seq.get("sum", 1))
	_bridge_seq = int(seq.get("bridge", 1))
	_ensure_all_characters()
