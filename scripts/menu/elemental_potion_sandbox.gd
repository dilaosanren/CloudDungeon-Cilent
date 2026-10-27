# PotionOfStormClouds / PotionOfDragonsBreath: actual fields, aimed drink,
# native FIRE_CONE flight, burning and cripple with no simulated damage.
extends "res://scripts/menu/potion_sandbox.gd"
const HealthIndicator = preload("res://scripts/status/character_health_indicator.gd")

class ElementalEffects extends LocalEffects:
	const BUFFS = preload("res://assets/ui/source/buffs.png")
	const Info = preload("res://scripts/status/buff_descriptions.gd")
	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			var at := actor_point(actor)+Vector2(-7,-14)
			for effect in ["burning","cripple"]:
				if not actor.has_status(effect): continue
				var id := StatusAssets.icon_id(str(Info.definitions()[effect].icon))
				var columns := floori(BUFFS.get_width()/7.0)
				draw_texture_rect_region(BUFFS,Rect2(at,Vector2(7,7)),Rect2((id%columns)*7,floori(float(id)/columns)*7,7,7))
				at.x += 8

var health_bar: Node2D
var _announcements: Array[Dictionary] = []
var _announcement_text: CombatFloatingText
var breath_completed := 0
var impact_cell := -1

func _make_effects() -> PotionEffects:
	return ElementalEffects.new()

func set_active(value: bool) -> void:
	_announcements.clear()
	_announcement_text = null
	super.set_active(value)

func _reset_scene(next_mode: String) -> void:
	_announcements.clear()
	_announcement_text = null
	if is_instance_valid(health_bar): health_bar.free()
	health_bar = null
	super._reset_scene(next_mode)
	impact_cell = world.level.cell_id(Vector2i(3,2))
	if item.type_id == "PotionOfStormClouds":
		for y in GRID_SIZE.y:
			for x in GRID_SIZE.x: world.environment.set_terrain(world.level.cell_id(Vector2i(x+1,y+1)),DungeonTerrain.Type.GRASS)
		world.environment.set_terrain(world.level.cell_id(Vector2i(3,1)),DungeonTerrain.Type.TRAP)
		world.environment.seed("fire",world.level.cell_id(Vector2i(2,1)),5)
	else:
		health_bar = HealthIndicator.new()
		rat_sprite.body.add_child(health_bar)
		health_bar.set_vitals(rat.hp,rat.max_hp,rat.shield)

func _start_cycle() -> void:
	_reset_scene("throw" if item.type_id == "PotionOfStormClouds" else "drink")
	history.clear()
	_steps.clear()
	_steps.append({"kind":"throw" if item.type_id == "PotionOfStormClouds" else "breath","delay":1.0})
	_ticks(5)
	_steps.append({"kind":"hold","delay":1.5})
	_next = 0
	_remaining = 1.0
	phase = "ready"

func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree(): return
	if is_instance_valid(health_bar): health_bar.set_vitals(rat.hp,rat.max_hp,rat.shield)
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
	if step.kind != "breath": super._execute(step); return
	phase = "breath"
	_pending = "breath"
	var generation := _epoch
	var plan := world.prepare_breath(warrior,rat.cell)
	effects.breathe(warrior,world.breath_visual(plan),func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		world.resolve_breath(plan)
		drinks_completed += 1
		breath_completed += 1
		_pending = ""
		history.append({"kind":"breath_impact","burning":rat.statuses.get("burning",0),"cripple":rat.statuses.get("cripple",0)}))

func _throw() -> void:
	_pending = "throw"
	var generation := _epoch
	hero_sprite.face_cell(world.level.cell_coords(impact_cell)-Vector2i.ONE)
	hero_sprite.play_action(&"zap")
	effects.throw_potion(item,warrior,impact_cell,func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		world.on_throw(item,impact_cell)
		throws_completed += 1
		_pending = "")

func _event(event: Dictionary) -> void:
	if event.action == "buff_added":
		var actor: WandActor = event.get("actor")
		if actor != null and BuffAnnouncements.is_announced(str(event.effect)): _announcements.append({"actor":actor,"effect":event.effect})
	elif event.action == "damage":
		var actor: WandActor = event.get("actor")
		if actor != null: actor.sprite.show_damage(int(event.amount),CombatTextAssets.Icon.BURNING if event.source == "burning" else CombatTextAssets.Icon.MAGIC_DMG)
	else: super._event(event)
