# Adapted from SPD 4.0.2 Item / ItemSlot. GPL-3.0-or-later.
class_name InventoryItem
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")

var uid: String = ""
var type_id: String = ""
var title: String = ""
var description: String = ""
var visual: String = "SOMETHING"
var icon: String = ""
var category: String = "misc"
var quantity: int = 1
var stackable: bool = false
var level: int = 0
# Read-only compatibility properties for old item/save callers. Knowledge is no longer gameplay state.
var level_known: bool:
	get: return true
	set(_value): pass
var identified: bool:
	get: return true
	set(_value): pass
var cursed: bool = false
var cursed_known: bool:
	get: return true
	set(_value): pass
var strength: int = 0
var charges: int = -1
var max_charges: int = 0
var default_action: String = ""
var extra_actions: Array = []
var targeting_actions: Array = []
var unique: bool = false
var kept: bool = false
var note: String = ""
var metadata: Dictionary = {}

const FIELDS = ["uid", "type_id", "title", "description", "visual", "icon", "category",
	"quantity", "stackable", "level", "level_known", "identified", "cursed", "cursed_known",
	"strength", "charges", "max_charges", "default_action", "extra_actions", "targeting_actions",
	"unique", "kept", "note", "metadata"]

func display_name() -> String:
	if L10n.is_english():
		var name := L10n.item_name(type_id, title)
		if metadata.has("enchantment"):
			return L10n.title_case(L10n.gear_text("weapon", str(metadata.enchantment), "name", "%s").replace("%s", name))
		if metadata.has("glyph"):
			return L10n.title_case(L10n.gear_text("armor", str(metadata.glyph), "name", "%s").replace("%s", name))
		return name
	return (str(metadata.get("enchantment_name", "")) if metadata.has("enchantment") else str(metadata.get("glyph_name", "")) if metadata.has("glyph") else "") + title

func similar(other: InventoryItem) -> bool:
	if MissileRules.is_weapon(self) and MissileRules.is_weapon(other):
		return type_id == other.type_id and level == other.level and metadata.get("set_id") == other.metadata.get("set_id")
	return other != null and type_id == other.type_id and level == other.level and cursed == other.cursed

func status() -> String:
	if charges >= 0:
		return "%d/%d" % [charges, max_charges]
	if category == "missile": return str(quantity)
	return str(quantity) if quantity != 1 else ""

func to_dict() -> Dictionary:
	var result := {}
	for field in FIELDS:
		result[field] = get(field)
	return result.duplicate(true)

static func from_dict(data: Dictionary) -> InventoryItem:
	var item := InventoryItem.new()
	for field in FIELDS:
		if data.has(field):
			if field in ["title", "description"] and data[field] == null: continue
			item.set(field, data[field])
	item.metadata.erase("type_known")
	# Discard retired action metadata in old saves/network item snapshots.
	item.extra_actions.erase("ABILITY")
	item.targeting_actions.erase("ABILITY")
	if item.default_action == "ABILITY": item.default_action = ""
	item.metadata.erase("ability_enabled")
	if item.metadata.get("action_labels") is Dictionary: item.metadata.action_labels.erase("ABILITY")
	return item

func copy_item() -> InventoryItem:
	var item := from_dict(to_dict())
	item.uid = ""
	return item
