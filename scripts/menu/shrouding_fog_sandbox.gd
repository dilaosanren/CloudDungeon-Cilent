# PotionOfShroudingFog / SmokeScreen / Level.updateFieldOfView, SPD 4.0.2.
# Independent real fields and two player views; no simulated hiding shortcut.
extends "res://scripts/menu/potion_sandbox.gd"
const Locale = preload("res://scripts/menu/game_locale.gd")

var views: Array[DungeonVisibility] = []
var viewer := 0
var impact_cell := -1
var caption: Label
var sight_history: Array[Dictionary] = []
var _fog_landed := false

func _reset_scene(next_mode: String) -> void:
	_fog_landed = false
	viewer = 0
	super._reset_scene(next_mode)
	map.auto_refresh_visibility = false
	impact_cell = world.level.cell_id(Vector2i(3,2))
	views.clear()
	for seat in 2:
		var observation := DungeonVisibility.new()
		observation.set_map(RULES_SIZE,world.environment.terrain)
		views.append(observation)
	if not is_instance_valid(caption):
		caption = Label.new()
		caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.add_theme_font_override("font",UiAssets.get_font())
		caption.add_theme_font_size_override("font_size",6)
		UiAssets.apply_text_outline(caption)
		caption.position = Vector2(2,1)
		caption.z_index = 110 # Keep the view label readable above FogOfWar.
		map.add_child(caption)
	map.set_fog_enabled(true)
	_sync_views()

func _start_cycle() -> void:
	_reset_scene("throw")
	history.clear()
	sight_history.clear()
	_steps = [{"kind":"throw","delay":1.8},
		{"kind":"view","seat":1,"delay":2.2},
		{"kind":"tick","delay":0.8},{"kind":"tick","delay":0.8},
		{"kind":"view","seat":0,"delay":2.2},
		{"kind":"hold","delay":1.2}]
	_next = 0
	_remaining = 1.0
	phase = "ready"

func _process(delta: float) -> void:
	if is_instance_valid(caption): caption.text = Locale.text("投掷前" if not _fog_landed else "己方视角" if viewer == 0 else "对方视角")
	super._process(delta)

func _execute(step: Dictionary) -> void:
	if step.kind == "view":
		phase = "view"
		viewer = int(step.seat)
	else: super._execute(step)
	_sync_views()

func _throw() -> void:
	_pending = "throw"
	var generation := _epoch
	hero_sprite.face_cell(world.level.cell_coords(impact_cell)-Vector2i.ONE)
	hero_sprite.play_action(&"zap")
	effects.throw_potion(item,warrior,impact_cell,func():
		if not _active or generation != _epoch or not is_inside_tree(): return
		world.on_throw(item,impact_cell)
		throws_completed += 1
		_fog_landed = true
		_pending = ""
		_sync_views())

func _sync_views() -> void:
	if views.size() != 2: return
	for seat in 2:
		var observer := warrior if seat == 0 else rat
		# Match PvpArenaWorld.observe_hero: neither player's observer is the
		# native ally exception, regardless of the current actor perspective.
		views[seat].observe(world.level.cell_coords(observer.cell),world.environment,8,
			{"alignment":"p%d" % seat,"species":"hero","reveal_cells":world.reveal_for(observer)})
	var active := views[viewer]
	map.visibility_state.visible.fill(0)
	map.visibility_state.visited.fill(0)
	for y in GRID_SIZE.y:
		for x in GRID_SIZE.x:
			var c := world.level.cell_id(Vector2i(x+1,y+1))
			map.visibility_state.visible[x+y*GRID_SIZE.x] = active.visible[c]
			map.visibility_state.visited[x+y*GRID_SIZE.x] = active.visited[c]
	map._apply_visibility()
	# Renderer is bound to the padded rules grid, while fog draws the crop.
	map.environment_renderer.visible_cells = active.visible.duplicate()
	hero_sprite.visible = bool(active.visible[warrior.cell])
	rat_sprite.visible = bool(active.visible[rat.cell])
	world.visible = active.visible.duplicate()
	if _fog_landed:
		sight_history.append({"viewer":viewer,"hero_visible":hero_sprite.visible,
			"rat_visible":rat_sprite.visible,"turn":world.environment.turn})
