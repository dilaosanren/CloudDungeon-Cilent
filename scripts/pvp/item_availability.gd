# PvP item exclusions are shared by the market and combat generation pools.
extends RefCounted

const EXCLUDED := [
	"RingOfMight", "RingOfWealth",
	"WandOfCorruption", "WandOfLivingEarth", "WandOfWarding",
	"PotionOfStrength", "PotionOfExperience", "ScrollOfIdentify", "ScrollOfRemoveCurse",
	"StoneOfAggression", "StoneOfDetectMagic", "StoneOfIntuition", "ScrollOfRage",
	"StoneOfDeepSleep", "StoneOfFear",
	"StoneOfClairvoyance",
]

static func allowed(type_id: String) -> bool:
	return type_id not in EXCLUDED

static func filter_types(types: Array) -> Array:
	var result: Array = []
	for type_id in types:
		if allowed(str(type_id)): result.append(type_id)
	return result
