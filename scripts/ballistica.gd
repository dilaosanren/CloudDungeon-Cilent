# Port of Shattered Pixel Dungeon 4.0.2 mechanics/Ballistica.java.
# Copyright (C) 2012-2015 Oleg Dolya; (C) 2014-2026 Evan Debenham.
# GPL-3.0-or-later. See LICENSE-SPD.txt and THIRD_PARTY.md.
class_name Ballistica
extends RefCounted

const LevelContext = preload("res://scripts/ballistic_level.gd")
const STOP_TARGET = 1
const STOP_CHARS = 2
const STOP_SOLID = 4
const IGNORE_SOFT_SOLID = 8
const PROJECTILE = STOP_TARGET | STOP_CHARS | STOP_SOLID
const MAGIC_BOLT = STOP_CHARS | STOP_SOLID
const WONT_STOP = 0

## FULL ray, including source and cells AFTER the first collision.
var path := PackedInt32Array()
var source_pos: int = -1
var collision_pos: int = -1
var collision_properties: int = 0
## Index of collision_pos in path, not Euclidean distance or a range limit.
var dist: int = 0
var valid: bool = false
var error: String = ""

func _init(from: int, to: int, params: int, level: LevelContext) -> void:
	source_pos = from
	collision_properties = params
	if level == null or not level.contains(from) or not level.contains(to):
		error = "Source and target must be valid row-major cells in a ballistic level."
		return
	valid = true
	_build(from, to, params, level)
	if collision_pos != -1:
		dist = path.find(collision_pos)
	elif not path.is_empty():
		dist = path.size() - 1
		collision_pos = path[dist]
	else:
		path.append(from)
		collision_pos = from
		dist = 0

func _build(from: int, to: int, params: int, level: LevelContext) -> void:
	var w := level.size.x
	var dx := to % w - from % w
	var dy := int(to / w) - int(from / w)
	var step_x := 1 if dx > 0 else -1
	var step_y := 1 if dy > 0 else -1
	dx = absi(dx)
	dy = absi(dy)
	var step_a: int
	var step_b: int
	var d_a: int
	var d_b: int
	if dx > dy:
		step_a = step_x
		step_b = step_y * w
		d_a = dx
		d_b = dy
	else:
		step_a = step_y * w
		step_b = step_x
		d_a = dy
		d_b = dx
	var cell := from
	# Java integer division is significant for odd slopes and tie breaking.
	var err := int(d_a / 2)
	while level.inside_map(cell):
		if collision_pos == -1 and (params & STOP_SOLID) != 0 and cell != source_pos and not level.passable[cell] and not level.avoid[cell] and not level.has_character(cell):
			collision_pos = path[path.size() - 1]
		path.append(cell)
		if collision_pos == -1 and (params & STOP_SOLID) != 0 and cell != source_pos and level.solid[cell]:
			if not ((params & IGNORE_SOFT_SOLID) != 0 and (level.passable[cell] or level.avoid[cell])):
				collision_pos = cell
		if collision_pos == -1 and cell != source_pos and (params & STOP_CHARS) != 0 and level.has_character(cell):
			collision_pos = cell
		if collision_pos == -1 and cell == to and (params & STOP_TARGET) != 0:
			collision_pos = cell
		cell += step_a
		err += d_b
		if err >= d_a:
			err -= d_a
			cell += step_b

## Inclusive endpoints; clamp end, return empty for invalid ranges, like SPD.
func sub_path(start: int, end: int) -> PackedInt32Array:
	end = mini(end, path.size() - 1)
	if start < 0 or start > end + 1 or end < -1 or start > path.size():
		return PackedInt32Array()
	return path.slice(start, end + 1)

func travel_path() -> PackedInt32Array:
	return sub_path(0, dist) if valid else PackedInt32Array()
