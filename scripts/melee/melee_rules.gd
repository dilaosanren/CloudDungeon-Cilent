# SPD 4.0.2 Weapon/MeleeWeapon, all 32 directory weapons and quest Pickaxe.
# GPL-3.0-or-later. Strength requirements are intentionally absent in this PvP host.
class_name MeleeRules
extends RefCounted
const ItemText = preload("res://scripts/inventory/item_text.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const DAGGER_TYPES := ["Dagger", "Dirk", "AssassinsBlade"]
static var _source: Dictionary = {}
static func source() -> Dictionary:
	if _source.is_empty(): _source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/melee/source_catalog.json").trim_prefix("\ufeff"))
	return _source
static func types() -> Array: return source().profiles.keys()
static func is_weapon(item: InventoryItem) -> bool: return item != null and source().profiles.has(item.type_id)
static func profile(item: InventoryItem) -> Dictionary: return source().profiles[item.type_id]
static func initialize(item: InventoryItem) -> void:
	if not is_weapon(item): return
	var p := profile(item)
	item.metadata.tier = int(p.tier)
	item.category = "weapon"
	item.visual = p.visual
	if item.type_id == "MagesStaff":
		item.extra_actions.erase("ZAP")
		item.extra_actions.erase("IMBUE")
		item.extra_actions.append("IMBUE")
		item.extra_actions.append("ZAP")
		if "ZAP" not in item.targeting_actions: item.targeting_actions.append("ZAP")
		item.default_action = "ZAP"
		var labels: Dictionary = item.metadata.get("action_labels", {})
		labels.IMBUE = "灌注"
		item.metadata.action_labels = labels
	else:
		item.default_action = ""

static func level(item: InventoryItem, actor: WandActor = null) -> int:
	if item == null: return 0
	var value := item.level
	if item.metadata.get("curse_infusion", false): value += 1 + int(value / 6)
	if actor != null and actor.has_status("degrade"): value = RingRules.reduced_level(value)
	return value
static func augment_damage(item: InventoryItem) -> float:
	return RingRules.f32(0.7) if item.metadata.get("augment") == "speed" else 1.5 if item.metadata.get("augment") == "damage" else float(item.metadata.get("augment_damage", 1))
static func augment_delay(item: InventoryItem) -> float:
	return RingRules.f32(2.0 / 3) if item.metadata.get("augment") == "speed" else RingRules.f32(5.0 / 3) if item.metadata.get("augment") == "damage" else float(item.metadata.get("augment_delay", 1))
static func fixed_damage(item: InventoryItem, actor: WandActor = null, apply_augment: bool = true, surprise: bool = false) -> int:
	var p := profile(item)
	# Keep half-point base/growth values until the final damage rounding.
	var base := (float(p.min_base) + float(p.max_base)) / 2
	var growth := (float(p.min_scale) + float(p.max_scale)) / 2
	var amount := base + growth * level(item, actor)
	if surprise and item.type_id in DAGGER_TYPES: amount *= 1.5
	if apply_augment: amount *= augment_damage(item)
	return maxi(0, RingRules.java_round(RingRules.f32(amount)))
static func raw_range(item: InventoryItem, actor: WandActor = null, surprise: bool = false, apply_augment: bool = true) -> Vector2i:
	var amount := fixed_damage(item, actor, apply_augment, surprise)
	return Vector2i(amount, amount)
static func damage_roll(item: InventoryItem, actor: WandActor, rng: RandomNumberGenerator, surprise: bool = false) -> int:
	if actor.species != "hero" and item == null: return WandState.normal_int(rng,int(actor.data.get("damage_min",4)),int(actor.data.get("damage_max",8)))
	var unarmed := RingRules.fighting_unarmed(actor,item != null)
	if unarmed:
		var bounds := RingRules.unarmed_range(actor)
		return maxi(0, WandState.normal_int(rng,bounds.x,bounds.y))
	return maxi(0, fixed_damage(item, actor, true, surprise) + RingRules.bonus(actor,"RingOfForce"))
static func damage_range(item: InventoryItem, actor: WandActor, surprise: bool = false) -> Vector2i:
	if actor.species != "hero" and item == null: return Vector2i(actor.data.get("damage_min", 4), actor.data.get("damage_max", 8))
	if RingRules.fighting_unarmed(actor, item != null):
		var bounds := RingRules.unarmed_range(actor)
		return bounds.max(Vector2i.ZERO)
	var result := raw_range(item, actor, surprise)
	result += Vector2i.ONE * RingRules.bonus(actor, "RingOfForce")
	return result.max(Vector2i.ZERO)
static func delay(item: InventoryItem, actor: WandActor) -> float:
	var speed := RingRules.furor(actor)
	var base := 1.0
	if item != null:
		if not RingRules.fighting_unarmed(actor, true): base = RingRules.f32(float(profile(item).delay) * augment_delay(item))
	return RingRules.f32(base / speed) / (1.5 if actor.has_status("adrenaline") else 1)
static func accuracy(item: InventoryItem, actor: WandActor) -> float:
	if item == null or RingRules.fighting_unarmed(actor, item != null): return 1
	var acc := float(profile(item).accuracy)
	if actor.has_status("wayward") and item.metadata.get("enchantment") == "wayward": acc /= 5
	return acc
static func reach(item: InventoryItem, actor: WandActor) -> int:
	var value := int(profile(item).reach) if item != null else 1
	var enchant: bool = item != null and item.metadata.get("enchantment") == "projecting" and not actor.has_status("magic_immune") and not actor.data.get("inventory_magic_immune", false)
	if RingRules.fighting_unarmed(actor, item != null):
		value = 1
		if not RingRules.unarmed_gets_enchantment(actor, item != null): return value
	if actor.has_status("ascended_form"): value += 2
	if enchant: value += RingRules.java_round(RingRules.arcana(actor))
	return value
static func defense(item: InventoryItem, actor: WandActor = null, mirror: bool = false) -> int:
	if not is_weapon(item): return 0
	var maximum := maxi(0, int(profile(item).defense_base) + level(item, actor) * int(profile(item).defense_scale))
	# Preserve the image's original halved range before taking its average.
	if mirror: maximum = int(maximum / 2)
	return RingRules.java_round(maximum / 2.0)
static func refresh_equipment(model: DungeonInventory, actor: WandActor) -> void:
	actor.data.melee_weapon = model.equipment.weapon
	actor.data.weapon_accuracy = accuracy(model.equipment.weapon, actor) if is_weapon(model.equipment.weapon) else 1.0
	for item in model.all_items():
		if is_weapon(item): initialize(item)

static func stats(item: InventoryItem, actor: WandActor = null, magic: String = "", curse: String = "") -> String:
	var bounds := raw_range(item, actor)
	var text := L10n.text("这件_%d阶_近战武器可以造成_%d点伤害_。") % [int(profile(item).tier), bounds.x]
	var values: Array = []
	if item.type_id == "Crossbow":
		var lvl := level(item, actor)
		values = [4 + lvl, 12 + 3 * lvl]
	# Greataxe's sole stats sentence describes its removed strength requirement.
	var properties := ""
	if int(profile(item).defense_base) > 0 or int(profile(item).defense_scale) > 0:
		properties = L10n.text("这件武器能稳定格挡_%d点伤害_。") % defense(item, actor)
		if item.type_id in ["RoundShield", "Greatshield"]: properties += " " + L10n.text("格挡量随升级而增长。")
	elif item.type_id != "Greataxe": properties = ItemText.for_item(item.type_id, "stats_desc", values)
	if item.type_id in DAGGER_TYPES: properties = L10n.text("伏击时造成_50%额外伤害_。")
	if item.type_id == "Flail": properties = L10n.text("这是一件不太精准的武器。不能仅凭隐身触发伏击；若攻击者不在对手视野内，仍保证命中。")
	if not properties.is_empty(): text += "\n\n" + properties
	if item.metadata.get("augment", "none") in ["speed", "damage"]:
		text += " " + ItemText.message("items.weapon.weapon." + ("faster" if item.metadata.augment == "speed" else "stronger"))
	if not magic.is_empty(): text += "\n\n" + magic
	if not curse.is_empty(): text += "\n\n" + curse
	if item.type_id == "MagesStaff" and item.metadata.has("staff_wand"):
		# Inspection must not call MeleeStaff.restore(), which writes charges and
		# serialized state back to the item while synchronizing the wand level.
		var wand := InventoryItem.from_dict(item.metadata.staff_wand)
		wand.level = level(item)
		text += "\n\n" + ItemText.for_item(item.type_id, "has_wand", [wand.display_name()])
		text += " " + (ItemText.for_item(item.type_id, "cursed_wand") if item.cursed or item.metadata.get("enchantment_curse", false) else WandState.stats(wand, actor.max_hp if actor != null else 50, actor))
		if actor != null and actor.data.get("battlemage", false): text += "\n\n" + ItemText.for_item(wand.type_id, "bmage_desc")
	return text
