# Local journal projectile demonstrations using the actual PvP MissileWorld.
extends "res://scripts/menu/potion_sandbox.gd"
const SeedPreview = preload("res://scripts/menu/seed_sandbox.gd")
const PiranhaSprite = preload("res://scripts/menu/equipment_piranha_sprite.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")

class LocalMissileEffects extends SeedPreview.LocalSeedEffects:
	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			if not actor.has_status("bleeding") or not is_instance_valid(actor.sprite): continue
			var columns := floori(BUFFS.get_width()/7.0)
			var id := 26 # BuffIndicator.BLEEDING.
			draw_texture_rect_region(BUFFS,Rect2(actor_point(actor)+Vector2(-7,-14),Vector2(7,7)),Rect2((id%columns)*7,floori(float(id)/columns)*7,7,7))

var projectile: InventoryItem
var owned_inventory: DungeonInventory
var extra_target: WandActor
var extra_sprite: DungeonHeroSprite
var caption: Label
var returned_sprite: Sprite2D
var returns_completed := 0
var resolved_results: Array[Dictionary] = []
var damage_events: Array[Dictionary] = []
var last_result: Dictionary = {}
var _buff_names: Array[Dictionary] = []
var _buff_left := -1.0

func _make_world() -> PotionWorld:
	return MeleeWorld.new()

func _make_effects() -> PotionEffects:
	return LocalMissileEffects.new()

func _make_target_sprite() -> DungeonHeroSprite:
	return PiranhaSprite.new() if item.type_id == "FishingSpear" else RatSprite.new()

func _reset_scene(next_mode: String) -> void:
	if is_instance_valid(extra_sprite): extra_sprite.free()
	extra_sprite = null
	extra_target = null
	_buff_names.clear()
	_buff_left = -1
	super._reset_scene(next_mode)
	warrior.hp = warrior.max_hp
	rat.hp = 70
	rat.max_hp = 70
	rat.defense_skill = 0
	if item.type_id == "FishingSpear":
		rat.species = "piranha"
		rat_sprite.body.position.y = -11.2
		rat_sprite.shadow.hide()
		world.environment.set_terrain(rat.cell,DungeonTerrain.Type.WATER)
		rat.data.in_water = true
	if item.type_id == "ForceCube":
		extra_target = WandActor.new()
		extra_target.species = "rat"
		extra_target.hp = 70
		extra_target.max_hp = 70
		extra_target.defense_skill = 0
		extra_sprite = RatSprite.new()
		map.add_child(extra_sprite)
		extra_target.sprite = extra_sprite
		world.add_actor(extra_target,world.level.cell_id(Vector2i(3,2)))
		extra_sprite.place_cell(Vector2i(2,1))
		extra_sprite.face_cell(hero_sprite.cell)
	owned_inventory = DungeonInventory.new()
	(world as MeleeWorld).inventory = owned_inventory
	(world as RingWorld).player = warrior
	projectile = item.copy_item()
	projectile.quantity = 1
	resolved_results.clear()
	damage_events.clear()
	last_result.clear()
	if caption == null:
		caption = Label.new()
		caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		caption.add_theme_font_size_override("font_size",6)
		caption.add_theme_font_override("font",UiAssets.get_font_at_scale(2))
		UiAssets.apply_text_outline(caption)
		caption.position = Vector2(2,2)
		map.add_child(caption)
		returned_sprite = Sprite2D.new()
		returned_sprite.position = Vector2(9,12)
		map.add_child(returned_sprite)
	caption.text = ""
	caption.position.x = 2
	returned_sprite.hide()
	world.events.clear()

func _start_cycle() -> void:
	_reset_scene("missile")
	history.clear()
	_steps = [{"kind":"throw","delay":2.2}]
	match item.type_id:
		"Shuriken": _steps.append({"kind":"throw","delay":1.5})
		"Tomahawk":
			for tick in 2: _steps.append({"kind":"tick","delay":1.3})
		"HeavyBoomerang": _steps.append({"kind":"tick","delay":1.4})
	_steps.append({"kind":"hold","delay":1.2})
	_next = 0
	phase = "ready"
	_remaining = 0.65

func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree(): return
	if _buff_left >= 0:
		_buff_left -= delta
		if _buff_left < 0:
			for announcement in _buff_names: BuffAnnouncements.show(announcement.actor.sprite,announcement.effect)
			_buff_names.clear()
	super._process(delta)

func set_active(value: bool) -> void:
	_buff_names.clear()
	_buff_left = -1
	super.set_active(value)

func _execute(step: Dictionary) -> void:
	phase = str(step.kind)
	history.append({"kind":phase})
	match phase:
		"throw": _throw_weapon()
		"tick":
			world.spend(1)
			world.events.clear()
			world.environment.events.clear()

func _throw_weapon() -> void:
	if not _active or not _pending.is_empty(): return
	_pending = "throw"
	var generation := _epoch
	var flight_item := item.copy_item()
	flight_item.quantity = 1
	hero_sprite.face_cell(rat_sprite.cell)
	hero_sprite.play_action(&"zap")
	var destination := (world as MissileWorld).throw_cell(flight_item,warrior,rat.cell)
	(effects as MissileEffects).throw_weapon(flight_item,warrior,destination,func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		projectile = flight_item
		last_result = (world as MissileWorld).resolve_throw(flight_item,warrior,destination)
		resolved_results.append(last_result.duplicate(true))
		throws_completed += 1
		if item.type_id == "Shuriken": caption.text = L10n.text("不耗回合" if is_zero_approx(float(last_result.cost)) else "冷却中")
		_pending = "")

func _event(event: Dictionary) -> void:
	var actor: WandActor = event.get("actor")
	match event.action:
		"damage":
			damage_events.append(event.duplicate())
			if actor != null and is_instance_valid(actor.sprite):
				actor.sprite.show_damage(int(event.amount),CombatTextAssets.Icon.BLEEDING if event.source == "bleeding" else CombatTextAssets.Icon.PHYS_DMG)
				actor.sprite.flash()
		"buff_added":
			if str(event.effect) not in ["bleeding","cripple"]: return
			_buff_names.append({"actor":actor,"effect":str(event.effect)})
			_buff_left = 1.05 # Show the name after the initial damage popup.
		"missile_hit_sound": effects.sound(str(event.sound),float(event.pitch))
		"missile_blood": effects.splash_at(effects.actor_point(actor),Color("bb0000"),int(event.count))
		"blast": effects.blast(int(event.cell))
		"missile_return":
			var circle: Dictionary = event.circle
			circle.awaiting_visual = true
			_pending = "return"
			var generation := _epoch
			(effects as MissileEffects).throw_weapon(event.item,warrior,int(event.to),func():
				if not _active or generation != _epoch or not is_inside_tree(): return
				(world as MissileWorld).finish_return(circle)
				returns_completed += 1
				returned_sprite.texture = ItemAssets.get_texture(item.visual)
				returned_sprite.show()
				caption.position.x = 17
				caption.text = L10n.text("已返回")
				_pending = "",int(event.from),true)
		_: super._event(event)
