# Source-backed normal wand rules from items/wands/*.java, SPD 4.0.2.
# Copyright Oleg Dolya / Evan Debenham. GPL-3.0-or-later.
class_name WandWorld
extends RefCounted

signal event(value: Dictionary)
const T = DungeonTerrain.Type
const S = preload("res://scripts/wands/wand_state.gd")
const A = preload("res://scripts/wands/wand_actor.gd")
const C = preload("res://scripts/wands/wand_cone.gd")
const MINOR = {"weakness": 2, "vulnerable": 2, "cripple": 1, "blindness": 1, "terror": 1,
	"chill": 0, "ooze": 0, "roots": 0, "vertigo": 0, "drowsy": 0, "bleeding": 0, "burning": 0, "poison": 0}
const MAJOR = {"amok": 3, "slow": 2, "hex": 2, "paralysis": 1, "daze": 0, "dread": 0,
	"charm": 0, "magical_sleep": 0, "soul_mark": 0, "corrosion": 0, "frost": 0, "doom": 0}
var environment: DungeonEnvironment
var level: BallisticLevel
var pathfinder := DungeonPathFinder.new()
var actors: Array[WandActor] = []
var wands: Dictionary = {} # actor instance ID -> currently carried InventoryItems.
var rng := RandomNumberGenerator.new()
var mapped := PackedByteArray()
var visible := PackedByteArray()
var discoverable := PackedByteArray()
var view_distance := 8
var darkness := false
var no_armor := false
## The source wand targets Mob; the PvP authority also permits other heroes.
var transfusion_affects_heroes := false
var events: Array[Dictionary] = []
var hooks: Dictionary = {} # press_cell, freeze_heap, burn_heap, proc, cursed_zap.

func bind(env: DungeonEnvironment, ballistics: BallisticLevel, seed_value: int = 402) -> void:
	environment = env
	level = ballistics
	pathfinder.set_map_size(env.size.x, env.size.y)
	rng.seed = seed_value
	mapped.resize(env.terrain.size())
	visible.resize(env.terrain.size())
	visible.fill(1)
	var visibility := DungeonVisibility.new()
	visibility.set_map(env.size, env.terrain)
	discoverable = visibility.discoverable
	var host_ref: WeakRef = weakref(self)
	env.hooks.wither_plant = func(cell):
		var host = host_ref.get_ref()
		if host != null: host.wither_plant(cell)

func add_actor(actor: WandActor, cell: int) -> void:
	if actor not in actors: actors.append(actor)
	actor.data.rng = rng
	actor.data.combat_world = weakref(self)
	actor.data.in_water = environment.terrain[cell] == T.WATER
	environment.register_actor(actor, cell)
	level.set_character(cell, actor)
	actor.received_damage.connect(_actor_damage.bind(actor))
	actor.status_added.connect(_actor_status.bind(actor))

func _actor_status(effect: String, actor: WandActor) -> void:
	_emit("buff_added", actor.cell, {"actor":actor, "effect":effect})

func _actor_damage(amount: int, source: String, actor: WandActor) -> void:
	_emit("damage", actor.cell, {"actor": actor, "amount": amount, "source": source})

func dispose() -> void:
	for actor in actors:
		var callback := _actor_damage.bind(actor)
		if actor.received_damage.is_connected(callback): actor.received_damage.disconnect(callback)
		var status_callback := _actor_status.bind(actor)
		if actor.status_added.is_connected(status_callback): actor.status_added.disconnect(status_callback)
		actor.owner = null
		actor.data.erase("enemy")
		actor.sprite = null
		actor.equipped_rings.clear()
	actors.clear()
	wands.clear()
	hooks.clear()
	events.clear()
	if environment != null: environment.actors.clear()
	if level != null: level.characters.clear()

func carry(actor: WandActor, items: Array) -> void:
	var carried: Array[InventoryItem] = []
	for item in items:
		if item.type_id in S.TYPES:
			S.initialize(item)
			carried.append(item)
	wands[actor.get_instance_id()] = carried

func actor_at(cell: int) -> WandActor:
	var actor: Variant = environment.actors.get(cell)
	return actor if actor is WandActor and actor.hp > 0 else null

func move(actor: WandActor, destination: int, motion: String = "") -> void:
	var old := actor.cell
	level.set_character(old, null)
	environment.enter_cell(actor, destination)
	_finish_movement(actor, old, destination, motion)

func swap_actors(first: WandActor, second: WandActor) -> void:
	var first_cell := first.cell
	var second_cell := second.cell
	# Char.interact reserves both new positions before either occupy/press
	# callback runs. A sequential pair of move() calls loses one occupant.
	environment.actors.erase(first_cell)
	environment.actors.erase(second_cell)
	level.set_character(first_cell, null)
	level.set_character(second_cell, null)
	first.cell = second_cell
	second.cell = first_cell
	environment.actors[second_cell] = first
	environment.actors[first_cell] = second
	level.set_character(second_cell, first)
	level.set_character(first_cell, second)
	environment.enter_cell(second, first_cell)
	environment.enter_cell(first, second_cell)
	_finish_movement(second, second_cell, first_cell, "swap")
	if first.hp > 0 and first.cell == second_cell:
		_finish_movement(first, first_cell, second_cell, "swap")

func _finish_movement(actor: WandActor, old: int, destination: int, motion: String = "") -> void:
	var trampled := environment.terrain[destination] in [T.HIGH_GRASS, T.FURROWED_GRASS]
	actor.data.in_water = environment.terrain[destination] == T.WATER
	if trampled and not actor.flying:
		# PvP: stepping through tall grass preserves its terrain and LOS blocking.
		_emit("nature_particles", destination, {"kind":"leaf", "count":4})
		var armor: InventoryItem = actor.data.get("armor_item")
		if armor != null and armor.metadata.get("glyph") == "camouflage" and not actor.has_status("magic_immune"):
			var lvl := maxi(0, RingRules.reduced_level(armor.level) if actor.has_status("degrade") else armor.level)
			actor.status("invisibility", roundi((3 + lvl / 2.0) * RingRules.arcana(actor)))
			_emit("sound", destination, {"sound":"meld"})
	if destination != old:
		actor.data.erase("earthroot_armor")
		actor.data.erase("sungrass_heal")
	level.set_character(destination, actor)
	var movement := {"actor": actor, "from": old}
	if not motion.is_empty(): movement.motion = motion
	_emit("move", destination, movement)
	if destination != old: press_after_movement(actor)

## TimeBubble holds plant presses until the bubble expires or an attack dispels it.
func press_after_movement(actor: WandActor) -> void:
	if actor.flying or not environment.plants.has(actor.cell): return
	if actor.statuses.has("time_bubble"):
		var presses: Array = actor.data.get("bubble_presses", [])
		if actor.cell not in presses: presses.append(actor.cell)
		actor.data.bubble_presses = presses
	else:
		activate_plant(actor.cell, actor)

func release_bubble_presses(actor: WandActor) -> void:
	if actor.statuses.has("time_bubble") or not actor.data.has("bubble_presses"): return
	var presses: Array = actor.data.bubble_presses
	actor.data.erase("bubble_presses")
	for cell in presses:
		if environment.plants.has(cell): activate_plant(int(cell), actor_at(int(cell)))

func _emit(action: String, cell: int, details: Dictionary = {}) -> void:
	var e := {"action": action, "cell": cell}
	e.merge(details)
	events.append(e)
	event.emit(e)

func distance(a: int, b: int) -> float:
	return Vector2(level.cell_coords(a)).distance_to(Vector2(level.cell_coords(b)))

func adjacent(a: int, b: int) -> bool:
	var delta := level.cell_coords(a) - level.cell_coords(b)
	return maxi(absi(delta.x), absi(delta.y)) == 1

func effective_level(item: InventoryItem, caster: WandActor) -> int:
	var lvl := S.level(item)
	if caster.has_status("degrade") and lvl > 0: lvl = roundi(sqrt(2 * (lvl - 1)) + 1)
	if caster.has_status("scroll_empower"): lvl += 2
	if item.charges == 1: lvl += int(caster.data.get("desperate_power", 0))
	if caster.has_status("wild_magic"):
		var points := int(caster.data.get("wild_power", 0))
		var bonus := int((4 + points + rng.randi_range(0, 1)) / 2)
		if lvl < 3 + points: lvl = mini(lvl + bonus, 3 + points)
	if caster.has_status("magic_charge"): lvl = maxi(lvl, int(caster.data.get("magic_charge_level", 0)))
	return lvl

# Prepare is side-effect-free except for source Wild Magic RNG. A rejected cast costs no turn/charge.
func prepare(item: InventoryItem, caster: WandActor, target: int) -> Dictionary:
	if item == null or item.type_id not in S.TYPES: return {"error": "不是法杖"}
	S.initialize(item)
	if caster.hp <= 0 or not level.inside_map(target): return {"error": "目标无效"}
	if caster.has_status("magic_immune"): return {"error": "魔法免疫状态无法施法"}
	var cost := S.cost(item, caster.has_status("wild_magic"))
	if item.charges < cost and not caster.has_status("wild_magic"): return {"error": "法杖能量不足"}
	var flags := Ballistica.MAGIC_BOLT
	match item.type_id:
		"WandOfDisintegration", "WandOfFireblast", "WandOfRegrowth": flags = Ballistica.WONT_STOP
		"WandOfCorrosion": flags = Ballistica.STOP_TARGET | Ballistica.STOP_SOLID
		"WandOfBlastWave": flags = Ballistica.PROJECTILE
		"WandOfWarding": flags = Ballistica.STOP_TARGET if visible[target] else Ballistica.PROJECTILE
	if item.cursed: flags = Ballistica.MAGIC_BOLT
	var bolt := Ballistica.new(caster.cell, target, flags, level)
	if target == caster.cell or bolt.collision_pos == caster.cell: return {"error": "不能瞄准自己"}
	if item.cursed and not hooks.has("cursed_zap"):
		return {"error": "诅咒随机施法需要宿主的 cursed_zap 接口；本演示使用正常法杖"}
	var p := {"item": item, "caster": caster, "target": target, "bolt": bolt,
		"type": item.type_id, "level": effective_level(item, caster), "cost": cost, "resolved": false}
	if item.type_id == "WandOfWarding" and not item.cursed:
		var current := 0
		for a in actors:
			if a.hp > 0 and a.species == "ward" and a.owner == caster: current += int(a.data.tier)
		var maximum := 0
		for wand in wands.get(caster.get_instance_id(), [item]):
			if wand.type_id == "WandOfWarding": maximum += 2 + S.level(wand)
		p.ward_available = current < maximum
		var a := actor_at(target)
		if current >= maximum and (a == null or a.species != "ward" or a.data.tier <= 3):
			return {"error": "哨卫能量已满（%d/%d）" % [current, maximum]}
	if item.type_id in ["WandOfFireblast", "WandOfRegrowth"] and not item.cursed:
		var fire: bool = item.type_id == "WandOfFireblast"
		p.cone = C.new(bolt, (3 if fire else 2) + 2 * cost,
			(30 if fire else 20) + (20 if fire else 10) * cost,
			Ballistica.STOP_TARGET | Ballistica.STOP_SOLID | (Ballistica.IGNORE_SOFT_SOLID if fire else 0), level)
	if item.type_id == "WandOfLightning" and not item.cursed:
		p.affected = []
		p.arcs = [[caster.cell, bolt.collision_pos]]
		var first := actor_at(bolt.collision_pos)
		if first != null:
			p.affected.append(first)
			_arc(first, p)
	return p

func _arc(actor: WandActor, p: Dictionary) -> void:
	var reach := (2 if environment.terrain[actor.cell] == T.WATER else 1) + (1 if p.caster.has_status("lightning_charge") else 0)
	pathfinder.build_distance_map(actor.cell, non_solid_mask(), reach)
	var targets: Array[WandActor] = []
	# Source scans cells in array order before recursively creating arcs.
	for cell in pathfinder.size:
		if pathfinder.distance[cell] == DungeonPathFinder.INFINITE: continue
		var other := actor_at(cell)
		if other != null and other not in p.affected and not (other == p.caster and pathfinder.distance[cell] > 1): targets.append(other)
	p.affected.append_array(targets)
	for other in targets:
		p.arcs.append([actor.cell, other.cell])
		_arc(other, p)

func non_solid_mask() -> PackedByteArray:
	var mask := PackedByteArray(); mask.resize(environment.terrain.size())
	for i in mask.size(): mask[i] = int(not environment.is_solid(i))
	return mask

func roll(p: Dictionary, lvl: int = -999) -> int:
	var bounds := S.damage_range(p.type, p.level if lvl == -999 else lvl, p.cost)
	var damage := bounds.x if bounds.x == bounds.y else S.normal_int(rng, bounds.x, bounds.y)
	var caster: WandActor = p.caster
	if caster.has_status("wand_empower"):
		damage += int(caster.data.get("wand_empower_damage", 0))
		caster.data.wand_empower_left = int(caster.data.get("wand_empower_left", 1)) - 1
		if caster.data.wand_empower_left <= 0: caster.statuses.erase("wand_empower")
	return damage

func _proc(a: WandActor, p: Dictionary) -> void:
	if a != p.caster and a.alignment != p.caster.alignment: a.interrupt_healing()
	if hooks.has("proc"): hooks.proc.call(a, p.level, p.cost, p.caster)
	var points := int(p.caster.data.get("arcane_vision", 0))
	if points > 0: a.status("awareness", 5 + 5 * points)
	if p.caster.data.get("warlock", false) and a != p.caster:
		if rng.randf() > pow(0.92, p.level * p.cost + 1) - 0.07: a.status("soul_mark", 10 + p.level)

func _press(cell: int) -> void:
	if not environment.inside(cell): return
	_emit("press", cell)
	if hooks.has("press_cell"): hooks.press_cell.call(cell)
	if environment.terrain[cell] == T.DOOR: environment.set_terrain(cell, T.OPEN_DOOR)
	if environment.plants.has(cell): activate_plant(cell, actor_at(cell))

func _heap(cell: int, action: String) -> void:
	if hooks.has(action + "_heap"): hooks[action + "_heap"].call(cell)
	if environment.heaps.has(cell):
		environment.heaps[cell]["wand_" + action] = true
		_emit(action + "_heap", cell)

func resolve(p: Dictionary) -> bool:
	if p.has("error") or p.get("resolved", false): return false
	p.resolved = true
	var item: InventoryItem = p.item
	var caster: WandActor = p.caster
	var bolt: Ballistica = p.bolt
	var cell := bolt.collision_pos
	var a := actor_at(cell)
	p.hit_actor = a
	if item.cursed:
		hooks.cursed_zap.call(p, self)
	else:
		match p.type:
			"WandOfMagicMissile":
				if a != null:
					_proc(a, p)
					a.damage(roll(p), p.type)
					for wand in wands.get(caster.get_instance_id(), []):
						if effective_level(wand, caster) < p.level or caster.has_status("magic_charge"):
							caster.status("magic_charge", 4)
							if int(caster.data.get("magic_charge_level", 0)) < p.level:
								caster.data.magic_charge_level = p.level
								caster.data.magic_charge_wand = item.uid
							break
				else: _press(cell)
			"WandOfFrost": _frost(p, a)
			"WandOfLightning": _lightning(p)
			"WandOfDisintegration": _disintegrate(p)
			"WandOfFireblast": _fireblast(p)
			"WandOfCorrosion":
				environment.seed("corrosive_gas", cell, 50 + 10 * p.level, {"strength": 2 + p.level, "source": "WandOfCorrosion"})
				for n in environment.neighbors(cell, true, true):
					var other := actor_at(n)
					if other != null: _proc(other, p)
				if a == null: _press(cell)
			"WandOfBlastWave": _blast(p)
			"WandOfLivingEarth": _earth(p, a)
			"WandOfPrismaticLight": _prismatic(p, a)
			"WandOfWarding": _ward(p, a)
			"WandOfTransfusion": _transfusion(p, a)
			"WandOfCorruption":
				if a != null and a.species != "hero":
					_corruption(p, a)
					_proc(a, p)
				elif a == null: _press(cell)
			"WandOfRegrowth": _regrowth(p)
	S.used(item, p.cost)
	if caster.has_status("magic_charge") and caster.data.get("magic_charge_wand", "") != item.uid and p.level > S.level(item):
		caster.statuses.erase("magic_charge")
		caster.data.magic_charge_level = 0
	else:
		if caster.has_status("scroll_empower"):
			caster.data.scroll_empower_left = int(caster.data.get("scroll_empower_left", 3)) - 1
			if caster.data.scroll_empower_left <= 0: caster.statuses.erase("scroll_empower")
	_emit("cast", cell, {"item": item, "caster": caster, "plan": p})
	_cleanup()
	return true

func _frost(p: Dictionary, a: WandActor) -> void:
	var bolt: Ballistica = p.bolt
	_heap(bolt.collision_pos, "freeze")
	environment.clear("fire", bolt.collision_pos)
	environment.clear("eternal_fire", bolt.collision_pos)
	if bolt.path.size() > bolt.dist + 1: environment.clear("eternal_fire", bolt.path[bolt.dist + 1])
	if a == null: _press(bolt.collision_pos); return
	var damage := roll(p)
	if a.has_status("frost"): return
	if a.has_status("chill"): damage = roundi(damage * pow(0.9333, minf(10, a.statuses.chill)))
	_proc(a, p)
	a.damage(damage, p.type)
	if a.hp > 0: a.status("chill", ((4 if environment.terrain[a.cell] == T.WATER else 2) + p.level) * a.resistance("chill"), "add")

func _lightning(p: Dictionary) -> void:
	var affected: Array = p.affected.filter(func(a): return not a.has_status("lightning_charge") and (a == p.caster or a.alignment != p.caster.alignment or a.cell == p.bolt.collision_pos))
	var multiplier := 0.4 + 0.6 / maxf(1, affected.size())
	if environment.terrain[p.bolt.collision_pos] == T.WATER: multiplier = 1
	for a in affected:
		_proc(a, p)
		a.damage(roundi(roll(p) * multiplier * (0.5 if a == p.caster else 1)), p.type)

func _disintegrate(p: Dictionary) -> void:
	var chars: Array[WandActor] = []
	var passed := 2
	var bonus := 0
	for cell in p.bolt.sub_path(1, mini(6 + 2 * p.level, p.bolt.dist)):
		var a := actor_at(cell)
		if a != null:
			bonus += int(passed / 3)
			passed %= 3
			if not (a.data.get("passive", false) and not mapped[cell]): chars.append(a)
		if environment.is_solid(cell): passed += 1
		if environment.is_flammable(cell): environment.destroy(cell)
		_emit("burst", cell, {"kind": "purple", "count": rng.randi_range(1, 2)})
	for a in chars:
		_proc(a, p)
		a.damage(roll(p, p.level + chars.size() - 1 + bonus), p.type)

func _fireblast(p: Dictionary) -> void:
	var nearby: Array[int] = []
	for cell in p.cone.cells:
		if cell == p.caster.cell: continue
		if environment.terrain[cell] == T.DOOR: environment.set_terrain(cell, T.OPEN_DOOR)
		if adjacent(p.caster.cell, cell) and not (environment.is_flammable(cell) or environment.is_solid(cell)):
			nearby.append(cell)
			_heap(cell, "burn")
		else: environment.seed("fire", cell, 1 + p.cost)
		var a := actor_at(cell)
		if a != null:
			_proc(a, p)
			a.damage(roll(p), p.type)
			if a.hp > 0:
				a.status("burning", 8)
				if p.cost == 2: a.status("cripple", 4)
				if p.cost == 3: a.status("paralysis", 4)
	if p.cone.cells.is_empty(): nearby.append(p.caster.cell)
	for cell in nearby:
		for n in environment.neighbors(cell, true):
			if distance(n, p.bolt.collision_pos) < distance(cell, p.bolt.collision_pos) and environment.is_flammable(n) and environment.amount("fire", n) == 0:
				environment.seed("fire", n, 1 + p.cost)

func _blast(p: Dictionary) -> void:
	var center: int = p.bolt.collision_pos
	_emit("blast", center)
	for n in environment.neighbors(center, true, true): _press(n)
	for n in environment.neighbors(center, true):
		var a := actor_at(n)
		if a == null: continue
		_proc(a, p)
		if a.alignment != "ally": a.damage(roll(p), p.type)
		var delta := level.cell_coords(n) - level.cell_coords(center)
		var to := level.cell_id(level.cell_coords(n) + delta)
		if level.contains(to): throw_actor(a, Ballistica.new(n, to, Ballistica.MAGIC_BOLT, level), roundi(1.5 + p.level / 2.0))
	var a := actor_at(center)
	if a != null:
		_proc(a, p)
		a.damage(roll(p), p.type)
		if p.bolt.path.size() > p.bolt.dist + 1:
			throw_actor(a, Ballistica.new(center, p.bolt.path[p.bolt.dist + 1], Ballistica.MAGIC_BOLT, level), p.level + 3)

func throw_actor(a: WandActor, trajectory: Ballistica, power: int) -> void:
	if "boss" in a.properties: power = int((power + 1) / 2)
	if a.has_status("roots") or "immovable" in a.properties: return
	var dist := mini(trajectory.dist, power)
	var collided := dist == trajectory.dist
	if "large" in a.properties:
		for i in range(1, dist + 1):
			for n in environment.neighbors(trajectory.path[i], true, true):
				if environment.is_solid(n): dist = i - 1; collided = true; break
			if collided: break
	if actor_at(trajectory.path[dist]) != null: dist -= 1; collided = true
	if dist <= 0: return
	move(a, trajectory.path[dist], "push")
	if collided:
		a.damage(S.normal_int(rng, dist, 2 * dist), "knockback")
		if a.hp > 0: a.status("paralysis", 1 + dist / 2.0)
	fall_into_chasm(a)

func fall_into_chasm(a: WandActor) -> void:
	if a.hp > 0 and environment.terrain[a.cell] == T.CHASM and not a.flying:
		a.damage(a.hp+a.shield,"fall")
		_emit("fall",a.cell,{"actor":a})

func _earth(p: Dictionary, target: WandActor) -> void:
	var guardian: WandActor
	for a in actors:
		if a.species == "guardian" and a.hp > 0 and a.owner == p.caster: guardian = a; break
	var damage := roll(p)
	var armor := damage
	if (guardian == null or target != guardian) and (target == null or target.alignment == "ally" or (target.alignment == "neutral" and target.species != "mimic")): armor = 0
	if guardian == null and armor > 0: p.caster.add_rock(p.level, armor)
	if target == guardian and guardian != null:
		_guardian_info(guardian, p.level, armor)
		_proc(guardian, p)
		return
	if target != null:
		_proc(target, p)
		target.damage(damage, p.type)
	else: _press(p.bolt.collision_pos)
	if guardian != null:
		_guardian_info(guardian, p.level, armor)
		if target != null: guardian.data.enemy = target
		return
	if int(p.caster.data.get("rock_armor", 0)) >= 8 + 4 * int(p.caster.data.get("rock_level", 0)):
		var cell: int = p.bolt.collision_pos
		if target != null:
			cell = -1
			for n in environment.neighbors(p.bolt.collision_pos, true, true):
				if level.passable[n] and actor_at(n) == null and (cell == -1 or distance(n, p.caster.cell) < distance(cell, p.caster.cell)): cell = n
		if cell < 0: return
		guardian = _summon("guardian", p.caster, cell, p.level)
		guardian.max_hp = 16 + 8 * p.level
		guardian.hp = mini(guardian.max_hp, int(p.caster.data.rock_armor))
		guardian.defense_skill = int((p.caster.hero_level + 4) / 2)
		guardian.attack_skill = 2 * guardian.defense_skill + 5
		guardian.data.enemy = target
		p.caster.data.rock_armor = 0

func _guardian_info(a: WandActor, lvl: int, heal_amount: int) -> void:
	if lvl > a.data.level: a.data.level = lvl; a.max_hp = 16 + 8 * lvl
	a.heal(heal_amount)
	_emit("healing", a.cell, {"actor": a, "amount": heal_amount})

func _prismatic(p: Dictionary, a: WandActor) -> void:
	for cell in p.bolt.sub_path(0, p.bolt.dist):
		for n in environment.neighbors(cell, true, true):
			if discoverable[n]: mapped[n] = 1
			if environment.terrain[n] == T.SECRET_DOOR: environment.set_terrain(n, T.DOOR)
			elif environment.terrain[n] == T.SECRET_TRAP: environment.set_terrain(n, T.TRAP)
		_emit("burst", cell, {"kind": "rainbow", "count": rng.randi_range(1, 2)})
	if view_distance < 6: p.caster.status("light", (2 + p.level) if darkness else (10 + 5 * p.level))
	_emit("mapping", p.bolt.collision_pos)
	if a == null: return
	_proc(a, p)
	var damage := roll(p)
	if rng.randi_range(0, maxi(1, 5 + p.level) - 1) >= 3: a.status("blindness", 2 + p.level * 0.333)
	if "undead" in a.properties or "demonic" in a.properties: damage = roundi(damage * 1.333)
	a.damage(damage, p.type)

func _summon(kind: String, caster: WandActor, cell: int, lvl: int) -> WandActor:
	var a := A.new()
	a.species = kind
	a.owner = caster
	a.alignment = "neutral" if kind == "lotus" else caster.alignment
	a.data = {"level": lvl, "tier": 1, "total_zaps": 0}
	a.properties.assign(["inorganic", "immovable"] if kind == "ward" else (["immovable", "static"] if kind == "lotus" else ["inorganic"]))
	if kind == "ward": a.immunities.assign(["sleep", "terror", "dread", "vertigo", "corruption", "charm"]); a.hp = 1; a.max_hp = 1
	if kind == "lotus": a.max_hp = 25 + 3 * lvl; a.hp = a.max_hp
	add_actor(a, cell)
	_emit("summon", cell, {"actor": a})
	return a

func _ward(p: Dictionary, target: WandActor) -> void:
	var cell: int = p.bolt.collision_pos
	if target != null and target.species != "ward":
		if p.bolt.dist > 1: cell = p.bolt.path[p.bolt.dist - 1]
		target = actor_at(cell)
		if target != null and target.species != "ward": _press(p.bolt.collision_pos); return
	if target != null:
		if p.ward_available: upgrade_ward(target, p.level)
		else: heal_ward(target, p.level)
		_emit("ward_update", cell, {"actor": target})
	elif level.passable[cell]: _summon("ward", p.caster, cell, p.level); _press(cell)
	else: _press(cell)

func upgrade_ward(a: WandActor, lvl: int) -> void:
	a.data.level = maxi(lvl, a.data.level)
	match int(a.data.tier):
		3: a.max_hp = 35; a.hp = 15 + (5 - int(a.data.total_zaps)) * 4
		4: a.max_hp = 54; a.hp += 19
		5: a.max_hp = 84; a.hp += 30
		6: heal_ward(a, lvl)
	a.data.tier = mini(6, a.data.tier + 1)
	a.changed.emit()

func heal_ward(a: WandActor, lvl: int, factor: float = 1.0) -> void:
	a.data.level = maxi(lvl, a.data.level)
	var amount := 0
	match int(a.data.tier):
		2: amount = 1
		3: amount = rng.randi_range(1, 2)
		4: amount = 9
		5: amount = 12
		6: amount = 16
	amount = roundi(amount * factor)
	if a.data.tier <= 3: a.data.total_zaps = maxi(0, a.data.total_zaps - amount)
	else: a.heal(amount)
	_emit("healing", a.cell, {"actor": a, "amount": amount})

func _transfusion(p: Dictionary, a: WandActor) -> void:
	for cell in p.bolt.sub_path(0, p.bolt.dist): _emit("burst", cell, {"kind": "blood", "count": 1})
	# Preserve the source Mob-only policy unless the PvP host opts heroes in.
	if a == null or a == p.caster: return
	if a.species == "hero" and not transfusion_affects_heroes: return
	_proc(a, p)
	if a.alignment == "ally" or a.has_status("charm"):
		var self_damage := roundi(p.caster.max_hp * 0.05)
		var amount: int = self_damage + 3 * p.level
		var shielding := maxi(0, a.hp + amount - a.max_hp)
		if shielding > 0: a.barrier(shielding); _emit("shielding", a.cell, {"actor": a, "amount": shielding})
		var healing := a.heal(amount - shielding)
		_emit("healing", a.cell, {"actor": a, "amount": healing})
		if not p.item.metadata.wand_state.free_charge: p.caster.damage(self_damage, p.type)
		else: p.item.metadata.wand_state.free_charge = false
	elif a.alignment != p.caster.alignment or a.species == "mimic":
		p.caster.barrier(5 + p.level)
		_emit("shielding", p.caster.cell, {"actor": p.caster, "amount": 5 + p.level})
		if "undead" not in a.properties:
			a.status("charm", 5, "prolong", {"object": p.caster.get_instance_id(), "ignore_hero_allies": true})

func _corruption(p: Dictionary, a: WandActor) -> void:
	var power: float = 3 + p.level / 3.0
	var depth := environment.scaling_depth
	var resist: float = 1 + float(a.data.get("ascension_resist", a.experience))
	match a.species:
		"mimic", "statue": resist = 1 + depth
		"piranha", "bee": resist = 1 + depth / 2.0
		"wraith": resist = (1 + depth / 4.0) / 5.0
		"swarm": resist = 1 + float(a.data.get("ascension_resist", 3))
	resist *= 1 + 4 * pow(float(a.hp) / a.max_hp, 2)
	for key in a.statuses:
		if key.ends_with("_details"): continue
		if MAJOR.has(key): resist *= 0.5
		elif MINOR.has(key) or key in a.data.get("negative_statuses", []): resist *= 0.75
	if a.has_status("corruption") or a.has_status("doom"): power = resist - 0.001
	if power > resist: corrupt(a, p.caster)
	else: _debuff(a, MAJOR if rng.randf() < power / resist else MINOR, p)

func _debuff(a: WandActor, category: Dictionary, p: Dictionary) -> void:
	var choices: Array[String] = []
	for key in category:
		if not a.has_status(key) and not a.is_immune(key):
			for i in int(category[key]): choices.append(key)
	if not choices.is_empty(): a.status(choices[rng.randi_range(0, choices.size() - 1)], 6 + p.level * 3)
	elif category == MINOR: _debuff(a, MAJOR, p)
	else: corrupt(a, p.caster)

func corrupt(a: WandActor, caster: WandActor) -> void:
	if a.has_status("corruption") or a.has_status("doom"): return
	if a.is_immune("corruption"): a.status("doom", INF); return
	a.hp = a.max_hp
	for key in a.statuses.keys():
		if key != "soul_mark" and (key in MINOR or key in MAJOR or key in a.data.get("negative_statuses", [])):
			if key == "paralysis": a.end_paralysis()
			else: a.statuses.erase(key)
	a.alignment = caster.alignment
	a.owner = caster
	a.status("corruption", INF)
	_emit("healing", a.cell, {"actor": a, "amount": a.max_hp})

func _regrowth(p: Dictionary) -> void:
	var state: Dictionary = p.item.metadata.wand_state
	var limit := S.charge_limit(p.caster.hero_level, S.level(p.item))
	var furrowed: float = (state.over_limit + 1) / 5.0 if state.total_used >= limit else 0.0
	var grass := roundi((3.67 + p.level / 3.0) * p.cost)
	var cells: Array[int] = []
	for cell in p.cone.cells:
		var a := actor_at(cell)
		if environment.terrain[cell] not in [T.EMPTY, T.EMBERS, T.EMPTY_DECO, T.GRASS, T.HIGH_GRASS, T.FURROWED_GRASS] or environment.plants.has(cell) or (a != null and "immovable" in a.properties): continue
		cells.append(cell)
		if environment.terrain[cell] not in [T.HIGH_GRASS, T.FURROWED_GRASS]: environment.set_terrain(cell, T.GRASS)
		if a != null: _proc(a, p); a.status("roots", 4 * p.cost)
	# Fisher-Yates using the simulation RNG, never global/random visual state.
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]; cells[i] = cells[j]; cells[j] = tmp
	if p.cost >= 3:
		var location := -1
		if p.target in cells and actor_at(p.target) == null: location = p.target
		else:
			for i in range(p.bolt.path.size() - 1, -1, -1):
				var c: int = p.bolt.path[i]
				if c in cells and actor_at(c) == null: location = c; break
		if location >= 0: cells.erase(location); _summon("lotus", p.caster, location, p.level)
	for cell in p.bolt.path:
		if grass > 0 and cell in cells:
			environment.set_terrain(cell, T.HIGH_GRASS if rng.randf() > furrowed else T.FURROWED_GRASS)
			grass -= 1
			cells.erase(cell); cells.append(cell)
	# Cloud Dungeon: regrowth no longer creates seedpods or dewcatchers.
	if not cells.is_empty() and rng.randf() > furrowed and rng.randi_range(0, 2) < p.cost:
		_plant(cells.pop_front(), random_seed_kind())
	for cell in cells:
		if grass <= 0 or cell in p.bolt.path: break
		if environment.terrain[cell] == T.HIGH_GRASS: continue
		environment.set_terrain(cell, T.HIGH_GRASS if rng.randf() > furrowed else T.FURROWED_GRASS)
		grass -= 1
	if state.total_used < limit:
		state.over_limit = 0
		state.total_used += p.cost
		if state.total_used > limit: state.over_limit = state.total_used - limit; state.total_used = limit
	else: state.over_limit += p.cost

func random_seed_kind() -> String:
	var kinds := ["sungrass", "fadeleaf", "icecap", "firebloom", "sorrowmoss", "swiftthistle", "blindweed", "stormvine", "earthroot", "mageroyal", "starflower"]
	# Generator.SEED.defaultProbs = {0,2,2,2,2,2,2,2,2,2,2,1}.
	return kinds[int(rng.randi_range(0, 20) / 2)]

func wither_plant(cell: int) -> void:
	if not environment.plants.has(cell): return
	var kind: String = environment.plants[cell].get("kind", "")
	environment.plants.erase(cell)
	_emit("nature_particles", cell, {"kind":"leaf", "count":6})
	if kind == "rotberry":
		_emit("drop", cell, {"kind":"rotberry"})
		return
	for lotus in actors:
		if lotus.species == "lotus" and lotus.hp > 0 and distance(lotus.cell, cell) <= float(lotus.data.get("level", 0)):
			if rng.randf() < minf(1, 0.40 + 0.04 * int(lotus.data.level)): _emit("drop", cell, {"kind":kind})
			break

func _plant(cell: int, kind: String) -> void:
	if environment.plants.has(cell): wither_plant(cell)
	if environment.terrain[cell] in [T.HIGH_GRASS, T.FURROWED_GRASS, T.EMPTY, T.EMBERS, T.EMPTY_DECO]: environment.set_terrain(cell, T.GRASS)
	environment.plants[cell] = {"kind":kind}
	_emit("plant", cell, {"kind":kind})
	_emit("sound", cell, {"sound":"plant"})

func activate_plant(cell: int, a: WandActor) -> void:
	# Movement already skips flying actors. A physical item can still press the
	# ground beneath one, just as Level.pressCell -> Plant.trigger does in SPD.
	if not environment.plants.has(cell): return
	var kind: String = environment.plants[cell].get("kind", "")
	wither_plant(cell)
	_emit("plant_trigger", cell, {"kind": kind, "actor": a})
	if kind in ["dewcatcher", "seedpod"]:
		var count := S.normal_int(rng, 3 if kind == "dewcatcher" else 2, 6 if kind == "dewcatcher" else 4)
		var choices := environment.neighbors(cell, true).filter(func(c): return level.passable[c] and environment.terrain[c] not in [T.ENTRANCE, T.EXIT])
		for i in count:
			if choices.is_empty(): break
			var j := rng.randi_range(0, choices.size() - 1)
			_emit("drop", choices[j], {"kind": "dewdrop" if kind == "dewcatcher" else random_seed_kind()})
			choices.remove_at(j)
		return
	if hooks.has("plant_activate"): hooks.plant_activate.call(kind, cell, a); return
	match kind:
		"rotberry": environment.seed("toxic_gas", cell, 100)
		"firebloom":
			environment.seed("fire", cell, 2)
			_emit("nature_particles", cell, {"kind":"flame", "count":5})
		"icecap":
			for n in environment.neighbors(cell, true, true):
				if not environment.is_solid(n): environment._freeze(n)
	if kind == "blindweed": _emit("scroll_specks", cell, {"kind":"light", "interval":0.0, "count":4, "center":false})
	elif kind == "earthroot": _emit("nature_particles", cell, {"kind":"earth", "interval":0.05, "count":8})
	elif kind == "sungrass": _emit("nature_particles", cell, {"kind":"shaft", "interval":0.2, "count":3})
	elif kind == "fadeleaf": _emit("scroll_specks", cell, {"kind":"light", "interval":0.2, "count":3, "center":false})
	if a == null: return
	match kind:
		"blindweed": a.status("blindness", 10); a.status("cripple", 10)
		"mageroyal":
			for key in ["poison", "cripple", "weakness", "vulnerable", "bleeding", "drowsy", "slow", "blindness", "vertigo"]: a.statuses.erase(key)
		"earthroot":
			var previous := int(a.data.get("earthroot_armor", 0)) if a.data.get("earthroot_pos", -1) == cell else 0
			a.data.earthroot_armor = a.max_hp; a.data.earthroot_pos = cell; a.data.earthroot_block = int((environment.scaling_depth + 5) / 2)
			a.announce_value_buff("earthroot_armor", previous, a.data.earthroot_armor)
		"fadeleaf":
			if "immovable" not in a.properties:
				var choices: Array[int] = []
				for c in environment.terrain.size():
					if level.passable[c] and actor_at(c) == null: choices.append(c)
				if not choices.is_empty():
					var old := a.cell
					move(a, choices[rng.randi_range(0, choices.size() - 1)])
					_emit("scroll_teleport", a.cell, {"actor":a, "from":old})
		"sorrowmoss": a.status("poison", 5 + roundi(2 * environment.scaling_depth / 3.0))
		"starflower":
			a.status("bless", 20)
			_emit("scroll_flare", a.cell, {"actor":a, "color":Color.YELLOW, "rays":6})
		"stormvine": a.status("vertigo", 10)
		"sungrass":
			var previous := int(a.data.get("sungrass_heal", 0)) if a.data.get("sungrass_pos", -1) == cell else 0
			a.data.sungrass_heal = int(a.data.get("sungrass_heal", 0)) + a.max_hp; a.data.sungrass_pos = cell
			a.announce_value_buff("sungrass_heal", previous, a.data.sungrass_heal)
		"swiftthistle":
			var previous := float(a.statuses.get("time_bubble", -1))
			a.statuses["time_bubble"] = 7.0
			# A zero-time bubble remains attached until its next spend.
			if previous < 0: a.status_added.emit("time_bubble")

func step_turn() -> void:
	# Buff and ally turns are explicit; frame rate never affects damage/charging.
	for a in actors.duplicate():
		if a.hp <= 0: continue
		a.data.in_water = environment.terrain[a.cell] == T.WATER
		if a.has_status("burning"):
			if a.data.get("burn_acted", false) and environment.terrain[a.cell] == T.WATER and not a.flying: a.statuses.erase("burning")
			else: a.damage(S.normal_int(rng, 1, 3 + int(environment.scaling_depth / 4)), "burning"); a.data.burn_acted = true
		if a.has_status("corrosion"):
			var details: Dictionary = a.statuses.get("corrosion_details", {})
			var strength := float(a.data.get("corrosion_damage", 1))
			strength = maxf(strength, details.get("strength", 1))
			a.damage(int(strength), "corrosion")
			a.data.corrosion_damage = strength + (1 if strength < int(environment.scaling_depth / 2) + 2 else 0.5)
		else: a.data.erase("corrosion_damage")
		if a.has_status("poison") and float(a.data.get("poison_delay", 0)) <= 0: a.damage(int(a.statuses.poison / 3) + 1, "poison")
		if a.data.get("sungrass_heal", 0) > 0:
			if a.cell != a.data.sungrass_pos: a.data.sungrass_heal = 0
			else:
				a.data.sungrass_partial = float(a.data.get("sungrass_partial", 0)) + (40 + a.max_hp) / 150.0
				if a.data.sungrass_partial > 1:
					var heal_amount := int(a.data.sungrass_partial)
					a.data.sungrass_partial -= heal_amount
					a.heal(heal_amount); a.data.sungrass_heal -= heal_amount
					_emit("healing", a.cell, {"actor": a, "amount": heal_amount})
		if a.has_status("corruption"):
			a.data.corrupt_partial = float(a.data.get("corrupt_partial", 0)) + a.max_hp / 100.0
			var damage := int(a.data.corrupt_partial)
			a.data.corrupt_partial -= damage
			if damage > 0: a.damage(damage, "corruption")
		var ordinary_shield: int = a.shield - a.opening_shield()
		if ordinary_shield > 0:
			a.data.barrier_partial = float(a.data.get("barrier_partial", 0)) + minf(1, ordinary_shield / 20.0)
			if a.data.barrier_partial >= 1: a.shield -= 1; a.data.barrier_partial = 0
		var recharge_remainder := minf(1, float(a.statuses.get("recharging", 0)))
		a.advance_statuses()
		for item in wands.get(a.get_instance_id(), []):
			if not a.has_status("magic_immune"):
				S.recharge(item, 1, float(a.data.get("charge_scale", 0.875)), float(a.data.get("energy_multiplier", 1)) * RingRules.energy(a), recharge_remainder, bool(a.data.get("regen_on", true)))
		if a.has_status("paralysis") or a.has_status("frost"): continue
		if a.species == "lotus": a.hp -= 1
		elif a.species == "ward": _ward_turn(a)
		elif a.species == "guardian" and not a.has_status("terror"): _guardian_turn(a)
		a.changed.emit()
	environment.step_turn()
	_cleanup()
	_emit("turn", -1)

func _enemy(a: WandActor, radius: float) -> WandActor:
	var found: WandActor
	var blocking := PackedByteArray()
	blocking.resize(environment.terrain.size())
	for c in blocking.size(): blocking[c] = int(environment.blocks_vision(c, a.alignment, a.species))
	var field_of_view := DungeonShadowCaster.cast(level.cell_coords(a.cell), level.size, blocking, int(radius))
	for other in actors:
		if other.hp <= 0 or other == a or other.species == "lotus" or other.alignment == "neutral": continue
		if other.alignment == a.alignment and not a.has_status("amok") and not other.has_status("aggression"): continue
		if a.is_charmed_by(other): continue
		if not field_of_view[other.cell]: continue
		if other.has_status("invisibility") and not a.has_status("mind_vision"): continue
		if a.species == "ward" and Ballistica.new(a.cell, other.cell, Ballistica.MAGIC_BOLT, level).collision_pos != other.cell: continue
		if found == null or other.has_status("aggression") and not found.has_status("aggression") or other.has_status("aggression") == found.has_status("aggression") and distance(a.cell, other.cell) < distance(a.cell, found.cell): found = other
	return found

func _ward_turn(a: WandActor) -> void:
	var target := _enemy(a, 3 + int(a.data.tier))
	if target == null: return
	_emit("ward_zap", target.cell, {"actor": a, "target": target})
	target.damage(S.normal_int(rng, 2 + a.data.level, 8 + 4 * a.data.level), "wand_magic")
	a.data.total_zaps += 1
	if a.data.tier <= 3:
		if a.data.total_zaps >= 2 * a.data.tier - 1: a.hp = 0
	else: a.damage(a.data.tier + 1, "ward_cost")

## Invoke AFTER the staff's physical hit has resolved, as Frost's VFX-priority buff does.
## These are the thirteen onHit effects; the host owns staff equipment and attack scheduling.
func staff_hit(item: InventoryItem, attacker: WandActor, defender: WandActor, damage: int, staff_level: int = -999) -> void:
	S.initialize(item)
	var lvl := effective_level(item, attacker)
	var multiplier := 1.0 + int(attacker.data.get("empowered_strike", 0)) / 2.0 if attacker.has_status("empowered_strike") else 1.0
	var staff_lvl := lvl if staff_level == -999 else staff_level
	var chance := 0.0
	match item.type_id:
		"WandOfMagicMissile":
			for other in wands.get(attacker.get_instance_id(), []):
				if other != item and other.charges < other.max_charges:
					S.gain_charge(other, 0.5 * multiplier)
					if other.charges >= other.max_charges: other.metadata.wand_state.partial = 0.0
		"WandOfFrost":
			if defender.has_status("chill"):
				chance = (floorf(defender.statuses.chill) - 1) / 9.0 * multiplier
				if rng.randf() < chance: defender.status("frost", roundi(10 * maxf(1, chance)) * defender.resistance("frost"))
		"WandOfLightning":
			chance = (lvl + 1.0) / (lvl + 4.0) * multiplier
			if rng.randf() < chance: attacker.status("lightning_charge", 10 * maxf(1, chance)); _emit("burst", attacker.cell, {"kind": "spark", "count": 10})
		"WandOfDisintegration": pass # reach handled by staff_reach_bonus.
		"WandOfFireblast":
			for n in environment.neighbors(defender.cell, true, true):
				var a := actor_at(n)
				if a != null and a.has_status("burning"): chance += 0.25
				elif environment.amount("fire", n) > 0: chance += 0.05
			chance = minf(1, chance) * multiplier
			if rng.randf() < chance and environment.fields.has("fire"):
				_emit("blast", defender.cell)
				for n in environment.neighbors(defender.cell, true, true):
					if environment.amount("fire", n) > 0: environment.destroy(n); environment.clear("fire", n)
					var a := actor_at(n)
					if a != null:
						a.statuses.erase("burning")
						if a.alignment == "enemy": a.damage(roundi(maxf(1, chance) * S.normal_int(rng, 2 + 2 * lvl, 8 + 4 * lvl)), "wand_magic")
		"WandOfCorrosion":
			chance = (maxi(0, lvl) + 1.0) / (maxi(0, lvl) + 3.0) * multiplier
			if rng.randf() < chance: defender.status("ooze", 20 * maxf(1, chance)); _emit("burst", defender.cell, {"kind": "corrosion", "count": 5})
		"WandOfBlastWave":
			if defender.has_status("paralysis") and not defender.has_status("blast_hit_cooldown"):
				defender.end_paralysis()
				defender.damage(roundi(multiplier * S.normal_int(rng, 8 + 2 * lvl, 12 + 3 * lvl)), "wand_magic")
				_emit("blast", defender.cell)
				defender.status("blast_hit_cooldown", 3)
		"WandOfLivingEarth":
			var guardian: WandActor
			for a in actors:
				if a.species == "guardian" and a.owner == attacker and a.hp > 0: guardian = a; break
			var armor := roundi(damage * 0.33 * multiplier)
			if guardian != null: _guardian_info(guardian, lvl, armor)
			else: attacker.add_rock(lvl, armor)
		"WandOfPrismaticLight": defender.status("cripple", roundi((1 + staff_lvl) * multiplier) * defender.resistance("cripple"))
		"WandOfWarding":
			chance = (maxi(0, staff_lvl) + 1.0) / (maxi(0, staff_lvl) + 5.0) * multiplier
			if rng.randf() < chance:
				for a in actors:
					if a.species == "ward" and a.owner == attacker and a.hp > 0: heal_ward(a, staff_lvl, maxf(1, chance))
		"WandOfTransfusion":
			if defender.has_status("charm") and defender.statuses.get("charm_details", {}).get("object") == attacker.get_instance_id():
				item.metadata.wand_state.free_charge = true
				var amount := roundi(2 * (5 + lvl) * multiplier)
				attacker.barrier(amount)
				_emit("shielding", attacker.cell, {"actor": attacker, "amount": amount})
		"WandOfCorruption":
			chance = (maxi(0, lvl) + 1.0) / (maxi(0, lvl) + 6.0) * multiplier
			if rng.randf() < chance: defender.status("amok", roundi((4 + 2 * maxi(0, lvl)) * maxf(1, chance)) * defender.resistance("amok"))
		"WandOfRegrowth":
			if environment.terrain[attacker.cell] in [T.GRASS, T.HIGH_GRASS, T.FURROWED_GRASS] or environment.terrain[defender.cell] in [T.GRASS, T.HIGH_GRASS, T.FURROWED_GRASS]:
				var healing := roundi(damage * (maxi(0, staff_lvl) + 2.0) / (maxi(0, staff_lvl) + 6.0) / 2.0)
				var previous := int(attacker.data.get("sungrass_heal", 0)) if attacker.data.get("sungrass_pos", -1) == attacker.cell else 0
				attacker.data.sungrass_heal = int(attacker.data.get("sungrass_heal", 0)) + roundi(healing * multiplier)
				attacker.data.sungrass_pos = attacker.cell
				attacker.announce_value_buff("sungrass_heal", previous, attacker.data.sungrass_heal)
	_cleanup()

func staff_reach_bonus(item: InventoryItem, attacker: WandActor) -> int:
	if item.type_id != "WandOfDisintegration" or not attacker.data.get("battlemage", false): return 0
	return roundi(1 + int(attacker.data.get("empowered_strike", 0)) / 2.0) if attacker.has_status("empowered_strike") else 1

func _guardian_turn(a: WandActor) -> void:
	var target := _enemy(a, 8)
	if target == null:
		a.owner.add_rock(a.data.level, a.hp)
		a.hp = 0
		return
	if adjacent(a.cell, target.cell):
		_emit("guardian_attack", target.cell, {"actor": a, "target": target})
		if rng.randf() * a.effective_accuracy() >= rng.randf() * target.effective_evasion():
			target.damage(maxi(0,S.normal_int(rng, 2, 4 + int(environment.scaling_depth / 2))-target.barkskin_defense()), "physical")
			target.data.enemy = a
		else: _emit("dodge", target.cell, {"actor": target})
	else:
		var mask := level.passable.duplicate()
		for other in actors:
			if other.hp > 0: mask[other.cell] = 0
		var step := pathfinder.get_step(a.cell, target.cell, mask)
		if step >= 0 and actor_at(step) == null: move(a, step)

func _cleanup() -> void:
	for a in actors:
		if a.hp > 0: continue
		environment.unregister_actor(a)
		# Never erase a living replacement that has already entered this cell.
		if level.characters.get(a.cell) == a: level.set_character(a.cell, null)
		if not a.data.get("death_reported", false):
			a.data.death_reported = true
			_emit("death", a.cell, {"actor": a})
