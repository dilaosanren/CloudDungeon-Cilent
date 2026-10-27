# WndJournal Armor.Glyph cloth icons and original SPD glyph demonstrations.
# Isolated rules world, native animations/effects; never opens a network match.
extends "res://scripts/menu/enchantment_sandbox.gd"

class GlyphEffects extends LocalEffectsView:
	func _emit_scroll_particle(emitter: Dictionary) -> void:
		if emitter.kind not in ["yellow_light","blue_light"]:
			super._emit_scroll_particle(emitter)
			return
		# Speck.YELLOW_LIGHT / BLUE_LIGHT share LIGHT's frame, lifetime,
		# rotation and fade; only their original tints differ.
		var light_emitter := emitter.duplicate()
		light_emitter.kind = "light"
		var previous := scroll_particles.size()
		super._emit_scroll_particle(light_emitter)
		if scroll_particles.size() > previous:
			scroll_particles.back().color = Color("dddd00" if emitter.kind == "yellow_light" else "00ccff")

	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			if not is_instance_valid(actor.sprite) or not actor.sprite.visible: continue
			var id := 21 if actor.has_status("charm") else 28 if int(actor.data.get("deferred_damage",0)) > 0 else -1
			if id < 0: continue
			var columns := floori(BUFFS.get_width()/7.0)
			draw_texture_rect_region(BUFFS,Rect2(actor_point(actor)+Vector2(-7,-14),Vector2(7,7)),Rect2((id%columns)*7,floori(float(id)/columns)*7,7,7))

var armor: InventoryItem
var wand: InventoryItem
var wand_icon: DungeonItemSprite
var movement_history: Array[Dictionary] = []
var damage_history: Array[Dictionary] = []
var casts_completed := 0
var _target_cell := -1
var _wearing_glyph := true

func _make_world() -> PotionWorld:
	return preload("res://scripts/menu/glyph_preview_world.gd").new()

func _make_effects() -> PotionEffects:
	return GlyphEffects.new()

func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(_announcement_text): return
	var bounds := _announcement_text.collision_rect()
	if bounds.size.x > 62:
		# Deferred Damage is wider than the small floor at the native font
		# size. Center it across the animation's spare side margins instead
		# of cutting off its outline or shrinking all combat text.
		_announcement_text.position.x += (64-bounds.size.x)/2-bounds.position.x

func _prepare_equipment() -> void:
	if is_instance_valid(wand_icon): wand_icon.free()
	wand_icon = null
	wand = null
	key = str(item.get_meta("journal_glyph"))
	armor = item.copy_item()
	armor.uid = "journal-glyph-armor"
	_wearing_glyph = true
	_target_cell = -1
	warrior.data.armor_item = armor
	warrior.data.armor_tier = ArmorRules.tier(armor)
	warrior.data.armor_min = ArmorRules.defense(armor,warrior)
	warrior.data.armor_max = warrior.data.armor_min
	warrior.defense_skill = 15 if key == "stone" else 0
	rat.defense_skill = 0
	rat.data.damage_min = 12 if key in ["viscosity","stone"] else 4 if key == "entanglement" else 6
	rat.data.damage_max = rat.data.damage_min
	_place_actor(warrior,Vector2i(0 if key == "repulsion" else 1,2))
	_place_actor(rat,Vector2i(1 if key == "repulsion" else 2,2))
	if key in ["swiftness","flow","camouflage"]:
		# Walking previews have no enemy, so Swiftness's real proximity check
		# succeeds. Remove rule occupancy as well as hiding the rat sprite.
		world.environment.unregister_actor(rat)
		world.level.set_character(rat.cell,null)
		world.actors.erase(rat)
		rat.received_damage.disconnect(world._actor_damage.bind(rat))
		rat.status_added.disconnect(world._actor_status.bind(rat))
		rat_sprite.hide()
		_place_actor(warrior,Vector2i(0,2))
	if key == "flow":
		for x in GRID_SIZE.x: world.environment.set_terrain(world.level.cell_id(Vector2i(x+1,3)),DungeonTerrain.Type.WATER)
		warrior.data.in_water = true
	elif key == "camouflage":
		world.environment.set_terrain(world.level.cell_id(Vector2i(2,3)),DungeonTerrain.Type.HIGH_GRASS)
	if key in ["potential","antimagic"]:
		wand = InventoryCatalog.create("WandOfMagicMissile")
		world.carry(warrior if key == "potential" else rat,[wand])
		wand.charges = 0 if key == "potential" else wand.max_charges
		wand.metadata.wand_state.partial = 0.0
		wand_icon = DungeonItemSprite.new()
		map.add_child(wand_icon)
		wand_icon.set_item(wand)
		wand_icon.position = Vector2(56,22)
	hero_sprite.face_cell(Vector2i(3,2) if rat_sprite.visible == false else rat_sprite.cell)
	rat_sprite.face_cell(hero_sprite.cell)
	weapon_icon = DungeonItemSprite.new()
	map.add_child(weapon_icon)
	weapon_icon.set_item(armor)
	weapon_icon.position = Vector2(8,22)
	counter = Label.new()
	counter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	counter.add_theme_font_override("font",UiAssets.get_font())
	counter.add_theme_font_size_override("font_size",6)
	UiAssets.apply_text_outline(counter)
	counter.position = Vector2(17,4)
	map.add_child(counter)
	health_bar = HealthIndicator.new()
	hero_sprite.body.add_child(health_bar)
	_stop_visuals()
	_refresh_vitals()
	world.events.clear()

func _start_cycle() -> void:
	_reset_scene("glyph")
	history.clear()
	movement_history.clear()
	damage_history.clear()
	_steps.clear()
	_next = 0
	phase = "ready"
	_remaining = 0.65
	match key:
		"swiftness", "flow":
			_steps.append({"kind":"plain","delay":0.3})
			for x in [1,2,3]: _steps.append({"kind":"step","cell":Vector2i(x,2)})
			_steps.append({"kind":"activate","delay":0.4})
			for x in [2,1,0]: _steps.append({"kind":"step","cell":Vector2i(x,2)})
		"camouflage": _steps.append({"kind":"step","cell":Vector2i(1,2)})
		"brimstone":
			_steps.append({"kind":"fire"})
			for tick in 4: _steps.append({"kind":"tick","delay":0.7})
		"stone", "antimagic":
			_steps.append({"kind":"plain","delay":0.3})
			_steps.append({"kind":"cast" if key == "antimagic" else "defend"})
			_steps.append({"kind":"activate","delay":0.7})
			_steps.append({"kind":"cast" if key == "antimagic" else "defend"})
		_:
			_steps.append({"kind":"defend"})
			if key in ["thorns","viscosity"]:
				for tick in 3: _steps.append({"kind":"tick","delay":0.7})
			elif key == "entanglement":
				_steps.append({"kind":"hold","delay":1.2})
				_steps.append({"kind":"step","cell":Vector2i(1,1)})
			elif key == "potential":
				_steps.append({"kind":"hold","delay":1.2})
				_steps.append({"kind":"cast"})
			elif key == "affection": _steps.append({"kind":"defend"})
	_steps.append({"kind":"hold","delay":2.0})

func _set_glyph(enabled: bool) -> void:
	_wearing_glyph = enabled
	if enabled: armor.metadata = item.metadata.duplicate(true)
	else: armor.metadata.erase("glyph")
	_refresh_vitals()

func _execute(step: Dictionary) -> void:
	phase = str(step.kind)
	match phase:
		"plain": _set_glyph(false)
		"activate": _set_glyph(true)
		"defend":
			_pending = "defend"
			rat_sprite.face_cell(hero_sprite.cell)
			rat_sprite.play_action(&"attack")
		"step":
			var target := world.level.cell_id(Vector2i(step.cell)+Vector2i.ONE)
			var plan := world.try_move(warrior,target)
			if plan.has("error"): return
			_pending = "step"
			_target_cell = int(plan.cell)
			_move_cost = float(plan.cost)
			# Keep the game's normal hop and apply movement cost to the pause
			# between steps. Occupancy and glyph activation wait for landing.
			if not hero_sprite.move_to_cell(Vector2i(step.cell)): _pending = ""
		"fire":
			world.environment.seed("fire",warrior.cell,6)
			world.environment.seed("fire",rat.cell,6)
			effects.sound("burning")
		"tick":
			world.spend(1)
			history.append({"kind":"tick","hp":warrior.hp,"rat_hp":rat.hp,"deferred":warrior.data.get("deferred_damage",0)})
			effects.sync_actor_states(0)
			_refresh_vitals()
		"cast": _cast()

func _action_finished(_action: StringName) -> void:
	pass # The armor wearer does not attack in glyph demonstrations.

func _rat_action_finished(action: StringName) -> void:
	if not _active or _pending != "defend" or action != &"attack": return
	# This local native seed triggers the chance-based glyph on the first hit.
	world.rng.seed = 0
	var before := warrior.hp
	last_result = (world as MeleeWorld).attack(rat,warrior)
	attacks_resolved += 1
	damage_history.append({"glyph":_wearing_glyph,"before":before,"after":warrior.hp,
		"damage":before-warrior.hp,"result":last_result.duplicate(),"pool":warrior.data.get("deferred_damage",0),
		"earthroot":warrior.data.get("earthroot_armor",0),"charge":wand.charges if wand != null else -1})
	_pending = ""
	effects.sync_actor_states(0)
	_refresh_vitals()

func _motion_finished() -> void:
	if _pending != "step": return
	world.move(warrior,_target_cell)
	moves_completed += 1
	movement_history.append({"glyph":_wearing_glyph,"cost":_move_cost,"cell":warrior.cell})
	if _wearing_glyph and key in ["swiftness","flow"]:
		(effects as GlyphEffects).start_specks(warrior,warrior.cell,"yellow_light" if key == "swiftness" else "blue_light",0.02,1 if key == "swiftness" else 2,false)
	_pending = ""
	_remaining = 0.6*_move_cost
	effects.sync_actor_states(0)
	_refresh_vitals()

func _cast() -> void:
	var caster := warrior if key == "potential" else rat
	var target := rat if key == "potential" else warrior
	var plan := world.prepare(wand,caster,target.cell)
	if plan.has("error"): return
	_pending = "cast"
	var generation := _epoch
	caster.sprite.play_action(&"zap" if caster == warrior else &"attack")
	effects.play(plan,func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		world.rng.seed = 2
		var before := target.hp
		world.resolve(plan)
		casts_completed += 1
		damage_history.append({"glyph":_wearing_glyph,"kind":"cast","damage":before-target.hp})
		_pending = ""
		effects.sync_actor_states(0)
		_refresh_vitals())

func _refresh_vitals() -> void:
	if not is_instance_valid(counter): return
	if key in ["swiftness","flow"]: counter.text = "%.2ft" % world.movement_cost(warrior)
	elif key in ["potential","antimagic"]: counter.text = "%d/%d" % [wand.charges,wand.max_charges]
	elif key == "viscosity": counter.text = str(warrior.data.get("deferred_damage",0))
	else: counter.text = ""
	if is_instance_valid(weapon_icon): weapon_icon.set_item(armor)
	if is_instance_valid(health_bar): health_bar.set_vitals(warrior.hp,warrior.max_hp,0)

func _event(event: Dictionary) -> void:
	if event.action == "move" and event.get("actor") == warrior and _pending == "step": return
	if event.action == "damage" and event.source in ["deferred","WandOfMagicMissile"]:
		var actor: WandActor = event.actor
		actor.sprite.show_damage(int(event.amount),CombatTextAssets.Icon.DEFERRED if event.source == "deferred" else CombatTextAssets.Icon.MAGIC_DMG)
	elif event.action == "dodge": event.actor.sprite.show_dodge()
	else: super._event(event)
