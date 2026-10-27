# MirrorSprite frames and MobSprite's 3-second fade; never a hero corpse.
class_name ScrollMirrorSprite
extends DungeonHeroSprite
var actor: WandActor
const FADE_TIME := 3.0
var _dying := false
var _fading_out := false

func _ready() -> void:
	if actor != null:
		hero_class = actor.data.hero_class
		armor_tier = actor.data.armor_tier
	super._ready()

func set_appearance(hero: String, tier: int) -> bool:
	if HeroAssets.sprite_frames(hero, tier) == null: return false
	hero_class = hero
	armor_tier = tier
	if body == null: return true
	var action := body.animation if body.sprite_frames != null else &"idle"
	var current_frame := body.frame
	var frames := SpriteFrames.new(); frames.remove_animation("default")
	for spec in [["idle", 1, true, [0, 0, 0, 1, 0, 0, 1, 1]], ["run", 20, true, [2, 3, 4, 5, 6, 7]], ["attack", 15, false, [13, 14, 15, 0]], ["die", 20, false, [0]]]:
		frames.add_animation(spec[0]); frames.set_animation_speed(spec[0], spec[1]); frames.set_animation_loop(spec[0], spec[2])
		for column in spec[3]: frames.add_frame(spec[0], HeroAssets.frame_texture(hero_class, armor_tier, column))
	body.sprite_frames = frames
	if not frames.has_animation(action): action = &"idle"
	body.play(action)
	body.frame = mini(current_frame, frames.get_frame_count(action) - 1)
	_sync_shadow()
	return true

func move_to_cell(target: Vector2i) -> bool:
	if _dying or moving: return false
	var delta := target - cell
	if delta == Vector2i.ZERO or absi(delta.x) > 1 or absi(delta.y) > 1: return false
	walk_to_cell(target)
	return true

func play_action(action: StringName) -> bool:
	if _dying: return action == &"die"
	var accepted := super.play_action(action)
	if accepted and action == &"die" and not moving: _dying = true
	return accepted

func _play(action: StringName) -> void:
	# MirrorSprite uses its standing/running frames even while levitating.
	super._play((&"run" if moving else &"idle") if action == &"fly" else action)

func _animation_finished() -> void:
	var action := body.animation
	_action_in_progress = false
	if action == &"die":
		if not _fading_out:
			_fading_out = true
			var tween := create_tween()
			tween.tween_property(self, "modulate:a", 0.0, FADE_TIME)
			tween.tween_callback(queue_free)
	else: body.play(&"idle")
	action_finished.emit(action)

func is_presenting_action() -> bool:
	return super.is_presenting_action() or _fading_out
