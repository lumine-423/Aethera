extends RefCounted
## Turns one AI reply (raw text, reply-format/1) into display beats for the Galgame page.
## Rules: 前端设计/03_AI回复格式约定.md. Missing tags fall back to defaults, never break.

const EXPR := {"平静": "neutral", "微笑": "smile", "说话": "speaking", "疑惑": "puzzled", "惊讶": "surprised",
	"害羞": "bashful", "生气": "angry", "难过": "sad", "嫌弃": "disgust", "星星眼": "star-eyes",
	"自信笑": "confident", "自信": "confident"}
## 立绘差分关键词表：中文写法 → 唯一 key（key = assets/characters/<id>/<key>/ 目录名）。
## 11 个 key 覆盖「形态 × 视角 × 姿态」；缺 key 的角色（如只有日常四机位的 8 位）写了解放即视为无效。
## 登记表：data/ui/portrait_diff_index.json（tools/build_portrait_diff_index.py 生成）。
const OUTFIT := {
	# 日常 · 默认机位
	"日常服": "daily", "日常": "daily", "默认": "daily",
	# 日常 · 默认机位·抬手
	"默认抬手": "daily_default_b", "抬手": "daily_default_b",
	# 日常 · 正面
	"正面": "daily_front_a", "正面自然": "daily_front_a",
	"正面手放胸口": "daily_front_b", "手放胸口": "daily_front_b",
	# 日常 · 半侧
	"日常侧面": "daily_side_a", "日常半侧": "daily_side_a", "半侧": "daily_side_a", "半侧腹前双手": "daily_side_a",
	"半侧抬手": "daily_side_b",
	# 休闲
	"休闲服": "casual", "休闲": "casual",
	"休闲扶额": "casual_b", "叉腰扶额": "casual_b",
	# 解放（仅七罪角色）
	"解放形态": "liberate", "解放": "liberate", "变身": "liberate",
	"解放侧面": "liberate_side", "解放半侧": "liberate_side",
	# 裸体
	"裸体": "nude", "全裸": "nude", "原图": "nude", "裸": "nude",
}

static var _re_say: RegEx
static var _re_tag: Dictionary = {}

static func _rx(p: String) -> RegEx:
	var r := RegEx.new(); r.compile(p); return r

static func _tag_group(tags: Array) -> String:
	var escaped: PackedStringArray = []
	for tag in tags:
		var word := String(tag)
		for c in ["\\", ".", "+", "*", "?", "^", "$", "(", ")", "[", "]", "{", "}", "|"]:
			word = word.replace(c, "\\" + c)
		escaped.append(word)
	return "|".join(escaped)

## Shared source with the generated browser rules. Invalid changes keep the previous rules.
static func configure_protocol(config: Dictionary) -> bool:
	if config.get("version") != 1: return false
	var update = config.get("variable_update", {})
	if not update is Dictionary: return false
	var lists := [config.get("hidden_tags"), update.get("tags"), update.get("patch_tags")]
	var has_unwrap := config.has("unwrap_tags")
	var unwrap_tags = config.get("unwrap_tags", [])
	var check_lists := lists.duplicate()
	if has_unwrap: check_lists.append(unwrap_tags)
	var all: Array = []
	var names := _rx("^[\\p{L}_][\\p{L}\\p{N}_.:-]*$")
	var seen := {}
	for tags in check_lists:
		if not tags is Array or tags.is_empty(): return false
		for tag in tags:
			if not tag is String or not names.search(tag) or seen.has(tag.to_lower()): return false
			seen[tag.to_lower()] = true
	for tags in lists:
		all.append_array(tags)
	if not "UpdateVariable" in lists[1] or not "JSONPatch" in lists[2]: return false
	_re_tag.clear()
	_re_say = _rx("^【([^】]+)】\\s*[:：]\\s*(.*)$")
	for t in ["场景", "在场", "选项", "插画", "pose", "choices", "dbNote"]:
		_re_tag[t] = _rx("(?is)<" + t + ">([\\s\\S]*?)</" + t + ">")
	_re_tag["sumUp"] = _rx("(?is)<sumUp(?:\\s[^>]*)?>([\\s\\S]*?)</sumUp\\s*>")
	_re_tag["summary_raw"] = _rx("(?is)<summary(?:\\s[^>]*)?>([\\s\\S]*?)</summary\\s*>")
	_re_tag["details"] = _rx("(?is)<details\\b[^>]*>[\\s\\S]*?</details\\s*>")
	_re_tag["bts_extract"] = _rx("(?is)<BTS(?:\\s[^>]*)?>([\\s\\S]*?)</BTS\\s*>")
	_re_tag["update"] = _rx("(?i)<(" + _tag_group(lists[1]) + ")(?=[\\s/>])[^>]*>([\\s\\S]*?)(</\\1\\s*>|$)")
	# These are protocol/control data, never story beats. Missing closing tags
	# hide the remainder rather than exposing an unfinished reasoning/update block.
	_re_tag["hidden"] = _rx("(?i)<(" + _tag_group(all) + ")(?=[\\s/>])[^>]*>[\\s\\S]*?(?:</\\1\\s*>|$)")
	var stream_tags := all.duplicate()
	for st_tag in ["sumUp", "pose", "choices", "dbNote"]:
		stream_tags.append(st_tag)
	_re_tag["unfinished"] = _rx("(?i)<(?:" + _tag_group(stream_tags) + ")(?=[\\s/>]|$)[^>]*$")
	_re_tag["tail_open"] = _rx("(?is)<(?:sumUp|pose|choices|dbNote|BTS)(?:\\s[^>]*)?>[\\s\\S]*$")
	_re_tag["empty_fence"] = _rx("(?m)^[ \\t]*```(?:xml|json|html|text)?[ \\t]*\\n[ \\t\\n]*```[ \\t]*$")
	if unwrap_tags is Array and not unwrap_tags.is_empty():
		var ug := _tag_group(unwrap_tags)
		_re_tag["unwrap"] = _rx("(?i)</?(" + ug + ")(?=[\\s/>])[^>]*>\\n?|<(?:" + ug + ")(?=[\\s/>]|$)[^>]*$")
	_re_tag["comment"] = _rx("<!--[\\s\\S]*?-->\\n?|<!--[^>]*$")
	_re_tag["magic"] = _rx("<激活魔法>([\\s\\S]*?)</激活魔法>")
	_re_tag["patch"] = _rx("(?i)<(" + _tag_group(lists[2]) + ")(?=[\\s/>])[^>]*>([\\s\\S]*?)</\\1\\s*>")
	_re_tag["selfclose"] = _rx("<[A-Za-z_][A-Za-z0-9_]*\\s*/>")
	return true

static func _ensure() -> bool:
	if _re_say: return true
	var config = JSON.parse_string(FileAccess.get_file_as_string("res://data/reply_protocol.json"))
	if config is Dictionary and configure_protocol(config): return true
	push_error("Invalid reply_protocol.json; refusing to display unfiltered AI text")
	return false

static func _split_npc_speaker(raw_part: String) -> Dictionary:
	const D = preload("res://scripts/ui/ui_data.gd")
	var clean := raw_part.strip_edges()
	if clean == "": return {"name": "", "sil": ""}
	# First check official cast / named NPC directly
	if D.id_of(clean) != "":
		return {"name": clean, "sil": ""}
	# Pattern 1: "[类别]NPC名" or "【类别】NPC名"
	for br in [["[", "]"], ["【", "】"]]:
		if clean.begins_with(br[0]) and br[1] in clean:
			var close_idx := clean.find(br[1])
			var cat_s := clean.substr(1, close_idx - 1).strip_edges()
			var nm_s := clean.substr(close_idx + 1).strip_edges()
			var sk := D.silhouette_key(cat_s)
			if sk != "":
				return {"name": nm_s if nm_s != "" else cat_s, "sil": sk}
	# Pattern 2: "类别:NPC名" / "类别：NPC名" / "类别·NPC名" / "类别/NPC名" / "类别-NPC名"
	for sep in [":", "：", "·", "/", "-"]:
		if sep in clean:
			var bits := clean.split(sep, true, 1)
			var left := bits[0].strip_edges()
			var right := bits[1].strip_edges()
			var sk := D.silhouette_key(left)
			if sk != "":
				return {"name": right if right != "" else left, "sil": sk}
			var sk_r := D.silhouette_key(right)
			if sk_r != "":
				return {"name": left if left != "" else right, "sil": sk_r}
	# Pattern 3: "NPC名(类别)" or "NPC名（类别）"
	for br_open in ["(", "（"]:
		if br_open in clean:
			var bits2 := clean.split(br_open, true, 1)
			var base_nm := bits2[0].strip_edges()
			var tag_s := bits2[1].trim_suffix(")").trim_suffix("）").strip_edges()
			var sk2 := D.silhouette_key(tag_s)
			if sk2 != "":
				return {"name": base_nm if base_nm != "" else tag_s, "sil": sk2}
	# Pattern 4: Direct category word alone (e.g. "老人", "魔物")
	var direct_sk := D.silhouette_key(clean)
	if direct_sk != "":
		return {"name": clean, "sil": direct_sk}
	return {"name": clean, "sil": ""}
static func expr_key(word: String) -> String:
	word = word.strip_edges()
	if EXPR.has(word): return EXPR[word]
	if word in EXPR.values(): return word
	return "speaking"

## Extract key: value or 【key】value fields from structured Hotaru blocks.
static func _extract_kv_fields(block: String, keys: Array) -> Dictionary:
	var res := {}
	var text := block.replace("\r", "").strip_edges()
	if text == "": return res
	var lines := text.split("\n", false)
	var last_key := ""
	for raw_line in lines:
		var line := String(raw_line).strip_edges()
		if line == "": continue
		var matched_key := ""
		var val := ""
		for k in keys:
			var ks := String(k)
			for pfx in ["【" + ks + "】:", "【" + ks + "】：", "【" + ks + "】", ks + ":", ks + "："]:
				if line.begins_with(pfx):
					matched_key = ks
					val = line.substr(pfx.length()).strip_edges()
					break
			if matched_key != "": break
		if matched_key != "":
			res[matched_key] = val
			last_key = matched_key
		elif last_key != "":
			res[last_key] = String(res.get(last_key, "")) + ("\n" if String(res.get(last_key, "")) != "" else "") + line
	return res

static func parse_sum_up_block(block: String) -> Dictionary:
	var clean := block.replace("\r", "").strip_edges()
	if clean == "": return {}
	var kv := _extract_kv_fields(clean, ["时间", "地点", "角色", "在场角色", "可见", "可见范围", "何事", "事件", "线索", "未解线索", "变动", "状态变动"])
	if kv.is_empty():
		return {
			"time": "",
			"location": "",
			"roles_raw": "",
			"role_names": [],
			"visibility": "present_only",
			"visibility_label": "在场私密",
			"event": clean,
			"clues": "",
			"changes": "",
			"raw": clean,
		}
	var time_s := String(kv.get("时间", "")).strip_edges()
	var loc_s := String(kv.get("地点", "")).strip_edges()
	var roles_raw := String(kv.get("角色", kv.get("在场角色", ""))).strip_edges()
	var vis_raw := String(kv.get("可见", kv.get("可见范围", ""))).strip_edges()
	var event_s := String(kv.get("何事", kv.get("事件", ""))).strip_edges()
	var clues_s := String(kv.get("线索", kv.get("未解线索", ""))).strip_edges()
	var changes_s := String(kv.get("变动", kv.get("状态变动", ""))).strip_edges()
	var vis := "world_public" if ("公开" in vis_raw or "传闻" in vis_raw or "世界" in vis_raw or "public" in vis_raw.to_lower()) else "present_only"
	var role_names: Array = []
	if roles_raw != "":
		var norm := roles_raw.replace("，", "、").replace(",", "、").replace("/", "、").replace("；", "、")
		for part in norm.split("、", false):
			var nm := String(part).strip_edges()
			for br in ["(", "（", "[", "【"]:
				if br in nm:
					nm = nm.split(br, true, 1)[0].strip_edges()
			if nm != "" and not nm in role_names:
				role_names.append(nm)
	if event_s == "": event_s = clean
	return {
		"time": time_s,
		"location": loc_s,
		"roles_raw": roles_raw,
		"role_names": role_names,
		"visibility": vis,
		"visibility_label": "公开传闻" if vis == "world_public" else "在场私密",
		"event": event_s,
		"clues": clues_s,
		"changes": changes_s,
		"raw": clean,
	}

static func parse_pose_block(block: String) -> Dictionary:
	var clean := block.replace("\r", "").strip_edges()
	if clean == "": return {}
	var kv := _extract_kv_fields(clean, ["人物", "角色", "姿势", "动作", "状态"])
	return {
		"character": String(kv.get("人物", kv.get("角色", ""))).strip_edges(),
		"pose": String(kv.get("姿势", kv.get("动作", ""))).strip_edges(),
		"state": String(kv.get("状态", "")).strip_edges(),
		"raw": clean,
	}

static func parse_db_note_block(block: String) -> Dictionary:
	var clean := block.replace("\r", "").strip_edges()
	if clean == "": return {}
	var kv := _extract_kv_fields(clean, ["态度", "印象", "记忆", "备忘"])
	return {
		"attitude": String(kv.get("态度", kv.get("印象", ""))).strip_edges(),
		"memory": String(kv.get("记忆", kv.get("备忘", ""))).strip_edges(),
		"raw": clean,
	}

static func _parse_choice_lines(block: String) -> Array:
	var res: Array = []
	for line in block.split("\n", false):
		var s := String(line).strip_edges()
		if s == "": continue
		for lead in ["- ", "-", "・", "· ", "•"]:
			if s.begins_with(lead): s = s.substr(lead.length()).strip_edges(); break
		if s.length() > 2 and s[1] in [".", "、", "．"] and s[0].is_valid_int():
			s = s.substr(2).strip_edges()
		elif s.length() > 3 and s[2] in [".", "、", "．"] and s.substr(0, 2).is_valid_int():
			s = s.substr(3).strip_edges()
		if s != "": res.append(s)
	return res

## user_name replaces {{user}}. Returns {beats, scene, cast, cast_present, options, cg, patch, pending, sum_up, pose, db_note, bts}.
static func parse(raw: String, user_name := "你") -> Dictionary:
	var out := {
		"beats": [], "scene": "", "cast": [], "cast_present": false, "options": [],
		"cg": "", "patch": "", "pending": false,
		"sum_up": {}, "pose": {}, "db_note": {}, "bts": "",
	}
	if not _ensure(): return out
	var text := raw.replace("{{user}}", user_name).replace("\r", "")
	# Extract structured Hotaru tags BEFORE hidden/update stripping so <sumUp> & <BTS> are preserved cleanly.
	var sm_up: RegExMatch = _re_tag["sumUp"].search(text)
	if sm_up:
		out["sum_up"] = parse_sum_up_block(sm_up.get_string(1))
	text = _re_tag["sumUp"].sub(text, "", true)
	var bts_m: RegExMatch = _re_tag["bts_extract"].search(text)
	if bts_m:
		out["bts"] = bts_m.get_string(1).strip_edges()
	text = _re_tag["bts_extract"].sub(text, "", true)
	if out["sum_up"].is_empty():
		var outside_details: String = (_re_tag["details"] as RegEx).sub(text, "", true)
		var sm_old: RegExMatch = _re_tag["summary_raw"].search(outside_details)
		if sm_old:
			out["sum_up"] = parse_sum_up_block(sm_old.get_string(1))
	var up: RegExMatch = _re_tag["update"].search(text)
	if up:
		var p: RegExMatch = _re_tag["patch"].search(up.get_string())
		if p: out.patch = p.get_string(2).strip_edges()
		out.pending = up.get_string(3) == ""
	text = _re_tag["update"].sub(text, "", true)
	text = _re_tag["hidden"].sub(text, "", true)
	text = _re_tag["unfinished"].sub(text, "", true)
	text = _re_tag["empty_fence"].sub(text, "", true)
	text = _re_tag["selfclose"].sub(text, "", true)
	if _re_tag.has("unwrap"): text = _re_tag["unwrap"].sub(text, "", true)
	if _re_tag.has("comment"): text = _re_tag["comment"].sub(text, "", true)   # tavern-only placeholders such as <StatusPlaceHolderImpl/>
	for t in ["场景", "插画"]:
		var m: RegExMatch = _re_tag[t].search(text)
		if m: out["scene" if t == "场景" else "cg"] = m.get_string(1).strip_edges()
		text = _re_tag[t].sub(text, "", true)
	var pm: RegExMatch = _re_tag["pose"].search(text)
	if pm: out["pose"] = parse_pose_block(pm.get_string(1))
	text = _re_tag["pose"].sub(text, "", true)
	var dm: RegExMatch = _re_tag["dbNote"].search(text)
	if dm: out["db_note"] = parse_db_note_block(dm.get_string(1))
	text = _re_tag["dbNote"].sub(text, "", true)
	const D = preload("res://scripts/ui/ui_data.gd")
	var npc_sil_map := {}
	var diff_warn: Array = []
	var cm: RegExMatch = _re_tag["在场"].search(text)
	if cm:
		out.cast_present = true
		for part in cm.get_string(1).replace("，", "、").replace(",", "、").split("、", false):
			var raw_item := part.strip_edges()
			if raw_item == "": continue
			var sp_info := _split_npc_speaker(raw_item)
			var outfit := "daily"
			var sil_id := String(sp_info.get("sil", ""))
			var name := String(sp_info.get("name", ""))
			if sil_id == "":
				for br in ["(", "（"]:
					if br in name:
						var bits := name.split(br, true, 1)
						name = bits[0].strip_edges()
						var raw_form := bits[1].trim_suffix(")").trim_suffix("）").strip_edges()
						var key := String(OUTFIT.get(raw_form, ""))
						var cid := String(D.id_of(name))
						if key == "":
							# 未登记写法：不猜、不借用别的差分，退回角色自身登记过的日常，并记一条对不上账的告警
							outfit = "daily"
							diff_warn.append("%s：未登记的形态「%s」" % [name, raw_form])
						elif cid != "" and not D.has_diff_key(cid, key):
							outfit = "daily"
							diff_warn.append("%s：没有「%s」差分，退回日常" % [name, raw_form])
						else:
							outfit = key
			else:
				# Strip optional trailing outfit paren if AI appended (日常) after sil NPC name
				for br in ["(", "（"]:
					if br in name:
						name = name.split(br, true, 1)[0].strip_edges()
			if sil_id == "" and D.id_of(name) == "" and name != user_name:
				sil_id = D.silhouette_key_fallback(name)
			if sil_id != "" and name != "":
				npc_sil_map[name] = sil_id
			if name != "":
				out.cast.append({"name": name, "outfit": outfit, "sil": sil_id})
	text = _re_tag["在场"].sub(text, "", true)
	var om: RegExMatch = _re_tag["选项"].search(text)
	if om: out.options.append_array(_parse_choice_lines(om.get_string(1)))
	text = _re_tag["选项"].sub(text, "", true)
	var chm: RegExMatch = _re_tag["choices"].search(text)
	if chm: out.options.append_array(_parse_choice_lines(chm.get_string(1)))
	text = _re_tag["choices"].sub(text, "", true)
	if _re_tag.has("tail_open"): text = _re_tag["tail_open"].sub(text, "", true)
	if _re_tag.has("unwrap"): text = _re_tag["unwrap"].sub(text, "", true)
	var magics: Array = []
	for m in _re_tag["magic"].search_all(text): magics.append(m.get_string(1).strip_edges())
	var k := 0
	while _re_tag["magic"].search(text):
		var m2: RegExMatch = _re_tag["magic"].search(text)
		text = text.substr(0, m2.get_start()) + "\n§§MAGIC%d\n" % k + text.substr(m2.get_end()); k += 1
	for line in text.split("\n", false):
		var s := String(line).strip_edges()
		if s == "": continue
		if s.begins_with("§§MAGIC"):
			out.beats.append({"kind": "magic", "speaker": "", "expr": "", "sil": "", "text": magics[int(s.substr(7))]}); continue
		var sm := _re_say.search(s)
		if sm:
			var who := sm.get_string(1).strip_edges(); var ex := "speaking"
			for bar in ["|", "｜"]:
				if bar in who:
					var bits := who.split(bar, true, 1)
					var l_side := bits[0].strip_edges()
					var r_side := bits[1].strip_edges()
					if D.silhouette_key(l_side) != "" and not EXPR.has(r_side) and not (r_side in EXPR.values()):
						who = l_side + ":" + r_side
					else:
						who = l_side; ex = expr_key(r_side)
					break
			var sil_id := ""
			var disp_name := who
			if D.id_of(who) == "" and who != user_name and not (who in ["我", "你", "旁白", "系统"]):
				var sp_d := _split_npc_speaker(who)
				disp_name = String(sp_d.get("name", who))
				sil_id = String(sp_d.get("sil", ""))
				if sil_id == "" and npc_sil_map.has(disp_name):
					sil_id = String(npc_sil_map[disp_name])
				elif sil_id == "":
					sil_id = D.silhouette_key_fallback(disp_name)
				if sil_id != "" and disp_name != "":
					npc_sil_map[disp_name] = sil_id
			out.beats.append({"kind": "say", "speaker": disp_name, "expr": ex, "sil": sil_id, "text": sm.get_string(2).strip_edges()})
		else:
			out.beats.append({"kind": "narr", "speaker": "", "expr": "", "sil": "", "text": s})
	if not diff_warn.is_empty():
		out["diff_warnings"] = diff_warn
	return out

static func _clean_bridge_msg(raw_msg: String, char_name := "") -> String:
	var s := raw_msg.replace("\r", "").strip_edges()
	if s == "": return ""
	var sm := _re_say.search(s) if _re_say != null else null
	if sm:
		s = sm.get_string(2).strip_edges()
	elif char_name != "":
		for pfx in [char_name + ":", char_name + "：", "【" + char_name + "】:", "【" + char_name + "】："]:
			if s.begins_with(pfx):
				s = s.substr(pfx.length()).strip_edges()
				break
	# Strip matching wrapping quotation marks so bubble text reads like direct IM chat
	for pair in [["“", "”"], ["「", "」"], ["『", "』"], ["\"", "\""]]:
		var l: String = pair[0]; var r: String = pair[1]
		if s.begins_with(l) and s.ends_with(r) and s.length() > l.length() + r.length():
			var inner := s.substr(l.length(), s.length() - l.length() - r.length()).strip_edges()
			if not (l in inner and r in inner):
				s = inner
				break
	# Reject standalone stage directions like (*歪头*) or （轻笑一声）
	if (s.begins_with("*") and s.ends_with("*")) or (s.begins_with("（") and s.ends_with("）")) or (s.begins_with("(") and s.ends_with(")")):
		return ""
	return s.strip_edges()

## Parse single-character isolated bridge chat reply (<content><msg>...</msg>...</content><dbNote>...</dbNote>).
## Returns {text: String, messages: Array[String] (1..5 spoken bubbles), db_note: Dictionary}.
static func bridge_plain(raw: String, user_name := "你", char_name := "") -> Dictionary:
	var msgs: Array = []
	if not _ensure():
		var fb := raw.strip_edges()
		if fb != "": msgs.append(fb)
		return {"text": fb, "messages": msgs, "db_note": {}}

	var working := raw.replace("{{user}}", user_name).replace("\r", "")
	var db_note := {}
	var dm: RegExMatch = _re_tag["dbNote"].search(working)
	if dm: db_note = parse_db_note_block(dm.get_string(1))
	working = _re_tag["dbNote"].sub(working, "", true)
	for strip_k in ["sumUp", "bts_extract", "update", "hidden", "unfinished", "tail_open", "pose", "choices", "在场", "场景", "插画", "选项"]:
		if _re_tag.has(strip_k):
			working = _re_tag[strip_k].sub(working, "", true)
	if _re_tag.has("unwrap"): working = _re_tag["unwrap"].sub(working, "", true)
	if _re_tag.has("comment"): working = _re_tag["comment"].sub(working, "", true)

	var msg_rx := _rx("(?is)<msg(?:\\s[^>]*)?>([\\s\\S]*?)</msg\\s*>")
	for mm in msg_rx.search_all(working):
		var c := _clean_bridge_msg(mm.get_string(1), char_name)
		if c != "":
			msgs.append(c)
			if msgs.size() >= 5: break

	if msgs.is_empty():
		var r := parse(raw, user_name)
		if db_note.is_empty(): db_note = r.get("db_note", {})
		var say_only: Array = []
		var other_lines: Array = []
		for b in r.beats:
			if b.kind == "say":
				var who := String(b.speaker).strip_edges()
				if char_name != "" and who != "" and who != char_name and not (char_name in who):
					continue
				var c := _clean_bridge_msg(String(b.text), char_name)
				if c != "": say_only.append(c)
			elif b.kind == "narr":
				var c2 := _clean_bridge_msg(String(b.text), char_name)
				if c2 != "": other_lines.append(c2)
		var picked := say_only if not say_only.is_empty() else other_lines
		for item in picked:
			msgs.append(item)
			if msgs.size() >= 5: break

	return {
		"text": "\n".join(PackedStringArray(msgs)).strip_edges(),
		"messages": msgs,
		"db_note": db_note,
	}

## Plain readable text for the backlog: tags removed, speech kept.
static func plain(raw: String, user_name := "你") -> String:
	var r := parse(raw, user_name)
	var lines: PackedStringArray = []
	for b in r.beats:
		match b.kind:
			"say": lines.append("【%s】：%s" % [b.speaker, b.text])
			"magic": lines.append("〔激活魔法〕" + String(b.text).replace("\n", " "))
			_: lines.append(b.text)
	if not r.options.is_empty(): lines.append("（选项 %d 个）" % r.options.size())
	return "\n".join(lines)
