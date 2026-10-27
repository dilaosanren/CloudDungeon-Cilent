# Fixed PvP armor protection, averaged from the existing SPD DRMin/DRMax rules.
# GPL-3.0-or-later. Weapon parry and glyph effects remain separate.
class_name ArmorRules
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")
const TYPES := ["ClothArmor", "LeatherArmor", "MailArmor", "ScaleArmor", "PlateArmor"]

static func tier(item: InventoryItem) -> int:
	if item == null: return 0
	var index := TYPES.find(item.type_id)
	return index + 1 if index >= 0 else int(item.metadata.get("tier", 1))

static func level(item: InventoryItem, actor: WandActor = null) -> int:
	if item == null: return 0
	return RingRules.reduced_level(item.level) if actor != null and actor.has_status("degrade") else item.level

static func defense(item: InventoryItem, actor: WandActor = null) -> int:
	if item == null: return 0
	var lvl := level(item, actor)
	var augmentation := str(item.metadata.get("augment", "none"))
	var bonus := (2 + lvl) * (1 if augmentation == "defense" else -1 if augmentation == "evasion" else 0)
	var maximum := tier(item) * (2 + lvl) + bonus
	# Preserve the original edge handling for evasion-augmented cloth/negative levels.
	maximum = maxi(0, int((lvl - maximum + 1) / 2) if lvl > maximum else maximum)
	var minimum := maxi(0, lvl - maximum if lvl >= maximum else lvl)
	# Average base and growth together, rounding only the final protection value.
	return RingRules.java_round((float(minimum) + float(maximum)) / 2)

static func evasion_bonus(item: InventoryItem, actor: WandActor = null) -> int:
	if item == null: return 0
	var augmentation := str(item.metadata.get("augment", "none"))
	return (2 + level(item, actor)) * (2 if augmentation == "evasion" else -2 if augmentation == "defense" else 0)

static func stats(item: InventoryItem, actor: WandActor = null) -> String:
	return L10n.text("这件_%d阶_护甲能抵挡_%d点伤害_。") % [tier(item), defense(item, actor)]
