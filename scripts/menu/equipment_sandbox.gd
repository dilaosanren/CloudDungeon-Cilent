# Local journal demonstration. Never owns a PvP connection, match or inventory.
extends Control
const RatSprite = preload("res://scripts/menu/equipment_rat_sprite.gd")
const GRID_SIZE := Vector2i(4, 3)
var item: InventoryItem
var map: DungeonMap
var world: MeleeWorld
var warrior: WandActor
var rat: WandActor
var attacker: WandActor
var defender: WandActor
var hero_sprite: DungeonHeroSprite
var rat_sprite: RatSprite
var effects: MeleeEffects
var reach := 1
var attacks_started := 0
var attacks_resolved := 0
var last_result: Dictionary = {}
var _active := false
var _busy := false
var _remaining := 0.65

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map = DungeonMap.new()
	map.name = "CavesShowcase"
	map.region = 2 # Third region: caves, not the third zero-based theme.
	add_child(map)
	var terrain := PackedInt32Array()
	terrain.resize(GRID_SIZE.x * GRID_SIZE.y)
	terrain.fill(DungeonTerrain.Type.EMPTY_SP)
	map.set_map(GRID_SIZE, terrain, 402)
	# Out-of-map terrain is treated as a wall by the gameplay renderer. Its
	# southern overhang must not cover the last half-row of this floor sample.
	map.layers["Walls"].hide()
	# Original pathfinding reserves boundary cells. Pad the RULES map only;
	# the rendered map remains precisely 4x3 with no surrounding wall artwork.
	var rules_size := GRID_SIZE + Vector2i(2, 2)
	var rules_terrain := PackedInt32Array()
	rules_terrain.resize(rules_size.x * rules_size.y)
	rules_terrain.fill(DungeonTerrain.Type.WALL)
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			rules_terrain[x + 1 + (y + 1) * rules_size.x] = DungeonTerrain.Type.EMPTY_SP
	var environment := DungeonEnvironment.new()
	environment.set_map(rules_size, rules_terrain, 402)
	var level := BallisticLevel.new()
	level.set_map(rules_size, rules_terrain)
	world = MeleeWorld.new()
	world.bind(environment, level)
	effects = MeleeEffects.new()
	effects.world = world
	map.add_child(effects)
	hero_sprite = DungeonHeroSprite.new()
	hero_sprite.hero_class = "warrior"
	hero_sprite.armor_tier = ArmorRules.tier(item) if item.category == "armor" else 1
	map.add_child(hero_sprite)
	rat_sprite = RatSprite.new()
	map.add_child(rat_sprite)
	warrior = WandActor.new()
	warrior.species = "hero"
	warrior.alignment = "ally"
	warrior.hp = 70
	warrior.max_hp = 70
	warrior.data.base_max_hp = 70
	warrior.sprite = hero_sprite
	if item.category == "armor":
		warrior.data.armor_item = item
		warrior.data.armor_tier = ArmorRules.tier(item)
		var protection := ArmorRules.defense(item, warrior)
		warrior.data.armor_min = protection
		warrior.data.armor_max = protection
		# A stationary demonstration target should show protection on every hit.
		warrior.defense_skill = 0
	else:
		warrior.data.melee_weapon = item
	rat = WandActor.new()
	rat.species = "rat"
	rat.alignment = "enemy"
	# Restore after each resolved hit, retaining real damage events and numbers.
	# No invulnerability, damage immunity or death/revival animation is involved.
	rat.hp = 1000000
	rat.max_hp = rat.hp
	rat.defense_skill = 0
	rat.sprite = rat_sprite
	if item.category == "armor":
		rat.data.damage_min = 4
		rat.data.damage_max = 4
		attacker = rat
		defender = warrior
	else:
		attacker = warrior
		defender = rat
	reach = MeleeRules.reach(world.weapon(attacker), attacker)
	# Use the bottom row so floating damage fits above the actors on the floor,
	# without reserving an empty strip between the description and animation.
	var from := Vector2i(1 if reach == 1 else 0, GRID_SIZE.y - 1)
	var to := from + Vector2i(reach, 0)
	world.add_actor(warrior, level.cell_id(from + Vector2i.ONE))
	world.add_actor(rat, level.cell_id(to + Vector2i.ONE))
	hero_sprite.place_cell(from)
	rat_sprite.place_cell(to)
	hero_sprite.face_cell(to)
	rat_sprite.face_cell(from)
	var attack_sprite := attacker.sprite as DungeonHeroSprite
	attack_sprite.action_finished.connect(_attack_finished)
	world.event.connect(_event)
	resized.connect(_layout)
	_layout()
	set_active(false)

func _layout() -> void:
	if map == null: return
	var zoom := minf(1, minf(size.x / 64, size.y / 48))
	map.scale = Vector2.ONE * zoom
	# The preview fits the floor itself, without a separate top padding strip.
	map.position = Vector2((size.x - 64 * zoom) / 2, size.y - 48 * zoom).floor()

func set_active(value: bool) -> void:
	_active = value
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if map == null: return
	_busy = false
	_remaining = 0.65
	hero_sprite.play_action(&"idle")
	rat_sprite.play_action(&"idle")
	if not value:
		effects.clear()
		var text_layer := map.get_node_or_null("CombatText") as CombatTextLayer
		if text_layer != null: text_layer.clear()

func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree() or _busy: return
	_remaining -= delta
	if _remaining <= 0: demonstrate_attack()

func demonstrate_attack() -> void:
	if not _active or _busy or not world.can_attack(attacker, defender): return
	_busy = true
	attacks_started += 1
	var attack_sprite := attacker.sprite as DungeonHeroSprite
	var target_sprite := defender.sprite as DungeonHeroSprite
	attack_sprite.face_cell(target_sprite.cell)
	attack_sprite.play_action(&"attack")
	attack_sprite.body.speed_scale = 1.0 / _attack_delay()

func _attack_delay() -> float:
	return MeleeRules.delay(world.weapon(attacker), attacker)

func _attack_finished(action: StringName) -> void:
	if action != &"attack" or not _active or not _busy: return
	world.events.clear()
	last_result = world.attack(attacker, defender)
	defender.hp = defender.max_hp
	if item.category == "armor" and last_result.get("hit", false): effects.sound("hit")
	attacks_resolved += 1
	_busy = false
	_remaining = maxf(1.5, 3 * _attack_delay())
	var attack_sprite := attacker.sprite as DungeonHeroSprite
	attack_sprite.body.speed_scale = 1

func _event(event: Dictionary) -> void:
	var actor: WandActor = event.get("actor")
	var sprite := actor.sprite as DungeonHeroSprite if actor != null else null
	match event.action:
		"buff_added":
			if actor != null: BuffAnnouncements.show(actor.sprite, str(event.effect))
		"damage":
			if sprite != null: sprite.show_damage(int(event.amount))
		"melee_hit":
			if sprite != null: sprite.flash()
		"melee_sound": effects.sound(str(event.sound), float(event.pitch))
		"dodge":
			if sprite != null: sprite.show_dodge()
		"missile_blocked":
			if sprite != null: sprite.show_block()

func _exit_tree() -> void:
	if world != null: world.dispose()
