# PiranhaSprite.java's unchanged frames, SPD 4.0.2, GPL-3.0-or-later.
extends DungeonHeroSprite
const PIRANHA = preload("res://assets/menu/showcase/piranha.png")

func set_appearance(_hero: String, _tier: int) -> bool:
	if body == null: return true
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_speed(&"idle",8)
	for column in [0,1,2,1]:
		var texture := AtlasTexture.new()
		texture.atlas = PIRANHA
		texture.region = Rect2(column*12,0,12,16)
		frames.add_frame(&"idle",texture)
	body.sprite_frames = frames
	body.position = Vector2(-6,-11.2) # Native 0.2-tile perspective raise.
	body.play(&"idle")
	_sync_shadow()
	shadow.hide()
	return true
