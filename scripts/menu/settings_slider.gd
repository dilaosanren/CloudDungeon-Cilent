# OptionSlider.java adaptation. GPL-3.0-or-later.
extends Control

signal selected(value: int)

const Art = preload("res://scripts/ui/ui_assets.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
var minimum := 0
var maximum := 10
var current := 0
var caption := ""
var value_names: Array[String] = []
var _dragging := false
var _fraction := 0.0
var _title: Label
var _low: Label
var _high: Label

func configure(title: String, low: String, high: String, from: int, to: int, initial: int, names: Array[String] = []) -> void:
	caption = title
	minimum = from
	maximum = to
	current = clampi(initial, from, to)
	value_names = names
	_fraction = float(current - minimum) / (maximum - minimum)
	_title = _label("", 9, HORIZONTAL_ALIGNMENT_CENTER)
	_low = _label(low, 6, HORIZONTAL_ALIGNMENT_LEFT)
	_high = _label(high, 6, HORIZONTAL_ALIGNMENT_RIGHT)
	_update_title()
	tooltip_text = title
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(_layout)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func _label(text: String, font_size: int, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Art.apply_text_outline(label)
	add_child(label)
	return label

func _layout() -> void:
	_title.position = Vector2(2, 0)
	_title.size = Vector2(size.x - 4, 13)
	_low.position = Vector2(2, 11)
	_low.size = Vector2(size.x / 2 - 2, 9)
	_high.position = Vector2(size.x / 2, 11)
	_high.size = Vector2(size.x / 2 - 2, 9)
	queue_redraw()

func _draw() -> void:
	var background: StyleBoxTexture = Art.get_style("ORANGE_BUTTON").duplicate()
	background.modulate_color.a = 0.5
	draw_style_box(background, Rect2(Vector2.ZERO, size))
	var track_y := size.y - 6
	var length := size.x - 5
	draw_rect(Rect2(2, track_y, length, 1), Color("222222"))
	for i in range(maximum - minimum + 1):
		var x := roundf(2 + length * i / (maximum - minimum))
		draw_rect(Rect2(x, track_y - 4, 1, 9), Color("222222"))
	var knob: StyleBoxTexture = Art.get_style("ORANGE_BUTTON").duplicate()
	if _dragging: knob.modulate_color = Color(1.5, 1.5, 1.5)
	draw_style_box(knob, Rect2(roundf(length * _fraction), track_y - 3, 4, 7))
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size), Color("ffff44"), false, 1)

func _update_title() -> void:
	var name := str(current)
	if not value_names.is_empty(): name = value_names[current - minimum]
	_title.text = L10n.text(caption) + " · " + L10n.text(name)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_title):
		_update_title()

func _point(at: float) -> void:
	_fraction = clampf((at - 2) / maxf(1, size.x - 5), 0, 1)
	queue_redraw()

func _commit() -> void:
	current = minimum + roundi(_fraction * (maximum - minimum))
	_fraction = float(current - minimum) / (maximum - minimum)
	_update_title()
	queue_redraw()
	selected.emit(current)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			_dragging = true
			_point(event.position.x)
		elif _dragging:
			_point(event.position.x)
			_dragging = false
			_commit()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_point(event.position.x)
		accept_event()
	elif event is InputEventKey and event.pressed:
		var next := current
		match event.keycode:
			KEY_LEFT, KEY_DOWN: next -= 1
			KEY_RIGHT, KEY_UP: next += 1
			KEY_HOME: next = minimum
			KEY_END: next = maximum
			_: return
		_fraction = float(clampi(next, minimum, maximum) - minimum) / (maximum - minimum)
		_commit()
		accept_event()
