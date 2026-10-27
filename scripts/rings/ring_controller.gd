class_name RingController
extends ScrollController
signal tested(result: Dictionary)
signal ground_item(item: InventoryItem, cell: Vector2i, sprite: DungeonItemSprite)
var ring_world: RingWorld

func bind(map: DungeonMap) -> void:
	dungeon = map
	if get_parent() == map: map.move_child(self, map.fog_renderer.get_index())
	ring_world = RingWorld.new(); ring_world.bind(map.environment, map.ballistic_level)
	scroll_world = ring_world; potion_world = ring_world; world = ring_world; world.event.connect(_event)
	scroll_effects = ScrollEffects.new(); scroll_effects.world = world
	potion_effects = scroll_effects; effects = scroll_effects; add_child(effects)

func setup_inventory(model: DungeonInventory, actor: WandActor) -> void:
	super.setup_inventory(model, actor); ring_world.player = actor

func fight(target: WandActor, kind: String = "melee", weapon: InventoryItem = null, armed: bool = true) -> bool:
	if busy or pending_scroll != null or caster.sprite is DungeonHeroSprite and caster.sprite.moving: return false
	var result := ring_world.attack(caster, target, kind, weapon, armed)
	if result.has("error"): rejected.emit(result.error); return false
	busy = true; var generation := _generation
	_operation = func(action):
		if action != &"attack" or generation != _generation: return
		_operation = Callable(); busy = false; tested.emit(result); updated.emit()
	if caster.sprite is DungeonHeroSprite:
		caster.sprite.face_cell(world.level.cell_coords(target.cell)); caster.sprite.action_finished.connect(_operation, CONNECT_ONE_SHOT); caster.sprite.play_action(&"attack")
	else: _operation.call(&"attack")
	return true

## Bag/quickslot projectiles use the same Aim/Accuracy/Furor rules as arena tests.
func throw_inventory_item(item: InventoryItem, actor: WandActor, target: int) -> bool:
	if item.category != "missile": return super.throw_inventory_item(item, actor, target)
	if busy or pending_scroll != null or not inventory.usable(item) or not world.level.inside_map(target): return false
	var ray := Ballistica.new(actor.cell, target, Ballistica.PROJECTILE, world.level)
	busy = true; var generation := _generation
	if actor.sprite is DungeonHeroSprite: actor.sprite.face_cell(world.level.cell_coords(target)); actor.sprite.play_action(&"zap")
	scroll_effects.throw_potion(item, actor, ray.collision_pos, func():
		if generation != _generation: return
		var victim := world.actor_at(ray.collision_pos)
		var cost := RingCombat.attack_cost(actor)
		var broken := false
		if victim != null and victim != actor:
			var result := ring_world.attack(actor, victim, "missile", item)
			broken = result.get("broken", false)
		else: broken = RingCombat.use_missile(actor, item, 5 if item.type_id == "ThrowingKnife" else 8)
		var detached := inventory.detach(item)
		if detached != null and not broken: inventory.dropped.emit(detached, world.level.cell_coords(ray.collision_pos))
		busy = false; inventory.changed.emit(); finished.emit(item); used.emit(item, "THROW", cost); updated.emit())
	return true

func _event(e: Dictionary) -> void:
	super._event(e)
	match e.action:
		"ring_blazing": effects.burst("fire", effects.actor_point(e.actor), 1)
		"ring_loot":
			var cell := world.level.cell_coords(e.cell)
			var sprite := dungeon.place_item(cell, e.item.visual)
			ground_item.emit(e.item, cell, sprite)
			if e.tier > 0:
				var tier: int = e.tier
				var colors := [Color("00ff00"), Color("00aaff"), Color("aa00ff"), Color("ffaa00")]
				scroll_effects.flares.append({"actor": e.actor, "pos": effects.actor_point(e.actor), "age": 0.0, "rays": 6,
					"radius": 16 + 4 * tier, "duration": [3.0, 3.33, 3.67, 4.0][tier - 1], "color": colors[tier - 1]})
