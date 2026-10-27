class_name MeleeController
extends MissileController
signal imbue_selection_requested(staff: InventoryItem)
var melee_world: MeleeWorld
var pending_staff: InventoryItem
func bind(map: DungeonMap) -> void:
	dungeon = map
	if get_parent() == map: map.move_child(self, map.fog_renderer.get_index())
	melee_world = MeleeWorld.new(); melee_world.bind(map.environment, map.ballistic_level)
	missile_world = melee_world; ring_world = melee_world; scroll_world = melee_world; potion_world = melee_world; world = melee_world; world.event.connect(_event)
	var visual := MeleeEffects.new(); visual.world = world
	missile_effects = visual; scroll_effects = visual; potion_effects = visual; effects = visual; add_child(effects)
func setup_inventory(model: DungeonInventory, actor: WandActor) -> void:
	super.setup_inventory(model, actor)
	var previous := model.effect_handler
	model.effect_handler = func(item, action, cell):
		if MeleeRules.is_weapon(item):
			match action:
				"IMBUE": return request_imbue(item)
				"ZAP": return cast_staff(item, world.level.cell_id(cell))
		return previous.call(item, action, cell)
	var provider := model.action_provider
	model.action_provider = func(item, actions): return [] if pending_staff != null else provider.call(item, actions)
func unavailable() -> bool:
	return busy or pending_scroll != null or pending_dart != null or pending_staff != null or caster.sprite is DungeonHeroSprite and caster.sprite.moving
func animate(a: WandActor, action: StringName, target: int, callback: Callable) -> void:
	var generation := _generation
	_operation = func(which):
		if which != action or generation != _generation: return
		_operation = Callable(); callback.call()
	if a.sprite is DungeonHeroSprite:
		a.sprite.face_cell(world.level.cell_coords(target)); a.sprite.action_finished.connect(_operation, CONNECT_ONE_SHOT); a.sprite.play_action(action)
	else: _operation.call(action)
func fight(target: WandActor, kind: String = "melee", item: InventoryItem = null, armed: bool = true) -> bool:
	if kind != "melee": return super.fight(target, kind, item, armed)
	if unavailable(): return false
	if item == null and armed: item = melee_world.weapon(caster)
	var error := melee_world.action_error(caster)
	if error.is_empty() and not melee_world.can_attack(caster, target, item): error = "目标超出攻击距离，或路径被阻挡"
	if not error.is_empty(): rejected.emit(error); return false
	busy = true
	animate(caster, &"attack", target.cell, func():
		var result := melee_world.attack(caster, target, kind, item, armed)
		busy = false
		if result.has("error"): rejected.emit(result.error)
		else: tested.emit(result)
		inventory.changed.emit(); updated.emit())
	return true
func request_imbue(staff: InventoryItem) -> bool:
	if unavailable() or not inventory.usable(staff): return false
	pending_staff = staff
	if inventory_ui != null:
		inventory_ui.select_item("选择灌注到法师魔杖中的法杖", func(item): return item.category == "wand" and not item.cursed, select_imbue)
	imbue_selection_requested.emit(staff); return true
func select_imbue(wand: InventoryItem) -> void:
	if wand == null: pending_staff = null; return
	if pending_staff == null or not inventory.usable(wand) or wand.category != "wand" or wand.cursed: return
	if inventory_ui != null:
		inventory_ui.show_options(pending_staff, "灌注会消耗所选法杖，并替换魔杖内的法杖。", ["灌注", "取消"], func(index):
			if index == 0: imbue(wand)
			else: pending_staff = null)
	else: imbue(wand)
func imbue(wand: InventoryItem) -> bool:
	if pending_staff == null or not inventory.usable(pending_staff) or not inventory.usable(wand) or wand.cursed: pending_staff = null; return false
	var staff := pending_staff; pending_staff = null
	if inventory_ui != null: inventory_ui._close_detail(); inventory_ui.close_bag()
	inventory.detach(wand, 1, false); melee_world.staff_cache.erase(staff.get_instance_id()); MeleeStaff.imbue(staff, wand)
	melee_world.carry(caster, inventory.all_items()); inventory.changed.emit(); updated.emit(); return true
func cast_staff(staff: InventoryItem, cell: int) -> bool:
	if unavailable() or not inventory.usable(staff): return false
	var wand := melee_world.embedded(staff)
	if wand == null: rejected.emit("先用灌注为法师魔杖加入法杖"); return false
	melee_world.carry(caster, inventory.all_items()); _sync_vision()
	var plan := world.prepare(wand, caster, cell)
	if plan.has("error"): rejected.emit(plan.error); return false
	busy = true; var generation := _generation
	if caster.sprite is DungeonHeroSprite: caster.sprite.face_cell(world.level.cell_coords(cell)); caster.sprite.play_action(&"zap")
	effects.play(plan, func():
		if generation != _generation: return
		world.resolve(plan); MeleeStaff.save(staff, wand); busy = false; inventory.changed.emit(); used.emit(staff, "ZAP", 1.0); updated.emit())
	return true
func cancel() -> void:
	pending_staff = null; super.cancel()
func _event(e: Dictionary) -> void:
	if e.action == "melee_sound": effects.sound(e.sound, e.pitch * effects.rng.randf_range(0.87, 1.15))
	elif e.action == "move" and e.actor == caster and caster.sprite is DungeonHeroSprite and not caster.sprite.moving:
		if caster.sprite is DungeonHeroSprite: caster.sprite.place_cell(world.level.cell_coords(caster.cell))
		super._event(e)
	else: super._event(e)
