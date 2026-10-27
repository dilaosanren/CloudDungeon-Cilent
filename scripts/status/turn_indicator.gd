# SPD StatusPane counter / BusyIndicator / CircleArc adaptation, GPL-3.0-or-later.
extends Control

const TRIANGLES := 18
const RADIUS := 4.25
const CENTER := Vector2(4, 4)
var action_time := 0.0
var sweep := 0.0
var busy_image: TextureRect
var _arc: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(8, 8)
	busy_image = TextureRect.new()
	busy_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy_image.texture = MenuAssets.icon("BUSY")
	busy_image.size = size
	busy_image.pivot_offset = CENTER
	busy_image.hide()
	add_child(busy_image)
	# CircleArc is added after BusyIndicator and uses additive blending upstream.
	_arc = Control.new()
	_arc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_arc.material = blend
	_arc.draw.connect(_draw_arc)
	add_child(_arc)
	set_process(false)

func set_state(own_time: float, alive: bool, ready_for_input: bool) -> void:
	action_time = own_time
	# Same formula as StatusPane: (1 - Actor.now() % 1) % 1.
	# The PvP counterpart is this player's authoritative accumulated action time.
	var next := fposmod(1.0 - fposmod(own_time, 1.0), 1.0)
	if next != sweep:
		sweep = next
		_arc.queue_redraw()
	busy_image.visible = alive and not ready_for_input
	set_process(busy_image.visible)

func _process(delta: float) -> void:
	if is_visible_in_tree():
		busy_image.rotation = fposmod(busy_image.rotation + delta * TAU * 2.0, TAU)

func _draw_arc() -> void:
	if sweep <= 0.0: return
	var points := PackedVector2Array([CENTER])
	# Original fan starts at the remaining fraction and ends at twelve o'clock.
	var start := TAU * (1.0 - sweep) - PI / 2.0
	for i in TRIANGLES + 1:
		var angle := start + i * TAU / TRIANGLES * sweep
		points.append(CENTER + Vector2(cos(angle), sin(angle)) * RADIUS)
	_arc.draw_colored_polygon(points, Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0))
