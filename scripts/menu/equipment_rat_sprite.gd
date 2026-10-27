# RatSprite.java's unchanged 16x15 frames, SPD 4.0.2, GPL-3.0-or-later.
# Inherit the existing shadow, hit flash and floating combat text presentation.
extends DungeonHeroSprite
const RAT = preload("res://assets/menu/showcase/rat.png")

func set_appearance(_hero: String, _tier: int) -> bool:
	if body == null: return true
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for spec in [["idle", 2, true, [0, 0, 0, 1]], ["attack", 15, false, [2, 3, 4, 5, 0]]]:
		frames.add_animation(spec[0])
		frames.set_animation_speed(spec[0], spec[1])
		frames.set_animation_loop(spec[0], spec[2])
		for column in spec[3]:
			var texture := AtlasTexture.new()
			texture.atlas = RAT
			texture.region = Rect2(column * 16, 0, 16, 15)
			frames.add_frame(spec[0], texture)
	body.sprite_frames = frames
	body.position = Vector2(-8, -13)
	body.play(&"idle")
	_sync_shadow()
	return true
