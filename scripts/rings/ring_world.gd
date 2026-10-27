# Arena actions and loot bridge for the ring port; shares the existing item world.
class_name RingWorld
extends ScrollWorld
var player: WandActor

func attack(attacker: WandActor, defender: WandActor, kind: String = "melee", weapon: InventoryItem = null, armed: bool = true) -> Dictionary:
	if attacker.hp <= 0 or defender.hp <= 0 or attacker.has_status("paralysis") or attacker.has_status("frost") or attacker.has_status("magical_sleep"): return {"error": "当前状态无法攻击"}
	if kind == "melee" and not adjacent(attacker.cell, defender.cell): return {"error": "近战需要相邻；点击相邻地面跳一格"}
	if kind == "missile" and (weapon == null or Ballistica.new(attacker.cell, defender.cell, Ballistica.PROJECTILE, level).collision_pos != defender.cell): return {"error": "投掷路径被阻挡"}
	var cost := RingCombat.attack_cost(attacker)
	var result := {"hit": RingCombat.hit(attacker, defender, rng), "damage": 0, "cost": cost, "enchant": false}
	if result.hit:
		var bounds := RingCombat.missile_range(attacker, weapon) if kind == "missile" else RingCombat.melee_range(attacker, Vector2i(4, 8), armed)
		var damage := S.normal_int(rng, bounds.x, bounds.y)
		var before := defender.hp + defender.shield
		defender.damage(damage, "physical")
		result.damage = before - defender.hp - defender.shield
		if kind == "melee" and attacker.data.get("test_enchantment", false):
			var proc := RingCombat.blazing(attacker, defender, 0, rng); result.enchant = proc.proc
			if proc.proc: _emit("ring_blazing", defender.cell, {"actor": defender})
	else: _emit("dodge", defender.cell, {"actor": defender})
	if kind == "missile": result.broken = RingCombat.use_missile(attacker, weapon, 5)
	attacker.statuses.erase("invisibility")
	_cleanup()
	return result

func roll_loot(victim: WandActor) -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	if player == null: return drops
	if rng.randf() < float(victim.data.get("loot_chance", 0.4)) * RingRules.wealth_chance(player):
		drops.append({"item": InventoryCatalog.create("PotionOfHealing"), "tier": 0, "bonus": false})
	var tries := 15 if "boss" in victim.properties else 5 if "miniboss" in victim.properties else 1
	drops.append_array(RingLoot.try_bonus_drop(player, tries, rng, int(environment.scaling_depth)))
	return drops

func _cleanup() -> void:
	super._cleanup()
	if player == null: return
	for a in actors:
		if a == player or a.hp > 0 or a.alignment == "ally" or not a.data.get("drops_loot", false) or a.data.get("loot_rolled", false): continue
		a.data.loot_rolled = true
		var drops := roll_loot(a)
		for drop in drops: _emit("ring_loot", a.cell, {"actor": a, "item": drop.item, "tier": drop.tier})

func dispose() -> void:
	player = null; super.dispose()
