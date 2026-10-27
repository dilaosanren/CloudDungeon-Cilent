# Original BuffIndicator enum and BuffIcon TextureFilm, GPL-3.0-or-later.
class_name StatusAssets
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")

const NONE := 127
const LARGE_SIZE := 16
static var _catalog: Dictionary = {}
static var _textures: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/status/source_catalog.json"))
	return _catalog.duplicate(true)

static func icon_id(name: String) -> int:
	return int(catalog().icons.get(name.to_upper(), NONE))

static func icon_texture(id: int) -> AtlasTexture:
	if id < 0 or id >= NONE: return null
	if not _textures.has(id):
		var texture := AtlasTexture.new()
		texture.atlas = load("res://assets/ui/source/large_buffs.png")
		var side := LARGE_SIZE
		var columns := floori(float(texture.atlas.get_width()) / side)
		texture.region = Rect2((id % columns) * side, floori(float(id) / columns) * side, side, side)
		_textures[id] = texture
	return _textures[id]

## Mirrors HeroSprite.avatar: uvRect(1,0,12,15), shifted to the armor row.
static func avatar_texture(hero: String, tier: int) -> AtlasTexture:
	var frame := HeroAssets.frame_texture(hero, tier, 0)
	if frame == null: return null
	frame.region = Rect2(1, tier * 15, 11, 15)
	return frame

static func example(key: String, value: int = -1) -> StatusBuff:
	for data in catalog().examples:
		if data.key != key: continue
		var buff := StatusBuff.new()
		var remaining := int(data.turns) if value < 0 else value
		buff.key = key
		buff.icon_id = int(data.icon_id)
		buff.display_name = L10n.text(str(data.name))
		buff.description = L10n.text(str(data.description)).replace("%s", str(remaining)).replace("%d", str(remaining))
		buff.tint = Color(data.tint[0], data.tint[1], data.tint[2])
		buff.kind = int(data.kind)
		buff.fade_percent = clampf(1.0 - float(remaining) / float(data.fade_base), 0, 1) if data.fade_base > 0 else 0.0
		buff.icon_text = str(remaining) if data.text else ""
		return buff
	return null
