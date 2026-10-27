# GameScene.examineCell / Level.tileName,tileDesc / WndInfoMob, SPD 4.0.2.
# Text and artwork only; inputs are the currently presented public snapshot.
extends RefCounted

const L10n = preload("res://scripts/menu/game_locale.gd")
const Text = preload("res://scripts/inventory/item_text.gd")
const T = preload("res://scripts/dungeon_terrain.gd").Type
const TILE_NAMES := {
	T.CHASM:"chasm", T.EMPTY:"floor", T.EMPTY_SP:"floor", T.EMPTY_DECO:"floor",
	T.CUSTOM_DECO_EMPTY:"floor", T.SECRET_TRAP:"floor", T.GRASS:"grass", T.WATER:"water",
	T.WALL:"wall", T.WALL_DECO:"wall", T.SECRET_DOOR:"wall", T.DOOR:"closed_door",
	T.OPEN_DOOR:"open_door", T.ENTRANCE:"entrace", T.ENTRANCE_SP:"entrace", T.EXIT:"exit",
	T.EMBERS:"embers", T.FURROWED_GRASS:"furrowed_grass", T.LOCKED_DOOR:"locked_door",
	T.HERO_LKD_DR:"locked_door", T.CRYSTAL_DOOR:"crystal_door", T.PEDESTAL:"pedestal",
	T.BARRICADE:"barricade", T.HIGH_GRASS:"high_grass", T.LOCKED_EXIT:"locked_exit",
	T.UNLOCKED_EXIT:"unlocked_exit", T.WELL:"well", T.EMPTY_WELL:"empty_well",
	T.STATUE:"statue", T.STATUE_SP:"statue", T.INACTIVE_TRAP:"inactive_trap",
	T.BOOKSHELF:"bookshelf", T.ALCHEMY:"alchemy"
}
const TILE_DESCRIPTIONS := {
	T.CHASM:"chasm", T.WATER:"water", T.ENTRANCE:"entrance", T.ENTRANCE_SP:"entrance",
	T.EXIT:"exit", T.UNLOCKED_EXIT:"exit", T.EMBERS:"embers", T.HIGH_GRASS:"high_grass",
	T.FURROWED_GRASS:"high_grass", T.LOCKED_DOOR:"locked_door", T.HERO_LKD_DR:"locked_door",
	T.CRYSTAL_DOOR:"crystal_door", T.LOCKED_EXIT:"locked_exit", T.BARRICADE:"barricade",
	T.INACTIVE_TRAP:"inactive_trap", T.STATUE:"statue", T.STATUE_SP:"statue",
	T.ALCHEMY:"alchemy", T.EMPTY_WELL:"empty_well"
}
const CREATURES := {
	"mirror_image":"actors.mobs.npcs.mirrorimage",
	"sheep":"actors.mobs.npcs.sheep",
	"guardian":"items.wands.wandoflivingearth$earthguardian",
	"lotus":"items.wands.wandofregrowth$lotus",
	"ward":"items.wands.wandofwarding$ward"
}

static func message(key: String, values: Array = []) -> String:
	var entry: Dictionary = L10n.catalog().get("examine", {}).get(key, {})
	return Text.format_message(str(entry.get("en" if L10n.is_english() else "zh", "")), values)

static func tile_name(tile: int) -> String:
	return message("levels.level.%s_name" % TILE_NAMES.get(tile, "default"))

static func tile_description(tile: int) -> String:
	var key := str(TILE_DESCRIPTIONS.get(tile, ""))
	return message("levels.level.%s_desc" % key) if not key.is_empty() else ""

static func actor_name(data: Dictionary, state: Dictionary) -> String:
	if data.species == "hero":
		var seat := int(data.seat)
		var name_value := ""
		if seat >= 0 and seat < state.get("names", []).size():
			name_value = str(state.names[seat])
			if state.get("default_names", [false, false])[seat]: name_value = L10n.text(name_value)
		var hero := HeroAssets.HERO_KEYS.find(str(data.hero))
		var class_name_value := L10n.title_case(L10n.text(HeroAssets.HERO_NAMES[maxi(0, hero)]))
		return "%s · %s" % [name_value, class_name_value] if not name_value.is_empty() else class_name_value
	var prefix := str(CREATURES.get(data.species, ""))
	var suffix := "name_%d" % clampi(int(data.tier), 1, 6) if data.species == "ward" else "name"
	return L10n.title_case(message(prefix + "." + suffix))

static func actor_description(data: Dictionary) -> String:
	if data.species == "hero": return ""
	var prefix := str(CREATURES.get(data.species, ""))
	if data.species == "ward":
		var level := int(data.level)
		return message(prefix + ".desc_%d" % clampi(int(data.tier), 1, 6), [2 + level, 8 + 4 * level, int(data.tier)])
	var description := message(prefix + ".desc")
	if data.species == "sheep": description += "\n\n" + L10n.text("对战中点击一次即可驱散这只魔法绵羊。")
	var level := int(data.level)
	if data.species == "guardian": description += "\n\n" + message(prefix + ".wand_info", [level, 3 + 3 * level])
	elif data.species == "lotus":
		var preservation := mini(100, 40 + 4 * level)
		description += "\n\n" + message(prefix + ".wand_info", [level, preservation, preservation])
	return description
