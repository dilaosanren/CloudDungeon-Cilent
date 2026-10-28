# Player-facing notes for the current release.
extends RefCounted

const VERSION := "0.0.9"
const DATE := "2026-10-28"
const SECTIONS := ["本次更新"]
const ENTRIES := [
	{"section":0,"icon":"menu:RANKINGS","title":"现在可以看到服务器其他玩家的最近对战记录","body":"在对战记录中切换至服务器页，查看最近100局已结束的对战。"},
	{"section":0,"icon":"menu:AUDIO","title":"新增两首音乐","body":"主菜单播放Theme，对战播放Game，可在设置中独立调节音乐音量。"},
	{"section":0,"icon":"item:ScrollOfMagicMapping","title":"探地卷轴重做并回归","body":"探地卷轴回归商店，阅读后本局持续标记所有地面升级卷轴的位置。"},
	{"section":0,"icon":"menu:NEWS","title":"新增“新闻”选项","body":"查看服务器发布的中英文新闻，未读新闻会让主菜单新闻按钮闪烁提醒。"},
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
