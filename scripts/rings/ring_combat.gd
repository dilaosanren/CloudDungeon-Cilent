# Ring-aware action adapter. Base weapon stats are supplied by the weapon system.
class_name RingCombat
extends RefCounted

static func hit(actor: WandActor, defender: WandActor, rng: RandomNumberGenerator, magic: bool = false) -> bool:
	if defender.has_status("invulnerable"): return false
	if actor.has_status("invisibility"): return true
	var acc := rng.randf() * actor.effective_accuracy()
	var eva := rng.randf() * defender.effective_evasion()
	for spec in [["bless", 1.25], ["hex", 0.8], ["daze", 0.5]]:
		if actor.has_status(spec[0]): acc *= spec[1]
		if defender.has_status(spec[0]): eva *= spec[1]
	return acc * (2 if magic else 1) >= eva

static func melee_range(actor: WandActor, base: Vector2i, armed: bool = true) -> Vector2i:
	if RingRules.fighting_unarmed(actor, armed): return RingRules.unarmed_range(actor)
	return (base + Vector2i.ONE * RingRules.bonus(actor, "RingOfForce")).max(Vector2i.ZERO)

static func attack_cost(actor: WandActor, base_delay: float = 1.0) -> float:
	return base_delay / RingRules.furor(actor) / (1.5 if actor.has_status("adrenaline") else 1.0)

static func missile_range(actor: WandActor, item: InventoryItem) -> Vector2i:
	if MissileRules.is_weapon(item): return MissileRules.damage_range(item, actor)
	var tier := int(item.metadata.get("tier", 1))
	var level := RingRules.reduced_level(item.level) if actor.has_status("degrade") else item.level
	level += RingRules.sharpshooting_damage(actor)
	var minimum := 2 * tier + level
	var maximum := 5 * tier + tier * level
	if item.type_id == "ThrowingKnife": maximum = 6 * tier + (2 * level if tier == 1 else tier * level)
	return Vector2i(maxi(0, minimum), maxi(0, maximum))

static func durability_per_use(actor: WandActor, item: InventoryItem, base_uses: float = 8, holster: bool = false) -> float:
	return 0.0 # Compatibility for older host adapters; projectiles have no wear.

static func use_missile(actor: WandActor, item: InventoryItem, base_uses: float = 8, holster: bool = false) -> bool:
	MissileRules.initialize(item)
	return true # A hit consumes the detached projectile, regardless of upgrades.

## Source Blazing: arcana increases proc chance; power above guaranteed proc
## converts to extra damage. Used by the ring demo's real fire enchant test.
static func blazing(actor: WandActor, defender: WandActor, level: int, rng: RandomNumberGenerator, runic_boost: float = 0) -> Dictionary:
	var chance := (level + 1.0) / (level + 3.0) * (RingRules.arcana(actor) + runic_boost)
	if rng.randf() >= chance: return {"proc": false, "damage": 0, "chance": chance}
	var power := maxf(1, chance)
	if not defender.has_status("burning"): defender.status("burning", 8); power -= 1
	var damage := 0
	if power > 0:
		damage = RingRules.java_round(WandState.normal_int(rng, 1, 3 + int(int(actor.data.get("depth", 5)) / 4)) * RingRules.f32(0.67) * power)
		defender.damage(damage, "blazing")
	return {"proc": true, "damage": damage, "chance": chance}
