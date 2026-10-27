# PathFinder.java, Pixel Dungeon (Oleg Dolya), Shattered Pixel Dungeon (Evan Debenham).
# Ported from the supplied 4.0.2 source. GPL-3.0-or-later; see LICENSE-SPD.txt.
class_name DungeonPathFinder
extends RefCounted

const INFINITE := 2147483647 # Java Integer.MAX_VALUE, including unreachable cells.
var distance := PackedInt32Array()
var neighbours4 := PackedInt32Array()
var neighbours8 := PackedInt32Array()
var neighbours9 := PackedInt32Array()
var circle4 := PackedInt32Array()
var circle8 := PackedInt32Array()
var width := 0
var size := 0
var _dir := PackedInt32Array()
var _dir_lr := PackedInt32Array()

# An instance per map replaces Java's static workspace so simultaneous PvP maps
# cannot overwrite one another. All ordering and early termination are retained.
func set_map_size(map_width: int, map_height: int) -> void:
	assert(map_width > 0 and map_height > 0)
	width = map_width; size = width * map_height
	distance.resize(size); distance.fill(0)
	_dir = PackedInt32Array([-1, 1, -width, width, -width - 1, -width + 1, width - 1, width + 1])
	_dir_lr = PackedInt32Array([-1 - width, -1, -1 + width, -width, width, 1 - width, 1, 1 + width])
	neighbours4 = PackedInt32Array([-width, -1, 1, width])
	neighbours8 = PackedInt32Array([-width - 1, -width, -width + 1, -1, 1, width - 1, width, width + 1])
	neighbours9 = PackedInt32Array([-width - 1, -width, -width + 1, -1, 0, 1, width - 1, width, width + 1])
	circle4 = PackedInt32Array([-width, 1, width, -1])
	circle8 = PackedInt32Array([-width - 1, -width, -width + 1, 1, width + 1, width, width - 1, -1])

## Returns null for no path (including from == to), otherwise cells excluding
## from and including to. Diagonal movement costs one; corner cutting is allowed.
func find(from: int, to: int, passable: PackedByteArray) -> Variant:
	if not build_target_distance_map(from, to, passable): return null
	var result: Array[int] = []
	var cell := from
	while cell != to:
		cell = _descending_step(cell)
		result.append(cell)
	return result

func get_step(from: int, to: int, passable: PackedByteArray) -> int:
	if not build_target_distance_map(from, to, passable): return -1
	return _descending_step(from)

## Source behaviour: when can_approach_from_pos is false, THIS INPUT MASK IS
## MODIFIED. Pass duplicate() if the caller needs to retain its terrain mask.
func get_step_back(cur: int, from: int, lookahead: int, passable: PackedByteArray, can_approach_from_pos: bool) -> int:
	if not _valid(cur, passable) or not _valid(from, passable): return -1
	var d := build_escape_distance_map(cur, from, lookahead, passable)
	if d == 0: return -1
	if not can_approach_from_pos:
		var queue: Array[int] = [cur]
		var queued := PackedByteArray(); queued.resize(size); queued[cur] = 1
		var head := 0
		var new_d := distance[cur]
		while head < queue.size():
			var step := queue[head]; head += 1
			new_d = maxi(new_d, distance[step])
			for i in range(3 if step % width == 0 else 0, 5 if (step + 1) % width == 0 else 8):
				var n := step + _dir_lr[i]
				if n < 0 or n >= size or not passable[n]: continue
				if distance[n] < distance[cur]: passable[n] = 0
				elif distance[n] >= distance[step] and not queued[n]:
					queue.append(n); queued[n] = 1
		d = mini(new_d, d)
	var goals := PackedByteArray(); goals.resize(size)
	for i in size: goals[i] = int(distance[i] == d)
	if not build_multi_goal_distance_map(cur, goals, passable): return -1
	return _descending_step(cur)

## Full map or bounded map; blocked origin is still seeded at distance zero.
func build_distance_map(to: int, passable: PackedByteArray, limit: int = INFINITE) -> void:
	if not _valid(to, passable): return
	var seeds: Array[int] = [to]
	_breadth_first(seeds, passable, -1, limit)

## Source's private overload, exposed for callers needing its partial distance map.
func build_target_distance_map(from: int, to: int, passable: PackedByteArray) -> bool:
	if not _valid(from, passable) or not _valid(to, passable) or from == to: return false
	var seeds: Array[int] = [to]
	return _breadth_first(seeds, passable, from)

func build_multi_goal_distance_map(from: int, goals: PackedByteArray, passable: PackedByteArray) -> bool:
	if not _valid(from, passable) or goals.size() != size or goals[from]: return false
	var seeds: Array[int] = []
	for i in size:
		if goals[i]: seeds.append(i)
	return _breadth_first(seeds, passable, from)

func build_escape_distance_map(cur: int, from: int, lookahead: int, passable: PackedByteArray) -> int:
	if not _valid(cur, passable) or not _valid(from, passable): return 0
	distance.fill(INFINITE)
	var queue: Array[int] = [from]; distance[from] = 0
	var head := 0
	var dest_dist := INFINITE
	var dist := 0
	while head < queue.size():
		var step := queue[head]; head += 1
		dist = distance[step]
		if dist > dest_dist: return dest_dist
		if step == cur: dest_dist = dist + lookahead
		var next_distance := dist + 1
		for i in range(3 if step % width == 0 else 0, 5 if (step + 1) % width == 0 else 8):
			var n := step + _dir_lr[i]
			if n >= 0 and n < size and passable[n] and distance[n] > next_distance:
				queue.append(n); distance[n] = next_distance
	return dist

func _breadth_first(seeds: Array[int], passable: PackedByteArray, from: int = -1, limit: int = INFINITE) -> bool:
	distance.fill(INFINITE)
	var queue: Array[int] = seeds.duplicate()
	for seed in seeds: distance[seed] = 0
	var head := 0
	while head < queue.size():
		var step := queue[head]; head += 1
		if step == from: return true
		var next_distance := distance[step] + 1
		if next_distance > limit: return false
		for i in range(3 if step % width == 0 else 0, 5 if (step + 1) % width == 0 else 8):
			var n := step + _dir_lr[i]
			if (from >= 0 and n == from) or (n >= 0 and n < size and passable[n] and distance[n] > next_distance):
				queue.append(n); distance[n] = next_distance
	return false

func _descending_step(from: int) -> int:
	var best := from
	var min_d := distance[from]
	for offset in _dir:
		var n := from + offset
		# Java relies on solid boundary rows. Guard map edges for reusable demos.
		if n < 0 or n >= size or absi(n % width - from % width) > 1: continue
		if distance[n] < min_d: min_d = distance[n]; best = n
	return best

func _valid(cell: int, passable: PackedByteArray) -> bool:
	return width > 0 and cell >= 0 and cell < size and passable.size() == size
