# StyledButton icon/text layout and GREY_BUTTON_TR chrome, GPL-3.0-or-later.
class_name DungeonMenuButton
extends Button

var caption := ""
var icon_texture: Texture2D
var caption_color := Color.WHITE
var icon_view: TextureRect
var caption_view: Label
var _click: AudioStreamPlayer

func configure(label: String, texture: Texture2D, color: Color = Color.WHITE) -> void:
	caption = label
	icon_texture = texture
	caption_color = color
	tooltip_text = label
	if is_node_ready():
		caption_view.text = caption
		caption_view.add_theme_color_override("font_color", caption_color)
		icon_view.texture = icon_texture
		_layout_content()

func _ready() -> void:
	text = "" # StyledButton draws its own icon + label as one centered group.
	add_theme_font_override("font", UiAssets.get_font())
	add_theme_font_size_override("font_size", 9)
	UiAssets.apply_button_style(self, "GREY_BUTTON_TR")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box := get_theme_stylebox(state)
		box.set_content_margin(SIDE_TOP, 2)
		box.set_content_margin(SIDE_BOTTOM, 2)
	icon_view = TextureRect.new()
	icon_view.texture = icon_texture
	icon_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_view.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon_view)
	caption_view = Label.new()
	caption_view.text = caption
	caption_view.add_theme_font_override("font", UiAssets.get_font())
	caption_view.add_theme_font_size_override("font_size", 9)
	caption_view.add_theme_color_override("font_color", caption_color)
	caption_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAssets.apply_text_outline(caption_view)
	add_child(caption_view)
	_click = AudioStreamPlayer.new()
	_click.stream = preload("res://assets/inventory/click.mp3")
	add_child(_click)
	button_down.connect(func(): _click.play())
	resized.connect(_layout_content)
	caption_view.minimum_size_changed.connect(_layout_content)
	_layout_content()

func _layout_content() -> void:
	if caption_view == null or icon_texture == null: return
	var icon_size := icon_texture.get_size()
	var text_size := caption_view.get_minimum_size()
	var component_width := icon_size.x + 2 + text_size.x + 2
	icon_view.position = Vector2((size.x - component_width) / 2 + 1, (size.y - icon_size.y) / 2).floor()
	icon_view.size = icon_size
	caption_view.position = Vector2((size.x + component_width) / 2 - text_size.x - 1, (size.y - text_size.y) / 2).floor()
	caption_view.size = text_size
