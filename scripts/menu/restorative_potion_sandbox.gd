# PotionOfStamina / PotionOfShielding, native drink/status UI and real rules.
extends "res://scripts/menu/potion_sandbox.gd"
const HealthIndicator = preload("res://scripts/status/character_health_indicator.gd")

var health_bar: Node2D
var buff_icon: TextureRect
var counter: Label
var movement_history: Array[Dictionary] = []
var shield_history: Array[Dictionary] = []
var attacks_resolved := 0
var _target_cell := -1
var _announcements: Array[Dictionary] = []
var _announcement_text: CombatFloatingText

func _make_world() -> PotionWorld:
	return MeleeWorld.new()

func _make_target_sprite() -> DungeonHeroSprite:
	var sprite := RatSprite.new()
	sprite.action_finished.connect(_rat_action_finished)
	return sprite

func set_active(value: bool) -> void:
	_announcements.clear()
	_announcement_text = null
	super.set_active(value)

func _reset_scene(next_mode: String) -> void:
	_announcements.clear()
	_announcement_text = null
	for view in [health_bar,buff_icon,counter]:
		if is_instance_valid(view): view.free()
	health_bar = null
	buff_icon = null
	counter = null
	super._reset_scene(next_mode)
	if item.type_id == "PotionOfStamina":
		world.environment.unregister_actor(rat)
		world.level.set_character(rat.cell,null)
		world.actors.erase(rat)
		rat.received_damage.disconnect(world._actor_damage.bind(rat))
		rat.status_added.disconnect(world._actor_status.bind(rat))
		rat_sprite.hide()
	else:
		world.move(warrior,world.level.cell_id(Vector2i(2,3)))
		hero_sprite.place_cell(Vector2i(1,2))
		world.move(rat,world.level.cell_id(Vector2i(3,3)))
		rat_sprite.place_cell(Vector2i(2,2))
		warrior.defense_skill = 0
		rat.data.damage_min = 8
		rat.data.damage_max = 8
		hero_sprite.face_cell(rat_sprite.cell)
		rat_sprite.face_cell(hero_sprite.cell)
		health_bar = HealthIndicator.new()
		hero_sprite.body.add_child(health_bar)
	buff_icon = TextureRect.new()
	buff_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buff_icon.position = Vector2(6,7)
	buff_icon.size = Vector2(7,7)
	var texture := AtlasTexture.new()
	texture.atlas = preload("res://assets/ui/source/buffs.png")
	var id := StatusAssets.icon_id("HASTE" if item.type_id == "PotionOfStamina" else "ARMOR")
	var columns := floori(texture.atlas.get_width()/7.0)
	texture.region = Rect2((id%columns)*7,floori(float(id)/columns)*7,7,7)
	buff_icon.texture = texture
	buff_icon.modulate = Color(0.5,1,0.5) if item.type_id == "PotionOfStamina" else Color(0.5,1,2)
	map.add_child(buff_icon)
	counter = Label.new()
	counter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	counter.add_theme_font_override("font",UiAssets.get_font())
	counter.add_theme_font_size_override("font_size",6)
	UiAssets.apply_text_outline(counter)
	counter.position = Vector2(17,5)
	map.add_child(counter)
	_refresh_vitals()

func _start_cycle() -> void:
	_reset_scene("drink")
	history.clear()
	movement_history.clear()
	shield_history.clear()
	_steps.clear()
	if item.type_id == "PotionOfStamina":
		for x in [1,2,3]: _steps.append({"kind":"step","cell":Vector2i(x,2)})
		_steps.append({"kind":"drink","delay":0.8})
		for x in [2,1,0]: _steps.append({"kind":"step","cell":Vector2i(x,2)})
	else:
		_steps = [{"kind":"drink","delay":0.8},{"kind":"tick","delay":0.9},
			{"kind":"defend","delay":0.9}]
		for tick in 3: _steps.append({"kind":"tick","delay":0.8})
	_steps.append({"kind":"hold","delay":1.8})
	_next = 0
	_remaining = 0.65
	phase = "ready"

func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree(): return
	var layer := map.get_node_or_null("CombatText") as CombatTextLayer
	if layer != null and not layer.active_texts().is_empty(): return
	if not _announcements.is_empty():
		var notice: Dictionary = _announcements.pop_front()
		_announcement_text = BuffAnnouncements.show(notice.actor.sprite,str(notice.effect))
		if _announcement_text != null:
			var bounds := _announcement_text.collision_rect()
			_announcement_text.position.x += clampf(bounds.position.x,1,maxf(1,63-bounds.size.x))-bounds.position.x
		return
	super._process(delta)

func _execute(step: Dictionary) -> void:
	phase = str(step.kind)
	match phase:
		"step":
			var plan := world.try_move(warrior,world.level.cell_id(Vector2i(step.cell)+Vector2i.ONE))
			if plan.has("error"): return
			_pending = "step"
			_target_cell = int(plan.cell)
			_move_cost = float(plan.cost)
			if not hero_sprite.move_to_cell(Vector2i(step.cell)): _pending = ""
		"defend":
			_pending = "defend"
			rat_sprite.play_action(&"attack")
		_:
			super._execute(step)
			_refresh_vitals()
			if phase == "drink": shield_history.append({"kind":"drink","shield":warrior.shield,"hp":warrior.hp})
			elif phase == "tick": shield_history.append({"kind":"tick","shield":warrior.shield,"hp":warrior.hp})

func _motion_finished() -> void:
	if _pending != "step": return
	world.move(warrior,_target_cell)
	movement_history.append({"cell":_target_cell,"cost":_move_cost,"stamina":warrior.has_status("stamina")})
	world.spend(_move_cost)
	moves_completed += 1
	_pending = ""
	_remaining = 0.6*_move_cost
	_refresh_vitals()

func _rat_action_finished(action: StringName) -> void:
	if not _active or _pending != "defend" or action != &"attack": return
	world.rng.seed = 0
	(world as MeleeWorld).attack(rat,warrior)
	attacks_resolved += 1
	shield_history.append({"kind":"defend","shield":warrior.shield,"hp":warrior.hp})
	_pending = ""
	_refresh_vitals()

func _refresh_vitals() -> void:
	if not is_instance_valid(counter): return
	if item.type_id == "PotionOfStamina":
		counter.text = "%.2ft" % world.movement_cost(warrior)
		buff_icon.visible = warrior.has_status("stamina")
	else:
		counter.text = str(warrior.shield)
		buff_icon.visible = warrior.shield > 0
		if is_instance_valid(health_bar): health_bar.set_vitals(warrior.hp,warrior.max_hp,warrior.shield)

func _event(event: Dictionary) -> void:
	var actor: WandActor = event.get("actor")
	match event.action:
		"buff_added":
			if actor != null and BuffAnnouncements.is_announced(str(event.effect)):
				_announcements.append({"actor":actor,"effect":event.effect})
		"shielding": actor.sprite.show_shielding(int(event.amount))
		"damage": actor.sprite.show_damage(int(event.amount),CombatTextAssets.Icon.PHYS_DMG)
		"melee_hit": actor.sprite.flash()
		_: super._event(event)
