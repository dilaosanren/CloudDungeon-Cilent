# Native terrain renderer plus an exact 12x12 mouse/touch painting surface.
extends Control
signal stroke_started
signal painted(cell: Vector2i)
signal stroke_finished
const Data = preload("res://scripts/maps/submitted_map.gd")
var editable := false
var document: Dictionary = {}
var map: DungeonMap
var overlay: Node2D
var _holding := false
var _last := Vector2i(-1,-1)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if editable else Control.MOUSE_FILTER_IGNORE
	map = DungeonMap.new()
	map.auto_refresh_visibility = false
	add_child(map)
	map.fog_renderer.hide()
	overlay = Node2D.new()
	# Keep grid/markers in local draw order so other cards and modal windows
	# can cover them; a global high Z would leak through those windows.
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	resized.connect(_layout)
	if not document.is_empty(): set_document(document)
	_layout()

func set_document(value: Dictionary) -> void:
	document = value.duplicate(true)
	if map == null: return
	map.region = int(document.region)
	map.set_map(Vector2i(12,12),PackedInt32Array(document.tiles),402)
	# The normal renderer assumes off-map cells are walls. Its southern
	# overhang must not cover the final half-row of an editable 12x12 surface.
	for x in 12:
		if not DungeonTerrain.is_wall(int(document.tiles[x+11*12])): map.layers.Walls.erase_cell(Vector2i(x,11))
	map.fog_renderer.hide()
	overlay.queue_redraw()

func _layout() -> void:
	var side := minf(size.x,size.y)
	var origin := (size-Vector2.ONE*side)/2
	if map != null:
		map.scale = Vector2.ONE*(side/192)
		map.position = origin
	if overlay != null:
		overlay.position = origin
		overlay.queue_redraw()

func _draw_overlay() -> void:
	if document.is_empty(): return
	var side := minf(size.x,size.y)
	var unit := side/12
	for line in 13:
		overlay.draw_line(Vector2(line*unit,0),Vector2(line*unit,side),Color(1,1,1,0.16))
		overlay.draw_line(Vector2(0,line*unit),Vector2(side,line*unit),Color(1,1,1,0.16))
	for index in 2:
		var point: Array = document.spawns[index]
		var center := Vector2(float(point[0])+0.5,float(point[1])+0.5)*unit
		overlay.draw_circle(center,unit*0.35,Color("226622") if index == 0 else Color("882222"))
		overlay.draw_set_transform(center-Vector2(1.5,3),0,Vector2.ONE*minf(1,unit/12))
		SpdPixelText.draw(overlay,Vector2.ZERO,"A" if index == 0 else "B",Color.WHITE)
		overlay.draw_set_transform(Vector2.ZERO)

func _paint_to(at: Vector2) -> void:
	var side := minf(size.x,size.y)
	var origin := (size-Vector2.ONE*side)/2
	if side <= 0 or not Rect2(origin,Vector2.ONE*side).has_point(at): return
	var cell := Vector2i(((at-origin)/(side/12)).floor())
	if cell == _last: return
	if _last.x >= 0:
		var distance := maxi(absi(cell.x-_last.x),absi(cell.y-_last.y))
		for step in range(1,distance+1): painted.emit(Vector2i(Vector2(_last).lerp(Vector2(cell),float(step)/distance).round()))
	else: painted.emit(cell)
	_last = cell

func _gui_input(event: InputEvent) -> void:
	if not editable: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_holding = true
			_last = Vector2i(-1,-1)
			stroke_started.emit()
			_paint_to(event.position)
		else: finish_stroke()
		accept_event()
	elif event is InputEventMouseMotion and _holding:
		_paint_to(event.position)
		accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT: finish_stroke()

func finish_stroke() -> void:
	if not _holding: return
	_holding = false
	stroke_finished.emit()
