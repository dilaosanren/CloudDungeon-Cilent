# Original MissileSprite / Splash / Speck / SpellSprite / Flare equations.
# Source art is unchanged. GPL-3.0-or-later.
class_name PotionEffects
extends WandEffects
const SPECKS = preload("res://assets/effects/specks.png")
const SPELLS = preload("res://assets/potions/source/spell_icons.png")
const ICE_SHADER = preload("res://scripts/potions/potion_tint.gdshader")
const Glow = preload("res://scripts/items/item_glow.gd")
var flights: Array[Dictionary] = []
var flecks: Array[Dictionary] = []
var spells: Array[Dictionary] = []
var flares: Array[Dictionary] = []
var emission_clocks: Dictionary = {}
var visual_states: Dictionary = {}
var snow_emitters: Array[Dictionary] = []
var breaths: Array[Dictionary] = []
var finish_actions := false
var _gradient: ImageTexture
var _flare_canvas: Node2D

func _ready() -> void:
	super._ready()
	var image := Image.create(5, 1, false, Image.FORMAT_RGBA8)
	var colors := [Color.WHITE, Color(1, 1, 1, 187.0 / 255), Color(1, 1, 1, 136.0 / 255), Color(0, 1, 1, 0), Color(1, 1, 1, 0)]
	for i in 5: image.set_pixel(i, 0, colors[i])
	_gradient = ImageTexture.create_from_image(image)
	_flare_canvas = Node2D.new(); _flare_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_flare_canvas.material = light.material; _flare_canvas.draw.connect(_draw_flares)
	add_child(_flare_canvas)

func sound(name: String, pitch: float = 1.0) -> void:
	var path := "res://assets/potions/source/%s.mp3" % name
	if not ResourceLoader.exists(path): super.sound(name, pitch); return
	if not sound_enabled or not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var player := AudioStreamPlayer.new(); player.stream = load(path); player.pitch_scale = pitch
	player.bus = &"SFX"
	if name == "miss": player.volume_db = linear_to_db(0.6)
	add_child(player); player.finished.connect(player.queue_free); player.play()

func throw_potion(item: InventoryItem, caster: WandActor, cell: int, callback: Callable, anchors: Dictionary = {}) -> void:
	var start: Vector2 = anchors.get("start", actor_point(caster))
	var end: Vector2 = anchors.get("end", endpoint(cell))
	var d := end - start
	var angle := deg_to_rad(135 - atan2(d.x, d.y) / 3.1415926 * 180)
	var left := d.x < 0
	if left: angle += PI / 2
	var flight := {"start": start, "end": end, "age": 0.0, "duration": d.length() / 240,
		"texture": ItemAssets.get_texture(item.visual), "angle": angle, "spin": -TAU * 2 if left else TAU * 2,
		"flip": left, "callback": callback, "cell": cell}
	_add_item_flight(flight, item)
	history.append({"kind": "potion_throw", "start": start, "end": end, "duration": flight.duration, "spin": flight.spin, "flip": left})
	sound("miss", 1.5)

## Isolate enchanted projectile pixels from particles and other effects.
func _add_item_flight(flight: Dictionary, item: InventoryItem) -> void:
	flights.append(flight)
	if Glow.profile(item).is_empty(): return
	var sprite := Sprite2D.new()
	sprite.texture = flight.texture
	add_child(sprite)
	move_child(sprite, 0)
	Glow.apply(sprite, item)
	flight.sprite = sprite
	_update_item_flight(flight)

func _update_item_flight(flight: Dictionary) -> void:
	var sprite: Sprite2D = flight.get("sprite")
	if not is_instance_valid(sprite): return
	sprite.position = flight.start.lerp(flight.end, minf(1, flight.age / maxf(0.00001, flight.duration)))
	sprite.rotation = flight.angle + flight.spin * flight.age
	sprite.scale = Vector2(-1 if flight.flip else 1, 1)
	var fade := float(flight.get("fade_time", 0))
	sprite.modulate.a = minf(1, flight.age / fade) if fade > 0 else 1.0

func splash_at(pos: Vector2, color: Color, count: int = 5) -> void:
	for i in count:
		flecks.append({"kind": "splash", "pos": pos, "age": 0.0, "life": rng.randf_range(0.5, 1),
			"velocity": Vector2.from_angle(rng.randf_range(-PI, 0)) * rng.randf_range(40, 80), "acc": Vector2(0, 100),
			"color": color, "angle": 0.0, "spin": 0.0, "frame": -1, "light": false})

func potion_color(item: InventoryItem) -> Color:
	# ItemSprite.pick(image,5,9), sampled in the original 16px cell.
	var texture := ItemAssets.get_texture(item.visual)
	var source := texture.get_image()
	return source.get_pixel(5, 9) if source != null and source.get_width() > 5 and source.get_height() > 9 else Color("00aaff")

func speck(kind: String, pos: Vector2, count: int = 1) -> void:
	for i in count:
		var p := {"kind": kind, "pos": pos, "age": 0.0, "life": 1.0, "velocity": Vector2.ZERO,
			"acc": Vector2.ZERO, "color": Color.WHITE, "angle": 0.0, "spin": 0.0, "frame": 0, "light": false}
		match kind:
			"healing": p.velocity = Vector2(0, -20)
			"jet": p.frame = 13; p.life = 0.5; p.velocity = Vector2(0, 32); p.acc = Vector2(0, -64); p.angle = rng.randf_range(0, TAU); p.spin = rng.randf_range(PI, TAU)
			"discover": p.frame = 2; p.life = 0.5; p.angle = rng.randf_range(0, TAU); p.spin = PI / 2
			"snow": p.frame = -1; p.life = 1.2; p.velocity = Vector2(0, rng.randf_range(5, 8)); p.pos -= p.velocity * p.life
			"wool": p.frame = 7; p.life = 0.5; p.velocity = Vector2(0, -50); p.angle = rng.randf_range(0, TAU); p.spin = rng.randf_range(-TAU, TAU)
		flecks.append(p)

# Freezing.affect: six native SnowParticles at 0.2-second intervals per cell.
func snow_at(cell: int, count: int = 6, interval: float = 0.2) -> void:
	snow_emitters.append({"cell":cell, "left":count, "interval":maxf(0.001,interval), "clock":0.0})
	history.append({"kind":"instant_freeze_snow", "cell":cell, "count":count, "interval":interval})

func spell(a: WandActor, index: int, color: Color) -> void:
	spells = spells.filter(func(p): return p.actor != a)
	if is_instance_valid(a.sprite) and a.sprite.visible: spells.append({"actor": a, "index": index, "color": color, "age": 0.0})

func flare(a: WandActor, color: Color = Color.YELLOW) -> void:
	flares.append({"actor": a, "color": color, "age": 0.0, "pos": actor_point(a)})

func _actor_body(a: WandActor) -> CanvasItem:
	if not is_instance_valid(a.sprite): return null
	if a.sprite is DungeonHeroSprite or a.sprite is WandSummonSprite: return a.sprite.body
	return a.sprite

func sync_actor_states(delta: float) -> void:
	if world == null: return
	for a in world.actors:
		var body := _actor_body(a)
		if body == null: continue
		if a.sprite is DungeonHeroSprite: a.sprite.flying = a.flying
		var id := a.get_instance_id()
		if not visual_states.has(id): visual_states[id] = {"invis": 0.0, "freeze_age": 0.0, "frozen": false, "paused": false}
		var state: Dictionary = visual_states[id]
		if a.has_status("invisibility"): state.invis = minf(1, state.invis + delta / 0.4)
		else: state.invis = 0.0
		body.modulate.a = lerpf(1, 0.4, state.invis)
		var frozen := a.has_status("frost")
		if frozen:
			state.freeze_age += delta
			if not state.frozen or not body.material is ShaderMaterial or body.material.shader != ICE_SHADER:
				var material := ShaderMaterial.new()
				material.shader = ICE_SHADER
				body.material = material
			body.material.set_shader_parameter("strength", minf(1, state.freeze_age * 2) * 0.6)
		elif state.frozen:
			body.material = null; state.freeze_age = 0.0
			if a.sprite.visible: splash_at(actor_point(a), Color("b2d6ff"), 5); sound("shatter")
		state.frozen = frozen
		var paused := not finish_actions and a.hp > 0 and (frozen or a.has_status("paralysis") or a.has_status("magical_sleep"))
		if body is AnimatedSprite2D:
			if paused: body.pause()
			elif state.paused: body.play()
		state.paused = paused
		if not a.sprite.visible or a.hp <= 0: continue
		for kind in ["healing", "jet", "burning", "snow"]:
			var active: bool = a.has_status("healing") if kind == "healing" else a.has_status("levitation") if kind == "jet" else a.has_status("burning") if kind == "burning" else a.has_status("chill")
			var key: String = str(id) + kind
			if not active: emission_clocks.erase(key); continue
			var interval := 0.5 if kind == "healing" else 0.02 if kind == "jet" else 0.06 if kind == "burning" else 0.1
			var clock := float(emission_clocks.get(key, rng.randf_range(0, interval))) + minf(delta, 0.1)
			while clock >= interval:
				clock -= interval
				var pos := actor_point(a) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-7.5, 7.5))
				if kind == "burning": _emit_particle("flame", pos, pos)
				else: speck(kind, pos)
			emission_clocks[key] = clock

func is_presenting_action() -> bool:
	return super.is_presenting_action() or not flights.is_empty() or not spells.is_empty() or not flares.is_empty() or not breaths.is_empty()

func breathe(actor: WandActor, visual: Dictionary, callback: Callable) -> void:
	breaths.append({"actor":actor,"visual":visual,"callback":callback,"launched":false})
	if is_instance_valid(actor.sprite) and actor.sprite is DungeonHeroSprite: actor.sprite.play_action(&"operate")
	sound("drink")
	history.append({"kind":"breath_drink"})

func _launch_breath(breath: Dictionary) -> void:
	breath.launched = true
	var actor: WandActor = breath.actor
	var visual: Dictionary = breath.visual
	if is_instance_valid(actor.sprite) and actor.sprite is DungeonHeroSprite:
		actor.sprite.face_cell(world.level.cell_coords(int(visual.to)))
		actor.sprite.play_action(&"zap")
	var start := actor_point(actor)
	for ray in visual.rays: missile("flame",start,point(int(ray.end)),Callable(),200,10,0.03)
	# Native FIRE_CONE resolves when its dedicated half-distance missile
	# arrives; outer tip rays continue displaying without repeated impacts.
	missile("flame",start,point(int(visual.midpoint)),func():
		if breath not in breaths: return
		breaths.erase(breath)
		if breath.callback.is_valid(): breath.callback.call(),200,10,0.03)
	sound("burning")
	history.append({"kind":"dragon_breath","rays":visual.rays.size(),"midpoint":visual.midpoint})

func advance(delta: float) -> void:
	super.advance(delta)
	for breath in breaths.duplicate():
		if breath.launched: continue
		var sprite: Node2D = breath.actor.sprite
		if is_instance_valid(sprite) and sprite is DungeonHeroSprite and sprite._action_in_progress: continue
		_launch_breath(breath)
	sync_actor_states(delta)
	for emitter in snow_emitters.duplicate():
		emitter.clock += delta
		while emitter.clock >= emitter.interval and emitter.left > 0:
			emitter.clock -= emitter.interval
			emitter.left -= 1
			var at := point(int(emitter.cell),false)+Vector2(rng.randf_range(-8,8),rng.randf_range(-8,8))
			speck("snow",at)
		if emitter.left <= 0: snow_emitters.erase(emitter)
	for flight in flights.duplicate():
		flight.age += delta
		if flight.age >= flight.duration:
			flights.erase(flight)
			if is_instance_valid(flight.get("sprite")): flight.sprite.queue_free()
			if flight.callback.is_valid(): flight.callback.call()
		else: _update_item_flight(flight)
	for p in flecks.duplicate():
		p.age += delta
		if p.age >= p.life: flecks.erase(p); continue
		p.pos += p.velocity * delta; p.velocity += p.acc * delta; p.angle += p.spin * delta
	for spell_data in spells.duplicate():
		spell_data.age += delta
		if spell_data.age >= 1.4: spells.erase(spell_data)
	for flare_data in flares.duplicate():
		flare_data.age += delta
		if flare_data.age >= flare_data.get("duration", 2): flares.erase(flare_data)
	queue_redraw()
	if light != null: light.queue_redraw()
	if _flare_canvas != null: _flare_canvas.queue_redraw()

func _draw() -> void:
	super._draw()
	_draw_flecks(self, false)
	for flight in flights:
		if is_instance_valid(flight.get("sprite")): continue
		var pos: Vector2 = flight.start.lerp(flight.end, minf(1, flight.age / maxf(0.00001, flight.duration)))
		var tex: Texture2D = flight.texture
		# MissileSprite.originToCenter + Image.flipHorizontal: mirror about the
		# same centered pivot, then rotate. A negative draw rect only flips the
		# texture; moving its origin to +width/2 made it orbit the flight path.
		var mirror := Vector2(-1 if flight.flip else 1, 1)
		draw_set_transform(pos, flight.angle + flight.spin * flight.age, mirror)
		var rect := Rect2(-tex.get_size() / 2, tex.get_size())
		var fade: float = flight.get("fade_time", 0)
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, minf(1, flight.age / fade) if fade > 0 else 1.0))
	draw_set_transform(Vector2.ZERO)
	for spell_data in spells:
		var a: WandActor = spell_data.actor
		if not is_instance_valid(a.sprite) or not a.sprite.visible: continue
		var age: float = spell_data.age
		var alpha := age / 0.2 if age < 0.2 else 1.0 if age <= 1 else 1 - (age - 1) / 0.4
		var factor := minf(1, age / 0.2)
		var pos := actor_point(a) + Vector2(0, -15.5)
		var color: Color = spell_data.color; color.a = alpha
		var region := Rect2((int(spell_data.index) % int(SPELLS.get_width() / 16)) * 16, int(spell_data.index / int(SPELLS.get_width() / 16)) * 16, 16, 16)
		draw_texture_rect_region(SPELLS, Rect2(pos - Vector2.ONE * 8 * factor, Vector2.ONE * 16 * factor), region, color)

func _draw_light() -> void:
	super._draw_light()
	_draw_flecks(light, true)
	light.draw_set_transform(Vector2.ZERO)

func _draw_flares() -> void:
	for flare_data in flares:
		var age: float = flare_data.age / 2.0
		var amplitude := age * 4 if age < 0.25 else (1 - age) * 1.333
		_flare_canvas.draw_set_transform(flare_data.pos, PI / 4 + PI * flare_data.age, Vector2.ONE * amplitude)
		var color: Color = flare_data.color; color.a = amplitude
		for ray in 6:
			var angle := ray * TAU / 6
			_flare_canvas.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(angle) * 32, Vector2.from_angle(angle + TAU / 12) * 32]),
				PackedColorArray([color, color, color]), PackedVector2Array([Vector2(0.25, 0), Vector2(0.75, 0), Vector2(0.75, 0)]), _gradient)
	_flare_canvas.draw_set_transform(Vector2.ZERO)

func _draw_flecks(canvas: Node2D, additive: bool) -> void:
	for p in flecks:
		if p.light != additive: continue
		var age: float = p.age / p.life
		var factor := 1.0
		var color: Color = p.color
		match p.kind:
			"splash": factor = (1 - age) * 4
			"healing": color.a = 1 if age < 0.5 else 2 - 2 * age
			"jet": color.a = minf(age, 1 - age) * 2; factor = age * 1.5
			"discover": color.a = 1 - age; factor = minf(age, 1 - age) * 2
			"snow": factor = 1; color.a = minf(age, 1 - age) * 1.5
			"wool": factor = 1 - age
		canvas.draw_set_transform(p.pos, p.angle)
		if p.frame < 0: canvas.draw_rect(Rect2(-Vector2.ONE * factor / 2, Vector2.ONE * factor), color)
		else:
			var columns := int(SPECKS.get_width() / 7)
			canvas.draw_texture_rect_region(SPECKS, Rect2(-Vector2.ONE * 3.5 * factor, Vector2.ONE * 7 * factor), Rect2((int(p.frame) % columns) * 7, int(p.frame / columns) * 7, 7, 7), color)
	canvas.draw_set_transform(Vector2.ZERO)

func clear() -> void:
	super.clear()
	for flight in flights:
		if is_instance_valid(flight.get("sprite")): flight.sprite.queue_free()
	flights.clear(); flecks.clear(); spells.clear(); flares.clear(); emission_clocks.clear()
	snow_emitters.clear()
	breaths.clear()
	if _flare_canvas != null: _flare_canvas.queue_redraw()
