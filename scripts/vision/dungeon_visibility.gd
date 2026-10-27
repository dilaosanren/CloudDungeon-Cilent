# SPD Level.updateFieldOfView / Dungeon.observe exploration state. GPL-3.0-or-later.
class_name DungeonVisibility
extends RefCounted

signal changed
const Caster = preload("res://scripts/vision/shadow_caster.gd")
const Rules = preload("res://scripts/dungeon_terrain.gd")
enum State { VISIBLE, VISITED, MAPPED, UNKNOWN }
var size := Vector2i.ZERO
var visible := PackedByteArray()
var visited := PackedByteArray()
var mapped := PackedByteArray()
var discoverable := PackedByteArray()
var origin := Vector2i(-1, -1)
var view_distance := 8
var observer_options: Dictionary = {}

func set_map(dimensions: Vector2i, terrain: PackedInt32Array) -> void:
	size = dimensions
	visible.resize(terrain.size())
	visited.resize(terrain.size())
	mapped.resize(terrain.size())
	visible.fill(0)
	visited.fill(0)
	mapped.fill(0)
	origin = Vector2i(-1, -1)
	observer_options.clear()
	rebuild_discoverable(terrain)

func rebuild_discoverable(terrain: PackedInt32Array) -> void:
	discoverable.resize(terrain.size())
	discoverable.fill(0)
	# Preserve the original flat NEIGHBOURS9 bounds check.
	for cell in terrain.size():
		for offset in [-size.x - 1, -size.x, -size.x + 1, -1, 0, 1, size.x - 1, size.x, size.x + 1]:
			var n: int = cell + offset
			if n >= 0 and n < terrain.size() and terrain[n] not in [Rules.Type.WALL, Rules.Type.WALL_DECO]:
				discoverable[cell] = 1
				break

func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y

func state(cell: int) -> int:
	if cell < 0 or cell >= visible.size():
		return State.UNKNOWN
	if visible[cell]:
		return State.VISIBLE
	if visited[cell]:
		return State.VISITED
	return State.MAPPED if mapped[cell] else State.UNKNOWN

## World provides effective LOS, including key walls and faction-dependent smoke.
## options: blind, shadows, alive, see_through_grass, fungi_quest, alignment, species,
## farsight_points, vision_multiplier, sense_distance, reveal_cells (mind/awareness sources).
func observe(cell: Vector2i, world: DungeonEnvironment, distance: int = 8, options: Dictionary = {}) -> bool:
	if not world.inside(world.cell_id(cell)) or world.size != size:
		return false
	origin = cell
	view_distance = distance
	observer_options = options.duplicate(true)
	var blocking := PackedByteArray()
	blocking.resize(visible.size())
	for c in blocking.size():
		blocking[c] = int(world.blocks_vision(c, options.get("alignment", "ally"), options.get("species", "hero")))
		if options.get("see_through_grass", false) and not options.get("fungi_quest", false) and world.terrain[c] in [Rules.Type.HIGH_GRASS, Rules.Type.FURROWED_GRASS]:
			blocking[c] = 0
	var alive: bool = options.get("alive", true)
	var sighted: bool = alive and not options.get("blind", false) and not options.get("shadows", false)
	var radius := clampi(floori(distance * (1 + 0.25 * int(options.get("farsight_points", 0))) * float(options.get("vision_multiplier", 1.0)) + 0.5), 0, Caster.MAX_DISTANCE)
	if sighted:
		visible = Caster.cast(cell, size, blocking, radius)
	else:
		visible.fill(0)
	var sense := clampi(int(options.get("sense_distance", 1)) if alive else 1, 1, Caster.MAX_DISTANCE)
	if not sighted or sense > 1:
		_apply_sense(cell, sense)
	if alive:
		for c in options.get("reveal_cells", []):
			if c >= 0 and c < visible.size():
				visible[c] = 1
	for c in visible.size():
		visited[c] |= visible[c]
	# Dungeon.observe visits all nine adjacent cells even if the FOV omits them.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var p := cell + Vector2i(dx, dy)
			if contains(p):
				visited[p.x + p.y * size.x] = 1
	changed.emit()
	return true

func refresh(world: DungeonEnvironment) -> void:
	if contains(origin):
		observe(origin, world, view_distance, observer_options)

func _apply_sense(cell: Vector2i, sense: int) -> void:
	Caster.initialize_rounding()
	var rounding: PackedInt32Array = Caster.rounding[sense]
	for y in range(maxi(0, cell.y - sense), mini(size.y - 1, cell.y + sense) + 1):
		var dy := absi(cell.y - y)
		var left: int
		if rounding[dy] < dy:
			left = cell.x - rounding[dy]
		else:
			left = sense
			while rounding[left] < rounding[dy]:
				left -= 1
			left = cell.x - left
		var right := mini(size.x - 1, cell.x + cell.x - left)
		left = maxi(0, left)
		for x in range(left, right + 1):
			var c := x + y * size.x
			visible[c] = discoverable[c]

func map_cells(cells: Array) -> void:
	for c in cells:
		if c >= 0 and c < mapped.size():
			mapped[c] = 1
	changed.emit()

func clear_memory() -> void:
	visited.fill(0)
	mapped.fill(0)
	changed.emit()

func snapshot() -> Dictionary:
	return {"version": 1, "size": [size.x, size.y], "visible": Array(visible),
		"visited": Array(visited), "mapped": Array(mapped), "origin": [origin.x, origin.y],
		"distance": view_distance, "options": observer_options.duplicate(true)}

func restore(data: Dictionary) -> bool:
	if data.get("version") != 1 or PackedInt32Array(data.get("size", [])) != PackedInt32Array([size.x, size.y]):
		return false
	for key in ["visible", "visited", "mapped"]:
		if not data.has(key) or data[key].size() != visible.size():
			return false
		for value in data[key]:
			if value != 0 and value != 1:
				return false
	visible = PackedByteArray(data.visible)
	visited = PackedByteArray(data.visited)
	mapped = PackedByteArray(data.mapped)
	origin = Vector2i(data.origin[0], data.origin[1])
	view_distance = int(data.distance)
	observer_options = data.options.duplicate(true)
	changed.emit()
	return true
