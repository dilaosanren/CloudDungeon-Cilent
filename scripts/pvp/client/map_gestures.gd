# CellSelector.java / PixelScene.java / Camera.shift, SPD 4.0.2.
# Client camera only; never changes visibility, actor cells or game time.
extends Node

signal tapped(position: Vector2)
signal pressing(position: Vector2)
signal press_ended

const TILE_SIZE := 16.0
const UI_ZOOM := 2.0
const MOUSE_POINTER := -100
var stage: Control
var map: DungeonMap
## Framing uses the battlefield, while selection retains the full target grid.
var view_bounds := Rect2i()
var available: Callable
var center := Vector2.ZERO
var zoom_pixels := 2.0
var default_zoom_pixels := 2.0
var physical_scale := 1.0
var _match_id := ""
var _initialized := false
var _bounds := Rect2()
var _pointers: Dictionary = {}
var _primary := MOUSE_POINTER
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _dragging := false
var _pinching := false
var _start_zoom := 2.0
var _start_span := 1.0
var _mouse_zoom := 2.0

func update_layout(match_id: String) -> void:
	if map == null or map.map_size == Vector2i.ZERO: return
	var next_scale := maxf(0.01, absf(get_viewport().get_final_transform().get_scale().x))
	var next_bounds := stage.get_global_rect()
	var next_default := maxf(1, roundf(UI_ZOOM * next_scale))
	var reset_mouse := false
	if not _initialized or _match_id != match_id:
		reset_mouse = true
		reset()
		_match_id = match_id
		_initialized = true
		var focus := view_bounds if view_bounds.has_area() else Rect2i(Vector2i.ZERO, map.map_size)
		center = Vector2(focus.position) * 16 + Vector2(focus.size * 16) / 2
		# Preserve the existing opening view; gestures use the upstream pixel scale.
		var extent := Vector2(focus.size * 16)
		var fit := minf(UI_ZOOM, minf(stage.size.x / extent.x, stage.size.y / extent.y))
		zoom_pixels = clampf(fit * next_scale, 1, next_default * 2)
	elif not _bounds.is_equal_approx(next_bounds) or not is_equal_approx(physical_scale, next_scale):
		reset_mouse = true
		reset()
		zoom_pixels = clampf(zoom_pixels * next_scale / physical_scale, 1, next_default * 2)
	physical_scale = next_scale
	default_zoom_pixels = next_default
	_bounds = next_bounds
	if reset_mouse: _mouse_zoom = zoom_pixels
	_apply()

func _apply() -> void:
	var zoom := zoom_pixels / physical_scale
	map.scale = Vector2.ONE * zoom
	# PixelCamera aligns translations to physical screen pixels.
	map.position = ((stage.size / 2 - center * zoom) * physical_scale).round() / physical_scale

func _can_use() -> bool:
	return _initialized and is_instance_valid(stage) and stage.is_visible_in_tree() and (not available.is_valid() or available.call())

func _emulated(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION

## Start only after GUI hit testing, so bags, toolbars and dialogs keep their input.
func begin(event: InputEvent) -> bool:
	if not _can_use() or _emulated(event): return false
	if event is InputEventMouseButton and event.pressed:
		if not _bounds.has_point(event.position): return false
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var amount: float = event.factor * (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			# CellSelector: diff=amount/10, scaled by current zoom; positive cap=1.
			var difference := minf(1, amount / 10 * zoom_pixels)
			_mouse_zoom = clampf(_mouse_zoom - difference, 1, default_zoom_pixels * 2)
			_set_zoom(roundf(_mouse_zoom))
			get_viewport().set_input_as_handled()
			return true
		if event.button_index == MOUSE_BUTTON_LEFT and _pointers.is_empty():
			_down(MOUSE_POINTER, event.position)
			get_viewport().set_input_as_handled()
			return true
	elif event is InputEventScreenTouch and event.pressed and _bounds.has_point(event.position):
		_down(event.index, event.position)
		get_viewport().set_input_as_handled()
		return true
	return false

## Capture an existing gesture before GUI handling, including a release over UI.
func _input(event: InputEvent) -> void:
	if _pointers.is_empty() or _emulated(event): return
	if not _can_use(): reset(); return
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_BACK]:
		reset()
		return
	if event is InputEventMouseMotion and _pointers.has(MOUSE_POINTER):
		_move(MOUSE_POINTER, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and _pointers.has(MOUSE_POINTER):
		get_viewport().set_input_as_handled()
		_up(MOUSE_POINTER, event.position, event.canceled)
		return
	elif event is InputEventScreenDrag and _pointers.has(event.index):
		_move(event.index, event.position)
	elif event is InputEventScreenTouch and not event.pressed and _pointers.has(event.index):
		get_viewport().set_input_as_handled()
		_up(event.index, event.position, event.canceled)
		return
	else: return
	get_viewport().set_input_as_handled()

func _down(pointer: int, position: Vector2) -> void:
	if _pointers.has(pointer): return
	if _pointers.size() >= 2 or not _pointers.is_empty() and _pointers.has(MOUSE_POINTER):
		reset()
		return
	_pointers[pointer] = position
	if _pointers.size() == 1:
		_primary = pointer
		_start = position
		_last = position
		_dragging = false
		pressing.emit(position)
	else:
		press_ended.emit()
		_pinching = true
		_dragging = false
		var points := _pointers.values()
		_start_span = maxf(1, (points[0] as Vector2).distance_to(points[1]))
		_start_zoom = zoom_pixels

func _move(pointer: int, position: Vector2) -> void:
	_pointers[pointer] = position
	if _pinching:
		var points := _pointers.values()
		var span := (points[0] as Vector2).distance_to(points[1])
		var zoom := _start_zoom * span / _start_span
		# Upstream pinch zoom is truncated to 0.1 physical-pixel increments.
		_set_zoom(floorf(zoom * 10) / 10)
	elif pointer == _primary:
		var threshold := default_zoom_pixels * TILE_SIZE / 2 / physical_scale
		if not _dragging and position.distance_to(_start) > threshold:
			_dragging = true
			press_ended.emit()
			_last = position
		elif _dragging:
			center += (_last - position) / (zoom_pixels / physical_scale)
			_last = position
			_apply()
		else:
			pressing.emit(position)

func _up(pointer: int, position: Vector2, canceled: bool) -> void:
	press_ended.emit()
	var was_pinching := _pinching
	_pointers.erase(pointer)
	if was_pinching:
		_pinching = false
		_set_zoom(roundf(zoom_pixels))
		_mouse_zoom = zoom_pixels
		_dragging = true # Releasing either pinch finger must never select a cell.
		if not _pointers.is_empty():
			_primary = int(_pointers.keys()[0])
			_last = _pointers[_primary]
	elif pointer == _primary:
		var select := not canceled and not _dragging and _bounds.has_point(position)
		reset()
		if select: tapped.emit(position)
	if _pointers.is_empty():
		_dragging = false
		_pinching = false

func _set_zoom(value: float) -> void:
	press_ended.emit()
	zoom_pixels = clampf(value, 1, default_zoom_pixels * 2)
	# Camera.zoom keeps the camera's center, rather than shifting toward a finger.
	_apply()

func reset() -> void:
	press_ended.emit()
	if _pinching and _initialized:
		_set_zoom(roundf(zoom_pixels))
		_mouse_zoom = zoom_pixels
	_pointers.clear()
	_dragging = false
	_pinching = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: reset()
