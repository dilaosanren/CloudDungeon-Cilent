class_name PvpProtocol
extends RefCounted
## Public snapshot conventions shared by presentation and authoritative code.
## No match allocation, simulation, storage or market generation lives here.
enum Phase { WAITING, DRAFT, BATTLE, FINISHED, MAP_PREVIEW }
const MAX_CONNECTIONS := 64
const RECONNECT_GRACE_MS := 60000
const BATTLE_DEPTH := 15
const SIZE := Vector2i(36, 36)
const BATTLE_SIZE := Vector2i(12, 12)
const ORIGIN := Vector2i(12, 12)
const BOUNDS := Rect2i(ORIGIN, BATTLE_SIZE)

static func cropped(tiles: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	for y in range(ORIGIN.y, BOUNDS.end.y):
		result.append_array(tiles.slice(ORIGIN.x + y*SIZE.x, BOUNDS.end.x + y*SIZE.x))
	return result
