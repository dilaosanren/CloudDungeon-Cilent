# Local journal seed throw -> grow -> step -> effect, using actual plant rules.
extends "res://scripts/menu/potion_sandbox.gd"
const Nature = preload("res://scripts/nature/nature_rules.gd")

class LocalSeedEffects extends "res://scripts/nature/nature_effects.gd":
	const BUFFS = preload("res://assets/ui/source/buffs.png")
	const ICONS = {"poison":3, "time_bubble":7, "chill":15, "blindness":16,
		"weakness":14, "cripple":23, "bless":37, "vertigo":33, "burning":2}
	func _ready() -> void:
		super._ready()
		var canvas := _flash.get_parent()
		_flash.reparent(self)
		canvas.queue_free()
		_flash.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_flash.position = Vector2.ZERO
		_flash.size = Vector2(64,48)
	func point(cell: int, raised: bool = true) -> Vector2:
		return super.point(cell, raised) - Vector2(16,16)
	func appear(actor: WandActor, old_cell: int) -> void:
		super.appear(actor,old_cell)
		actor.sprite.place_cell(world.level.cell_coords(actor.cell) - Vector2i.ONE)
	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			if not is_instance_valid(actor.sprite) or not actor.sprite.visible: continue
			var at := actor_point(actor) + Vector2(-7,-14)
			var icons: Array[int] = []
			for status in ICONS:
				if actor.has_status(status): icons.append(ICONS[status])
			if int(actor.data.get("earthroot_armor",0)) > 0: icons.append(20)
			if int(actor.data.get("sungrass_heal",0)) > 0: icons.append(19)
			for id in icons:
				var columns := floori(BUFFS.get_width() / 7.0)
				draw_texture_rect_region(BUFFS,Rect2(at,Vector2(7,7)),Rect2((id%columns)*7,floori(float(id)/columns)*7,7,7))
				at.x += 8
	func clear() -> void:
		super.clear()
		for child in get_children():
			if child is AudioStreamPlayer:
				child.stop()
				child.queue_free()

var seed: InventoryItem
var plant_cell := -1
var plants_created := 0
var triggers_completed := 0
var teleports_completed := 0
var dropped_seed: DungeonItemSprite
var _step_target := -1

func _make_world() -> PotionWorld:
	return MeleeWorld.new()

func _make_effects() -> PotionEffects:
	return LocalSeedEffects.new()

func _reset_scene(next_mode: String) -> void:
	if is_instance_valid(dropped_seed): dropped_seed.free()
	dropped_seed = null
	super._reset_scene(next_mode)
	hero_sprite.modulate = Color.WHITE
	world.environment.unregister_actor(rat)
	world.level.set_character(rat.cell,null)
	world.actors.erase(rat)
	rat.received_damage.disconnect(world._actor_damage.bind(rat))
	rat.status_added.disconnect(world._actor_status.bind(rat))
	rat_sprite.hide()
	seed = item.copy_item()
	seed.quantity = 1
	world.move(warrior,world.level.cell_id(Vector2i(2,3)))
	hero_sprite.place_cell(Vector2i(1,2))
	hero_sprite.face_cell(Vector2i(2,2))
	plant_cell = world.level.cell_id(Vector2i(3,3))
	warrior.hp = 40 if item.type_id == "SEED_SUNGRASS" else 70
	if item.type_id == "SEED_MAGEROYAL":
		# Existing debuffs make the real cleansing result visible.
		warrior.status("poison",20)
		warrior.status("weakness",20)
		var layer := map.get_node_or_null("CombatText") as CombatTextLayer
		if layer != null: layer.clear()
	world.events.clear()
	_step_target = -1

func _start_cycle() -> void:
	_reset_scene("seed")
	history.clear()
	_steps = [{"kind":"throw", "delay":0.9}, {"kind":"step", "delay":1.1}]
	_next = 0
	phase = "ready"
	_remaining = 0.65
	if item.type_id in ["SEED_SUNGRASS", "SEED_ROTBERRY", "SEED_FIREBLOOM", "SEED_SORROWMOSS"]:
		for tick in 3: _steps.append({"kind":"tick", "delay":1.1})
	_steps.append({"kind":"hold", "delay":2.0})

func _execute(step: Dictionary) -> void:
	phase = str(step.kind)
	history.append({"kind":phase})
	match phase:
		"throw": _throw_seed()
		"step":
			var plan := world.try_move(warrior,plant_cell)
			if plan.has("error"): return
			_pending = "step"
			_step_target = int(plan.cell)
			_move_cost = float(plan.cost)
			# Keep rule occupancy at the old cell until the foot actually lands.
			# Use the battle client's neighbouring-cell hop, including its native
			# fly pose, arc, timing, shadow and landing callback.
			if not hero_sprite.move_to_cell(world.level.cell_coords(_step_target)-Vector2i.ONE): _pending = ""
		"tick":
			world.spend(1)
			world.events.clear()
			world.environment.events.clear()

func _throw_seed() -> void:
	if not _active: return
	_pending = "throw"
	var generation := _epoch
	hero_sprite.play_action(&"zap")
	var ray := Ballistica.new(warrior.cell,plant_cell,Ballistica.PROJECTILE,world.level)
	(effects as LocalSeedEffects).throw_item(seed,warrior,ray.collision_pos,func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		Nature.plant_seed(world as RingWorld,seed,ray.collision_pos)
		throws_completed += 1
		_pending = "")

func _motion_finished() -> void:
	if _pending != "step": return
	world.move(warrior,_step_target)
	moves_completed += 1
	history.append({"kind":"stepped", "cell":_step_target})
	# Hold the triggered state first; later scripted ticks show damage/healing.
	# Swiftthistle's bubble is not advanced by rendering frames.
	_pending = ""
	effects.sync_actor_states(0)

func _event(event: Dictionary) -> void:
	var actor: WandActor = event.get("actor")
	var view := effects as LocalSeedEffects
	match event.action:
		"damage":
			if actor != null and is_instance_valid(actor.sprite):
				var icon := CombatTextAssets.Icon.MAGIC_DMG
				if event.source == "poison": icon = CombatTextAssets.Icon.POISON
				elif event.source == "burning": icon = CombatTextAssets.Icon.BURNING
				elif event.source == "toxic_gas": icon = CombatTextAssets.Icon.TOXIC
				actor.sprite.show_damage(int(event.amount),icon)
		"plant":
			plants_created += 1
			var at := world.level.cell_coords(int(event.cell))-Vector2i.ONE
			var frame := int(Nature.PLANT_FRAMES[event.kind])
			# grow_plant animates an existing feature, like snapshot -> event
			# ordering in the battle client; install the real plant tile first.
			map.set_feature(at,112+frame)
			map.grow_plant(at,frame)
		"plant_trigger":
			triggers_completed += 1
			map.set_feature(world.level.cell_coords(int(event.cell))-Vector2i.ONE,-1)
		"nature_particles": view.nature_burst(int(event.cell),str(event.kind),int(event.count),float(event.get("interval",0)))
		"scroll_specks": view.start_specks(actor,int(event.cell),str(event.kind),float(event.interval),int(event.count),bool(event.center))
		"scroll_flare": view.scroll_flare(actor,event.color,int(event.rays))
		"scroll_teleport":
			teleports_completed += 1
			view.appear(actor,int(event.from))
		"drop":
			if str(event.kind) != "rotberry": return
			dropped_seed = DungeonItemSprite.new()
			map.add_child(dropped_seed)
			dropped_seed.set_item(InventoryCatalog.create("SEED_ROTBERRY"))
			dropped_seed.place(world.level.cell_coords(int(event.cell))-Vector2i.ONE)
			dropped_seed.drop()
		_: super._event(event)
