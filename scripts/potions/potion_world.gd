# Potion.java, twelve base potions and ten exotic potions.
# Adapted from supplied SPD 4.0.2. GPL-3.0-or-later.
class_name PotionWorld
extends WandWorld

const TYPES = ["PotionOfHealing", "PotionOfStrength", "PotionOfExperience", "PotionOfHaste",
	"PotionOfInvisibility", "PotionOfLevitation", "PotionOfMindVision", "PotionOfPurity",
	"PotionOfToxicGas", "PotionOfParalyticGas", "PotionOfLiquidFlame", "PotionOfFrost", "PotionOfSnapFreeze",
	"PotionOfStamina", "PotionOfShielding", "PotionOfShroudingFog", "PotionOfStormClouds", "PotionOfDragonsBreath",
	"PotionOfEarthenArmor", "PotionOfCleansing", "PotionOfCorrosiveGas", "PotionOfMagicalSight"]
const CURE = ["poison", "cripple", "weakness", "vulnerable", "bleeding", "blindness", "drowsy", "slow", "vertigo"]
const SNAP_FREEZE_GROUND := 5.0
const SNAP_FREEZE_WATER := 10.0
const SNAP_FREEZE_ROOTS := 5.0
const STAMINA_DURATION := 20.0
const SHIELDING_AMOUNT := 20
const MIND_VISION_DURATION := 5.0
const MAGICAL_SIGHT_DURATION := 10.0
const MAGICAL_SIGHT_DISTANCE := 6
var elapsed_time := 0.0
var _tick_remainder := 0.0
var no_healing := false

func apply(item: InventoryItem, hero: WandActor) -> bool:
	if item.type_id not in TYPES or hero.hp <= 0: return false
	if item.type_id == "PotionOfDragonsBreath": return false # Requires an aimed drink.
	match item.type_id:
		"PotionOfHealing":
			for effect in CURE: hero.statuses.erase(effect)
			if no_healing: hero.status("poison", 4 + int(hero.hero_level / 2))
			else:
				hero.clear_healing()
				hero.status("healing", 20)
		"PotionOfStrength":
			hero.data.strength = int(hero.data.get("strength", 10)) + 1
			_emit("strength", hero.cell, {"actor": hero, "amount": 1})
		"PotionOfExperience":
			var amount := 5 + 5 * hero.hero_level
			hero.data.exp = int(hero.data.get("exp", 0)) + amount
			_emit("experience", hero.cell, {"actor": hero, "amount": amount})
			while hero.data.exp >= 5 + 5 * hero.hero_level:
				hero.data.exp -= 5 + 5 * hero.hero_level
				if hero.hero_level < 30:
					hero.hero_level += 1
					hero.attack_skill += 1; hero.defense_skill += 1
					hero.data.base_max_hp = int(hero.data.get("base_max_hp", hero.max_hp)) + 5
					hero.update_ring_health(true)
				else: hero.status("bless", 20); hero.data.exp = 0; break
			_emit("flare", hero.cell, {"actor": hero, "rays": 6, "radius": 32, "duration": 2.0, "color": Color.YELLOW})
		"PotionOfHaste":
			hero.status("haste", 10 * hero.resistance("haste"))
			_emit("spell", hero.cell, {"actor": hero, "index": 5, "color": Color.YELLOW})
		"PotionOfStamina":
			hero.status("stamina", STAMINA_DURATION * hero.resistance("stamina"))
			_emit("spell", hero.cell, {"actor":hero, "index":5, "color":Color(0.5,1,0.5)})
		"PotionOfShielding":
			if no_healing: hero.status("poison", 4 + int(hero.hero_level / 2))
			else:
				# Barrier.setShield raises the ordinary pool to at least this
				# amount. It preserves separate opening protection and larger pools.
				hero.barrier(SHIELDING_AMOUNT)
				_emit("shielding", hero.cell, {"actor":hero, "amount":SHIELDING_AMOUNT})
		"PotionOfEarthenArmor": hero.status("barkskin",24)
		"PotionOfCleansing":
			hero.cleanse()
			_emit("flare",hero.cell,{"actor":hero,"rays":6,"radius":32,"duration":2.0,"color":Color("ff4cd2")})
		"PotionOfInvisibility": hero.status("invisibility", 10 * hero.resistance("invisibility")); _emit("sound", hero.cell, {"sound": "meld"})
		"PotionOfLevitation": hero.statuses.erase("roots"); hero.status("levitation", 20 * hero.resistance("levitation")); hero.flying = true
		"PotionOfMindVision":
			hero.status("mind_vision", MIND_VISION_DURATION * hero.resistance("mind_vision"))
			_emit("spell", hero.cell, {"actor": hero, "index": 6, "color": Color(1, 0.77, 0.9)})
		"PotionOfMagicalSight":
			hero.status("magical_sight", MAGICAL_SIGHT_DURATION * hero.resistance("magical_sight"))
			_emit("spell", hero.cell, {"actor":hero, "index":6, "color":Color(1, 0.77, 0.9)})
		"PotionOfPurity":
			hero.status("blob_immunity", 20 * hero.resistance("blob_immunity"))
			_emit("spell", hero.cell, {"actor": hero, "index": 7, "color": Color.WHITE})
		_: shatter(item, hero.cell)
	_emit("drink", hero.cell, {"actor": hero, "item": item})
	hero.changed.emit()
	return true

func on_throw(item: InventoryItem, cell: int) -> void:
	if environment.terrain[cell] == T.WELL or (environment.flags(cell) & DungeonTerrain.PIT) != 0:
		_emit("potion_drop", cell, {"item": item, "into_pit": environment.terrain[cell] == T.CHASM})
		return
	_press(cell)
	shatter(item, cell)

func shatter(item: InventoryItem, cell: int) -> void:
	if item.type_id == "PotionOfPurity":
		for c in reachable(cell, 3):
			for kind in WandActor.BLOB_IMMUNITIES: environment.clear(kind, c)
			if visible[c]: _emit("discover_speck", c, {"count": 2})
	splash(item, cell)
	if visible[cell]: _emit("sound", cell, {"sound": "shatter"})
	match item.type_id:
		"PotionOfCleansing":
			var actor := actor_at(cell)
			if actor != null: actor.cleanse()
		"PotionOfToxicGas", "PotionOfParalyticGas", "PotionOfLevitation":
			var kind := "toxic_gas" if item.type_id == "PotionOfToxicGas" else "paralytic_gas" if item.type_id == "PotionOfParalyticGas" else "confusion_gas"
			environment.seed(kind, cell, 1000)
			if visible[cell]: _emit("sound", cell, {"sound": "gas"})
		"PotionOfLiquidFlame", "PotionOfFrost":
			var flame: bool = item.type_id == "PotionOfLiquidFlame"
			for c in environment.neighbors(cell, true, true):
				if not environment.is_solid(c): environment.seed("fire" if flame else "freezing", c, 2 if flame else 10)
			if flame and visible[cell]: _emit("sound", cell, {"sound": "burning"})
		"PotionOfSnapFreeze":
			# PotionOfSnapFreeze.shatter -> Freezing.affect, not a Freezing blob.
			# Walls exclude only their own cells, matching NEIGHBOURS9 upstream.
			for c in environment.neighbors(cell, true, true):
				if environment.is_solid(c): continue
				environment.instant_freeze(c,SNAP_FREEZE_GROUND,SNAP_FREEZE_WATER)
				var actor := actor_at(c)
				if actor != null: actor.status("roots", SNAP_FREEZE_ROOTS * actor.resistance("roots"))
				if visible[c]: _emit("potion_snow", c, {"count":6, "interval":0.2})
		"PotionOfShroudingFog":
			# Native NEIGHBOURS8: keep 9 * 180 total volume by moving
			# each solid neighbour's share to the center. Smoke is not solid.
			var center_volume := 180
			for c in environment.neighbors(cell,true):
				if environment.is_solid(c): center_volume += 180
				else: environment.seed("smoke_screen",c,180)
			environment.seed("smoke_screen",cell,center_volume)
			if visible[cell]: _emit("sound",cell,{"sound":"gas"})
		"PotionOfCorrosiveGas":
			# Native NEIGHBOURS8, 9 * 25 total volume; solid shares go to center.
			var center_volume := 25
			var strength := 2 + int(environment.scaling_depth / 5)
			for c in environment.neighbors(cell, true):
				if environment.is_solid(c): center_volume += 25
				else: environment.seed("corrosive_gas", c, 25, {"strength":strength})
			environment.seed("corrosive_gas", cell, center_volume, {"strength":strength})
			if visible[cell]: _emit("sound",cell,{"sound":"gas"})
		"PotionOfStormClouds":
			var center_volume := 120
			for c in environment.neighbors(cell,true):
				if environment.is_solid(c): center_volume += 120
				else: environment.seed("storm_cloud",c,120)
			environment.seed("storm_cloud",cell,center_volume)
			if visible[cell]: _emit("sound",cell,{"sound":"gas"})
	_emit("shatter", cell, {"item": item})

func prepare_breath(hero: WandActor, target: int) -> Dictionary:
	if hero == null or hero.hp <= 0: return {"error":"角色已经倒下"}
	if not level.contains(target) or target == hero.cell: return {"error":"请选择喷吐火焰的方向"}
	var bolt := Ballistica.new(hero.cell,target,Ballistica.WONT_STOP,level)
	var cone := WandCone.new(bolt,6,60,Ballistica.STOP_SOLID | Ballistica.STOP_TARGET | Ballistica.IGNORE_SOFT_SOLID,level)
	return {"caster":hero,"bolt":bolt,"cone":cone,"to":target,
		"midpoint":bolt.path[int(mini(bolt.dist,6)/2)]}

func breath_visual(plan: Dictionary) -> Dictionary:
	var rays := []
	for ray in plan.cone.outer_rays: rays.append({"end":ray.collision_pos})
	return {"actor":plan.caster,"to":plan.to,"midpoint":plan.midpoint,"rays":rays}

func resolve_breath(plan: Dictionary) -> void:
	var hero: WandActor = plan.caster
	var nearby: Array[int] = []
	for cell in plan.cone.cells:
		if cell == hero.cell: continue
		if environment.terrain[cell] == T.DOOR: environment.set_terrain(cell,T.OPEN_DOOR)
		if adjacent(hero.cell,cell) and not environment.is_flammable(cell): nearby.append(cell)
		else: environment.seed("fire",cell,5)
		var actor := actor_at(cell)
		if actor != null:
			actor.status("burning",8) # Burning.reignite uses the full native 8t.
			actor.data.burn_acted = false
			actor.status("cripple",5*actor.resistance("cripple"))
	# Native short casts ignite flammable cells beyond a near nonflammable
	# cell using four side neighbours and distance from the caster.
	for cell in nearby:
		for n in environment.neighbors(cell):
			if distance(n,hero.cell) > distance(cell,hero.cell) and environment.is_flammable(n) and environment.amount("fire",n) == 0:
				environment.seed("fire",n,5)

func splash(item: InventoryItem, cell: int) -> void:
	environment.clear("fire", cell)
	var a := actor_at(cell)
	if a != null: a.statuses.erase("burning"); a.statuses.erase("ooze"); a.changed.emit()
	if visible[cell]: _emit("splash", cell, {"actor": a, "item": item, "count": 5})

func reachable(origin: int, reach: int) -> Array[int]:
	pathfinder.build_distance_map(origin, non_solid_mask(), reach)
	var result: Array[int] = []
	for c in pathfinder.size:
		if pathfinder.distance[c] != DungeonPathFinder.INFINITE: result.append(c)
	return result

func step_turn() -> void:
	# Healing resolves before harmful buffs; the shared status tick consumes 1t.
	for a in actors:
		if a.hp <= 0 or not a.has_status("healing"): continue
		if is_finite(float(a.statuses.healing)):
			var gained := a.heal(2)
			if gained > 0: _emit("healing", a.cell, {"actor":a, "amount":gained})
		elif a.data.get("healing_left", 0) > 0:
			# Legacy HealingDart uses its own finite healing pool, not the potion.
			var left := int(a.data.healing_left)
			var heal_amount := clampi(roundi(left * float(a.data.healing_percent)) + int(a.data.healing_flat), 1, left)
			a.heal(heal_amount)
			a.data.healing_left -= heal_amount
			_emit("healing", a.cell, {"actor": a, "amount": heal_amount})
			if a.data.healing_left <= 0: a.statuses.erase("healing")
	super.step_turn()
	for a in actors:
		if a.flying and not a.has_status("levitation") and not a.data.get("naturally_flying", false):
			a.flying = false
			if environment.terrain[a.cell] == T.CHASM: fall_into_chasm(a)
			else: _press(a.cell)
	_emit("potion_turn", -1)
	_cleanup()

func spend(time: float) -> void:
	elapsed_time += time
	_tick_remainder += time
	while _tick_remainder >= 1 - 0.00001:
		_tick_remainder -= 1
		step_turn()

func movement_cost(a: WandActor) -> float:
	var speed := 3.0 if a.has_status("haste") else 1.0
	if a.has_status("stamina"): speed *= 1.5
	speed *= RingRules.haste(a)
	if a.has_status("cripple"): speed /= 2
	if a.has_status("adrenaline"): speed *= 2
	if a.has_status("dread"): speed *= 2
	var armor: InventoryItem = a.data.get("armor_item")
	if armor != null and not a.has_status("magic_immune"):
		var glyph := str(armor.metadata.get("glyph", ""))
		var lvl := maxi(0, RingRules.reduced_level(armor.level) if a.has_status("degrade") else armor.level)
		if glyph == "flow" and environment.terrain[a.cell] == T.WATER: speed *= (2 + 0.5 * lvl) * RingRules.arcana(a)
		elif glyph == "swiftness":
			pathfinder.build_distance_map(a.cell, level.passable, 3)
			var enemy_near := false
			for other in actors:
				if other != a and other.hp > 0 and other.alignment != a.alignment and other.alignment != "neutral" and pathfinder.distance[other.cell] != DungeonPathFinder.INFINITE: enemy_near = true; break
			if not enemy_near: speed *= (1.2 + 0.04 * lvl) * RingRules.arcana(a)
	return 1 / (speed * a.action_time_scale())

func try_move(a: WandActor, target: int) -> Dictionary:
	if a.hp <= 0 or a.has_status("paralysis") or a.has_status("frost") or a.has_status("roots") or a.has_status("magical_sleep"): return {"error": "当前状态无法移动"}
	if not level.inside_map(target) or not adjacent(a.cell, target): return {"error": "一次只能移动相邻一格"}
	var stumbling := a.has_status("vertigo")
	if stumbling:
		var choices := environment.neighbors(a.cell, true)
		target = choices[rng.randi_range(0, choices.size() - 1)]
	var stumbling_into_chasm := stumbling and environment.terrain[target] == T.CHASM
	if actor_at(target) != null or not (level.passable[target] or (a.flying and level.avoid[target]) or stumbling_into_chasm): return {"error": "无法移动到这里"}
	return {"cell": target, "cost": movement_cost(a)}

func vision_options(a: WandActor, alignment: String = "") -> Dictionary:
	return {"alignment":a.alignment if alignment.is_empty() else alignment, "species":a.species,
		"alive":a.hp > 0, "blind":a.has_status("blindness"),
		"sense_distance":MAGICAL_SIGHT_DISTANCE if a.has_status("magical_sight") else 1,
		"reveal_cells":reveal_for(a)}

func reveal_for(a: WandActor) -> Array[int]:
	var result: Array[int] = []
	if not a.has_status("mind_vision"): return result
	for other in actors:
		if other.hp <= 0 or other == a or "object" in other.properties or (other.species == "mimic" and other.alignment == "neutral"): continue
		for c in environment.neighbors(other.cell, true, true):
			if c not in result: result.append(c)
	return result
