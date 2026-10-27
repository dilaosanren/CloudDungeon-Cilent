# WndJournal's glowing worn shortsword, staged with actual RunicGear procs.
# Original SPD 4.0.2 sprites/particles; only timing and RNG are local to the journal.
extends "res://scripts/menu/potion_sandbox.gd"
const Gear = preload("res://scripts/nature/runic_gear.gd")
const SeedPreview = preload("res://scripts/menu/seed_sandbox.gd")
const HealthIndicator = preload("res://scripts/status/character_health_indicator.gd")

class LocalEffectsView extends SeedPreview.LocalSeedEffects:
	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			if actor.has_status("bleeding") and is_instance_valid(actor.sprite):
				var columns := floori(BUFFS.get_width() / 7.0)
				draw_texture_rect_region(BUFFS, Rect2(actor_point(actor) + Vector2(-7,-14), Vector2(7,7)), Rect2((26 % columns)*7, floori(26.0/columns)*7,7,7))

class MortalRat extends RatSprite:
	func set_appearance(hero: String, tier: int) -> bool:
		super.set_appearance(hero,tier)
		if body == null: return true
		var frames := body.sprite_frames
		frames.add_animation(&"die")
		frames.set_animation_speed(&"die",10)
		frames.set_animation_loop(&"die",false)
		for column in [11,12,13,14]:
			var texture := AtlasTexture.new()
			texture.atlas = RAT
			texture.region = Rect2(column*16,0,16,15)
			frames.add_frame(&"die",texture)
		return true

var key := ""
var weapon: InventoryItem
var weapon_icon: DungeonItemSprite
var counter: Label
var health_bar: Node2D
var extra_targets: Array[WandActor] = []
var extra_sprites: Array[DungeonHeroSprite] = []
var attacks_resolved := 0
var shatters_completed := 0
var last_result: Dictionary = {}
var _push_tweens: Array[Tween] = []
var _announcements: Array[Dictionary] = []
var _announcement_text: CombatFloatingText

func _make_world() -> PotionWorld:
	return MeleeWorld.new()

func _make_effects() -> PotionEffects:
	return LocalEffectsView.new()

func _make_target_sprite() -> DungeonHeroSprite:
	var sprite := MortalRat.new()
	sprite.action_finished.connect(_rat_action_finished)
	return sprite

func _stop_visuals() -> void:
	_announcements.clear()
	_announcement_text = null
	for tween in _push_tweens:
		if tween.is_valid(): tween.kill()
	_push_tweens.clear()

func set_active(value: bool) -> void:
	_stop_visuals()
	super.set_active(value)

func _place_actor(actor: WandActor, at: Vector2i) -> void:
	world.move(actor,world.level.cell_id(at+Vector2i.ONE))
	actor.sprite.place_cell(at)

func _reset_scene(next_mode: String) -> void:
	_stop_visuals()
	for sprite in extra_sprites: sprite.free()
	extra_sprites.clear()
	extra_targets.clear()
	for view in [weapon_icon,counter,health_bar]:
		if is_instance_valid(view): view.free()
	weapon_icon = null
	counter = null
	health_bar = null
	super._reset_scene(next_mode)
	_prepare_equipment()

# Glyph previews share this scene lifecycle, native effects and popup queue.
func _prepare_equipment() -> void:
	key = str(item.get_meta("journal_enchantment"))
	weapon = item.copy_item()
	weapon.uid = "journal-enchanted-sword"
	warrior.data.melee_weapon = weapon
	rat.defense_skill = 0
	warrior.defense_skill = 0
	rat.data.damage_min = 2
	rat.data.damage_max = 2
	var left: bool = key in ["shocking","elastic","projecting"]
	_place_actor(warrior,Vector2i(0 if left else 1,2))
	_place_actor(rat,Vector2i(2 if key == "projecting" else 1 if left else 2,2))
	if key == "grim": rat.hp = 12
	if key == "vampiric": warrior.hp = 40
	# Blooming's native proc grows on ordinary dungeon floor.
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			world.environment.set_terrain(world.level.cell_id(Vector2i(x+1,y+1)),DungeonTerrain.Type.EMPTY)
	if key == "shocking":
		var sprite := MortalRat.new()
		map.add_child(sprite)
		var target := WandActor.new()
		target.species = "rat"
		target.max_hp = 70
		target.hp = 70
		target.sprite = sprite
		world.add_actor(target,world.level.cell_id(Vector2i(3,3)))
		sprite.place_cell(Vector2i(2,2))
		extra_targets.append(target)
		extra_sprites.append(sprite)
	hero_sprite.face_cell(rat_sprite.cell)
	rat_sprite.face_cell(hero_sprite.cell)
	weapon_icon = DungeonItemSprite.new()
	map.add_child(weapon_icon)
	weapon_icon.set_item(weapon)
	weapon_icon.position = Vector2(8,22)
	if key == "crystal":
		counter = Label.new()
		counter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		counter.add_theme_font_override("font",UiAssets.get_font())
		counter.add_theme_font_size_override("font_size",6)
		UiAssets.apply_text_outline(counter)
		counter.position = Vector2(17,5)
		map.add_child(counter)
	if key in ["vampiric","blocking"]:
		health_bar = HealthIndicator.new()
		hero_sprite.body.add_child(health_bar)
	world.hooks.destroy_gear = _shatter
	world.events.clear()
	_refresh_vitals()

func _start_cycle() -> void:
	_reset_scene("melee")
	history.clear()
	_steps = [{"kind":"attack","delay":0.75}]
	_next = 0
	phase = "ready"
	_remaining = 0.65
	match key:
		"crystal":
			for hit in 4: _steps.append({"kind":"attack","delay":0.75})
		"blocking": _steps.append({"kind":"defend","delay":1.0})
		"blazing", "vorpal", "venomous":
			for tick in (5 if key == "venomous" else 3): _steps.append({"kind":"tick","delay":0.7})
	_steps.append({"kind":"hold","delay":2.0})

func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree(): return
	# The compact preview queues names after numbers, keeping native popups
	# inside its 48px floor without changing normal battle presentation.
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
		"attack":
			_pending = "attack"
			hero_sprite.play_action(&"attack")
		"defend":
			_pending = "defend"
			rat_sprite.play_action(&"attack")
		"tick":
			world.spend(1)
			effects.sync_actor_states(0)
			_refresh_vitals()
			history.append({"kind":"tick","hp":rat.hp})

func _action_finished(action: StringName) -> void:
	if not _active or _pending != "attack" or action != &"attack": return
	# A deterministic native RNG roll makes a chance-based enchantment visible
	# on every demonstration. Proc chances, damage and status rules stay real.
	world.rng.seed = 0 if key in ["projecting","crystal"] else 2
	last_result = (world as MeleeWorld).attack(warrior,rat)
	attacks_resolved += 1
	history.append({"kind":"attack","result":last_result.duplicate(),"hp":rat.hp,
		"hero_hp":warrior.hp,"uses":Gear.crystal_uses_left(weapon),"cell":rat.cell})
	_pending = ""
	effects.sync_actor_states(0)
	_refresh_vitals()
	if rat.hp <= 0: rat_sprite.play_action(&"die")

func _rat_action_finished(action: StringName) -> void:
	if not _active or _pending != "defend" or action != &"attack": return
	last_result = (world as MeleeWorld).attack(rat,warrior)
	history.append({"kind":"defend","result":last_result.duplicate(),"hp":warrior.hp,
		"shield":warrior.data.get("block_shield",0)})
	_pending = ""
	_refresh_vitals()

func _refresh_vitals() -> void:
	if is_instance_valid(counter): counter.text = "%d/%d" % [Gear.crystal_uses_left(weapon),Gear.CRYSTAL_USES]
	if is_instance_valid(weapon_icon): weapon_icon.set_item(weapon)
	if is_instance_valid(health_bar):
		health_bar.set_vitals(warrior.hp,warrior.max_hp,int(warrior.data.get("block_shield",0)))

func _shatter(actor: WandActor, broken: InventoryItem) -> void:
	if actor != warrior or broken != weapon: return
	warrior.data.erase("melee_weapon")
	shatters_completed += 1
	weapon_icon.hide()
	effects.splash_at(effects.actor_point(warrior),Color("66ddff"),15)
	effects.sound("shatter")
	history.append({"kind":"shatter","uses":Gear.crystal_uses_left(broken)})

func _event(event: Dictionary) -> void:
	var actor: WandActor = event.get("actor")
	var view := effects as LocalEffectsView
	match event.action:
		"buff_added":
			if actor != null and BuffAnnouncements.is_announced(str(event.effect)):
				_announcements.append({"actor":actor,"effect":event.effect})
		"damage":
			if actor == null or not is_instance_valid(actor.sprite): return
			var icon := CombatTextAssets.Icon.PHYS_DMG
			match str(event.source):
				"burning": icon = CombatTextAssets.Icon.BURNING
				"poison": icon = CombatTextAssets.Icon.POISON
				"bleeding": icon = CombatTextAssets.Icon.BLEEDING
				"crystal", "grim", "shocking": icon = CombatTextAssets.Icon.MAGIC_DMG
			actor.sprite.show_damage(int(event.amount),icon)
		"healing": actor.sprite.show_healing(int(event.amount))
		"shielding":
			var layer := CombatTextLayer.for_actor(actor.sprite)
			var at := layer.to_local(actor.sprite.to_global(Vector2(0,-13)))
			layer.show_status(at,str(event.amount),Color.GREEN,CombatTextAssets.Icon.SHIELDING,world.level.cell_coords(actor.cell))
		"melee_hit": actor.sprite.flash()
		"melee_sound": effects.sound(str(event.sound),float(event.pitch))
		"move":
			if actor == null or not is_instance_valid(actor.sprite): return
			var at := world.level.cell_coords(actor.cell)-Vector2i.ONE
			actor.sprite.cell = at
			var tween := actor.sprite.create_tween()
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(actor.sprite,"position",Vector2(at*16)+Vector2(8,8),0.15)
			_push_tweens.append(tween)
		"nature_particles": view.nature_burst(int(event.cell),str(event.kind),int(event.count),float(event.get("interval",0)))
		"nature_lightning":
			for arc in event.arcs: effects.lightning(effects.point(int(arc[0])),effects.point(int(arc[1])))
		"scroll_specks": view.start_specks(actor,int(event.cell),str(event.kind),float(event.interval),int(event.count),bool(event.center))
		_: super._event(event)

func _exit_tree() -> void:
	_stop_visuals()
	super._exit_tree()
