# SPD 4.0.2 Char.attack, Hero.canAttack and 33 ordinary melee weapons.
# GPL-3.0-or-later. Each world owns its actors and pathfinder.
class_name MeleeWorld
extends MissileWorld
var staff_cache: Dictionary = {}

func weapon(a: WandActor) -> InventoryItem:
	if a.species == "mirror_image":
		var hero := _actor_by_id(int(a.data.get("hero_id", -1)))
		return hero.data.get("melee_weapon") if hero != null else null
	return a.data.get("melee_weapon")
func grid_distance(from: int, to: int) -> int:
	var delta := level.cell_coords(from) - level.cell_coords(to)
	return maxi(absi(delta.x), absi(delta.y))
func movement_mask(a: WandActor) -> PackedByteArray:
	var mask := PackedByteArray(); mask.resize(level.passable.size())
	for i in mask.size(): mask[i] = int(level.passable[i] or level.avoid[i])
	for other in actors:
		if other != a and other.hp > 0: mask[other.cell] = 0
	return mask
func can_attack(a: WandActor, d: WandActor, item: InventoryItem = null) -> bool:
	if a == d or d == null or d.hp <= 0: return false
	if adjacent(a.cell, d.cell): return true
	if item == null: item = weapon(a)
	var reach := MeleeRules.reach(item, a)
	if item != null and item.type_id == "MagesStaff":
		var wand := embedded(item)
		if wand != null: reach += staff_reach_bonus(wand, a)
	if grid_distance(a.cell, d.cell) > reach: return false
	var mask := non_solid_mask()
	for other in actors:
		if other != a and other.hp > 0: mask[other.cell] = 0
	var finder := DungeonPathFinder.new(); finder.set_map_size(level.size.x, level.size.y)
	finder.build_distance_map(d.cell, mask, reach)
	return finder.distance[a.cell] <= reach
func action_error(a: WandActor) -> String:
	if a == null or a.hp <= 0: return "角色已经倒下"
	if a.has_status("paralysis") or a.has_status("frost") or a.has_status("magical_sleep"): return "当前状态无法攻击"
	return ""
func surprised(a: WandActor, d: WandActor, item: InventoryItem) -> bool:
	if unseen_player_attack(a, d): return true
	return (item == null or item.type_id != "Flail" or RingRules.fighting_unarmed(a, true)) and (a.has_status("invisibility") or d.data.get("surprised", false))
func melee_hit(a: WandActor, d: WandActor, item: InventoryItem) -> bool:
	# Char.hit checks infinite evasion before infinite accuracy.
	if surprised(a, d, item): return true
	var stat := maxi(1,RingRules.java_round(RingRules.f32(a.attack_skill * RingRules.accuracy(a) * MeleeRules.accuracy(item,a))))
	var acc := rng.randf() * stat
	var evade := rng.randf() * d.effective_evasion()
	for spec in [["bless", 1.25], ["hex", 0.8], ["daze", 0.5]]:
		if a.has_status(spec[0]): acc *= spec[1]
		if d.has_status(spec[0]): evade *= spec[1]
	return acc >= evade
func armor_roll(a: WandActor) -> int:
	if a.species == "mirror_image":
		return MeleeRules.defense(weapon(a), a, true) + a.barkskin_defense()
	var weapon_dr := 0 if RingRules.fighting_unarmed(a,weapon(a) != null) else maxi(0,MeleeRules.defense(weapon(a),a))
	return S.normal_int(rng,int(a.data.get("armor_min",0)),int(a.data.get("armor_max",0))) + weapon_dr + a.barkskin_defense()

func _mirror_can_attack(a: WandActor, target: WandActor, item: InventoryItem) -> bool:
	return can_attack(a, target, item)

func _mirror_hit(a: WandActor, target: WandActor, hero: WandActor, item: InventoryItem) -> void:
	var damage := MeleeRules.damage_roll(item, a if item != null else hero, rng)
	damage = int((damage + 1) / 2)
	if a.has_status("weakness"): damage = RingRules.java_round(damage * 0.67)
	damage = maxi(0, damage - armor_roll(target))
	target.interrupt_healing()
	damage = RunicGear.weapon_proc(self, item, a, target, damage)
	damage = RunicGear.armor_proc(self, a, target, damage)
	if target.has_status("vulnerable"): damage = RingRules.java_round(damage * 1.33)
	var before := target.hp + target.shield
	target.damage(damage, "physical")
	RunicGear.after_hit(self, item, a, target, damage, before)
	target.data.enemy = a
	_emit("melee_hit", target.cell, {"actor":target})
	if item != null:
		var p := MeleeRules.profile(item)
		_emit("melee_sound", target.cell, {"sound":p.sound, "pitch":p.pitch})
func attack(a: WandActor, d: WandActor, kind: String = "melee", item: InventoryItem = null, armed: bool = true) -> Dictionary:
	if kind != "melee": return super.attack(a, d, kind, item, armed)
	if item == null and armed: item = weapon(a)
	var error := action_error(a)
	if not error.is_empty(): return {"error":error}
	if a.is_charmed_by(d): return {"error":"被魅惑时无法直接攻击魅惑施行者"}
	if not can_attack(a, d, item): return {"error":"目标超出攻击距离，或路径被墙壁／角色阻挡"}
	var result := strike(a, d, item)
	a.dispel(); _cleanup()
	return result
func strike(a: WandActor, d: WandActor, item: InventoryItem) -> Dictionary:
	var surprise := surprised(a, d, item)
	var result := {"hit":surprise or melee_hit(a, d, item), "surprise":surprise, "damage":0, "cost":MeleeRules.delay(item, a), "enchant":false}
	if not result.hit:
		_emit("dodge", d.cell, {"actor":d})
		return result
	if surprise: _emit("surprise", d.cell, {"actor":d})
	d.interrupt_healing()
	var amount := MeleeRules.damage_roll(item,a,rng,surprise)
	if a.has_status("weakness"): amount = RingRules.java_round(amount * 0.67)
	amount = maxi(0, amount - armor_roll(d))
	amount = RunicGear.weapon_proc(self, item, a, d, amount)
	amount = RunicGear.armor_proc(self, a, d, amount)
	if d.has_status("vulnerable"): amount = RingRules.java_round(amount * 1.33)
	var before := d.hp + d.shield
	d.damage(amount, "physical")
	RunicGear.after_hit(self, item, a, d, amount, before)
	result.damage = before - d.hp - d.shield
	if amount == 0: _emit("missile_blocked", d.cell, {"actor":d})
	if item != null:
		var p := MeleeRules.profile(item)
		_emit("melee_sound", d.cell, {"sound":p.sound, "pitch":p.pitch})
		var hook: Callable = a.data.get("weapon_proc", Callable())
		if hook.is_valid(): hook.call(item, a, d, amount, 0)
		if item.type_id == "MagesStaff" and a.data.get("battlemage", false):
			var wand := embedded(item)
			if wand != null:
				WandState.gain_charge(wand, 0.5); staff_hit(wand, a, d, amount, MeleeRules.level(item, a)); MeleeStaff.save(item, wand)
	# Char.attack flashes on every successful hit, even when no HP is lost.
	_emit("melee_hit", d.cell, {"actor":d})
	_cleanup()
	return result
func resolve(plan: Dictionary) -> bool:
	var result := super.resolve(plan)
	if result: plan.caster.dispel()
	for entry in staff_cache.values(): MeleeStaff.save(entry.staff, entry.wand)
	return result

func embedded(staff: InventoryItem) -> InventoryItem:
	if not staff.metadata.has("staff_wand"): return null
	if staff_cache.has(staff.get_instance_id()) and staff_cache[staff.get_instance_id()].wand.type_id != staff.metadata.staff_wand.type_id: staff_cache.erase(staff.get_instance_id())
	if not staff_cache.has(staff.get_instance_id()): staff_cache[staff.get_instance_id()] = {"staff":staff,"wand":MeleeStaff.restore(staff)}
	var wand: InventoryItem = staff_cache[staff.get_instance_id()].wand
	MeleeStaff.sync_level(staff, wand); return wand
func carry(a: WandActor, items: Array) -> void:
	if inventory != null:
		for id in staff_cache.keys():
			if not inventory.contains(staff_cache[id].staff): staff_cache.erase(id)
	var with_embedded := items.duplicate()
	for item in items:
		if item.type_id == "MagesStaff":
			var wand := embedded(item)
			if wand != null: with_embedded.append(wand)
	super.carry(a, with_embedded)
func step_turn() -> void:
	super.step_turn()
	for entry in staff_cache.values(): MeleeStaff.save(entry.staff, entry.wand)
func dispose() -> void:
	staff_cache.clear(); super.dispose()
