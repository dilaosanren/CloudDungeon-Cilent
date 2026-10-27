# Port of SPD 4.0.2 mechanics/ShadowCaster.java, GPL-3.0-or-later.
class_name DungeonShadowCaster
extends RefCounted

const MAX_DISTANCE := 20
static var rounding: Array = []

static func initialize_rounding() -> void:
	if not rounding.is_empty():
		return
	for distance in MAX_DISTANCE + 1:
		var row := PackedInt32Array()
		row.resize(distance + 1)
		for j in range(1, distance + 1):
			row[j] = mini(j, floori(distance * cos(asin(float(j) / (distance + 0.5))) + 0.5))
		rounding.append(row)

static func cast(origin: Vector2i, size: Vector2i, blocking: PackedByteArray, distance: int) -> PackedByteArray:
	initialize_rounding()
	var fov := PackedByteArray()
	fov.resize(size.x * size.y)
	if blocking.size() != fov.size() or origin.x < 0 or origin.y < 0 or origin.x >= size.x or origin.y >= size.y:
		return fov
	distance = clampi(distance, 0, MAX_DISTANCE)
	fov[origin.x + origin.y * size.x] = 1
	for octant in [[1, -1, false], [-1, 1, true], [1, 1, true], [1, 1, false],
		[-1, 1, false], [1, -1, true], [-1, -1, true], [-1, -1, false]]:
		_scan(distance, fov, blocking, 1, origin.x, origin.y, size.x, 0.0, 1.0, octant[0], octant[1], octant[2])
	return fov

static func _scan(distance: int, fov: PackedByteArray, blocking: PackedByteArray, row: int,
	x: int, y: int, width: int, left_slope: float, right_slope: float, mx: int, my: int, mirror_xy: bool) -> void:
	var in_blocking := false
	var rounding_at_distance: PackedInt32Array = rounding[distance]
	if distance == 2:
		rounding_at_distance = rounding_at_distance.duplicate()
		rounding_at_distance[2] = 2
	while row <= distance:
		if right_slope < left_slope:
			return
		var start := 0 if left_slope == 0 else floori((row - 0.5) * left_slope + 0.499)
		var end: int = rounding_at_distance[row] if right_slope == 1 else mini(rounding_at_distance[row], ceili((row + 0.5) * right_slope - 0.499))
		var cell := x + y * width
		cell += mx * start * width + my * row if mirror_xy else mx * start + my * row * width
		for col in range(start, end + 1):
			if col == end and in_blocking and ceili((row - 0.5) * right_slope - 0.499) != end:
				break
			if cell < 0 or cell >= fov.size():
				return # Safe boundary guard; valid SPD maps have opaque outer walls.
			fov[cell] = 1
			if blocking[cell] != 0:
				if not in_blocking:
					in_blocking = true
					if col != start:
						_scan(distance, fov, blocking, row + 1, x, y, width, left_slope,
							(col - 0.5) / (row + 0.5), mx, my, mirror_xy)
			else:
				if in_blocking:
					in_blocking = false
					left_slope = (col - 0.5) / (row - 0.5)
			cell += mx * width if mirror_xy else mx
		if in_blocking:
			return
		row += 1
