# ChangesScene-style icon and text, with the explanation always visible.
extends Control
const NativeText = preload("res://scripts/ui/native_rich_text.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
var icon_view: TextureRect
var title_view: NativeText
var body_view: NativeText

func configure(entry: Dictionary, texture: Texture2D) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_view = TextureRect.new()
	icon_view.texture = texture
	icon_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_view.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon_view)
	title_view = _text("[color=#ffff44]" + L10n.text(str(entry.title)) + "[/color]", 9)
	body_view = _text(L10n.text(str(entry.body)), 8)

func _text(value: String, font_size: int) -> NativeText:
	var view := NativeText.new()
	view.font_size = font_size
	view.text = value
	add_child(view)
	view.minimum_size_changed.connect(func(): minimum_size_changed.emit())
	return view

func _place_text(view: NativeText, at: Vector2, width: float) -> float:
	view.position = at.floor()
	view.size.x = maxf(1, width)
	view.refresh_pixels()
	view.size.y = view.get_content_height()
	return view.size.y

func layout_width(width: float) -> float:
	size.x = width
	icon_view.position = Vector2(3, 6)
	icon_view.size = Vector2(24, 24)
	var top := 5.0
	top += _place_text(title_view, Vector2(34, top), width - 39) + 4
	top += _place_text(body_view, Vector2(34, top), width - 39) + 9
	size.y = ceilf(maxf(38, top))
	queue_redraw()
	return size.y

func _draw() -> void:
	draw_line(Vector2(5, size.y - 1), Vector2(size.x - 5, size.y - 1), Color(0.6, 0.6, 0.5, 0.25))
