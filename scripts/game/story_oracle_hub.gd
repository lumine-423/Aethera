extends Node
## In-game Story Oracle (故事神谕) ported from SillyTavern story-oracle v1.84.0:
## - Connects to modded Godot game data channel (Game.stat / Game.messages / GameDatabase / Data.worldbook)
## - Supports all 6 modes: normal, diagnose, worldinfo, advisor, fix, forge
## - Applies edits back to Game / DemoBackend / Worldbook cleanly with 1-click Undo
## - Supports remote GitHub Raw / jsDelivr CDN version checks & live prompt update pulling

const SO_VERSION_DEFAULT := "1.84.0"
const BASE_DIR := "user://story_oracle/"
const SETTINGS_FILE := "settings.json"
const STATE_FILE := "state.json"
const PULLED_FILE := "pulled_prompts.json"

const SO_UPDATE_SOURCES := [
	{"name": "GitHub Raw", "base": "https://raw.githubusercontent.com/namelessone88/story-oracle/main/", "bust": true},
	{"name": "jsDelivr CDN", "base": "https://cdn.jsdelivr.net/gh/namelessone88/story-oracle@main/", "bust": false},
]

const MODES := [
	{"id": "normal", "label": "普通聊天", "icon": "chat", "hint": "戏外聊剧情、查数值与前情伏笔"},
	{"id": "diagnose", "label": "诊断", "icon": "search", "hint": "核对 MVU 变量状态并生成一键修复补丁"},
	{"id": "worldinfo", "label": "世界书", "icon": "book", "hint": "查看世界观条目或直接应用 <LorebookEdit> 修改"},
	{"id": "advisor", "label": "参谋", "icon": "compass", "hint": "构思走向/序列并通过主线引导注入"},
	{"id": "fix", "label": "校正", "icon": "star4", "hint": "润色最新回复（保留原文为旧 Swipe 与结构块）"},
	{"id": "forge", "label": "角色工坊", "icon": "person", "hint": "从零打磨 NPC 世界书 DLC 或主角人设"},
]

const INTENSITIES := {
	"subtle": {"label": "轻柔引导", "caption": "仅轻推方向与线索，由角色自主触发"},
	"normal": {"label": "标准引导", "caption": "平衡推进目标与故事自然演出"},
	"strong": {"label": "强力推进", "caption": "明确推动本回合朝设定目标聚拢"},
}

const BUILTIN_PERSONAS := [
	{"id": "none", "name": "普通（无附加人格）", "voice": ""},
	{"id": "warm", "name": "温和前辈", "voice": "语气温和沉稳、条理清晰，先共情理解再冷静分析。"},
	{"id": "sharp", "name": "毒舌损友", "voice": "像熟悉剧本的毒舌损友，直白敏锐吐槽精准，但不歪曲原文事实。"},
	{"id": "scholar", "name": "学院学者", "voice": "像塞蕾特中央学院的魔导研究员，习惯分点考据、指出因果漏洞。"},
	{"id": "muse", "name": "戏剧策展", "voice": "敏锐捕捉戏剧张力、情感暗线与角色动机，语言简练富画面感。"},
]

const DEFAULT_PROMPTS := {
	"normal": "你是「故事神谕」，一个为正在进行的角色扮演/故事服务的“戏外”分析者。\n下方提供了当前的故事上下文（角色信息、变量状态、数据库总结与最近对话记录）。请基于这些上下文，准确地回答用户关于这个故事的问题。\n\n规则：\n- 你不是故事里的角色。不要进行角色扮演、旁白叙述，也不要续写剧情。\n- 除非用户要求展开细节，否则请简明、直接地回答。\n- 如果某些内容在所提供的上下文中并不存在，请如实说明，不要凭空编造。",
	"diagnose": "你是一个用于《艾瑟拉》角色扮演的 MVU 变量修复助手。玩家的状态由系统追踪应用每一回合发出的 <UpdateVariable> 补丁，有时会出现漏写或数值偏差。\n\n你的任务：\n1. 逐项核对当前 变量状态（stat_data） 与最近剧情是否一致。\n2. 指出确凿存在的数值、物品、好感度/色情值或状态偏差。\n3. 给出最小且保守的 JSONPatch 修正补丁（使用 replace / delta / insert / remove），严格放到回复末尾：\n\n<UpdateVariable>\n<Analysis>对所做修复的简短中文说明</Analysis>\n<JSONPatch>\n[ {\"op\": \"replace\", \"path\": \"/主角组/时间\", \"value\": \"...\"} ]\n</JSONPatch>\n</UpdateVariable>\n\n如果一切准确无需改动，请如实说明并在 JSONPatch 中写 []。",
	"worldinfo": "你是「故事神谕」的世界书管家——专门帮用户阅读、梳理并按要求修改《艾瑟拉》世界书的助手。\n当前要处理的世界书条目放在末尾的〔世界书快照〕中。\n\n一、纯提问时：仅根据快照内容作答，指明条目标题或 uid，不输出修改区块。\n二、明确要求修改世界书时：在回复末尾输出一个或多个 <LorebookEdit> 区块供用户一键应用：\n\n<LorebookEdit>\naction: edit\nuid: 12\ncomment: 条目标题\n<<<content\n（修改后的完整正文）\ncontent>>>\n</LorebookEdit>\n\n也支持 action: patch（配 anchor: 原文 与 <<<replace ... replace>>>，长段可用 开头 || 结尾 区间锚点）、action: append、action: prepend、action: create（配 category/title/keywords/<<<content）及 action: delete。\n正文中不要加 Markdown 标题/粗体装饰，保留原有变量格式与结构。",
	"advisor": "你是「故事神谕」的剧情参谋——戏外剧情顾问。通读当前角色设定、世界观、变量状态与故事发展，帮用户找准未回收伏笔、关系转折与可行剧情走向。\n\n当讨论收敛到 1~3 个可选走向时，输出 <StoryPlan> 区块：\n<StoryPlan>\ntitle: 短标题（4~10字）\ngoal: 单句、结果式、可直接注入主线指导的目标\nseed: 最初显露的轻巧迹象\nwhy: 贴合当前故事与数值的原因\n</StoryPlan>\n\n当讨论收敛为一整段多步相连的长线弧线时，输出 <StorySequence> 区块：\n<StorySequence>\ntitle: 序列标题\nbeat: 第一拍标题\ngoal: 单句目标\nseed: 初始迹象\nwhy: 原因\nbeat: 第二拍标题\ngoal: ……\n</StorySequence>\n\n仅讨论现状时不要硬输出方案区块。",
	"fix": "你是资深中文轻小说与视觉小说编辑。<text_to_transform> 是最新一条故事回复，请严格按用户要求修正文风（如去 AI 味、去除八股说教、润色对白神态、调整详略），要求之外的剧情事实、人物人称和结构化标签尽量逐字保留。\n\n请先用 <fix_think>...</fix_think> 简述修改要点，再把改写后的正文完整放进：\n<FixedReply>\n（修改后的正文）\n</FixedReply>",
	"forge": "你是「故事神谕」的角色工坊访谈师与设计师。协助玩家从零构思、打磨艾瑟拉世界中的原创角色 DLC 或主角个人档案。\n\n收集到足够设定后，先整理简要确认卡：\n<CharBrief>\n姓名: 角色名\n身份: 所属与背景定位\n性格: 性格核心\n</CharBrief>\n\n需要直接输出可写入游戏的成稿时，严格附带：\n<CharDraft>\ntarget: npc\nname: 角色名\noverview: 简介与可解锁形态说明\n<<<archive\n（完整的世界书角色档案正文 / 或人物小传设定）\narchive>>>\n</CharDraft>",
}

const OFFSTAGE_TAIL_NORMAL := "【戏外提醒】以上故事记录为只读引用材料。你是戏外分析者、不是故事中角色，除非用户明确点名要求撰写草稿片段，否则不要擅自续写正文。"
const OFFSTAGE_TAIL_ADVISOR := "【戏外提醒】你是戏外剧情参谋，专注梳理方向并在合适时提供 <StoryPlan> 或 <StorySequence>。"

signal changed
signal reply_completed(mode: String, message: Dictionary)
signal update_status_changed

var base_dir_override := ""
var mock_transport: Callable = Callable()

var installed_version := SO_VERSION_DEFAULT
var latest_version := ""
var update_available := false
var update_checking := false
var update_pulling := false
var update_status_text := "未检查远端版本"
var remote_readme_excerpt := ""
var pulled_prompts: Dictionary = {}

var settings: Dictionary = {
	"conn_mode": "game", # game | custom
	"custom_format": "openai",
	"custom_url": "",
	"custom_model": "",
	"custom_key": "",
	"temperature": 0.7,
	"max_tokens": 2048,
	"context_depth": 12,
	"include_card": true,
	"persona_id": "none",
	"auto_diagnose": false,
	"auto_check_update": true,
	"seq_pulse": true,
	"advisor_intensity": "normal",
	"advisor_depth": 2,
	"float_rect": {"x": 860.0, "y": 130.0, "w": 1000.0, "h": 810.0},
	"fullscreen": false,
	"window_skin": "theme",
	"prompt_overrides": {},
}

var current_mode := "normal"
var chat_history: Array = [] # [{id, mode, role, text, timestamp, applied_actions, undo_id}]
var guidance_plan: Dictionary = {} # {title, goal, seed, why, intensity, adopted_at}
var guidance_seq: Dictionary = {} # {title, current_index, beat_ready, beat_evidence, beats: [{title, goal, seed, why, status, custom_text}]}
var busy := false
var last_debug_prompt := ""
var _active_http: HTTPRequest = null
var _lore_undo_batches: Dictionary = {}
var _msg_seq := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not UiHub.review_mode or base_dir_override != "":
		load_all()

func _dir() -> String:
	var d := base_dir_override if base_dir_override != "" else BASE_DIR
	return d if d.ends_with("/") else (d + "/")

func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir()))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir() + "remote/"))

func _read_json(path: String, fallback):
	if not FileAccess.file_exists(path): return fallback
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed != null else fallback

func _write_json(path: String, data) -> void:
	_ensure_dirs()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()

func load_all() -> void:
	var s = _read_json(_dir() + SETTINGS_FILE, {})
	if s is Dictionary:
		for k in s: settings[k] = s[k]
	var st = _read_json(_dir() + STATE_FILE, {})
	if st is Dictionary:
		if st.get("chat_history") is Array: chat_history = st.chat_history.duplicate(true)
		if st.get("guidance_plan") is Dictionary: guidance_plan = st.guidance_plan.duplicate(true)
		if st.get("guidance_seq") is Dictionary: guidance_seq = st.guidance_seq.duplicate(true)
		_msg_seq = int(st.get("msg_seq", chat_history.size()))
	var pulled = _read_json(_dir() + PULLED_FILE, {})
	if pulled is Dictionary and not pulled.is_empty():
		var pv := String(pulled.get("version", "")).strip_edges()
		if pv != "" and not so_version_newer(SO_VERSION_DEFAULT, pv):
			installed_version = pv
			pulled_prompts = pulled.get("prompts", {}) if pulled.get("prompts") is Dictionary else {}
			remote_readme_excerpt = String(pulled.get("readme_excerpt", ""))
	if settings.get("conn_mode", "") == "":
		settings["conn_mode"] = "game"

func save_settings() -> void:
	if UiHub.review_mode and base_dir_override == "": return
	_write_json(_dir() + SETTINGS_FILE, settings)

func save_state() -> void:
	if UiHub.review_mode and base_dir_override == "": return
	_write_json(_dir() + STATE_FILE, {
		"msg_seq": _msg_seq,
		"chat_history": chat_history,
		"guidance_plan": guidance_plan,
		"guidance_seq": guidance_seq,
	})

func clear_history() -> void:
	chat_history.clear()
	save_state()
	changed.emit()

func set_mode(m: String) -> void:
	for it in MODES:
		if String(it.id) == m:
			current_mode = m
			changed.emit()
			return

func mode_info(m: String) -> Dictionary:
	for it in MODES:
		if String(it.id) == m: return it
	return MODES[0]

func has_active_guidance() -> bool:
	return not guidance_plan.is_empty() or _active_seq_beat_idx() >= 0

# ---------------- Version Compare & GitHub Pull Updater ----------------
static func so_version_newer(remote_ver: String, local_ver: String) -> bool:
	var ra := _ver_tuple(remote_ver)
	var la := _ver_tuple(local_ver)
	for i in range(3):
		if ra[i] > la[i]: return true
		if ra[i] < la[i]: return false
	return false

static func _ver_tuple(v: String) -> Array[int]:
	var clean := v.strip_edges().trim_prefix("v").split("-")[0]
	var parts := clean.split(".")
	var out: Array[int] = [0, 0, 0]
	for i in range(mini(3, parts.size())):
		if parts[i].is_valid_int(): out[i] = int(parts[i])
	return out

func _http_get_text(url: String, cb: Callable) -> void:
	if mock_transport.is_valid():
		var res: Variant = mock_transport.call("GET", url, {})
		if res is Dictionary:
			var sc := int(res.get("status", 200))
			cb.call(sc >= 200 and sc < 300, String(res.get("body", "")), sc)
			return
	var req := HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray):
		req.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
			cb.call(true, body.get_string_from_utf8(), code)
		else:
			cb.call(false, "", code)
	, CONNECT_ONE_SHOT)
	var err := req.request(url, PackedStringArray(["Accept: text/plain, application/json"]), HTTPClient.METHOD_GET)
	if err != OK:
		req.queue_free()
		cb.call(false, "", 0)

func _fetch_with_fallback(rel_path: String, cb: Callable, idx := 0) -> void:
	if idx >= SO_UPDATE_SOURCES.size():
		cb.call(false, "", {})
		return
	var src: Dictionary = SO_UPDATE_SOURCES[idx]
	var url := String(src.base) + rel_path.trim_prefix("/")
	if bool(src.get("bust", false)):
		url += ("&" if "?" in url else "?") + "t=" + str(Time.get_unix_time_from_system())
	_http_get_text(url, func(ok_flag: bool, body_txt: String, _code: int):
		if ok_flag and body_txt.strip_edges() != "":
			cb.call(true, body_txt, src)
		else:
			_fetch_with_fallback(rel_path, cb, idx + 1)
	)

func check_for_updates(cb := Callable()) -> void:
	if update_checking or update_pulling: return
	update_checking = true
	update_status_text = "正在检查远端版本…"
	update_status_changed.emit()
	_fetch_with_fallback("manifest.json", func(ok_flag: bool, raw_txt: String, src: Dictionary):
		update_checking = false
		if not ok_flag:
			update_status_text = "检查失败（无法连接 GitHub / jsDelivr）"
			update_status_changed.emit(); changed.emit()
			if cb.is_valid(): cb.call(false, installed_version, update_status_text)
			return
		var parsed = JSON.parse_string(raw_txt)
		if not parsed is Dictionary or String(parsed.get("version", "")).strip_edges() == "":
			update_status_text = "远端 manifest 格式异常"
			update_status_changed.emit(); changed.emit()
			if cb.is_valid(): cb.call(false, installed_version, update_status_text)
			return
		latest_version = String(parsed.version).strip_edges()
		update_available = so_version_newer(latest_version, installed_version)
		update_status_text = ("发现新版本 v%s（来源：%s）" % [latest_version, String(src.get("name", "GitHub"))]) if update_available else ("已是最新版本 v%s" % installed_version)
		update_status_changed.emit(); changed.emit()
		if cb.is_valid(): cb.call(true, latest_version, update_status_text)
	)

func pull_update(cb := Callable()) -> void:
	if update_pulling: return
	update_pulling = true
	update_status_text = "正在拉取 manifest.json / 提示词规则…"
	update_status_changed.emit()
	_fetch_with_fallback("manifest.json", func(ok_m: bool, man_txt: String, _src: Dictionary):
		if not ok_m:
			update_pulling = false
			update_status_text = "拉取失败：未能下载远端 manifest.json"
			update_status_changed.emit(); changed.emit()
			if cb.is_valid(): cb.call(false, update_status_text)
			return
		var man_d = JSON.parse_string(man_txt)
		var r_ver := String(man_d.get("version", "")).strip_edges() if man_d is Dictionary else ""
		if r_ver == "":
			update_pulling = false
			update_status_text = "远端 manifest 缺少版本号"
			update_status_changed.emit(); changed.emit()
			if cb.is_valid(): cb.call(false, update_status_text)
			return
		_ensure_dirs()
		var fm := FileAccess.open(_dir() + "remote/manifest.json", FileAccess.WRITE)
		if fm: fm.store_string(man_txt); fm.close()
		_fetch_with_fallback("index.js", func(ok_js: bool, js_txt: String, _src2: Dictionary):
			if ok_js and js_txt != "":
				var fj := FileAccess.open(_dir() + "remote/index.js", FileAccess.WRITE)
				if fj: fj.store_string(js_txt); fj.close()
				pulled_prompts = _extract_prompts_from_js(js_txt)
			_fetch_with_fallback("README.md", func(ok_rm: bool, rm_txt: String, _src3: Dictionary):
				if ok_rm and rm_txt != "":
					var fr := FileAccess.open(_dir() + "remote/README.md", FileAccess.WRITE)
					if fr: fr.store_string(rm_txt); fr.close()
					remote_readme_excerpt = rm_txt.substr(0, 1200)
				installed_version = r_ver
				latest_version = r_ver
				update_available = false
				update_pulling = false
				_write_json(_dir() + PULLED_FILE, {
					"version": installed_version,
					"pulled_at": Time.get_datetime_string_from_system(false, true),
					"prompts": pulled_prompts,
					"readme_excerpt": remote_readme_excerpt,
				})
				update_status_text = "已拉取更新至 v%s（提示词模块 %d 项已热更新）" % [installed_version, pulled_prompts.size()]
				update_status_changed.emit(); changed.emit()
				if cb.is_valid(): cb.call(true, update_status_text)
			)
		)
	)

func _extract_prompts_from_js(js_txt: String) -> Dictionary:
	var map := {
		"normal": "DEFAULT_SYSTEM_PROMPT",
		"diagnose": "DIAGNOSE_SYSTEM_PROMPT",
		"worldinfo": "LOREBOOK_SYSTEM_PROMPT",
		"advisor": "ADVISOR_SYSTEM_PROMPT",
		"fix": "FIX_SYSTEM_PROMPT_MANUAL",
	}
	var out := {}
	for k in map:
		var cname: String = map[k]
		var rx := RegEx.new()
		rx.compile("const\\s+" + cname + "\\s*=\\s*`([\\s\\S]*?)`\\s*;")
		var m := rx.search(js_txt)
		if m != null:
			var val := m.get_string(1).strip_edges()
			if val != "": out[k] = val
	return out

func base_prompt_for(m: String) -> String:
	var ovs: Dictionary = settings.get("prompt_overrides", {}) if settings.get("prompt_overrides") is Dictionary else {}
	var custom := String(ovs.get(m, "")).strip_edges()
	if custom != "": return custom
	if pulled_prompts.has(m) and String(pulled_prompts[m]).strip_edges() != "":
		return String(pulled_prompts[m])
	return String(DEFAULT_PROMPTS.get(m, DEFAULT_PROMPTS.normal))

# ---------------- Game Data Channel ----------------
func read_channel_snapshot() -> Dictionary:
	var DataCls = preload("res://scripts/ui/ui_data.gd")
	var wb: Dictionary = DataCls.worldbook()
	var entries: Array = wb.get("entries", []) if wb.get("entries") is Array else []
	var indexed_wb: Array = []
	for i in range(entries.size()):
		if not entries[i] is Dictionary: continue
		var e: Dictionary = entries[i].duplicate()
		e["uid"] = i + 1
		indexed_wb.append(e)
	var known_chars := {}
	for k in Game.known():
		known_chars[k] = Game.known()[k]
	var cur_stat: Dictionary = Game.stat.duplicate(true)
	var active_conn: Dictionary = active_connection_cfg()
	var mod_lbl := String(active_conn.get("model", "")).strip_edges()
	if mod_lbl == "": mod_lbl = "本地预览"
	return {
		"persona": Game.persona.duplicate(true),
		"stat_data": cur_stat,
		"message_count": Game.messages.size(),
		"last_assistant_id": Game.last_assistant_id(),
		"worldbook_entries": indexed_wb,
		"recap_text": String(Game.recap.get("text", "")),
		"timeline_count": Game.db.get("timeline_summaries", []).size() if Game.db.get("timeline_summaries") is Array else 0,
		"known_count": known_chars.size(),
		"conn_label": "%s (%s)" % [String(active_conn.get("profile_name", "未连接")), mod_lbl],
		"guidance_active": has_active_guidance(),
	}

func active_connection_cfg() -> Dictionary:
	if String(settings.get("conn_mode", "game")) == "custom":
		return {
			"source": "custom",
			"profile_name": "故事神谕独立端点",
			"format": String(settings.get("custom_format", "openai")),
			"url": String(settings.get("custom_url", "")).strip_edges(),
			"model": String(settings.get("custom_model", "")).strip_edges(),
			"key": String(settings.get("custom_key", "")).strip_edges(),
			"temperature": float(settings.get("temperature", 0.7)),
			"max_tokens": int(settings.get("max_tokens", 2048)),
		}
	var gc: Dictionary = Game.connection
	var raw_key := ""
	if Game.backend != null and Game.backend.has_method("_conn_cfg"):
		var full_c: Dictionary = Game.backend._conn_cfg()
		raw_key = String(full_c.get("key", ""))
	return {
		"source": "game",
		"profile_name": String(gc.get("profile_name", "跟随游戏 API")),
		"format": String(gc.get("format", "openai")),
		"url": String(gc.get("url", "")).strip_edges(),
		"model": String(gc.get("model", "")).strip_edges(),
		"key": raw_key,
		"temperature": float(settings.get("temperature", 0.7)),
		"max_tokens": int(settings.get("max_tokens", 2048)),
	}

func _has_live_oracle_api() -> bool:
	if OS.has_feature("web") and Game.demo: return false
	if Game.backend != null and bool(Game.backend.get("test_replies_enabled")): return false
	var c := active_connection_cfg()
	return (String(c.url).begins_with("http://") or String(c.url).begins_with("https://")) and String(c.model) != ""

func build_mode_messages(mode: String, user_text: String, wb_filter := "", target_msg_id := -1) -> Array:
	var DataCls = preload("res://scripts/ui/ui_data.gd")
	var Parser = preload("res://scripts/game/reply_parser.gd")
	var sys_parts := PackedStringArray([base_prompt_for(mode)])

	# Persona voice
	var pid := String(settings.get("persona_id", "none"))
	if mode != "diagnose" and mode != "fix" and pid != "none":
		for p in BUILTIN_PERSONAS:
			if String(p.id) == pid and String(p.voice) != "":
				sys_parts.append("=== 说话人格风格 ===\n" + String(p.voice))
				break

	# Advisor current active guidance block
	if mode == "advisor" and has_active_guidance():
		sys_parts.append("=== 当前生效中的剧情引导 ===\n" + active_guidance_summary())

	# Game Card & Hero Persona
	if bool(settings.get("include_card", true)):
		var hero_lines := PackedStringArray([
			"主角姓名：%s｜种族：%s｜出身：%s" % [String(Game.persona.get("name", "你")), String(Game.persona.get("race", "未定")), String(Game.persona.get("origin", ""))]
		])
		if String(Game.persona.get("bio", "")) != "":
			hero_lines.append("主角背景：" + String(Game.persona.bio))
		sys_parts.append("=== 当前角色 / 玩家档案 ===\n" + "\n".join(hero_lines))

	# Stat data snapshot (from Data Channel)
	sys_parts.append("=== 当前变量状态（stat_data —— 游戏权威实时数值）===\n" + JSON.stringify(Game.stat, "\t"))

	# Mode-specific context blocks
	var wb: Dictionary = DataCls.worldbook()
	var entries: Array = wb.get("entries", []) if wb.get("entries") is Array else []
	if mode == "diagnose":
		var rule_lines := PackedStringArray()
		for i in range(entries.size()):
			var e = entries[i]
			if not e is Dictionary: continue
			var t := String(e.get("title", ""))
			if t.begins_with("[mvu") or bool(e.get("_workshop", false)) or t in ["规则 · 世界叙述指南"]:
				rule_lines.append("[uid:%d] %s：%s" % [i + 1, t, String(e.get("body", "")).substr(0, 600)])
		sys_parts.append("=== MVU 变量规则与更新说明 ===\n" + "\n\n".join(rule_lines))
		var last_id := target_msg_id if target_msg_id >= 0 else Game.last_assistant_id()
		var last_m := Game.message(last_id)
		if not last_m.is_empty():
			var last_txt := Game.text_of(last_m)
			var parsed: Dictionary = Parser.parse(last_txt)
			if String(parsed.get("patch", "")) != "":
				sys_parts.append("=== 最新更新区块（<UpdateVariable> JSONPatch）===\n" + String(parsed.patch))
			sys_parts.append("=== 最新一条 AI 回复正文 ===\n" + last_txt)
	elif mode == "worldinfo":
		var snap := PackedStringArray(["〔世界书快照 · 共 %d 条（仅列匹配或摘要前 40 条）〕" % entries.size()])
		var q := wb_filter.strip_edges().to_lower()
		var shown := 0
		for i in range(entries.size()):
			var e = entries[i]
			if not e is Dictionary: continue
			var t := String(e.get("title", ""))
			var cat := String(e.get("category", ""))
			var body := String(e.get("body", ""))
			if q != "" and not (t.to_lower().contains(q) or cat.to_lower().contains(q) or body.to_lower().contains(q)):
				continue
			snap.append("---\nuid: %d\ncategory: %s\ntitle: %s\nconstant: %s\ncontent:\n%s" % [i + 1, cat, t, str(bool(e.get("constant", false))), body])
			shown += 1
			if shown >= 40: break
		sys_parts.append("\n".join(snap))
	elif mode == "fix":
		var mid := target_msg_id if target_msg_id >= 0 else Game.last_assistant_id()
		var target_m := Game.message(mid)
		var prose := Game.text_of(target_m) if not target_m.is_empty() else ""
		sys_parts.append("=== <text_to_transform>（待校正回复原文）===\n<text_to_transform>\n%s\n</text_to_transform>" % prose)
	else:
		# Summarize constant / custom workshop worldbook lore + recap + DB timeline
		var lore_lines := PackedStringArray()
		for e in entries:
			if not e is Dictionary: continue
			if bool(e.get("constant", false)) or bool(e.get("_workshop", false)):
				lore_lines.append("[%s] %s" % [String(e.get("title", "")), String(e.get("body", "")).substr(0, 400)])
		if not lore_lines.is_empty():
			sys_parts.append("=== 核心世界书与扩展设定 ===\n" + "\n\n".join(lore_lines))
		var rtxt := String(Game.recap.get("text", "")).strip_edges()
		if rtxt != "":
			sys_parts.append("=== 阶段大总结 ===\n" + rtxt)
		var sums: Array = Game.db.get("timeline_summaries", []) if Game.db.get("timeline_summaries") is Array else []
		if not sums.is_empty():
			var sl := PackedStringArray()
			for idx in range(maxi(0, sums.size() - 8), sums.size()):
				var su: Dictionary = sums[idx]
				sl.append("- [%s｜%s] %s" % [String(su.get("game_time", "")), String(su.get("location", "")), String(su.get("event", ""))])
			sys_parts.append("=== 游戏数据库时间线小总结 ===\n" + "\n".join(sl))

	# Transcript envelope
	var depth := int(settings.get("context_depth", 12))
	if mode == "advisor": depth = -1 # advisor inspects full chat history
	var transcript_lines := PackedStringArray()
	var msgs := Game.messages
	var start := 0 if depth < 0 else maxi(0, msgs.size() - depth)
	for i in range(start, msgs.size()):
		var m = msgs[i]
		if not m is Dictionary: continue
		var who := String(m.get("name", "玩家" if String(m.get("role", "")) == "user" else "艾瑟拉"))
		var txt := Game.text_of(m)
		if mode != "diagnose":
			txt = _strip_mechanism_blocks(txt)
		if txt.strip_edges() != "":
			transcript_lines.append("%s: %s" % [who, txt])
	if not transcript_lines.is_empty():
		sys_parts.append("=== 故事对话记录（只读引用材料）===\n<story_transcript>\n%s\n</story_transcript>" % "\n\n".join(transcript_lines))
		if mode == "normal": sys_parts.append(OFFSTAGE_TAIL_NORMAL)
		elif mode == "advisor": sys_parts.append(OFFSTAGE_TAIL_ADVISOR)

	var sys_final := "\n\n".join(sys_parts)
	last_debug_prompt = sys_final
	var api_msgs: Array = [{"role": "system", "content": sys_final}]
	for hm in chat_history:
		if hm is Dictionary and String(hm.get("mode", "")) == mode:
			api_msgs.append({"role": "assistant" if String(hm.role) == "assistant" else "user", "content": String(hm.text)})
	api_msgs.append({"role": "user", "content": user_text})
	return api_msgs

static func _strip_mechanism_blocks(raw: String) -> String:
	var s := raw
	for tag in ["UpdateVariable", "details", "StatusPlaceHolderImpl"]:
		var rx := RegEx.new()
		rx.compile("(?is)<" + tag + "(?:\\s[^>]*)?(?:/>|>[\\s\\S]*?</" + tag + "\\s*>)")
		s = rx.sub(s, "", true)
	return s.strip_edges()

func send_oracle_message(mode: String, user_text: String, cb := Callable(), wb_filter := "") -> void:
	var clean := user_text.strip_edges()
	if clean == "" or busy: return
	current_mode = mode
	_append_msg(mode, "user", clean)
	var api_msgs := build_mode_messages(mode, clean, wb_filter)
	if mock_transport.is_valid():
		var res: Variant = mock_transport.call("CHAT", mode, {"messages": api_msgs, "user_text": clean})
		if res is Dictionary:
			var reply_txt := String(res.get("reply", ""))
			var mrec := _append_msg(mode, "assistant", reply_txt)
			reply_completed.emit(mode, mrec)
			if cb.is_valid(): cb.call(true, mrec)
			return
	if not _has_live_oracle_api():
		var demo_reply := _offline_demo_reply(mode, clean)
		var mrec := _append_msg(mode, "assistant", demo_reply)
		reply_completed.emit(mode, mrec)
		if cb.is_valid(): cb.call(true, mrec)
		return
	busy = true
	changed.emit()
	_post_llm(api_msgs, func(ok_flag: bool, reply_txt: String):
		busy = false
		if ok_flag and reply_txt.strip_edges() != "":
			var mrec := _append_msg(mode, "assistant", reply_txt.strip_edges())
			reply_completed.emit(mode, mrec)
			changed.emit()
			if cb.is_valid(): cb.call(true, mrec)
		else:
			var err_rec := _append_msg(mode, "assistant", "请求失败：" + reply_txt + "\n可在右上角连接设置确认 API 地址、密钥和模型名称。")
			changed.emit()
			if cb.is_valid(): cb.call(false, err_rec)
	)

func _append_msg(mode: String, role: String, txt: String) -> Dictionary:
	_msg_seq += 1
	var actions := detect_actions_in_reply(mode, txt) if role == "assistant" else {}
	var rec := {
		"id": _msg_seq,
		"mode": mode,
		"role": role,
		"text": txt,
		"time": Time.get_time_string_from_system(false),
		"actions": actions,
		"applied": false,
		"undo_ref": "",
	}
	chat_history.append(rec)
	save_state()
	changed.emit()
	return rec

func _post_llm(messages: Array, on_done: Callable) -> void:
	var c := active_connection_cfg()
	var fmt := String(c.get("format", "openai")).to_lower()
	var base: String = String(c.get("url", "")).trim_suffix("/")
	var temp := float(c.get("temperature", 0.7))
	var headers := PackedStringArray(["Content-Type: application/json"])
	var endpoint := ""
	var payload := {}
	var sys_parts := PackedStringArray()
	var non_sys: Array = []
	for msg in messages:
		if not msg is Dictionary: continue
		if String(msg.get("role", "")) == "system":
			if String(msg.get("content", "")) != "": sys_parts.append(String(msg.content))
		else:
			non_sys.append({"role": String(msg.get("role", "user")), "content": String(msg.get("content", ""))})
	if fmt == "claude":
		endpoint = base if base.ends_with("/messages") else (base + "/messages" if base.ends_with("/v1") else base + "/v1/messages")
		headers.append("anthropic-version: 2023-06-01")
		if c.key != "": headers.append("x-api-key: " + c.key)
		payload = {"model": c.model, "max_tokens": int(c.max_tokens), "system": "\n\n".join(sys_parts), "messages": non_sys, "temperature": temp}
	elif fmt == "google":
		var api_root := base if ("/v1" in base) else (base + "/v1beta")
		endpoint = base if ":generateContent" in base else ("%s/models/%s:generateContent?key=%s" % [api_root, String(c.model).uri_encode(), String(c.key).uri_encode()])
		var g_contents: Array = []
		for it in non_sys:
			g_contents.append({"role": "model" if String(it.role) == "assistant" else "user", "parts": [{"text": String(it.content)}]})
		payload = {"systemInstruction": {"parts": [{"text": "\n\n".join(sys_parts)}]}, "contents": g_contents, "generationConfig": {"temperature": temp}}
	else:
		endpoint = base if base.ends_with("/chat/completions") else (base + "/chat/completions")
		if c.key != "": headers.append("Authorization: Bearer " + c.key)
		payload = {"model": c.model, "messages": messages, "temperature": temp, "stream": false}
	var req := HTTPRequest.new()
	req.timeout = 90.0
	add_child(req)
	_active_http = req
	req.request_completed.connect(func(result: int, code: int, _hdrs: PackedStringArray, body: PackedByteArray):
		_active_http = null
		req.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			on_done.call(false, "HTTP %d (result %d)" % [code, result])
			return
		var parsed = JSON.parse_string(body.get_string_from_utf8())
		if fmt == "claude" and parsed is Dictionary and parsed.get("content") is Array:
			var parts := PackedStringArray()
			for blk in parsed.content:
				if blk is Dictionary and blk.has("text"): parts.append(String(blk.text))
			on_done.call(true, "\n".join(parts))
		elif fmt == "google" and parsed is Dictionary and parsed.get("candidates") is Array and not parsed.candidates.is_empty():
			var out_g := PackedStringArray()
			for pt in parsed.candidates[0].get("content", {}).get("parts", []):
				if pt is Dictionary and pt.has("text"): out_g.append(String(pt.text))
			on_done.call(true, "\n".join(out_g))
		elif parsed is Dictionary and parsed.get("choices") is Array and not parsed.choices.is_empty():
			var ch: Dictionary = parsed.choices[0]
			on_done.call(true, String(ch.get("message", {}).get("content", ch.get("text", ""))))
		else:
			on_done.call(false, "响应格式无法解析")
	, CONNECT_ONE_SHOT)
	var err := req.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_active_http = null
		req.queue_free()
		on_done.call(false, "请求发起失败 (err %d)" % err)

func stop_request() -> void:
	if is_instance_valid(_active_http):
		_active_http.cancel_request()
		_active_http.queue_free()
		_active_http = null
	busy = false
	changed.emit()

func _offline_demo_reply(mode: String, user_text: String) -> String:
	var h: Dictionary = Game.hero()
	var loc := String(h.get("当前地点", "未展开"))
	var tm := String(h.get("时间", "—"))
	var known := Game.known()
	match mode:
		"diagnose":
			return "（未连接真实 AI，当前为数据通道本地自检）已读取到 %d 名已解锁角色、当前地点「%s」、时间「%s」。\n示例修复补丁（可直接点下方应用测试写入通路）：\n<UpdateVariable>\n<Analysis>校准当前时间或状态示例</Analysis>\n<JSONPatch>\n[{\"op\": \"replace\", \"path\": \"/主角组/时间\", \"value\": \"%s\"}]\n</JSONPatch>\n</UpdateVariable>" % [known.size(), loc, tm, tm]
		"worldinfo":
			var DataCls = preload("res://scripts/ui/ui_data.gd")
			var cnt := (DataCls.worldbook().get("entries", []) as Array).size()
			return "（本地数据通道预览）当前已读取完整世界书共 %d 条（含工坊 DLC 与自定义修改）。接通 API 后即可用自然语言直接修改或新增设定条目。" % cnt
		"advisor":
			return "已读取目前 %d 条主线楼层与 %d 条角色关系，当前舞台位于「%s」。以下给出两个可立即一键注入主线的引导方案参考：\n<StoryPlan>\ntitle: 暗涌中的学院试探\ngoal: 在不揭破彼此底牌的前提下，触发与在场角色关于旧日契约的关键试探对话\nseed: 一页边缘焦黑却仍保留微弱魔力反应的借阅单滑落桌面\nwhy: 顺应「%s」当前氛围，自然推进信任或试探张力\n</StoryPlan>" % [Game.messages.size(), known.size(), loc, user_text.substr(0, 20)]
		"fix":
			var last_m := Game.message(Game.last_assistant_id())
			var orig := Game.text_of(last_m) if not last_m.is_empty() else "（当前没有可校正的剧情回复）"
			return "<fix_think>未连接真实 AI，此处演示校正结构保留与 Swipe 写回通道。</fix_think>\n<FixedReply>\n%s\n</FixedReply>" % orig
		"forge":
			return "（本地工坊模式已就绪）随时说出角色概念，接通真实 AI 后会自动产出 `<CharDraft>` 并一键写入世界书 DLC 或主角个人档案。\n<CharBrief>\n姓名: 示例访客\n身份: 塞蕾特游学记录员\n性格: 温和敏锐、记性极佳\n</CharBrief>"
		_:
			return "已通过故事神谕数据通道读取实时状态（地点：%s · 已解锁同伴：%d 人 · 主线楼层：%d 条）。你在问：「%s」——在设置或主连接配置好真实 AI API 后即可直接展开分析。" % [loc, known.size(), Game.messages.size(), user_text.substr(0, 40)]

# ---------------- Action Parsers & Game Writeback Channels ----------------
func detect_actions_in_reply(mode: String, txt: String) -> Dictionary:
	var out := {}
	if mode == "diagnose" or ("<JSONPatch" in txt and "<UpdateVariable" in txt):
		var ops := parse_diagnose_patches(txt)
		if not ops.is_empty(): out["patch_ops"] = ops
	if "<LorebookEdit" in txt:
		var lbs := parse_lorebook_blocks(txt)
		if not lbs.is_empty(): out["lore_ops"] = lbs
	var plans := parse_story_plans(txt)
	if not plans.is_empty(): out["plans"] = plans
	var seqs := parse_story_sequences(txt)
	if not seqs.is_empty(): out["sequences"] = seqs
	var fixed := parse_fixed_reply(txt)
	if fixed != "": out["fixed_reply"] = fixed
	var draft := parse_char_draft(txt)
	if not draft.is_empty(): out["char_draft"] = draft
	return out

static func parse_diagnose_patches(text: String) -> Array:
	var rx := RegEx.new()
	rx.compile("(?is)<JSONPatch\\s*>([\\s\\S]*?)(?:</JSONPatch\\s*>|</UpdateVariable\\s*>|$)")
	var m := rx.search(text)
	if m == null: return []
	var body := m.get_string(1).strip_edges()
	var fence_rx := RegEx.new()
	fence_rx.compile("(?is)^```(?:json)?\\s*|\\s*```$")
	body = fence_rx.sub(body, "", true).strip_edges()
	if body.begins_with("[") and not body.ends_with("]"):
		body += "]"
	var parsed = JSON.parse_string(body)
	if not parsed is Array: return []
	var clean: Array = []
	for raw_op in parsed:
		if not raw_op is Dictionary: continue
		var op: Dictionary = (raw_op as Dictionary).duplicate(true)
		var verb := String(op.get("op", "")).to_lower().strip_edges()
		if verb in ["set", "update", "修改"]: verb = "replace"
		elif verb in ["add", "新增"]: verb = "insert"
		elif verb in ["delete", "del", "删除"]: verb = "remove"
		op["op"] = verb
		var path_s := String(op.get("path", "")).strip_edges().trim_suffix("/")
		if path_s.begins_with("/stat_data/") and not Game.stat.has("stat_data"):
			path_s = path_s.trim_prefix("/stat_data")
		if not path_s.begins_with("/"): path_s = "/" + path_s
		op["path"] = path_s
		if verb == "delta" and op.get("value") is String:
			var vs := String(op.value).strip_edges()
			if vs.is_valid_float(): op["value"] = float(vs)
		clean.append(op)
	return clean

func apply_message_diagnose(msg_rec_id: int) -> Dictionary:
	var rec := _find_msg(msg_rec_id)
	if rec.is_empty(): return {"ok": false, "error": "消息不存在"}
	var ops: Array = rec.get("actions", {}).get("patch_ops", [])
	if ops.is_empty(): return {"ok": false, "error": "没有可应用的诊断补丁"}
	var patch_id: String = Game.oracle_apply_stat_patch(ops, "故事神谕诊断 #%d" % msg_rec_id)
	if patch_id == "": return {"ok": false, "error": "应用补丁失败（请检查当前游戏是否已开启）"}
	rec["applied"] = true
	rec["undo_ref"] = patch_id
	save_state(); changed.emit()
	return {"ok": true, "count": ops.size(), "undo_id": patch_id}

func undo_message_action(msg_rec_id: int) -> Dictionary:
	var rec := _find_msg(msg_rec_id)
	if rec.is_empty() or not bool(rec.get("applied", false)):
		return {"ok": false, "error": "没有可撤销的应用记录"}
	var uref := String(rec.get("undo_ref", ""))
	if uref.begins_with("lore:"):
		var ok_l := undo_lorebook_batch(uref)
		if ok_l:
			rec["applied"] = false; rec["undo_ref"] = ""
			save_state(); changed.emit()
			return {"ok": true}
	elif uref.begins_with("swipe:"):
		var parts := uref.split(":")
		if parts.size() >= 3:
			var mid := int(parts[1]); var old_idx := int(parts[2])
			Game.set_swipe(mid, old_idx)
			rec["applied"] = false; rec["undo_ref"] = ""
			save_state(); changed.emit()
			return {"ok": true}
	else:
		if Game.oracle_undo_stat_patch(uref):
			rec["applied"] = false; rec["undo_ref"] = ""
			save_state(); changed.emit()
			return {"ok": true}
	return {"ok": false, "error": "撤销失败"}

static func parse_lorebook_blocks(text: String) -> Array:
	var out: Array = []
	var rx := RegEx.new()
	rx.compile("(?is)<LorebookEdit>([\\s\\S]*?)</LorebookEdit>")
	for hit in rx.search_all(text):
		var op := _parse_one_lorebook_block(hit.get_string(1))
		if not op.is_empty(): out.append(op)
	return out

static func _parse_one_lorebook_block(inner: String) -> Dictionary:
	var txt := inner
	var c_body := ""
	var r_body := ""
	var has_c := false
	var has_r := false
	var crx := RegEx.new(); crx.compile("(?s)<<<content\\r?\\n?([\\s\\S]*?)content>>>")
	var cm := crx.search(txt)
	if cm != null:
		has_c = true; c_body = cm.get_string(1).trim_suffix("\n").trim_suffix("\r")
		txt = txt.substr(0, cm.get_start()) + "\n" + txt.substr(cm.get_end())
	var rrx := RegEx.new(); rrx.compile("(?s)<<<replace\\r?\\n?([\\s\\S]*?)replace>>>")
	var rm := rrx.search(txt)
	if rm != null:
		has_r = true; r_body = rm.get_string(1).trim_suffix("\n").trim_suffix("\r")
		txt = txt.substr(0, rm.get_start()) + "\n" + txt.substr(rm.get_end())

	var headers := {}
	var absorb := ""
	var kv_rx := RegEx.new(); kv_rx.compile("^([A-Za-z_]+)\\s*[:：]\\s*(.*)$")
	for raw_line in txt.split("\n"):
		var line := raw_line.strip_edges()
		var mm := kv_rx.search(line)
		if mm != null:
			var k := mm.get_string(1)
			headers[k] = mm.get_string(2)
			absorb = "anchor" if k == "anchor" else ""
			continue
		if line == "":
			if absorb != "anchor": absorb = ""
			continue
		if absorb != "":
			headers[absorb] = String(headers.get(absorb, "")) + "\n" + line

	var action := String(headers.get("action", "")).strip_edges().to_lower()
	if not (action in ["create", "edit", "patch", "delete", "prepend", "append"]):
		return {}
	return {
		"action": action,
		"uid": int(String(headers.get("uid", "0")).strip_edges()) if String(headers.get("uid", "")).strip_edges().is_valid_int() else 0,
		"title": String(headers.get("title", headers.get("comment", ""))).strip_edges(),
		"category": String(headers.get("category", headers.get("book", "创意工坊DLC"))).strip_edges(),
		"key": String(headers.get("key", "")).strip_edges(),
		"constant": String(headers.get("constant", "")).strip_edges(),
		"anchor": String(headers.get("anchor", "")),
		"has_content": has_c,
		"content": c_body,
		"has_replace": has_r,
		"replace": r_body,
	}

func apply_message_lorebook(msg_rec_id: int) -> Dictionary:
	var rec := _find_msg(msg_rec_id)
	if rec.is_empty(): return {"ok": false, "error": "消息不存在"}
	var ops: Array = rec.get("actions", {}).get("lore_ops", [])
	if ops.is_empty(): return {"ok": false, "error": "没有世界书修改块"}
	var DataCls = preload("res://scripts/ui/ui_data.gd")
	var wb: Dictionary = DataCls.worldbook()
	var entries: Array = wb.get("entries", []) if wb.get("entries") is Array else []
	var custom_list: Array = DataCls.custom_worldbook_entries().duplicate(true)
	var batch_id := "lore_%d" % msg_rec_id
	var undo_log := {"native": {}, "custom_prev": custom_list.duplicate(true)}
	var applied_cnt := 0

	for raw_op in ops:
		if not raw_op is Dictionary: continue
		var op: Dictionary = raw_op
		var act := String(op.get("action", ""))
		var uid := int(op.get("uid", 0))
		var target_entry: Dictionary = {}
		if uid > 0 and uid <= entries.size() and entries[uid - 1] is Dictionary:
			target_entry = entries[uid - 1]
		elif String(op.get("title", "")) != "":
			for e in entries:
				if e is Dictionary and String(e.get("title", "")) == String(op.get("title", "")):
					target_entry = e; break

		if act == "create":
			var new_t := String(op.get("title", ""))
			if new_t == "": new_t = "神谕新增条目_%d" % (custom_list.size() + 1)
			var is_const := String(op.get("constant", "")) == "true" or String(op.get("key", "")) == ""
			var kw_arr: Array = []
			if String(op.get("key", "")) != "":
				for k in String(op.get("key", "")).split(","):
					if k.strip_edges() != "": kw_arr.append(k.strip_edges())
			custom_list.append({
				"id": "oracle_wb_%d_%d" % [Time.get_unix_time_from_system(), custom_list.size() + 1],
				"title": new_t,
				"category": String(op.get("category", "创意工坊DLC")) if String(op.get("category", "")) != "" else "创意工坊DLC",
				"path": "story_oracle",
				"summary": String(op.get("content", "")).substr(0, 100),
				"body": String(op.get("content", "")),
				"constant": is_const,
				"keywords": kw_arr,
				"_workshop": true,
				"_oracle": true,
			})
			applied_cnt += 1
			continue

		if target_entry.is_empty(): continue
		var orig_title := String(target_entry.get("title", ""))
		var cur_body := String(target_entry.get("body", ""))
		var next_body := cur_body
		if act == "edit":
			if bool(op.get("has_content", false)): next_body = String(op.get("content", ""))
		elif act == "append":
			next_body = cur_body + String(op.get("content", ""))
		elif act == "prepend":
			next_body = String(op.get("content", "")) + cur_body
		elif act == "patch":
			var anc := String(op.get("anchor", ""))
			var rep := String(op.get("replace", ""))
			if " || " in anc:
				var segs := anc.split(" || ", false, 1)
				var i0 := cur_body.find(segs[0])
				var i1 := cur_body.find(segs[1], i0 + segs[0].length()) if i0 >= 0 else -1
				if i0 >= 0 and i1 >= 0:
					next_body = cur_body.substr(0, i0) + rep + cur_body.substr(i1 + segs[1].length())
				else:
					continue
			elif anc != "" and anc in cur_body:
				var pos := cur_body.find(anc)
				next_body = cur_body.substr(0, pos) + rep + cur_body.substr(pos + anc.length())
			else:
				continue
		elif act == "delete":
			if bool(target_entry.get("_oracle", false)) or bool(target_entry.get("_workshop", false)):
				custom_list = custom_list.filter(func(ce): return not (ce is Dictionary and String(ce.get("title", "")) == orig_title))
				applied_cnt += 1
			continue

		if bool(target_entry.get("_oracle", false)):
			for idx in range(custom_list.size()):
				if custom_list[idx] is Dictionary and String(custom_list[idx].get("title", "")) == orig_title:
					var upd: Dictionary = custom_list[idx].duplicate()
					upd["body"] = next_body
					if String(op.get("title", "")) != "": upd["title"] = String(op.get("title", ""))
					custom_list[idx] = upd
					applied_cnt += 1; break
		else:
			if not undo_log["native"].has(orig_title):
				undo_log["native"][orig_title] = DataCls.worldbook_override_for(orig_title).duplicate()
			var ov_patch := {"body": next_body}
			if String(op.get("title", "")) != "" and act == "edit":
				ov_patch["title"] = String(op.get("title", ""))
			DataCls.save_worldbook_override(orig_title, ov_patch)
			applied_cnt += 1

	DataCls.save_custom_worldbook_entries(custom_list)
	if applied_cnt > 0:
		_lore_undo_batches[batch_id] = undo_log
		rec["applied"] = true
		rec["undo_ref"] = "lore:" + batch_id
		save_state(); changed.emit()
		return {"ok": true, "count": applied_cnt}
	return {"ok": false, "error": "未能定位需要修改的条目（请检查 uid 或 anchor）"}

func undo_lorebook_batch(uref: String) -> bool:
	var bid := uref.trim_prefix("lore:")
	if not _lore_undo_batches.has(bid): return false
	var log: Dictionary = _lore_undo_batches[bid]
	var DataCls = preload("res://scripts/ui/ui_data.gd")
	DataCls.save_custom_worldbook_entries(log.get("custom_prev", []))
	var nat: Dictionary = log.get("native", {})
	for t in nat:
		var prev = nat[t]
		if prev is Dictionary and prev.is_empty():
			DataCls.reset_worldbook_override(String(t))
		elif prev is Dictionary:
			DataCls.save_worldbook_override(String(t), prev)
	_lore_undo_batches.erase(bid)
	return true

# ---------------- Advisor Plans & Sequences ----------------
static func parse_story_plans(text: String) -> Array:
	var out: Array = []
	var rx := RegEx.new()
	rx.compile("(?is)<Story[_-]?Plan>([\\s\\S]*?)(?:</Story[_-]?Plan>|$)")
	for hit in rx.search_all(text):
		var inner := hit.get_string(1)
		var g := _kv_pick(inner, ["goal", "目标"])
		if g == "": continue
		out.append({
			"title": _kv_pick(inner, ["title", "标题", "方案"]),
			"goal": g,
			"seed": _kv_pick(inner, ["seed", "起始迹象", "种子"]),
			"why": _kv_pick(inner, ["why", "契合点", "理由"]),
		})
	return out

static func parse_story_sequences(text: String) -> Array:
	var out: Array = []
	var rx := RegEx.new()
	rx.compile("(?is)<Story[_-]?Sequence>([\\s\\S]*?)(?:</Story[_-]?Sequence>|$)")
	for hit in rx.search_all(text):
		var inner := hit.get_string(1)
		var title := ""
		var beats: Array = []
		var cur: Dictionary = {}
		for line in inner.split("\n"):
			var bo := _kv_pick(line, ["beat", "拍"])
			if bo != "":
				cur = {"title": bo, "goal": "", "seed": "", "why": "", "status": "pending", "custom_text": ""}
				beats.append(cur); continue
			var tt := _kv_pick(line, ["title", "标题"])
			if tt != "" and cur.is_empty() and title == "":
				title = tt; continue
			if cur.is_empty(): continue
			var g := _kv_pick(line, ["goal", "目标"])
			if g != "": cur["goal"] = g; continue
			var s := _kv_pick(line, ["seed", "起始迹象", "种子"])
			if s != "": cur["seed"] = s; continue
			var w := _kv_pick(line, ["why", "契合点", "理由"])
			if w != "": cur["why"] = w; continue
		var valid: Array = []
		for b in beats:
			if String(b.get("goal", "")) != "": valid.append(b)
		if not valid.is_empty():
			out.append({"title": title, "beats": valid})
	return out

static func _kv_pick(blob: String, keys: Array) -> String:
	for k in keys:
		var rx := RegEx.new()
		rx.compile("(?im)^\\s*" + String(k) + "\\s*[:：]\\s*(.+)$")
		var m := rx.search(blob)
		if m != null and m.get_string(1).strip_edges() != "":
			return m.get_string(1).strip_edges()
	return ""

func adopt_story_plan(plan: Dictionary, intensity := "") -> void:
	guidance_seq = {}
	guidance_plan = plan.duplicate(true)
	guidance_plan["intensity"] = intensity if intensity != "" else String(settings.get("advisor_intensity", "normal"))
	guidance_plan["adopted_at"] = Game.messages.size()
	save_state(); changed.emit()

func adopt_story_sequence(seq: Dictionary) -> void:
	guidance_plan = {}
	guidance_seq = seq.duplicate(true)
	var beats: Array = guidance_seq.get("beats", [])
	for i in range(beats.size()):
		if beats[i] is Dictionary:
			beats[i]["status"] = "active" if i == 0 else "pending"
	guidance_seq["current_index"] = 0
	guidance_seq["beat_ready"] = false
	guidance_seq["beat_evidence"] = ""
	guidance_seq["adopted_at"] = Game.messages.size()
	save_state(); changed.emit()

func _active_seq_beat_idx() -> int:
	if guidance_seq.is_empty() or not (guidance_seq.get("beats") is Array): return -1
	var beats: Array = guidance_seq.beats
	for i in range(beats.size()):
		if beats[i] is Dictionary and String(beats[i].get("status", "")) == "active":
			return i
	return -1

func advance_sequence(skip_current := false) -> void:
	var idx := _active_seq_beat_idx()
	if idx < 0: return
	var beats: Array = guidance_seq.beats
	beats[idx]["status"] = "skipped" if skip_current else "done"
	guidance_seq["beat_ready"] = false
	guidance_seq["beat_evidence"] = ""
	var next_idx := -1
	for j in range(idx + 1, beats.size()):
		if beats[j] is Dictionary and String(beats[j].get("status", "")) == "pending":
			beats[j]["status"] = "active"; next_idx = j; break
	guidance_seq["current_index"] = next_idx
	if next_idx < 0:
		guidance_seq = {}
	save_state(); changed.emit()

func clear_guidance() -> void:
	guidance_plan = {}
	guidance_seq = {}
	save_state(); changed.emit()

func active_guidance_summary() -> String:
	var idx := _active_seq_beat_idx()
	if idx >= 0:
		var b: Dictionary = guidance_seq.beats[idx]
		return "序列「%s」第 %d/%d 拍：%s\n目标：%s" % [
			String(guidance_seq.get("title", "剧情序列")), idx + 1, guidance_seq.beats.size(),
			String(b.get("title", "")), String(b.get("goal", ""))
		]
	if not guidance_plan.is_empty():
		var in_k := String(guidance_plan.get("intensity", "normal"))
		var in_lbl := String(INTENSITIES.get(in_k, INTENSITIES.normal).label)
		return "单步引导「%s」（%s）：%s" % [String(guidance_plan.get("title", "")), in_lbl, String(guidance_plan.get("goal", ""))]
	return ""

func active_guidance_injection() -> String:
	var idx := _active_seq_beat_idx()
	if idx >= 0:
		var b: Dictionary = guidance_seq.beats[idx]
		var custom_txt := String(b.get("custom_text", "")).strip_edges()
		var core := custom_txt if custom_txt != "" else ("目标：%s\n迹象：%s" % [String(b.get("goal", "")), String(b.get("seed", ""))])
		var pulse_note := ""
		if bool(settings.get("seq_pulse", true)):
			pulse_note = "\n若本拍目标已在本条回复正文落地，请在末尾注释附上 <!-- SO_BEAT: done | quote: 原文关键句 -->（对玩家不可见）。"
		return "[故事神谕 · 幕后剧情序列引导（第 %d/%d 拍）]\n%s%s" % [idx + 1, guidance_seq.beats.size(), core, pulse_note]
	if not guidance_plan.is_empty():
		var in_k := String(guidance_plan.get("intensity", "normal"))
		var in_lbl := String(INTENSITIES.get(in_k, INTENSITIES.normal).label)
		return "[故事神谕 · 幕后剧情引导｜强度：%s]\n请自然推进以下故事走向，勿生硬跳戏或直接念出指令：\n目标：%s\n起始迹象：%s" % [
			in_lbl, String(guidance_plan.get("goal", "")), String(guidance_plan.get("seed", ""))
		]
	return ""

func check_beat_completion(reply_text: String) -> bool:
	var idx := _active_seq_beat_idx()
	if idx < 0: return false
	var rx := RegEx.new()
	rx.compile("(?is)<!--\\s*SO_BEAT\\s*:\\s*done(?:\\s*\\|\\s*quote\\s*:\\s*(.+?))?\\s*-->")
	var m := rx.search(reply_text)
	if m == null: return false
	guidance_seq["beat_ready"] = true
	guidance_seq["beat_evidence"] = m.get_string(1).strip_edges()
	save_state(); changed.emit()
	return true

# ---------------- Fix Reply & Character Forge ----------------
static func parse_fixed_reply(text: String) -> String:
	var rx := RegEx.new()
	rx.compile("(?is)<FixedReply\\s*>([\\s\\S]*?)(?:</FixedReply\\s*>|$)")
	var hits := rx.search_all(text)
	if hits.is_empty(): return ""
	return hits[-1].get_string(1).strip_edges()

func apply_message_fix(msg_rec_id: int, target_chat_id := -1) -> Dictionary:
	var rec := _find_msg(msg_rec_id)
	if rec.is_empty(): return {"ok": false, "error": "消息不存在"}
	var fixed := String(rec.get("actions", {}).get("fixed_reply", "")).strip_edges()
	if fixed == "": return {"ok": false, "error": "没有提取到 <FixedReply> 正文"}
	var cid := target_chat_id if target_chat_id >= 0 else Game.last_assistant_id()
	var m := Game.message(cid)
	if m.is_empty(): return {"ok": false, "error": "主聊天没有可替换的 AI 楼层"}
	var old_swipe := int(m.get("swipe", 0))
	var orig_txt := Game.text_of(m)
	var final_txt := _merge_preserved_blocks(orig_txt, fixed)
	if not Game.append_swipe(cid, final_txt):
		return {"ok": false, "error": "追加新 Swipe 失败"}
	rec["applied"] = true
	rec["undo_ref"] = "swipe:%d:%d" % [cid, old_swipe]
	save_state(); changed.emit()
	return {"ok": true, "msg_id": cid}

static func _merge_preserved_blocks(orig_txt: String, fixed_txt: String) -> String:
	var out := fixed_txt
	for tag in ["choices", "sumUp", "UpdateVariable"]:
		if not ("<" + tag) in out:
			var rx := RegEx.new()
			rx.compile("(?is)<" + tag + "(?:\\s[^>]*)?>[\\s\\S]*?</" + tag + "\\s*>")
			var m := rx.search(orig_txt)
			if m != null:
				out += "\n" + m.get_string(0)
	return out

static func parse_char_draft(text: String) -> Dictionary:
	var rx := RegEx.new()
	rx.compile("(?is)<CharDraft>([\\s\\S]*?)</CharDraft>")
	var m := rx.search(text)
	if m == null: return {}
	var inner := m.get_string(1)
	var arx := RegEx.new(); arx.compile("(?s)<<<archive\\r?\\n?([\\s\\S]*?)archive>>>")
	var am := arx.search(inner)
	var archive := am.get_string(1).strip_edges() if am != null else ""
	return {
		"target": _kv_pick(inner, ["target", "目标"]),
		"name": _kv_pick(inner, ["name", "姓名", "名称"]),
		"overview": _kv_pick(inner, ["overview", "简介"]),
		"archive": archive if archive != "" else inner,
	}

func apply_message_forge(msg_rec_id: int) -> Dictionary:
	var rec := _find_msg(msg_rec_id)
	if rec.is_empty(): return {"ok": false, "error": "消息不存在"}
	var draft: Dictionary = rec.get("actions", {}).get("char_draft", {})
	var cname := String(draft.get("name", "")).strip_edges()
	if cname == "": return {"ok": false, "error": "草稿缺少角色名称"}
	if String(draft.get("target", "npc")).to_lower() == "persona":
		Game.update_persona({"name": cname, "bio": String(draft.get("archive", ""))})
		rec["applied"] = true; save_state(); changed.emit()
		return {"ok": true, "kind": "persona", "name": cname}
	var DataCls = preload("res://scripts/ui/ui_data.gd")
	var wb_custom: Array = DataCls.custom_worldbook_entries().duplicate(true)
	wb_custom.append({
		"id": "oracle_char_" + cname,
		"title": "DLC/" + cname,
		"category": "创意工坊DLC",
		"path": "story_oracle/forge",
		"summary": String(draft.get("overview", cname)),
		"body": "<DLC_%s>\n%s\n</DLC_%s>" % [cname, String(draft.get("archive", "")), cname],
		"constant": false,
		"_workshop": true,
		"_workshop_type": "character",
		"_oracle": true,
	})
	DataCls.save_custom_worldbook_entries(wb_custom)
	rec["applied"] = true; save_state(); changed.emit()
	return {"ok": true, "kind": "npc", "name": cname}

func _find_msg(id: int) -> Dictionary:
	for r in chat_history:
		if r is Dictionary and int(r.get("id", -1)) == id:
			return r
	return {}
