# HeroSprite / CharSprite visual animation and motion port. GPL-3.0-or-later.
class_name DungeonHeroSprite
extends Node2D

signal action_finished(action: StringName)
signal motion_finished

const TILE_SIZE := 16
const DEFAULT_MOVE_INTERVAL := 0.1
const JUMP_DURATION_PER_CELL := 0.1
const JUMP_HEIGHT_PER_CELL := 2.0
const PUSH_DURATION := 0.15 # Pushing.Effect.DELAY, independent of distance.
const BODY_POSITION := Vector2(-6, -13) # CharSprite: tile bottom - 6px perspective raise.
const SHADOW_POSITION := Vector2(-7.2, -1.5)
const FLASH_INTERVAL := 0.05 # CharSprite.FLASH_INTERVAL.
const FLASH_SHADER = preload("res://scripts/heroes/hero_flash.gdshader")
const HealthIndicator = preload("res://scripts/status/character_health_indicator.gd")
const FOOTSTEPS := {
	"step": preload("res://assets/heroes/source/step.mp3"),
	"water": preload("res://assets/heroes/source/water.mp3"),
	"grass": preload("res://assets/heroes/source/grass.mp3"),
	"trample": preload("res://assets/heroes/source/trample.mp3"),
	"sturdy": preload("res://assets/heroes/source/sturdy.mp3"),
}

@export_enum("warrior", "mage", "rogue", "huntress", "duelist", "cleric") var hero_class: String = "warrior"
@export_range(0, 6) var armor_tier: int = 0
var body: AnimatedSprite2D
var shadow: Sprite2D
var cell := Vector2i.ZERO
var moving := false
var flying := false
var sprint_speed := 1.0
var _motion_elapsed := 0.0
var _motion_duration := 0.1
var _start := Vector2.ZERO
var _destination := Vector2.ZERO
var _destination_cell := Vector2i.ZERO
var _jump_height := 0.0
var _jumping := false
var _stepping := false
var _pushing := false
var _action_in_progress := false
var _death_pending := false
var _footsteps: Dictionary = {}
var _flash_overlay: Sprite2D
var _flash_time := 0.0
var _flash_body_color := Color.WHITE
var _local_player_marker: Sprite2D
var opponent_health: HealthIndicator
## Optional explicit world layer; otherwise one is created lazily on the map.
var combat_text_layer: CombatTextLayer

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow = Sprite2D.new()
	shadow.name = "Shadow"
	shadow.centered = false
	shadow.position = SHADOW_POSITION
	shadow.scale = Vector2(1.2, 0.25)
	shadow.modulate = Color(0, 0, 0, 0.6)
	add_child(shadow)
	body = AnimatedSprite2D.new()
	body.name = "Body"
	body.centered = false
	body.position = BODY_POSITION
	add_child(body)
	body.frame_changed.connect(_sync_shadow)
	body.animation_finished.connect(_animation_finished)
	set_appearance(hero_class, armor_tier)
	play_action("idle")

func set_appearance(hero: String, tier: int) -> bool:
	var frames := HeroAssets.sprite_frames(hero, tier)
	if frames == null: return false
	hero_class = hero
	armor_tier = tier
	if body == null: return true
	var action := body.animation if body.sprite_frames != null else &"idle"
	var current_frame := body.frame
	var playing := body.is_playing()
	body.sprite_frames = frames
	if not frames.has_animation(action): action = &"idle"
	body.play(action)
	body.frame = mini(current_frame, frames.get_frame_count(action) - 1)
	if not playing: body.pause()
	_sync_shadow()
	return true

func place_cell(at: Vector2i) -> void:
	_cancel_motion()
	_footsteps.clear()
	cell = at
	position = cell_position(at)
	if _death_pending: play_action(&"die")

static func cell_position(at: Vector2i) -> Vector2:
	return Vector2(at * TILE_SIZE) + Vector2(8, 8)

func face_left(value: bool) -> void:
	if body == null: return
	body.flip_h = value
	_sync_shadow()

func face_cell(target: Vector2i) -> void:
	if target.x != cell.x: face_left(target.x < cell.x)

## Client-only ownership marker; attach to the body so jumps carry it too.
func set_local_player_marker(value: bool) -> void:
	if body == null: return
	if value and _local_player_marker == null:
		var arrow := AtlasTexture.new()
		arrow.atlas = preload("res://assets/ui/source/icons.png")
		arrow.region = Rect2(128, 32, 11, 11) # Icons.ARROW, originally pointing right.
		_local_player_marker = Sprite2D.new()
		_local_player_marker.name = "LocalPlayerMarker"
		_local_player_marker.texture = arrow
		_local_player_marker.rotation = PI / 2
		_local_player_marker.scale = Vector2.ONE * (7.0 / 11.0)
		_local_player_marker.position = Vector2(6, -5)
		var marker_material := ShaderMaterial.new()
		marker_material.shader = preload("res://scripts/heroes/local_player_marker.gdshader")
		_local_player_marker.material = marker_material
		_local_player_marker.z_index = 101 # Keep the owner's marker above grass and fog.
		body.add_child(_local_player_marker)
	if _local_player_marker != null: _local_player_marker.visible = value

## CharSprite.showStatusWithIcon: anchor at the sprite top; walking uses its destination.
func show_status_with_icon(color: Color, text: String, icon: int = CombatTextAssets.Icon.NO_ICON,
		buff_name: bool = false) -> CombatFloatingText:
	if body == null or not is_inside_tree() or not is_visible_in_tree() or not body.is_visible_in_tree(): return null
	if not is_instance_valid(combat_text_layer): combat_text_layer = CombatTextLayer.for_actor(self)
	if combat_text_layer == null: return null
	var anchor := to_global(Vector2(0, body.position.y))
	if moving and _jump_height == 0:
		var parent_item := get_parent() as CanvasItem
		var parent_transform := parent_item.get_global_transform() if parent_item != null else Transform2D.IDENTITY
		anchor = parent_transform * (_destination + Vector2(0, BODY_POSITION.y))
	anchor = combat_text_layer.to_local(anchor)
	var key := Vector2i(((anchor + Vector2(0, HeroAssets.FRAME_SIZE.y)) / TILE_SIZE).floor())
	return combat_text_layer.show_status(anchor, text, color, icon, key, true, buff_name)

func show_status(color: Color, text: String) -> CombatFloatingText:
	return show_status_with_icon(color, text)

func set_opponent_vitals(enabled: bool, hp: int, maximum: int, shield: int) -> void:
	if body == null: return
	if opponent_health == null and enabled:
		opponent_health = HealthIndicator.new()
		opponent_health.name = "OpponentHealth"
		body.add_child(opponent_health)
	if opponent_health != null:
		opponent_health.set_vitals(hp, maximum, shield)
		opponent_health.visible = enabled and hp > 0

## amount is the resolved HP + absorbed shield damage, matching Char.damage's popup value.
func show_damage(amount: int, kind: int = CombatTextAssets.Icon.PHYS_DMG,
		hit_reason: int = CombatTextAssets.Icon.NO_ICON) -> CombatFloatingText:
	return show_status_with_icon(CombatTextAssets.damage_color(), str(maxi(0, amount)), CombatTextAssets.damage_icon(kind, hit_reason))

func show_dodge(reason_icon: int = CombatTextAssets.Icon.NO_ICON) -> CombatFloatingText:
	return show_status_with_icon(Color.YELLOW, CombatTextAssets.defense_word("dodge"), reason_icon)

func show_block(reason_icon: int = CombatTextAssets.Icon.NO_ICON) -> CombatFloatingText:
	return show_status_with_icon(Color.YELLOW, CombatTextAssets.defense_word("block"), reason_icon)

func show_parry() -> CombatFloatingText:
	return show_status(Color.YELLOW, CombatTextAssets.defense_word("parry"))

func show_healing(amount: int) -> CombatFloatingText:
	return show_status_with_icon(Color.GREEN, str(maxi(0, amount)), CombatTextAssets.Icon.HEALING)

func show_shielding(amount: int) -> CombatFloatingText:
	return show_status_with_icon(Color.GREEN, str(maxi(0, amount)), CombatTextAssets.Icon.SHIELDING)

## Separate overlay preserves frost materials and inherits the body's invisibility.
func flash() -> void:
	if body == null or not is_visible_in_tree(): return
	if _flash_overlay == null:
		_flash_overlay = Sprite2D.new()
		_flash_overlay.name = "HitFlash"
		_flash_overlay.centered = false
		var material := ShaderMaterial.new()
		material.shader = FLASH_SHADER
		_flash_overlay.material = material
		body.add_child(_flash_overlay)
	if _flash_time <= 0: _flash_body_color = body.self_modulate
	_flash_overlay.self_modulate = _flash_body_color
	# Draw only the white silhouette, without doubling translucent pixels.
	body.self_modulate.a = 0.0
	_flash_time = FLASH_INTERVAL
	_sync_shadow()
	_flash_overlay.show()

func play_action(action: StringName) -> bool:
	if body == null or not body.sprite_frames.has_animation(action): return false
	if action == &"die" and moving:
		_death_pending = true
		return true
	if moving and _stepping: return false
	_cancel_motion()
	_footsteps.clear()
	if action == &"idle" or action == &"die": flying = false
	elif action == &"fly": flying = true
	_play(action)
	return true

func _play(action: StringName) -> void:
	if action == &"die": _death_pending = false
	_action_in_progress = not body.sprite_frames.get_animation_loop(action)
	body.stop()
	body.speed_scale = sprint_speed if action == &"run" else 1.0
	body.play(action)
	_sync_shadow()

func set_flying(value: bool) -> void:
	flying = value
	if body != null: _play(&"fly" if value else &"idle")

func sprint(speed: float) -> void:
	sprint_speed = maxf(0.01, speed)
	if body != null and body.animation == &"run": body.speed_scale = sprint_speed

## PvP movement: exactly one neighbouring cell, using HeroicLeap's fly pose.
## The host checks terrain/occupancy; the settled cell changes only on landing.
func move_to_cell(target: Vector2i) -> bool:
	if body == null or moving or body.animation == &"die": return false
	var difference := target - cell
	if difference == Vector2i.ZERO or absi(difference.x) > 1 or absi(difference.y) > 1: return false
	# HeroicLeap calls CharSprite.jump(from, to, callback) without overrides.
	jump_to_cell(target)
	_stepping = true
	return true

## Original walking retained for source animation previews / scripted motion.
func walk_to_cell(target: Vector2i, duration: float = DEFAULT_MOVE_INTERVAL) -> void:
	if moving and _stepping: return
	_begin_motion(target, duration, 0)

func jump_to_cell(target: Vector2i, height: float = -1, duration: float = -1) -> void:
	if moving and _stepping: return
	var distance := maxf(1, Vector2(cell).distance_to(Vector2(target)))
	_begin_motion(target, distance * JUMP_DURATION_PER_CELL if duration < 0 else duration, distance * JUMP_HEIGHT_PER_CELL if height < 0 else height, true)

## Pushing.Effect: slide with constant deceleration, preserving pose/facing.
## Forced motion can interrupt a step, but never produces footsteps or ripples.
func push_to_cell(target: Vector2i) -> bool:
	if body == null: return false
	var was_moving := moving
	_cancel_motion()
	_footsteps.clear()
	_start = position
	_destination = cell_position(target)
	_destination_cell = target
	if _start.is_equal_approx(_destination):
		cell = target
		return false
	_motion_duration = PUSH_DURATION
	_motion_elapsed = 0
	_pushing = true
	moving = true
	if was_moving: _play(&"fly" if flying else &"idle")
	return true

func _begin_motion(target: Vector2i, duration: float, height: float, jumping: bool = false) -> void:
	if body == null: return
	_cancel_motion()
	# CharSprite.move ripples at departure; CharSprite.jump ripples on landing.
	if not jumping: _water_ripple(cell)
	face_cell(target)
	_start = position
	_destination = cell_position(target)
	_destination_cell = target
	_motion_duration = maxf(0.001, duration)
	_motion_elapsed = 0
	_jump_height = maxf(0, height)
	_jumping = jumping
	moving = true
	_play(&"fly" if flying or height > 0 else &"run")

func _cancel_motion() -> void:
	if moving: cell = Vector2i((position / TILE_SIZE).floor())
	moving = false
	_stepping = false
	_pushing = false
	_jump_height = 0
	_jumping = false
	if body != null: body.position = BODY_POSITION
	if shadow != null: shadow.position = SHADOW_POSITION

func _process(delta: float) -> void:
	if _flash_time > 0:
		_flash_time = maxf(0, _flash_time - delta)
		if _flash_time <= 0:
			_flash_overlay.hide()
			body.self_modulate = _flash_body_color
	if not moving: return
	_motion_elapsed += delta
	# Tweener.update finishes early when another frame would overshoot by
	# more than half a frame. Preserve the source timing at actual frame rates.
	if _motion_duration - _motion_elapsed < delta / 2:
		_motion_elapsed = _motion_duration
	var progress := minf(1, _motion_elapsed / _motion_duration)
	var travel := 1.0 - (1.0 - progress) * (1.0 - progress) if _pushing else progress
	position = _start.lerp(_destination, travel)
	var height := _jump_height * 4 * progress * (1 - progress)
	body.position = BODY_POSITION - Vector2(0, height)
	# Upstream shadowOffset follows 80% of the jump displacement.
	shadow.position = SHADOW_POSITION - Vector2(0, height * 0.2)
	if progress >= 1:
		cell = _destination_cell
		var landed_from_jump := _jumping
		var landed_from_push := _pushing
		_cancel_motion()
		if not landed_from_push: _play(&"fly" if flying else &"idle")
		if landed_from_jump: _water_ripple(cell)
		if not landed_from_push: _play_footstep(cell)
		motion_finished.emit()
		if _death_pending and not moving:
			_death_pending = false
			play_action(&"die")

## Looping idle/fly poses never hold the match result open.
func is_presenting_action() -> bool:
	return moving or _death_pending or _action_in_progress or _flash_time > 0

## The authority selects the surface. Queue audio until the matching landing,
## including a later destination received while the previous step is animating.
func queue_footstep(sound_name: String, at: Vector2i) -> void:
	if not FOOTSTEPS.has(sound_name) or not is_visible_in_tree(): return
	if not moving and cell != at: return
	_footsteps[at] = sound_name
	if not moving and cell == at: _play_footstep(at)

func _play_footstep(at: Vector2i) -> void:
	var sound_name := str(_footsteps.get(at, ""))
	_footsteps.erase(at)
	if sound_name.is_empty() or not is_visible_in_tree() or DisplayServer.get_name() == "headless": return
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = FOOTSTEPS[sound_name]
	# Hero.move's pitch variation is cosmetic and never advances the rules RNG.
	player.pitch_scale = randf_range(0.8, 1.25) if sound_name == "water" else randf_range(0.96, 1.05)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _water_ripple(at: Vector2i) -> void:
	if flying or not is_visible_in_tree(): return
	var map_node := get_parent()
	while map_node != null:
		if map_node.has_method("ripple_at"):
			map_node.ripple_at(at)
			return
		map_node = map_node.get_parent()

func _sync_shadow() -> void:
	if body == null or body.sprite_frames == null: return
	if not body.sprite_frames.has_animation(body.animation): return
	shadow.texture = body.sprite_frames.get_frame_texture(body.animation, body.frame)
	shadow.flip_h = body.flip_h
	if _flash_overlay != null:
		_flash_overlay.texture = shadow.texture
		_flash_overlay.flip_h = body.flip_h

func _animation_finished() -> void:
	var action := body.animation
	_action_in_progress = false
	# Death holds its final frame; other one-shot actions return to rest.
	if action != &"die": _play(&"fly" if flying else &"idle")
	action_finished.emit(action)
