# StatueSprite.java's unchanged 12x15 idle frames, SPD 4.0.2, GPL-3.0-or-later.
extends DungeonHeroSprite
const STATUE = preload("res://assets/menu/showcase/statue.png")

func set_appearance(_hero: String, _tier: int) -> bool:
	if body == null: return true
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle", 2)
	frames.set_animation_loop(&"idle", true)
	for column in [0, 0, 0, 0, 0, 1, 1]:
		var texture := AtlasTexture.new()
		texture.atlas = STATUE
		texture.region = Rect2(column * 12, 0, 12, 15)
		frames.add_frame(&"idle", texture)
	body.sprite_frames = frames
	body.position = Vector2(-6, -13)
	body.play(&"idle")
	_sync_shadow()
	return true
