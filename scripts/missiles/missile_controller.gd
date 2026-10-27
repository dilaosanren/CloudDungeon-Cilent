# Bag/quickslot casts plus original Dart TIP/CLEAN and last-upgraded-item warning.
class_name MissileController
extends RingController
signal thrown(result: Dictionary)
signal dart_selection_requested(item: InventoryItem, prompt: String, predicate: Callable)
signal break_warning_requested(item: InventoryItem, confirm: Callable)
var missile_world: MissileWorld
var missile_effects: MissileEffects
var pending_dart: InventoryItem
var _returns_in_flight := 0

func bind(map: DungeonMap) -> void:
	dungeon = map
	if get_parent() == map: map.move_child(self, map.fog_renderer.get_index())
	missile_world = MissileWorld.new(); missile_world.bind(map.environment, map.ballistic_level)
	ring_world = missile_world; scroll_world = missile_world; potion_world = missile_world; world = missile_world; world.event.connect(_event)
	missile_effects = MissileEffects.new(); missile_effects.world = world
	scroll_effects = missile_effects; potion_effects = missile_effects; effects = missile_effects; add_child(effects)

func setup_inventory(model: DungeonInventory, actor: WandActor) -> void:
	super.setup_inventory(model, actor)
	var previous := model.effect_handler
	model.effect_handler = func(item, action, cell):
		if action == "TIP": return request_tip(item)
		if action == "CLEAN": return request_clean(item)
		return previous.call(item, action, cell)
	var provider := model.action_provider
	model.action_provider = func(item, actions): return [] if pending_dart != null else provider.call(item, actions)

func _throw_error(item: InventoryItem, actor: WandActor, target: int) -> String:
	if busy or pending_scroll != null or pending_dart != null: return "正在使用物品"
	if actor.hp <= 0 or actor.has_status("paralysis") or actor.has_status("frost") or actor.has_status("magical_sleep"): return "当前状态无法投掷"
	if actor.sprite is DungeonHeroSprite and actor.sprite.moving: return "正在移动"
	if not inventory.usable(item): return "背包内没有这件武器"
	if not world.level.inside_map(target): return "目标不在地图内"
	return ""
func throw_inventory_item(item: InventoryItem, actor: WandActor, target: int, confirmed: bool = false) -> bool:
	if not MissileRules.is_weapon(item): return super.throw_inventory_item(item, actor, target)
	var error := _throw_error(item, actor, target)
	if not error.is_empty(): rejected.emit(error); return false
	_sync_vision()
	var cell := missile_world.throw_cell(item, actor, target)
	var generation := _generation; busy = true
	if actor.sprite is DungeonHeroSprite: actor.sprite.face_cell(world.level.cell_coords(cell)); actor.sprite.play_action(&"zap")
	missile_effects.throw_weapon(item, actor, cell, func():
		if generation != _generation: return
		var parent: InventoryItem = item if item.quantity > 1 else null
		var projectile := inventory.detach(item)
		if projectile != null:
			var result := missile_world.resolve_throw(projectile, actor, cell, parent)
			busy = false; inventory.changed.emit(); finished.emit(item); used.emit(item, "THROW", result.cost); thrown.emit(result); updated.emit()
		else: busy = false)
	updated.emit(); return true

func request_tip(item: InventoryItem) -> bool:
	if busy or pending_dart != null or pending_scroll != null or not inventory.usable(item) or item.type_id != "Dart": return false
	pending_dart = item
	var predicate := func(seed): return MissileRules.source().seed_tips.has(seed.type_id)
	if inventory_ui != null: inventory_ui.select_item("选择用于涂药的种子", predicate, select_seed, "pouch")
	dart_selection_requested.emit(item, "选择用于涂药的种子", predicate); return true
func select_seed(seed: InventoryItem) -> void:
	if pending_dart == null: return
	if seed == null: pending_dart = null; return
	if not inventory.usable(seed) or not MissileRules.source().seed_tips.has(seed.type_id): return
	var count := mini(pending_dart.quantity, seed.quantity * 2)
	if inventory_ui == null: tip(seed, count); return
	var type: String = MissileRules.source().seed_tips[seed.type_id]
	var result := InventoryCatalog.create(type)
	var choices := ["涂药全部 %d 支" % count, "涂药 %d 支" % mini(2, count), "取消"] if count > 2 else ["涂药 %d 支" % count, "取消"]
	inventory_ui.show_options(result, result.description, choices, func(index):
		if index == 0: tip(seed, count)
		elif index == 1 and choices.size() == 3: tip(seed, mini(2, count))
		else: pending_dart = null)
func tip(seed: InventoryItem, count: int) -> bool:
	var darts := pending_dart
	if darts == null or not inventory.usable(darts) or not inventory.usable(seed): pending_dart = null; return false
	count = mini(count, mini(darts.quantity, seed.quantity * 2))
	if count <= 0: pending_dart = null; return false
	var type: String = MissileRules.source().seed_tips[seed.type_id]
	inventory.detach(seed, ceili(count / 2.0), false); inventory.detach(darts, count, false)
	var result := MissileRules.create(type, count)
	if not inventory.collect(result): inventory.dropped.emit(result, inventory.hero_cell)
	pending_dart = null; _operate_dart(darts, "TIP"); return true
func request_clean(item: InventoryItem) -> bool:
	if busy or pending_dart != null or pending_scroll != null or not inventory.usable(item) or not MissileRules.tipped(item): return false
	pending_dart = item
	if inventory_ui == null: return clean(item.quantity)
	var choices := ["清洗全部", "清洗一支", "取消"] if item.quantity > 1 else ["清洗一支", "取消"]
	inventory_ui.show_options(item, "清洗将移除药剂，把它变回普通飞镖。", choices, func(index):
		if index == 0: clean(item.quantity)
		elif index == 1 and choices.size() == 3: clean(1)
		else: pending_dart = null)
	return true
func clean(count: int) -> bool:
	var item := pending_dart
	if item == null or not inventory.usable(item): pending_dart = null; return false
	count = mini(count, item.quantity); inventory.detach(item, count, false)
	var result := MissileRules.create("Dart", count)
	if not inventory.collect(result): inventory.dropped.emit(result, inventory.hero_cell)
	pending_dart = null; _operate_dart(item, "CLEAN"); return true
func _operate_dart(item: InventoryItem, action: String) -> void:
	if inventory_ui != null: inventory_ui.close_bag(); inventory_ui._close_detail()
	busy = true; var generation := _generation
	_operation = func(which):
		if which != &"operate" or generation != _generation: return
		_operation = Callable(); busy = false; inventory.changed.emit(); finished.emit(item); used.emit(item, action, 1.0); updated.emit()
	if caster.sprite is DungeonHeroSprite: caster.sprite.action_finished.connect(_operation, CONNECT_ONE_SHOT); caster.sprite.play_action(&"operate")
	else: _operation.call(&"operate")
func cancel() -> void:
	pending_dart = null; _returns_in_flight = 0; super.cancel()
func _event(e: Dictionary) -> void:
	super._event(e)
	match e.action:
		"missile_drop": inventory.dropped.emit(e.item, world.level.cell_coords(e.cell))
		"missile_return":
			var circle: Dictionary = e.circle; circle.awaiting_visual = true
			_returns_in_flight += 1; busy = true
			var generation := _generation
			missile_effects.throw_weapon(circle.item, circle.actor, circle.to, func():
				if generation == _generation:
					missile_world.finish_return(circle); _returns_in_flight -= 1; busy = _returns_in_flight > 0; inventory.changed.emit(); updated.emit(), circle.from, true)
		"missile_hit_sound": missile_effects.sound(e.sound, e.pitch * effects.rng.randf_range(0.87, 1.15))
		"missile_shock":
			var pos := effects.actor_point(e.actor)
			effects.lightning(pos + Vector2(-6, 0), pos + Vector2(6, 0)); effects.lightning(pos + Vector2(0, -6), pos + Vector2(0, 6)); effects.sound("lightning")
		"missile_holy": scroll_effects.start_specks(e.actor, e.cell, "shadow_up", 0.05, e.count, true); effects.sound("burning")
		"missile_blood": potion_effects.splash_at(effects.actor_point(e.actor), Color("bb0000"), e.count)
		"missile_blocked":
			if e.actor.sprite is DungeonHeroSprite: e.actor.sprite.show_block()
