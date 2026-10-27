extends Node2D
## Static feedback while a pointer is held; no timer or per-frame processing.
const TILE_SIZE := 16
var cell := Vector2i(-1, -1)

func _ready() -> void:
	z_index = 50
	clear()

func hold(selected: Vector2i) -> void:
	if visible and cell == selected: return
	cell = selected
	position = Vector2(selected * TILE_SIZE)
	show()
	queue_redraw()

func clear() -> void:
	hide()
	set_process(false)

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2.ONE * TILE_SIZE)
	draw_rect(rect, Color(1, 1, 1, 0.4))
	draw_rect(rect.grow(-0.5), Color(1, 1, 1, 0.7), false, 1.0)
