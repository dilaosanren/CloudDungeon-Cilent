# Plant.Seed, InventoryStone and the twelve native Runestone classes, SPD 4.0.2.
# GPL-3.0-or-later. All mutations are performed by the authoritative world.
extends RefCounted

const SEEDS = ["SEED_ROTBERRY", "SEED_FIREBLOOM", "SEED_SWIFTTHISTLE", "SEED_SUNGRASS",
	"SEED_ICECAP", "SEED_STORMVINE", "SEED_SORROWMOSS", "SEED_MAGEROYAL",
	"SEED_EARTHROOT", "SEED_STARFLOWER", "SEED_FADELEAF", "SEED_BLINDWEED"]
const STONES = ["StoneOfAggression", "StoneOfAugmentation", "StoneOfFear", "StoneOfBlast",
	"StoneOfBlink", "StoneOfClairvoyance", "StoneOfDeepSleep", "StoneOfDetectMagic",
	"StoneOfEnchantment", "StoneOfFlock", "StoneOfIntuition", "StoneOfShock"]
const PLANT_FRAMES = {"rotberry":0, "firebloom":1, "swiftthistle":2, "sungrass":3, "icecap":4, "stormvine":5, "sorrowmoss":6, "mageroyal":7, "earthroot":8, "starflower":9, "fadeleaf":10, "blindweed":11, "blandfruit":12, "seedpod":13, "dewcatcher":14}
const INVENTORY_STONES = ["StoneOfAugmentation", "StoneOfDetectMagic", "StoneOfEnchantment", "StoneOfIntuition"]
const BLAST_STONE_DAMAGE := 15
const T = DungeonTerrain.Type
const Gear = preload("res://scripts/nature/runic_gear.gd")
static var _catalog: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/nature/source_catalog.json"))
	return _catalog

static func selectable(stone: InventoryItem, target: InventoryItem) -> bool:
	if target == null or target == stone: return false
	match stone.type_id:
		"StoneOfAugmentation", "StoneOfEnchantment":
			return target.category in ["weapon", "armor", "missile"] and target.type_id not in ["Dart"] and not MissileRules.tipped(target)
		"StoneOfDetectMagic":
			return target.category in ["weapon", "armor", "missile", "wand", "ring", "artifact"]
		"StoneOfIntuition":
			return target.category in ["potion", "scroll", "ring"]
	return false

static func use_inventory(world: RingWorld, stone: InventoryItem, hero: WandActor, selected: InventoryItem, choice: String) -> Dictionary:
	if hero.has_status("magic_immune"): return {"error":"魔法免疫时无法使用符石"}
	if not selectable(stone, selected): return {"error":"请选择有效的符石作用物品"}
	var consume := true
	match stone.type_id:
		"StoneOfAugmentation":
			var options: Array = ["evasion", "defense", "none"] if selected.category == "armor" else ["speed", "damage", "none"]
			if choice not in options or choice == selected.metadata.get("augment", "none"): return {"error":"请选择不同的强化属性"}
			selected.metadata.augment = choice
			if selected.category == "missile":
				selected.metadata.augment_damage = 0.7 if choice == "speed" else 1.5 if choice == "damage" else 1.0
				selected.metadata.augment_delay = 2.0 / 3 if choice == "speed" else 5.0 / 3 if choice == "damage" else 1.0
			world._emit("scroll_specks", hero.cell, {"actor":hero, "kind":"up", "interval":0.1, "count":5, "center":false})
		"StoneOfEnchantment":
			Gear.enchant(world, selected)
			world._emit("nature_enchant", hero.cell, {"actor":hero, "item":selected, "color":Gear.glow(selected)})
			world._emit("scroll_specks", hero.cell, {"actor":hero, "kind":"light", "interval":0.1, "count":5, "center":false})
		"StoneOfDetectMagic":
			var bad: bool = selected.cursed or selected.metadata.get("enchantment_curse", false) or selected.metadata.get("glyph_curse", false)
			var good: bool = selected.level > 0 or (selected.metadata.has("enchantment") and not selected.metadata.get("enchantment_curse", false)) or (selected.metadata.has("glyph") and not selected.metadata.get("glyph_curse", false))
			world._emit("nature_notice", hero.cell, {"actor":hero, "text":"同时侦测到正面与负面的魔法。" if good and bad else "侦测到正面的魔法。" if good else "侦测到负面的魔法。" if bad else "没有侦测到魔法。"})
		"StoneOfIntuition":
			var uses := int(stone.metadata.get("intuition_uses", 0)) + 1
			stone.metadata.intuition_uses = uses % 2
			consume = uses >= 2
			world._emit("identification", hero.cell, {"actor":hero})
			world._emit("nature_notice", hero.cell, {"actor":hero, "text":"所有物品均已鉴定。" + ("符石已经耗尽。" if consume else "符石还可以使用一次。")})
	world._emit("nature_operate", hero.cell, {"actor":hero})
	world._emit("sound", hero.cell, {"sound":"read"})
	hero.dispel()
	return {"cost":1.0, "consume":consume, "label":"使用" + stone.title}

static func plant_seed(world: RingWorld, item: InventoryItem, cell: int) -> void:
	# Alchemy, pits and traps retain a physical seed rather than growing a plant.
	if world.environment.terrain[cell] in [T.ALCHEMY, T.TRAP, T.SECRET_TRAP, T.INACTIVE_TRAP] or (world.environment.flags(cell) & DungeonTerrain.PIT) != 0:
		world._emit("nature_drop", cell, {"item":item, "into_pit":(world.environment.flags(cell) & DungeonTerrain.PIT) != 0})
		return
	world._plant(cell, item.type_id.trim_prefix("SEED_").to_lower())
	# Native planting beneath a creature only triggers immediately in a Lotus aura.
	var occupant := world.actor_at(cell)
	if occupant != null:
		for lotus in world.actors:
			if lotus.species == "lotus" and lotus.hp > 0 and world.distance(lotus.cell, cell) <= float(lotus.data.get("level", 0)):
				world.activate_plant(cell, occupant)
				break

static func throw_stone(world: RingWorld, stone: InventoryItem, hero: WandActor, cell: int) -> void:
	if stone.type_id in INVENTORY_STONES or hero.has_status("magic_immune") or (world.environment.flags(cell) & DungeonTerrain.PIT) != 0 and world.actor_at(cell) == null:
		world._emit("nature_drop", cell, {"item":stone, "into_pit":(world.environment.flags(cell) & DungeonTerrain.PIT) != 0})
		return
	var target := world.actor_at(cell)
	match stone.type_id:
		"StoneOfAggression":
			if target != null and "boss" not in target.properties and "miniboss" not in target.properties: target.status("aggression", 20)
			world._emit("scroll_specks", cell, {"kind":"scream", "interval":0.3, "count":3, "center":true})
			world._emit("sound", cell, {"sound":"read"})
		"StoneOfFear":
			if target != null and target.alignment != hero.alignment:
				target.data.fear_source_id = hero.get_instance_id()
				target.status("terror", 20)
			world._emit("nature_flare", cell, {"color":Color.RED, "rays":5, "radius":16, "duration":2.0})
			world._emit("sound", cell, {"sound":"read"})
		"StoneOfDeepSleep":
			# Native StoneOfDeepSleep requires Mob: human heroes are not valid sleepers.
			if target != null and target.species != "hero":
				target.status("magical_sleep", INF)
				world._emit("scroll_specks", cell, {"actor":target, "kind":"note", "interval":0.3, "count":5, "center":true})
			world._emit("sound", cell, {"sound":"lullaby"})
		"StoneOfBlink":
			if "immovable" not in hero.properties and world.level.passable[cell] and world.actor_at(cell) == null:
				var from := hero.cell
				world.move(hero, cell)
				hero.statuses.erase("roots")
				world._emit("scroll_teleport", cell, {"actor":hero, "from":from})
			else: world._emit("nature_notice", cell, {"text":"无法传送到这里。"})
		"StoneOfBlast":
			var mask := world.non_solid_mask()
			for c in mask.size():
				if world.environment.is_flammable(c): mask[c] = 1
			world.pathfinder.build_distance_map(cell, mask, 1)
			var victims: Array[WandActor] = []
			for c in mask.size():
				if world.pathfinder.distance[c] == DungeonPathFinder.INFINITE: continue
				if world.environment.is_flammable(c): world.environment.destroy(c)
				if world.hooks.has("explode_heap"): world.hooks.explode_heap.call(c)
				var victim := world.actor_at(c)
				if victim != null: victims.append(victim)
				world._emit("nature_particles", c, {"kind":"smoke", "count":4})
			for victim in victims:
				var dr := WandState.normal_int(world.rng, int(victim.data.get("armor_min", 0)), int(victim.data.get("armor_max", 0)))
				var damage := maxi(0, BLAST_STONE_DAMAGE - dr)
				if damage > 0: victim.damage(damage, "conjured_bomb")
			world._emit("nature_particles", cell, {"kind":"blast", "count":30})
			world._emit("sound", cell, {"sound":"blast"})
		"StoneOfShock":
			var arcs := []
			var hits := 0
			for c in world.reachable(cell, 2):
				var victim := world.actor_at(c)
				if victim == null: continue
				arcs.append([cell, victim.cell])
				victim.status("paralysis", 1)
				hits += 1
			world._emit("nature_particles", cell, {"kind":"spark", "count":3})
			if hits > 0:
				for wand in world.wands.get(hero.get_instance_id(), []): WandState.gain_charge(wand, 1 + hits)
				world._emit("nature_lightning", cell, {"arcs":arcs})
				world._emit("scroll_specks", hero.cell, {"actor":hero, "kind":"energy", "interval":0.0, "count":10, "center":true})
			world._emit("sound", cell, {"sound":"lightning"})
		"StoneOfFlock":
			for c in world.reachable(cell, 2):
				if not world.level.inside_map(c) or world.actor_at(c) != null or (world.environment.flags(c) & DungeonTerrain.PIT) != 0: continue
				var sheep := WandActor.new()
				sheep.species = "sheep"
				sheep.alignment = "neutral"
				sheep.hp = 1
				sheep.max_hp = 1
				sheep.data.sheep_left = 8 + world.rng.randf_range(-2, 2)
				sheep.properties.assign(["static", "immovable", "inorganic"])
				world.add_actor(sheep, c)
				world._emit("scroll_specks", c, {"kind":"wool", "interval":0.0, "count":4, "center":false})
				world._press(c)
			world._emit("scroll_specks", cell, {"kind":"wool", "interval":0.0, "count":4, "center":false})
			world._emit("sound", cell, {"sound":"puff"})
			world._emit("sound", cell, {"sound":"sheep"})
		"StoneOfClairvoyance":
			var cells: Array[int] = []
			var center := world.level.cell_coords(cell)
			DungeonShadowCaster.initialize_rounding()
			var rounding: PackedInt32Array = DungeonShadowCaster.rounding[20]
			for y in range(maxi(0, center.y - 20), mini(world.level.size.y - 1, center.y + 20) + 1):
				var dy := absi(center.y - y)
				var radius := int(rounding[dy])
				if radius >= dy:
					radius = 20
					while rounding[radius] < rounding[dy]: radius -= 1
				for x in range(maxi(0, center.x - radius), mini(world.level.size.x - 1, center.x + radius) + 1):
					var c := x + y * world.level.size.x
					world.mapped[c] = 1
					cells.append(c)
					if world.environment.terrain[c] == T.SECRET_DOOR: world.environment.set_terrain(c, T.DOOR)
					elif world.environment.terrain[c] == T.SECRET_TRAP: world.environment.set_terrain(c, T.TRAP)
			world._emit("nature_checked", cell, {"cells":cells, "owner":int(hero.data.get("net_owner", -1))})
			world._emit("sound", cell, {"sound":"teleport"})
	if world.actor_at(cell) == null: world._press(cell)
	hero.dispel()
	world._cleanup()
