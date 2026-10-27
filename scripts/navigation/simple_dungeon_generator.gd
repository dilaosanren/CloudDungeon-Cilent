# Small seeded room/corridor generator for the PathFinder demonstration.
# This is demonstration layout generation, separate from SPD's level generator.
class_name SimpleDungeonGenerator
extends RefCounted

static func generate(size: Vector2i, seed_value: int) -> Dictionary:
	assert(size.x >= 8 and size.y >= 8)
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	var cells := PackedInt32Array(); cells.resize(size.x * size.y); cells.fill(DungeonTerrain.Type.WALL)
	var centers: Array[Vector2i] = []
	for room in 6:
		# Spread six rooms through the map so small portrait previews still show
		# corridors and useful route lengths, rather than a single dense cluster.
		var column := room % 2; var row := int(room / 2)
		var zone_start := Vector2i(1 + int(column * (size.x - 2) / 2), 1 + int(row * (size.y - 2) / 3))
		var zone_end := Vector2i(1 + int((column + 1) * (size.x - 2) / 2), 1 + int((row + 1) * (size.y - 2) / 3))
		var w := rng.randi_range(2, mini(4, zone_end.x - zone_start.x))
		var h := rng.randi_range(2, mini(4, zone_end.y - zone_start.y))
		var origin := Vector2i(rng.randi_range(zone_start.x, zone_end.x - w), rng.randi_range(zone_start.y, zone_end.y - h))
		for y in range(origin.y, origin.y + h):
			for x in range(origin.x, origin.x + w): cells[x + y * size.x] = DungeonTerrain.Type.EMPTY
		var center := origin + Vector2i(w / 2, h / 2)
		if not centers.is_empty():
			var p: Vector2i = centers.back()
			var horizontal_first := rng.randf() < 0.5
			while p != center:
				cells[p.x + p.y * size.x] = DungeonTerrain.Type.EMPTY
				if (horizontal_first and p.x != center.x) or p.y == center.y: p.x += signi(center.x - p.x)
				else: p.y += signi(center.y - p.y)
		centers.append(center)
	for i in cells.size():
		if cells[i] != DungeonTerrain.Type.EMPTY: continue
		var roll := rng.randf()
		if roll < 0.08: cells[i] = DungeonTerrain.Type.WATER
		elif roll < 0.16: cells[i] = DungeonTerrain.Type.GRASS
		elif roll < 0.21: cells[i] = DungeonTerrain.Type.EMPTY_DECO
	var level := BallisticLevel.new(size, cells)
	var finder := DungeonPathFinder.new(); finder.set_map_size(size.x, size.y)
	var start := level.cell_id(centers[0])
	finder.build_distance_map(start, level.passable)
	var goal := start
	for i in cells.size():
		if finder.distance[i] != DungeonPathFinder.INFINITE and finder.distance[i] > finder.distance[goal]: goal = i
	cells[start] = DungeonTerrain.Type.ENTRANCE; cells[goal] = DungeonTerrain.Type.EXIT
	return {"terrain": cells, "start": start, "goal": goal, "seed": seed_value}
