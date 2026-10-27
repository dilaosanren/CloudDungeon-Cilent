# Terrain IDs from Shattered Pixel Dungeon 4.0.2 (GPL-3.0-or-later).
class_name DungeonTerrain
extends RefCounted

enum Type {
	CHASM = 0, EMPTY = 1, GRASS = 2, EMPTY_WELL = 3, WALL = 4,
	DOOR = 5, OPEN_DOOR = 6, ENTRANCE = 7, EXIT = 8, EMBERS = 9,
	LOCKED_DOOR = 10, PEDESTAL = 11, WALL_DECO = 12, BARRICADE = 13,
	EMPTY_SP = 14, HIGH_GRASS = 15, SECRET_DOOR = 16, SECRET_TRAP = 17,
	TRAP = 18, INACTIVE_TRAP = 19, EMPTY_DECO = 20, LOCKED_EXIT = 21,
	UNLOCKED_EXIT = 22, CUSTOM_DECO = 23, WELL = 24, STATUE = 25,
	STATUE_SP = 26, BOOKSHELF = 27, ALCHEMY = 28, WATER = 29,
	FURROWED_GRASS = 30, CRYSTAL_DOOR = 31, CUSTOM_DECO_EMPTY = 32,
	REGION_DECO = 33, REGION_DECO_ALT = 34, MINE_CRYSTAL = 35,
	MINE_BOULDER = 36, ENTRANCE_SP = 37, HERO_LKD_DR = 38, CUSTOM_DECO_WTR = 39,
}

# Exact Terrain.java flags. Ballistics must use gameplay flags, not wall visuals
# or LOS_BLOCKING (tall grass blocks sight but does not stop projectiles).
const PASSABLE = 0x01
const LOS_BLOCKING = 0x02
const FLAMABLE = 0x04
const SECRET = 0x08
const SOLID = 0x10
const AVOID = 0x20
const LIQUID = 0x40
const PIT = 0x80
const FLAGS = [
	AVOID | PIT, PASSABLE, PASSABLE | FLAMABLE, PASSABLE,
	LOS_BLOCKING | SOLID, PASSABLE | LOS_BLOCKING | FLAMABLE | SOLID,
	PASSABLE | FLAMABLE, PASSABLE, PASSABLE, PASSABLE,
	LOS_BLOCKING | SOLID, PASSABLE, LOS_BLOCKING | SOLID,
	FLAMABLE | SOLID | LOS_BLOCKING, PASSABLE, PASSABLE | LOS_BLOCKING | FLAMABLE,
	LOS_BLOCKING | SOLID | SECRET, PASSABLE | SECRET, AVOID, PASSABLE,
	PASSABLE, SOLID, PASSABLE, SOLID, AVOID, SOLID, SOLID,
	FLAMABLE | SOLID | LOS_BLOCKING, SOLID, PASSABLE | LIQUID,
	PASSABLE | LOS_BLOCKING | FLAMABLE, SOLID, PASSABLE,
	SOLID, SOLID, SOLID, SOLID, PASSABLE, LOS_BLOCKING | SOLID, SOLID,
]

static func flags_for(tile: int) -> int:
	return FLAGS[tile] if tile >= 0 and tile < FLAGS.size() else 0

static func is_wall(tile: int) -> bool:
	return tile in [-1, Type.WALL, Type.WALL_DECO, Type.SECRET_DOOR,
		Type.LOCKED_EXIT, Type.UNLOCKED_EXIT, Type.BOOKSHELF]

static func is_door(tile: int) -> bool:
	return tile in [Type.DOOR, Type.OPEN_DOOR, Type.LOCKED_DOOR,
		Type.HERO_LKD_DR, Type.CRYSTAL_DOOR]

static func stitches_water(tile: int, region: int) -> bool:
	if tile == Type.REGION_DECO_ALT:
		return region == 4
	return tile in [Type.EMPTY, Type.GRASS, Type.EMPTY_WELL, Type.ENTRANCE,
		Type.EXIT, Type.EMBERS, Type.BARRICADE, Type.HIGH_GRASS,
		Type.FURROWED_GRASS, Type.SECRET_TRAP, Type.TRAP, Type.INACTIVE_TRAP,
		Type.EMPTY_DECO, Type.CUSTOM_DECO, Type.WELL, Type.STATUE,
		Type.REGION_DECO, Type.ALCHEMY, Type.CUSTOM_DECO_EMPTY,
		Type.MINE_CRYSTAL, Type.MINE_BOULDER, Type.DOOR, Type.OPEN_DOOR,
		Type.LOCKED_DOOR, Type.HERO_LKD_DR, Type.CRYSTAL_DOOR]
