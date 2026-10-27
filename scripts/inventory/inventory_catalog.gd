class_name InventoryCatalog
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")

static var _definitions: Dictionary = {}
static var _exotic_visuals: Dictionary = {}
const SCROLL_VISUALS = {"ScrollOfIdentify": "SCROLL_KAUNAN", "ScrollOfLullaby": "SCROLL_SOWILO",
	"ScrollOfMagicMapping": "SCROLL_LAGUZ", "ScrollOfMirrorImage": "SCROLL_YNGVI", "ScrollOfRage": "SCROLL_GYFU",
	"ScrollOfRecharging": "SCROLL_RAIDO", "ScrollOfRemoveCurse": "SCROLL_ISAZ", "ScrollOfRetribution": "SCROLL_MANNAZ",
	"ScrollOfTeleportation": "SCROLL_NAUDIZ", "ScrollOfTerror": "SCROLL_BERKANAN", "ScrollOfTransmutation": "SCROLL_ODAL", "ScrollOfUpgrade": "SCROLL_TIWAZ"}
const POTION_VISUALS = {"PotionOfHealing": "POTION_CRIMSON", "PotionOfStrength": "POTION_AMBER",
	"PotionOfExperience": "POTION_GOLDEN", "PotionOfToxicGas": "POTION_JADE",
	"PotionOfLevitation": "POTION_TURQUOISE", "PotionOfFrost": "POTION_AZURE",
	"PotionOfMindVision": "POTION_INDIGO", "PotionOfInvisibility": "POTION_MAGENTA",
	"PotionOfLiquidFlame": "POTION_BISTRE", "PotionOfParalyticGas": "POTION_CHARCOAL",
	"PotionOfHaste": "POTION_SILVER", "PotionOfPurity": "POTION_IVORY"}

static func definitions() -> Dictionary:
	if _definitions.is_empty():
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/inventory/definitions.json"))
		for data in source.items:
			_definitions[data.type_id] = data
		var nature: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/nature/source_catalog.json"))
		for data in nature.items: _definitions[data.type_id] = data
	return _definitions.duplicate(true)

static func create(type_id: String, quantity: int = 1) -> InventoryItem:
	var data: Dictionary = definitions().get(type_id, {})
	if data.is_empty():
		push_error("Unknown inventory type: " + type_id)
		return null
	var item := InventoryItem.from_dict(data)
	if POTION_VISUALS.has(type_id): item.visual = POTION_VISUALS[type_id]
	if SCROLL_VISUALS.has(type_id): item.visual = SCROLL_VISUALS[type_id]
	if type_id in RingRules.TYPES: item.visual = RingRules.VISUALS[RingRules.TYPES.find(type_id)]
	if _exotic_visuals.is_empty():
		var scroll_source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/scrolls/source_catalog.json").trim_prefix("\ufeff"))
		for original in scroll_source.exotic_pairs:
			var base_visual: String = SCROLL_VISUALS.get(original, POTION_VISUALS.get(original, ""))
			if not base_visual.is_empty(): _exotic_visuals[scroll_source.exotic_pairs[original]] = "EXOTIC_" + base_visual.trim_prefix("SCROLL_").trim_prefix("POTION_")
	if _exotic_visuals.has(type_id): item.visual = _exotic_visuals[type_id]
	if type_id == "ScrollOfUpgrade": item.unique = true
	if type_id == "ScrollOfIdentify": item.description = "所有物品均已鉴定。阅读会消耗一张卷轴，并播放原版阅读动作与特效。"
	item.quantity = quantity
	if type_id == "ScrollOfIdentify": item.extra_actions = ["READ"]; item.default_action = "READ"
	if ItemAssets.get_texture(item.visual) == null:
		item.visual = "SOMETHING"
	if item.category == "wand":
		WandState.initialize(item)
	MissileRules.initialize(item)
	MeleeRules.initialize(item)
	return item

static func action_label(item: InventoryItem, action: String) -> String:
	var labels := {"DROP": "放下", "THROW": "扔出", "EQUIP": "装备", "UNEQUIP": "取下",
		"OPEN": "打开", "DRINK": "饮用", "READ": "阅读", "EAT": "食用", "ZAP": "释放",
		"PLANT": "种植", "USE": "使用", "CAST": "施放", "SHOOT": "射击", "LIGHTTHROW": "点燃并扔出", "TIP": "涂药", "CLEAN": "清洗"}
	return L10n.text(str(item.metadata.get("action_labels", {}).get(action, labels.get(action, action))))
