# BuffIndicator.BuffButton, GPL-3.0-or-later.
class_name StatusBuffButton
extends BaseButton

var buff: StatusBuff
var pixel_zoom: float = 2.0

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func icon_rect() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2.ONE * StatusAssets.LARGE_SIZE)

func _draw() -> void:
	if buff == null: return
	var texture := StatusAssets.icon_texture(buff.icon_id)
	if texture == null: return
	var rect := icon_rect()
	draw_texture_rect(texture, rect, false, buff.tint)
	if buff.icon_text.is_empty():
		var height := clampf(buff.fade_percent, 0, 1) * rect.size.y
		height = ceilf(height * pixel_zoom) / pixel_zoom if height < rect.size.y / 2 else floorf(height * pixel_zoom) / pixel_zoom
		draw_rect(Rect2(rect.position, Vector2(rect.size.x, height)), Color(0.4, 0.4, 0.4, 0.8))
	else:
		var factor := 0.5 if SpdPixelText.measure(buff.icon_text).x > size.x else 1.0
		var measured := SpdPixelText.measure(buff.icon_text) * factor
		var color := Color.GREEN if buff.kind > 0 else UiPalette.color(Color.RED) if buff.kind < 0 else Color.WHITE
		color.a = 0.7
		var point := Vector2(size.x - measured.x - 1, size.x - SpdPixelText.BASELINE * factor - 2)
		point = (point * pixel_zoom).floor() / pixel_zoom
		SpdPixelText.draw(self, point, buff.icon_text, color, factor)
