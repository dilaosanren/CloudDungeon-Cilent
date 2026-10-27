# Real Barkskin mitigation / decay and PotionOfCleansing drink + thrown use.
extends "res://scripts/menu/restorative_potion_sandbox.gd"

class ProtectiveEffects extends LocalEffects:
	const BUFFS = preload("res://assets/ui/source/buffs.png")
	const Info = preload("res://scripts/status/buff_descriptions.gd")
	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			var at := actor_point(actor)+Vector2(-7,-14)
			for effect in ["poison","burning","cripple"]:
				if not actor.has_status(effect): continue
				var id := StatusAssets.icon_id(str(Info.definitions()[effect].icon))
				var columns := floori(BUFFS.get_width()/7.0)
				draw_texture_rect_region(BUFFS,Rect2(at,Vector2(7,7)),Rect2((id%columns)*7,floori(float(id)/columns)*7,7,7))
				at.x += 8

var bark_history: Array[Dictionary] = []
var resisted := 0

func _make_effects() -> PotionEffects:
	return ProtectiveEffects.new()

func _reset_scene(next_mode: String) -> void:
	super._reset_scene(next_mode)
	rat.data.damage_min = 12
	rat.data.damage_max = 12
	var id := StatusAssets.icon_id("BARKSKIN" if item.type_id == "PotionOfEarthenArmor" else "IMMUNITY")
	var texture := buff_icon.texture as AtlasTexture
	var columns := floori(texture.atlas.get_width()/7.0)
	texture.region = Rect2((id%columns)*7,floori(float(id)/columns)*7,7,7)
	buff_icon.modulate = Color.WHITE if item.type_id == "PotionOfEarthenArmor" else Color(1,0,2)
	if item.type_id == "PotionOfCleansing":
		var actor := _subject()
		actor.hp = 40
		for effect in ["poison","burning","cripple"]: actor.status(effect,8)
		# Start with native icons/particles; reserve name announcements for
		# the actual cleansing so setup does not dominate the demonstration.
		_announcements.clear()
		health_bar.reparent(actor.sprite.body)
		effects.sync_actor_states(0)
	_refresh_vitals()

func _subject() -> WandActor:
	return rat if mode == "throw" else warrior

func _start_cycle() -> void:
	_reset_scene("drink")
	history.clear()
	bark_history.clear()
	_steps.clear()
	_steps.append({"kind":"drink","delay":0.9})
	if item.type_id == "PotionOfEarthenArmor":
		_steps.append({"kind":"defend","delay":0.9})
		_ticks(3)
		_steps.append({"kind":"defend","delay":0.9})
	else:
		_steps.append({"kind":"challenge","delay":1.2})
		_ticks(2)
		_steps.append({"kind":"scene","mode":"throw","delay":1.2})
		_steps.append({"kind":"throw","delay":1.0})
		_steps.append({"kind":"challenge","delay":1.2})
	_steps.append({"kind":"hold","delay":1.5})
	_next = 0
	_remaining = 1.0
	phase = "ready"

func _execute(step: Dictionary) -> void:
	if step.kind == "challenge":
		phase = "challenge"
		var actor := _subject()
		for effect in ["poison","burning","cripple"]:
			actor.status(effect,8)
			if not actor.has_status(effect): resisted += 1
		_refresh_vitals()
	else: super._execute(step)

func _rat_action_finished(action: StringName) -> void:
	var resolving := _active and _pending == "defend" and action == &"attack"
	var before := warrior.hp
	var armor := warrior.barkskin_defense()
	super._rat_action_finished(action)
	if resolving: bark_history.append({"armor":armor,"damage":before-warrior.hp,"hp":warrior.hp,"turn":world.environment.turn})

func _refresh_vitals() -> void:
	if not is_instance_valid(counter): return
	var actor := _subject()
	var key := "barkskin" if item.type_id == "PotionOfEarthenArmor" else "cleanse"
	counter.text = str(actor.barkskin_defense()) if key == "barkskin" else str(ceili(float(actor.statuses.get(key,0))))
	buff_icon.visible = actor.has_status(key)
	if is_instance_valid(health_bar): health_bar.set_vitals(actor.hp,actor.max_hp,actor.shield)

func _event(event: Dictionary) -> void:
	super._event(event)
	# Thrown cleansing attaches at flight arrival, between scripted steps.
	# Refresh the target's native icon/counter at that attachment as well.
	if event.action == "buff_added": _refresh_vitals()
