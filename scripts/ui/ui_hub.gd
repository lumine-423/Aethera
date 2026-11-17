extends Node
## Autoload "UiHub": one shared source for colors, day/night, accessibility options and
## the outward-facing interface signals that future game/AI/audio services connect to.
## Pure Godot (no web-only API), so desktop exe and Android apk behave the same.

signal palette_changed
signal options_changed
signal music_changed
## Every player intent the UI cannot fulfil by itself goes out through here.
## Back-end services listen and answer by calling the screen APIs listed in docs/ui-full-01.md.
signal action_requested(action: String, payload: Dictionary)
signal sfx_requested(cue: String)

const OPTIONS_PATH := "user://home_ui_sample.cfg"
const EXTRA_PATH := "user://ui_options.cfg"

var palette: Dictionary = {}
var night := 0.0
var night_target := false
var reduced_motion := false
var spacing := 0.5
var text_scale := 1.0
var dialog_speed := 0.6
var auto_speed := 0.5
var flash_strength := 1.0
var volumes := {"master": 0.8, "music": 0.7, "sfx": 0.8, "voice": 0.9, "ui": 0.8}
var mute_unfocused := true
var review_mode := false
var mobile_portrait_input := false
var gate_unlock_hash := ""
var notice_seen := false
var opening_seen := false
var options_path_override := ""
var extra_path_override := ""
var _night_tween: Tween
## Set by the UI root: animated day/night switches play the circular reveal instead of a crossfade.
var reveal_handler: Callable
var _sfx_players: Dictionary = {}
var _sfx_map: Dictionary = {}
var music_manifest: Dictionary = {}
var music_current := ""
var music_disabled := false
var music_override := ""
var music_paused := false
var music_story_var := ""
var music_route_resolver: Callable = Callable()
var _music_players: Array[AudioStreamPlayer] = []
var _music_slot := 0
var _music_tween: Tween
var _music_ducked := false
var _duck_tween: Tween
var _focused := true
var _workshop_hub: Node
var _oracle_hub: Node
var _updater_hub: Node

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if "--home-review" in args or "--ui-review" in args:
		return
	var cfg := ConfigFile.new()
	if cfg.load("user://app_updater.cfg") != OK:
		return
	var pck_path := String(cfg.get_value("patch", "active_pck_path", "")).strip_edges()
	var patch_ver := String(cfg.get_value("patch", "installed_patch_version", "")).strip_edges()
	if pck_path == "" or not FileAccess.file_exists(pck_path):
		return
	var base_ver := "1.0.0"
	if FileAccess.file_exists("res://data/app_update.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/app_update.json"))
		if parsed is Dictionary:
			base_ver = String(parsed.get("version", "1.0.0")).strip_edges()
	var UpdaterCls := preload("res://scripts/game/app_updater_hub.gd")
	if patch_ver != "" and UpdaterCls.version_newer(patch_ver, base_ver):
		ProjectSettings.load_resource_pack(pck_path, true)

func workshop() -> Node:
	if _workshop_hub == null or not is_instance_valid(_workshop_hub):
		_workshop_hub = preload("res://scripts/game/workshop_hub.gd").new()
		_workshop_hub.name = "WorkshopHub"
		add_child(_workshop_hub)
	return _workshop_hub

func story_oracle() -> Node:
	if _oracle_hub == null or not is_instance_valid(_oracle_hub):
		_oracle_hub = preload("res://scripts/game/story_oracle_hub.gd").new()
		_oracle_hub.name = "StoryOracleHub"
		add_child(_oracle_hub)
	return _oracle_hub

func updater() -> Node:
	if _updater_hub == null or not is_instance_valid(_updater_hub):
		_updater_hub = preload("res://scripts/game/app_updater_hub.gd").new()
		_updater_hub.name = "AppUpdaterHub"
		add_child(_updater_hub)
	return _updater_hub

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	review_mode = "--home-review" in args or "--ui-review" in args
	palette = JSON.parse_string(FileAccess.get_file_as_string("res://data/home_palette.json"))
	var extra = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/ui_palette_extra.json"))
	for mode in ["day", "night"]:
		for key in extra[mode]: palette[mode][key] = extra[mode][key]
	if FileAccess.file_exists("res://data/ui/ui_sounds.json"):
		_sfx_map = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui/ui_sounds.json"))
		sfx_pack = _sfx_map.get("default_pack", "aic")
	if not review_mode: load_options()
	_setup_buses()
	if FileAccess.file_exists("res://data/content/music_manifest.json"):
		music_manifest = JSON.parse_string(FileAccess.get_file_as_string("res://data/content/music_manifest.json"))
	for i in range(2):
		# Web sample playback did not emit BGM in the desktop runtime; use the Godot mixer.
		var player := AudioStreamPlayer.new(); player.bus = "Music"; player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM; add_child(player); _music_players.append(player)
	workshop()

## Palette role at the current day/night mix. Alpha multiplies the role's own alpha.
func c(role: String, alpha := 1.0) -> Color:
	var day: Color = Color(palette.day.get(role, "ff00ff"))
	var nite: Color = Color(palette.night.get(role, "ff00ff"))
	var out := day.lerp(nite, night)
	out.a *= alpha
	return out

func set_night(value: bool, animate := true) -> void:
	if animate and not reduced_motion and reveal_handler.is_valid() and value != night_target:
		reveal_handler.call(value); return
	var prev_target := night_target
	if animate and value != night_target:
		sfx("theme_night" if value else "theme_day")
	night_target = value
	if _night_tween: _night_tween.kill()
	var target := 1.0 if value else 0.0
	if reduced_motion or not animate or not is_inside_tree():
		night = target; palette_changed.emit()
	else:
		_night_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_night_tween.tween_method(func(v): night = v; palette_changed.emit(), night, target, 0.4)
	save_options()
	if value != prev_target and music_route_resolver.is_valid():
		music_route_resolver.call_deferred()

func set_option(key: String, value) -> void:
	set(key, value)
	if key == "mute_unfocused": _apply_focus_mute()
	options_changed.emit()
	save_options()

func set_volume(bus: String, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volumes()
	options_changed.emit(); save_options()

## Spacing-aware gap: the UI布局 slider widens or tightens margins, never zooms.
func gap(base: float) -> float:
	return base * lerpf(0.72, 1.32, spacing)

func fs(base: float) -> int:
	return int(round(base * text_scale))

func request(action: String, payload := {}) -> void:
	action_requested.emit(action, payload)

## ---------- interface sound ----------
## sfx(cue, pitch, gain_db): every cue has a small voice pool (overlapping plays), a cooldown so fast
## repeats (hover sweeps, typing) never stack into noise, and a tiny random pitch so repeats feel alive.
## Pack switch keeps the same cue names: "aic" (reference, not cleared for release) or "mystic".
## The old synth pack "original" was removed 2026-11-17; a saved "original" falls back to aic.
var sfx_pack := "aic"
var haptics := true
var _streams: Dictionary = {}
var _last_play: Dictionary = {}
const POOL := 4

func _setup_buses() -> void:
	for bus in ["Music", "SFX", "Voice", "UI"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus(); var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus); AudioServer.set_bus_send(i, "Master")
	_apply_volumes()

func _bus_for(key: String) -> String:
	return {"master": "Master", "music": "Music", "sfx": "SFX", "voice": "Voice", "ui": "UI"}.get(key, "Master")

func _apply_volumes() -> void:
	for key in volumes:
		var i := AudioServer.get_bus_index(_bus_for(key))
		if i >= 0: AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volumes[key], 0.0001)))

func _stream(cue: String) -> AudioStream:
	var key := sfx_pack + "/" + cue
	var fixed := String(_sfx_map.get("cues", {}).get(cue, {}).get("file", ""))
	if fixed != "":
		# pack-independent cue (home room object sounds, synthesized for this game)
		if not _streams.has(fixed): _streams[fixed] = load(fixed) if ResourceLoader.exists(fixed) else null
		return _streams[fixed]
	if not _streams.has(key):
		var path := "res://assets/audio/ui/%s/%s.ogg" % [sfx_pack, cue]
		if not ResourceLoader.exists(path):
			var spec: Dictionary = _sfx_map.get("cues", {}).get(cue, {})
			var fb := String(spec.get("fallback", ""))
			if fb != "":
				var fb_path := "res://assets/audio/ui/%s/%s.ogg" % [sfx_pack, fb]
				if ResourceLoader.exists(fb_path): path = fb_path
		_streams[key] = load(path) if ResourceLoader.exists(path) else null
	return _streams[key]

## true while the workshop activation music plays: no other sound may play (user rule 2026-11-17)
var sfx_quiet := false

func sfx(cue: String, pitch := 1.0, gain_db := 0.0) -> void:
	if sfx_quiet: return
	sfx_requested.emit(cue)
	var spec: Dictionary = _sfx_map.get("cues", {}).get(cue, {})
	if spec.is_empty(): return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(cue, -10.0)) < float(spec.get("cd", 0.04)): return
	_last_play[cue] = now
	var stream := _stream(cue)
	if stream == null: return
	if not _sfx_players.has(cue):
		var pool: Array = []
		for k in range(POOL):
			var p := AudioStreamPlayer.new(); p.bus = spec.get("bus", "UI"); p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM; add_child(p); pool.append(p)
		_sfx_players[cue] = {"pool": pool, "next": 0}
	var slot: Dictionary = _sfx_players[cue]
	var player: AudioStreamPlayer = slot.pool[slot.next]
	slot.next = (slot.next + 1) % POOL
	player.stream = stream
	var v: float = float(spec.get("var", 0.0))
	player.pitch_scale = clampf(pitch * (1.0 + randf_range(-v, v)), 0.25, 4.0)
	player.volume_db = float(spec.get("db", -8.0)) + gain_db
	player.play()

## Light tap on phones (needs the VIBRATE permission in the Android export preset).
## Programmatic focus right after a page appears should not beep; real keyboard moves still do.
var _focus_quiet_until := 0
func quiet_focus(ms := 700) -> void:
	_focus_quiet_until = Time.get_ticks_msec() + ms
func focus_sound_ok() -> bool:
	return Time.get_ticks_msec() > _focus_quiet_until

func haptic(ms := 12) -> void:
	if haptics and OS.has_feature("mobile"): Input.vibrate_handheld(ms)

func set_mobile_portrait(on: bool) -> void:
	mobile_portrait_input = on
	if OS.has_feature("android") or OS.has_feature("ios"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT if on else DisplayServer.SCREEN_SENSOR_LANDSCAPE)
	options_changed.emit()

func set_pack(p: String) -> void:
	sfx_pack = p; _streams.clear(); options_changed.emit(); save_options()

func _options_path() -> String:
	return options_path_override if options_path_override != "" else OPTIONS_PATH

func _extra_path() -> String:
	return extra_path_override if extra_path_override != "" else EXTRA_PATH

func is_gate_unlocked(expected_password: String) -> bool:
	var normalized := expected_password.strip_edges()
	return normalized != "" and gate_unlock_hash != "" and gate_unlock_hash == normalized.sha256_text()

func mark_gate_unlocked(expected_password: String) -> void:
	var target := expected_password.strip_edges().sha256_text()
	if gate_unlock_hash == target: return
	gate_unlock_hash = target
	save_options()

func mark_opening_seen() -> void:
	if opening_seen: return
	opening_seen = true
	save_options()

func mark_notice_seen() -> void:
	if notice_seen: return
	notice_seen = true
	save_options()

func load_options() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_options_path()) == OK:
		night_target = bool(cfg.get_value("home", "night", false)); night = 1.0 if night_target else 0.0
		reduced_motion = bool(cfg.get_value("home", "reduced_motion", false))
		spacing = clampf(float(cfg.get_value("home", "spacing", 0.5)), 0.0, 1.0)
		text_scale = clampf(float(cfg.get_value("home", "text_scale", 1.0)), 0.90, 1.12)
	var extra := ConfigFile.new()
	if extra.load(_extra_path()) == OK:
		dialog_speed = float(extra.get_value("ui", "dialog_speed", dialog_speed))
		auto_speed = float(extra.get_value("ui", "auto_speed", auto_speed))
		flash_strength = float(extra.get_value("ui", "flash_strength", flash_strength))
		mute_unfocused = bool(extra.get_value("ui", "mute_unfocused", mute_unfocused))
		# v3 key: switch default UI SFX pack to aic (Alice In Cradle)
		var saved_pack := str(extra.get_value("ui", "sfx_pack_v3", _sfx_map.get("default_pack", "aic")))
		sfx_pack = saved_pack if _sfx_map.get("packs", {}).has(saved_pack) else str(_sfx_map.get("default_pack", "aic"))
		haptics = bool(extra.get_value("ui", "haptics", haptics))
		music_disabled = bool(extra.get_value("ui", "music_disabled", music_disabled))
		gate_unlock_hash = str(extra.get_value("ui", "gate_unlock_hash", gate_unlock_hash))
		notice_seen = bool(extra.get_value("ui", "notice_seen", notice_seen))
		opening_seen = bool(extra.get_value("ui", "opening_seen", opening_seen))
		var saved = extra.get_value("ui", "volumes", volumes)
		if saved is Dictionary:
			for k in saved: volumes[k] = clampf(float(saved[k]), 0.0, 1.0)

func save_options() -> void:
	if review_mode: return
	var cfg := ConfigFile.new()
	cfg.set_value("home", "night", night_target); cfg.set_value("home", "reduced_motion", reduced_motion)
	cfg.set_value("home", "spacing", spacing); cfg.set_value("home", "text_scale", text_scale)
	cfg.save(_options_path())
	var extra := ConfigFile.new()
	extra.set_value("ui", "dialog_speed", dialog_speed); extra.set_value("ui", "auto_speed", auto_speed)
	extra.set_value("ui", "flash_strength", flash_strength); extra.set_value("ui", "mute_unfocused", mute_unfocused)
	extra.set_value("ui", "volumes", volumes)
	extra.set_value("ui", "sfx_pack_v3", sfx_pack); extra.set_value("ui", "haptics", haptics)
	extra.set_value("ui", "music_disabled", music_disabled)
	extra.set_value("ui", "gate_unlock_hash", gate_unlock_hash)
	extra.set_value("ui", "notice_seen", notice_seen)
	extra.set_value("ui", "opening_seen", opening_seen)
	extra.save(_extra_path())

func reset_display() -> void:
	spacing = 0.5; text_scale = 1.0; reduced_motion = false; dialog_speed = 0.6; auto_speed = 0.5; flash_strength = 1.0
	options_changed.emit(); palette_changed.emit(); save_options()

## Only current and fading tracks are loaded. Old save aliases resolve here.
func music_spec(value: String) -> Dictionary:
	var tracks: Array = music_manifest.get("tracks", [])
	for track in tracks:
		if value == track.title or value == track.id or value in track.get("aliases", []):
			return track
	var low := value.strip_edges().to_lower()
	if low != "":
		for track in tracks:
			if String(track.title).to_lower() == low or String(track.id).to_lower() == low:
				return track
			for a in track.get("aliases", []):
				if String(a).to_lower() == low:
					return track
	return {}

func music_spec_for_location(loc: String) -> Dictionary:
	if loc == "":
		return {}
	for rule in music_manifest.get("location_tracks", []):
		if not rule is Dictionary: continue
		var kw := String(rule.get("keyword", ""))
		if kw != "" and kw in loc:
			return music_spec(String(rule.get("title", "")))
	return {}

func ui_screen_track(key: String, fallback_title := "Main Theme") -> String:
	var table: Dictionary = music_manifest.get("ui_screen_tracks", {})
	var chosen := String(table.get(key, ""))
	return chosen if chosen != "" and not music_spec(chosen).is_empty() else fallback_title

func music_title(value: String) -> String:
	if value == "无" or value == "": return "无"
	return String(music_spec(value).get("title", "无"))

func active_music_player() -> AudioStreamPlayer:
	if _music_slot < 0 or _music_slot >= _music_players.size(): return null
	return _music_players[_music_slot]

func is_music_playing() -> bool:
	var p := active_music_player()
	return not music_disabled and not music_paused and p != null and p.playing and not p.stream_paused

func music_position() -> float:
	var p := active_music_player()
	if p == null or p.stream == null or not p.playing: return 0.0
	return p.get_playback_position()

func music_duration() -> float:
	var p := active_music_player()
	if p == null or p.stream == null: return 0.0
	return maxf(p.stream.get_length(), 0.0)

func seek_music(sec: float) -> void:
	var p := active_music_player()
	if p == null or p.stream == null: return
	var pos := clampf(sec, 0.0, maxf(music_duration() - 0.05, 0.0))
	if p.playing: p.seek(pos)
	else:
		p.play(pos)
		p.stream_paused = music_paused
	music_changed.emit()

func toggle_music_pause() -> void:
	if music_disabled:
		set_music_disabled(false); return
	if music_current == "":
		if music_override == "" and music_route_resolver.is_valid():
			music_route_resolver.call(); return
		var target := music_override if music_override != "" else (music_story_var if music_story_var != "" else String(music_manifest.get("title_track", "Main Theme")))
		play_music(target, 0.25, true); return
	music_paused = not music_paused
	var p := active_music_player()
	if p: p.stream_paused = music_paused
	music_changed.emit()

func set_music_disabled(disabled: bool) -> void:
	music_disabled = disabled
	music_paused = false
	save_options()
	if disabled:
		stop_workshop_activation(false)
		stop_music()
	else:
		if music_override != "":
			play_music(music_override, 0.35, true)
		elif music_route_resolver.is_valid():
			music_route_resolver.call()
		else:
			var target := music_story_var if music_story_var != "" else String(music_manifest.get("title_track", "Main Theme"))
			if target != "" and target != "无音乐":
				play_music(target, 0.35, true)
	music_changed.emit()
	options_changed.emit()

func select_music(title: String) -> void:
	music_override = title
	music_paused = false
	if music_disabled:
		music_disabled = false
		save_options()
		options_changed.emit()
	play_music(title, 0.25, true)

func clear_music_override() -> void:
	music_override = ""
	music_paused = false
	if music_disabled:
		music_changed.emit(); return
	if music_route_resolver.is_valid():
		music_route_resolver.call()
	else:
		var target := music_story_var if music_story_var != "" else String(music_manifest.get("title_track", "Main Theme"))
		play_music(target, 0.35, true)

func duck_music(ducked: bool, fade := 0.25, depth := 24.0) -> void:
	_music_ducked = ducked
	var p := active_music_player()
	if p == null or not p.playing:
		return
	var spec := music_spec(music_current)
	var base_db := float(spec.get("gain_db", -10.0)) if not spec.is_empty() else -10.0
	var target_db := (base_db - depth) if ducked else base_db
	if _duck_tween: _duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_property(p, "volume_db", target_db, fade)

func play_music(value: String, fade := 0.45, force := false) -> void:
	if not force and value != "无音乐":
		music_story_var = value
	if music_disabled:
		stop_music()
		music_changed.emit()
		return
	var effective := value
	if not force and music_override != "" and value != "无音乐":
		effective = music_override
	var spec := music_spec(effective)
	var title := String(spec.get("title", ""))
	if title == music_current and not (force and music_paused): return
	if _music_tween: _music_tween.kill()
	if _duck_tween: _duck_tween.kill()
	music_current = title
	music_paused = false
	var old: AudioStreamPlayer = _music_players[_music_slot]
	_music_slot = 1 - _music_slot
	var next: AudioStreamPlayer = _music_players[_music_slot]
	next.stop(); next.stream = null; next.stream_paused = false
	_music_tween = create_tween().set_parallel(true)
	_music_tween.tween_property(old, "volume_db", -60.0, fade)
	if spec.is_empty():
		_music_tween.chain().tween_callback(func(): old.stop(); old.stream = null)
		music_changed.emit()
		return
	var stream := load(String(spec.res)) as AudioStreamOggVorbis
	if stream == null:
		music_current = ""
		music_changed.emit()
		return
	stream.loop = true; stream.loop_offset = float(spec.get("loop_offset_seconds", 0.0))
	next.stream = stream; next.volume_db = -60.0; next.stream_paused = false; next.play()
	var target_db := float(spec.get("gain_db", -10.0)) - (24.0 if _music_ducked else 0.0)
	_music_tween.tween_property(next, "volume_db", target_db, fade)
	_music_tween.chain().tween_callback(func(): old.stop(); old.stream = null)
	music_changed.emit()

func stop_music() -> void:
	if _music_tween: _music_tween.kill()
	if _duck_tween: _duck_tween.kill()
	_music_ducked = false
	for player in _music_players:
		player.stop(); player.stream = null; player.stream_paused = false
	music_current = ""
	music_paused = false
	music_changed.emit()

var _ws_click_player: AudioStreamPlayer
var _ws_loop_player: AudioStreamPlayer
var _ws_loop_tween: Tween
var _ws_alt_idx := 0

func _ensure_ws_players() -> void:
	if _ws_click_player == null:
		_ws_click_player = AudioStreamPlayer.new()
		_ws_click_player.bus = "Music"
		add_child(_ws_click_player)
	if _ws_loop_player == null:
		_ws_loop_player = AudioStreamPlayer.new()
		_ws_loop_player.bus = "Music"
		add_child(_ws_loop_player)

func _workshop_activation_res(role: String) -> String:
	for item in music_manifest.get("workshop_activation", []):
		if item is Dictionary and String(item.get("role", "")) == role:
			return String(item.get("res", ""))
	var fallback := {
		"click": "res://assets/audio/ui/workshop_activation/activate_click.ogg",
		"loop_a": "res://assets/audio/ui/workshop_activation/activate_loop_a.ogg",
		"loop_b": "res://assets/audio/ui/workshop_activation/activate_loop_b.ogg",
		"done": "res://assets/audio/ui/workshop_activation/activate_done.ogg",
	}
	return String(fallback.get(role, ""))

## The four activation clips, each played to its end (user rule 2026-11-17: same for day and
## night, nothing else sounds while they play).
const WS_ORDER := ["click", "loop_a", "loop_b", "done"]
const WS_SEQUENCE := "res://assets/audio/ui/workshop_activation/activate_sequence.ogg"
var _ws_seq_start_us := -1

## Plays 1 click, then 2 loop_a + 3 loop_b together, then 4 done once both are over (user rule
## 2026-11-17; gapless AudioStreamPlaylist of [click, AudioStreamSynchronized(loop_a, loop_b), done],
## no loop, no fades) and fully silences the page BGM meanwhile. The animation is timed to this
## sequence (data/workshop/activation_cues.json) and reads the heard position from
## workshop_activation_time().
func start_workshop_activation() -> void:
	_ws_seq_start_us = -1
	sfx_quiet = true
	if music_disabled:
		return
	_ensure_ws_players()
	if _ws_loop_tween: _ws_loop_tween.kill()
	_ws_click_player.stop()
	duck_music(true, 0.2, 80.0)
	# preferred: the pre-placed one-file mix (tools/build_workshop_activation.py, timing from the
	# user's mixer page) - sample-exact, and its playback position is the animation clock
	if ResourceLoader.exists(WS_SEQUENCE):
		var seq := load(WS_SEQUENCE) as AudioStreamOggVorbis
		if seq != null:
			seq.loop = false
			_ws_loop_player.stop()
			_ws_loop_player.stream = seq
			_ws_loop_player.volume_db = -6.5
			_ws_loop_player.play()
			_ws_seq_start_us = Time.get_ticks_usec()
			return
	var clip := {}
	for role in WS_ORDER:
		var res := _workshop_activation_res(role)
		if res == "" or not ResourceLoader.exists(res): continue
		var st := load(res) as AudioStreamOggVorbis
		if st == null: continue
		st.loop = false
		clip[role] = st
	# 2 and 3 start together: one synchronized stream that lasts as long as the longer of them
	var both := AudioStreamSynchronized.new()
	var k := 0
	for role in ["loop_a", "loop_b"]:
		if not clip.has(role): continue
		both.stream_count = k + 1
		both.set_sync_stream(k, clip[role]); both.set_sync_stream_volume(k, 0.0); k += 1
	var pl := AudioStreamPlaylist.new()
	pl.loop = false; pl.shuffle = false; pl.fade_time = 0.0
	var parts: Array = []
	if clip.has("click"): parts.append(clip.click)
	if k > 0: parts.append(both)
	if clip.has("done"): parts.append(clip.done)
	if parts.is_empty(): return
	pl.stream_count = parts.size()
	for i in range(parts.size()): pl.set_list_stream(i, parts[i])
	_ws_loop_player.stop()
	_ws_loop_player.stream = pl
	_ws_loop_player.volume_db = -6.5
	_ws_loop_player.play()
	_ws_seq_start_us = Time.get_ticks_usec()

## Heard position (s) in the activation sequence, or -1 when it is not playing.
func workshop_activation_time() -> float:
	if _ws_seq_start_us < 0 or _ws_loop_player == null or not _ws_loop_player.playing: return -1.0
	if _ws_loop_player.stream is AudioStreamOggVorbis:
		# one-file mix: the decoder position is exact
		return maxf(0.0, _ws_loop_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	return maxf(0.0, (Time.get_ticks_usec() - _ws_seq_start_us) / 1000000.0 - AudioServer.get_output_latency())

## Player skipped the animation: cut the sequence and play only 06 (the completion sound).
func skip_workshop_activation() -> void:
	_ws_seq_start_us = -1
	if _ws_loop_player: _ws_loop_player.stop()
	finish_workshop_activation()

func finish_workshop_activation() -> void:
	if music_disabled:
		return
	_ensure_ws_players()
	if _ws_loop_tween: _ws_loop_tween.kill()
	if _ws_loop_player.playing:
		_ws_loop_tween = create_tween()
		_ws_loop_tween.tween_property(_ws_loop_player, "volume_db", -52.0, 0.6)
		_ws_loop_tween.tween_callback(_ws_loop_player.stop)
	var done_res := _workshop_activation_res("done")
	if done_res != "" and ResourceLoader.exists(done_res):
		_ws_click_player.stop()
		_ws_click_player.stream = load(done_res)
		_ws_click_player.volume_db = -6.0
		_ws_click_player.play()

func stop_workshop_activation(restore_bgm := true) -> void:
	sfx_quiet = false
	_ws_seq_start_us = -1
	if _ws_loop_tween: _ws_loop_tween.kill()
	if _ws_click_player: _ws_click_player.stop()
	if _ws_loop_player: _ws_loop_player.stop()
	if restore_bgm:
		duck_music(false, 0.45)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]: _focused = false; _apply_focus_mute()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN]: _focused = true; _apply_focus_mute()

func _apply_focus_mute() -> void:
	AudioServer.set_bus_mute(0, mute_unfocused and not _focused)
