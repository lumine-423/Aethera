extends Control
## Cross-platform GitHub Application Updater Overlay (Android APK & Desktop PCK/ZIP/EXE).
## Opened from Title Screen's bottom-left placeholder button or Settings footer.

const Kit = preload("res://scripts/ui/ui_kit.gd")
const Plate = preload("res://scripts/ui/ui_plate.gd")
const Btn = preload("res://scripts/ui/ui_button.gd")
const Lbl = preload("res://scripts/ui/ui_label.gd")
const W = preload("res://scripts/ui/ui_widgets.gd")
const UpdaterHub = preload("res://scripts/game/app_updater_hub.gd")

var owner_root: Node
var panel: Control
var slug_input: LineEdit
var branch_input: LineEdit
var dl_bar: Control
var dl_pct_lbl: Label
var status_lbl: Label
var _closing := false

func _hub() -> UpdaterHub:
	return UiHub.updater() as UpdaterHub

func _ready() -> void:
	name = "AppUpdateOverlay"
	set_meta("app_update_modal", true)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	var h := _hub()
	if is_instance_valid(h):
		if not h.changed.is_connected(_on_hub_changed): h.changed.connect(_on_hub_changed)
		if not h.progress_changed.is_connected(_on_progress): h.progress_changed.connect(_on_progress)

func _exit_tree() -> void:
	var h := _hub()
	if is_instance_valid(h):
		if h.changed.is_connected(_on_hub_changed): h.changed.disconnect(_on_hub_changed)
		if h.progress_changed.is_connected(_on_progress): h.progress_changed.disconnect(_on_progress)

func _on_hub_changed() -> void:
	if is_inside_tree() and not _closing:
		_build()

func _on_progress(got: int, total: int, ratio: float) -> void:
	if not is_inside_tree(): return
	if is_instance_valid(dl_bar):
		dl_bar.max_value = 1.0
		dl_bar.set_value(ratio, false)
	if is_instance_valid(dl_pct_lbl):
		var mb_got := float(got) / 1048576.0
		var mb_tot := float(maxi(total, 1)) / 1048576.0
		dl_pct_lbl.text = "%d%% · %.1f/%.1f MB" % [int(round(ratio * 100.0)), mb_got, mb_tot]

func close() -> void:
	if _closing: return
	_closing = true
	UiHub.sfx("close")
	if get_parent(): get_parent().remove_child(self)
	queue_free()

func _build() -> void:
	var draft_slug := slug_input.text if is_instance_valid(slug_input) else ""
	var draft_branch := branch_input.text if is_instance_valid(branch_input) else ""
	for c in get_children():
		c.queue_free()

	var h := _hub()
	var shade := ColorRect.new()
	shade.color = UiHub.c("shade")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close(); shade.accept_event()
	)
	add_child(shade)
	Kit.frost(shade)

	var pw := 1320.0
	var ph := 860.0
	panel = Control.new()
	panel.name = "UpdatePanel"
	panel.size = Vector2(pw, ph)
	panel.position = (size - panel.size) * 0.5
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var bg := Plate.new()
	bg.shape = "cut"; bg.slant = 42; bg.corner = "tr"; bg.fill_alpha = 0.98
	bg.hatch = true; bg.dots = true; bg.layer_offset = Vector2(14, 12)
	bg.size = panel.size
	panel.add_child(bg)

	# Header
	var title_lbl := Lbl.new()
	title_lbl.setup("版本与 GitHub 更新", 36, "ink", 900)
	title_lbl.position = Vector2(40, 26); title_lbl.size = Vector2(480, 56)
	panel.add_child(title_lbl)

	var badge_lbl := Lbl.new()
	badge_lbl.setup("当前 v%s  ·  %s" % [h.local_version(), h.platform_label()], 20, "accent", 800)
	badge_lbl.position = Vector2(520, 32); badge_lbl.size = Vector2(620, 44)
	badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(badge_lbl)

	var close_b := Btn.new(); close_b.name = "UpdateCloseBtn"
	close_b.setup("关闭", "close", "secondary", 20)
	close_b.position = Vector2(pw - 156, 26); close_b.size = Vector2(120, 54)
	close_b.pressed.connect(func(): close())
	panel.add_child(close_b)

	# Status & Progress plate
	var st_plate := Plate.new()
	st_plate.shape = "cut"; st_plate.slant = 20; st_plate.fill = "surface2"
	st_plate.fill_alpha = 0.85; st_plate.layered = false; st_plate.stripe = "left"
	st_plate.position = Vector2(36, 98); st_plate.size = Vector2(pw - 72, 152)
	panel.add_child(st_plate)

	var meta_lbl := Lbl.new()
	var ver_far := ("v" + h.latest_version) if h.latest_version != "" else "未获取"
	var chk_at := h.last_checked_at if h.last_checked_at != "" else "未检查"
	meta_lbl.setup("GitHub 仓库：%s   ｜   远端最新：%s   ｜   上次检查：%s" % [h.repo_slug(), ver_far, chk_at], 18, "muted", 700)
	meta_lbl.position = Vector2(36, 14); meta_lbl.size = Vector2(pw - 144, 32)
	st_plate.add_child(meta_lbl)

	status_lbl = Lbl.new(); status_lbl.name = "UpdateStatusLabel"
	status_lbl.setup(h.status_text, 22, "accent" if h.update_available else "ink", 800)
	status_lbl.position = Vector2(36, 50); status_lbl.size = Vector2(pw - 144, 42)
	status_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	st_plate.add_child(status_lbl)

	dl_bar = W.Bar.new(); dl_bar.name = "UpdateDownloadBar"; dl_bar.intro = false
	dl_bar.max_value = 1.0
	var ratio_now := 1.0 if h.downloaded_file_path != "" else (clampf(float(h.downloaded_bytes) / float(maxi(h.total_bytes, 1)), 0.0, 1.0) if h.downloading else 0.0)
	dl_bar.value = ratio_now
	dl_bar.role = "accent"
	dl_bar.position = Vector2(36, 108); dl_bar.size = Vector2(920, 16)
	st_plate.add_child(dl_bar)

	dl_pct_lbl = Lbl.new(); dl_pct_lbl.name = "UpdateProgressText"
	var pct_txt := "待下载"
	if h.downloading:
		pct_txt = "%d%% · %.1f/%.1f MB" % [int(round(ratio_now * 100.0)), float(h.downloaded_bytes) / 1048576.0, float(maxi(h.total_bytes, 1)) / 1048576.0]
	elif h.downloaded_file_path != "":
		pct_txt = "100%% · 已下载 (%.1f MB)" % [float(h.downloaded_bytes) / 1048576.0]
	dl_pct_lbl.setup(pct_txt, 18, "muted", 700)
	dl_pct_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dl_pct_lbl.position = Vector2(968, 98); dl_pct_lbl.size = Vector2(252, 36)
	st_plate.add_child(dl_pct_lbl)

	# 3-step Action Strip: Check -> Pull -> Download -> Apply/Browser
	var b_chk := Btn.new(); b_chk.name = "UpdateCheckBtn"
	b_chk.setup("1. 检查更新", "refresh", "secondary", 20)
	b_chk.disabled = h.checking or h.pulling
	b_chk.position = Vector2(36, 268); b_chk.size = Vector2(218, 58)
	b_chk.pressed.connect(func():
		h.check_for_updates(func(_ok_u: bool, _v: String, msg: String):
			_toast(msg)
		)
	)
	panel.add_child(b_chk)

	var b_pull := Btn.new(); b_pull.name = "UpdatePullBtn"
	b_pull.setup("2. 拉取更新", "docs", "secondary", 20)
	b_pull.disabled = h.checking or h.pulling
	b_pull.position = Vector2(270, 268); b_pull.size = Vector2(218, 58)
	b_pull.pressed.connect(func():
		h.pull_update(func(_ok_p: bool, msg: String):
			_toast(msg)
		)
	)
	panel.add_child(b_pull)

	var b_dl := Btn.new(); b_dl.name = "UpdateDownloadBtn"
	if h.downloading:
		b_dl.setup("取消下载", "close", "danger", 20)
		b_dl.pressed.connect(func(): h.cancel_download())
	else:
		b_dl.setup("3. 下载更新", "download", "primary", 20)
		b_dl.disabled = h.checking or h.pulling or not h.is_repo_configured() or h.release_assets.is_empty()
		b_dl.pressed.connect(func():
			h.download_recommended(func(_ok_d: bool, _path: String, msg: String):
				_toast(msg)
			)
		)
	b_dl.position = Vector2(504, 268); b_dl.size = Vector2(236, 58)
	panel.add_child(b_dl)

	var b_act := Btn.new(); b_act.name = "UpdateInstallBtn"
	var dl_low := h.downloaded_file_path.to_lower()
	if dl_low.ends_with(".pck"):
		b_act.setup("启用补丁(重启生效)", "check", "primary", 19)
		b_act.disabled = h.downloaded_file_path == ""
		b_act.pressed.connect(func():
			var res := h.apply_downloaded_pck_patch()
			_toast(String(res.get("message", "")))
		)
	elif h.detect_platform_key() == "android" or dl_low.ends_with(".apk"):
		b_act.setup("尝试安装 APK", "play", "secondary", 19)
		b_act.disabled = h.downloaded_file_path == ""
		b_act.pressed.connect(func():
			if not h.open_downloaded_package():
				_toast("Android 限制直接唤起本地 APK，请点右侧「浏览器直链下载」安装")
		)
	elif OS.get_name() == "Windows" and dl_low.ends_with(".exe") and not dl_low.ends_with("-setup.exe") and not OS.has_feature("editor"):
		b_act.setup("覆盖更新并重启", "play", "primary", 19)
		b_act.disabled = h.downloaded_file_path == ""
		b_act.pressed.connect(func():
			var res := h.apply_windows_exe_update()
			_toast(String(res.get("message", "")))
		)
	else:
		b_act.setup("运行/打开安装包", "play", "secondary", 19)
		b_act.disabled = h.downloaded_file_path == ""
		b_act.pressed.connect(func():
			if not h.open_downloaded_package():
				h.open_download_folder()
		)
	b_act.position = Vector2(756, 268); b_act.size = Vector2(268, 58)
	panel.add_child(b_act)

	var b_web := Btn.new(); b_web.name = "UpdateBrowserBtn"
	b_web.setup("浏览器直链下载", "next", "chip", 19)
	b_web.disabled = not h.is_repo_configured()
	b_web.tooltip_text = "用系统浏览器直达安装包或 Release 页面（手机端可直接下载完成点击安装）"
	b_web.position = Vector2(1040, 268); b_web.size = Vector2(244, 58)
	b_web.pressed.connect(func():
		h.open_browser_download()
		_toast("已交由系统浏览器打开更新地址")
	)
	panel.add_child(b_web)

	# Asset list & Changelog box
	var notes_plate := Plate.new()
	notes_plate.shape = "cut"; notes_plate.slant = 20; notes_plate.fill = "surface2"
	notes_plate.fill_alpha = 0.65; notes_plate.layered = false
	notes_plate.position = Vector2(36, 344); notes_plate.size = Vector2(pw - 72, 276)
	panel.add_child(notes_plate)

	var ax := 22.0
	if h.release_assets.is_empty():
		var hint := Lbl.new()
		var hmsg := "提示：目前为 GitHub 更新占位。上传仓库并发布 Release（附带 Android .apk 或 电脑端 .pck/.zip/.exe）后即可自动匹配下载。"
		hint.setup(hmsg, 18, "muted", 650)
		hint.position = Vector2(22, 16); hint.size = Vector2(pw - 116, 40)
		notes_plate.add_child(hint)
	else:
		var lbl_a := Lbl.new(); lbl_a.setup("发布包：", 18, "ink", 800)
		lbl_a.position = Vector2(22, 18); lbl_a.size = Vector2(96, 38)
		notes_plate.add_child(lbl_a)
		ax = 118.0
		var max_chips := mini(h.release_assets.size(), 4)
		for i in range(max_chips):
			var a: Dictionary = h.release_assets[i]
			var mb := float(int(a.get("size", 0))) / 1048576.0
			var cap := "%s (%.1fMB)" % [String(a.get("name", "")), mb]
			var cw := clampf(float(cap.length()) * 11.0 + 34.0, 170.0, 276.0)
			if ax + cw > pw - 96: break
			var idx_i := i
			var cb := Btn.new(); cb.name = "UpdateAssetChip_%d" % i
			cb.setup(cap, "", "segment", 16)
			cb.center_text = true; cb.selected = (i == h.selected_asset_index)
			cb.position = Vector2(ax, 14); cb.size = Vector2(cw, 44)
			cb.pressed.connect(func():
				h.selected_asset_index = idx_i
				h.changed.emit()
			)
			notes_plate.add_child(cb)
			ax += cw + 10.0

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.position = Vector2(22, 68); sc.size = Vector2(pw - 116, 192)
	notes_plate.add_child(sc)
	var note_lbl := Lbl.new(); note_lbl.name = "UpdateChangelog"
	var body_lines := []
	if h.release_notes != "":
		body_lines.append("【远端更新说明 %s】" % (h.release_name if h.release_name != "" else h.latest_tag))
		body_lines.append(h.release_notes)
	elif not h.pulled_manifest.is_empty():
		body_lines.append("【已拉取清单 v%s】%s" % [String(h.pulled_manifest.get("version", "")), String(h.pulled_manifest.get("notes", ""))])
	else:
		body_lines.append("【更新通道说明】")
		body_lines.append("1. 手机端（Android）：检查 GitHub Release 最新版本 -> 拉取更新说明与校验 -> 下载 .apk 或唤起浏览器直接安装更新包。")
		body_lines.append("2. 电脑端（Windows/macOS/Linux）：支持下载 .pck 热更补丁（重启即生效）或完整 .zip/.exe 安装包，并可直接打开所在目录。")
		body_lines.append("3. 上传到 GitHub 后，可在下方输入「用户名/仓库名」立即测试；也可直接修改项目文件 data/app_update.json 中的默认仓库地址。")
	if h.downloaded_file_path != "":
		body_lines.append("\n已下载文件路径：%s" % ProjectSettings.globalize_path(h.downloaded_file_path))
		if h.downloaded_sha256 != "":
			body_lines.append("SHA256：%s" % h.downloaded_sha256)
	note_lbl.setup("\n".join(body_lines), 18, "ink", 600)
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.custom_minimum_size = Vector2(pw - 136, 0)
	sc.add_child(note_lbl)

	# GitHub Repo Config Plate
	var cfg_plate := Plate.new()
	cfg_plate.shape = "cut"; cfg_plate.slant = 20; cfg_plate.fill = "surface2"
	cfg_plate.fill_alpha = 0.72; cfg_plate.layered = false
	cfg_plate.position = Vector2(36, 636); cfg_plate.size = Vector2(pw - 72, 192)
	panel.add_child(cfg_plate)

	var cfg_head := Lbl.new()
	cfg_head.setup("GitHub 仓库绑定（手机与电脑通用，修改后保存在本机配置中）", 19, "ink", 850)
	cfg_head.position = Vector2(24, 14); cfg_head.size = Vector2(pw - 120, 32)
	cfg_plate.add_child(cfg_head)

	var l_slug := Lbl.new(); l_slug.setup("仓库:", 18, "muted", 700)
	l_slug.position = Vector2(24, 62); l_slug.size = Vector2(64, 46)
	cfg_plate.add_child(l_slug)

	slug_input = LineEdit.new(); slug_input.name = "UpdateRepoInput"
	slug_input.placeholder_text = "用户名/仓库名（例如 Hotaru/aethera-rpg）"
	slug_input.text = draft_slug if draft_slug != "" else ("" if not h.is_repo_configured() else h.repo_slug())
	slug_input.position = Vector2(92, 58); slug_input.size = Vector2(510, 48)
	cfg_plate.add_child(slug_input)

	var l_br := Lbl.new(); l_br.setup("分支:", 18, "muted", 700)
	l_br.position = Vector2(620, 62); l_br.size = Vector2(60, 46)
	cfg_plate.add_child(l_br)

	branch_input = LineEdit.new(); branch_input.name = "UpdateBranchInput"
	branch_input.placeholder_text = "main"
	branch_input.text = draft_branch if draft_branch != "" else (h.github_branch if h.github_branch != "" else "main")
	branch_input.position = Vector2(684, 58); branch_input.size = Vector2(150, 48)
	cfg_plate.add_child(branch_input)

	var mir_b := Btn.new(); mir_b.name = "UpdateMirrorBtn"
	mir_b.setup("镜像加速：" + ("已开启" if h.use_mirror else "关闭(直连)"), "refresh", "chip", 18)
	mir_b.selected = h.use_mirror
	mir_b.position = Vector2(852, 58); mir_b.size = Vector2(372, 48)
	mir_b.pressed.connect(func():
		h.use_mirror = not h.use_mirror
		h.save_config()
		h.changed.emit()
	)
	cfg_plate.add_child(mir_b)

	var save_b := Btn.new(); save_b.name = "UpdateSaveRepoBtn"
	save_b.setup("保存并检查更新", "check", "primary", 18)
	save_b.position = Vector2(24, 122); save_b.size = Vector2(246, 52)
	save_b.pressed.connect(func():
		h.set_repo_config(slug_input.text, "", branch_input.text, h.use_mirror)
		if h.is_repo_configured():
			h.check_for_updates(func(_ok_c: bool, _v: String, msg: String): _toast(msg))
		else:
			_toast("已清空仓库绑定（保持更新占位状态）")
	)
	cfg_plate.add_child(save_b)

	var rst_b := Btn.new(); rst_b.name = "UpdateResetRepoBtn"
	rst_b.setup("恢复占位", "refresh", "secondary", 18)
	rst_b.position = Vector2(286, 122); rst_b.size = Vector2(168, 52)
	rst_b.pressed.connect(func():
		slug_input.text = ""
		branch_input.text = "main"
		h.reset_repo_config()
		_toast("已恢复默认占位配置")
	)
	cfg_plate.add_child(rst_b)

	var dir_b := Btn.new(); dir_b.name = "UpdateOpenDirBtn"
	dir_b.setup("打开更新目录", "save", "secondary", 18)
	dir_b.position = Vector2(470, 122); dir_b.size = Vector2(220, 52)
	dir_b.pressed.connect(func():
		h.open_download_folder()
		_toast("更新包保存于：" + ProjectSettings.globalize_path(h.preferred_download_dir()))
	)
	cfg_plate.add_child(dir_b)

	var patch_lbl := Lbl.new()
	var patch_txt := ("已激活热更补丁：v%s" % h.installed_patch_version) if h.active_pck_path != "" else "尚无激活中的 .pck 热更补丁"
	patch_lbl.setup(patch_txt, 17, "muted", 600)
	patch_lbl.position = Vector2(710, 130); patch_lbl.size = Vector2(514, 36)
	patch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cfg_plate.add_child(patch_lbl)

func _toast(msg: String) -> void:
	if msg == "": return
	if is_instance_valid(owner_root) and owner_root.has_method("toast"):
		owner_root.toast(msg, "info")
