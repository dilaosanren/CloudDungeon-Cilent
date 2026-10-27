# MagesStaff.applyWand/updateWand, serialized without object references.
class_name MeleeStaff
extends RefCounted
static func restore(staff: InventoryItem) -> InventoryItem:
	if not staff.metadata.has("staff_wand"): return null
	var wand := InventoryItem.from_dict(staff.metadata.staff_wand)
	sync_level(staff, wand)
	return wand
static func sync_level(staff: InventoryItem, wand: InventoryItem) -> void:
	if wand.level < MeleeRules.level(staff): wand.charges += 1
	wand.level = MeleeRules.level(staff)
	wand.metadata.staff_capacity_bonus = 1
	wand.metadata.staff_charge_scale = 0.75
	wand.metadata.wand_state.resin = 0
	wand.max_charges = WandState.capacity(wand)
	wand.charges = mini(wand.charges, wand.max_charges)
	save(staff, wand)
static func save(staff: InventoryItem, wand: InventoryItem) -> void:
	staff.metadata.staff_wand = wand.to_dict()
	staff.metadata.wand_type = wand.type_id
	staff.title = MeleeRules.source().wand_messages.get(wand.type_id.to_lower(),{}).get("staff_name",staff.title)
	staff.charges = wand.charges; staff.max_charges = wand.max_charges
static func imbue(staff: InventoryItem, wand: InventoryItem) -> void:
	WandState.initialize(wand)
	var old := restore(staff)
	var previous := staff.level
	staff.level = maxi(previous, wand.level)
	if previous > 0 and wand.level >= previous: staff.level += 1
	wand.charges += old.charges if old != null else 0
	wand.level = MeleeRules.level(staff)
	sync_level(staff, wand)
