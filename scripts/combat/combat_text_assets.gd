# FloatingText iconFilm and Char.damage icon indices. GPL-3.0-or-later.
class_name CombatTextAssets
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")

enum Icon {
	NO_ICON = -1,
	PHYS_DMG = 0, PHYS_DMG_NO_BLOCK = 1, MAGIC_DMG = 2, PICK_DMG = 3,
	HUNGER = 5, BURNING = 6, SHOCKING = 7, FROST = 8, WATER = 9,
	BLEEDING = 10, TOXIC = 11, CORROSION = 12, POISON = 13, OOZE = 14,
	DEFERRED = 15, CORRUPTION = 16, AMULET = 17,
	HEALING = 18, SHIELDING = 19, EXPERIENCE = 20, STRENGTH = 21,
	GOLD = 23, ENERGY = 24,
	HIT_WEP = 36, HIT_ARM = 37, HIT_BLS = 38, HIT_HEX = 39,
	HIT_DAZE = 40, HIT_ACC = 41, HIT_EVA = 42, HIT_LIQ = 43,
	HIT_DANCE = 44, HIT_SUPR = 45, HIT_PRES = 46, HIT_MOMEN = 47,
	MISS_WEP = 72, MISS_ARM = 73, MISS_BLS = 74, MISS_HEX = 75,
	MISS_DAZE = 76, MISS_ACC = 77, MISS_EVA = 78, MISS_LIQ = 79,
	MISS_DEF = 80, MISS_TUFT = 81, MISS_RUN = 82,
}
const ICON_SIZE := Vector2i(7, 8)
const FONT_SIZE := 9
const DAMAGE_TYPES := {
	Icon.PHYS_DMG: "物理伤害", Icon.PHYS_DMG_NO_BLOCK: "穿甲伤害",
	Icon.MAGIC_DMG: "魔法伤害", Icon.PICK_DMG: "镐击伤害",
	Icon.HUNGER: "饥饿", Icon.BURNING: "燃烧", Icon.SHOCKING: "电击",
	Icon.FROST: "冰霜", Icon.WATER: "水流", Icon.BLEEDING: "流血",
	Icon.TOXIC: "毒气", Icon.CORROSION: "腐蚀", Icon.POISON: "中毒",
	Icon.OOZE: "污泥", Icon.DEFERRED: "延迟伤害", Icon.CORRUPTION: "腐化",
	Icon.AMULET: "护符伤害",
}
static var _catalog: Dictionary = {}
static var _icons: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat/source_catalog.json"))
	return _catalog.duplicate(true)

static func icon_id(name: String) -> int:
	return int(catalog().icons.get(name.to_upper(), Icon.NO_ICON))

static func icon_texture(id: int) -> AtlasTexture:
	if id < 0: return null
	var atlas: Texture2D = load("res://assets/combat/source/text_icons.png")
	var columns := floori(float(atlas.get_width()) / ICON_SIZE.x)
	var rows := floori(float(atlas.get_height()) / ICON_SIZE.y)
	if id >= columns * rows: return null
	if not _icons.has(id):
		var texture := AtlasTexture.new()
		texture.atlas = atlas
		texture.region = Rect2((id % columns) * ICON_SIZE.x, floori(float(id) / columns) * ICON_SIZE.y, ICON_SIZE.x, ICON_SIZE.y)
		_icons[id] = texture
	return _icons[id]

## Char.damage substitutes the hit reason; piercing variants occupy the next 18-cell row.
static func damage_icon(kind: int, hit_reason: int = Icon.NO_ICON) -> int:
	if kind in [Icon.PHYS_DMG, Icon.PHYS_DMG_NO_BLOCK] and hit_reason >= Icon.HIT_WEP and hit_reason <= Icon.HIT_MOMEN:
		return hit_reason + (18 if kind == Icon.PHYS_DMG_NO_BLOCK else 0)
	return kind

static func defense_word(kind: String) -> String:
	return L10n.text(String(catalog().words.get(kind, "")))

static func damage_color() -> Color:
	return UiPalette.color(Color.RED)
