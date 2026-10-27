# ItemSlot / InventorySlot geometry, colors and gestures from SPD 4.0.2.
# GPL-3.0-or-later.
class_name InventorySlot
extends Control
const Glow = preload("res://scripts/items/item_glow.gd")

signal clicked
signal right_clicked
signal long_clicked

var item: InventoryItem
var inventory: DungeonInventory
var placeholder_visual: String = ""
var equipped: bool = false
var enabled: bool = true
var show_extra: bool = true
var quick: bool = false
var _holding: bool = false
var _elapsed: float = 0.0
var _long_fired: bool = false
var _press_position := Vector2.ZERO
var _sound: AudioStreamPlayer
var _image: TextureRect
var _details: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	tooltip_text = item.display_name() if item != null else ""
	# Keep the item shader separate from the slot, badges and bitmap counters.
	_image = TextureRect.new()
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_SCALE
	_image.hide()
	add_child(_image)
	_details = Control.new()
	_details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_details.hide()
	_details.draw.connect(_draw_details)
	add_child(_details)
	queue_redraw()
	_sound = AudioStreamPlayer.new()
	_sound.stream = preload("res://assets/inventory/click.mp3")
	_sound.volume_db = -3.1
	_sound.pitch_scale = 1.2
	add_child(_sound)

func _draw() -> void:
	if not quick and not item is InventoryBag:
		var bg := Color("91938c") if equipped or not placeholder_visual.is_empty() else Color("53564d")
		bg.a = 0.6
		if item != null:
			if item.cursed:
				bg.r += 0.3; bg.g -= 0.15; bg.b -= 0.15
		if _holding: bg = bg.lightened(0.25)
		draw_rect(Rect2(Vector2.ZERO, size), UiPalette.color(bg))
	var alpha := 1.0 if enabled else 0.3
	var texture := ItemAssets.get_texture(item.visual if item != null else placeholder_visual)
	_image.texture = texture
	_image.visible = texture != null
	_image.self_modulate.a = alpha
	if texture != null:
		var tex_size := texture.get_size()
		var fit := minf(1.0, minf((size.x - 2) / tex_size.x, (size.y - 2) / tex_size.y))
		tex_size *= fit
		_image.position = ((size - tex_size) / 2).floor()
		_image.size = tex_size
	Glow.apply(_image, item)
	_details.size = size
	_details.show()
	_details.queue_redraw()

func _draw_details() -> void:
	if item == null: return
	var alpha := 1.0 if enabled else 0.3
	var text_color := Color(1, 1, 1, alpha)
	var status_text := item.status()
	var status_width := SpdPixelText.measure(status_text).x
	SpdPixelText.draw(_details, Vector2.ZERO, status_text, text_color, 0.8 if status_width > size.x else 1.0)
	if show_extra:
		if not item.icon.is_empty():
			var icon_tex := ItemAssets.get_texture(item.icon, true)
			if icon_tex != null:
				_details.draw_texture(icon_tex, Vector2(size.x - icon_tex.get_width() - 1, 0), text_color)
	if item.level != 0:
		var level_text := "%+d" % item.level
		var width := SpdPixelText.measure(level_text).x
		var color := Color("44ff44") if item.level > 0 else UiPalette.color(Color("ff4444"))
		color.a = alpha
		SpdPixelText.draw(_details, Vector2(size.x - width, size.y - SpdPixelText.BASELINE - 1), level_text, color)

func _gui_input(event: InputEvent) -> void:
	if not enabled: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			right_clicked.emit()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if _sound != null: _sound.play()
				_holding = true
				_elapsed = 0
				_long_fired = false
				_press_position = event.position
			else:
				var activate := _holding and not _long_fired and Rect2(Vector2.ZERO, size).has_point(event.position)
				_holding = false
				if activate: clicked.emit()
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _holding:
		if event.position.distance_to(_press_position) > 6 or not Rect2(Vector2.ZERO, size).has_point(event.position):
			_holding = false
			queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_SPACE]:
		clicked.emit()
		accept_event()

func cancel_press() -> void:
	_holding = false
	queue_redraw()

func _process(delta: float) -> void:
	if _holding and not _long_fired:
		_elapsed += delta
		if _elapsed >= 0.5:
			_long_fired = true
			_holding = false
			long_clicked.emit()
			queue_redraw()
