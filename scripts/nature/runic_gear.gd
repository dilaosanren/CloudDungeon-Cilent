# Weapon.Enchantment / Armor.Glyph rules required by native enchantment stones.
# SPD 4.0.2, GPL-3.0-or-later. No client-side rolls.
extends RefCounted
const T = DungeonTerrain.Type
const CRYSTAL_USES := 5
static var _data: Dictionary = {}

static func catalog() -> Dictionary:
	if _data.is_empty(): _data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/nature/source_catalog.json"))
	return _data

static func glow(item: InventoryItem) -> Color:
	var key: String = item.metadata.get("glyph" if item.category == "armor" else "enchantment", "")
	var family := "armor" if item.category == "armor" else "weapon"
	if item.metadata.get(("glyph" if family == "armor" else "enchantment") + "_curse", false): return Color.BLACK
	return Color(str(catalog().gear[family].get(key, {}).get("glow", {}).get("color", "#ffffff")))

static func enchant(world: WandWorld, item: InventoryItem) -> void:
	enchant_with_rng(item, world.rng)

## Market generation shares the stone's effect pool without a battle world.
static func enchant_with_rng(item: InventoryItem, rng: RandomNumberGenerator) -> void:
	var family := "armor" if item.category == "armor" else "weapon"
	var field := "glyph" if family == "armor" else "enchantment"
	var roll := rng.randf() * 100
	var tier := 0 if roll < 50 else 1 if roll < 90 else 2
	var pool: Array = catalog().pools[family][tier].duplicate()
	pool.erase(item.metadata.get(field, ""))
	var key: String = pool[rng.randi_range(0, pool.size() - 1)]
	item.metadata[field] = key
	item.metadata[field + "_curse"] = false
	for retired in ["crystal_durability", "crystal_uses_left", "crystal_shattered"]: item.metadata.erase(retired)
	if key == "crystal" and item.category == "weapon": item.metadata.crystal_uses_left = CRYSTAL_USES
	var info: Dictionary = catalog().gear[family][key]
	item.metadata[field + "_name"] = info.name
	item.metadata[field + "_description"] = info.description

static func armor_level(actor: WandActor) -> int:
	var armor: InventoryItem = actor.data.get("armor_item")
	if armor == null or actor.has_status("magic_immune"): return -1
	return maxi(0, RingRules.reduced_level(armor.level) if actor.has_status("degrade") else armor.level)

static func glyph(actor: WandActor) -> String:
	var armor: InventoryItem = actor.data.get("armor_item")
	return "" if armor == null or actor.has_status("magic_immune") else str(armor.metadata.get("glyph", ""))

static func charge(world: WandWorld, actor: WandActor, amount: float) -> void:
	for wand in world.wands.get(actor.get_instance_id(), []): WandState.gain_charge(wand, amount)
	world._emit("scroll_specks", actor.cell, {"actor":actor, "kind":"energy", "count":10, "interval":0.0, "center":true})

static func crystal_uses_left(item: InventoryItem) -> int:
	return clampi(int(item.metadata.get("crystal_uses_left", CRYSTAL_USES)), 0, CRYSTAL_USES)

static func use_crystal(item: InventoryItem, actor: WandActor) -> void:
	if item == null or item.category != "weapon" or item.metadata.get("enchantment") != "crystal": return
	# An image borrows its hero's weapon; it does not spend the real item's uses.
	if actor.species == "mirror_image" or actor.has_status("magic_immune") or (RingRules.fighting_unarmed(actor, true) and not RingRules.unarmed_gets_enchantment(actor, true)): return
	item.metadata.erase("crystal_durability")
	item.metadata.crystal_uses_left = maxi(0, crystal_uses_left(item)-1)
	if item.metadata.crystal_uses_left == 0: item.metadata.crystal_shattered = true

static func shatter_crystal(world: WandWorld, item: InventoryItem, actor: WandActor) -> void:
	if item != null and item.category == "weapon" and item.metadata.get("enchantment") == "crystal" and item.metadata.get("crystal_shattered", false):
		if world.hooks.has("destroy_gear"): world.hooks.destroy_gear.call(actor, item)

static func push(world: WandWorld, actor: WandActor, away_from: int, power: int) -> void:
	if "immovable" in actor.properties: return
	if actor.cell == away_from: return
	var line := Ballistica.new(away_from, actor.cell, Ballistica.STOP_TARGET, world.level)
	if line.path.is_empty(): return
	var trajectory := Ballistica.new(actor.cell, line.path[line.path.size() - 1], Ballistica.PROJECTILE, world.level)
	world.throw_actor(actor, trajectory, power)

static func weapon_proc(world: WandWorld, item: InventoryItem, a: WandActor, d: WandActor, damage: int) -> int:
	if item == null or a.has_status("magic_immune") or (RingRules.fighting_unarmed(a, true) and not RingRules.unarmed_gets_enchantment(a, true)): return damage
	var key: String = str(item.metadata.get("enchantment", ""))
	var lvl := maxi(0, MeleeRules.level(item, a) if item.category == "weapon" else MissileRules.effective_level(item, a))
	var power := RingRules.arcana(a)
	var chance := 0.0
	match key:
		"blazing":
			RingCombat.blazing(a, d, lvl, world.rng)
		"chilling":
			chance = (lvl + 1.0) / (lvl + 2.0) * power
			if world.rng.randf() < chance:
				var duration := minf(3 * maxf(1, chance), 6 * maxf(1, chance) - float(d.statuses.get("chill", 0)))
				if duration > 0: d.status("chill", duration, "add")
				world._emit("nature_particles", d.cell, {"kind":"snow", "count":5})
		"venomous":
			chance = power / 3
			if world.rng.randf() < chance:
				if not d.has_status("poison"): d.data.poison_delay = 3.0
				d.status("poison", maxf(1, chance) * (lvl / 2.0 + 3), "add")
				world._emit("nature_particles", d.cell, {"kind":"poison", "count":5})
		"blocking":
			chance = (lvl + 4.0) / (lvl + 40.0) * power
			if world.rng.randf() < chance:
				var previous := int(a.data.get("block_shield", 0))
				a.data.block_shield_left = 5.0
				a.data.block_shield = maxi(int(a.data.get("block_shield", 0)), roundi(maxf(1, chance) * (2 + lvl)))
				a.announce_value_buff("block_shield", previous, a.data.block_shield)
				world._emit("shielding", a.cell, {"actor":a, "amount":a.data.block_shield})
				world._emit("scroll_specks", a.cell, {"actor":a, "kind":"light", "count":5, "interval":0.0, "center":false})
		"blooming":
			chance = (lvl + 1.0) / (lvl + 3.0) * power
			if world.rng.randf() < chance:
				var amount := (1.5 + 0.1 * lvl) * maxf(1, chance)
				var left := floori(amount) + (1 if world.rng.randf() < fmod(amount, 1) else 0)
				var candidates := world.environment.neighbors(d.cell, true)
				for i in range(candidates.size()-1, 0, -1):
					var index := world.rng.randi_range(0, i)
					var swap: int = candidates[i]; candidates[i] = candidates[index]; candidates[index] = swap
				candidates.erase(a.cell); candidates.push_front(d.cell)
				if world.adjacent(a.cell, d.cell): candidates.append(a.cell)
				for c in candidates:
					if left <= 0: break
					if world.environment.terrain[c] in [T.EMPTY, T.EMBERS, T.EMPTY_DECO, T.GRASS, T.FURROWED_GRASS]:
						world.environment.set_terrain(c, T.HIGH_GRASS)
						world._emit("nature_particles", c, {"kind":"leaf", "count":4})
						left -= 1
		"elastic":
			chance = (lvl + 1.0) / (lvl + 5.0) * power
			if world.rng.randf() < chance: push(world, d, a.cell, roundi(2 * maxf(1, chance)))
		"shocking":
			if world.rng.randf() < power / 3:
				var affected: Array[WandActor] = [d]
				var arcs := []
				var index := 0
				while index < affected.size():
					var from := affected[index]; index += 1
					for other in world.actors:
						if other == a or other in affected or other.hp <= 0 or other.flying: continue
						var reach := 2 if world.environment.terrain[from.cell] == T.WATER else 1
						if world.distance(from.cell, other.cell) <= reach:
							affected.append(other); arcs.append([from.cell, other.cell])
				for other in affected:
					if other != d and other.alignment != a.alignment: other.damage(roundi(damage * 0.5 * maxf(1, power / 3)), "shocking")
				world._emit("nature_lightning", d.cell, {"arcs":arcs})
				world._emit("sound", d.cell, {"sound":"lightning"})
		"vorpal":
			if not d.is_immune("bleeding") and world.rng.randf() < power / 4: a.data.vorpal_power = maxf(1, power / 4)
		"grim":
			if not d.is_immune("grim"): a.data.grim_chance = (0.5 + 0.05 * lvl) * power
		"vampiric":
			chance = (0.05 + 0.25 * float(a.max_hp - a.hp) / a.max_hp) * power
			if a.alignment != d.alignment and world.rng.randf() < chance:
				var healed := a.heal(roundi(damage * 0.5 * maxf(1, chance)))
				if healed > 0: world._emit("healing", a.cell, {"actor":a, "amount":healed})
		"crystal":
			d.damage(ceili(damage * 0.33 * power), "crystal")
			use_crystal(item, a)
	return damage

static func armor_proc(world: WandWorld, a: WandActor, d: WandActor, damage: int) -> int:
	var lvl := armor_level(d)
	if lvl < 0: return damage
	var power := RingRules.arcana(d)
	var chance := 0.0
	match glyph(d):
		"affection":
			chance = (lvl + 3.0) / (lvl + 20.0) * power
			if world.rng.randf() < chance:
				a.status("charm", roundi(20 * maxf(1, chance)), "prolong", {"object":d.get_instance_id()})
				world._emit("scroll_specks", a.cell, {"actor":a, "kind":"heart", "interval":0.2, "count":5, "center":true})
		"entanglement":
			if world.rng.randf() < power / 4:
				d.data.earthroot_armor = maxi(int(d.data.get("earthroot_armor", 0)), roundi((5 + 2 * lvl) * maxf(1, power / 4)))
				d.data.earthroot_pos = d.cell
				d.data.earthroot_block = int((world.environment.scaling_depth + 5) / 2)
				world._emit("nature_particles", d.cell, {"kind":"earth", "interval":0.05, "count":8})
		"potential":
			chance = (lvl + 1.0) / (lvl + 6.0) * power
			if d.species == "hero" and world.rng.randf() < chance: charge(world, d, maxf(1, chance))
		"repulsion":
			chance = (lvl + 1.0) / (lvl + 5.0) * power
			if world.adjacent(a.cell, d.cell) and world.rng.randf() < chance: push(world, a, d.cell, roundi(2 * maxf(1, chance)))
		"thorns":
			chance = (lvl + 2.0) / (lvl + 12.0) * power
			if a.alignment != d.alignment and world.rng.randf() < chance and not a.is_immune("bleeding"):
				a.data.bleed_level = maxf(float(a.data.get("bleed_level", 0)), roundi((4 + lvl) * maxf(1, chance)))
				a.status("bleeding", INF)
		"stone":
			var acc := float(a.effective_accuracy())
			var evade := float(d.base_evasion()) * power
			for spec in [["bless", 1.25], ["hex", 0.8], ["daze", 0.5]]:
				if a.has_status(spec[0]): acc *= spec[1]
				if d.has_status(spec[0]): evade *= spec[1]
			var hit_chance := acc / maxf(1, evade) / 2 if evade >= acc else 1 - evade / maxf(1, acc) / 2
			damage = ceili(damage * clampf((1 + 3 * hit_chance) / 4, 0.25, 1))
		"viscosity":
			var fraction := (lvl + 1.0) / (lvl + 6.0) * power
			var deferred := ceili(damage * fraction) if fraction <= 1 else roundi(damage / fraction)
			var previous := int(d.data.get("deferred_damage", 0))
			if not d.is_immune("deferred_damage"):
				d.data.deferred_damage = previous + deferred
				d.announce_value_buff("deferred_damage", previous, d.data.deferred_damage)
			damage = maxi(0, damage - deferred)
	return damage

static func after_hit(world: WandWorld, item: InventoryItem, a: WandActor, d: WandActor, damage: int, _hp_before: int) -> void:
	if a.data.has("vorpal_power"):
		if d.hp > 0 and not d.is_immune("bleeding"):
			d.data.bleed_level = maxf(float(d.data.get("bleed_level", 0)), float(a.data.vorpal_power) * (2 + damage / 2.0))
			d.status("bleeding", INF)
		a.data.erase("vorpal_power")
	if a.data.has("grim_chance"):
		var chance := float(a.data.grim_chance) * pow(float(d.max_hp - d.hp) / d.max_hp, 2)
		a.data.erase("grim_chance")
		if d.hp > 0 and world.rng.randf() < chance:
			d.damage(roundi(d.hp * d.resistance("grim")), "grim")
			world._emit("scroll_specks", d.cell, {"actor":d, "kind":"shadow_up", "count":5, "interval":0.0, "center":false})
	shatter_crystal(world, item, a)
