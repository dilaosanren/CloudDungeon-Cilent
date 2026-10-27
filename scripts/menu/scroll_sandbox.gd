# Local journal demonstrations using real ScrollWorld rules and SPD effects.
extends "res://scripts/menu/potion_sandbox.gd"
const StatueSprite = preload("res://scripts/menu/equipment_statue_sprite.gd")

class PreviewWorld extends MeleeWorld:
	var disarm_inventory: DungeonInventory
	var disarm_target: WandActor
	func apply_terror(hero: WandActor) -> void:
		# Match the PvP disarm rule, applied to a statue's local inventory.
		if disarm_target != null and visible[disarm_target.cell] and disarm_target != hero:
			disarm_inventory.disarm_weapon(level.cell_coords(disarm_target.cell))
	func dispose() -> void:
		disarm_inventory = null
		disarm_target = null
		super.dispose()

class LocalScrollEffects extends ScrollEffects:
	const SMALL_BUFFS = preload("res://assets/ui/source/buffs.png")
	const UI_ICONS = preload("res://assets/ui/source/icons.png")
	var display_item: InventoryItem
	var display_caption := ""
	var display_left := 0.0
	func _ready() -> void:
		super._ready()
		# The real effect flashes the full viewport. Keep this preview's flash
		# inside its 4x3 map and under the window's normal clipping instead.
		var canvas := _flash.get_parent()
		_flash.reparent(self)
		canvas.queue_free()
		_flash.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_flash.position = Vector2.ZERO
		_flash.size = Vector2(64, 48)
	func point(cell: int, raised: bool = true) -> Vector2:
		return super.point(cell, raised) - Vector2(16, 16)
	func appear(actor: WandActor, old_cell: int) -> void:
		super.appear(actor, old_cell)
		if actor.sprite is DungeonHeroSprite:
			actor.sprite.place_cell(world.level.cell_coords(actor.cell) - Vector2i.ONE)
	func advance(delta: float) -> void:
		super.advance(delta)
		display_left = maxf(0, display_left - delta)
	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			if not is_instance_valid(actor.sprite) or not actor.sprite.visible: continue
			if actor.has_status("magical_sleep"):
				# Original Icons.SLEEP crop and EmoIcon.Sleep pulse.
				var pulse := 1.1 + sin(Time.get_ticks_msec() / 400.0) * 0.1
				draw_texture_rect_region(UI_ICONS, Rect2(actor_point(actor) + Vector2(2, -16), Vector2(9, 8) * pulse), Rect2(7, 88, 9, 8))
			var left := actor_point(actor) + Vector2(-8, -15)
			for spec in [["blindness", 16], ["paralysis", 4]]:
				if not actor.has_status(spec[0]): continue
				var id := int(spec[1])
				var columns := floori(SMALL_BUFFS.get_width() / 7.0)
				draw_texture_rect_region(SMALL_BUFFS, Rect2(left, Vector2(7, 7)), Rect2((id % columns) * 7, floori(float(id) / columns) * 7, 7, 7))
				left.x += 8
		if display_item != null and display_left > 0:
			var texture := ItemAssets.get_texture(display_item.visual)
			var color := Color(1, 1, 1, minf(1, display_left * 2))
			draw_texture(texture, Vector2(8, 12) - texture.get_size() / 2, color)
			SpdPixelText.draw(self, Vector2(13, 13), display_caption, Color(1, 1, 0.27, color.a))
	func clear() -> void:
		super.clear()
		display_item = null
		display_left = 0

var rules: PreviewWorld
var owned_inventory: DungeonInventory
var target_inventory: DungeonInventory
var selected_item: InventoryItem
var wand: InventoryItem
var mirrors: Array[ScrollMirrorSprite] = []
var dropped_weapon: DungeonItemSprite
var reads_completed := 0
var zaps_completed := 0
var mirror_attacks := 0
var drop_count := 0
var teleport_cells: Array[int] = []

func _make_world() -> PotionWorld:
	return PreviewWorld.new()

func _make_effects() -> PotionEffects:
	return LocalScrollEffects.new()

func _make_target_sprite() -> DungeonHeroSprite:
	return StatueSprite.new() if item.type_id == "ScrollOfTerror" else RatSprite.new()

func _reset_scene(next_mode: String) -> void:
	for sprite in mirrors: sprite.free()
	mirrors.clear()
	if is_instance_valid(dropped_weapon): dropped_weapon.free()
	dropped_weapon = null
	super._reset_scene(next_mode)
	rules = world as PreviewWorld
	# Vary only the local preview seed, allowing repeated teleports to differ.
	rules.rng.randomize()
	rat.max_hp = 1000000
	rat.hp = rat.max_hp
	rat.defense_skill = 0
	warrior.data.hero_class = "warrior"
	warrior.hp = 14 if item.type_id == "ScrollOfRetribution" else 70
	owned_inventory = DungeonInventory.new()
	owned_inventory.bind_actor(warrior)
	rules.inventory = owned_inventory
	selected_item = InventoryCatalog.create("Shortsword" if item.type_id == "ScrollOfTransmutation" else "WornShortsword")
	selected_item.level = 2 if item.type_id == "ScrollOfTransmutation" else 0
	owned_inventory.collect(selected_item)
	owned_inventory.equip(selected_item)
	wand = InventoryCatalog.create("WandOfMagicMissile")
	wand.charges = 0
	owned_inventory.collect(wand)
	rules.carry(warrior, [wand])
	target_inventory = DungeonInventory.new()
	target_inventory.bind_actor(rat)
	if item.type_id == "ScrollOfTerror":
		rat.species = "statue"
		# Leave room beside the statue for its dropped sword to remain legible.
		rules.move(rat, rules.level.cell_id(Vector2i(3, 3)))
		rat_sprite.place_cell(Vector2i(2, 2))
		var weapon := InventoryCatalog.create("Sword")
		target_inventory.collect(weapon)
		target_inventory.equip(weapon)
		rules.disarm_inventory = target_inventory
		rules.disarm_target = rat
		target_inventory.dropped.connect(_weapon_dropped)
	rat_sprite.visible = item.type_id not in ["ScrollOfTeleportation", "ScrollOfTransmutation", "ScrollOfUpgrade"]
	if item.type_id in ["ScrollOfTransmutation", "ScrollOfUpgrade", "ScrollOfRecharging"]: _show_selected()

func _start_cycle() -> void:
	_reset_scene("read")
	history.clear()
	_steps = [{"kind":"read"}]
	_next = 0
	phase = "ready"
	_remaining = 0.65
	match item.type_id:
		"ScrollOfLullaby": _ticks(7)
		"ScrollOfMirrorImage": _ticks(9)
		"ScrollOfRecharging":
			_ticks(4)
			_steps.append({"kind":"zap", "delay":0.8})
			_ticks(4)
			_steps.append({"kind":"zap", "delay":0.8})
		"ScrollOfRetribution":
			_steps.append({"kind":"hold", "delay":2.5})
		"ScrollOfTeleportation":
			for repeat in 2:
				_steps.append({"kind":"hold", "delay":1.5})
				_steps.append({"kind":"read"})
		_:
			_steps.append({"kind":"hold", "delay":2.5})
	_steps.append({"kind":"hold", "delay":1.5})

func _execute(step: Dictionary) -> void:
	phase = str(step.kind)
	history.append({"kind":phase})
	match phase:
		"read":
			_pending = "read"
			hero_sprite.face_cell(rat_sprite.cell)
			hero_sprite.play_action(&"read")
			rules.apply_scroll(item, warrior, selected_item)
			if item.type_id not in ["ScrollOfLullaby", "ScrollOfRetribution"]: effects.sound("read")
			if item.type_id == "ScrollOfTransmutation": selected_item = owned_inventory.equipment.weapon
			if item.type_id in ["ScrollOfUpgrade", "ScrollOfRecharging"]: _show_selected()
			effects.sync_actor_states(0)
		"tick":
			hero_sprite.show_status(Color.WHITE, "...")
			rules.spend(1)
			for actor in rules.actors:
				if actor.species != "mirror_image": continue
				var sprite := actor.sprite as DungeonHeroSprite
				var cell := rules.level.cell_coords(actor.cell) - Vector2i.ONE
				if sprite.cell != cell: sprite.walk_to_cell(cell, 0.2)
			if item.type_id == "ScrollOfRecharging": _show_selected()
			rules.events.clear()
			rules.environment.events.clear()
		"zap": _zap()

func _show_selected() -> void:
	var view := effects as LocalScrollEffects
	view.display_item = wand if item.type_id == "ScrollOfRecharging" else selected_item
	view.display_caption = "%d/%d" % [wand.charges, wand.max_charges] if item.type_id == "ScrollOfRecharging" else "+%d" % selected_item.level
	view.display_left = 2.2

func _zap() -> void:
	var plan := rules.prepare(wand, warrior, rat.cell)
	if plan.has("error"): return
	_pending = "zap"
	var generation := _epoch
	hero_sprite.face_cell(rat_sprite.cell)
	hero_sprite.play_action(&"zap")
	effects.play(plan, func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		rules.resolve(plan)
		zaps_completed += 1
		_show_selected()
		_pending = "")

func _action_finished(action: StringName) -> void:
	if _pending != "read" or action != &"read": return
	reads_completed += 1
	_pending = ""

func _weapon_dropped(weapon: InventoryItem, cell: Vector2i) -> void:
	drop_count += 1
	dropped_weapon = DungeonItemSprite.new()
	map.add_child(dropped_weapon)
	dropped_weapon.set_item(weapon)
	dropped_weapon.place(cell - Vector2i.ONE)
	dropped_weapon.drop()
	# Keep the source ground-item bounce, with a small display offset beside
	# the feet. The actual heap cell is still exactly the statue's cell.
	dropped_weapon.position.x += 7
	map.move_child(dropped_weapon, rat_sprite.get_index())

func _event(event: Dictionary) -> void:
	var actor: WandActor = event.get("actor")
	var view := effects as LocalScrollEffects
	match event.action:
		"scroll_specks": view.start_specks(actor, int(event.cell), str(event.kind), float(event.interval), int(event.count), bool(event.center))
		"scroll_flare": view.scroll_flare(actor, event.color, int(event.rays))
		"scroll_flash": view.flash(event.color)
		"scroll_teleport":
			view.appear(actor, int(event.from))
			if actor == warrior: teleport_cells.append(actor.cell)
		"transmutation":
			view.display_left = 0
			view.transmute(actor, event.old, event.new)
		"mirror_spawn":
			var sprite := ScrollMirrorSprite.new()
			sprite.actor = actor
			map.add_child(sprite)
			actor.sprite = sprite
			sprite.place_cell(rules.level.cell_coords(actor.cell) - Vector2i.ONE)
			mirrors.append(sprite)
		"mirror_attack":
			mirror_attacks += 1
			var sprite := actor.sprite as DungeonHeroSprite
			sprite.face_cell(rat_sprite.cell)
			sprite.play_action(&"attack")
			view.sound("hit")
		"damage":
			if actor != null and actor.sprite is DungeonHeroSprite:
				actor.sprite.show_damage(int(event.amount), CombatTextAssets.Icon.PHYS_DMG if event.source == "physical" else CombatTextAssets.Icon.MAGIC_DMG)
				actor.sprite.flash()
		_:
			super._event(event)
