## Palette replacement for UI chrome, preserving pixel geometry and shading.
class_name UiPalette
extends RefCounted

const ACCENT := Color("d97757")
const SOURCE_RED := Color("b22a2a") # Original RED_BUTTON center fill.
const SHEETS := ["chrome", "status_pane", "boss_hp", "menu_button"]
const DIRECTORY := "res://assets/ui/palettes/claude/"
static var _textures: Dictionary = {}

static func is_red(color: Color) -> bool:
	return color.a > 0 and color.r > 0.15 and color.r > color.g * 1.5 and color.r > color.b * 1.5

static func color(value: Color) -> Color:
	if not is_red(value): return value
	return Color.from_hsv(ACCENT.h, minf(1, value.s * ACCENT.s / SOURCE_RED.s), minf(1, value.v * ACCENT.v / SOURCE_RED.v), value.a)

static func texture(original: Texture2D) -> Texture2D:
	if original == null: return null
	var path := original.resource_path
	# Only interface chrome/HUD assets use this palette. Source art stays intact.
	if not path.begins_with("res://assets/ui/source/"): return original
	var sheet := path.get_file().get_basename()
	if not SHEETS.has(sheet): return original
	if not _textures.has(sheet): _textures[sheet] = load(DIRECTORY + sheet + ".res")
	return _textures[sheet]
