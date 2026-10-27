class_name DungeonItemSprite
extends Node2D

const Assets = preload("res://scripts/items/item_assets.gd")
const Glow = preload("res://scripts/items/item_glow.gd")
# SPD ItemSprite.drop / Visual.updateMotion, in original 16px map units.
const DROP_INTERVAL := 0.4
const DROP_SPEED := -100.0
const DROP_ACCELERATION := -DROP_SPEED / DROP_INTERVAL * 2.0
@export var visual_key: StringName = &"GOLD":
	set(value):
		visual_key = value
		_numeric_id = -1
		if is_node_ready():
			_refresh()
@export var show_shadow: bool = true:
	set(value):
		show_shadow = value
		if is_node_ready():
			shadow.visible = value
var map_cell := Vector2i.ZERO
var sprite: Sprite2D
var shadow: Sprite2D
var _numeric_id: int = -1
var _rest_sprite := Vector2.ZERO
var _rest_shadow := Vector2.ZERO
var _drop_remaining := 0.0
var _drop_speed := 0.0
var _drop_offset := 0.0
var _item: InventoryItem

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.centered = false
	shadow.modulate = Color(0, 0, 0, 0.5)
	add_child(shadow)
	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	add_child(sprite)
	_refresh()

func set_visual(identifier: Variant) -> bool:
	if Assets.get_texture(identifier) == null:
		return false
	_item = null
	visual_key = StringName(str(identifier).to_upper())
	_numeric_id = identifier if identifier is int else -1
	if is_node_ready():
		_refresh()
	return true

func set_item(value: InventoryItem) -> bool:
	if value == null: return false
	var texture := Assets.get_texture(value.visual)
	if texture == null: return false
	# Reusing a ground view must preserve its current drop animation and pulse.
	if not is_node_ready() or sprite.texture != texture:
		if not set_visual(value.visual): return false
	_item = value
	if is_node_ready(): Glow.apply(sprite, value)
	return true

func place(cell: Vector2i, tile_size: int = 16) -> void:
	map_cell = cell
	position = Vector2((cell.x + 0.5) * tile_size, (cell.y + 1.0) * tile_size)
	if is_node_ready(): _finish_drop()

## Called only once the thrown sprite has reached its server-provided cell.
func drop() -> void:
	if sprite == null or sprite.texture == null: return
	_finish_drop()
	_drop_remaining = DROP_INTERVAL
	_drop_speed = DROP_SPEED
	set_process(true)

func _process(delta: float) -> void:
	if _drop_remaining <= 0: return
	# Original Visual updates velocity before position. The shadow follows 20%
	# of the rise: ItemSprite subtracts 80% through its shadowOffset.
	_drop_speed += DROP_ACCELERATION * delta
	_drop_offset += _drop_speed * delta
	_drop_remaining -= delta
	if _drop_remaining <= 0:
		_finish_drop()
		return
	sprite.position = _rest_sprite + Vector2(0, _drop_offset)
	shadow.position = _rest_shadow + Vector2(0, _drop_offset * 0.2)

func _finish_drop() -> void:
	_drop_remaining = 0.0
	_drop_speed = 0.0
	_drop_offset = 0.0
	set_process(false)
	if sprite != null: sprite.position = _rest_sprite
	if shadow != null: shadow.position = _rest_shadow

func _refresh() -> void:
	var texture := Assets.get_texture(_numeric_id if _numeric_id >= 0 else visual_key)
	sprite.texture = texture
	Glow.apply(sprite, _item)
	shadow.texture = texture
	shadow.visible = show_shadow and texture != null
	if texture == null:
		_finish_drop()
		return
	var size := texture.get_size()
	# ItemSprite.worldToCamera: centered horizontally, raised by 5px;
	# very short artwork is raised further to remain visible.
	var raise := 5.0 + maxf(0.0, 8.0 - size.y)
	_rest_sprite = Vector2(-size.x * 0.5, -size.y - raise)
	shadow.scale = Vector2(1, 0.25)
	_rest_shadow = _rest_sprite + Vector2(0, size.y * 0.75 + 0.5)
	_finish_drop()
