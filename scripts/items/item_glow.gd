# ItemSprite.Glowing / ItemSprite.update, SPD 4.0.2. GPL-3.0-or-later.
# Cosmetic only: no rules RNG, changes to equipment or authority calculations.
class_name ItemGlow
extends Node

const SHADER = preload("res://scripts/items/item_glow.gdshader")
static var _gear: Dictionary = {}
var _target: CanvasItem
var _material: ShaderMaterial
var _color := Color.WHITE
var _period := 1.0
var _phase := 0.0
var _up := false

static func profile(item: InventoryItem) -> Dictionary:
	if item == null or item.category not in ["weapon", "missile", "armor"]: return {}
	var field := "glyph" if item.category == "armor" else "enchantment"
	var key := str(item.metadata.get(field, ""))
	if key.is_empty(): return {}
	# All PvP items are identified; original known curses pulse black.
	if item.metadata.get(field + "_curse", false): return {"color":"#000000", "period":1.0}
	if _gear.is_empty(): _gear = JSON.parse_string(FileAccess.get_file_as_string("res://assets/nature/source_catalog.json")).gear
	var result: Dictionary = _gear["armor" if item.category == "armor" else "weapon"].get(key, {}).get("glow", {}).duplicate()
	# Crystal's thrown-weapon glow always uses the undamaged period.
	if key == "crystal" and item.category == "weapon":
		var uses_left := int(item.metadata.get("crystal_uses_left", 5))
		result.period = 1.0 if uses_left > 2 else 0.5 if uses_left > 1 else 0.25
	return result

static func apply(target: CanvasItem, item: InventoryItem) -> void:
	var settings := profile(item)
	var effect := target.get_node_or_null("ItemGlow") as ItemGlow
	if settings.is_empty():
		if effect != null:
			target.material = null
			target.remove_child(effect)
			effect.queue_free()
		return
	if effect == null:
		effect = ItemGlow.new()
		effect.name = "ItemGlow"
		effect._target = target
		effect._material = ShaderMaterial.new()
		effect._material.shader = SHADER
		target.material = effect._material
		target.add_child(effect)
	effect._color = Color(str(settings.color))
	effect._period = maxf(0.01, float(settings.period))
	effect._material.set_shader_parameter("glow_color", Vector3(effect._color.r, effect._color.g, effect._color.b))

func _process(delta: float) -> void:
	if not is_instance_valid(_target) or not _target.is_visible_in_tree(): return
	# Match the original triangular pulse, including clamped end frames.
	_phase += delta if _up else -delta
	if _up and _phase > _period:
		_up = false
		_phase = _period
	elif not _up and _phase < 0:
		_up = true
		_phase = 0
	_material.set_shader_parameter("glow_strength", _phase / _period * 0.6)
