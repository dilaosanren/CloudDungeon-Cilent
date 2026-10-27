# Adapted from SPD 4.0.2 Wand.java / DamageWand.java, GPL-3.0-or-later.
class_name WandState
extends RefCounted
const ItemText = preload("res://scripts/inventory/item_text.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const FIXED_DAMAGE := {"WandOfMagicMissile":Vector2i(5,2), "WandOfLightning":Vector2i(7,3),
	"WandOfDisintegration":Vector2i(5,3), "WandOfFrost":Vector2i(5,3),
	"WandOfBlastWave":Vector2i(1,1), "WandOfPrismaticLight":Vector2i(3,2)}

const TYPES = ["WandOfMagicMissile", "WandOfLightning", "WandOfDisintegration",
	"WandOfFireblast", "WandOfCorrosion", "WandOfBlastWave", "WandOfLivingEarth",
	"WandOfFrost", "WandOfPrismaticLight", "WandOfWarding", "WandOfTransfusion",
	"WandOfCorruption", "WandOfRegrowth"]
static func stats(item: InventoryItem, hero_max_hp: int = 50, actor: WandActor = null) -> String:
	var lvl := level(item)
	if actor != null and actor.has_status("degrade"): lvl = RingRules.reduced_level(lvl)
	if actor != null and actor.has_status("scroll_empower"): lvl += 2
	if actor != null and actor.has_status("magic_charge"): lvl = maxi(lvl, int(actor.data.get("magic_charge_level", 0)))
	var charges := cost(item)
	var bounds := damage_range(item.type_id, lvl, charges)
	var values: Array = [bounds.x, bounds.y]
	match item.type_id:
		"WandOfMagicMissile": return L10n.text("从法杖中发出的魔法飞弹会对单个目标造成_%d点伤害_，如果被升级则会暂时强化其他法杖。") % bounds.x
		"WandOfLightning": return L10n.text("这根法杖能向任何瞄准的地方射出强大的电弧，造成_%d点伤害_。这道闪电能在附近多个目标间跳跃，在水里会更强力。要是太接近，同样可能电到你自己，却不会波及到你的同伴。") % bounds.x
		"WandOfDisintegration": return L10n.text("这根法杖射出的光束能穿透任何障碍物，并将随着法杖等级的提升而射得更远。光束会造成_%d点伤害_，并且会根据穿透的地形和敌人数量造成额外伤害。") % bounds.x
		"WandOfFrost": return L10n.text("这根法杖能向你的敌人射击冰霜能量，造成_%d点伤害_并冻伤目标，在水中的作用似乎更强。冻伤的敌人受到的伤害会降低，冻结的敌人不受本次冰霜伤害。") % bounds.x
		"WandOfBlastWave": return L10n.text("这根法杖能射出一股能量，在目标位置引发强烈的爆炸。爆炸造成_%d点伤害_，并能击飞大多数敌人。") % bounds.x
		"WandOfPrismaticLight": return L10n.text("这根法杖射出的光线能刺破地牢的黑暗，揭露隐藏的区域和陷阱。光线能致盲敌人并造成_%d点伤害_。恶魔与亡灵生物会在法杖的强光下被灼烧而受到额外伤害。") % bounds.x
		"WandOfFireblast": return L10n.text("这根法杖在使用时会产生一股强大的焰浪，延伸出一个锥形区域。下一次使用将消耗_%d点充能_并造成_%d点伤害_。消耗的充能越多，范围与威力越大。") % [charges, bounds.x]
		"WandOfCorrosion": values = [2 + lvl]
		"WandOfRegrowth": values = [charges]
		"WandOfWarding": values = [2 + lvl]
		"WandOfTransfusion":
			var health_cost := RingRules.java_round(RingRules.f32(hero_max_hp * RingRules.f32(0.05)))
			return L10n.text("这根法杖对友军或已被魅惑的敌人释放时，会消耗你_%d点生命_并提供_%d点治疗_，溢出治疗转为护盾；对敌人释放时会给予你_%d点护盾_，活体敌人还会被短暂魅惑。") % [health_cost, health_cost + 3 * lvl, 5 + lvl]
	return ItemText.for_item(item.type_id, "stats_desc", values)

static func initialize(item: InventoryItem) -> void:
	if item.metadata.has("wand_state"): return
	item.max_charges = capacity(item)
	item.charges = item.max_charges
	item.metadata.wand_state = {"partial": 0.0, "total_used": 0, "over_limit": 0, "free_charge": false,
		"resin": 0, "curse_infusion": false}

static func level(item: InventoryItem) -> int:
	var state: Dictionary = item.metadata.get("wand_state", {})
	var lvl := item.level
	if item.cursed and state.get("curse_infusion", false): lvl += 1 + int(lvl / 6)
	return lvl + int(state.get("resin", 0))

static func capacity(item: InventoryItem) -> int:
	return mini(10, (3 if item.type_id == "WandOfMagicMissile" else 2) + level(item) + int(item.metadata.get("staff_capacity_bonus", 0)))

static func cost(item: InventoryItem, wild_magic: bool = false) -> int:
	if item.cursed or wild_magic: return 1
	if item.type_id in ["WandOfFireblast", "WandOfRegrowth"]:
		return clampi(int(ceil(item.charges * 0.3)), 1, 3)
	return 1

static func damage_range(type: String, lvl: int, charges: int = 1) -> Vector2i:
	if FIXED_DAMAGE.has(type):
		var balance: Vector2i = FIXED_DAMAGE[type]
		var amount := maxi(0, balance.x + balance.y * lvl)
		return Vector2i(amount, amount)
	match type:
		"WandOfFireblast":
			var amount := maxi(0, (1 + lvl) * charges)
			return Vector2i(amount, amount)
		"WandOfLivingEarth": return Vector2i(4, 6 + 2 * lvl)
	return Vector2i.ZERO

static func normal_int(rng: RandomNumberGenerator, low: int, high: int) -> int:
	# Random.NormalIntRange: triangular continuous distribution, then Java truncation.
	return low + int((rng.randf() + rng.randf()) * (high - low + 1) / 2.0)

static func charge_limit(hero_level: int, wand_level: int) -> int:
	if wand_level >= 10: return 2147483647
	# The source expression uses integer division inside (wndLvl/(50-5*wndLvl)).
	return roundi(20 + hero_level * (2 + wand_level) * (1 + int(wand_level / (50 - 5 * wand_level))))

static func recharge(item: InventoryItem, turns: float = 1.0, scale_factor: float = 0.875,
		energy_multiplier: float = 1.0, bonus_remainder: float = 0.0, regen_on: bool = true) -> void:
	initialize(item)
	var s: Dictionary = item.metadata.wand_state
	item.max_charges = capacity(item)
	scale_factor = float(item.metadata.get("staff_charge_scale", scale_factor))
	if item.charges < item.max_charges:
		if regen_on: s.partial += turns * energy_multiplier / (10 + 40 * pow(scale_factor, maxi(0, item.max_charges - item.charges)))
		s.partial += 0.25 * bonus_remainder
		while s.partial >= 1 and item.charges < item.max_charges:
			s.partial -= 1
			item.charges += 1
	if item.charges == item.max_charges: s.partial = 0.0

static func gain_charge(item: InventoryItem, amount: float, overcharge: bool = false) -> void:
	initialize(item)
	var s: Dictionary = item.metadata.wand_state
	s.partial += amount
	while s.partial >= 1:
		item.charges = mini(item.max_charges + (int(amount) if overcharge else 0), item.charges + 1)
		s.partial -= 1

static func used(item: InventoryItem, charges: int) -> void:
	item.charges -= charges

static func upgrade(item: InventoryItem, rng: RandomNumberGenerator) -> void:
	initialize(item)
	item.level += 1
	if rng.randi_range(0, 2) == 0: item.cursed = false
	item.metadata.wand_state.resin = maxi(0, item.metadata.wand_state.resin - 1)
	item.max_charges = capacity(item)
	item.charges = mini(item.charges + 1, item.max_charges)
