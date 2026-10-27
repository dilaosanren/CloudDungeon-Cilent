# Original MissileSprite angular speeds and Crossbow/returning projectile visuals.
class_name MissileEffects
extends ScrollEffects
func sound(name: String, pitch: float = 1.0) -> void:
	var path := "res://assets/missiles/source/%s.mp3" % name
	if not ResourceLoader.exists(path): super.sound(name, pitch); return
	history.append({"kind": "missile_sound", "sound": name, "pitch": pitch})
	if not sound_enabled or not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var player := AudioStreamPlayer.new(); player.stream = load(path); player.pitch_scale = pitch
	add_child(player); player.finished.connect(player.queue_free); player.play()

func throw_weapon(item: InventoryItem, actor: WandActor, cell: int, callback: Callable, from: int = -1, returning: bool = false, anchors: Dictionary = {}) -> void:
	var start: Vector2 = anchors.get("start", actor_point(actor) if from < 0 else point(from))
	var end: Vector2 = anchors.get("end", endpoint(cell) if from < 0 else point(cell))
	var d := end - start; var left := d.x < 0
	var angle := deg_to_rad(135 - atan2(d.x, d.y) / 3.1415926 * 180)
	if left: angle += PI / 2
	var spin := deg_to_rad(float(MissileRules.profile(item).spin)) * (-1 if left else 1)
	var speed := 720.0 if MissileRules.dart(item) and actor.data.get("crossbow") != null else 240.0
	var flight := {"start": start, "end": end, "age": 0.0, "duration": d.length() / speed,
		"texture": ItemAssets.get_texture(item.visual), "angle": angle, "spin": spin, "flip": left,
		"callback": callback, "cell": cell, "fade_time": world.distance(from, cell) / 20 if returning else 0.0}
	_add_item_flight(flight, item)
	history.append({"kind": "weapon_throw", "type": item.type_id, "start": start, "end": end, "duration": flight.duration, "spin": spin, "flip": left, "speed": speed, "returning": returning})
	if not returning: sound("atk_crossbow", rng.randf_range(0.87, 1.15)) if speed == 720 else sound("miss", 1.5)
