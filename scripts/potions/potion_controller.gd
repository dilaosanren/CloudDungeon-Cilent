## Potion use through the same bag / item window / quickslots as SPD.
class_name PotionController
extends WandController
signal used(item: InventoryItem, action: String, cost: float)
var potion_world: PotionWorld
var potion_effects: PotionEffects
var inventory: DungeonInventory
var caster: WandActor
var _operation: Callable

func bind(map: DungeonMap) -> void:
	dungeon = map
	if get_parent() == map: map.move_child(self, map.fog_renderer.get_index())
	potion_world = PotionWorld.new()
	potion_world.bind(map.environment, map.ballistic_level)
	world = potion_world
	world.event.connect(_event)
	potion_effects = PotionEffects.new()
	potion_effects.world = world
	effects = potion_effects
	add_child(effects)

func setup_inventory(model: DungeonInventory, actor: WandActor) -> void:
	if is_instance_valid(caster) and caster.status_added.is_connected(_buff_added): caster.status_added.disconnect(_buff_added)
	inventory = model; caster = actor
	model.bind_actor(actor)
	actor.status_added.connect(_buff_added)
	model.effect_handler = func(item, action, cell): return drink(item, actor, world.level.cell_id(cell)) if action == "DRINK" else false
	model.targeted_throw_handler = func(item, target): return throw_item(item, actor, world.level.cell_id(target))
	model.action_provider = func(_item, actions): return [] if busy or actor.hp <= 0 or actor.has_status("paralysis") or actor.has_status("frost") else actions

func _buff_added(effect: String) -> void:
	if effect != "frost" or inventory == null or inventory.lost_inventory: return
	var exposed: Array[InventoryItem] = []
	# Frost shatters one exposed potion; the bandolier protects its contents.
	for item in inventory.backpack.items:
		if not item.unique and item.type_id in PotionWorld.TYPES: exposed.append(item)
	if not exposed.is_empty():
		var item := exposed[world.rng.randi_range(0, exposed.size() - 1)]
		var detached := inventory.detach(item)
		if detached != null: potion_world.shatter(detached, caster.cell)

func _validate(item: InventoryItem, actor: WandActor) -> String:
	if busy: return "正在使用物品"
	if actor.hp <= 0: return "角色已经倒下"
	if actor.has_status("paralysis") or actor.has_status("frost"): return "当前状态无法使用物品"
	if item.type_id not in PotionWorld.TYPES: return "这不是可用的药水"
	if inventory == null or not inventory.usable(item): return "背包内没有这瓶药水"
	return ""

func drink(item: InventoryItem, actor: WandActor, target: int = -1) -> bool:
	var error := _validate(item, actor)
	if not error.is_empty(): rejected.emit(error); return false
	if item.type_id == "PotionOfDragonsBreath":
		var plan := potion_world.prepare_breath(actor,target)
		if plan.has("error"): rejected.emit(str(plan.error)); return false
		if not inventory.consume(item): return false
		busy = true
		var generation := _generation
		potion_effects.breathe(actor,potion_world.breath_visual(plan),func():
			if generation != _generation: return
			potion_world.resolve_breath(plan)
			_complete(item,"DRINK"))
		updated.emit()
		return true
	busy = true
	if not inventory.consume(item): busy = false; return false
	potion_world.apply(item, actor)
	potion_effects.sound("drink")
	var generation := _generation
	_operation = func(action):
		if action != &"operate" or generation != _generation: return
		_complete(item, "DRINK")
	if is_instance_valid(actor.sprite) and actor.sprite is DungeonHeroSprite:
		actor.sprite.action_finished.connect(_operation, CONNECT_ONE_SHOT)
		actor.sprite.play_action(&"operate")
	else: _complete(item, "DRINK")
	updated.emit()
	return true

func throw_item(item: InventoryItem, actor: WandActor, target: int) -> bool:
	var error := _validate(item, actor)
	if not world.level.inside_map(target): error = "目标不在地图内"
	if not error.is_empty(): rejected.emit(error); return false
	var ray := Ballistica.new(actor.cell, target, Ballistica.PROJECTILE, world.level)
	busy = true
	var generation := _generation
	if is_instance_valid(actor.sprite) and actor.sprite is DungeonHeroSprite:
		actor.sprite.face_cell(world.level.cell_coords(ray.collision_pos)); actor.sprite.play_action(&"zap")
	potion_effects.throw_potion(item, actor, ray.collision_pos, func():
		if generation != _generation: return
		if inventory.usable(item):
			var detached := inventory.detach(item)
			if detached != null: potion_world.on_throw(detached, ray.collision_pos)
		_complete(item, "THROW"))
	updated.emit()
	return true

func _complete(item: InventoryItem, action: String) -> void:
	_operation = Callable()
	busy = false
	inventory.changed.emit()
	finished.emit(item)
	used.emit(item, action, 1.0)
	updated.emit()

func cancel() -> void:
	if is_instance_valid(caster) and is_instance_valid(caster.sprite) and _operation.is_valid() and caster.sprite.action_finished.is_connected(_operation):
		caster.sprite.action_finished.disconnect(_operation)
	_operation = Callable()
	super.cancel()

func _exit_tree() -> void:
	if is_instance_valid(caster) and caster.status_added.is_connected(_buff_added): caster.status_added.disconnect(_buff_added)
	super._exit_tree()

func _event(e: Dictionary) -> void:
	super._event(e)
	match e.action:
		"potion_snow": potion_effects.snow_at(int(e.cell),int(e.count),float(e.interval))
		"splash": potion_effects.splash_at(potion_effects.actor_point(e.actor) if e.actor != null else potion_effects.point(e.cell, false), potion_effects.potion_color(e.item), e.count)
		"discover_speck":
			for i in e.count: potion_effects.speck("discover", potion_effects.point(e.cell, false) + Vector2(potion_effects.rng.randf_range(-8, 8), potion_effects.rng.randf_range(-8, 8)))
		"spell": potion_effects.spell(e.actor, e.index, e.color)
		"flare": potion_effects.flare(e.actor, e.color)
		"sound": potion_effects.sound(e.sound)
		"strength", "experience":
			var actor: WandActor = e.actor
			if is_instance_valid(actor.sprite):
				var layer := CombatTextLayer.for_actor(actor.sprite)
				layer.show_status(layer.to_local(actor.sprite.to_global(Vector2(0, -13))), str(e.amount), Color.GREEN,
					CombatTextAssets.Icon.STRENGTH if e.action == "strength" else CombatTextAssets.Icon.EXPERIENCE, world.level.cell_coords(actor.cell))
