# Journal-only staging of actual WandWorld casts and original SPD effects.
extends "res://scripts/menu/potion_sandbox.gd"
const HealthIndicator = preload("res://scripts/status/character_health_indicator.gd")

class LocalWandEffects extends PotionEffects:
	const BUFFS = preload("res://assets/ui/source/buffs.png")
	const ICONS = {"burning":2, "roots":11, "chill":15, "blindness":16, "charm":21, "magic_charge":50}
	var shown_wand: InventoryItem
	var shown_level := 0
	func point(cell: int, raised: bool = true) -> Vector2:
		return super.point(cell, raised) - Vector2(16, 16)
	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			if not is_instance_valid(actor.sprite) or not actor.sprite.visible: continue
			var at := actor_point(actor) + Vector2(-3, -13)
			for status in ICONS:
				if not actor.has_status(status): continue
				var id: int = ICONS[status]
				var columns := floori(BUFFS.get_width() / 7.0)
				draw_texture_rect_region(BUFFS, Rect2(at, Vector2(7, 7)), Rect2((id % columns) * 7, floori(float(id) / columns) * 7, 7, 7))
				at.x += 8
		if shown_wand != null:
			var texture := ItemAssets.get_texture(shown_wand.visual)
			draw_texture(texture, Vector2(8, 11) - texture.get_size() / 2)
			var caption := "+%d" % shown_level
			if shown_level > shown_wand.level: caption = "+%d>+%d" % [shown_wand.level, shown_level]
			SpdPixelText.draw(self, Vector2(16, 13), caption, Color("ffff44"))
	func clear() -> void:
		super.clear()
		shown_wand = null
		for child in get_children():
			if child is AudioStreamPlayer:
				child.stop()
				child.queue_free()

var wand: InventoryItem
var secondary_wand: InventoryItem
var extra_targets: Array[WandActor] = []
var extra_sprites: Array[DungeonHeroSprite] = []
var health_bar: Node2D
var zaps_completed := 0
var cast_history: Array[Dictionary] = []
var _push_tweens: Array[Tween] = []
var _announcements: Array[Dictionary] = []
var _announcement_text: CombatFloatingText

func _make_effects() -> PotionEffects:
	return LocalWandEffects.new()

func set_active(value: bool) -> void:
	_announcements.clear()
	_announcement_text = null
	for tween in _push_tweens:
		if tween.is_valid(): tween.kill()
	_push_tweens.clear()
	super.set_active(value)

func _place_actor(actor: WandActor, at: Vector2i) -> void:
	world.move(actor, world.level.cell_id(at + Vector2i.ONE))
	actor.sprite.place_cell(at)

func _add_target(at: Vector2i) -> void:
	var sprite := RatSprite.new()
	map.add_child(sprite)
	var target := WandActor.new()
	target.species = "rat"
	target.max_hp = 1000000
	target.hp = target.max_hp
	target.sprite = sprite
	world.add_actor(target, world.level.cell_id(at + Vector2i.ONE))
	sprite.place_cell(at)
	sprite.face_cell(hero_sprite.cell)
	extra_targets.append(target)
	extra_sprites.append(sprite)

func _reset_scene(next_mode: String) -> void:
	_announcements.clear()
	_announcement_text = null
	for tween in _push_tweens:
		if tween.is_valid(): tween.kill()
	_push_tweens.clear()
	for sprite in extra_sprites: sprite.free()
	extra_sprites.clear()
	extra_targets.clear()
	if is_instance_valid(health_bar): health_bar.free()
	health_bar = null
	super._reset_scene(next_mode)
	world.rng.seed = 402
	rat.max_hp = 1000000
	rat.hp = rat.max_hp
	wand = item.copy_item()
	wand.uid = "journal-primary-wand"
	# A +3 missile can lend its level to a second +0 wand. The inspected item
	# and ordinary inventory remain untouched by the demonstration.
	if item.type_id == "WandOfMagicMissile": wand.level = 3
	WandState.initialize(wand)
	wand.max_charges = WandState.capacity(wand)
	wand.charges = wand.max_charges
	secondary_wand = null
	_place_actor(rat, Vector2i(2, 2))
	match item.type_id:
		"WandOfMagicMissile":
			secondary_wand = InventoryCatalog.create("WandOfFrost")
			secondary_wand.uid = "journal-secondary-wand"
			world.carry(warrior, [wand, secondary_wand])
			_show_wand(wand, wand.level)
		"WandOfLightning": _add_target(Vector2i(3, 2))
		"WandOfDisintegration":
			_add_target(Vector2i(3, 2))
			# A real wall between the caster and both targets makes terrain
			# penetration visible as well as hitting multiple enemies.
			world.environment.set_terrain(world.level.cell_id(Vector2i(2, 3)), DungeonTerrain.Type.WALL)
			map.layers.Walls.show()
			# Keep the real interior wall but suppress the renderer's automatic
			# bottom border, as in the other compact journal demonstrations.
			for x in GRID_SIZE.x:
				if x != 1: map.layers.Walls.erase_cell(Vector2i(x, 2))
		"WandOfBlastWave": _place_actor(rat, Vector2i(1, 2))
		"WandOfTransfusion":
			health_bar = HealthIndicator.new()
			hero_sprite.body.add_child(health_bar)
			health_bar.set_vitals(warrior.hp, warrior.max_hp, warrior.shield)
		"WandOfRegrowth":
			# Regrowth accepts dungeon floor, not EMPTY_SP cave decoration.
			for y in GRID_SIZE.y:
				for x in GRID_SIZE.x:
					world.environment.set_terrain(world.level.cell_id(Vector2i(x + 1, y + 1)), DungeonTerrain.Type.EMPTY)
	hero_sprite.face_cell(rat_sprite.cell)
	rat_sprite.face_cell(hero_sprite.cell)
	world.events.clear()

func _start_cycle() -> void:
	_reset_scene("zap")
	history.clear()
	cast_history.clear()
	_steps = [{"kind":"zap"}]
	_next = 0
	phase = "ready"
	_remaining = 0.65
	match item.type_id:
		"WandOfMagicMissile":
			_steps.append({"kind":"hold", "delay":1.6})
			_steps.append({"kind":"secondary", "delay":1.0})
		"WandOfFireblast", "WandOfCorrosion":
			for tick in 3: _steps.append({"kind":"tick", "delay":1.1})
		"WandOfPrismaticLight":
			# Blindness uses the normal random proc. This local seed produces
			# it on the first shot; no status or combat rule is overridden.
			_steps.append({"kind":"hold", "delay":2.5})
		_:
			_steps.append({"kind":"hold", "delay":2.5})
	_steps.append({"kind":"hold", "delay":1.4})

func _execute(step: Dictionary) -> void:
	phase = str(step.kind)
	history.append({"kind":phase})
	match phase:
		"zap": _zap(wand)
		"secondary": _zap(secondary_wand)
		"tick":
			world.spend(1)
			world.events.clear()
			world.environment.events.clear()

func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree(): return
	# Let each queued name finish before staging another cast or time tick.
	if is_instance_valid(_announcement_text) and not _announcement_text.is_queued_for_deletion(): return
	if _announcements.is_empty(): super._process(delta)
	if _announcements.is_empty(): return
	var layer := map.get_node_or_null("CombatText") as CombatTextLayer
	if layer != null and not layer.active_texts().is_empty(): return
	# In a 48px-high preview simultaneous names/numbers would stack beyond
	# its top edge. Present names after damage while real states/icons remain
	# immediate; this staging never changes combat rules or live PvP text.
	var notice: Dictionary = _announcements.pop_front()
	var actor: WandActor = notice.actor
	var effect := str(notice.effect)
	if not actor.has_status(effect) and not (effect == "barrier" and actor.shield > 0): return
	var popup := BuffAnnouncements.show(actor.sprite, str(notice.effect))
	_announcement_text = popup
	if popup != null:
		var bounds := popup.collision_rect()
		popup.position.x += clampf(bounds.position.x, 1, maxf(1, 63 - bounds.size.x)) - bounds.position.x

func _show_wand(selected: InventoryItem, level_value: int) -> void:
	var view := effects as LocalWandEffects
	view.shown_wand = selected
	view.shown_level = level_value

func _zap(selected: InventoryItem) -> void:
	if not _active or not _pending.is_empty(): return
	var plan := world.prepare(selected, warrior, rat.cell)
	if plan.has("error"): return
	_pending = "zap"
	var generation := _epoch
	if item.type_id == "WandOfMagicMissile": _show_wand(selected, int(plan.level))
	hero_sprite.face_cell(rat_sprite.cell)
	hero_sprite.play_action(&"zap")
	effects.play(plan, func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		world.resolve(plan)
		zaps_completed += 1
		cast_history.append({"type":selected.type_id, "level":plan.level, "cost":plan.cost,
			"damage":rat.max_hp - rat.hp, "magic_charge":warrior.has_status("magic_charge")})
		effects.sync_actor_states(0)
		if is_instance_valid(health_bar): health_bar.set_vitals(warrior.hp, warrior.max_hp, warrior.shield)
		_pending = "")

func _event(event: Dictionary) -> void:
	var actor: WandActor = event.get("actor")
	match event.action:
		"buff_added":
			if actor != null and BuffAnnouncements.is_announced(str(event.effect)):
				_announcements.append({"actor":actor, "effect":event.effect})
		"move":
			if actor == null or not is_instance_valid(actor.sprite): return
			var sprite := actor.sprite as DungeonHeroSprite
			var at := world.level.cell_coords(actor.cell) - Vector2i.ONE
			sprite.cell = at
			var tween := sprite.create_tween()
			tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(sprite, "position", Vector2(at * 16) + Vector2(8, 8), 0.15)
			_push_tweens.append(tween)
		"blast": effects.blast(int(event.cell))
		"burst": effects.burst(str(event.kind), effects.point(int(event.cell)), int(event.count))
		"damage":
			if actor == null or not is_instance_valid(actor.sprite): return
			var icon := CombatTextAssets.Icon.MAGIC_DMG
			if event.source == "burning": icon = CombatTextAssets.Icon.BURNING
			elif event.source == "corrosion": icon = CombatTextAssets.Icon.CORROSION
			elif event.source == "knockback": icon = CombatTextAssets.Icon.PHYS_DMG
			actor.sprite.show_damage(int(event.amount), icon)
			actor.sprite.flash()
		"shielding":
			if actor != null and is_instance_valid(actor.sprite):
				var layer := CombatTextLayer.for_actor(actor.sprite)
				var at := layer.to_local(actor.sprite.to_global(Vector2(0, -13)))
				layer.show_status(at, str(event.amount), Color.GREEN, CombatTextAssets.Icon.SHIELDING, world.level.cell_coords(actor.cell))
		"cast":
			if event.item.type_id == "WandOfCorrosion":
				effects.sound("gas")
				effects.burst("corrosion", effects.point(int(event.cell)), 10)
			var hit: WandActor = event.plan.get("hit_actor")
			if hit != null:
				if event.item.type_id in ["WandOfMagicMissile", "WandOfFrost"]: effects.sound("hit_magic")
				var kind: String = WandEffects.KIND.get(event.item.type_id, "rainbow")
				if event.item.type_id == "WandOfTransfusion": kind = "blood"
				effects.burst(kind, effects.actor_point(hit), 2 + int(event.plan.level / 2))
		_: super._event(event)
