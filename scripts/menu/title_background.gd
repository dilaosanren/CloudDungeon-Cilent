# Port of SPD TitleBackground.java: seven rising layers and weighted artwork.
# GPL-3.0-or-later; see THIRD_PARTY.md.
class_name DungeonTitleBackground
extends Control

const SCROLL_SPEED := 15.0
const LAYERS := [
	{"sheet": "arch", "speed": 1.0},
	{"sheet": "cluster", "speed": 1.33, "scale_min": 0.5, "scale_max": 0.5, "brightness": 0.5, "spacing": 0.5, "padding": 300},
	{"sheet": "cluster", "speed": 1.33 * 1.5, "scale_min": 1.0, "scale_max": 1.0, "brightness": 0.75, "spacing": 0.5, "padding": 300},
	{"sheet": "small", "speed": 1.33 * 1.5 * 1.33, "scale_min": 0.75, "scale_max": 1.25, "brightness": 0.8, "spacing": 1.0, "padding": 150},
	{"sheet": "mid", "speed": 1.33 * 1.5 * 1.33 * 1.33, "scale_min": 0.75, "scale_max": 1.25, "brightness": 0.9, "spacing": 0.75, "padding": 300},
	{"sheet": "mid", "speed": 1.33 * 1.5 * 1.33 * 1.33 * 1.33, "scale_min": 1.25, "scale_max": 1.75, "brightness": 1.0, "spacing": 0.75, "padding": 300},
	{"sheet": "small", "speed": 1.33 * 1.5 * 1.33 * 1.33 * 1.33 * 1.33, "scale_min": 2.0, "scale_max": 2.5, "brightness": 1.0, "spacing": 1.0, "padding": 150},
]
var layer_nodes: Array[Node2D] = []
var objects: Array[Array] = []
var density := 1.0
var _weights: Dictionary = {}
var _recent: Dictionary = {"mid": [], "small": []}
var _rng := RandomNumberGenerator.new()
var _old_size := Vector2.ZERO
var _darkness: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	for i in LAYERS.size():
		var layer := Node2D.new()
		layer.name = ["Arches", "FarClusters", "Clusters", "FarSmall", "MidMixed1", "MidMixed2", "FrontSmall"][i]
		add_child(layer)
		layer_nodes.append(layer)
		objects.append([])
		if i == 0: _build_darkness()
	resized.connect(_resize_objects)
	_resize_objects()

func _build_darkness() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, 0.2, 0.4, 0.6, 0.8, 1])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 17.0/255), Color(0, 0, 0, 34.0/255), Color(0, 0, 0, 51.0/255), Color(0, 0, 0, 68.0/255), Color(0, 0, 0, 136.0/255)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1
	texture.height = 512
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2(0, 1)
	_darkness = TextureRect.new()
	_darkness.name = "ArchDarkness"
	_darkness.texture = texture
	_darkness.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_darkness)

func _base_scale(dimensions: Vector2) -> float:
	return dimensions.y / 450.0

func _floating_scale(dimensions: Vector2) -> float:
	return _base_scale(dimensions) / (1.5 if dimensions.x <= dimensions.y else 1.0)

func _resize_objects() -> void:
	if not is_node_ready() or size.x <= 0 or size.y <= 0: return
	_darkness.size = size
	var orientation_changed := (_old_size.x > _old_size.y) != (size.x > size.y)
	if _old_size != Vector2.ZERO and not orientation_changed:
		for layer_index in objects.size():
			var factor := _base_scale(size) / _base_scale(_old_size)
			var width_factor := size.x / _old_size.x
			for sprite: Sprite2D in objects[layer_index]:
				sprite.scale *= factor
				sprite.position *= factor
				if layer_index > 0 and sprite.position.x > 0:
					sprite.position.x *= width_factor / factor
			# Source convertArchLayer fills newly exposed portions of each arch row.
			if layer_index == 0:
				var row_ends: Dictionary = {}
				for arch: Sprite2D in objects[0]:
					if not row_ends.has(arch.position.y) or row_ends[arch.position.y].position.x < arch.position.x:
						row_ends[arch.position.y] = arch
				for row_y in row_ends:
					var arch: Sprite2D = row_ends[row_y]
					while arch.position.x + _dimensions(arch).x < size.x:
						var extra := _new_sprite(0, _base_scale(size))
						extra.position = Vector2(arch.position.x + _dimensions(arch).x - 9 * arch.scale.x, arch.position.y)
						arch = extra
	else:
		for entries in objects:
			for sprite: Sprite2D in entries:
				sprite.get_parent().remove_child(sprite)
				sprite.queue_free()
			entries.clear()
	density = (size.x / (800.0 * _floating_scale(size)) + 0.5) / 1.5
	_old_size = size
	advance(0)

func reset_with_seed(value: int) -> void:
	for entries in objects:
		for sprite: Sprite2D in entries:
			sprite.get_parent().remove_child(sprite)
			sprite.queue_free()
		entries.clear()
	_weights.clear()
	_recent = {"mid": [], "small": []}
	_rng.seed = value
	advance(0)

func _pick(sheet: String) -> int:
	var initial: Array = MenuAssets.catalog().sheets[sheet].weights
	if not _weights.has(sheet): _weights[sheet] = initial.duplicate()
	while true:
		var remaining: Array = _weights[sheet]
		var total := 0.0
		for weight in remaining: total += weight
		if total <= 0:
			_weights[sheet] = initial.duplicate()
			continue
		var roll := _rng.randf_range(0, total)
		var index := remaining.size() - 1
		for i in remaining.size():
			roll -= remaining[i]
			if roll < 0:
				index = i
				break
		if _recent.has(sheet) and _recent[sheet].has(index): continue
		remaining[index] -= 1
		if _recent.has(sheet):
			_recent[sheet].push_front(index)
			if _recent[sheet].size() >= (20 if sheet == "mid" else 15): _recent[sheet].pop_back()
		return index
	return 0

func _new_sprite(layer: int, factor: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false # Noosa Image rotates about the top-left origin.
	sprite.texture = MenuAssets.frame_texture(LAYERS[layer].sheet, _pick(LAYERS[layer].sheet))
	sprite.scale = Vector2.ONE * factor
	var brightness: float = LAYERS[layer].get("brightness", 1.0)
	sprite.modulate = Color(brightness, brightness, brightness)
	layer_nodes[layer].add_child(sprite)
	objects[layer].append(sprite)
	return sprite

func _dimensions(sprite: Sprite2D) -> Vector2:
	return sprite.texture.get_size() * sprite.scale

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if size.y <= 0 or layer_nodes.is_empty(): return
	var base := _base_scale(size)
	var shift := delta * SCROLL_SPEED * _floating_scale(size)
	_update_arches(base, shift)
	var floating := _floating_scale(size)
	for i in range(1, LAYERS.size()): _update_floating(i, floating, shift * LAYERS[i].speed)

func _update_arches(factor: float, shift: float) -> void:
	var bottom := 0.0
	var recycled: Array[Sprite2D] = []
	for arch: Sprite2D in objects[0]:
		arch.position.y -= shift
		var end := arch.position.y + _dimensions(arch).y
		if end < 0: recycled.append(arch)
		else: bottom = maxf(bottom, end)
	if not recycled.is_empty():
		for arch in recycled:
			arch.texture = MenuAssets.frame_texture("arch", _pick("arch"))
			arch.position.y = bottom - 5 * factor
		bottom += 100 * factor
	while bottom < size.y:
		var left := -5 + (-33.334 * _rng.randi_range(1, 9) * factor)
		while left < size.x:
			var arch := _new_sprite(0, factor)
			arch.position = Vector2(left, bottom - 5 * factor)
			left += _dimensions(arch).x - 9 * factor
		bottom += 100 * factor

func _update_floating(layer: int, factor: float, shift: float) -> void:
	var bottom := 0.0
	var last_x := 0.0
	var recycled: Array[Sprite2D] = []
	for sprite: Sprite2D in objects[layer]:
		sprite.position.y -= shift
		var end := sprite.position.y + _dimensions(sprite).y
		if end < -20: recycled.append(sprite)
		elif end > bottom:
			bottom = end
			last_x = sprite.position.x
	for sprite in recycled:
		sprite.texture = MenuAssets.frame_texture(LAYERS[layer].sheet, _pick(LAYERS[layer].sheet))
		_place_floating(sprite, layer, factor, bottom, last_x, true)
		bottom = sprite.position.y + _dimensions(sprite).y
		last_x = sprite.position.x
	var padding: float = LAYERS[layer].padding
	padding -= padding / 2 / density
	while bottom < size.y + padding:
		var sprite := _new_sprite(layer, factor)
		_place_floating(sprite, layer, factor, bottom, last_x, false)
		bottom = sprite.position.y + _dimensions(sprite).y
		last_x = sprite.position.x

func _place_floating(sprite: Sprite2D, layer: int, factor: float, bottom: float, last_x: float, recycled: bool) -> void:
	var definition: Dictionary = LAYERS[layer]
	# Clusters retain their scale when recycled; other foregrounds reroll it.
	if not recycled or layer > 2:
		sprite.scale = Vector2.ONE * factor * _rng.randf_range(definition.scale_min, definition.scale_max)
	var dimensions := _dimensions(sprite)
	var flex := 0.0
	while true:
		sprite.position.x = _rng.randf_range(dimensions.x / 3, size.x - 4 * dimensions.x / 3) if layer == 3 else _rng.randf_range(-dimensions.x / 3, size.x - 2 * dimensions.x / 3)
		flex += 1
		if absf(sprite.position.x - last_x) >= density * (dimensions.x * definition.spacing - flex): break
	var minimum := dimensions.y * (0.75 if recycled and layer == 4 else 0.5)
	sprite.position.y = bottom - dimensions.y / (2 if layer == 3 else 1) + _rng.randf_range(minimum, dimensions.y) / density
	sprite.rotation_degrees = _rng.randf_range(-20, 20)
