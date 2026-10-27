# Original inventory bitmap digits and click sample, with alternating tick pitches.
extends Control

const TickSound = preload("res://scripts/pvp/client/countdown_sound.gd")
const DIGIT_SCALE := 2.0
var seconds := -1
var _sound: TickSound

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sound = TickSound.new()
	add_child(_sound)

func reset() -> void:
	if seconds == -1: return
	seconds = -1
	if _sound != null: _sound.reset()
	queue_redraw()

func set_seconds(value: int) -> void:
	if value == seconds: return
	seconds = value
	queue_redraw()
	if seconds > 0 and is_visible_in_tree(): _sound.set_seconds(seconds)

func _draw() -> void:
	if seconds < 0: return
	var text := str(seconds)
	var origin := ((size - SpdPixelText.measure(text) * DIGIT_SCALE) / 2).floor()
	for offset in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1),
		Vector2(-1, 0), Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]:
		SpdPixelText.draw(self, origin + offset, text, Color.BLACK, DIGIT_SCALE)
	SpdPixelText.draw(self, origin, text, Color("ff4444"), DIGIT_SCALE)
