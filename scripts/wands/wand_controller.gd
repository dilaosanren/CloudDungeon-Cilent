## Connects turn-based wand rules to the existing dungeon, hero, inventory and floating text.
class_name WandController
extends Node2D
signal finished(item: InventoryItem)
signal rejected(reason: String)
signal updated
var world: WandWorld
var effects: WandEffects
var dungeon: DungeonMap
var busy := false
var _pending: Dictionary = {}
var _generation := 0

func _exit_tree() -> void:
	cancel()
	if world != null: world.dispose()

func bind(map: DungeonMap) -> void:
	dungeon = map
	if get_parent() == map: map.move_child(self, map.fog_renderer.get_index())
	world = WandWorld.new()
	world.bind(map.environment, map.ballistic_level)
	world.event.connect(_event)
	effects = WandEffects.new()
	effects.world = world
	add_child(effects)

func cast(item: InventoryItem, caster: WandActor, target: int) -> bool:
	if busy: rejected.emit("正在施法"); return false
	if dungeon.fog_enabled:
		world.visible = dungeon.visibility_state.visible.duplicate()
		world.discoverable = dungeon.visibility_state.discoverable.duplicate()
		world.view_distance = dungeon.visibility_state.view_distance
		for cell in world.mapped.size(): world.mapped[cell] |= dungeon.visibility_state.mapped[cell] | dungeon.visibility_state.visited[cell]
	var p := world.prepare(item, caster, target)
	if p.has("error"): rejected.emit(p.error); return false
	busy = true
	_pending = p
	var generation := _generation
	if is_instance_valid(caster.sprite) and caster.sprite is DungeonHeroSprite:
		caster.sprite.face_cell(world.level.cell_coords(p.bolt.collision_pos))
		caster.sprite.play_action(&"zap")
	effects.play(p, func():
		if generation != _generation: return
		world.resolve(p)
		_pending = {}
		busy = false
		finished.emit(item)
		updated.emit())
	return true

func step_turn() -> bool:
	if busy: return false
	world.step_turn()
	updated.emit()
	return true

func cancel() -> void:
	_generation += 1
	_pending = {}
	busy = false
	if effects != null: effects.clear()

func _event(e: Dictionary) -> void:
	var a: WandActor = e.get("actor")
	match e.action:
		"buff_added":
			if a != null: BuffAnnouncements.show(a.sprite, str(e.effect))
		"summon":
			var sprite := WandSummonSprite.new()
			sprite.actor = a
			dungeon.add_child(sprite)
			dungeon.move_child(sprite, dungeon.layers["RaisedGrass"].get_index())
			a.sprite = sprite
			sprite.place(world.level.cell_coords(a.cell))
			dungeon.track_visibility(sprite, world.level.cell_coords(a.cell))
			effects.burst("ward" if a.species == "ward" else "earth", effects.actor_point(a), 8)
		"ward_update":
			if is_instance_valid(a.sprite): a.sprite.refresh()
			effects.burst("ward", effects.actor_point(a), a.data.tier)
		"move":
			if is_instance_valid(a.sprite):
				dungeon.track_visibility(a.sprite, world.level.cell_coords(a.cell))
				if a.sprite is WandSummonSprite: a.sprite.move_to(world.level.cell_coords(a.cell))
				elif a.sprite is DungeonHeroSprite:
					var tween := a.sprite.create_tween()
					tween.tween_property(a.sprite, "position", Vector2(world.level.cell_coords(a.cell) * 16) + Vector2(8, 8), 0.15)
					a.sprite.cell = world.level.cell_coords(a.cell)
				else: a.sprite.position = Vector2(world.level.cell_coords(a.cell) * 16) + Vector2(8, 8)
		"blast": effects.blast(e.cell)
		"burst": effects.burst(e.kind, effects.point(e.cell), e.count)
		"damage":
			_show(a, e.amount, "damage", e.source)
		"healing", "shielding": _show(a, e.amount, e.action)
		"ward_zap":
			effects.beam("death", effects.actor_point(a), effects.actor_point(e.target), 0.5)
			effects.sound("ray")
		"guardian_attack":
			if is_instance_valid(a.sprite): a.sprite.attack(e.target.sprite.global_position if is_instance_valid(e.target.sprite) else effects.point(e.target.cell))
		"dodge":
			if is_instance_valid(a.sprite) and a.sprite.has_method("show_dodge"): a.sprite.show_dodge()
		"death":
			if is_instance_valid(a.sprite):
				if a.sprite is WandSummonSprite: a.sprite.die()
				elif a.sprite is DungeonHeroSprite: a.sprite.play_action(&"die")
				else: a.sprite.hide()
		"mapping":
			var revealed: Array[int] = []
			for cell in world.mapped.size():
				if world.mapped[cell]: revealed.append(cell)
			dungeon.visibility_state.map_cells(revealed)
		"cast":
			if e.item.type_id == "WandOfCorrosion": effects.sound("gas"); effects.burst("corrosion", effects.point(e.cell), 10)
			var hit: WandActor = e.plan.get("hit_actor")
			if hit != null:
				if e.item.type_id in ["WandOfMagicMissile", "WandOfFrost", "WandOfLivingEarth", "WandOfCorruption"]:
					var pitch: float = 1.1 if e.item.type_id == "WandOfFrost" else 0.8 if e.item.type_id == "WandOfCorruption" else 0.9 if e.item.type_id == "WandOfLivingEarth" else 1.0
					effects.sound("hit_magic", pitch * effects.rng.randf_range(0.87, 1.15))
				var kind: String = WandEffects.KIND.get(e.item.type_id, "rainbow")
				if e.item.type_id == "WandOfPrismaticLight": kind = "shadow" if "undead" in hit.properties or "demonic" in hit.properties else "rainbow"
				if e.item.type_id == "WandOfTransfusion": kind = "blood"
				if e.item.type_id != "WandOfWarding": effects.burst(kind, effects.actor_point(hit), 2 + int(e.plan.level / 2))
	updated.emit()

func _show(a: WandActor, amount: int, kind: String, source: String = "") -> void:
	if amount <= 0 or not is_instance_valid(a.sprite) or not a.sprite.visible: return
	var layer := CombatTextLayer.for_actor(a.sprite)
	var pos := layer.to_local(a.sprite.to_global(Vector2(0, -13)))
	var cell := world.level.cell_coords(a.cell)
	match kind:
		"damage":
			var icon := CombatTextAssets.Icon.MAGIC_DMG
			if source == "burning": icon = CombatTextAssets.Icon.BURNING
			elif source == "corrosion": icon = CombatTextAssets.Icon.CORROSION
			elif source == "corruption": icon = CombatTextAssets.Icon.CORRUPTION
			elif source == "poison": icon = CombatTextAssets.Icon.POISON
			elif source == "bleeding": icon = CombatTextAssets.Icon.BLEEDING
			elif source == "toxic_gas": icon = CombatTextAssets.Icon.TOXIC
			elif source == "electricity": icon = CombatTextAssets.Icon.SHOCKING
			elif source in ["physical", "knockback", "fall", "ward_cost"]: icon = CombatTextAssets.Icon.PHYS_DMG
			layer.show_damage(pos, amount, icon, cell)
		"healing": layer.show_status(pos, str(amount), Color.GREEN, CombatTextAssets.Icon.HEALING, cell)
		"shielding": layer.show_status(pos, str(amount), Color.GREEN, CombatTextAssets.Icon.SHIELDING, cell)
