# SPD 4.0.2 CharHealthIndicator / HealthBar, GPL-3.0-or-later.
# PvP exception: the visible opponent's bar is shown even at full health.
extends Node2D

const WIDTH := 8.0 # HeroSprite width (12) * 4/6.
const HEIGHT := 1.0
const COLOR_BG := Color("aa0000")
const COLOR_HP := Color("00ee00")
var health := 0
var max_health := 1
var shielding := 0
var _pixel_width := 0.0

func _ready() -> void:
	# CharHealthIndicator: sprite.x + width/6, sprite.y - 2.
	position = Vector2(HeroAssets.FRAME_SIZE.x / 6.0, -2)
	z_index = 101
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_vitals(hp: int, maximum: int, shield: int) -> void:
	var next_hp := maxi(0, hp)
	var next_max := maxi(1, maximum)
	var next_shield := maxi(0, shield)
	if health == next_hp and max_health == next_max and shielding == next_shield: return
	health = next_hp
	max_health = next_max
	shielding = next_shield
	queue_redraw()

func fractions() -> Vector2:
	var maximum := float(maxi(max_health, health + shielding))
	return Vector2(health / maximum, (health + shielding) / maximum)

func _process(_delta: float) -> void:
	if not is_visible_in_tree(): return
	var transform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var pixels := WIDTH * absf(transform.get_scale().x)
	if not is_equal_approx(pixels, _pixel_width):
		_pixel_width = pixels
		queue_redraw()

func _draw() -> void:
	var levels := fractions()
	# HealthBar rounds filled lengths upward to the nearest screen pixel.
	var transform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var pixels := maxf(1, WIDTH * absf(transform.get_scale().x))
	var shield_width := WIDTH * ceilf(levels.y * pixels) / pixels
	var hp_width := WIDTH * ceilf(levels.x * pixels) / pixels
	draw_rect(Rect2(0, 0, WIDTH, HEIGHT), COLOR_BG)
	draw_rect(Rect2(0, 0, shield_width, HEIGHT), Color.WHITE)
	draw_rect(Rect2(0, 0, hp_width, HEIGHT), COLOR_HP)
