# SPD FogOfWar.java and WallBlockingTilemap.java. GPL-3.0-or-later.
class_name DungeonFogRenderer
extends Node2D

const Rules = preload("res://scripts/dungeon_terrain.gd")
const BLOCKING = preload("res://assets/environment/wall_blocking.png")
const COLORS = [
	[Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0)],
	[Color8(0, 0, 0, 0xcc), Color8(0, 0, 0, 0x99), Color8(0, 0, 0, 0x55)],
	[Color8(0x11, 0x22, 0x44, 0xcc), Color8(0x19, 0x33, 0x66, 0x99), Color8(0x22, 0x44, 0x88, 0x55)],
	[Color.BLACK, Color.BLACK, Color.BLACK]]
var brightness := 0
var mining_level := false
var halls_boss_level := false
var pixels: Image
var texture: ImageTexture
var sprite: Sprite2D
var block_codes := PackedInt32Array()
var _vision: DungeonVisibility
var _terrain := PackedInt32Array()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 100
	sprite = Sprite2D.new()
	sprite.name = "FogTexture"
	sprite.centered = false
	sprite.texture = texture
	sprite.scale = Vector2.ONE * 8 # Original: 2 fog pixels per 16px tile.
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR # Original TextureCache.create uses LINEAR.
	add_child(sprite)

func update_fog(vision: DungeonVisibility, terrain: PackedInt32Array) -> void:
	_vision = vision
	_terrain = terrain
	if vision.size.x <= 0 or vision.size.y <= 0:
		return
	var dimensions := Vector2i(1, 1)
	while dimensions.x < vision.size.x * 2:
		dimensions.x *= 2
	while dimensions.y < vision.size.y * 2:
		dimensions.y *= 2
	if pixels == null or pixels.get_size() != dimensions:
		pixels = Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.BLACK)
	block_codes.resize(terrain.size())
	for c in terrain.size():
		var halves := cell_fog(c)
		var x := (c % vision.size.x) * 2
		var y := (c / vision.size.x) * 2
		for side in 2:
			var color: Color = COLORS[halves[side]][clampi(brightness + 1, 0, 2)]
			pixels.set_pixel(x + side, y, color)
			pixels.set_pixel(x + side, y + 1, color)
		block_codes[c] = _block_code(c)
	if texture == null or texture.get_size() != Vector2(dimensions):
		texture = ImageTexture.create_from_image(pixels)
	else:
		texture.update(pixels)
	if sprite != null:
		sprite.texture = texture
	queue_redraw()

func cell_fog(c: int) -> Vector2i:
	var own := _vision.state(c)
	if not _vision.discoverable[c] or own == DungeonVisibility.State.UNKNOWN:
		return Vector2i(3, 3)
	if not _wall(c):
		return Vector2i(own, own)
	var width := _vision.size.x
	if c + width >= _terrain.size():
		return Vector2i(3, 3)
	if not _wall(c + width):
		var shade := maxi(own, _vision.state(c + width))
		return Vector2i(shade, shade)
	var result := Vector2i(3, 3)
	if c % width != 0:
		if _wall(c - 1):
			if not _wall(c + width - 1):
				result.x = maxi(own, maxi(_vision.state(c - 1), _vision.state(c + width - 1)))
		else:
			result.x = maxi(own, _vision.state(c - 1))
	if (c + 1) % width != 0:
		if _wall(c + 1):
			if not _wall(c + width + 1):
				result.y = maxi(own, maxi(_vision.state(c + 1), _vision.state(c + width + 1)))
		else:
			result.y = maxi(own, _vision.state(c + 1))
	return result

func _wall(c: int) -> bool:
	return c < 0 or c >= _terrain.size() or Rules.is_wall(_terrain[c])

func _shelf(c: int) -> bool:
	return c >= 0 and c < _terrain.size() and _terrain[c] == Rules.Type.BOOKSHELF

func _hidden(c: int) -> bool:
	if c < 0 or c >= _terrain.size():
		return true
	if not _vision.visited[c] and not _vision.mapped[c]:
		return true
	var below := c + _vision.size.x
	return _wall(c) and below < _terrain.size() and not _wall(below) and not _vision.visited[below] and not _vision.mapped[below]

func _block_code(c: int) -> int:
	var w := _vision.size.x
	if halls_boss_level or not _vision.discoverable[c] or c - w <= 0 or c + w >= _terrain.size():
		return -2
	if not _wall(c):
		if not _hidden(c) or not _wall(c + w):
			return -2
		if not _hidden(c + w) and (_hidden(c - 1) or _wall(c - 1)) and (_hidden(c + 1) or _wall(c + 1)) and (_hidden(c - 1 + w) or _wall(c - 1 + w)) and (_hidden(c + 1 + w) or _wall(c + 1 + w)):
			return 3
		return -1
	if not _wall(c + w):
		if _wall(c - 1 - w) and _wall(c - w) and _wall(c + 1 - w):
			return -1 if mining_level or _shelf(c - 1 - w) or _shelf(c - w) or _shelf(c + 1 - w) else -2
		if (not _wall(c - 1 - w) and not _hidden(c - 1 - w) and _wall(c - 1)) or (not _wall(c - w) and not _hidden(c - w)) or (not _wall(c + 1 - w) and not _hidden(c + 1 - w) and _wall(c + 1)):
			if not _hidden(c + w) or (not _wall(c - 1) and not _hidden(c - 1)) or (not _wall(c - 1 + w) and not _hidden(c - 1 + w)) or (not _wall(c + 1) and not _hidden(c + 1)) or (not _wall(c + 1 + w) and not _hidden(c + 1 + w)):
				return -2
			return 2
		return -1
	var code := -1
	if not _hidden(c - w) or not _hidden(c - w - 1) or not _hidden(c - w + 1) or not _hidden(c) or not _hidden(c + w):
		if not ((c + 1) % w == 0 or (not _wall(c + 1) and not _hidden(c + 1 - w)) or (not _wall(c + 1) and not _hidden(c + 1)) or (not _wall(c + 1 + w) and not _hidden(c + 1 + w))):
			code += 1
		if not (c % w == 0 or (not _wall(c - 1) and not _hidden(c - 1 - w)) or (not _wall(c - 1) and not _hidden(c - 1)) or (not _wall(c - 1 + w) and not _hidden(c - 1 + w))):
			code += 2
		if code == -1:
			code = -2
	return code

func _draw() -> void:
	if _vision == null:
		return
	var columns := BLOCKING.get_width() / 16
	for c in block_codes.size():
		var code := block_codes[c]
		if code >= 0:
			var region := Rect2((code % columns) * 16, (code / columns) * 16, 16, 16)
			draw_texture_rect_region(BLOCKING, Rect2(Vector2(c % _vision.size.x, c / _vision.size.x) * 16, Vector2.ONE * 16), region)
