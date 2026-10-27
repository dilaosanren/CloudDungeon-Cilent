# Local scripted demonstrations using the actual PotionWorld and environment.
extends Control
const RatSprite = preload("res://scripts/menu/equipment_rat_sprite.gd")
const GRID_SIZE := Vector2i(4, 3)
const RULES_SIZE := GRID_SIZE + Vector2i(2, 2)
const FIELD_FOR = {
	"PotionOfLevitation":"confusion_gas", "PotionOfToxicGas":"toxic_gas",
	"PotionOfParalyticGas":"paralytic_gas", "PotionOfLiquidFlame":"fire",
	"PotionOfFrost":"freezing",
	"PotionOfCorrosiveGas":"corrosive_gas",
}

class LocalEffects extends PotionEffects:
	func point(cell: int, raised: bool = true) -> Vector2:
		return super.point(cell, raised) - Vector2(16, 16)

class PreviewHero extends DungeonHeroSprite:
	func _process(delta: float) -> void:
		super._process(delta)
		# Keep the original top-row walking frames inside the compact floor.
		# This only adjusts the preview's perspective raise, not its rule cell.
		var shift := maxf(0, -position.y - body.position.y)
		body.position.y += shift
		shadow.position.y += shift

var item: InventoryItem
var map: DungeonMap
var world: PotionWorld
var warrior: WandActor
var rat: WandActor
var hero_sprite: DungeonHeroSprite
var rat_sprite: DungeonHeroSprite
var effects: PotionEffects
var vision := DungeonVisibility.new()
var phase := "ready"
var mode := "drink"
var loops_completed := 0
var drinks_completed := 0
var throws_completed := 0
var moves_completed := 0
var purity_clears := 0
var history: Array[Dictionary] = []
var _active := false
var _steps: Array[Dictionary] = []
var _next := 0
var _remaining := 0.65
var _pending := ""
var _move_cost := 0.0
var _epoch := 0
var _hover_age := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map = DungeonMap.new()
	map.region = 2
	add_child(map)
	hero_sprite = PreviewHero.new()
	hero_sprite.hero_class = "warrior"
	hero_sprite.armor_tier = 1
	map.add_child(hero_sprite)
	rat_sprite = _make_target_sprite()
	map.add_child(rat_sprite)
	effects = _make_effects()
	map.add_child(effects)
	hero_sprite.action_finished.connect(_action_finished)
	hero_sprite.motion_finished.connect(_motion_finished)
	resized.connect(_layout)
	_reset_scene("throw" if FIELD_FOR.has(item.type_id) and item.type_id != "PotionOfLevitation" else "drink")
	_layout()
	set_active(false)

func _make_target_sprite() -> DungeonHeroSprite:
	return RatSprite.new()

func _make_effects() -> PotionEffects:
	return LocalEffects.new()

func _make_world() -> PotionWorld:
	return PotionWorld.new()

func _layout() -> void:
	if map == null: return
	var zoom := minf(1, minf(size.x / 64, size.y / 48))
	map.scale = Vector2.ONE * zoom
	map.position = Vector2((size.x - 64 * zoom) / 2, size.y - 48 * zoom).floor()

func set_active(value: bool) -> void:
	_epoch += 1
	_active = value
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if map == null: return
	_pending = ""
	effects.clear()
	hero_sprite.play_action(&"idle")
	rat_sprite.play_action(&"idle")
	if value: _start_cycle()

func _start_cycle() -> void:
	_reset_scene("throw" if FIELD_FOR.has(item.type_id) and item.type_id != "PotionOfLevitation" else "drink")
	history.clear()
	_steps.clear()
	_next = 0
	phase = "ready"
	_remaining = 0.65
	match item.type_id:
		"PotionOfHealing":
			_steps.append({"kind":"drink"})
			_ticks(6)
		"PotionOfHaste":
			_steps.append({"kind":"drink"})
			var route := [Vector2i(1, 1), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
				Vector2i(3, 1), Vector2i(3, 2), Vector2i(2, 2), Vector2i(1, 2)]
			for lap in 3:
				for cell in route: _steps.append({"kind":"move", "cell":cell, "delay":0.0})
		"PotionOfInvisibility", "PotionOfMindVision":
			_steps.append({"kind":"drink"})
			_ticks(4)
		"PotionOfMagicalSight":
			_steps.append({"kind":"drink"})
			_ticks(10)
		"PotionOfLevitation":
			_steps.append({"kind":"drink"})
			_ticks(3)
			_steps.append({"kind":"scene", "mode":"throw"})
			_steps.append({"kind":"throw"})
			_ticks(4)
		"PotionOfPurity":
			_steps.append({"kind":"drink"})
			_steps.append({"kind":"seed", "kinds":["toxic_gas"]})
			_ticks(3)
			_steps.append({"kind":"scene", "mode":"throw"})
			_steps.append({"kind":"seed", "kinds":["toxic_gas", "paralytic_gas"], "delay":1.2})
			_steps.append({"kind":"throw"})
			_steps.append({"kind":"hold", "delay":1.5})
		_:
			_steps.append({"kind":"throw"})
			# Freezing mist builds chill before it freezes the target.
			_ticks(6 if item.type_id == "PotionOfFrost" else 4)
	_steps.append({"kind":"hold", "delay":1.2})

func _ticks(count: int) -> void:
	for index in count: _steps.append({"kind":"tick", "delay":0.75})

func _reset_scene(next_mode: String) -> void:
	_epoch += 1
	_pending = ""
	mode = next_mode
	if world != null: world.dispose()
	effects.clear()
	effects.visual_states.clear()
	var text_layer := map.get_node_or_null("CombatText") as CombatTextLayer
	if text_layer != null: text_layer.clear()
	for sprite in [hero_sprite, rat_sprite]:
		sprite.place_cell(Vector2i.ZERO)
		sprite.flying = false
		sprite.body.modulate = Color.WHITE
		sprite.body.material = null
		sprite.body.position.y = DungeonHeroSprite.BODY_POSITION.y
		sprite.play_action(&"idle")
	var floor_cells := PackedInt32Array()
	floor_cells.resize(12)
	floor_cells.fill(DungeonTerrain.Type.EMPTY_SP)
	if item.type_id == "PotionOfMindVision":
		for y in 3: floor_cells[2 + y * 4] = DungeonTerrain.Type.HIGH_GRASS
	elif item.type_id == "PotionOfMagicalSight":
		for y in 3: floor_cells[2 + y * 4] = DungeonTerrain.Type.WALL
	map.set_map(GRID_SIZE, floor_cells, 402)
	map.layers.Walls.hide()
	if item.type_id == "PotionOfMagicalSight": map.layers.Walls.show()
	var terrain := PackedInt32Array()
	terrain.resize(RULES_SIZE.x * RULES_SIZE.y)
	terrain.fill(DungeonTerrain.Type.WALL)
	for y in 3:
		for x in 4: terrain[x + 1 + (y + 1) * RULES_SIZE.x] = floor_cells[x + y * 4]
	var environment := DungeonEnvironment.new()
	environment.set_map(RULES_SIZE, terrain, 402)
	environment.scaling_depth = 15
	var level := BallisticLevel.new()
	level.set_map(RULES_SIZE, terrain)
	world = _make_world()
	world.bind(environment, level)
	effects.world = world
	map.environment_renderer.bind_environment(environment)
	map.environment_renderer.position = Vector2(-16, -16)
	environment.terrain_changed.connect(_terrain_changed)
	environment.flags_changed.connect(func(cell, flags): level.set_flags(cell, flags))
	warrior = WandActor.new()
	warrior.species = "hero"
	warrior.alignment = "ally"
	warrior.max_hp = 70
	warrior.hp = 40 if item.type_id == "PotionOfHealing" else 70
	warrior.data.base_max_hp = 70
	warrior.sprite = hero_sprite
	rat = WandActor.new()
	rat.species = "rat"
	rat.max_hp = 70
	rat.hp = 70
	rat.sprite = rat_sprite
	var from := Vector2i(0, 2)
	var to := Vector2i(3, 2)
	if item.type_id == "PotionOfHaste":
		from = Vector2i(1, 2)
		to = Vector2i(2, 1)
	elif item.type_id == "PotionOfPurity" and mode == "drink":
		from = Vector2i(1, 2)
		to = Vector2i(2, 2)
	elif item.type_id == "PotionOfLevitation" and mode == "drink": from = Vector2i(1, 2)
	world.add_actor(warrior, level.cell_id(from + Vector2i.ONE))
	world.add_actor(rat, level.cell_id(to + Vector2i.ONE))
	hero_sprite.place_cell(from)
	rat_sprite.place_cell(to)
	hero_sprite.face_cell(to)
	rat_sprite.face_cell(from)
	hero_sprite.show()
	rat_sprite.visible = item.type_id not in ["PotionOfHealing", "PotionOfInvisibility"] and not (item.type_id == "PotionOfLevitation" and mode == "drink")
	vision.set_map(RULES_SIZE, terrain)
	world.event.connect(_event)
	_sync_vision()

func _terrain_changed(cell: int, tile: int) -> void:
	world.level.set_terrain(cell, tile)
	var at := world.level.cell_coords(cell) - Vector2i.ONE
	if map.contains(at): map.set_terrain(at, tile)

func _sync_vision() -> void:
	if item.type_id not in ["PotionOfMindVision", "PotionOfMagicalSight"]: return
	vision.observe(world.level.cell_coords(warrior.cell), world.environment, 8,
		world.vision_options(warrior))
	rat_sprite.visible = bool(vision.visible[rat.cell])

func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree(): return
	_hover_age += delta
	if warrior.flying and not hero_sprite.moving:
		hero_sprite.body.position.y = DungeonHeroSprite.BODY_POSITION.y - 2 + sin(_hover_age * 4)
	if not _pending.is_empty(): return
	_remaining -= delta
	if _remaining > 0: return
	if _next >= _steps.size():
		loops_completed += 1
		_start_cycle()
		return
	var step := _steps[_next]
	_next += 1
	_remaining = float(step.get("delay", 0.6))
	_execute(step)

func _execute(step: Dictionary) -> void:
	phase = str(step.kind)
	history.append({"kind":phase, "mode":mode})
	match phase:
		"drink":
			_pending = "drink"
			hero_sprite.play_action(&"operate")
			world.apply(item, warrior)
			effects.sound("drink")
			effects.sync_actor_states(0)
			_sync_vision()
		"tick":
			if item.type_id == "PotionOfHealing": hero_sprite.show_status(Color.WHITE, "...")
			world.spend(1)
			world.events.clear()
			world.environment.events.clear()
			_sync_vision()
		"move":
			var target := world.level.cell_id(Vector2i(step.cell) + Vector2i.ONE)
			var plan := world.try_move(warrior, target)
			if plan.has("error"): return
			_pending = "move"
			_move_cost = float(plan.cost)
			world.move(warrior, int(plan.cell))
			hero_sprite.walk_to_cell(world.level.cell_coords(warrior.cell) - Vector2i.ONE, 0.6 * _move_cost)
		"scene": _reset_scene(str(step.mode))
		"seed":
			for kind in step.kinds:
				world.environment.seed(str(kind), rat.cell, 1000)
				if mode == "drink": world.environment.seed(str(kind), warrior.cell, 1000)
		"throw": _throw()

func _throw() -> void:
	_pending = "throw"
	var generation := _epoch
	var ray := Ballistica.new(warrior.cell, rat.cell, Ballistica.PROJECTILE, world.level)
	hero_sprite.face_cell(rat_sprite.cell)
	hero_sprite.play_action(&"zap")
	effects.throw_potion(item, warrior, ray.collision_pos, func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		world.on_throw(item, ray.collision_pos)
		throws_completed += 1
		if item.type_id == "PotionOfPurity":
			purity_clears += 1
			# Discard particles emitted by gas that has actually been removed.
			map.environment_renderer.bind_environment(world.environment)
		_pending = "")

func _action_finished(action: StringName) -> void:
	if _pending != "drink" or action != &"operate": return
	drinks_completed += 1
	_pending = ""

func _motion_finished() -> void:
	if _pending != "move": return
	world.spend(_move_cost)
	moves_completed += 1
	history.append({"kind":"moved", "cell":hero_sprite.cell, "cost":_move_cost})
	_pending = ""
	_remaining = 0

func _event(event: Dictionary) -> void:
	var actor: WandActor = event.get("actor")
	var sprite := actor.sprite as DungeonHeroSprite if actor != null else null
	match event.action:
		"potion_snow": effects.snow_at(int(event.cell),int(event.count),float(event.interval))
		"buff_added":
			if actor != null: BuffAnnouncements.show(actor.sprite, str(event.effect))
		"healing":
			if sprite != null: sprite.show_healing(int(event.amount))
		"damage":
			if sprite != null:
				sprite.show_damage(int(event.amount), CombatTextAssets.Icon.TOXIC if event.source == "toxic_gas" else CombatTextAssets.Icon.MAGIC_DMG)
		"sound": effects.sound(str(event.sound))
		"spell": effects.spell(actor, int(event.index), event.color)
		"splash": effects.splash_at(effects.actor_point(actor) if actor != null else effects.point(int(event.cell), false), effects.potion_color(item), int(event.count))
		"discover_speck": effects.speck("discover", effects.point(int(event.cell), false), int(event.count))

func _exit_tree() -> void:
	_epoch += 1
	_active = false
	if world != null: world.dispose()
