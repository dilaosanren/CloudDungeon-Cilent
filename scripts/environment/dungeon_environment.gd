# Environmental fields from Shattered Pixel Dungeon 4.0.2.
# Copyright Oleg Dolya / Evan Debenham. GPL-3.0-or-later; see LICENSE-SPD.txt.
class_name DungeonEnvironment
extends RefCounted

signal terrain_changed(cell: int, tile: int)
signal flags_changed(cell: int, flags: int)
signal reacted(event: Dictionary)
signal advanced(turn: int)

const Rules = preload("res://scripts/dungeon_terrain.gd")
const T = Rules.Type
const Field = preload("res://scripts/environment/environment_field.gd")
const ActorAdapter = preload("res://scripts/environment/environment_actor.gd")
const TYPES = ["fire", "freezing", "web", "toxic_gas", "corrosive_gas", "confusion_gas",
	"paralytic_gas", "stench_gas", "smoke_screen", "electricity", "inferno", "blizzard",
	"storm_cloud", "regrowth", "foliage", "alchemy", "sacrificial_fire", "goo_warn",
	"vault_flame_traps", "water_of_health", "water_of_awareness", "eternal_fire",
	"toxic_gas_seed", "well_id", "pylon_energy", "light_wall", "hallowed_terrain",
	"key_wall", "tengu_fire", "tengu_shocker"]
const DIFFUSING = ["toxic_gas", "corrosive_gas", "confusion_gas", "paralytic_gas",
	"stench_gas", "smoke_screen", "inferno", "blizzard", "storm_cloud", "regrowth"]
const PERSISTENT = ["foliage", "alchemy", "sacrificial_fire", "water_of_health",
	"water_of_awareness", "eternal_fire", "toxic_gas_seed", "well_id", "pylon_energy"]
const FLAG_FIELDS = ["web", "eternal_fire", "light_wall", "key_wall"]
const PRIORITIES = {"web": 1, "goo_warn": -19, "electricity": -21,
	"paralytic_gas": -21, "sacrificial_fire": -21, "tengu_fire": -31, "tengu_shocker": -31}

var size := Vector2i.ZERO
var terrain := PackedInt32Array()
var fields: Dictionary = {}
var actors: Dictionary = {}
var heaps: Dictionary = {}
var plants: Dictionary = {}
## Optional host hooks: well_actor, well_item, spawn_sacrifice_mob, sacrifice_prize,
## can_water, can_change_terrain, hallowed_actor. Hosts may preserve permanent pits.
var hooks: Dictionary = {}
var scaling_depth := 1
var turn := 0
var events: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var _acting := false
var _priority := 1000
var _next_order := 0

func set_map(dimensions: Vector2i, cells: PackedInt32Array, random_seed: int = 1) -> void:
	size = dimensions
	terrain = cells.duplicate()
	fields.clear()
	actors.clear()
	heaps.clear()
	plants.clear()
	events.clear()
	turn = 0
	_next_order = 0
	rng.seed = random_seed

func cell_id(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return -1
	return cell.x + cell.y * size.x

func inside_xy(x: int, y: int) -> bool:
	return x > 0 and y > 0 and x < size.x - 1 and y < size.y - 1

func inside(cell: int) -> bool:
	return cell >= 0 and cell < terrain.size() and inside_xy(cell % size.x, cell / size.x)

func neighbors(cell: int, diagonal: bool = false, center: bool = false) -> Array[int]:
	var result: Array[int] = []
	var x := cell % size.x
	var y := cell / size.x
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				if center:
					result.append(cell)
				continue
			if not diagonal and absi(dx) + absi(dy) != 1:
				continue
			if x + dx >= 0 and y + dy >= 0 and x + dx < size.x and y + dy < size.y:
				result.append(cell + dx + dy * size.x)
	return result

func seed(kind: String, cell: int, amount: int, options: Dictionary = {}) -> EnvironmentField:
	if kind not in TYPES or not inside(cell) or amount <= 0:
		return null
	if not fields.has(kind):
		var created := Field.new(kind, terrain.size())
		created.order = _next_order
		_next_order += 1
		created.next_turn = turn + (1 if _acting and _priority < priority(kind) else 0)
		fields[kind] = created
	var f: EnvironmentField = fields[kind]
	f.seed(cell, amount, size.x)
	if kind == "corrosive_gas":
		if int(options.get("strength", 0)) >= int(f.data.get("strength", 0)):
			f.data["strength"] = int(options.get("strength", 0))
			f.data["source"] = options.get("source", "corrosive_gas")
	else:
		f.data.merge(options, true)
	if kind in FLAG_FIELDS:
		_refresh_flags(cell)
	return f

func amount(kind: String, cell: int) -> int:
	if not fields.has(kind) or cell < 0 or cell >= terrain.size():
		return 0
	return fields[kind].cur[cell]

func clear(kind: String, cell: int = -1) -> void:
	if not fields.has(kind):
		return
	var f: EnvironmentField = fields[kind]
	if cell == -1 or (kind == "eternal_fire" and amount(kind, cell) > 0):
		f.fully_clear()
		if kind in FLAG_FIELDS:
			for c in terrain.size():
				_refresh_flags(c)
	elif cell >= 0 and cell < terrain.size():
		f.clear(cell)
		if kind in FLAG_FIELDS:
			_refresh_flags(cell)

func flags(cell: int) -> int:
	if not inside(cell):
		return Rules.SOLID | Rules.LOS_BLOCKING
	var value: int = Rules.flags_for(terrain[cell])
	if amount("web", cell) > 0:
		value |= Rules.SOLID | Rules.FLAMABLE
	if amount("eternal_fire", cell) > 0:
		value &= ~(Rules.PASSABLE | Rules.AVOID)
	if amount("light_wall", cell) > 0 or amount("key_wall", cell) > 0:
		value |= Rules.SOLID
		value &= ~(Rules.PASSABLE | Rules.AVOID)
	if amount("key_wall", cell) > 0:
		value |= Rules.LOS_BLOCKING
	return value

func _refresh_flags(cell: int) -> void:
	flags_changed.emit(cell, flags(cell))

func is_solid(cell: int) -> bool:
	return (flags(cell) & Rules.SOLID) != 0

func is_flammable(cell: int) -> bool:
	return (flags(cell) & Rules.FLAMABLE) != 0

func blocks_vision(cell: int, viewer_alignment: String = "enemy", viewer_species: String = "") -> bool:
	return (flags(cell) & Rules.LOS_BLOCKING) != 0 or (amount("smoke_screen", cell) > 0
		and viewer_alignment != "ally" and viewer_species != "gnoll_geomancer")

func set_terrain(cell: int, tile: int) -> void:
	if cell < 0 or cell >= terrain.size() or tile < 0 or tile > 39:
		return
	if hooks.has("can_change_terrain") and not hooks.can_change_terrain.call(cell,tile): return
	if terrain[cell] != tile:
		terrain[cell] = tile
		terrain_changed.emit(cell, tile)
	_refresh_flags(cell)

func destroy(cell: int) -> void:
	if terrain[cell] in [T.EMPTY, T.EMPTY_DECO] or (Rules.flags_for(terrain[cell]) & Rules.FLAMABLE) != 0:
		set_terrain(cell, T.EMBERS)
	clear("web", cell)

func set_water(cell: int) -> bool:
	if terrain[cell] not in [T.EMPTY, T.GRASS, T.EMBERS, T.EMPTY_SP, T.HIGH_GRASS,
		T.FURROWED_GRASS, T.EMPTY_DECO, T.SECRET_TRAP, T.TRAP, T.INACTIVE_TRAP]:
		return false
	if hooks.has("can_water") and not hooks.can_water.call(cell):
		return false
	set_terrain(cell, T.WATER)
	_event("water", cell, "storm_cloud")
	return true

func register_actor(actor: RefCounted, cell: int) -> void:
	actor.cell = cell
	actors[cell] = actor
	# Level.occupyCell opens ordinary doors for grounded and flying actors alike.
	if terrain[cell] == T.DOOR: set_terrain(cell, T.OPEN_DOOR)

func close_empty_door(cell: int) -> void:
	if cell < 0 or cell >= terrain.size(): return
	if terrain[cell] == T.OPEN_DOOR and not actors.has(cell) and not heaps.has(cell):
		set_terrain(cell, T.DOOR)

func unregister_actor(actor: RefCounted) -> void:
	var cell: int = actor.cell
	if actors.get(cell) != actor: return
	actors.erase(cell)
	# Door.leave keeps the door open when another occupant or a heap remains.
	close_empty_door(cell)

## Invoke after movement, as Level.occupyCell does. Hard presses destroy webs without rooting.
func enter_cell(actor: RefCounted, cell: int, hard_press: bool = false) -> void:
	if actor.cell != cell: unregister_actor(actor)
	register_actor(actor, cell)
	if amount("web", cell) > 0 and (hard_press or not actor.is_immune("web")):
		clear("web", cell)
		if not hard_press:
			_status(actor, "roots", 5.0, "web")
	if terrain[cell] == T.WATER and not actor.flying:
		actor.statuses.erase("burning")

func priority(kind: String) -> int:
	return int(PRIORITIES.get(kind, -10))

## Hosts with a complete actor scheduler should call act_field at each field's priority instead.
## No damage or diffusion runs per frame: one call advances exactly one environmental turn.
func step_turn() -> void:
	events.clear()
	_acting = true
	var done: Dictionary = {}
	while true:
		var candidates: Array = []
		for f in fields.values():
			if not done.has(f.kind) and f.next_turn <= turn:
				candidates.append(f)
		if candidates.is_empty():
			break
		candidates.sort_custom(func(a, b):
			if priority(a.kind) == priority(b.kind):
				return a.order < b.order
			return priority(a.kind) > priority(b.kind))
		var f: EnvironmentField = candidates[0]
		done[f.kind] = true
		_priority = priority(f.kind)
		act_field(f.kind)
	_acting = false
	_priority = 1000
	turn += 1
	advanced.emit(turn)

func act_field(kind: String) -> void:
	if not fields.has(kind):
		return
	var f: EnvironmentField = fields[kind]
	var flag_before := f.cur.duplicate() if kind in FLAG_FIELDS else PackedInt32Array()
	if f.volume <= 0:
		f.fully_clear()
		if kind == "vault_flame_traps":
			_vault_triggers(f)
		return
	if f.right == f.left:
		for c in f.cur.size():
			if f.cur[c] > 0:
				f.include_cell(c, size.x)
	f.volume = 0
	if kind in DIFFUSING:
		f.diffuse(self)
		_evolve_diffusing(f)
	elif kind == "fire":
		_evolve_fire(f)
	elif kind == "electricity":
		_evolve_electricity(f)
	elif kind == "eternal_fire":
		_evolve_eternal(f)
	else:
		_evolve_local(f)
	var previous := f.cur
	f.cur = f.off
	f.off = previous
	if kind in FLAG_FIELDS:
		for c in terrain.size():
			if f.cur[c] != flag_before[c]:
				_refresh_flags(c)
	if kind == "vault_flame_traps":
		_vault_triggers(f)
	if kind == "corrosive_gas" and f.volume == 0:
		f.data["strength"] = 0
		f.data["source"] = ""

func _scan(f: EnvironmentField, callback: Callable) -> void:
	# Original fire/electricity scans columns first and extends its live Rect during the loop.
	var x := f.left - 1
	while x <= f.right:
		var y := f.top - 1
		while y <= f.bottom:
			if inside_xy(x, y):
				callback.call(x + y * size.x)
			y += 1
		x += 1

func _evolve_fire(f: EnvironmentField) -> void:
	_scan(f, func(c: int):
		var value := 0
		if f.cur[c] > 0:
			if amount("freezing", c) > 0:
				clear("freezing", c)
				f.cur[c] = 0
				f.off[c] = 0
				return
			_burn(c)
			value = f.cur[c] - 1
			if value <= 0 and is_flammable(c):
				destroy(c)
		elif amount("freezing", c) == 0 and is_flammable(c):
			for n in neighbors(c):
				if f.cur[n] > 0:
					value = 4
					_burn(c)
					f.include_cell(c, size.x)
					break
		f.off[c] = value
		f.volume += value)

func _evolve_electricity(f: EnvironmentField) -> void:
	_scan(f, func(c: int):
		if f.cur[c] <= 0:
			return
		var power: int = f.cur[c]
		var queue: Array[int] = [c]
		while not queue.is_empty():
			var at: int = queue.pop_back()
			for n in neighbors(at):
				if inside(n) and terrain[n] == T.WATER and f.cur[n] < power:
					f.cur[n] = power
					f.include_cell(n, size.x)
					queue.append(n))
	_scan(f, func(c: int):
		f.off[c] = maxi(0, f.cur[c] - 1)
		f.volume += f.off[c]
		if f.cur[c] <= 0:
			return
		var a: RefCounted = actors.get(c)
		if a != null and not a.is_immune("electricity"):
			if not a.has_status("paralysis"):
				_status(a, "paralysis", f.cur[c], "electricity")
			if f.cur[c] % 2 == 1:
				_damage(a, int(round(rng.randf() * (2.0 + scaling_depth / 5.0))), "electricity")
		_heap(c, "charge", "electricity", {"amount": 0.333}))

func _evolve_diffusing(f: EnvironmentField) -> void:
	_scan(f, func(c: int):
		if f.kind == "regrowth":
			if f.volume <= 0 or f.off[c] <= 0:
				return
			if terrain[c] in [T.EMPTY, T.EMBERS, T.EMPTY_DECO]:
				set_terrain(c, T.HIGH_GRASS if f.cur[c] > 9 and not actors.has(c) else T.GRASS)
			elif terrain[c] in [T.GRASS, T.FURROWED_GRASS] and f.cur[c] > 9 and not actors.has(c) and not plants.has(c):
				set_terrain(c, T.HIGH_GRASS)
			if actors.has(c) and not actors[c].is_immune("regrowth") and f.off[c] > 1:
				_status(actors[c], "roots", 1.0, "regrowth")
			return
		if f.cur[c] <= 0:
			if f.kind == "inferno" and inside(c) and is_flammable(c) and amount("fire", c) == 0:
				for n in neighbors(c):
					if f.cur[n] > 0:
						self.seed("fire", c, 4)
						break
			return
		var a: RefCounted = actors.get(c)
		match f.kind:
			"toxic_gas":
				if a != null and not a.is_immune(f.kind):
					_damage(a, 1 + int(scaling_depth / 5), f.kind)
			"confusion_gas", "paralytic_gas", "stench_gas":
				if a != null and not a.is_immune(f.kind):
					if f.kind == "stench_gas" and a.species == "hero" and not a.has_status("paralysis"):
						for mob in actors.values():
							if mob.species == "fetid_rat" and mob.hp > 0:
								_event("challenge_penalty", c, f.kind, {"quest": 0, "amount": -100})
								break
					if f.kind != "paralytic_gas" or not a.has_status("paralysis"):
						_status(a, "vertigo" if f.kind == "confusion_gas" else "paralysis",
							5.0 if f.kind == "paralytic_gas" else 2.0, f.kind)
			"corrosive_gas":
				if f.volume > 0 and a != null and not a.is_immune(f.kind):
					_status(a, "corrosion", 2.0, f.kind, "prolong", f.data)
			"inferno", "blizzard":
				clear("fire", c)
				clear("freezing", c)
				var opposing := "blizzard" if f.kind == "inferno" else "inferno"
				if amount(opposing, c) > 0:
					clear(opposing, c)
					f.cur[c] = 0
					f.off[c] = 0
					return
				if f.kind == "inferno":
					_burn(c)
					if is_flammable(c):
						destroy(c)
				else:
					_freeze(c)
					_freeze(c)
			"storm_cloud":
				set_water(c)
				clear("fire", c)
				if a != null and a.fiery and not a.is_immune(f.kind):
					_damage(a, 1 + int(scaling_depth / 5), f.kind)
		return)

func _evolve_local(f: EnvironmentField) -> void:
	if f.kind == "pylon_energy":
		for c in terrain.size():
			if inside(c) and terrain[c] == T.WATER:
				f.cur[c] = maxi(f.cur[c], 1)
				f.include_cell(c, size.x)
	_scan(f, func(c: int):
		var old: int = f.cur[c]
		var value: int = old if f.kind in PERSISTENT else maxi(0, old - 1)
		if f.kind == "key_wall":
			value = mini(value, 9)
		if f.kind == "tengu_fire":
			value = mini(value, 1)
		if old > 0:
			var a: RefCounted = actors.get(c)
			match f.kind:
				"freezing":
					if amount("fire", c) > 0:
						clear("fire", c)
						value = 0
						f.cur[c] = 0
					else:
						_freeze(c)
				"foliage":
					if terrain[c] == T.EMBERS:
						var burning := false
						for n in neighbors(c, true, true):
							burning = burning or amount("fire", n) > 0
						if not burning:
							set_terrain(c, T.GRASS)
					if a != null and a.species == "hero" and a.hp > 0:
						_status(a, "shadows", 2.0, f.kind)
				"toxic_gas_seed":
					if terrain[c] != T.INACTIVE_TRAP:
						value = 0
					elif amount("toxic_gas", c) <= 9 * value:
						self.seed("toxic_gas", c, value)
				"sacrificial_fire":
					for n in neighbors(c, true, true):
						if actors.has(n):
							_status(actors[n], "marked", 2.0, f.kind)
					if not f.data.has("bonus_spawns"):
						f.data["bonus_spawns"] = 3
					if hooks.has("spawn_sacrifice_mob") and int(f.data.bonus_spawns) > 0:
						if hooks.spawn_sacrifice_mob.call(c, 4):
							f.data.bonus_spawns -= 1
				"vault_flame_traps":
					if a != null and not a.is_immune(f.kind):
						_burn(c, f.kind, 4.0)
						if a.species == "hero":
							_event("challenge_penalty", c, f.kind, {"quest": 3, "amount": -100, "allow_freebie": true})
					_event("vault_flame_burst", c, f.kind)
				"pylon_energy":
					if a != null and a.species != "dm300" and not a.flying:
						_damage(a, _normal_int(6, 12), "electricity")
						_event("boss_hazard", c, f.kind)
				"hallowed_terrain":
					if amount("fire", c) > 0:
						value = 0
						f.cur[c] = 0
					else:
						_hallow(f, c, a)
				"tengu_fire":
					if value == 0:
						_burn(c, f.kind)
						if is_flammable(c):
							destroy(c)
						_event("flame_burst", c, f.kind)
				"tengu_shocker":
					if value == 0 and a != null and a.species != "tengu":
						_damage(a, 2 + scaling_depth, "electricity")
						_event("shock_burst", c, f.kind)
		f.off[c] = value
		f.volume += value)
	if f.kind == "hallowed_terrain" and f.volume > 0:
		f.data["furrowed_counter"] = int(f.data.get("furrowed_counter", 0)) + 1

func _evolve_eternal(f: EnvironmentField) -> void:
	var clear_all := [false]
	_scan(f, func(c: int):
		if f.cur[c] > 0:
			if terrain[c] == T.WATER:
				f.cur[c] = 0
				clear_all[0] = true
			clear("fire", c)
			for n in neighbors(c, true, true):
				if amount("freezing", n) > 0:
					clear("freezing", c)
					f.cur[c] = 0
					clear_all[0] = true
				if amount("blizzard", n) > 0:
					clear("blizzard", c)
					f.cur[c] = 0
					clear_all[0] = true
		var affected: bool = f.cur[c] > 0
		if not affected:
			for n in neighbors(c):
				affected = affected or f.cur[n] > 0
		if affected:
			if is_flammable(c) and amount("fire", c) == 0:
				self.seed("fire", c, 4)
			var a: RefCounted = actors.get(c)
			if a != null and not a.is_immune("eternal_fire"):
				_status(a, "burning", 4.0, "eternal_fire")
			if terrain[c] not in [T.EMPTY_SP, T.WATER]:
				_heap(c, "burn", "eternal_fire")
		f.off[c] = f.cur[c]
		f.volume += f.off[c])
	if clear_all[0]:
		f.fully_clear()

func _hallow(f: EnvironmentField, c: int, a: RefCounted) -> void:
	if terrain[c] == T.GRASS and rng.randi_range(0, 9 + 10 * int(f.data.get("talent_points", 0))) == 0 and not plants.has(terrain[c]):
		set_terrain(c, T.FURROWED_GRASS if not f.data.get("regeneration", true)
			or int(f.data.get("furrowed_counter", 0)) > 100 else T.HIGH_GRASS)
	elif terrain[c] in [T.EMPTY, T.EMBERS, T.EMPTY_DECO]:
		set_terrain(c, T.GRASS)
	if a == null:
		return
	if hooks.has("hallowed_actor"):
		hooks.hallowed_actor.call(c, a, f.data)
	elif a.alignment == "ally":
		if a.species == "hero" or a.hp == a.max_hp:
			a.shield += 1
		else:
			a.hp = mini(a.max_hp, a.hp + 1)
	elif not a.flying and not a.has_status("roots"):
		_status(a, "cripple", 1.0, f.kind)

func _vault_triggers(f: EnvironmentField) -> void:
	var triggers: Dictionary = f.data.get("triggers", {})
	var cooldowns: Dictionary = f.data.get("cooldowns", {})
	for c in triggers:
		var entry: Dictionary = triggers[c]
		if int(entry.get("repeat", -1)) < 0:
			continue
		var timer := int(cooldowns.get(c, 0))
		if timer <= 0:
			timer = int(entry.repeat)
		timer -= 1
		cooldowns[c] = timer
		if timer <= 0:
			self.seed("vault_flame_traps", int(c), int(entry.get("amount", 4)))
	f.data["cooldowns"] = cooldowns

func _burn(c: int, source: String = "fire", duration: float = 8.0) -> void:
	var a: RefCounted = actors.get(c)
	if a != null and not a.is_immune("fire") and not (source == "tengu_fire" and a.species == "tengu"):
		_status(a, "burning", duration, source)
	_heap(c, "burn", source)
	if plants.has(c):
		if hooks.has("wither_plant"):
			hooks.wither_plant.call(c)
		else:
			var plant: Variant = plants[c]
			if plant is Object and plant.has_method("wither"): plant.wither()
			plants.erase(c)
		_event("plant_wither", c, source)

func _freeze(c: int) -> void:
	var a: RefCounted = actors.get(c)
	if a != null and not a.is_immune("freezing"):
		if a.has_status("frost"):
			_status(a, "frost", 2.0, "freezing", "add")
		else:
			var existing: bool = a.has_status("chill")
			_status(a, "chill", (5.0 if terrain[c] == T.WATER else 3.0) * a.resistance("chill"),
				"freezing", "add", {"cap": 10.0})
			if existing and float(a.statuses.get("chill", 0)) >= 10 and not a.is_immune("frost"):
				_status(a, "frost", 10.0, "freezing")
	_heap(c, "freeze", "freezing")

func instant_freeze(c: int, ground_duration: float = 10.0, water_duration: float = 30.0) -> void:
	var a: RefCounted = actors.get(c)
	if a != null:
		_status(a, "frost", water_duration if terrain[c] == T.WATER else ground_duration, "freezing")
	clear("fire", c)
	clear("eternal_fire", c)
	_heap(c, "freeze", "freezing")

func _status(a: RefCounted, status_name: String, duration: float, source: String,
	mode: String = "prolong", details: Dictionary = {}) -> void:
	if status_name != "chill" and status_name != "burning" and status_name != "shadows":
		duration *= a.resistance(status_name)
	a.status(status_name, duration, mode, details)
	_event("status", a.cell, source, {"status": status_name, "duration": duration, "mode": mode})

func _damage(a: RefCounted, value: int, source: String) -> void:
	a.damage(value, source)
	_event("damage", a.cell, source, {"amount": value})

func _heap(c: int, action: String, source: String, details: Dictionary = {}) -> void:
	if not heaps.has(c):
		return
	var heap: Object = heaps[c]
	if heap.has_method("environment_react"):
		heap.environment_react(action, details)
	_event("heap_" + action, c, source, details)

func _event(action: String, cell: int, source: String, details: Dictionary = {}) -> void:
	var event := {"action": action, "cell": cell, "source": source, "details": details.duplicate(true)}
	events.append(event)
	reacted.emit(event)

func _normal_int(low: int, high: int) -> int:
	return low + int(floor((rng.randf() + rng.randf()) * (high - low + 1) / 2.0))

## Interaction succeeds only if the host's real hero/item system actually accepted the well.
func use_well(kind: String, c: int, target: Object, is_item: bool = false) -> bool:
	if kind not in ["water_of_health", "water_of_awareness"] or amount(kind, c) <= 0:
		return false
	var hook := "well_item" if is_item else "well_actor"
	var accepted := false
	if hooks.has(hook):
		accepted = hooks[hook].call(kind, target, c)
	elif not is_item and target.has_method("environment_use_well"):
		accepted = target.environment_use_well(kind)
	elif is_item and target.has_method("environment_use_well"):
		accepted = target.environment_use_well(kind)
	if not accepted:
		if is_item:
			var possible: Array[int] = []
			for n in neighbors(c, true):
				if (flags(n) & (Rules.PASSABLE | Rules.AVOID)) != 0:
					possible.append(n)
			if not possible.is_empty():
				_event("well_eject_item", c, kind, {"destination": possible[rng.randi_range(0, possible.size() - 1)]})
		return false
	if kind == "water_of_awareness" and not is_item:
		for cell in terrain.size():
			if terrain[cell] == T.SECRET_DOOR:
				set_terrain(cell, T.DOOR)
			elif terrain[cell] == T.SECRET_TRAP:
				set_terrain(cell, T.TRAP)
	clear(kind, c)
	set_terrain(c, T.EMPTY_WELL)
	_event("well_consumed", c, kind)
	return true

func sacrifice(a: RefCounted) -> bool:
	if a.hp > 0 or not a.has_status("marked"):
		return false
	for c in neighbors(a.cell, true, true):
		if amount("sacrificial_fire", c) <= 0:
			continue
		var xp := 0
		match a.species:
			"hero": xp = 1000000
			"statue", "mimic": xp = 1 + scaling_depth
			"piranha", "bee": xp = 1 + int(scaling_depth / 2)
			"wraith": xp = 1 + int(scaling_depth / 3)
			"swarm": xp = 1 if a.experience == 0 else 1 + a.experience
			_: xp = 1 + a.experience if a.experience > 0 else 0
		if a.species != "hero":
			xp *= rng.randi_range(2, 3)
		if xp == 0:
			return false
		var f: EnvironmentField = fields.sacrificial_fire
		var remaining: int = f.cur[c] - xp
		clear("sacrificial_fire", c)
		if remaining > 0:
			self.seed("sacrificial_fire", c, remaining)
			f.data["bonus_spawns"] = int(f.data.get("bonus_spawns", 3)) + 1
		else:
			if hooks.has("sacrifice_prize"):
				hooks.sacrifice_prize.call(c, f.data)
			_event("sacrifice_prize", c, "sacrificial_fire", f.data)
		_event("sacrifice", c, "sacrificial_fire", {"experience": xp, "species": a.species})
		return true
	return false

func snapshot() -> Dictionary:
	var saved_fields: Array = []
	for f in fields.values():
		saved_fields.append(f.snapshot())
	return {"version": 1, "size": [size.x, size.y], "terrain": Array(terrain),
		"turn": turn, "depth": scaling_depth, "rng_state": str(rng.state),
		"rng_seed": str(rng.seed), "fields": saved_fields, "next_order": _next_order}

## Hosts restore actors/heaps/plants separately; they are not owned by the field system.
func restore(saved: Dictionary) -> bool:
	if int(saved.get("version", 0)) != 1 or not saved.has("size") or not saved.has("terrain"):
		return false
	var dimensions := Vector2i(int(saved.size[0]), int(saved.size[1]))
	if dimensions.x < 3 or dimensions.y < 3 or saved.terrain.size() != dimensions.x * dimensions.y:
		return false
	var restored: Dictionary = {}
	for entry in saved.get("fields", []):
		if entry.kind not in TYPES or entry.cur.size() != saved.terrain.size() or entry.off.size() != entry.cur.size():
			return false
		var f := Field.new(entry.kind, entry.cur.size())
		f.cur = PackedInt32Array(entry.cur)
		f.off = PackedInt32Array(entry.off)
		f.volume = int(entry.volume)
		f.left = int(entry.area[0])
		f.top = int(entry.area[1])
		f.right = int(entry.area[2])
		f.bottom = int(entry.area[3])
		f.data = entry.data.duplicate(true)
		f.next_turn = int(entry.next_turn)
		f.order = int(entry.order)
		restored[f.kind] = f
	set_map(dimensions, PackedInt32Array(saved.terrain))
	fields = restored
	turn = int(saved.turn)
	scaling_depth = int(saved.depth)
	rng.seed = int(saved.rng_seed)
	rng.state = int(saved.rng_state)
	_next_order = int(saved.next_order)
	for c in terrain.size():
		terrain_changed.emit(c, terrain[c])
		_refresh_flags(c)
	return true


