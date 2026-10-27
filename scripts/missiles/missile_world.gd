# Source MissileWeapon.onThrow/rangedHit, PinCushion and projectile procs.
# GPL-3.0-or-later. PvP host does not impose strength requirements.
class_name MissileWorld
extends RingWorld
const RunicGear = preload("res://scripts/nature/runic_gear.gd")
const POSITIVE = ["haste", "stamina", "adrenaline", "invisibility", "levitation", "mind_vision", "magical_sight", "blob_immunity", "healing", "bless", "recharging", "magic_charge", "enhanced_rings", "cleanse", "invulnerable", "paralysis_resist", "barkskin"]
const NEGATIVE = ["poison", "cripple", "weakness", "vulnerable", "bleeding", "blindness", "drowsy", "slow", "vertigo", "chill", "frost", "burning", "ooze", "corrosion", "paralysis", "hex", "daze", "doom", "magical_sleep", "roots", "degrade", "terror", "dread", "charm", "amok"]
var stuck: Dictionary = {} # actor instance ID -> physical missiles, released on death.
var circles: Array[Dictionary] = []

func attack(attacker: WandActor, defender: WandActor, kind: String = "melee", weapon: InventoryItem = null, armed: bool = true) -> Dictionary:
	if kind != "missile" or not MissileRules.is_weapon(weapon): return super.attack(attacker, defender, kind, weapon, armed)
	if attacker.hp <= 0 or defender.hp <= 0: return {"error": "角色已经倒下"}
	if attacker.has_status("paralysis") or attacker.has_status("frost") or attacker.has_status("magical_sleep"): return {"error": "当前状态无法攻击"}
	if attacker.is_charmed_by(defender): return {"error":"被魅惑时无法直接攻击魅惑施行者"}
	if throw_cell(weapon, attacker, defender.cell) != defender.cell: return {"error": "投掷路径被阻挡"}
	var result := shoot(weapon, attacker, defender)
	result.consumed = result.hit and weapon.type_id != "HeavyBoomerang"
	result.broken = result.hit # Compatibility for the shared throw controller; no wear roll.
	if weapon.type_id == "HeavyBoomerang":
		var returning := weapon.copy_item()
		returning.quantity = 1
		_circle(returning, attacker, defender.cell)
		result.broken = true # The shared controller must not also drop this flight.
	if weapon.type_id == "Shuriken" and not attacker.has_status("shuriken_cooldown"): attacker.status("shuriken_cooldown", 19)
	attacker.dispel(); _cleanup(); return result

func add_actor(a: WandActor, cell: int) -> void:
	a.data.map_width = level.size.x
	super.add_actor(a, cell)

func throw_cell(item: InventoryItem, actor: WandActor, target: int) -> int:
	if MissileRules.effective_enchant(item, actor) == "projecting" and not actor.has_status("magic_immune") and not actor.data.get("inventory_magic_immune", false):
		if (level.passable[target] or level.avoid[target] or actor_at(target) != null) and maxi(absi(level.cell_coords(actor.cell).x - level.cell_coords(target).x), absi(level.cell_coords(actor.cell).y - level.cell_coords(target).y)) <= RingRules.java_round(4 * RingRules.arcana(actor)): return target
	return Ballistica.new(actor.cell, target, Ballistica.PROJECTILE, level).collision_pos

func unseen_player_attack(_attacker: WandActor, _defender: WandActor) -> bool:
	return false # PvP supplies the defender's own live visibility.

func surprised(attacker: WandActor, defender: WandActor, _item: InventoryItem) -> bool:
	return unseen_player_attack(attacker, defender) or attacker.has_status("invisibility") or defender.data.get("surprised", false)

func hit(item: InventoryItem, attacker: WandActor, defender: WandActor, returning: bool = false) -> bool:
	var acc := MissileRules.accuracy(item, attacker, defender, returning)
	if acc == INF: return true
	if surprised(attacker, defender, item): return true
	var a := rng.randf() * attacker.effective_accuracy() * acc
	var d := rng.randf() * defender.effective_evasion()
	for spec in [["bless", 1.25], ["hex", 0.8], ["daze", 0.5]]:
		if attacker.has_status(spec[0]): a *= spec[1]
		if defender.has_status(spec[0]): d *= spec[1]
	return a >= d

func shoot(item: InventoryItem, attacker: WandActor, defender: WandActor, returning: bool = false) -> Dictionary:
	var surprise := surprised(attacker, defender, item)
	var result := {"hit": surprise or hit(item, attacker, defender, returning), "surprise":surprise, "damage": 0, "enchant": false, "cost": MissileRules.delay(item, attacker, defender)}
	if not result.hit:
		_emit("dodge", defender.cell, {"actor": defender})
		return result
	if surprise: _emit("surprise", defender.cell, {"actor":defender})
	var same_team := attacker.alignment == defender.alignment
	if not same_team: defender.interrupt_healing()
	var bounds := MissileRules.damage_range(item, attacker, surprise)
	var damage := S.normal_int(rng, bounds.x, bounds.y)
	if same_team and item.type_id in ["HealingDart", "AdrenalineDart", "HolyDart", "CleansingDart"]: damage = 0
	if item.type_id == "FishingSpear" and defender.species == "piranha": damage = maxi(damage, int(defender.hp / 2))
	var armor := S.normal_int(rng, int(defender.data.get("armor_min", 0)), int(defender.data.get("armor_max", 0)))
	armor += defender.barkskin_defense()
	if not RingRules.fighting_unarmed(defender,defender.data.get("melee_weapon") != null): armor += MeleeRules.defense(defender.data.get("melee_weapon"),defender)
	damage = maxi(0, damage - armor)
	damage = proc(item, attacker, defender, damage)
	damage = RunicGear.weapon_proc(self, item, attacker, defender, damage)
	damage = RunicGear.armor_proc(self, attacker, defender, damage)
	if defender.has_status("vulnerable"): damage = RingRules.java_round(damage * 1.33)
	var before := defender.hp + defender.shield
	defender.damage(damage, "physical")
	RunicGear.after_hit(self, item, attacker, defender, damage, before)
	result.damage = before - defender.hp - defender.shield
	if damage == 0 and item.type_id not in ["HealingDart", "AdrenalineDart", "HolyDart", "CleansingDart"]: _emit("missile_blocked", defender.cell, {"actor": defender})
	var p := MissileRules.profile(item)
	if item.type_id != "ForceCube": _emit("missile_hit_sound", defender.cell, {"sound": p.sound, "pitch": p.pitch})
	defender.changed.emit()
	return result

func proc(item: InventoryItem, a: WandActor, d: WandActor, damage: int) -> int:
	var ally := a.alignment == d.alignment
	var lv := MissileRules.effective_level(item, a)
	match item.type_id:
		"Bolas": d.status("cripple", 5 * d.resistance("cripple"))
		"Tomahawk":
			if not d.is_immune("bleeding"):
				var bleed := (rng.randf() + rng.randf()) / 2 * ((6 + lv) - (3 + lv / 2.0)) + 3 + lv / 2.0
				bleed *= float(item.metadata.get("augment_damage", 1))
				bleed = (rng.randf() + rng.randf()) / 2 * bleed / 2 + bleed / 2
				d.data.bleed_level = maxf(float(d.data.get("bleed_level", 0)), bleed); d.status("bleeding", INF)
		"AdrenalineDart":
			if ally: d.status("adrenaline", 10); return 0
			d.status("cripple", 5 * d.resistance("cripple"))
		"BlindingDart":
			d.status("blindness", 10 * d.resistance("blindness"))
		"ChillingDart":
			d.status("chill", (float(MissileRules.source().durations.chill) if environment.terrain[d.cell] == T.WATER else 6.0) * d.resistance("chill"))
		"CleansingDart":
			if ally:
				d.cleanse(10); return 0
			d.clear_opening_protection()
			for key in POSITIVE: d.statuses.erase(key)
			d.shield = 0; d.data.healing_left = 0; d.flying = bool(d.data.get("naturally_flying", false))
			d.update_ring_health(); d.data.ai_state = "wandering"; _emit("missile_cleansed", d.cell, {"actor": d})
		"DisplacingDart":
			displace(a, d)
		"HealingDart":
			for key in PotionWorld.CURE: d.statuses.erase(key)
			d.data.healing_left = maxi(int(d.data.get("healing_left", 0)), int(0.5 * d.max_hp + 30)); d.data.healing_percent = 0.25; d.data.healing_flat = 0; d.status("healing", INF)
			if ally: return 0
		"HolyDart":
			if ally: d.status("bless", 30); return 0
			if "undead" in d.properties or "demonic" in d.properties:
				d.damage(S.normal_int(rng, 10 + int(environment.scaling_depth / 3), 20 + int(environment.scaling_depth / 3)), "holy_dart")
				_emit("missile_holy", d.cell, {"actor": d, "count": 10 + item.level})
			else: d.status("bless", 30)
		"IncendiaryDart":
			d.status("burning", 8)
		"ParalyticDart":
			d.status("paralysis", 5 * d.resistance("paralysis"))
		"PoisonDart":
			d.status("poison", (3 + int(environment.scaling_depth / 2)) * d.resistance("poison"))
		"RotDart":
			var boss := "boss" in d.properties or "miniboss" in d.properties
			d.status("corrosion", (5 if boss else 10) * d.resistance("corrosion"), "prolong", {"strength": int(environment.scaling_depth / 3) if boss else int(environment.scaling_depth)})
		"ShockingDart":
			d.damage(S.normal_int(rng, 5 + int(environment.scaling_depth / 4), 10 + int(environment.scaling_depth / 4)), "electricity"); _emit("missile_shock", d.cell, {"actor": d})
	if not a.has_status("magic_immune") and not a.data.get("inventory_magic_immune", false) and MissileRules.effective_enchant(item, a) == "blazing":
		var source_level: int = a.data.crossbow.level if MissileRules.dart(item) and a.data.get("crossbow") != null else item.level
		if a.has_status("degrade"): source_level = RingRules.reduced_level(source_level)
		var blazing := RingCombat.blazing(a, d, source_level, rng)
		if blazing.proc: _emit("ring_blazing", d.cell, {"actor": d})
	if hooks.has("missile_proc"): damage = int(hooks.missile_proc.call(item, a, d, damage))
	return damage

func displace(a: WandActor, d: WandActor) -> void:
	if "immovable" in d.properties: return
	pathfinder.build_distance_map(a.cell, non_solid_mask())
	var seen: Array[int] = []; var unseen: Array[int] = []
	for c in pathfinder.size:
		if level.passable[c] and pathfinder.distance[c] >= 8 and pathfinder.distance[c] <= 10 and actor_at(c) == null and ("large" not in d.properties or _open_space(c)):
			if visible[c]: seen.append(c)
			else: unseen.append(c)
	var chosen := -1
	for c in seen if not seen.is_empty() else unseen:
		if chosen < 0 or distance(d.cell, c) < distance(d.cell, chosen): chosen = c
	if chosen >= 0:
		var old := d.cell; move(d, chosen); _emit("scroll_teleport", chosen, {"actor": d, "from": old})
		if not visible[chosen]: a.status("char_awareness", 5); a.data.awareness_target = d.get_instance_id()

func preservation(a: WandActor, target: int) -> float:
	var value := 0.0
	for other in actors:
		if other.species == "lotus" and other.hp > 0 and (distance(other.cell, a.cell) <= other.data.level or distance(other.cell, target) <= other.data.level): value = maxf(value, minf(1, 0.4 + 0.04 * other.data.level))
	return value

func _land(item: InventoryItem, cell: int) -> void:
	if not item.metadata.get("spawned_for_effect", false): _emit("missile_drop", cell, {"item": item})
func _stick(item: InventoryItem, enemy: WandActor, cell: int) -> void:
	if item.metadata.get("spawned_for_effect", false): return
	if enemy != null and enemy.hp > 0 and enemy.alignment != "ally" and (MissileRules.profile(item).sticky or enemy.species == "vault_boss_elemental"):
		var id := enemy.get_instance_id()
		if not stuck.has(id): stuck[id] = []
		for old in stuck[id]:
			if old.similar(item):
				var lost := MissileRules.merge(old, item)
				if lost > 0: _stick(MissileRules.create("Dart", lost), enemy, cell)
				enemy.changed.emit(); return
		stuck[id].append(item); enemy.changed.emit(); _emit("missile_stuck", enemy.cell, {"actor": enemy, "item": item})
	else: _land(item, cell)

func resolve_throw(item: InventoryItem, actor: WandActor, cell: int, _parent: InventoryItem = null, _holster: bool = false) -> Dictionary:
	var victim := actor_at(cell)
	var cost := MissileRules.delay(item, actor, victim)
	var result := {"hit": false, "damage": 0, "enchant": false, "broken": false, "consumed": false, "cost": cost, "cell": cell}
	var cube := item.type_id == "ForceCube" and (environment.terrain[cell] != T.CHASM or victim != null)
	if cube:
		cost = 1.0 if victim == actor else RingCombat.attack_cost(actor, float(item.metadata.get("augment_delay", 1))); result.cost = cost
		var targets: Array[WandActor] = []
		for c in environment.neighbors(cell, true, true):
			_press(c)
			var target := actor_at(c)
			if target != null: targets.append(target)
		targets.sort_custom(func(a, b): return distance(actor.cell, a.cell) > distance(actor.cell, b.cell))
		for target in targets:
			var attack := shoot(item, actor, target); result.hit = result.hit or attack.hit; result.damage += attack.damage
		result.consumed = result.hit
		result.broken = result.consumed
		if not result.consumed: _land(item, cell)
		_emit("blast", cell)
	elif victim != null and victim != actor:
		result.merge(shoot(item, actor, victim), true)
		if result.hit:
			# The detached projectile is consumed even by a fully blocked hit.
			# It never sticks, drops, turns into a dart or starts a return flight.
			if item.type_id == "HeavyBoomerang": _circle(item, actor, cell)
			else:
				result.consumed = true
				result.broken = true
		else:
			if item.type_id == "HeavyBoomerang": _circle(item, actor, cell)
			else: _land(item, cell)
	else:
		if item.type_id == "IncendiaryDart" and (environment.flags(cell) & DungeonTerrain.FLAMABLE) != 0:
			environment.seed("fire", cell, 4)
			result.consumed = true
			result.broken = true
		else: _land(item, cell)
	if item.type_id == "Shuriken" and not actor.has_status("shuriken_cooldown"): actor.status("shuriken_cooldown", 19)
	actor.dispel()
	_cleanup(); _emit("missile_resolved", cell, {"actor": actor, "item": item, "result": result})
	return result

func _circle(item: InventoryItem, actor: WandActor, from: int) -> void:
	circles.append({"item": item, "actor": actor, "from": from, "to": actor.cell, "left": 1})
	_emit("missile_circling", from, {"actor": actor, "item": item})
func finish_return(circle: Dictionary) -> void:
	var item: InventoryItem = circle.item; var actor: WandActor = circle.actor
	var victim := actor_at(circle.to)
	if victim == actor and inventory != null and actor == player:
		if not inventory.collect(item): _land(item, circle.to)
	elif victim != null:
		shoot(item, actor, victim, true)
		_land(item, circle.to) # The return finishes here, without another circle.
	else: _land(item, circle.to)
	_cleanup(); _emit("missile_returned", circle.to, {"actor": actor, "item": item})

func step_turn() -> void:
	for a in actors:
		if a.hp > 0 and a.has_status("bleeding"):
			var level_value := float(a.data.get("bleed_level", 0))
			var damage := RingRules.java_round(level_value)
			if damage > 0: a.damage(damage, "bleeding"); _emit("missile_blood", a.cell, {"actor": a, "count": mini(10, int(10 * damage / maxi(1, a.max_hp)))})
			level_value = (rng.randf() + rng.randf()) / 2 * level_value / 2 + level_value / 2
			a.data.bleed_level = level_value
			if RingRules.java_round(level_value) <= 0: a.statuses.erase("bleeding")
	super.step_turn()
	for circle in circles.duplicate():
		circle.left -= 1
		if circle.left <= 0:
			circles.erase(circle); _emit("missile_return", circle.to, {"circle": circle, "actor":circle.actor, "item":circle.item, "from":circle.from, "to":circle.to})
			if not circle.get("awaiting_visual", false): finish_return(circle)

func _cleanup() -> void:
	super._cleanup()
	for a in actors:
		if a.hp <= 0 and stuck.has(a.get_instance_id()):
			for item in stuck[a.get_instance_id()]: _land(item, a.cell)
			stuck.erase(a.get_instance_id())
func release_stuck(a: WandActor) -> void:
	for item in stuck.get(a.get_instance_id(), []): _land(item, a.cell)
	stuck.erase(a.get_instance_id()); a.changed.emit()
func save_projectiles() -> Dictionary:
	var pins := []; var returns := []
	for a in actors:
		var items := []
		for item in stuck.get(a.get_instance_id(), []): items.append(item.to_dict())
		if not items.is_empty(): pins.append({"cell": a.cell, "items": items})
	for circle in circles: returns.append({"item": circle.item.to_dict(), "owner_cell": circle.actor.cell, "from": circle.from, "to": circle.to, "left": circle.left})
	return {"stuck": pins, "returns": returns}
func load_projectiles(data: Dictionary) -> void:
	stuck.clear(); circles.clear()
	for pin in data.get("stuck", []):
		var actor := actor_at(int(pin.cell))
		if actor != null:
			stuck[actor.get_instance_id()] = []
			for item in pin.items: stuck[actor.get_instance_id()].append(InventoryItem.from_dict(item))
	for saved in data.get("returns", []):
		var actor := actor_at(int(saved.owner_cell))
		if actor != null: circles.append({"actor": actor, "item": InventoryItem.from_dict(saved.item), "from": int(saved.from), "to": int(saved.to), "left": int(saved.left)})
func dispose() -> void:
	stuck.clear(); circles.clear(); super.dispose()
