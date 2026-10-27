# SPD BitmapText.Font.colorMarked / PixelScene.pixelFont. GPL-3.0-or-later.
# Draw the original PNG glyphs directly; the similarly named TTF is a different font.
class_name SpdPixelText
extends RefCounted

const TEXTURE: Texture2D = preload("res://assets/inventory/pixel_font.png")
const BASELINE: int = 6
const TRACKING: int = -1
static var _glyphs: Dictionary = {}

static func _column_has_ink(bitmap: Image, x: int) -> bool:
	for y in bitmap.get_height():
		if bitmap.get_pixel(x, y).a > 0: return true
	return false

static func _index() -> void:
	if not _glyphs.is_empty(): return
	var bitmap := TEXTURE.get_image()
	var x := 0
	while x < bitmap.get_width() and not _column_has_ink(bitmap, x): x += 1
	_glyphs[" "] = Rect2(0, 0, x, bitmap.get_height())
	# LATIN_FULL is ASCII 32 through 127; transparent columns separate glyphs.
	for codepoint in range(33, 128):
		while x < bitmap.get_width() and not _column_has_ink(bitmap, x): x += 1
		var start := x
		while x < bitmap.get_width() and _column_has_ink(bitmap, x): x += 1
		if x <= start:
			push_error("Invalid SPD pixel font: missing glyph %d" % codepoint)
			return
		_glyphs[String.chr(codepoint)] = Rect2(start, 0, x - start, bitmap.get_height())
		x += 1

static func glyph_rect(character: String) -> Rect2:
	_index()
	return _glyphs.get(character, _glyphs["?"])

static func measure(text: String) -> Vector2:
	var width := 0.0
	for character in text: width += glyph_rect(character).size.x + TRACKING
	if not text.is_empty(): width -= TRACKING
	return Vector2(width, TEXTURE.get_height() if not text.is_empty() else 0)

static func draw(canvas: CanvasItem, top_left: Vector2, text: String, color: Color = Color.WHITE, factor: float = 1.0) -> void:
	var x := 0.0
	for character in text:
		var region := glyph_rect(character)
		canvas.draw_texture_rect_region(TEXTURE, Rect2(top_left + Vector2(x, 0), region.size * factor), region, color)
		x += (region.size.x + TRACKING) * factor
