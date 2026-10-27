## Small adapter for previews and prototypes. A full combat system can implement the same methods.
## Status timers are NOT advanced by environment.step_turn(): the actor/buff scheduler owns them.
class_name EnvironmentActor
extends RefCounted

var cell := -1
var hp := 100
var max_hp := 100
var alignment := "enemy"
var species := "dummy"
var flying := false
var fiery := false
var immunities: Array[String] = []
var resistances: Dictionary = {}
var statuses: Dictionary = {}
var shield := 0
var experience := 1
var hunger := 0.0
var equipped_items: Array[Dictionary] = []
var inventory: Array[Dictionary] = []

func is_immune(effect: String) -> bool:
	return effect in immunities

func resistance(effect: String) -> float:
	return float(resistances.get(effect, 1.0))

func has_status(effect: String) -> bool:
	return float(statuses.get(effect, 0)) > 0

func status(effect: String, duration: float, mode: String = "prolong", details: Dictionary = {}) -> void:
	if is_immune(effect):
		return
	if effect == "burning":
		statuses.erase("chill")
		statuses.erase("frost")
	elif effect == "chill" or effect == "frost":
		statuses.erase("burning")
		if effect == "frost":
			statuses.erase("chill")
	if mode == "add":
		statuses[effect] = minf(float(statuses.get(effect, 0)) + duration, float(details.get("cap", INF)))
	else:
		statuses[effect] = maxf(float(statuses.get(effect, 0)), duration)
	if not details.is_empty():
		statuses[effect + "_details"] = details.duplicate()

func damage(amount: int, source: String) -> void:
	if is_immune(source):
		return
	hp = maxi(0, hp - amount)

func advance_statuses(turns: float = 1.0) -> void:
	for key in statuses.keys():
		if statuses[key] is Dictionary or key == "time_bubble":
			continue
		statuses[key] = maxf(0, float(statuses[key]) - turns)
		if statuses[key] == 0:
			statuses.erase(key)

## Prototype well behavior; production actors can replace this method or use the world's hooks.
func environment_use_well(kind: String) -> bool:
	if species != "hero" or hp <= 0:
		return false
	if kind == "water_of_health":
		hp = max_hp
		hunger = 0
		for effect in ["poison", "cripple", "weakness", "vulnerable", "bleeding", "drowsy", "slow", "blindness", "vertigo"]:
			statuses.erase(effect)
		for item in equipped_items:
			item["cursed"] = false
	elif kind == "water_of_awareness":
		for item in inventory:
			item["cursed_known"] = true
		for item in equipped_items:
			item["identified"] = true
		status("awareness", 2.0)
	return true

func snapshot() -> Dictionary:
	return {"hp": hp, "max_hp": max_hp, "cell": cell, "alignment": alignment,
		"species": species, "flying": flying, "fiery": fiery, "immunities": immunities.duplicate(),
		"resistances": resistances.duplicate(), "statuses": statuses.duplicate(true),
		"shield": shield, "experience": experience, "hunger": hunger,
		"inventory": inventory.duplicate(true), "equipped_items": equipped_items.duplicate(true)}
