# PixelScene.renderTextBlock: rasterize at screen size, then undo the UI zoom.
# The logical font size stays unchanged; glyph textures are drawn 1:1 on screen.
extends Control

var font_size := 6:
	set(value):
		font_size = maxi(1, value)
		_schedule()
var text := "":
	set(value):
		text = value
		if is_instance_valid(content):
			content.text = value
			_schedule()
var content: RichTextLabel
var _content_height := 0.0
var _pending := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_notify_transform(true)
	content = RichTextLabel.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.bbcode_enabled = true
	content.fit_content = true
	content.scroll_active = false
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_theme_font_override("normal_font", UiAssets.get_native_ui_font())
	UiAssets.apply_text_outline(content)
	content.text = text
	add_child(content)
	content.minimum_size_changed.connect(_schedule)
	resized.connect(_schedule)
	get_viewport().size_changed.connect(_schedule)
	_schedule()

func _schedule() -> void:
	if _pending or not is_inside_tree(): return
	_pending = true
	refresh_pixels.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED: _schedule()

func refresh_pixels() -> void:
	_pending = false
	if not is_instance_valid(content) or not is_inside_tree(): return
	var screen := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	# Aspect-expand can round the viewport width and height differently.
	var density := screen.get_scale().abs().max(Vector2(0.01, 0.01))
	var pixels := maxi(1, roundi(font_size * density.y))
	if content.get_theme_font_size("normal_font_size") != pixels:
		content.add_theme_font_size_override("normal_font_size", pixels)
	content.scale = Vector2.ONE / density
	content.position = (screen.origin.round() - screen.origin) / density
	content.size.x = maxf(1, size.x * density.x)
	var height := content.get_content_height() / density.y
	if not is_equal_approx(_content_height, height):
		_content_height = height
		update_minimum_size()

func get_content_height() -> float:
	return _content_height

func _get_minimum_size() -> Vector2:
	return Vector2(0, _content_height)
