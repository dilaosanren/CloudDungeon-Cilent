# Original WardSprite / EarthGuardianSprite / LotusSprite frames, GPL-3.0-or-later.
class_name WandSummonSprite
extends Node2D
const SHEEP = preload("res://assets/nature/source/sheep.png")
const WARDS = preload("res://assets/wands/source/wards.png")
const GUARDIAN = preload("res://assets/wands/source/guardian.png")
const LOTUS = preload("res://assets/wands/source/lotus.png")
const WARD_FRAMES = [Rect2(0, 0, 9, 10), Rect2(10, 0, 11, 12), Rect2(22, 0, 15, 16),
	Rect2(38, 0, 6, 13), Rect2(45, 0, 6, 15), Rect2(52, 0, 8, 15)]
var actor: WandActor
var body: AnimatedSprite2D
var shadow: Sprite2D
var _tier := -1
var _motion: Tween
var _action_in_progress := false
var _fading_out := false

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shadow = Sprite2D.new()
	shadow.centered = false
	shadow.position = Vector2(-7.2, -1.5)
	shadow.scale = Vector2(1.2, 0.25)
	shadow.modulate = Color(0, 0, 0, 0.6)
	add_child(shadow)
	body = AnimatedSprite2D.new()
	body.centered = false
	add_child(body)
	body.animation_finished.connect(func():
		_action_in_progress = false
		if body.animation != &"die": body.play(&"idle"))
	body.frame_changed.connect(func():
		if body.sprite_frames != null:
			shadow.texture = body.sprite_frames.get_frame_texture(body.animation, body.frame)
			shadow.flip_h = body.flip_h)
	refresh()

func _texture(atlas: Texture2D, region: Rect2) -> AtlasTexture:
	var frame := AtlasTexture.new()
	frame.atlas = atlas
	frame.region = region
	return frame

func refresh() -> void:
	if actor == null or body == null: return
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	if actor.species == "sheep":
		if _tier == 0 and body.sprite_frames != null: return
		_tier = 0
		frames.add_animation(&"idle"); frames.set_animation_speed(&"idle", 8); frames.set_animation_loop(&"idle", true)
		for index in [0,0,0,0,0,0,0,0,0,0,0,0,1,2,3,0]: frames.add_frame(&"idle", _texture(SHEEP, Rect2(index * 16, 0, 16, 15)))
		frames.add_animation(&"die"); frames.add_frame(&"die", _texture(SHEEP, Rect2(0, 0, 16, 15)))
		body.position = Vector2(-8, -13)
	elif actor.species == "guardian":
		var definitions := {"idle": [2, true, [0, 0, 0, 0, 0, 1, 1]], "run": [15, true, [2, 3, 4, 5, 6, 7]], "attack": [12, false, [8, 9, 10]], "die": [5, false, [11, 12, 13, 14, 15, 15]]}
		for name in definitions:
			frames.add_animation(name)
			frames.set_animation_speed(name, definitions[name][0])
			frames.set_animation_loop(name, definitions[name][1])
			for index in definitions[name][2]: frames.add_frame(name, _texture(GUARDIAN, Rect2((index % int(GUARDIAN.get_width() / 12)) * 12, int(index / int(GUARDIAN.get_width() / 12)) * 15, 12, 15)))
		body.position = Vector2(-6, -13)
	else:
		var tier := int(actor.data.get("tier", 1))
		if _tier == tier and body.sprite_frames != null: return
		_tier = tier
		var rect: Rect2 = WARD_FRAMES[tier - 1] if actor.species == "ward" else Rect2(0, 0, 19, 16)
		frames.add_animation(&"idle")
		frames.add_frame(&"idle", _texture(WARDS if actor.species == "ward" else LOTUS, rect))
		body.position = Vector2(-rect.size.x / 2, -rect.size.y / 2) if actor.species == "lotus" or tier <= 3 else Vector2(-rect.size.x / 2, 2 - rect.size.y)
	body.sprite_frames = frames
	body.play(&"idle")
	if actor.species == "sheep": body.frame = randi_range(0, 15)
	shadow.texture = frames.get_frame_texture(&"idle", 0)
	shadow.visible = actor.species != "lotus"

func place(cell: Vector2i) -> void: position = Vector2(cell) * 16 + Vector2(8, 8)

func center_point() -> Vector2:
	var frame := body.sprite_frames.get_frame_texture(body.animation, body.frame)
	return body.to_global(Vector2(frame.get_size()) / 2)

func move_to(cell: Vector2i, duration: float = 0.1) -> void:
	if _motion != null: _motion.kill()
	if body.sprite_frames.has_animation(&"run"): body.play(&"run")
	body.flip_h = Vector2(cell * 16).x + 8 < position.x
	_motion = create_tween()
	_motion.tween_property(self, "position", Vector2(cell * 16) + Vector2(8, 8), duration)
	_motion.tween_callback(func(): body.play(&"idle"))

func attack(target: Vector2) -> void:
	body.flip_h = target.x < global_position.x
	if body.sprite_frames.has_animation(&"attack"):
		_action_in_progress = true
		body.play(&"attack")

func die() -> void:
	if actor != null and actor.species == "sheep":
		hide()
	elif body.sprite_frames.has_animation(&"die"):
		_action_in_progress = true
		body.play(&"die")
		get_tree().create_timer(1.2).timeout.connect(queue_free)
	else:
		_fading_out = true
		var tween := create_tween()
		tween.tween_property(self, "modulate:a", 0, 2)
		tween.tween_callback(queue_free)

func is_presenting_action() -> bool:
	return _action_in_progress or _fading_out or (_motion != null and _motion.is_running())
