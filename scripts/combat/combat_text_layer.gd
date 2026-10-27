# GameScene.statuses and FloatingText per-cell stack. GPL-3.0-or-later.
class_name CombatTextLayer
extends Node2D

const STACK_GAP := 4.0
var _stacks: Dictionary = {}
var _active: Array[CombatFloatingText] = []

func _ready() -> void:
	# Like GameScene.statuses, text is above world geometry and below CanvasLayer UI.
	z_index = 100
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## A separate layer per world keeps text independent of actor movement/death and of other maps.
static func for_actor(actor: Node2D) -> CombatTextLayer:
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return null
	var world: Node = actor.get_parent()
	var ancestor: Node = world
	while ancestor != null:
		if ancestor is DungeonMap:
			world = ancestor
			break
		ancestor = ancestor.get_parent()
	if world == null: return null
	var existing := world.get_node_or_null("CombatText")
	if existing is CombatTextLayer: return existing
	var layer := CombatTextLayer.new()
	layer.name = "CombatText"
	world.add_child(layer)
	return layer

## Anchor is in this layer's local map pixels, usually the top of the target sprite.
func show_status(anchor: Vector2, text: String, color: Color, icon: int = CombatTextAssets.Icon.NO_ICON,
		key: Variant = null, left: bool = true, buff_name: bool = false) -> CombatFloatingText:
	if text.is_empty(): return null
	var popup := CombatFloatingText.new()
	add_child(popup)
	# Include the window stretch (e.g. a 1080px phone displaying a 360px logical viewport).
	var display_transform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var zoom := absf(display_transform.get_scale().y)
	popup.reset(anchor, text, color, icon, zoom, left)
	popup.stack_key = key
	popup.is_buff_name = buff_name
	popup.expired.connect(_remove)
	popup.tree_exiting.connect(_remove.bind(popup))
	_active.append(popup)
	if key != null: _push(popup, key)
	_separate_texts()
	return popup

## Keep the source per-cell stacking and also resolve visual intersections
## across nearby cells. Long buff names can extend into another actor's damage.
func source_stack_pair(older: CombatFloatingText, newer: CombatFloatingText) -> bool:
	return older.stack_key != null and older.stack_key == newer.stack_key

func _separate_texts() -> void:
	var texts := active_texts()
	for index in range(texts.size() - 2, -1, -1):
		var older := texts[index]
		# Newer rows are already settled; moving above one may meet another.
		for attempt in texts.size():
			var moved := false
			for newer_index in range(index + 1, texts.size()):
				var newer := texts[newer_index]
				var same_stack := source_stack_pair(older, newer)
				# FloatingText.push measures every same-cell row by logical height
				# plus 4px, including damage/icons and mixed status messages.
				# Full font bounds here would enlarge the gap a second time.
				var a := Rect2(older.position, older.logical_size) if same_stack else older.collision_rect()
				var b := Rect2(newer.position, newer.logical_size) if same_stack else newer.collision_rect()
				if same_stack:
					# A neighboring actor can push a newer row up first. Keep older
					# rows above it in source order, regardless of message type.
					if a.end.y + STACK_GAP <= b.position.y: continue
				else:
					if a.end.x <= b.position.x or a.position.x >= b.end.x: continue
					if a.end.y + STACK_GAP <= b.position.y or a.position.y >= b.end.y + STACK_GAP: continue
				older.position.y -= a.end.y - b.position.y + STACK_GAP
				older.time_left = minf(older.time_left, CombatFloatingText.LIFESPAN - 0.2)
				moved = true
			if not moved: break

func show_damage(anchor: Vector2, amount: int, kind: int = CombatTextAssets.Icon.PHYS_DMG,
		key: Variant = null, hit_reason: int = CombatTextAssets.Icon.NO_ICON) -> CombatFloatingText:
	return show_status(anchor, str(maxi(0, amount)), CombatTextAssets.damage_color(),
		CombatTextAssets.damage_icon(kind, hit_reason), key)

func _push(popup: CombatFloatingText, key: Variant) -> void:
	if not _stacks.has(key): _stacks[key] = []
	var stack: Array = _stacks[key]
	var below := popup
	var number_below := 0
	for i in range(stack.size() - 1, -1, -1):
		var above: CombatFloatingText = stack[i]
		if not is_instance_valid(above) or above.is_queued_for_deletion(): continue
		number_below += 1
		if above.position.y + above.logical_size.y + STACK_GAP <= below.position.y: break
		above.position.y = below.position.y - above.logical_size.y - STACK_GAP
		above.time_left = maxf(0, minf(above.time_left, CombatFloatingText.LIFESPAN - number_below / 5.0))
		below = above
	stack.append(popup)

func _remove(popup: CombatFloatingText) -> void:
	_active.erase(popup)
	if popup.stack_key != null and _stacks.has(popup.stack_key):
		var stack: Array = _stacks[popup.stack_key]
		stack.erase(popup)
		if stack.is_empty(): _stacks.erase(popup.stack_key)

func active_texts() -> Array[CombatFloatingText]:
	var result: Array[CombatFloatingText] = []
	for popup in _active:
		if is_instance_valid(popup) and not popup.is_queued_for_deletion(): result.append(popup)
	return result

func clear() -> void:
	for popup in active_texts(): popup.queue_free()
	_active.clear()
	_stacks.clear()
