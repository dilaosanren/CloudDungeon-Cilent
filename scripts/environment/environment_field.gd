# Port of SPD 4.0.2 Blob.java. GPL-3.0-or-later; see LICENSE-SPD.txt.
class_name EnvironmentField
extends RefCounted

var kind: String
var cur := PackedInt32Array()
var off := PackedInt32Array()
var volume := 0
# Rect.right/bottom are exclusive, as in Watabou's Rect. The area grows during scanning.
var left := 0
var top := 0
var right := 0
var bottom := 0
var data: Dictionary = {}
var next_turn := 0
var order := 0

func _init(type: String = "", length: int = 0) -> void:
	kind = type
	cur.resize(length)
	off.resize(length)

func include_cell(cell: int, width: int) -> void:
	var x := cell % width
	var y := cell / width
	if right == left or bottom == top:
		left = x
		top = y
		right = x + 1
		bottom = y + 1
	else:
		left = mini(left, x)
		top = mini(top, y)
		right = maxi(right, x + 1)
		bottom = maxi(bottom, y + 1)

func seed(cell: int, amount: int, width: int) -> void:
	if kind == "goo_warn":
		amount = maxi(0, amount - cur[cell])
	cur[cell] += amount
	volume += amount
	include_cell(cell, width)

func clear(cell: int) -> void:
	if volume == 0:
		return
	volume -= cur[cell]
	cur[cell] = 0

func fully_clear() -> void:
	cur.fill(0)
	off.fill(0)
	volume = 0
	left = 0
	right = 0
	top = 0
	bottom = 0

func diffuse(world: RefCounted) -> void:
	var y := top - 1
	while y <= bottom:
		var x := left - 1
		while x <= right:
			var c: int = x + y * world.size.x
			if world.inside_xy(x, y):
				if not world.is_solid(c):
					var count := 1
					var total := cur[c]
					if x > left and not world.is_solid(c - 1):
						total += cur[c - 1]
						count += 1
					if x < right and not world.is_solid(c + 1):
						total += cur[c + 1]
						count += 1
					if y > top and not world.is_solid(c - world.size.x):
						total += cur[c - world.size.x]
						count += 1
					if y < bottom and not world.is_solid(c + world.size.x):
						total += cur[c + world.size.x]
						count += 1
					var value: int = total / count - 1 if total >= count else 0
					off[c] = value
					if value > 0:
						include_cell(c, world.size.x)
					volume += value
				else:
					off[c] = 0
			x += 1
		y += 1

func snapshot() -> Dictionary:
	return {"kind": kind, "cur": Array(cur), "off": Array(off), "volume": volume,
		"area": [left, top, right, bottom], "data": data.duplicate(true),
		"next_turn": next_turn, "order": order}
