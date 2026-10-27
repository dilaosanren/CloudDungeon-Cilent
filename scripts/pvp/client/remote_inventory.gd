class_name PvpRemoteInventory
extends DungeonInventory
## UI mirror only. Mutating actions are requests, never local game calculations.
signal intent(value: Dictionary)
signal selection_needed(item: InventoryItem, action: String)
var can_act := false

func refresh_equipment() -> void:
	# The server sends equipment metadata. Keep presentation references
	# without applying ring health, charges, damage or other game rules here.
	if ring_actor == null: return
	ring_actor.equipped_rings.clear()
	for slot in ["ring", "misc"]:
		if equipment[slot] != null and equipment[slot].category == "ring": ring_actor.equipped_rings.append(equipment[slot])
	ring_actor.data.melee_weapon = equipment.weapon
	ring_actor.data.crossbow = null
	if equipment.weapon != null and equipment.weapon.type_id == "Crossbow": ring_actor.data.crossbow = equipment.weapon

func execute(item: InventoryItem, action: String = "") -> bool:
	if item == null: return false
	if action.is_empty(): action = default_action(item)
	if action == "CHOOSE": choice_requested.emit(item); return true
	if not can_act: message.emit("还未轮到你行动。"); return false
	if action == "READ" and item.type_id in ScrollWorld.INVENTORY_SCROLLS or action == "IMBUE" or action == "USE" and item.category == "stone":
		selection_needed.emit(item, action)
		return true
	# Ranged actions always request a map cell, even when it is hidden by fog.
	if action in ["THROW", "ZAP"] or action in item.targeting_actions:
		pending_item = item
		pending_action = action
		targeting_requested.emit(item, action)
		return true
	intent.emit({"kind":"item", "uid":item.uid, "action":action})
	return true

func equip(item: InventoryItem, slot: String = "") -> bool:
	if not can_act or item == null: message.emit("还未轮到你行动。"); return false
	intent.emit({"kind":"item", "uid":item.uid, "action":"EQUIP", "slot":slot})
	return true

func unequip(item: InventoryItem, _collect_back: bool = true) -> bool:
	return execute(item, "UNEQUIP")

func set_quickslot(index: int, item: InventoryItem) -> bool:
	intent.emit({"kind":"quickslot", "slot":index, "uid":item.uid if item != null else ""})
	return true

func finish_target(pos: Vector2i) -> bool:
	var item := pending_item
	var action := pending_action
	cancel_target()
	if item == null or not can_act: return false
	intent.emit({"kind":"item", "uid":item.uid, "action":action, "target_xy":[pos.x, pos.y]})
	return true
