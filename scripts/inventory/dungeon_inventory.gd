# SPD 4.0.2 Item.collect/detach, Belongings, EquipableItem and QuickSlot adaptation.
# GPL-3.0-or-later. Own one instance per player, never a global shared PvP inventory.
class_name DungeonInventory
extends RefCounted

signal changed
signal message(text: String)
signal dropped(item: InventoryItem, cell: Vector2i)
signal action_requested(item: InventoryItem, action: String, cell: Vector2i)
signal targeting_requested(item: InventoryItem, action: String)
signal choice_requested(item: InventoryItem)
signal turn_spent(cost: float)

const EQUIPMENT_SLOTS = ["weapon", "armor", "artifact", "misc", "ring"]
const ORDER = {"trinket": 0, "weapon": 1, "armor": 7, "missile": 8, "wand": 14,
	"ring": 15, "artifact": 16, "food": 17, "potion": 18, "seed": 19,
	"scroll": 20, "stone": 21, "gold": 22, "misc": 23, "spell": 23, "bomb": 23, "bag": 23}
var backpack: InventoryBag = InventoryBag.create("backpack")
var equipment: Dictionary = {"weapon": null, "armor": null, "artifact": null, "misc": null, "ring": null}
var quickslots: Array[InventoryItem] = [null, null, null, null, null, null]
var gold: int = 0
var energy: int = 0
var hero_strength: int = 10
var hero_cell := Vector2i.ZERO
var alive: bool = true
var lost_inventory: bool = false
var magic_immune: bool = false
var pending_item: InventoryItem
var pending_action: String = ""
var effect_handler: Callable
var throw_handler: Callable
## Optional host owns projectile flight and detaches the item at impact (Potion/Item.cast).
var targeted_throw_handler: Callable
var action_provider: Callable
var _serial: int = 1
var ring_actor: WandActor
var ring_state: Dictionary = {}
var missile_state: Dictionary = {}

func _init() -> void:
	_assign_uid(backpack)
	changed.connect(refresh_equipment)

func bind_actor(actor: WandActor) -> void:
	if ring_actor != null: ring_actor.equipped_rings.clear(); ring_actor.update_ring_health()
	ring_actor = actor
	refresh_equipment()

func refresh_equipment() -> void:
	if ring_actor == null: return
	ring_actor.equipped_rings.clear()
	for slot in ["ring", "misc"]:
		var item: InventoryItem = equipment[slot]
		if item != null and item.category == "ring": ring_actor.equipped_rings.append(item)
	ring_actor.data.inventory_magic_immune = magic_immune
	ring_actor.data.ring_state = ring_state
	ring_actor.data.ring_armed = equipment.weapon != null
	ring_actor.data.armor_item = equipment.armor
	ring_actor.data.crossbow = null
	var weapon: InventoryItem = equipment.weapon
	if weapon != null and weapon.type_id == "Crossbow": ring_actor.data.crossbow = weapon
	MeleeRules.refresh_equipment(self, ring_actor)
	ring_actor.update_ring_health()

func ring_stats(item: InventoryItem) -> String:
	return RingRules.stats(item, ring_actor)

func _magic_enabled() -> bool:
	return magic_immune or (ring_actor != null and ring_actor.has_status("magic_immune"))

func _assign_uid(item: InventoryItem) -> void:
	if item.uid.is_empty():
		item.uid = "item_%d" % _serial
		_serial += 1

func create_item(type_id: String, quantity: int = 1) -> InventoryItem:
	return InventoryCatalog.create(type_id, quantity)

func default_action(item: InventoryItem) -> String:
	if item == null: return ""
	if item.type_id in ["PotionOfToxicGas", "PotionOfLiquidFlame", "PotionOfParalyticGas", "PotionOfFrost", "PotionOfCorrosiveGas", "PotionOfSnapFreeze", "PotionOfShroudingFog", "PotionOfStormClouds"]:
		return "THROW"
	if item.type_id in ["PotionOfPurity", "PotionOfLevitation", "PotionOfCleansing", "ElixirOfHoneyedHealing"]:
		return "CHOOSE"
	return item.default_action

func container_modifiers(item: InventoryItem) -> Dictionary:
	var bag := bag_of(item)
	if bag != null and bag.kind == "holster":
		if item.category == "wand": return {"recharge_scale": 0.85}
	return {}

func is_equipped(item: InventoryItem) -> bool:
	return item != null and equipment.values().has(item)

func contains(item: InventoryItem) -> bool:
	return item != null and (item == backpack or is_equipped(item) or backpack.contains(item))

func usable(item: InventoryItem) -> bool:
	return alive and contains(item) and item.quantity > 0 and (not lost_inventory or item.kept)

func bags() -> Array[InventoryBag]:
	var result: Array[InventoryBag] = [backpack]
	for item in all_items(false):
		if item is InventoryBag:
			result.append(item)
	return result

func all_items(include_equipped: bool = true) -> Array[InventoryItem]:
	var result: Array[InventoryItem] = []
	if include_equipped:
		for item in equipment.values():
			if item != null:
				result.append(item)
	_append_recursive(backpack, result)
	return result

func _append_recursive(bag: InventoryBag, result: Array[InventoryItem]) -> void:
	for item in bag.items:
		result.append(item)
		if item is InventoryBag:
			_append_recursive(item, result)

func bag_of(item: InventoryItem, bag: InventoryBag = null) -> InventoryBag:
	if bag == null:
		bag = backpack
	for entry in bag.items:
		if entry == item:
			return bag
		if entry is InventoryBag:
			var found := bag_of(item, entry)
			if found != null:
				return found
	return null

func collect(item: InventoryItem, container: InventoryBag = null) -> bool:
	if item == null or item.quantity <= 0:
		return false
	if MissileRules.is_weapon(item):
		MissileRules.initialize(item)
	if contains(item):
		return true
	if MissileRules.is_weapon(item): MissileRules.filter_enchantment(item, self)
	if lost_inventory and not item.kept:
		return false
	if item.category in ["gold", "energy"]:
		if item.category == "gold": gold += item.quantity
		else: energy += item.quantity
		changed.emit()
		return true
	if container == null:
		container = backpack
	if container != backpack and not backpack.contains(container): return false
	if item is InventoryBag:
		# A player owns at most one of each specialized bag. No bag cycles.
		if container != backpack or item.kind == "backpack": return false
		for bag in bags():
			if bag.kind == item.kind: return false
	var collected := _collect_into(item, container)
	if collected == null:
		return false
	if item is InventoryBag:
		for nested in item.items: _assign_uid(nested)
		refill(item)
	changed.emit()
	return true

func _collect_into(item: InventoryItem, bag: InventoryBag) -> InventoryItem:
	for entry in bag.items:
		if entry is InventoryBag and entry.can_hold(item):
			var nested := _collect_into(item, entry)
			if nested != null: return nested
	if not bag.can_hold(item):
		return null
	if item.stackable:
		for entry in bag.items:
			if entry.similar(item):
				if MissileRules.is_weapon(entry):
					var lost := MissileRules.merge(entry, item)
					if lost > 0:
						var plain := MissileRules.create("Dart", lost)
						if _collect_into(plain, backpack) == null: dropped.emit(plain, hero_cell)
				else: entry.quantity += item.quantity; item.quantity = 0
				for i in quickslots.size():
					if quickslots[i] == item: quickslots[i] = entry
				_replace_placeholders(entry)
				return entry
	_assign_uid(item)
	bag.items.append(item)
	sort_items(bag.items)
	_replace_placeholders(item)
	return item

func sort_items(items: Array[InventoryItem], equipped_first: bool = false) -> void:
	# Java Collections.sort is stable. Preserve pickup order within a category.
	for i in range(1, items.size()):
		var item := items[i]
		var key: int = ORDER.get(item.category, 23) - (100 if equipped_first and is_equipped(item) else 0)
		var j := i - 1
		while j >= 0:
			var previous_key: int = ORDER.get(items[j].category, 23) - (100 if equipped_first and is_equipped(items[j]) else 0)
			if previous_key <= key: break
			items[j + 1] = items[j]
			j -= 1
		items[j + 1] = item

func refill(bag: InventoryBag) -> void:
	if bag == backpack: return
	for item in backpack.items.duplicate():
		if not item is InventoryBag and bag.can_hold(item) and (not lost_inventory or item.kept):
			backpack.items.erase(item)
			_collect_into(item, bag)

func set_quickslot(index: int, item: InventoryItem) -> bool:
	if index < 0 or index >= quickslots.size(): return false
	if item != null and (not usable(item) or item.default_action.is_empty()): return false
	if item != null:
		for i in quickslots.size():
			if quickslots[i] == item: quickslots[i] = null
	quickslots[index] = item
	changed.emit()
	return true

func auto_quickslot(item: InventoryItem) -> bool:
	for i in quickslots.size():
		if quickslots[i] == null or quickslots[i] == item:
			return set_quickslot(i, item)
	return set_quickslot(0, item)

func _replace_placeholders(item: InventoryItem) -> void:
	for i in quickslots.size():
		if quickslots[i] != null and quickslots[i].quantity == 0 and quickslots[i].similar(item):
			for j in quickslots.size():
				if quickslots[j] == item: quickslots[j] = null
			quickslots[i] = item

func _clear_detached(item: InventoryItem, placeholder: bool) -> void:
	for i in quickslots.size():
		if quickslots[i] == item:
			if placeholder and item.stackable:
				quickslots[i] = item.copy_item()
				quickslots[i].quantity = 0
			else: quickslots[i] = null
		elif item is InventoryBag and item.contains(quickslots[i]):
			quickslots[i] = null

func detach(item: InventoryItem, amount: int = 1, placeholder: bool = true) -> InventoryItem:
	if not usable(item) or item == backpack or amount <= 0: return null
	if is_equipped(item) and not unequip(item, false): return null
	var bag := bag_of(item)
	var removed: InventoryItem
	if item.stackable and amount < item.quantity:
		removed = item.copy_item()
		removed.quantity = amount
		item.quantity -= amount
		if MissileRules.is_weapon(item): MissileRules.split(item, removed)
		_assign_uid(removed)
	else:
		removed = item
		if bag != null: bag.items.erase(item)
		_clear_detached(item, placeholder)
	if bag != null: refill(bag)
	changed.emit()
	return removed

func equipment_options(item: InventoryItem) -> Array:
	match item.category:
		"weapon": return ["weapon"]
		"armor": return ["armor"]
		"artifact": return ["artifact", "misc"]
		"ring": return ["ring", "misc"]
	return []

func equipment_needs_choice(item: InventoryItem) -> bool:
	var options := equipment_options(item)
	if options.size() < 2: return false
	if equipment[options[0]] == null or equipment.misc == null: return false
	var opposite: String = "ring" if item.category == "artifact" else "artifact"
	return equipment[opposite] != null or equipment.misc.category != opposite

func replacement_options(item: InventoryItem) -> Array:
	var options := equipment_options(item)
	if options.size() < 2: return options
	var opposite: String = "ring" if item.category == "artifact" else "artifact"
	if equipment.misc != null and equipment.misc.category == opposite: options.append(opposite)
	return options

func equip(item: InventoryItem, slot: String = "") -> bool:
	if not usable(item) or is_equipped(item): return false
	var options := equipment_options(item)
	if options.is_empty(): return false
	var bag := bag_of(item)
	if bag == null: return false
	var rearrange_to := ""
	if options.size() == 2 and equipment[options[0]] != null and equipment.misc != null:
		var opposite: String = "ring" if item.category == "artifact" else "artifact"
		if equipment[opposite] == null and equipment.misc.category == opposite:
			rearrange_to = opposite
	if slot.is_empty():
		slot = options[0]
		for option in options:
			if equipment[option] == null or (option == "misc" and not rearrange_to.is_empty()):
				slot = option
				break
	if not replacement_options(item).has(slot): return false
	var previous: InventoryItem = equipment[slot]
	if slot == "misc" and not rearrange_to.is_empty(): previous = null
	if previous != null and previous.cursed and not _magic_enabled():
		message.emit("被诅咒的装备无法取下！")
		return false
	if item.category == "artifact":
		for worn in equipment.values():
			if worn != null and worn.type_id == item.type_id:
				message.emit("不能同时装备两个相同的神器。")
				return false
	bag.items.erase(item)
	if not options.has(slot):
		equipment[slot] = equipment.misc
		equipment[slot].metadata["equipped_slot"] = slot
		slot = "misc"
	elif slot == "misc" and not rearrange_to.is_empty():
		equipment[rearrange_to] = equipment.misc
		equipment[rearrange_to].metadata["equipped_slot"] = rearrange_to
	equipment[slot] = item
	if previous != null:
		if _collect_into(previous, backpack) == null:
			_clear_detached(previous, false)
			dropped.emit(previous, hero_cell)
		var previous_slot := quickslots.find(previous)
		if previous_slot >= 0 and not quickslots.has(item) and not item.default_action.is_empty():
			quickslots[previous_slot] = item
	item.metadata["equipped_slot"] = slot
	refill(bag)
	refresh_equipment()
	turn_spent.emit(1.0)
	changed.emit()
	return true

func unequip(item: InventoryItem, collect_back: bool = true) -> bool:
	if not is_equipped(item): return false
	if item.cursed and not _magic_enabled():
		message.emit("被诅咒的装备无法取下！")
		changed.emit()
		return false
	for slot in equipment:
		if equipment[slot] == item: equipment[slot] = null
	item.metadata.erase("equipped_slot")
	refresh_equipment()
	if collect_back:
		if _collect_into(item, backpack) == null:
			_clear_detached(item, false)
			dropped.emit(item, hero_cell)
		turn_spent.emit(1.0)
	changed.emit()
	return true

func disarm_weapon(cell: Vector2i) -> InventoryItem:
	# Forced disarm bypasses curses, backpack capacity and voluntary action cost.
	var weapon: InventoryItem = equipment.weapon
	if weapon == null: return null
	equipment.weapon = null
	weapon.metadata.erase("equipped_slot")
	_clear_detached(weapon, false)
	changed.emit()
	dropped.emit(weapon, cell)
	return weapon

func actions(item: InventoryItem) -> Array:
	if not usable(item): return []
	var result: Array = [] if item == backpack else ["DROP", "THROW"]
	if not equipment_options(item).is_empty():
		result.append("UNEQUIP" if is_equipped(item) else "EQUIP")
	for action in item.extra_actions:
		if item.category == "artifact" and not is_equipped(item): continue
		if not result.has(action): result.append(action)
	if action_provider.is_valid():
		return action_provider.call(item, result)
	return result

func execute(item: InventoryItem, action: String = "") -> bool:
	if item == null: return false
	if action.is_empty(): action = default_action(item)
	if usable(item) and action == "CHOOSE" and default_action(item) == "CHOOSE":
		choice_requested.emit(item)
		return true
	if not actions(item).has(action): return false
	match action:
		"EQUIP": return equip(item)
		"UNEQUIP": return unequip(item)
		"DROP":
			var removed := detach(item, item.quantity, false)
			if removed == null: return false
			dropped.emit(removed, hero_cell)
			turn_spent.emit(1.0)
			return true
		"THROW":
			pending_item = item
			pending_action = action
			targeting_requested.emit(item, action)
			return true
	if item.targeting_actions.has(action):
		pending_item = item
		pending_action = action
		targeting_requested.emit(item, action)
		return true
	return _effect(item, action, hero_cell)

func _effect(item: InventoryItem, action: String, cell: Vector2i) -> bool:
	# Host returns false for unavailable/failed actions; no item is consumed implicitly.
	if not usable(item): return false
	if effect_handler.is_valid():
		return bool(effect_handler.call(item, action, cell))
	action_requested.emit(item, action, cell)
	return true

func finish_target(cell: Vector2i) -> bool:
	var item := pending_item
	var action := pending_action
	cancel_target()
	if not usable(item): return false
	if action == "THROW":
		if targeted_throw_handler.is_valid(): return bool(targeted_throw_handler.call(item, cell))
		var removed := detach(item)
		if removed == null: return false
		if throw_handler.is_valid(): throw_handler.call(removed, cell)
		else: dropped.emit(removed, cell)
		turn_spent.emit(1.0)
		return true
	return _effect(item, action, cell)

func cancel_target() -> void:
	pending_item = null
	pending_action = ""

func consume(item: InventoryItem, amount: int = 1) -> bool:
	return detach(item, amount) != null

func save_data() -> Dictionary:
	var worn := {}
	for slot in equipment:
		worn[slot] = equipment[slot].to_dict() if equipment[slot] != null else null
	var slots := []
	for item in quickslots:
		slots.append(null if item == null else {"uid": item.uid, "placeholder": item.to_dict() if item.quantity == 0 else null})
	return {"version": 1, "backpack": backpack.to_dict(), "equipment": worn, "quickslots": slots,
		"ring_state": ring_state.duplicate(true),
		"missile_state": missile_state.duplicate(true),
		"gold": gold, "energy": energy, "serial": _serial, "strength": hero_strength,
		"lost_inventory": lost_inventory, "alive": alive}

func load_data(data: Dictionary) -> bool:
	if not _valid_save(data): return false
	# Parse into a separate inventory first. Failed loads do not erase the player's inventory.
	var restored := DungeonInventory.new()
	restored.backpack = InventoryBag.restore(data.backpack)
	for slot in equipment:
		var entry = data.get("equipment", {}).get(slot)
		restored.equipment[slot] = InventoryItem.from_dict(entry) if entry is Dictionary else null
	# Preserve a retired secondary slot's item when loading an old inventory.
	var legacy_weapon = data.get("equipment", {}).get("second_weapon")
	if legacy_weapon is Dictionary:
		restored.backpack.items.append(InventoryItem.from_dict(legacy_weapon))
	var by_uid := {restored.backpack.uid: restored.backpack}
	for item in restored.all_items():
		if item.uid.is_empty() or by_uid.has(item.uid): return false
		by_uid[item.uid] = item
	var saved_slots: Array = data.get("quickslots", [])
	for i in mini(6, saved_slots.size()):
		var entry = saved_slots[i]
		if entry is Dictionary:
			restored.quickslots[i] = InventoryItem.from_dict(entry.placeholder) if entry.get("placeholder") is Dictionary else by_uid.get(entry.get("uid", ""))
	backpack = restored.backpack
	equipment = restored.equipment
	quickslots = restored.quickslots
	gold = int(data.get("gold", 0))
	energy = int(data.get("energy", 0))
	hero_strength = int(data.get("strength", 10))
	_serial = maxi(int(data.get("serial", 1)), by_uid.size() + 1)
	for uid in by_uid:
		if String(uid).begins_with("item_"): _serial = maxi(_serial, String(uid).substr(5).to_int() + 1)
	lost_inventory = bool(data.get("lost_inventory", false))
	ring_state = data.get("ring_state", {}).duplicate(true)
	missile_state = data.get("missile_state", {}).duplicate(true)
	alive = bool(data.get("alive", true))
	cancel_target()
	changed.emit()
	return true

func _valid_save(data: Dictionary) -> bool:
	if data.has("ring_state") and not data.ring_state is Dictionary: return false
	if data.has("missile_state") and not data.missile_state is Dictionary: return false
	if not data.get("version") is float and not data.get("version") is int: return false
	if int(data.version) != 1 or not data.get("backpack") is Dictionary: return false
	if data.backpack.get("kind") != "backpack" or not _valid_item_data(data.backpack): return false
	if not data.get("equipment", {}) is Dictionary or not data.get("quickslots", []) is Array: return false
	for field in ["gold", "energy", "serial", "strength"]:
		var value = data.get(field, 0)
		if not value is float and not value is int: return false
	for entry in data.get("equipment", {}).values():
		if entry != null and (not entry is Dictionary or not _valid_item_data(entry)): return false
	for entry in data.get("quickslots", []):
		if entry == null: continue
		if not entry is Dictionary or not entry.get("uid", "") is String: return false
		var placeholder = entry.get("placeholder")
		if placeholder != null and (not placeholder is Dictionary or not _valid_item_data(placeholder, true)): return false
	return true

func _valid_item_data(data: Dictionary, placeholder: bool = false, depth: int = 0) -> bool:
	if depth > 2: return false
	var template := InventoryItem.new()
	for field in InventoryItem.FIELDS:
		if not data.has(field): continue
		var value = data[field]
		var expected_type := typeof(template.get(field))
		if expected_type == TYPE_INT:
			if not value is int and not value is float: return false
		elif typeof(value) != expected_type: return false
	if int(data.get("quantity", 1)) < (0 if placeholder else 1): return false
	for field in ["extra_actions", "targeting_actions"]:
		for action in data.get(field, []):
			if not action is String: return false
	if data.has("kind"):
		if depth > 1: return false
		if not InventoryBag.DEFINITIONS.has(data.kind) or not data.get("items") is Array: return false
		if depth > 0 and data.kind == "backpack": return false
		for entry in data.items:
			if not entry is Dictionary or not _valid_item_data(entry, false, depth + 1): return false
	return true
