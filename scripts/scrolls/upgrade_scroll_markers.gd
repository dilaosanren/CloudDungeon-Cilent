# A sensed scroll is visible above fog, without changing explored cells or FOV.
extends Node2D

var markers: Dictionary = {}
var _item: InventoryItem
var _positions: Array[Vector2i] = []

func _init() -> void:
	z_index = 108

func sync(cells: Array, vision: DungeonVisibility, offset := Vector2i.ZERO) -> void:
	var wanted := {}
	_positions.clear()
	for value in cells:
		var cell := int(value)
		if cell < 0 or cell >= vision.visible.size(): continue
		var at := Vector2i(cell % vision.size.x, cell / vision.size.x) + offset
		_positions.append(at)
		if vision.visible[cell]: continue
		wanted[cell] = true
		if not markers.has(cell):
			if _item == null: _item = InventoryCatalog.create("ScrollOfUpgrade")
			var sprite := DungeonItemSprite.new()
			sprite.show_shadow = false
			add_child(sprite)
			sprite.set_item(_item)
			markers[cell] = sprite
		markers[cell].place(at)
	for cell in markers.keys():
		if not wanted.has(cell):
			markers[cell].hide()
			markers[cell].queue_free()
			markers.erase(cell)
	queue_redraw()

func _draw() -> void:
	# Keep a visible location indicator even if another item covers the scroll
	# in a mixed heap. Corners leave the original item artwork unobscured.
	for at in _positions:
		var origin := Vector2(at * 16)
		for corner in [Vector2(1,1), Vector2(14,1), Vector2(1,14), Vector2(14,14)]:
			var point: Vector2 = origin + corner
			draw_line(point, point + Vector2(3 if corner.x < 8 else -3, 0), Color("ffdd55"))
			draw_line(point, point + Vector2(0, 3 if corner.y < 8 else -3), Color("ffdd55"))

func clear() -> void:
	for sprite in markers.values():
		sprite.hide()
		sprite.queue_free()
	markers.clear()
	_positions.clear()
	queue_redraw()
