# RingOfWealth's per-hero counters, quality rolls, generator pools and second-ring cap.
# GPL-3.0-or-later, supplied SPD 4.0.2 source.
class_name RingLoot
extends RefCounted

static func _normal(rng: RandomNumberGenerator, low: int, high: int) -> int: return WandState.normal_int(rng, low, high)

static func _pick(rng: RandomNumberGenerator, types: Array, weights: Array) -> String:
	var total := 0.0
	for weight in weights: total += float(weight)
	if total <= 0: return ""
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= float(weights[i])
		if roll < 0: return str(types[i])
	return str(types.back())

static func _pool(rng: RandomNumberGenerator, category: String) -> InventoryItem:
	var pool: Dictionary = RingRules.source().pools[category]
	return InventoryCatalog.create(_pick(rng, pool.types, pool.weights))

static func equipment_bonus(actor: WandActor) -> int:
	var bonus := 0
	for ring in actor.equipped_rings:
		if ring.type_id != "RingOfWealth": continue
		var level := RingRules.solo_bonus(ring, actor)
		bonus = level + mini(bonus, 2) if level > bonus else bonus + mini(level, 2)
	return bonus

static func try_bonus_drop(actor: WandActor, tries: int, rng: RandomNumberGenerator, depth: int = 5) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	var bonus := RingRules.bonus(actor, "RingOfWealth")
	if bonus <= 0: return drops
	var state: Dictionary = actor.data.get("ring_state", {})
	actor.data.ring_state = state
	if not state.has("wealth_tries"): state.wealth_tries = _normal(rng, 0, 20)
	if not state.has("wealth_equips"): state.wealth_equips = _normal(rng, 5, 10)
	state.wealth_tries -= tries
	while state.wealth_tries <= 0:
		var drop: Dictionary
		if state.wealth_equips <= 0:
			drop = equipment_drop(actor, equipment_bonus(actor) - 1, rng, depth)
			state.wealth_equips += _normal(rng, 5, 10)
		else:
			drop = consumable_drop(bonus - 1, rng, depth)
			state.wealth_equips -= 1
		drops.append(drop)
		state.wealth_tries += _normal(rng, 0, 20)
	return drops

static func quality(level: int, roll: float) -> int:
	var low := RingRules.f32(RingRules.f32(0.6) - RingRules.f32(RingRules.f32(0.04) * level))
	var mid := RingRules.f32(RingRules.f32(0.9) - RingRules.f32(RingRules.f32(0.02) * level))
	return 1 if roll < low else 2 if roll < mid else 3

static func consumable_drop(level: int, rng: RandomNumberGenerator, depth: int) -> Dictionary:
	var tier := quality(level, rng.randf())
	var item := _low(rng, depth) if tier == 1 else _mid(rng, depth) if tier == 2 else _high(rng, depth)
	return {"item": item, "tier": tier, "bonus": true}

static func _low(rng: RandomNumberGenerator, depth: int) -> InventoryItem:
	match rng.randi_range(0, 3):
		0: return InventoryCatalog.create("Gold", int(rng.randi_range(30 + depth * 10, 60 + depth * 20) / 2))
		1: return _pool(rng, "STONE")
		2: return _pool(rng, "POTION")
	return _pool(rng, "SCROLL")

static func _mid(rng: RandomNumberGenerator, depth: int) -> InventoryItem:
	var choice := rng.randi_range(0, 5)
	match choice:
		0:
			var item := _low(rng, depth); item.quantity *= 2; return item
		1, 2:
			var potion := choice == 1
			var item := _pool(rng, "POTION" if potion else "SCROLL")
			var pairs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/scrolls/source_catalog.json")).exotic_pairs
			return InventoryCatalog.create(pairs[item.type_id])
		3: return InventoryCatalog.create("UnstableBrew" if rng.randi_range(0, 1) == 0 else "UnstableSpell")
		4: return InventoryCatalog.create("Bomb")
	return InventoryCatalog.create("Honeypot")

static func _high(rng: RandomNumberGenerator, depth: int) -> InventoryItem:
	match rng.randi_range(0, 3):
		0:
			var item := _mid(rng, depth)
			if item.type_id == "Bomb":
				item.type_id = "DoubleBomb"; item.title = "双炸弹"; item.visual = "DBL_BOMB"; item.stackable = false
			else: item.quantity *= 2
			return item
		1: return InventoryCatalog.create("StoneOfEnchantment")
		2: return InventoryCatalog.create("PotionOfExperience")
	return InventoryCatalog.create("ScrollOfTransmutation")

static func equipment_drop(actor: WandActor, level: int, rng: RandomNumberGenerator, depth: int) -> Dictionary:
	var tiers: Array = RingRules.source().equipment_tiers
	var floorset := clampi(int((depth + level) / 5), 0, tiers.size() - 1)
	var tier := int(_pick(rng, ["1", "2", "3", "4", "5"], tiers[floorset]))
	var item: InventoryItem
	var kind := rng.randi_range(0, 4)
	match kind:
		0, 1: item = _pool(rng, "WEP_T" + str(tier))
		2: item = InventoryCatalog.create(["ClothArmor", "LeatherArmor", "MailArmor", "ScaleArmor", "PlateArmor"][tier - 1])
		3: item = _pool(rng, "RING")
		4:
			var state: Dictionary = actor.data.ring_state
			if not state.has("wealth_artifacts"):
				state.wealth_artifacts = []
				var pool: Dictionary = RingRules.source().pools.ARTIFACT
				for i in pool.types.size():
					if pool.weights[i] > 0: state.wealth_artifacts.append(pool.types[i])
			if state.wealth_artifacts.is_empty(): item = _pool(rng, "RING")
			else:
				var index := rng.randi_range(0, state.wealth_artifacts.size() - 1)
				item = InventoryCatalog.create(state.wealth_artifacts[index]); state.wealth_artifacts.remove_at(index)
	if item.category != "artifact":
		if item.category == "ring":
			if rng.randi_range(0, 2) == 0: item.level = 1 + int(rng.randi_range(0, 4) == 0)
		elif rng.randi_range(0, 3) == 0: item.level = 1 + int(rng.randi_range(0, 4) == 0)
		item.level = maxi(item.level, int((level + 1) / 2))
	if item.category in ["weapon", "armor"]:
		# Weapon.random / Armor.random can already roll a good enchant/glyph.
		# Wealth preserves it; cursed effects are removed from this reward.
		var natural := rng.randf() >= (0.9 if item.category == "weapon" else 0.85)
		if natural or rng.randi_range(0, 9) < level:
			var groups: Dictionary = RingRules.source().enchantments[item.category]
			var group := _pick(rng, ["common", "uncommon", "rare"], [50, 40, 10])
			var choices: Array = groups[group]
			item.metadata["glyph" if item.category == "armor" else "enchantment"] = str(choices[rng.randi_range(0, choices.size() - 1)]).to_snake_case()
	item.cursed = false
	return {"item": item, "tier": 4 if item.level >= 2 else 3, "bonus": true}
