# PotionOfSnapFreeze: a real thrown potion, instant freeze and roots, no blob.
extends "res://scripts/menu/potion_sandbox.gd"

class SnapEffects extends LocalEffects:
	const BUFFS = preload("res://assets/ui/source/buffs.png")
	func _draw() -> void:
		super._draw()
		if world == null: return
		for actor in world.actors:
			if not is_instance_valid(actor.sprite) or not actor.sprite.visible: continue
			var at := actor_point(actor)+Vector2(-7,-14)
			for effect in ["frost","roots"]:
				if not actor.has_status(effect): continue
				var id := 15 if effect == "frost" else 11
				var columns := floori(BUFFS.get_width()/7.0)
				draw_texture_rect_region(BUFFS,Rect2(at,Vector2(7,7)),Rect2((id%columns)*7,floori(float(id)/columns)*7,7,7),Color(0,0.75,1) if effect == "frost" else Color.WHITE)
				at.x += 8

var impact_cell := -1
var _announcements: Array[Dictionary] = []
var _announcement_text: CombatFloatingText

func _make_effects() -> PotionEffects:
	return SnapEffects.new()

func set_active(value: bool) -> void:
	_announcements.clear()
	_announcement_text = null
	super.set_active(value)

func _reset_scene(next_mode: String) -> void:
	_announcements.clear()
	_announcement_text = null
	super._reset_scene(next_mode)
	# Center the 3x3 splash inside the twelve-cell floor. The rat remains in
	# the bottom row so frozen/rooted names have room above its sprite.
	world.move(rat,world.level.cell_id(Vector2i(3,3)))
	rat_sprite.place_cell(Vector2i(2,2))
	hero_sprite.face_cell(rat_sprite.cell)
	impact_cell = world.level.cell_id(Vector2i(3,2))
	if next_mode == "water": world.environment.set_terrain(rat.cell,DungeonTerrain.Type.WATER)

func _start_cycle() -> void:
	_reset_scene("ground")
	history.clear()
	_steps = [{"kind":"throw"},{"kind":"hold","delay":1.5},
		{"kind":"scene","mode":"water"},{"kind":"throw"},{"kind":"hold","delay":1.5}]
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

func _throw() -> void:
	_pending = "throw"
	var generation := _epoch
	hero_sprite.play_action(&"zap")
	effects.throw_potion(item,warrior,impact_cell,func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		world.on_throw(item,impact_cell)
		throws_completed += 1
		history.append({"kind":"impact","mode":mode,"frost":rat.statuses.get("frost",0),"roots":rat.statuses.get("roots",0)})
		effects.sync_actor_states(0)
		_pending = "")

func _event(event: Dictionary) -> void:
	if event.action == "buff_added":
		var actor: WandActor = event.get("actor")
		if actor != null and BuffAnnouncements.is_announced(str(event.effect)):
			_announcements.append({"actor":actor,"effect":event.effect})
	else: super._event(event)
