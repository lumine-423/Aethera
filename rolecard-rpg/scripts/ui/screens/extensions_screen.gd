extends "res://scripts/ui/ui_screen.gd"
## 扩展中心 (Extensions Hub): Houses adapted card extensions (创意工坊, 故事神谕, and future adapters).

const EXTENSIONS := [
	{
		"id": "creative_workshop",
		"title": "创意工坊（荧荧工坊）",
		"subtitle": "浏览、免登录下载与导入艾瑟拉玩家作品（刻印 / 角色 DLC / 世界书），支持 Discord 回环登录上传发布。",
		"icon": "globe",
		"source": "hotaru-workshop",
		"version_prop": "builtin",
		"route": "creative_workshop",
	},
	{
		"id": "story_oracle",
		"title": "故事神谕 (Story Oracle)",
		"subtitle": "戏外剧情顾问、MVU 变量诊断修复、世界书自然语言管理、多拍剧情参谋引导、正文校正与 GitHub 在线更新。",
		"icon": "compass",
		"source": "namelessone88/story-oracle",
		"version_prop": "oracle",
		"route": "oracle_overlay",
	},
]

func build() -> void:
	uses_backdrop = true
	backdrop_style = "blur"
	chrome("扩展中心")
	decor(104, Rect2(Vector2.ZERO, size), 0.35)

	var oracle := UiHub.story_oracle()
	if not oracle.update_status_changed.is_connected(_on_oracle_upd):
		oracle.update_status_changed.connect(_on_oracle_upd)
	if bool(oracle.settings.get("auto_check_update", true)) and oracle.latest_version == "":
		oracle.check_for_updates()

	text("已适配并接入独立客户端的酒馆扩展工具与在线平台入口，后续新增适配扩展也将汇总在此。", Rect2(86, 134, 1748, 36), 21, "muted", 600)

	var cw := 848.0
	var ch := 396.0
	for i in range(EXTENSIONS.size()):
		var ext: Dictionary = EXTENSIONS[i]
		var col_i := i % 2
		var row_i := i / 2
		var rect := Rect2(86.0 + float(col_i) * (cw + 48.0), 192.0 + float(row_i) * (ch + 34.0), cw, ch)
		_build_ext_card(ext, rect, i)

	# Future extension reservation strip
	var fut := plate(Rect2(86, 634, 1744, 196), {"shape": "cut", "slant": 26, "corner": "tr", "fill": "surface2", "layered": false}, "c", 0.25)
	fut.name = "ExtensionsFutureSlot"
	icon("star4", Rect2(38, 66, 62, 62), "muted", "c", fut)
	text("更多扩展预留位", Rect2(124, 42, 600, 42), 28, "ink", 850, "c", fut)
	var fut_sub := text("扩展中心已采用统一注册表与独立数据通道，后续有其他需要适配的酒馆插件（如角色/记忆/美化类脚本），均会作为新卡片加入此列表并在故事界面或本页提供入口。", Rect2(124, 92, 1570, 76), 20, "muted", 600, "c", fut)
	fut_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _exit_tree() -> void:
	if is_instance_valid(UiHub):
		var oracle := UiHub.story_oracle()
		if oracle.update_status_changed.is_connected(_on_oracle_upd):
			oracle.update_status_changed.disconnect(_on_oracle_upd)

func _on_oracle_upd() -> void:
	if is_inside_tree():
		refresh(false)

func _build_ext_card(ext: Dictionary, rect: Rect2, idx: int) -> void:
	var eid := String(ext.id)
	var card := plate(rect, {"shape": "cut", "slant": 32, "corner": "tr", "hatch": true}, "c", 0.06 * float(idx + 1))
	card.name = "ExtCard_" + eid

	var ic_bg := plate(Rect2(34, 34, 96, 96), {"shape": "rect", "fill": "surface2", "layered": false}, "c", -1.0, card)
	icon(String(ext.icon), Rect2(22, 22, 52, 52), "accent", "c", ic_bg)

	var oracle := UiHub.story_oracle()
	var ver_str := "v" + String(oracle.installed_version) if eid == "story_oracle" else "已连接艾瑟拉分区"
	if eid == "story_oracle" and oracle.update_available:
		ver_str += "  ·  可更新至 v" + String(oracle.latest_version)

	text(String(ext.title), Rect2(150, 34, rect.size.x - 184.0, 46), 30, "ink", 900, "c", card)
	text("来源：%s  ·  %s" % [String(ext.source), ver_str], Rect2(150, 84, rect.size.x - 184.0, 32), 17, "accent" if (eid == "story_oracle" and oracle.update_available) else "muted", 700, "c", card)

	var sub_l := text(String(ext.subtitle), Rect2(34, 152, rect.size.x - 68.0, 118), 20, "ink", 550, "c", card)
	sub_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	if eid == "creative_workshop":
		var b := btn("进入创意工坊", "globe", "primary", Rect2(34, rect.size.y - 96.0, 290, 64), func(): root.go("creative_workshop"), "c", -1.0, card, 21)
		b.name = "ExtOpenWorkshopBtn"
		var b_repo := btn("管理面板", "docs", "secondary", Rect2(340, rect.size.y - 96.0, 210, 64), func(): root.go("creative_workshop", {"tab": "repo"}), "c", -1.0, card, 20)
		b_repo.name = "ExtOpenWorkshopRepoBtn"
	elif eid == "story_oracle":
		var b_o := btn("打开故事神谕", "compass", "primary", Rect2(34, rect.size.y - 96.0, 270, 64), func(): root.open_story_oracle(), "c", -1.0, card, 21)
		b_o.name = "ExtOpenOracleBtn"
		var upd_lbl := "拉取新版 v" + String(oracle.latest_version) if oracle.update_available else "检查 / 拉取更新"
		var b_u := btn(upd_lbl, "download" if oracle.update_available else "refresh", "secondary", Rect2(320, rect.size.y - 96.0, 260, 64), func():
			if oracle.update_available:
				oracle.pull_update(func(ok_p: bool, msg: String): toast(msg, "confirm" if ok_p else "warn"))
			else:
				oracle.check_for_updates(func(_ok: bool, _v: String, msg: String): toast(msg, "info"))
		, "c", -1.0, card, 19)
		b_u.name = "ExtOracleUpdateBtn"
