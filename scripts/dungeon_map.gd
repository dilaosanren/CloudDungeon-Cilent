# Godot port of SPD's DungeonTileSheet, DungeonTerrainTilemap,
# DungeonWallsTilemap, WallOcclusionTilemap and terrain feature layers.
# Copyright (C) 2012-2015 Oleg Dolya; (C) 2014-2026 Evan Debenham.
# Distributed under GPL-3.0-or-later; see LICENSE-SPD.txt and THIRD_PARTY.md.
class_name DungeonMap
extends Node2D

const T = preload("res://scripts/dungeon_terrain.gd").Type
const TerrainRules = preload("res://scripts/dungeon_terrain.gd")
const BallisticContext = preload("res://scripts/ballistic_level.gd")
const BallisticRay = preload("res://scripts/ballistica.gd")
const ItemSprite = preload("res://scripts/items/dungeon_item_sprite.gd")
const ItemArt = preload("res://scripts/items/item_assets.gd")
const EnvironmentWorld = preload("res://scripts/environment/dungeon_environment.gd")
const EnvironmentView = preload("res://scripts/environment/environment_renderer.gd")
const VisibilityState = preload("res://scripts/vision/dungeon_visibility.gd")
const FogView = preload("res://scripts/vision/fog_renderer.gd")
const RippleView = preload("res://scripts/environment/water_ripples.gd")
const TILE_SIZE = 16
const THEMES = ["sewers", "prison", "caves", "city", "halls"]
const DIRECT = {
	T.EMPTY: 0, T.GRASS: 2, T.EMPTY_WELL: 19, T.ENTRANCE: 16,
	T.EXIT: 17, T.EMBERS: 3, T.PEDESTAL: 20, T.EMPTY_SP: 4,
	T.ENTRANCE_SP: 22, T.SECRET_TRAP: 0, T.TRAP: 0, T.INACTIVE_TRAP: 0,
	T.CUSTOM_DECO: 0, T.CUSTOM_DECO_EMPTY: 0, T.CUSTOM_DECO_WTR: 32,
	T.EMPTY_DECO: 1, T.LOCKED_EXIT: 61, T.UNLOCKED_EXIT: 60, T.WELL: 18,
}
const LOWER = {
	T.ALCHEMY: 120, T.BARRICADE: 121, T.HIGH_GRASS: 122,
	T.FURROWED_GRASS: 123, T.STATUE: 128, T.STATUE_SP: 129,
	T.REGION_DECO: 130, T.REGION_DECO_ALT: 131,
	T.MINE_CRYSTAL: 132, T.MINE_BOULDER: 132,
}
const OVERHANG = {
	T.DOOR: 224, T.LOCKED_DOOR: 224, T.HERO_LKD_DR: 224,
	T.OPEN_DOOR: 225, T.CRYSTAL_DOOR: 226, T.STATUE: 240,
	T.STATUE_SP: 241, T.REGION_DECO: 242, T.REGION_DECO_ALT: 243,
	T.MINE_CRYSTAL: 244, T.MINE_BOULDER: 244, T.ALCHEMY: 232,
	T.BARRICADE: 233, T.HIGH_GRASS: 234, T.FURROWED_GRASS: 235,
}
const ALTS = {1: 7, 2: 8, 3: 9, 4: 10, 80: 96, 84: 100, 92: 108,
	122: 125, 123: 126, 234: 237, 235: 238}

var map_size := Vector2i.ZERO
var terrain := PackedInt32Array()
var region: int = 0
var variance := PackedInt32Array()
var layers: Dictionary = {}
var water: ColorRect
var water_ripples: Node2D
var _atlas_cache: Dictionary = {}
var _features: Dictionary = {}
var _growing_plants: Dictionary = {}
var ballistic_level := BallisticContext.new()
var pathfinder := DungeonPathFinder.new()
var item_layer: Node2D
var environment := EnvironmentWorld.new()
var environment_renderer: EnvironmentRenderer
var visibility_state := VisibilityState.new()
var fog_renderer: DungeonFogRenderer
var fog_enabled := false
## Network clients render server visibility without recomputing it on tile changes.
var auto_refresh_visibility := true
var _visibility_nodes: Dictionary = {}
var _visibility_pending := false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ensure_layers()

func _ensure_layers() -> void:
	if water != null:
		return
	water = ColorRect.new()
	water.name = "AnimatedWater"
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader_material := ShaderMaterial.new()
	shader_material.shader = preload("res://shaders/water.gdshader")
	water.material = shader_material
	add_child(water)
	# GameScene places ripples above the water and below terrain/shore artwork.
	water_ripples = RippleView.new()
	water_ripples.name = "WaterRipples"
	add_child(water_ripples)
	for layer_name in ["Ground", "Grid", "Shadows", "Features", "RaisedGrass", "Walls"]:
		if layer_name == "RaisedGrass":
			item_layer = Node2D.new()
			item_layer.name = "Items"
			item_layer.y_sort_enabled = true
			add_child(item_layer)
		var layer := TileMapLayer.new()
		layer.name = layer_name
		add_child(layer)
		layers[layer_name] = layer
	environment_renderer = EnvironmentView.new()
	environment_renderer.name = "EnvironmentEffects"
	add_child(environment_renderer)
	environment_renderer.bind_environment(environment)
	environment.terrain_changed.connect(_environment_terrain_changed)
	environment.flags_changed.connect(_environment_flags_changed)
	environment.advanced.connect(_environment_advanced)
	fog_renderer = FogView.new()
	fog_renderer.name = "FogOfWar"
	fog_renderer.visible = false
	add_child(fog_renderer)
	visibility_state.changed.connect(_apply_visibility)
	if not ClientPrefs.changed.is_connected(_preferences_changed):
		ClientPrefs.changed.connect(_preferences_changed)
	fog_renderer.brightness = int(ClientPrefs.value(&"brightness"))

func _preferences_changed(key: StringName) -> void:
	if key == &"brightness":
		fog_renderer.brightness = int(ClientPrefs.value(key))
		_apply_visibility()
	elif key == &"visual_grid" and map_size != Vector2i.ZERO:
		for y in map_size.y:
			for x in map_size.x:
				var cell := Vector2i(x, y)
				_put("Grid", cell, _grid_visual(cell, get_terrain(cell)))

func _environment_terrain_changed(cell: int, tile: int) -> void:
	set_terrain(Vector2i(cell % map_size.x, cell / map_size.x), tile)

func _environment_flags_changed(cell: int, flags: int) -> void:
	ballistic_level.set_flags(cell, flags)
	if fog_enabled and auto_refresh_visibility and not _visibility_pending:
		_visibility_pending = true
		_refresh_visibility.call_deferred()

func _environment_advanced(_turn: int) -> void:
	if fog_enabled:
		_refresh_visibility()

func _refresh_visibility() -> void:
	_visibility_pending = false
	if fog_enabled:
		if auto_refresh_visibility: visibility_state.refresh(environment)
		else: _apply_visibility()

func set_fog_enabled(enabled: bool) -> void:
	_ensure_layers()
	if fog_enabled == enabled:
		return
	fog_enabled = enabled
	fog_renderer.visible = enabled
	_apply_visibility()

## Called by visible, grounded character motion; never changes gameplay state.
func ripple_at(cell: Vector2i) -> void:
	if not contains(cell) or get_terrain(cell) != T.WATER: return
	var index := cell.x + cell.y * map_size.x
	if fog_enabled and not visibility_state.visible[index]: return
	_ensure_layers()
	water_ripples.emit_at(cell)

func observe(cell: Vector2i, distance: int = 8, options: Dictionary = {}) -> bool:
	if not environment.inside(environment.cell_id(cell)):
		return false
	set_fog_enabled(true)
	return visibility_state.observe(cell, environment, distance, options)

## Actors use current visibility; ground item art uses previously seen cells.
func track_visibility(node: CanvasItem, cell: Vector2i, remember: bool = false, previously_seen: bool = false) -> void:
	var seen_before: bool = previously_seen or _visibility_nodes.get(node, {}).get("seen", false)
	_visibility_nodes[node] = {"cell": cell, "remember": remember, "seen": seen_before}
	_apply_visibility()

func untrack_visibility(node: CanvasItem) -> void:
	_visibility_nodes.erase(node)

func _apply_visibility() -> void:
	if fog_renderer == null or map_size == Vector2i.ZERO:
		return
	if fog_enabled:
		fog_renderer.update_fog(visibility_state, terrain)
		environment_renderer.visible_cells = visibility_state.visible.duplicate()
	else:
		environment_renderer.visible_cells = PackedByteArray()
	for node in _visibility_nodes.keys():
		if not is_instance_valid(node):
			_visibility_nodes.erase(node)
			continue
		var entry: Dictionary = _visibility_nodes[node]
		var cell: Vector2i = entry.cell
		var seen := not fog_enabled
		if fog_enabled and contains(cell):
			var c := cell.x + cell.y * map_size.x
			var currently_visible := visibility_state.visible[c] != 0
			if entry.remember:
				entry.seen = entry.seen or currently_visible
				_visibility_nodes[node] = entry
				seen = entry.seen
			else:
				seen = currently_visible
		node.visible = seen

## Row-major terrain IDs, matching SPD's Terrain.java. Invalid input leaves the map intact.
func set_map(size_in_cells: Vector2i, cells: PackedInt32Array, map_seed: int = 1) -> bool:
	if size_in_cells.x <= 0 or size_in_cells.y <= 0 or cells.size() != size_in_cells.x * size_in_cells.y:
		push_error("Map dimensions must match terrain array length.")
		return false
	for tile in cells:
		if tile < 0 or tile > 39:
			push_error("Unsupported terrain ID: %s" % tile)
			return false
	_ensure_layers()
	map_size = size_in_cells
	water_ripples.clear()
	for plant in _growing_plants.values(): plant.queue_free()
	_growing_plants.clear()
	terrain = cells.duplicate()
	ballistic_level.set_map(map_size, terrain)
	pathfinder.set_map_size(map_size.x, map_size.y)
	environment.set_map(map_size, terrain, map_seed)
	environment_renderer.bind_environment(environment)
	clear_items()
	for node in _visibility_nodes:
		if is_instance_valid(node):
			node.visible = false
	_visibility_nodes.clear()
	visibility_state.set_map(map_size, terrain)
	_features.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	variance.resize(cells.size())
	for i in variance.size():
		variance[i] = rng.randi_range(0, 99)
	set_region(region)
	_apply_visibility()
	return true

func set_region(value: int) -> void:
	_ensure_layers()
	region = clampi(value, 0, 4)
	environment_renderer.region = region
	var region_atlas := _atlas("tiles_%s.png" % THEMES[region])
	layers["Ground"].tile_set = region_atlas
	layers["Grid"].tile_set = _atlas("visual_grid.png")
	layers["Walls"].tile_set = region_atlas
	layers["Shadows"].tile_set = _atlas("occlusion_shadows.png")
	layers["Features"].tile_set = _atlas("terrain_features.png")
	layers["RaisedGrass"].tile_set = _atlas("raised_terrain.png")
	var water_texture: Texture2D = load("res://assets/environment/water%d.png" % region)
	water.size = Vector2(map_size * TILE_SIZE)
	water.material.set_shader_parameter("water_texture", water_texture)
	water.material.set_shader_parameter("map_pixels", water.size)
	water.material.set_shader_parameter("water_pixels", water_texture.get_size())
	rebuild()

func rebuild() -> void:
	for layer in layers.values():
		layer.clear()
	for y in map_size.y:
		for x in map_size.x:
			_render_cell(Vector2i(x, y))

## Updates the surrounding 3x3 cells, including wall overhangs and water banks.
func set_terrain(cell: Vector2i, tile: int) -> void:
	if not contains(cell) or tile < 0 or tile > 39:
		return
	var index := cell.x + cell.y * map_size.x
	if not _set_terrain_data(index, tile): return
	_render_terrain_changes([index], true)

## Apply a full terrain snapshot atomically. Network clients restore the
## server's visibility immediately afterwards, so they do not redraw old fog.
func apply_terrain_snapshot(cells: PackedInt32Array) -> bool:
	if cells.size() != terrain.size(): return false
	for tile in cells:
		if tile < 0 or tile > 39: return false
	var changed: Array[int] = []
	for index in cells.size():
		if _set_terrain_data(index, cells[index]): changed.append(index)
	_render_terrain_changes(changed, auto_refresh_visibility)
	return true

func _set_terrain_data(index: int, tile: int) -> bool:
	# environment.set_terrain emits terrain_changed synchronously. The data
	# is already applied when it calls back, so never render that change twice.
	if terrain[index] == tile: return false
	terrain[index] = tile
	ballistic_level.set_terrain(index, tile)
	environment.set_terrain(index, tile)
	return true

func _render_terrain_changes(changed: Array[int], refresh_fog: bool) -> void:
	if changed.is_empty(): return
	var dirty: Dictionary = {}
	for index in changed:
		var cell := Vector2i(index % map_size.x, index / map_size.x)
		for y in range(cell.y - 1, cell.y + 2):
			for x in range(cell.x - 1, cell.x + 2):
				var neighbor := Vector2i(x, y)
				if contains(neighbor): dirty[neighbor] = true
	for cell in dirty: _render_cell(cell)
	if fog_enabled:
		visibility_state.rebuild_discoverable(terrain)
		if refresh_fog: _refresh_visibility()

## Explicit atlas index for a visible trap (shape * 16 + color) or plant (112 + image).
## Pass -1 to remove it. Hidden traps intentionally have no visible overlay.
func set_feature(cell: Vector2i, atlas_index: int) -> void:
	if not contains(cell):
		return
	if atlas_index < 0:
		if _growing_plants.has(cell):
			_growing_plants[cell].queue_free()
			_growing_plants.erase(cell)
		_features.erase(cell)
	else:
		_features[cell] = atlas_index
	_render_cell(cell)

## TerrainFeaturesTilemap.growPlant: native (8,12) pivot and 0.2 second growth.
func grow_plant(cell: Vector2i, image: int) -> void:
	if image < 0 or not contains(cell) or not _features.has(cell): return
	if _growing_plants.has(cell): _growing_plants[cell].queue_free()
	var atlas: Texture2D = preload("res://assets/environment/terrain_features.png")
	var frame := AtlasTexture.new()
	frame.atlas = atlas
	var columns := int(atlas.get_width() / TILE_SIZE)
	var visual := 112 + image
	frame.region = Rect2((visual % columns) * TILE_SIZE, int(visual / columns) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	var sprite := Sprite2D.new()
	sprite.texture = frame
	sprite.centered = false
	sprite.position = Vector2(cell * TILE_SIZE) + Vector2(8, 12)
	sprite.offset = Vector2(-8, -12)
	sprite.scale = Vector2.ZERO
	add_child(sprite)
	move_child(sprite, layers["Features"].get_index() + 1)
	_growing_plants[cell] = sprite
	_render_cell(cell)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.2)
	tween.tween_callback(func():
		if _growing_plants.get(cell) == sprite:
			_growing_plants.erase(cell)
			_render_cell(cell)
		sprite.queue_free())

## Query only; callers later decide damage, range limits and animation.
func trace_ballistic(from_cell: Vector2i, to_cell: Vector2i, properties: int = BallisticRay.PROJECTILE) -> BallisticRay:
	return BallisticRay.new(ballistic_level.cell_id(from_cell), ballistic_level.cell_id(to_cell), properties, ballistic_level)

## Terrain and actor rules are separate from PathFinder, as in Dungeon.java.
## Uses live flags, so doors, roots/webs and terrain updates affect new queries.
func navigation_mask(flying: bool = false, block_characters: bool = true) -> PackedByteArray:
	var mask := ballistic_level.passable.duplicate()
	for i in mask.size():
		if flying and ballistic_level.avoid[i]: mask[i] = 1
		if block_characters and ballistic_level.has_character(i): mask[i] = 0
	return mask

func find_path(from_cell: Vector2i, to_cell: Vector2i, flying: bool = false, block_characters: bool = true) -> Variant:
	return pathfinder.find(ballistic_level.cell_id(from_cell), ballistic_level.cell_id(to_cell), navigation_mask(flying, block_characters))

func find_step(from_cell: Vector2i, to_cell: Vector2i, flying: bool = false, block_characters: bool = true) -> int:
	var from := ballistic_level.cell_id(from_cell); var to := ballistic_level.cell_id(to_cell)
	var mask := navigation_mask(flying, block_characters)
	if not ballistic_level.inside_map(from) or not ballistic_level.inside_map(to): return -1
	if maxi(absi(from_cell.x - to_cell.x), absi(from_cell.y - to_cell.y)) == 1:
		return to if mask[to] else -1
	var step := pathfinder.get_step(from, to, mask)
	return step if step >= 0 and mask[step] else -1

## Visual placement only: items do not change terrain, collision or actor occupancy.
func place_item(cell: Vector2i, visual: Variant) -> ItemSprite:
	if not contains(cell) or ItemArt.get_texture(visual) == null:
		return null
	_ensure_layers()
	var item := ItemSprite.new()
	item.set_visual(visual)
	item.place(cell, TILE_SIZE)
	item_layer.add_child(item)
	track_visibility(item, cell, true)
	return item

func clear_items() -> void:
	if item_layer == null:
		return
	for item in item_layer.get_children():
		untrack_visibility(item)
		item_layer.remove_child(item)
		item.queue_free()

func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < map_size.x and cell.y < map_size.y

func get_terrain(cell: Vector2i) -> int:
	if not contains(cell):
		return -1
	return terrain[cell.x + cell.y * map_size.x]

func local_to_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / TILE_SIZE), floori(point.y / TILE_SIZE))

func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE_SIZE) + Vector2.ONE * 8.0

## WndInfoCell uses DungeonTerrainTilemap.tile(..., flat=true).
func inspection_texture(cell: Vector2i) -> Texture2D:
	if not contains(cell): return null
	var tile := get_terrain(cell)
	var result := AtlasTexture.new()
	if tile == T.WATER:
		result.atlas = load("res://assets/environment/water%d.png" % region)
		result.region = Rect2(0, 0, 16, 16)
		return result
	var flat := {T.WALL:48, T.SECRET_DOOR:48, T.WALL_DECO:49, T.BOOKSHELF:50,
		T.DOOR:56, T.OPEN_DOOR:57, T.LOCKED_DOOR:58, T.HERO_LKD_DR:58, T.CRYSTAL_DOOR:59,
		T.ALCHEMY:64, T.BARRICADE:65, T.HIGH_GRASS:66, T.FURROWED_GRASS:67,
		T.STATUE:72, T.STATUE_SP:73, T.REGION_DECO:74, T.REGION_DECO_ALT:75,
		T.MINE_CRYSTAL:76, T.MINE_BOULDER:76}
	var visual := int(flat.get(tile, _ground_visual(cell, tile)))
	if flat.has(tile) and variance[cell.x + cell.y * map_size.x] < 50:
		visual = int({48:52, 49:53, 50:54, 66:69, 67:70}.get(visual, visual))
	if visual < 0: visual = 0
	result.atlas = load("res://assets/environment/tiles_%s.png" % THEMES[region])
	var columns := int(result.atlas.get_width() / TILE_SIZE)
	result.region = Rect2((visual % columns) * 16, int(visual / columns) * 16, 16, 16)
	return result

func _atlas(file: String) -> TileSet:
	if _atlas_cache.has(file):
		return _atlas_cache[file]
	var texture: Texture2D = load("res://assets/environment/" + file)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i.ONE * TILE_SIZE
	for y in int(texture.get_height() / TILE_SIZE):
		for x in int(texture.get_width() / TILE_SIZE):
			source.create_tile(Vector2i(x, y))
	var atlas := TileSet.new()
	atlas.tile_size = Vector2i.ONE * TILE_SIZE
	atlas.add_source(source, 0)
	_atlas_cache[file] = atlas
	return atlas

func _put(layer_name: String, cell: Vector2i, visual: int) -> void:
	var layer: TileMapLayer = layers[layer_name]
	if visual < 0:
		layer.erase_cell(cell)
	else:
		var source: TileSetAtlasSource = layer.tile_set.get_source(0)
		var columns := int(source.texture.get_width() / TILE_SIZE)
		layer.set_cell(cell, 0, Vector2i(visual % columns, int(visual / columns)))

func _alt(visual: int, cell: Vector2i) -> int:
	var roll := variance[cell.x + cell.y * map_size.x]
	if visual == 0:
		if roll < 5:
			return 12
		return 6 if roll < 52.5 else 0
	return ALTS[visual] if ALTS.has(visual) and roll < 50 else visual

func _render_cell(cell: Vector2i) -> void:
	var tile := get_terrain(cell)
	_put("Ground", cell, _ground_visual(cell, tile))
	_put("Grid", cell, _grid_visual(cell, tile))
	_put("Shadows", cell, _shadow_visual(cell, tile))
	_put("Features", cell, -1 if _growing_plants.has(cell) else _features.get(cell, _feature_visual(cell, tile)))
	var tall := -1
	if tile in [T.HIGH_GRASS, T.FURROWED_GRASS]:
		tall = region * 4 + int(tile == T.FURROWED_GRASS)
		if _alt(122, cell) == 125:
			tall += 2
	_put("RaisedGrass", cell, tall)
	_put("Walls", cell, _wall_visual(cell, tile))

## GridTileMap.java: original checkerboard and raised-door variants, under fog.
func _grid_visual(cell: Vector2i, tile: int) -> int:
	var setting := int(ClientPrefs.value(&"visual_grid"))
	if setting == -1 or cell.x % 2 != cell.y % 2: return -1
	if tile == T.WATER or DIRECT.get(tile, 24) < 24 or tile in [T.HIGH_GRASS, T.FURROWED_GRASS]:
		return setting
	if TerrainRules.is_door(tile):
		if TerrainRules.is_wall(get_terrain(cell + Vector2i.UP)): return 12 + setting
		return (8 if tile == T.OPEN_DOOR else 4) + setting
	return -1

func _ground_visual(c: Vector2i, tile: int) -> int:
	if DIRECT.has(tile):
		var direct := _alt(DIRECT[tile], c)
		return -1 if direct == 32 else direct
	if tile == T.WATER:
		var mask := 0
		var offsets := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
		for i in 4:
			if TerrainRules.stitches_water(get_terrain(c + offsets[i]), region):
				mask += 1 << i
		return -1 if mask == 0 else 32 + mask
	if tile == T.CHASM:
		var above := get_terrain(c + Vector2i.UP)
		if above == T.REGION_DECO_ALT:
			return [26, 24, 26, 26, 25][region]
		if above in [T.EMPTY_SP, T.STATUE_SP]:
			return 26
		if above == T.WATER:
			return 28
		if above in [T.WALL, T.WALL_DECO, T.SECRET_DOOR] or TerrainRules.is_door(above):
			return 27
		if above in [T.EMPTY, T.GRASS, T.EMBERS, T.EMPTY_WELL, T.HIGH_GRASS,
			T.FURROWED_GRASS, T.EMPTY_DECO, T.CUSTOM_DECO, T.WELL, T.STATUE,
			T.REGION_DECO, T.SECRET_TRAP, T.INACTIVE_TRAP, T.TRAP, T.BOOKSHELF,
			T.BARRICADE, T.PEDESTAL, T.CUSTOM_DECO_EMPTY, T.MINE_BOULDER, T.MINE_CRYSTAL]:
			return 25
		return 24
	if TerrainRules.is_door(tile):
		# SPD passes the cell ABOVE to getRaisedDoorTile (despite its argument name).
		if TerrainRules.is_wall(get_terrain(c + Vector2i.UP)):
			return 116
		return {T.DOOR: 112, T.OPEN_DOOR: 113, T.LOCKED_DOOR: 114,
			T.HERO_LKD_DR: 114, T.CRYSTAL_DOOR: 115}[tile]
	if TerrainRules.is_wall(tile):
		var below := get_terrain(c + Vector2i.DOWN)
		if TerrainRules.is_wall(below):
			return -1
		var visual := 80
		if TerrainRules.is_door(below):
			visual = 88
		elif tile == T.WALL_DECO:
			visual = 84
		elif tile == T.BOOKSHELF:
			visual = 92
		visual = _alt(visual, c)
		if not TerrainRules.is_wall(get_terrain(c + Vector2i.RIGHT)):
			visual += 1
		if not TerrainRules.is_wall(get_terrain(c + Vector2i.LEFT)):
			visual += 2
		return visual
	return _alt(LOWER.get(tile, -1), c)

func _wall_visual(c: Vector2i, tile: int) -> int:
	var below := get_terrain(c + Vector2i.DOWN)
	var right_below := get_terrain(c + Vector2i(1, 1))
	var left_below := get_terrain(c + Vector2i(-1, 1))
	if TerrainRules.is_wall(tile):
		if not TerrainRules.is_wall(below):
			# DungeonWallsTilemap only returns early for sideways doors here.
			# Other lower tiles must reach OVERHANG, including grass below walls.
			if TerrainRules.is_door(below):
				return {T.DOOR: 227, T.LOCKED_DOOR: 228, T.HERO_LKD_DR: 228,
					T.CRYSTAL_DOOR: 229}.get(below, -1)
		else:
			var visual := 176 if tile == T.BOOKSHELF or below == T.BOOKSHELF else 144
			if not TerrainRules.is_wall(get_terrain(c + Vector2i.RIGHT)):
				visual += 1
			if not TerrainRules.is_wall(right_below):
				visual += 2
			if not TerrainRules.is_wall(left_below):
				visual += 4
			if not TerrainRules.is_wall(get_terrain(c + Vector2i.LEFT)):
				visual += 8
			return visual
	if tile in [T.LOCKED_EXIT, T.UNLOCKED_EXIT]:
		return 230
	if TerrainRules.is_wall(below):
		var visual: int = {T.OPEN_DOOR: 208, T.DOOR: 212, T.LOCKED_DOOR: 216,
			T.HERO_LKD_DR: 216, T.CRYSTAL_DOOR: 220}.get(tile, 200 if below == T.BOOKSHELF else 192)
		if not TerrainRules.is_wall(right_below):
			visual += 1
		if not TerrainRules.is_wall(left_below):
			visual += 2
		return visual
	return _alt(OVERHANG.get(below, -1), c + Vector2i.DOWN) if contains(c + Vector2i.DOWN) else -1

func _feature_visual(c: Vector2i, tile: int) -> int:
	var base := 128 + region * 16
	var alternate := int(_alt(122, c) == 125)
	match tile:
		T.HIGH_GRASS: return base + alternate
		T.FURROWED_GRASS: return base + 2 + alternate
		T.GRASS: return base + 4 + alternate
		T.BARRICADE: return base + 6
		T.ALCHEMY: return base + 7
		T.STATUE, T.STATUE_SP: return base + 8
		T.REGION_DECO: return base + 9
		T.REGION_DECO_ALT: return base + 10
		T.EMBERS: return 208 + alternate
		T.MINE_CRYSTAL: return 210
		T.MINE_BOULDER: return 216
	return -1

func _shadow_visual(c: Vector2i, tile: int) -> int:
	if c.x == 0 or c.y == 0 or c.x == map_size.x - 1 or c.y == map_size.y - 1:
		return -1
	if TerrainRules.is_door(tile):
		return 7 if _wall(c + Vector2i.LEFT) and _wall(c + Vector2i.RIGHT) else 6
	if TerrainRules.is_wall(tile) or tile == T.CHASM:
		return -1
	var above := _wall(c + Vector2i.UP) and tile != T.ALCHEMY
	var visual := 40 if above else 0
	for side in [-1, 1]:
		var weight := 1 if side == -1 else 8
		if _wall(c + Vector2i(side, 0)):
			visual += 2 * weight
		elif _wall(c + Vector2i(side, 1)):
			visual += (4 if not above and _wall(c + Vector2i(side, -1)) else 1) * weight
		elif not above and _wall(c + Vector2i(side, -1)):
			visual += 3 * weight
	return visual if visual > 0 else -1

func _wall(c: Vector2i) -> bool:
	return TerrainRules.is_wall(get_terrain(c))
