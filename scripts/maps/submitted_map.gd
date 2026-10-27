# Shared wire/draft validation. Submitted maps are data, never scripts or resources.
extends RefCounted
const SIZE := 12
const CELL_COUNT := SIZE*SIZE
const T = DungeonTerrain.Type
const TERRAINS := [T.EMPTY,T.EMPTY_SP,T.WALL,T.WATER,T.HIGH_GRASS,T.GRASS,T.DOOR,T.BOOKSHELF,T.STATUE,T.STATUE_SP,T.CHASM]
const TITLES := ["地板","特殊地板","墙壁","水面","高草","矮草","木门","书架","雕像","特殊雕像","深渊"]
const MAX_TITLE := 24
const MAX_AUTHOR := 16

static func empty() -> Dictionary:
	var cells: Array = []
	cells.resize(CELL_COUNT)
	cells.fill(T.EMPTY)
	return {"name":"", "author":"", "region":2, "tiles":cells, "spawns":[[1,5],[10,6]]}

static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func clean_text(value: Variant, maximum: int) -> bool:
	if not value is String or value.length() > maximum: return false
	for letter in value:
		if letter.unicode_at(0) < 32 or letter.unicode_at(0) == 127: return false
	return true

static func valid_id(value: String) -> bool:
	return value.length() == 32 and value == value.to_lower() and value.is_valid_hex_number()

static func validate(data: Dictionary, complete: bool = true) -> Dictionary:
	if not clean_text(data.get("name"),MAX_TITLE) or (complete and str(data.get("name","")).strip_edges().is_empty()): return {"error":"请填写1～24字的地图名称。"}
	if not clean_text(data.get("author"),MAX_AUTHOR): return {"error":"作者名称最多16字，不能包含换行。"}
	if not whole(data.get("region")) or int(data.region) < 0 or int(data.region) > 4: return {"error":"请选择有效的地牢风格。"}
	var cells: Variant = data.get("tiles")
	if not (cells is Array or cells is PackedInt32Array) or cells.size() != CELL_COUNT: return {"error":"地图必须恰好包含12×12个地格。"}
	var tiles: Array = []
	for tile in cells:
		if not whole(tile) or int(tile) not in TERRAINS: return {"error":"地图包含不支持的地形。"}
		tiles.append(int(tile))
	var positions: Variant = data.get("spawns")
	if not positions is Array or positions.size() != 2: return {"error":"请设置双方的出生点。"}
	var spawns: Array = []
	var ids: Array[int] = []
	for point in positions:
		if not point is Array or point.size() != 2: return {"error":"出生点坐标无效。"}
		for coordinate in point:
			if not whole(coordinate) or int(coordinate) < 0 or int(coordinate) >= SIZE: return {"error":"出生点必须位于地图内。"}
		var at := int(point[0])+int(point[1])*SIZE
		if complete and not walkable(tiles[at]): return {"error":"出生点必须放在可以行走的地形上。"}
		ids.append(at)
		spawns.append([int(point[0]),int(point[1])])
	if ids[0] == ids[1]: return {"error":"双方出生点不能重叠。"}
	var seen := {ids[0]:true}
	var queue: Array[int] = [ids[0]]
	var index := 0
	while index < queue.size():
		var from := queue[index]
		index += 1
		for dy in range(-1,2):
			for dx in range(-1,2):
				var x := from%SIZE+dx
				var y := floori(float(from)/SIZE)+dy
				var to := x+y*SIZE
				if x < 0 or y < 0 or x >= SIZE or y >= SIZE or seen.has(to) or not walkable(tiles[to]): continue
				seen[to] = true
				queue.append(to)
	if complete and not seen.has(ids[1]): return {"error":"双方出生点之间必须有可行走的路径。"}
	return {"map":{"name":str(data.name).strip_edges() if complete else str(data.name),
		"author":(str(data.author).strip_edges() if not str(data.author).strip_edges().is_empty() else "匿名玩家") if complete else str(data.author),
		"region":int(data.region),"tiles":tiles,"spawns":spawns}}

static func walkable(tile: int) -> bool:
	return (DungeonTerrain.flags_for(tile)&DungeonTerrain.PASSABLE) != 0

static func identity(data: Dictionary) -> String:
	return JSON.stringify([data.name,data.author,data.region,data.tiles,data.spawns]).sha256_text().left(32)
