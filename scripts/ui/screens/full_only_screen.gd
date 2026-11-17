extends "res://scripts/ui/ui_screen.gd"
## Reserved placeholder for unbuilt optional modules (ship / advanced scripts / optional slots).
## params: id, title.

const PAGES := {
	"workshop": ["刻印工坊", "拼装纹章、图纸、纹章图鉴；完成后存进 主角组.魔法。"],
	"bridge": ["舰桥看板", "看板角色互动与单角色聊天。"],
	"advanced": ["高级", "世界书开关、正则开关、脚本库、扩展管理、变量修复。"],
	"adult": ["成人模块", "只留位置，不做内容。"],
}

func build() -> void:
	var id: String = params.get("id", "advanced")
	var pg: Array = PAGES.get(id, [params.get("title", "扩展功能"), ""])
	chrome(pg[0])
	var p := plate(Rect2(460, 330, 1000, 300), {"shape": "cut", "slant": 40, "corner": "tr", "hatch": true}, "c", 0.1)
	text("该扩展功能暂未启用", Rect2(60, 40, 880, 70), 40, "ink", 900, "c", p)
	text(pg[1], Rect2(60, 130, 880, 120), 24, "muted", 650, "c", p)
