# Player-facing notes for the current release.
extends RefCounted

const VERSION := "0.0.8"
const DATE := "2026-10-27"
const SECTIONS := ["本次更新"]
const ENTRIES := [
	{"section":0,"icon":"item:PotionOfCorrosiveGas","title":"新添2种合剂","body":"腐蚀酸雾合剂、魔能透视合剂。"},
	{"section":0,"icon":"menu:JOURNAL","title":"增加对话系统","body":"战斗中可通过右上角菜单与本局对手对话。"},
	{"section":0,"icon":"menu:EXIT","title":"投降按钮","body":"战斗菜单新增投降按钮，确认后本局判负。"},
	{"section":0,"icon":"menu:GOLD","title":"捐赠按钮","body":"主菜单捐献入口现可查看说明，并前往爱发电自愿支持服务器与开发。"},
]

static func icon(key: String) -> Texture2D:
	if key.begins_with("menu:"): return MenuAssets.icon(key.trim_prefix("menu:"))
	if key.begins_with("item:"):
		var item := InventoryCatalog.create(key.trim_prefix("item:"))
		return ItemAssets.get_texture(item.visual) if item != null else null
	if key.begins_with("buff:"):
		var definition: Dictionary = preload("res://scripts/status/buff_descriptions.gd").definitions().get(key.trim_prefix("buff:"), {})
		return StatusAssets.icon_texture(StatusAssets.icon_id(str(definition.get("icon", "NONE"))))
	return null
