# Local journal runestones: real inventory/throw rules and original nature effects.
extends "res://scripts/menu/seed_sandbox.gd"
const SeedPreview = preload("res://scripts/menu/seed_sandbox.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")

class LocalStoneEffects extends SeedPreview.LocalSeedEffects:
	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			if not actor.has_status("paralysis") or not is_instance_valid(actor.sprite): continue
			var columns := floori(BUFFS.get_width() / 7.0)
			draw_texture_rect_region(BUFFS,Rect2(actor_point(actor)+Vector2(-7,-14),Vector2(7,7)),Rect2((4%columns)*7,floori(4.0/columns)*7,7,7))

class PreviewSheep extends WandSummonSprite:
	func place(cell: Vector2i) -> void:
		super.place(cell)
		body.position.y = maxf(-13,-position.y)

var stone: InventoryItem
var selected_item: InventoryItem
var wand: InventoryItem
var target_cell := -1
var uses_completed := 0
var attacks_completed := 0
var lightning_arcs := 0
var sheep: Array[WandSummonSprite] = []
var equipment_sprite: Sprite2D
var caption: Label

func _make_effects() -> PotionEffects:
	return LocalStoneEffects.new()

func _reset_scene(next_mode: String) -> void:
	for sprite in sheep: sprite.free()
	sheep.clear()
	super._reset_scene(next_mode)
	world.rng.randomize()
	stone = item.copy_item()
	stone.quantity = 1
	selected_item = InventoryCatalog.create("Shortsword")
	warrior.data.melee_weapon = selected_item
	var from := Vector2i(0,2)
	var to := Vector2i(3,2)
	if item.type_id in ["StoneOfAugmentation","StoneOfEnchantment"]:
		from = Vector2i(1,2)
		to = Vector2i(2,2)
	world.move(warrior,world.level.cell_id(from+Vector2i.ONE))
	hero_sprite.place_cell(from)
	hero_sprite.body.speed_scale = 1
	hero_sprite.face_cell(to)
	if item.type_id in ["StoneOfBlast","StoneOfShock","StoneOfAugmentation"]:
		world.add_actor(rat,world.level.cell_id(to+Vector2i.ONE))
		rat_sprite.show()
		rat_sprite.place_cell(to)
		rat_sprite.face_cell(from)
		rat.defense_skill = 0
		rat.hp = 10000
		rat.max_hp = rat.hp
	target_cell = world.level.cell_id(Vector2i(3,1)+Vector2i.ONE) if item.type_id == "StoneOfShock" else world.level.cell_id(to+Vector2i.ONE)
	if item.type_id == "StoneOfFlock": target_cell = world.level.cell_id(Vector2i(2,2)+Vector2i.ONE)
	wand = InventoryCatalog.create("WandOfMagicMissile")
	WandState.initialize(wand)
	wand.charges = 0
	world.wands[warrior.get_instance_id()] = [wand]
	if equipment_sprite == null:
		equipment_sprite = Sprite2D.new()
		equipment_sprite.position = Vector2(8,12)
		map.add_child(equipment_sprite)
		caption = Label.new()
		caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		caption.add_theme_font_size_override("font_size",6)
		caption.add_theme_font_override("font",UiAssets.get_font_at_scale(2))
		UiAssets.apply_text_outline(caption)
		caption.position = Vector2(17,6)
		map.add_child(caption)
	equipment_sprite.visible = item.type_id in ["StoneOfAugmentation","StoneOfEnchantment","StoneOfShock"]
	caption.visible = equipment_sprite.visible
	caption.text = ""
	_refresh_equipment(wand if item.type_id == "StoneOfShock" else selected_item)
	world.events.clear()

func _refresh_equipment(value: InventoryItem) -> void:
	equipment_sprite.texture = ItemAssets.get_texture(value.visual)
	ItemGlow.apply(equipment_sprite,value)
	if item.type_id == "StoneOfShock": caption.text = "%d/%d" % [wand.charges,wand.max_charges]

func _start_cycle() -> void:
	_reset_scene("stone")
	history.clear()
	_steps.clear()
	if item.type_id == "StoneOfAugmentation":
		for choice in ["speed","damage"]:
			_steps.append({"kind":"use","choice":choice,"delay":0.85})
			for index in 3: _steps.append({"kind":"attack"})
	elif item.type_id == "StoneOfEnchantment":
		_steps.append({"kind":"use","delay":2.5})
		_steps.append({"kind":"armor","delay":0.5})
		_steps.append({"kind":"use","delay":2.5})
	else: _steps.append({"kind":"throw","delay":2.5})
	_steps.append({"kind":"hold","delay":1.2})
	_next = 0
	phase = "ready"
	_remaining = 0.65

func _execute(step: Dictionary) -> void:
	phase = str(step.kind)
	history.append({"kind":phase})
	match phase:
		"throw": _throw_stone()
		"use":
			var result := Nature.use_inventory(world as RingWorld,stone,warrior,selected_item,str(step.get("choice","")))
			if result.has("error"): return
			uses_completed += 1
			if item.type_id == "StoneOfAugmentation": caption.text = L10n.text("速度强化" if step.choice == "speed" else "伤害强化")
			_refresh_equipment(selected_item)
		"armor":
			selected_item = InventoryCatalog.create("ClothArmor")
			_refresh_equipment(selected_item)
		"attack":
			_pending = "attack"
			hero_sprite.play_action(&"attack")
			hero_sprite.body.speed_scale = 1.0/MeleeRules.delay(selected_item,warrior)

func _throw_stone() -> void:
	if not _active: return
	_pending = "throw"
	var generation := _epoch
	hero_sprite.face_cell(world.level.cell_coords(target_cell)-Vector2i.ONE)
	hero_sprite.play_action(&"zap")
	var ray := Ballistica.new(warrior.cell,target_cell,Ballistica.PROJECTILE,world.level)
	(effects as LocalStoneEffects).throw_item(stone,warrior,ray.collision_pos,func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		Nature.throw_stone(world as RingWorld,stone,warrior,ray.collision_pos)
		throws_completed += 1
		if item.type_id == "StoneOfShock": _refresh_equipment(wand)
		if item.type_id == "StoneOfFlock":
			for actor in world.actors:
				if actor.species != "sheep": continue
				var sprite := PreviewSheep.new()
				sprite.actor = actor
				actor.sprite = sprite
				map.add_child(sprite)
				sprite.place(world.level.cell_coords(actor.cell)-Vector2i.ONE)
				sheep.append(sprite)
		_pending = "")

func _action_finished(action: StringName) -> void:
	if not _active or _pending != "attack" or action != &"attack": return
	var result := (world as MeleeWorld).attack(warrior,rat)
	history.append({"kind":"hit","augment":selected_item.metadata.get("augment","none"),"damage":result.get("damage",0),"cost":result.get("cost",0)})
	rat.hp = rat.max_hp
	attacks_completed += 1
	hero_sprite.body.speed_scale = 1
	_pending = ""
	_remaining = 0.65*MeleeRules.delay(selected_item,warrior)

func _event(event: Dictionary) -> void:
	var view := effects as LocalStoneEffects
	match event.action:
		"nature_operate": hero_sprite.play_action(&"operate")
		"nature_enchant": view.enchant(event.actor,event.item,event.color)
		"nature_lightning":
			for arc in event.arcs:
				view.lightning(view.point(int(arc[0]),false),view.point(int(arc[1]),false))
				lightning_arcs += 1
		"melee_sound": view.sound(str(event.sound),float(event.pitch))
		"melee_hit": rat_sprite.flash()
		"damage":
			if event.actor != null and is_instance_valid(event.actor.sprite):
				event.actor.sprite.show_damage(int(event.amount),CombatTextAssets.Icon.PHYS_DMG if event.source == "physical" else CombatTextAssets.Icon.MAGIC_DMG)
		_: super._event(event)
