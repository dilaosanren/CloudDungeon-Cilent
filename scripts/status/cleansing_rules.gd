# PotionOfCleansing.cleanse / Char.add: source buff type, not an effect list.
# AllyBuff (Corruption) and LostInventory are explicit native exceptions.
class_name CleansingRules
extends RefCounted
static var _definitions: Dictionary = {}

static func blocks(effect: String) -> bool:
	if effect in ["corruption","lost_inventory"]: return false
	if _definitions.is_empty():
		_definitions = JSON.parse_string(FileAccess.get_file_as_string("res://assets/status/buff_descriptions.json")).definitions
	return int(_definitions.get(effect,{}).get("kind",0)) < 0
