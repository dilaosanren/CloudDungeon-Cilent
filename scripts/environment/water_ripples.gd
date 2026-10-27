# SPD Effects.RIPPLE / Ripple.java, GPL-3.0-or-later.
# Pure presentation: elapsed frame time never advances the authoritative world.
extends Node2D

const ATLAS = preload("res://assets/wands/source/effects.png")
const FRAME := Rect2(0, 0, 16, 16)
const TIME_TO_FADE := 0.5
var ripples: Array[Dictionary] = []

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)

func emit_at(cell: Vector2i) -> void:
	ripples.append({"center":Vector2(cell * 16) + Vector2(8, 8), "age":0.0})
	set_process(true)
	queue_redraw()

func clear() -> void:
	ripples.clear()
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	for index in range(ripples.size() - 1, -1, -1):
		ripples[index].age += delta
		if ripples[index].age >= TIME_TO_FADE: ripples.remove_at(index)
	set_process(not ripples.is_empty())
	queue_redraw()

func _draw() -> void:
	for ripple in ripples:
		var progress := clampf(float(ripple.age) / TIME_TO_FADE, 0, 1)
		if progress <= 0: continue
		var extent := Vector2.ONE * 16 * progress
		# Noosa Image scales around its (8,8) origin, with alpha = time remaining.
		draw_texture_rect_region(ATLAS, Rect2(Vector2(ripple.center) - extent / 2, extent), FRAME, Color(1, 1, 1, 1 - progress))
