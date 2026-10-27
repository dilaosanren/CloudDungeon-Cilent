# AboutScene.CreditsBlock / RenderedTextBlock adaptation. GPL-3.0-or-later.
extends Control

const NativeText = preload("res://scripts/ui/native_rich_text.gd")
var large := false
var highlight := Color.WHITE
var title_view: NativeText
var body_view: NativeText
var avatar: TextureRect
var link_button: Button
var link_view: NativeText
var _angle := 45.0

func configure(data: Dictionary, texture: Texture2D) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	large = bool(data.get("large", false))
	highlight = Color(str(data.get("color", "ffffff")))
	if not str(data.get("title", "")).is_empty():
		title_view = _text(str(data.title), 8 if large else 6, true, true)
	if texture != null:
		avatar = TextureRect.new()
		avatar.texture = texture
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		avatar.size = texture.get_size() * (0.5 if texture.get_width() > 20 else 1.0)
		add_child(avatar)
	body_view = _text(str(data.body), 6, large)
	if not str(data.get("link_url", "")).is_empty():
		link_button = Button.new()
		link_button.name = "CreditLink"
		link_button.tooltip_text = str(data.link_url)
		link_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			link_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		add_child(link_button)
		link_view = _text("[u]" + str(data.link_text) + "[/u]", 6, true, true, link_button)
		var url := str(data.link_url)
		link_button.pressed.connect(func(): OS.shell_open(url))
	set_process(large and avatar != null)

func _text(value: String, font_size: int, centered: bool, colored: bool = false, parent: Node = null) -> NativeText:
	if parent == null: parent = self
	var view := NativeText.new()
	view.font_size = font_size
	var emphasis := RegEx.new()
	emphasis.compile("_([^_]+)_")
	value = emphasis.sub(value, "[color=#%s]$1[/color]" % highlight.to_html(false), true)
	if colored: value = "[color=#%s]%s[/color]" % [highlight.to_html(false), value]
	view.text = "[center]" + value + "[/center]" if centered else value
	parent.add_child(view)
	view.minimum_size_changed.connect(func(): minimum_size_changed.emit())
	return view

func _place_text(view: NativeText, at: Vector2, width: float) -> float:
	view.position = at.floor()
	view.size.x = maxf(1, width)
	view.refresh_pixels()
	view.size.y = view.get_content_height()
	return view.size.y

func layout_at(at: Vector2, width: float) -> float:
	position = at.floor()
	size.x = width
	var top := 0.0
	if title_view != null:
		top += _place_text(title_view, Vector2.ZERO, width) + (2 if large else 1)
	if large:
		if avatar != null:
			avatar.position = Vector2((width - avatar.size.x) / 2, top).floor()
			top += avatar.size.y + 2
		top += _place_text(body_view, Vector2(0, top), width) + 2
	elif avatar != null:
		var body_height := _place_text(body_view, Vector2(avatar.size.x + 1, top), width - avatar.size.x - 1)
		var row_height := maxf(maxf(16, avatar.size.y), body_height)
		avatar.position = Vector2(0, top + (row_height - avatar.size.y) / 2).floor()
		body_view.position.y = floorf(top + (row_height - body_height) / 2)
		top += row_height + 2
	else:
		top += _place_text(body_view, Vector2(0, top + 1), width) + 3
	if link_button != null:
		top += 1 if large else 0
		link_button.position = Vector2(0, top - 1)
		var link_height := _place_text(link_view, Vector2(0, 1), width)
		link_button.size = Vector2(width, link_height + 3)
		top += link_height + 3
	size.y = ceilf(top)
	queue_redraw()
	return size.y

func _process(delta: float) -> void:
	_angle = fmod(_angle + 20 * delta, 360)
	queue_redraw()

func _draw() -> void:
	if not large or avatar == null: return
	var center := avatar.position + avatar.size / 2
	# Seven rotating rays, radius 24, fading from the icon toward their tips.
	for ray in 7:
		var angle := deg_to_rad(_angle) + ray * TAU / 7
		var points := PackedVector2Array([center, center + Vector2.from_angle(angle) * 24, center + Vector2.from_angle(angle + PI / 7) * 24])
		draw_polygon(points, PackedColorArray([Color(highlight, 0.5), Color(highlight, 0), Color(highlight, 0)]))
