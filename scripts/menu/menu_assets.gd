# TitleBackground / Icons data from supplied SPD 4.0.2. GPL-3.0-or-later.
class_name MenuAssets
extends RefCounted

static var _catalog: Dictionary = {}
static var _textures: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/menu/source_catalog.json").trim_prefix("\ufeff"))
	return _catalog.duplicate(true)

static func frame_texture(sheet: String, index: int) -> AtlasTexture:
	var key := "%s_%d" % [sheet, index]
	if not _textures.has(key):
		var definition: Dictionary = catalog().sheets[sheet]
		var atlas: Texture2D = load(definition.texture)
		var columns := int(atlas.get_width() / definition.frame_width)
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2((index % columns) * definition.frame_width, int(index / columns) * definition.frame_height, definition.frame_width, definition.frame_height)
		_textures[key] = frame
	return _textures[key]

static func icon(name: String) -> AtlasTexture:
	var key := "icon_" + name
	if not _textures.has(key):
		var rect: Array = catalog().icons[name]
		var texture := AtlasTexture.new()
		texture.atlas = preload("res://assets/ui/source/icons.png")
		texture.region = Rect2(rect[0], rect[1], rect[2], rect[3])
		_textures[key] = texture
	return _textures[key]
