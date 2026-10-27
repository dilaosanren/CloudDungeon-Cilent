# Terrain/actor context for the SPD Ballistica port (GPL-3.0-or-later).
# Copyright (C) 2012-2015 Oleg Dolya; (C) 2014-2026 Evan Debenham.
class_name BallisticLevel
extends RefCounted

const TerrainRules = preload("res://scripts/dungeon_terrain.gd")
var size := Vector2i.ZERO
var passable := PackedByteArray()
var avoid := PackedByteArray()
var solid := PackedByteArray()
# Occupied row-major cell IDs. Values may be actor objects or simply true.
var characters: Dictionary = {}

func _init(map_size: Vector2i = Vector2i.ZERO, cells: PackedInt32Array = PackedInt32Array()) -> void:
	if map_size != Vector2i.ZERO:
		set_map(map_size, cells)

func set_map(map_size: Vector2i, cells: PackedInt32Array) -> bool:
	if map_size.x <= 0 or map_size.y <= 0 or cells.size() != map_size.x * map_size.y:
		return false
	for tile in cells:
		if tile < 0 or tile >= TerrainRules.FLAGS.size():
			return false
	size = map_size
	passable.resize(cells.size())
	avoid.resize(cells.size())
	solid.resize(cells.size())
	characters.clear()
	for i in cells.size():
		set_flags(i, TerrainRules.flags_for(cells[i]))
	return true

## Matches Level.insideMap: the outermost row and column are excluded.
func inside_map(cell: int) -> bool:
	return contains(cell) and cell >= size.x and cell < size.x * (size.y - 1) and cell % size.x != 0 and cell % size.x != size.x - 1

func contains(cell: int) -> bool:
	return size.x > 0 and cell >= 0 and cell < size.x * size.y

func cell_id(cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return -1
	return cell.x + cell.y * size.x

func cell_coords(cell: int) -> Vector2i:
	return Vector2i(cell % size.x, int(cell / size.x)) if contains(cell) else Vector2i(-1, -1)

func set_terrain(cell: int, tile: int) -> void:
	if tile >= 0 and tile < TerrainRules.FLAGS.size():
		set_flags(cell, TerrainRules.flags_for(tile))

## Dynamic effects such as webs can override the effective flags, just as
## Level.buildFlagMaps/onUpdateCellFlags do. This does not alter the terrain art.
func set_flags(cell: int, flags: int) -> void:
	if not contains(cell):
		return
	passable[cell] = int((flags & TerrainRules.PASSABLE) != 0)
	avoid[cell] = int((flags & TerrainRules.AVOID) != 0)
	solid[cell] = int((flags & TerrainRules.SOLID) != 0)
	if not inside_map(cell):
		passable[cell] = 0
		avoid[cell] = 0
		solid[cell] = 1

func set_character(cell: int, character: Variant = true) -> void:
	if not contains(cell):
		return
	if character == null or (character is bool and not character):
		characters.erase(cell)
	else:
		characters[cell] = character

func has_character(cell: int) -> bool:
	return characters.get(cell) != null
