extends MeleeWorld
## Local journal simulation, GPL-3.0-or-later.
## Only the timed armor pools needed by glyph demonstrations. No PvP host,
## player seats, inventories, matchmaking or perspective filtering.
func step_turn() -> void:
	for actor in actors.duplicate():
		if actor.hp <= 0: continue
		if actor.data.get("deferred_damage", 0) > 0:
			var amount := maxi(1, int(actor.data.deferred_damage * 0.1))
			actor.data.deferred_damage -= amount
			actor.damage(amount, "deferred")
		if actor.data.get("conserved_damage", 0) > 0:
			actor.data.conserved_damage = maxf(0, float(actor.data.conserved_damage) - maxf(float(actor.data.conserved_damage) * 0.025, 0.1))
		if actor.data.get("block_shield", 0) > 0:
			actor.data.block_shield_left = float(actor.data.get("block_shield_left", 5)) - 1
			if actor.data.block_shield_left <= 0: actor.data.erase("block_shield")
	super.step_turn()
