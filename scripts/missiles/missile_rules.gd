# SPD 4.0.2 MissileWeapon and fifteen normal / thirteen dart classes.
# Copyright Oleg Dolya / Evan Debenham. GPL-3.0-or-later.
class_name MissileRules
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")
const ItemText = preload("res://scripts/inventory/item_text.gd")
const NORMAL_TYPES = ["ThrowingStone", "ThrowingKnife", "ThrowingSpike", "FishingSpear", "Shuriken", "ThrowingClub", "ThrowingSpear", "Kunai", "Bolas", "Javelin", "Tomahawk", "HeavyBoomerang", "Trident", "ThrowingHammer", "ForceCube"]
const DART_TYPES = ["Dart", "AdrenalineDart", "BlindingDart", "ChillingDart", "CleansingDart", "DisplacingDart", "HealingDart", "HolyDart", "IncendiaryDart", "ParalyticDart", "PoisonDart", "RotDart", "ShockingDart"]
static var _catalog: Dictionary = {}
static var _balance: Dictionary = {}
static var _serial := 0
static func balance() -> Dictionary:
	if _balance.is_empty(): _balance = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missiles/pvp_balance.json"))
	return _balance
static func source() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/missiles/source_catalog.json").trim_prefix("\ufeff"))
		for type_id in balance().weapons:
			_catalog.profiles[type_id].merge(balance().weapons[type_id], true)
	return _catalog
static func is_weapon(item: InventoryItem) -> bool: return item != null and (item.type_id in NORMAL_TYPES or item.type_id in DART_TYPES)
static func profile(item: InventoryItem) -> Dictionary: return source().profiles[item.type_id]
static func dart(item: InventoryItem) -> bool: return item.type_id in DART_TYPES
static func tipped(item: InventoryItem) -> bool: return dart(item) and item.type_id != "Dart"
static func effective_enchant(item: InventoryItem, actor: WandActor) -> String:
	var bow: InventoryItem = actor.data.get("crossbow")
	return str(bow.metadata.get("enchantment", "")) if dart(item) and bow != null and bow.metadata.has("enchantment") else str(item.metadata.get("enchantment", ""))
static func initialize(item: InventoryItem) -> void:
	if not is_weapon(item): return
	var p := profile(item)
	item.category = "missile"; item.stackable = true; item.default_action = "THROW"; item.visual = p.visual
	item.metadata.tier = int(p.tier)
	if not item.metadata.has("set_id"):
		_serial += 1
		item.metadata.set_id = "0" if dart(item) else "%d_%d" % [Time.get_ticks_usec(), _serial]
	for key in ["durability", "extra_thrown_left", "crystal_durability", "crystal_uses_left", "crystal_shattered"]: item.metadata.erase(key)
	if dart(item):
		item.extra_actions.erase("TIP"); item.extra_actions.erase("CLEAN")
		item.extra_actions.append("CLEAN" if tipped(item) else "TIP")
static func create(type: String, quantity: int = -1) -> InventoryItem:
	var item := InventoryCatalog.create(type)
	item.quantity = int(profile(item).quantity) if quantity < 0 else quantity
	return item
static func effective_level(item: InventoryItem, actor: WandActor = null) -> int:
	var level := item.level
	if actor != null:
		if actor.has_status("degrade"): level = RingRules.reduced_level(level)
		level += RingRules.sharpshooting_damage(actor)
	return level
static func damage_range(item: InventoryItem, actor: WandActor = null, surprise: bool = false) -> Vector2i:
	if item.type_id in NORMAL_TYPES:
		var data := profile(item)
		var fixed := maxf(0, float(data.damage) + float(data.growth) * effective_level(item, actor))
		var damage := RingRules.java_round(fixed * float(item.metadata.get("augment_damage", 1)))
		return Vector2i(damage, damage)
	var tier := int(profile(item).tier); var level := effective_level(item, actor)
	var lo := 2 * tier + level; var hi := 5 * tier + tier * level
	match item.type_id:
		"ThrowingKnife": hi = 6 * tier + (2 * level if tier == 1 else tier * level)
		"Shuriken", "ThrowingClub", "ThrowingHammer", "Kunai": hi = 4 * tier + tier * level
		"HeavyBoomerang": hi = 4 * tier + (tier - 1) * level
		"ForceCube": hi = 6 * tier + tier * level
		"Bolas": lo = 2 * (tier - 1); hi = 3 * tier + (tier - 1) * level
		"Tomahawk": lo = RingRules.java_round(1.5 * tier) + level; hi = 4 * tier + (tier - 1) * level
	if dart(item):
		lo = 1 + level; hi = 2 + 2 * level
		var bow: InventoryItem = actor.data.get("crossbow") if actor != null else null
		if bow != null:
			var bow_level := RingRules.reduced_level(bow.level) if actor.has_status("degrade") else bow.level
			lo = 4 + bow_level + level; hi = 12 + 3 * bow_level + 2 * level
	lo = maxi(0, lo); hi = maxi(0, hi)
	if surprise and item.type_id in ["ThrowingKnife", "Kunai"]:
		lo += RingRules.java_round(RingRules.f32((hi - lo) * RingRules.f32(0.75 if item.type_id == "ThrowingKnife" else 0.6)))
	var damage_factor := float(item.metadata.get("augment_damage", 1))
	return Vector2i(RingRules.java_round(lo * damage_factor), RingRules.java_round(hi * damage_factor))
static func delay(item: InventoryItem, actor: WandActor, enemy: WandActor = null) -> float:
	if item.type_id == "Shuriken" and not actor.has_status("shuriken_cooldown"): return 0
	if enemy == null or enemy == actor: return 1.0
	var cost := float(item.metadata.get("augment_delay", 1)) / RingRules.furor(actor)
	if actor.has_status("adrenaline"): cost /= 1.5
	return cost
static func accuracy(item: InventoryItem, actor: WandActor, enemy: WandActor, returning: bool = false) -> float:
	var factor := 1.5 if returning or maxi(absi(enemy.cell % int(actor.data.get("map_width", 1)) - actor.cell % int(actor.data.get("map_width", 1))), absi(int(enemy.cell / int(actor.data.get("map_width", 1))) - int(actor.cell / int(actor.data.get("map_width", 1))))) > 1 else 0.5 + 0.25 * int(actor.data.get("point_blank", 0))
	return factor * float(item.metadata.get("accuracy", 1))
static func split(source_item: InventoryItem, projectile: InventoryItem) -> void:
	initialize(source_item)
	initialize(projectile)
static func merge(item: InventoryItem, other: InventoryItem) -> int:
	initialize(item)
	initialize(other)
	item.quantity += other.quantity
	var infused := bool(item.metadata.get("curse_infusion", false))
	var cursed_enchant := bool(item.metadata.get("enchantment_curse", false))
	var other_cursed := bool(other.metadata.get("enchantment_curse", false))
	if (not infused and other.metadata.get("curse_infusion", false) and other_cursed) or (not infused and (not item.metadata.has("enchantment") or cursed_enchant) and other.metadata.has("enchantment") and not other_cursed) or (not cursed_enchant and other_cursed and other.metadata.get("curse_infusion", false)):
		for key in ["enchantment", "enchantment_curse", "curse_infusion"]:
			if other.metadata.has(key): item.metadata[key] = other.metadata[key]
			else: item.metadata.erase(key)
		item.cursed = other.cursed
	for key in ["mastery_bonus", "enchantment_hardened"]: item.metadata[key] = item.metadata.get(key, false) or other.metadata.get(key, false)
	other.quantity = 0
	return 0
static func record_enchantment(item: InventoryItem, model: DungeonInventory) -> void:
	if not model.missile_state.has("enchants"): model.missile_state.enchants = {}
	var key := str(item.metadata.set_id)
	if item.metadata.has("enchantment"): model.missile_state.enchants[key] = item.metadata.enchantment
	else: model.missile_state.enchants.erase(key)
static func filter_enchantment(item: InventoryItem, model: DungeonInventory) -> void:
	var latest: String = model.missile_state.get("enchants", {}).get(str(item.metadata.set_id), "")
	if not latest.is_empty() and item.metadata.has("enchantment") and latest != item.metadata.enchantment:
		for key in ["enchantment", "enchantment_curse", "curse_infusion"]: item.metadata.erase(key)
static func upgraded(item: InventoryItem, model: DungeonInventory) -> void:
	# Upgrade only the surviving stack; no refill or destruction of old drops.
	initialize(item)
	record_enchantment(item, model)
static func pickup_delay(item: InventoryItem) -> float: return float(profile(item).pickup_delay)
static func stats(item: InventoryItem, actor: WandActor = null, _holster: bool = false, magic: String = "", _curse: String = "") -> String:
	var bounds := damage_range(item, actor)
	var amount := str(bounds.x) if bounds.x==bounds.y else "%d~%d" % [bounds.x,bounds.y]
	var text := L10n.text("投掷武器，造成_%s_点伤害。") % amount
	var effect: Dictionary = balance().effects.get(item.type_id,{})
	var special := str(effect.get("en" if L10n.is_english() else "zh",""))
	if not special.is_empty(): text += "\n\n" + special
	if not magic.is_empty(): text += "\n\n" + magic
	return text
