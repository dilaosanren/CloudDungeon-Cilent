# Adapted from SPD Bag / Belongings.Backpack and the four specialized bags.
# GPL-3.0-or-later; see LICENSE-SPD.txt.
class_name InventoryBag
extends InventoryItem

var items: Array[InventoryItem] = []
var kind: String = "backpack"

const DEFINITIONS = {
	"backpack": ["背包", "BACKPACK", 176],
	"pouch": ["绒布袋", "POUCH", 196],
	"scroll": ["卷轴筒", "HOLDER", 186],
	"potion": ["药剂挎带", "BANDOLIER", 216],
	"holster": ["魔法筒袋", "HOLSTER", 206],
}

static func create(bag_kind: String) -> InventoryBag:
	var bag := InventoryBag.new()
	bag.kind = bag_kind
	bag.type_id = "bag_" + bag_kind
	bag.title = DEFINITIONS[bag_kind][0]
	bag.visual = DEFINITIONS[bag_kind][1]
	bag.category = "bag"
	bag.default_action = "OPEN"
	bag.extra_actions = ["OPEN"]
	bag.unique = true
	bag.description = "分类收纳物品。点击底部标签切换，放入快捷栏后可快速使用其中的物品。"
	return bag

func capacity() -> int:
	if kind != "backpack":
		return 19
	var bags := 0
	for item in items:
		if item is InventoryBag:
			bags += 1
	return maxi(20 + bags, int(metadata.get("pvp_capacity", 0)))

func accepts(item: InventoryItem) -> bool:
	match kind:
		"backpack": return true
		"pouch": return item.category in ["seed", "stone"] or item.type_id in ["GooBlob", "MetalShard"]
		"scroll": return item.category in ["scroll", "spell"] or item.type_id in ["ArcaneResin", "Stylus"]
		"potion": return item.category == "potion" or item.type_id in ["LiquidMetal", "Waterskin"]
		"holster": return item.category in ["wand", "missile", "bomb"]
	return false

func can_hold(item: InventoryItem) -> bool:
	if not accepts(item):
		return false
	if items.has(item) or item is InventoryBag or items.size() < capacity():
		return true
	if item.stackable:
		for existing in items:
			if existing.similar(item):
				return true
	return false

func contains(item: InventoryItem) -> bool:
	for existing in items:
		if existing == item or (existing is InventoryBag and existing.contains(item)):
			return true
	return false

func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["kind"] = kind
	data["items"] = []
	for item in items:
		data.items.append(item.to_dict())
	return data

static func restore(data: Dictionary) -> InventoryBag:
	var bag := create(data.get("kind", "backpack"))
	for field in FIELDS:
		if data.has(field):
			bag.set(field, data[field])
	for entry in data.get("items", []):
		bag.items.append(restore(entry) if entry.has("kind") else InventoryItem.from_dict(entry))
	return bag
