# Wand combat adapter. Source rules: Char, RockArmor, Barrier, Corruption, Lotus.
# GPL-3.0-or-later.
class_name WandActor
extends EnvironmentActor

signal changed
signal received_damage(amount: int, source: String)
signal status_added(effect: String)
const PARALYSIS_DAMAGE_REDUCTION := 5.0
const PARALYSIS_IMMUNITY_DURATION := 3.0
var properties: Array[String] = []
var data: Dictionary = {}
var sprite: Node2D
var owner: WandActor
var hero_level := 1 # Compatibility parameter; never displayed as PvP experience.
var defense_skill := 5
var attack_skill := 15
var equipped_rings: Array[InventoryItem] = []
const Gear = preload("res://scripts/nature/runic_gear.gd")
const BLOB_IMMUNITIES = ["blizzard", "confusion_gas", "corrosive_gas", "electricity", "fire", "eternal_fire", "freezing", "inferno", "paralytic_gas", "regrowth", "smoke_screen", "stench_gas", "storm_cloud", "toxic_gas", "web", "tengu_fire", "vault_flame_traps"]

func is_immune(effect: String) -> bool:
	if species == "sheep": return true
	if super.is_immune(effect): return true
	if effect == "paralysis" and has_status("paralysis_resist"): return true
	if effect == "blindness" and has_status("magical_sight"): return true
	if effect == "roots" and flying: return true
	if effect == "terror" and has_status("dread"): return true
	if has_status("cleanse") and CleansingRules.blocks(effect): return true
	if has_status("magic_immune") and effect in ["magical_sleep", "charm", "weakness", "vulnerable", "hex", "degrade", "ScrollOfRetribution", "ScrollOfTeleportation"]: return true
	if effect in ["drowsy", "magical_sleep"] and ("sleep" in immunities or "static" in properties): return true
	if effect == "chill" and has_status("frost"): return true
	if has_status("blob_immunity") and effect in BLOB_IMMUNITIES: return true
	if has_status("magic_immune") and (effect.begins_with("WandOf") or effect == "wand_magic"): return true
	if "inorganic" in properties and effect in ["bleeding", "toxic_gas", "poison"]: return true
	if "fiery" in properties and effect == "burning": return true
	if "icy" in properties and effect in ["chill", "frost"]: return true
	if "acidic" in properties and effect == "ooze": return true
	if "immovable" in properties and effect == "vertigo": return true
	if "static" in properties and effect in ["corruption", "dread", "terror", "amok", "charm", "sleep", "paralysis", "frost", "chill", "slow", "speed"]: return true
	return false

func resistance(effect: String) -> float:
	var multiplier := super.resistance(effect)
	if Gear.glyph(self) == "antimagic" and effect in ["magical_sleep", "charm", "weakness", "vulnerable", "hex", "degrade", "ScrollOfTeleportation"]: multiplier *= 0.5
	if "boss" in properties and effect == "ScrollOfRetribution": multiplier *= 0.5
	if ("fiery" in properties and effect == "WandOfFireblast") or ("icy" in properties and effect == "WandOfFrost") or ("acidic" in properties and effect == "corrosion") or ("electric" in properties and effect in ["WandOfLightning", "electricity", "shocking"]): multiplier *= 0.5
	return multiplier * RingRules.elements(self, effect)

func status(effect: String, duration: float, mode: String = "prolong", details: Dictionary = {}) -> void:
	if species in ["lotus", "sheep"]: return
	if effect == "magical_sleep" and species == "hero" and hp >= max_hp: return
	if effect == "dread": statuses.erase("terror")
	var fresh := not has_status(effect)
	super.status(effect, duration, mode, details)
	if effect == "magical_sight" and has_status(effect):
		statuses.erase("blindness")
		statuses.erase("blindness_details")
	update_ring_health()
	if fresh and has_status(effect): status_added.emit(effect)
	changed.emit()

func damage(amount: int, source: String) -> void:
	if hp <= 0 or species in ["lotus", "sheep"] or has_status("invulnerable"): return
	update_ring_health()
	if species == "hero": amount = ceili(RingRules.f32(amount * RingRules.tenacity(self)))
	amount = 0 if is_immune(source) else maxi(0, roundi(amount * resistance(source)))
	if Gear.glyph(self) == "brimstone" and source == "burning": amount = 0
	if Gear.glyph(self) == "antimagic" and data.has("rng") and (source.begins_with("WandOf") or source in ["wand_magic", "grim", "crystal", "shocking", "ScrollOfRetribution"]):
		var lvl := Gear.armor_level(self)
		amount = maxi(0, amount - WandState.normal_int(data.rng, roundi(lvl * RingRules.arcana(self)), roundi((3 + 1.5 * lvl) * RingRules.arcana(self))))
	if has_status("doom") and not is_immune("doom"): amount = roundi(amount * 1.67)
	if has_status("frost"):
		statuses.erase("frost")
		if data.get("in_water", false): status("chill", 5 * resistance("chill"))
	statuses.erase("magical_sleep")
	if species == "hero":
		statuses.erase("drowsy")
		data.sleep_interrupted = true
	for effect in ["charm", "dread"]:
		if not has_status(effect): continue
		var ignore_key: String = str(effect) + "_ignore_next_hit"
		if data.get(ignore_key, false): data[ignore_key] = false
		else:
			statuses[effect] = maxf(0, float(statuses[effect]) - 5)
			if statuses[effect] <= 0: statuses.erase(effect)
	if has_status("terror"):
		if data.get("terror_ignore_next_hit", false): data.terror_ignore_next_hit = false
		else:
			statuses.terror = maxf(0, float(statuses.terror) - 5)
			if statuses.terror <= 0: statuses.erase("terror")
	if data.get("rock_armor", 0) > 0:
		var blocked := mini(int(data.rock_armor), amount - int(amount / 2))
		data.rock_armor -= blocked
		amount -= blocked
	if source == "physical" and data.get("earthroot_armor", 0) > 0 and data.get("earthroot_pos", -1) == cell:
		var blocked := mini(int(data.earthroot_armor), mini(amount, int(data.get("earthroot_block", 3))))
		data.earthroot_armor = maxi(0, data.earthroot_armor - blocked)
		amount -= blocked
	var incoming_amount := amount
	var block_absorbed := mini(int(data.get("block_shield", 0)), amount)
	data.block_shield = int(data.get("block_shield", 0)) - block_absorbed
	amount -= block_absorbed
	var absorbed := mini(shield, amount)
	var opening_absorbed := mini(opening_shield(), absorbed)
	if opening_absorbed > 0:
		data.opening_shield = opening_shield() - opening_absorbed
		if int(data.opening_shield) == 0: clear_opening_protection()
	shield -= absorbed
	hp = maxi(0, hp - (amount - absorbed))
	if incoming_amount > 0: interrupt_healing()
	# Positive damage to HP or shields reduces the timer once per damage event.
	# Fully mitigated/immune damage does not count, and never rolls rules RNG.
	if incoming_amount > 0 and has_status("paralysis"):
		var remaining := float(statuses.paralysis) - PARALYSIS_DAMAGE_REDUCTION
		if remaining <= 0: end_paralysis()
		else: statuses.paralysis = remaining
	received_damage.emit(incoming_amount, source)
	changed.emit()

func clear_healing() -> void:
	statuses.erase("healing")
	statuses.erase("healing_details")
	for key in ["healing_left", "healing_percent", "healing_flat"]: data.erase(key)

# Barkskin is an additional physical armour roll, fixed by this PvP rule.
# Its timer stores the full lifetime: 24 -> 21 -> ... -> 0, 8 -> 7 -> ... -> 0.
func barkskin_defense() -> int:
	return maxi(0,ceili(float(statuses.get("barkskin",0))/3.0))

func cleanse(duration: float = 5.0) -> void:
	for effect in statuses.keys():
		if not statuses.has(effect) or statuses[effect] is Dictionary or not CleansingRules.blocks(str(effect)): continue
		if effect == "paralysis": end_paralysis()
		else: statuses.erase(effect)
		statuses.erase(str(effect)+"_details")
	for key in ["bleed_level","corrosion_damage","poison_delay","burn_acted",
		"deferred_damage","charm_ignore_next_hit","terror_ignore_next_hit","dread_ignore_next_hit"]: data.erase(key)
	hunger = 0
	status("cleanse",duration)
	update_ring_health()
	changed.emit()

## Potion healing is timed. Other sources retain their legacy healing pool.
func interrupt_healing() -> void:
	if not has_status("healing") or not is_finite(float(statuses.healing)): return
	clear_healing()
	changed.emit()

func end_paralysis() -> void:
	if not has_status("paralysis"): return
	statuses.erase("paralysis")
	statuses.erase("paralysis_details")
	status("paralysis_resist", PARALYSIS_IMMUNITY_DURATION)

func advance_statuses(turns: float = 1.0) -> void:
	var poison_left := float(statuses.get("poison", 0))
	var poison_delay := float(data.get("poison_delay", 0))
	var frozen := has_status("frost")
	var paralysis_left := float(statuses.get("paralysis", 0))
	super.advance_statuses(turns)
	if data.has("opening_shield") and not has_status("opening_protection"):
		clear_opening_protection()
	if paralysis_left > 0 and not has_status("paralysis"):
		# Newly granted protection is not decremented by the expiry tick again.
		# If a caller advances past the exact expiry, account for that excess.
		var protected_for := PARALYSIS_IMMUNITY_DURATION - maxf(0, turns - paralysis_left)
		if protected_for > 0: status("paralysis_resist", protected_for)
		statuses.erase("paralysis_details")
	if poison_delay > 0 and poison_left > 0:
		statuses.poison = poison_left
		data.poison_delay = maxf(0, poison_delay - turns)
	update_ring_health()
	if frozen and not has_status("frost") and data.get("in_water", false): status("chill", 5 * resistance("chill"))

## A separate timed portion of the total shield, spent before ordinary Barrier.
func opening_shield() -> int:
	return clampi(int(data.get("opening_shield", 0)), 0, shield)

func grant_opening_protection(turns: float) -> void:
	clear_opening_protection()
	var amount := ceili(max_hp * 0.33)
	shield += amount
	data.opening_shield = amount
	status("opening_protection", turns)

func clear_opening_protection() -> void:
	shield -= opening_shield()
	data.erase("opening_shield")
	statuses.erase("opening_protection")
	statuses.erase("opening_protection_details")

func barrier(value: int) -> void:
	var opening := opening_shield()
	var previous := shield - opening
	var ordinary := maxi(shield - opening, value) # Never reduces an existing Barrier.
	shield = opening + ordinary
	if ordinary == value: data.barrier_partial = 0.0
	announce_value_buff("barrier", previous, ordinary)
	changed.emit()

## Pool-backed buffs have no timer entry, but still attach only once.
func announce_value_buff(effect: String, previous: float, current: float) -> void:
	if previous <= 0 and current > 0: status_added.emit(effect)

func heal(value: int) -> int:
	update_ring_health()
	var gained := mini(max_hp - hp, value)
	hp += gained
	changed.emit()
	return gained

## RingOfMight.updateHT(false): maximum changes never grant free healing.
func update_ring_health(boost_hp: bool = false) -> void:
	if species != "hero": return
	if not data.has("base_max_hp"): data.base_max_hp = max_hp
	var previous := max_hp
	max_hp = maxi(1, RingRules.java_round(RingRules.f32(int(data.base_max_hp) * RingRules.might_health(self))))
	if boost_hp: hp += maxi(0, max_hp - previous)
	hp = mini(hp, max_hp)

func effective_accuracy() -> int:
	return int(RingRules.f32(attack_skill * RingRules.accuracy(self)))

func base_evasion() -> int:
	return maxi(0, RingRules.java_round(RingRules.f32(defense_skill * RingRules.evasion(self))) + int(data.get("armor_evasion", 0)))

func effective_evasion() -> int:
	if species == "sheep": return 2147483647
	return 0 if Gear.glyph(self) == "stone" else base_evasion()

func dispel() -> void:
	statuses.erase("invisibility")
	statuses.erase("time_bubble")

## Char.spend: Slow takes priority over Chill; Speed multiplies the result.
func action_time_scale() -> float:
	var factor := 1.0
	if has_status("slow"): factor *= 0.5
	elif has_status("chill"): factor *= maxf(0.5, 1 - float(statuses.chill) * 0.1)
	if has_status("speed"): factor *= 2.0
	return factor

func is_charmed_by(other: WandActor) -> bool:
	return other != null and has_status("charm") and int(statuses.get("charm_details", {}).get("object", -1)) == other.get_instance_id()

## TimeBubble.processTime consumes its own budget without advancing world time.
func consume_time_bubble(time: float) -> bool:
	if not statuses.has("time_bubble"): return false
	statuses.time_bubble = float(statuses.time_bubble) - time
	if statuses.time_bubble < -0.001: statuses.erase("time_bubble")
	return true

func add_rock(lvl: int, amount: int) -> void:
	var previous := int(data.get("rock_armor", 0))
	data.rock_level = maxi(int(data.get("rock_level", 0)), lvl)
	data.rock_armor = mini(int(data.get("rock_armor", 0)) + amount, 2 * (8 + 4 * int(data.rock_level)))
	announce_value_buff("rock_armor", previous, data.rock_armor)
	changed.emit()
