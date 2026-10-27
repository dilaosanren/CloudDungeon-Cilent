class_name ItemAssets
extends RefCounted

const Visual = preload("res://scripts/items/item_visual_resource.gd")
const CATALOG = preload("res://assets/items/item_catalog.tres")
const CATEGORY_LABELS = {
	"PLACEHOLDERS": "占位图", "UNCOLLECTIBLE": "金币与特殊物件", "CONTAINERS": "宝箱与遗骸",
	"MISC_CONSUMABLE": "钥匙与杂项", "BOMBS": "炸弹", "WEP_TIER1": "一阶武器",
	"WEP_TIER2": "二阶武器", "WEP_TIER3": "三阶武器", "WEP_TIER4": "四阶武器",
	"WEP_TIER5": "五阶武器", "MISSILE_WEP": "弓与投掷武器", "DARTS": "飞镖",
	"ARMOR": "护甲", "WANDS": "法杖", "RINGS": "戒指", "ARTIFACTS": "神器",
	"TRINKETS": "饰物", "SCROLLS": "卷轴", "EXOTIC_SCROLLS": "秘卷",
	"STONES": "符石", "POTIONS": "药剂", "EXOTIC_POTIONS": "合剂",
	"SEEDS": "种子", "BREWS": "魔药", "ELIXIRS": "秘药", "SPELLS": "法术结晶",
	"FOOD": "食物", "HOLIDAY_FOOD": "节日食物", "QUEST": "任务物品",
	"BAGS": "容器与背包", "DOCUMENTS": "文档",
}
static var _items: Dictionary = {}
static var _icons: Dictionary = {}
static var _ids: Dictionary = {}
static var _icon_ids: Dictionary = {}

static func _index() -> void:
	if not _items.is_empty():
		return
	for entry in CATALOG.items:
		_items[entry.key] = entry
		_ids[entry.sprite_id] = entry
	for entry in CATALOG.icons:
		_icons[entry.key] = entry
		_icon_ids[entry.sprite_id] = entry

static func get_visual(identifier: Variant, icon: bool = false) -> Visual:
	_index()
	if identifier is int:
		return (_icon_ids if icon else _ids).get(identifier)
	if identifier is String or identifier is StringName:
		return (_icons if icon else _items).get(StringName(String(identifier).to_upper()))
	return null

## Main sprites and small icons have separate namespaces and numeric IDs.
## Numeric lookup also supports unnamed original slots (including blank ones).
static func get_texture(identifier: Variant, icon: bool = false) -> Texture2D:
	var entry := get_visual(identifier, icon)
	if entry != null:
		return entry.texture
	if identifier is int:
		var slots: Array[AtlasTexture] = CATALOG.icon_slots if icon else CATALOG.item_slots
		return slots[identifier] if identifier >= 0 and identifier < slots.size() else null
	return null

static func categories(icon: bool = false) -> PackedStringArray:
	var result := PackedStringArray()
	for entry in CATALOG.icons if icon else CATALOG.items:
		if not result.has(String(entry.category)):
			result.append(String(entry.category))
	return result

static func list_visuals(category: String = "", query: String = "", icon: bool = false) -> Array[Visual]:
	var result: Array[Visual] = []
	query = query.to_lower().strip_edges()
	for entry in CATALOG.icons if icon else CATALOG.items:
		if not category.is_empty() and entry.category != StringName(category):
			continue
		if not query.is_empty() and not String(entry.key).to_lower().contains(query) and not " ".join(entry.source_references).to_lower().contains(query):
			continue
		result.append(entry)
	return result
