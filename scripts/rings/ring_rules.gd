# Ring.java and all twelve RingOf*.java, supplied SPD 4.0.2.
# Copyright Oleg Dolya / Evan Debenham. GPL-3.0-or-later.
class_name RingRules
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")
const ItemText = preload("res://scripts/inventory/item_text.gd")

const TYPES = ["RingOfAccuracy", "RingOfArcana", "RingOfElements", "RingOfEnergy", "RingOfEvasion", "RingOfForce",
	"RingOfFuror", "RingOfHaste", "RingOfMight", "RingOfSharpshooting", "RingOfTenacity", "RingOfWealth"]
const VISUALS = ["RING_GARNET", "RING_RUBY", "RING_TOPAZ", "RING_EMERALD", "RING_ONYX", "RING_OPAL",
	"RING_TOURMALINE", "RING_SAPPHIRE", "RING_AMETHYST", "RING_QUARTZ", "RING_AGATE", "RING_DIAMOND"]
const ELEMENTS = ["burning", "chill", "frost", "ooze", "paralysis", "poison", "corrosion", "toxic_gas", "electricity",
	"magical_sleep", "charm", "weakness", "vulnerable", "hex", "degrade", "disintegration_trap", "grim_trap", "ArcaneBomb", "holy_damage",
	"ScrollOfRetribution", "ScrollOfPsionicBlast", "ScrollOfTeleportation", "holy_dart", "guiding_light", "holy_weapon", "sunray", "holy_lance", "smite", "judgement",
	"elemental_blast", "cursed_wand", "WandOfBlastWave", "WandOfDisintegration", "WandOfFireblast", "WandOfFrost", "WandOfLightning",
	"WandOfLivingEarth", "WandOfMagicMissile", "WandOfPrismaticLight", "WandOfTransfusion", "wand_magic", "chalice", "blazing", "shocking", "grim", "crystal",
	"elemental_strike", "warp_beacon", "dm100_lightning_bolt", "shaman_earthen_bolt", "crystal_wisp_light_beam", "warlock_dark_bolt", "eye_death_gaze", "bright_fist_light_beam", "dark_fist_dark_bolt"]
static var _source: Dictionary = {}

static func source() -> Dictionary:
	if _source.is_empty(): _source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/rings/source_catalog.json").trim_prefix("\ufeff"))
	return _source

static func f32(value: float) -> float:
	var bytes := PackedByteArray(); bytes.resize(4); bytes.encode_float(0, value); return bytes.decode_float(0)

static func java_round(value: float) -> int: return int(floor(value + 0.5))

static func reduced_level(level: int) -> int:
	return level if level <= 0 else java_round(sqrt(2 * (level - 1)) + 1)

static func solo_bonus(item: InventoryItem, actor: WandActor = null, buffed: bool = true) -> int:
	var level := item.level
	if buffed and actor != null:
		if actor.has_status("degrade"): level = reduced_level(level)
		if actor.has_status("enhanced_rings"): level += 1
	return mini(0, level - 2) if item.cursed else level + 1

static func bonus(actor: WandActor, type: String, buffed: bool = true) -> int:
	if actor == null or actor.has_status("magic_immune") or actor.data.get("inventory_magic_immune", false): return 0
	var total := 0
	for item in actor.equipped_rings:
		if item.type_id == type: total += solo_bonus(item, actor, buffed)
	var spirit: InventoryItem = actor.data.get("spirit_ring")
	if total == 0 and actor.has_status("spirit_form") and spirit != null and spirit.type_id == type: total = solo_bonus(spirit, actor, buffed)
	return total

static func present(actor: WandActor, type: String) -> bool:
	for item in actor.equipped_rings:
		if item.type_id == type: return true
	var spirit: InventoryItem = actor.data.get("spirit_ring")
	return actor.has_status("spirit_form") and spirit != null and spirit.type_id == type

static func accuracy(actor: WandActor) -> float: return f32(pow(f32(1.3), bonus(actor, "RingOfAccuracy")))
static func arcana(actor: WandActor) -> float: return f32(pow(f32(1.175), bonus(actor, "RingOfArcana")))
static func evasion(actor: WandActor) -> float: return f32(pow(1.125, bonus(actor, "RingOfEvasion")))
static func furor(actor: WandActor) -> float: return f32(pow(1.09051, bonus(actor, "RingOfFuror")))
static func haste(actor: WandActor) -> float: return f32(pow(1.15, bonus(actor, "RingOfHaste")))
static func might_health(actor: WandActor) -> float: return f32(pow(1.035, bonus(actor, "RingOfMight")))
static func might_strength(actor: WandActor) -> int: return bonus(actor, "RingOfMight", false)
static func sharpshooting_damage(actor: WandActor) -> int: return bonus(actor, "RingOfSharpshooting")
static func sharpshooting_durability(actor: WandActor) -> float: return f32(pow(1.2, bonus(actor, "RingOfSharpshooting", false)))
static func wealth_chance(actor: WandActor) -> float: return f32(pow(1.2, bonus(actor, "RingOfWealth")))

static func energy(actor: WandActor, kind: String = "wand") -> float:
	var value := f32(pow(1.175, bonus(actor, "RingOfEnergy")))
	var key := "light_reading" if kind == "wand" else "light_cloak"
	var exception := "cleric" if kind == "wand" else "rogue"
	if kind != "armor" and hero_class(actor) != exception:
		value = f32(value * f32(1 + f32(f32(0.2) * int(actor.data.get(key, 0))) / 3))
	return value

static func elements(actor: WandActor, effect: String) -> float:
	return f32(pow(0.825, bonus(actor, "RingOfElements"))) if effect in ELEMENTS else 1.0

static func tenacity(actor: WandActor) -> float:
	var missing := f32(float(actor.max_hp - actor.hp) / maxi(1, actor.max_hp))
	return f32(pow(0.85, f32(bonus(actor, "RingOfTenacity") * missing)))

static func force_tier(strength: int) -> float:
	var tier := maxf(1, (strength - 8) / 2.0)
	return 5 + (tier - 5) / 2 if tier > 5 else tier

static func force_range(level: int, strength: int) -> Vector2i:
	var tier := force_tier(strength) if level > 0 else 1.0
	return Vector2i(maxi(0, java_round(f32(tier + level))), maxi(0, java_round(f32(f32(5 * f32(tier + 1)) + f32(level * f32(tier + 1))))))

static func strength(actor: WandActor) -> int: return int(actor.data.get("strength", 10)) + might_strength(actor)

static func hero_class(actor: WandActor) -> String:
	return actor.sprite.hero_class if actor.sprite is DungeonHeroSprite else str(actor.data.get("hero_class", "warrior"))

static func unarmed_range(actor: WandActor) -> Vector2i:
	if present(actor, "RingOfForce") and not actor.data.get("monk_unarmed", false):
		var level := bonus(actor, "RingOfForce")
		var result := force_range(level, strength(actor))
		return result
	return Vector2i(1, maxi(strength(actor) - 8, 1))

static func fighting_unarmed(actor: WandActor, armed: bool) -> bool:
	return not armed or actor.data.get("monk_unarmed", false)

static func unarmed_gets_enchantment(actor: WandActor, armed: bool) -> bool:
	return armed and actor.data.get("monk_unarmed", false) and actor.data.get("flurry_empower", false)

static func stats(item: InventoryItem, actor: WandActor = null) -> String:
	var level := solo_bonus(item, actor)
	var text := _stat_text(item.type_id, level, item, actor)
	if actor != null and item in actor.equipped_rings:
		var combined := 0
		for ring in actor.equipped_rings:
			if ring.type_id == item.type_id: combined += solo_bonus(ring, actor)
		if combined != level: text += "\n\n" + _stat_text(item.type_id, combined, item, actor, true)
	return text

static func _stat_text(type: String, level: int, item: InventoryItem, actor: WandActor, combined: bool = false) -> String:
	if type == "RingOfSharpshooting": return L10n.text("投掷武器有效等级：%+d") % level
	var raw := solo_bonus(item, actor, false)
	if combined and actor != null:
		raw = 0
		for ring in actor.equipped_rings:
			if ring.type_id == type: raw += solo_bonus(ring, actor, false)
	var values: Array = []
	match type:
		"RingOfAccuracy": values = [_decimal(100 * (pow(f32(1.3), level) - 1))]
		"RingOfArcana", "RingOfEnergy": values = [_decimal(100 * (pow(f32(1.175), level) - 1))]
		"RingOfElements": values = [_decimal(100 * (1 - pow(f32(0.825), level)))]
		"RingOfEvasion": values = [_decimal(100 * (pow(f32(1.125), level) - 1))]
		"RingOfFuror": values = [_decimal(100 * (pow(f32(1.09051), level) - 1))]
		"RingOfHaste": values = [_decimal(100 * (pow(f32(1.15), level) - 1))]
		"RingOfMight": values = [raw, _decimal(100 * (pow(1.035, level) - 1))]
		"RingOfSharpshooting": values = [level, _decimal(100 * (pow(1.2, raw) - 1))]
		"RingOfTenacity": values = [_decimal(100 * (1 - pow(f32(0.85), level)))]
		"RingOfWealth": values = [_decimal(100 * (pow(f32(1.2), level) - 1))]
		"RingOfForce":
			var bounds := force_range(level, strength(actor) if actor != null else 10); values = [bounds.x, bounds.y, level]
	var text: String = source().stats.get(type.to_lower() + (".combined_stats" if combined else ".stats"), "")
	return ItemText.format_message(L10n.text(text), values)

static func _decimal(value: float) -> String:
	return ("%.2f" % value).trim_suffix("00").trim_suffix("0").trim_suffix(".")
