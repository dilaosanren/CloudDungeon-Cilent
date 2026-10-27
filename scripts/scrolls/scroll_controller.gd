# Known InventoryScroll selection and HeroSprite.read operation adapter.
class_name ScrollController
extends PotionController
signal selection_requested(scroll: InventoryItem, prompt: String, predicate: Callable)
var scroll_world: ScrollWorld
var scroll_effects: ScrollEffects
var inventory_ui: InventoryUI
var pending_scroll: InventoryItem
var pending_selection: InventoryItem
var _repeat_target: InventoryItem

func bind(map: DungeonMap) -> void:
	dungeon = map
	if get_parent() == map: map.move_child(self, map.fog_renderer.get_index())
	scroll_world = ScrollWorld.new(); scroll_world.bind(map.environment, map.ballistic_level)
	potion_world = scroll_world; world = scroll_world; world.event.connect(_event)
	scroll_effects = ScrollEffects.new(); scroll_effects.world = world
	potion_effects = scroll_effects; effects = scroll_effects; add_child(effects)

func setup_inventory(model: DungeonInventory, actor: WandActor) -> void:
	super.setup_inventory(model, actor); scroll_world.inventory = model
	model.targeted_throw_handler = func(item, target): return throw_inventory_item(item, actor, world.level.cell_id(target))
	model.effect_handler = func(item, action, cell):
		match action:
			"READ": return read(item, actor)
			"DRINK": return drink(item, actor)
			"ZAP": world.carry(actor, inventory.all_items()); return cast(item, actor, world.level.cell_id(cell))
		return false
	model.action_provider = func(_item, actions): return [] if busy or pending_scroll != null or actor.hp <= 0 or actor.has_status("paralysis") or actor.has_status("frost") or actor.has_status("magical_sleep") else actions

func _scroll_error(item: InventoryItem, actor: WandActor, selecting: bool = false) -> String:
	if item == null or actor == null or inventory == null: return "没有可读的卷轴"
	if busy or (pending_scroll != null and not selecting): return "正在使用物品"
	if actor.sprite is DungeonHeroSprite and actor.sprite.moving: return "正在移动"
	if actor.hp <= 0: return "角色已经倒下"
	if actor.has_status("paralysis") or actor.has_status("frost") or actor.has_status("magical_sleep"): return "当前状态无法阅读卷轴"
	if actor.has_status("magic_immune") or inventory.magic_immune: return "魔法免疫阻止了卷轴的魔法"
	if actor.has_status("blindness"): return "失明时无法阅读卷轴"
	if actor.data.get("cursed_spellbook", false) and item.type_id != "ScrollOfRemoveCurse": return "被诅咒的法术书阻止了阅读"
	if item.type_id not in ScrollWorld.SCROLL_TYPES: return "演示仅接入十二种基础卷轴"
	if inventory == null or not inventory.usable(item): return "背包内没有这张卷轴"
	return ""

func _sync_vision() -> void:
	if not dungeon.fog_enabled: return
	world.visible = dungeon.visibility_state.visible.duplicate(); scroll_world.visited = dungeon.visibility_state.visited.duplicate()
	world.discoverable = dungeon.visibility_state.discoverable.duplicate(); world.mapped = dungeon.visibility_state.mapped.duplicate()

func read(item: InventoryItem, actor: WandActor) -> bool:
	var error := _scroll_error(item, actor)
	if not error.is_empty(): rejected.emit(error); return false
	_sync_vision()
	if item.type_id in ScrollWorld.INVENTORY_SCROLLS and not (item.type_id == "ScrollOfRemoveCurse" and scroll_world.cleansing_spirit(actor) != null):
		pending_scroll = item; _request_selection(); return true
	return _read_now(item, actor)

func _request_selection() -> void:
	if pending_scroll == null: return
	var item := pending_scroll
	var prompt := "选择要升级的物品" if item.type_id == "ScrollOfUpgrade" else "选择要净化的物品" if item.type_id == "ScrollOfRemoveCurse" else "选择要嬗变的物品"
	var predicate := func(candidate): return scroll_world.selectable(item, candidate, caster)
	if inventory_ui != null: inventory_ui.select_item(prompt, predicate, select_target, "backpack")
	selection_requested.emit(item, prompt, predicate)

func select_target(item: InventoryItem) -> void:
	if pending_scroll == null: return
	if item == null: pending_scroll = null; pending_selection = null; updated.emit(); return
	if not scroll_world.selectable(pending_scroll, item, caster): rejected.emit("不能对这件物品使用卷轴"); return
	if inventory_ui != null:
		inventory_ui.close_bag(false); inventory_ui.selector = Callable(); inventory_ui.selection_callback = Callable(); inventory_ui.selection_prompt = ""
	pending_selection = item
	if pending_scroll.type_id == "ScrollOfUpgrade" and inventory_ui != null:
		inventory_ui.show_upgrade_preview(pending_scroll, item, confirm_upgrade, func(): pending_selection = null; _request_selection())
	else: _finish_selection()

func confirm_upgrade() -> void:
	if inventory_ui != null: inventory_ui._close_detail()
	_finish_selection()

func _finish_selection() -> void:
	var scroll := pending_scroll; var selected := pending_selection
	if scroll == null or selected == null: return
	var error := _scroll_error(scroll, caster, true)
	if not error.is_empty(): rejected.emit(error); cancel_selection(); return
	if not scroll_world.selectable(scroll, selected, caster): rejected.emit("目标物品已不可用"); cancel_selection(); return
	_repeat_target = selected if scroll.type_id == "ScrollOfUpgrade" and inventory_ui != null else null
	pending_scroll = null; pending_selection = null; _read_now(scroll, caster, selected)

func _read_now(item: InventoryItem, actor: WandActor, selected: InventoryItem = null) -> bool:
	# Detach before changing another stack, as in known InventoryScroll.
	var detached := inventory.detach(item)
	if detached == null: return false
	busy = true
	if not scroll_world.apply_scroll(item, actor, selected):
		inventory.collect(detached); busy = false; rejected.emit("此目标无法产生卷轴效果，卷轴已返还"); return false
	inventory.hero_cell = world.level.cell_coords(actor.cell); world.carry(actor, inventory.all_items())
	if item.type_id not in ["ScrollOfLullaby", "ScrollOfRage", "ScrollOfRetribution"]: scroll_effects.sound("read")
	var cost := scroll_world.last_read_time
	if cost == 0: _complete_read(item, cost); return true
	var generation := _generation
	_operation = func(action):
		if action != &"read" or generation != _generation: return
		_complete_read(item, cost)
	if is_instance_valid(actor.sprite) and actor.sprite is DungeonHeroSprite:
		actor.sprite.action_finished.connect(_operation, CONNECT_ONE_SHOT); actor.sprite.play_action(&"read")
	else: _complete_read(item, cost)
	updated.emit(); return true

func _complete_read(item: InventoryItem, cost: float) -> void:
	_operation = Callable(); busy = false
	inventory.changed.emit(); finished.emit(item); used.emit(item, "READ", cost); updated.emit()
	if _repeat_target != null and inventory.usable(_repeat_target) and ScrollWorld.upgradable(_repeat_target) and caster.hp > 0:
		for more in inventory.all_items():
			if more.type_id == "ScrollOfUpgrade" and inventory.usable(more):
				pending_scroll = more; pending_selection = _repeat_target
				inventory_ui.show_upgrade_preview(more, _repeat_target, confirm_upgrade, func(): _repeat_target = null; pending_selection = null; _request_selection())
				return
	_repeat_target = null

func throw_inventory_item(item: InventoryItem, actor: WandActor, target: int) -> bool:
	if item.type_id in PotionWorld.TYPES: return throw_item(item, actor, target)
	if busy or pending_scroll != null or not inventory.usable(item) or not world.level.inside_map(target): return false
	var ray := Ballistica.new(actor.cell, target, Ballistica.PROJECTILE, world.level)
	busy = true; var generation := _generation
	if actor.sprite is DungeonHeroSprite: actor.sprite.face_cell(world.level.cell_coords(target)); actor.sprite.play_action(&"zap")
	scroll_effects.throw_potion(item, actor, ray.collision_pos, func():
		if generation != _generation: return
		var detached := inventory.detach(item)
		if detached != null: inventory.dropped.emit(detached, world.level.cell_coords(ray.collision_pos))
		_complete(item, "THROW"))
	return true

func cancel_selection() -> void:
	pending_scroll = null; pending_selection = null; _repeat_target = null
	if inventory_ui != null and is_instance_valid(inventory_ui): inventory_ui.close_bag(); inventory_ui._close_detail()

func _validate(item: InventoryItem, actor: WandActor) -> String:
	if actor.has_status("magical_sleep"): return "魔法睡眠中无法使用物品"
	if actor.sprite is DungeonHeroSprite and actor.sprite.moving: return "正在移动"
	return super._validate(item, actor)

func cancel() -> void:
	cancel_selection(); super.cancel()

func _event(e: Dictionary) -> void:
	if e.action == "move" and e.actor == caster: updated.emit(); return
	if e.action == "move" and e.actor.species == "mirror_image" and is_instance_valid(e.actor.sprite):
		var pos := world.level.cell_coords(e.actor.cell)
		dungeon.track_visibility(e.actor.sprite, pos); e.actor.sprite.walk_to_cell(pos); updated.emit(); return
	super._event(e)
	match e.action:
		"scroll_specks": scroll_effects.start_specks(e.get("actor"), e.cell, e.kind, e.interval, e.count, e.center)
		"scroll_flare": scroll_effects.scroll_flare(e.actor, e.color, e.rays)
		"identification": scroll_effects.identification(e.actor)
		"transmutation": scroll_effects.transmute(e.actor, e.old, e.new)
		"scroll_flash": scroll_effects.flash(e.color)
		"scroll_failed": rejected.emit(e.reason)
		"scroll_teleport": scroll_effects.appear(e.actor, e.from)
		"mirror_spawn":
			var actor: WandActor = e.actor
			var sprite := ScrollMirrorSprite.new(); sprite.actor = actor; dungeon.add_child(sprite)
			dungeon.move_child(sprite, dungeon.layers["RaisedGrass"].get_index()); actor.sprite = sprite
			sprite.place_cell(world.level.cell_coords(actor.cell)); dungeon.track_visibility(sprite, world.level.cell_coords(actor.cell))
		"mirror_attack":
			if e.actor.sprite is DungeonHeroSprite: e.actor.sprite.face_cell(world.level.cell_coords(e.target.cell)); e.actor.sprite.play_action(&"attack")
