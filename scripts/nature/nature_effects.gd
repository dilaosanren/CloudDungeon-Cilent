# Native plant particles, CheckedCell and Enchanting presentation. GPL-3.0-or-later.
extends MeleeEffects
var nature_particles: Array[Dictionary] = []
var nature_emitters: Array[Dictionary] = []
var checked_cells: Array[Dictionary] = []
var enchantments: Array[Dictionary] = []
var checked_canvas: Node2D

func _ready() -> void:
	super._ready()
	checked_canvas = Node2D.new()
	checked_canvas.name = "ClairvoyanceCells"
	checked_canvas.z_index = 110 # CheckedCell is intentionally visible over fog.
	checked_canvas.draw.connect(_draw_checked)
	add_child(checked_canvas)

# Seeds and stones use MissileSprite default: 240px/s and 720deg/s.
func throw_item(item: InventoryItem, actor: WandActor, cell: int, callback: Callable, anchors: Dictionary = {}) -> void:
	throw_potion(item, actor, cell, callback, anchors)

func sound(name: String, pitch: float = 1.0) -> void:
	var file := "res://assets/nature/source/%s.mp3" % name
	if not ResourceLoader.exists(file): super.sound(name, pitch); return
	if not sound_enabled or not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = load(file); player.pitch_scale = pitch
	add_child(player); player.finished.connect(player.queue_free); player.play()

func nature_burst(cell: int, kind: String, count: int, interval: float = 0.0) -> void:
	var emitter := {"cell":cell, "kind":kind, "left":count, "clock":0.0, "interval":interval}
	if interval <= 0:
		for i in count: _emit_nature(emitter)
	else: nature_emitters.append(emitter)

func _emit_nature(emitter: Dictionary) -> void:
	var at := point(int(emitter.cell), false) + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
	var particle := {"kind":emitter.kind, "pos":at, "age":0.0, "life":1.0, "size":1.0, "velocity":Vector2.ZERO, "acc":Vector2.ZERO, "angle":0.0, "color":Color.WHITE, "light":false}
	match str(emitter.kind):
		"leaf":
			particle.life = 1.2; particle.size = rng.randf_range(2, 3)
			particle.color = Color(0.5333 * rng.randf(), 0.2667 + 0.5333 * rng.randf(), 0.2667 * rng.randf())
			particle.velocity = Vector2(rng.randf_range(-8, 8), -20); particle.acc = Vector2(0, 25)
		"earth":
			particle.pos = point(int(emitter.cell), false) + Vector2(rng.randf_range(-8, 8), 8)
			particle.life = 0.5; particle.size = 16
			particle.angle = deg_to_rad(rng.randf_range(-30, 30)); particle.color = Color(rng.randf_range(0.2667, 0.4667), rng.randf_range(0.2667, 0.4667), rng.randf_range(0.2667, 0.4))
		"shaft":
			particle.life = 1.2
			particle.age = -rng.randf_range(0, 1.2); particle.velocity = Vector2(0, -6); particle.light = true
		"blast":
			particle.pos = point(int(emitter.cell), false); particle.life = maxf(0.001, rng.randf())
			particle.velocity = Vector2.from_angle(-rng.randf() * PI) * rng.randf_range(32, 64)
			particle.acc = Vector2(0, 50); particle.size = 8; particle.color = Color("ee7722"); particle.light = true
		"spark":
			particle.pos = point(int(emitter.cell), false); particle.life = rng.randf_range(0.5, 1.0)
			particle.velocity = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(8, 16)
			particle.acc = Vector2(0, 16); particle.color = Color("ffffaa"); particle.size = 2; particle.light = true
		"smoke":
			particle.life = rng.randf_range(1, 2); particle.size = rng.randf_range(4, 8)
			particle.velocity = Vector2(rng.randf_range(-4, 4), rng.randf_range(-16, -4)); particle.color = Color("555555")
		"flame": _emit_particle("flame", at, at); return
		"snow": speck("snow", at, 1); return
		"poison": particle.life = 0.8; particle.size = 2; particle.color = Color("50ff60"); particle.velocity = Vector2.from_angle(rng.randf() * TAU) * 16; particle.acc = Vector2(0, 30)
	nature_particles.append(particle)

func checked(cell: int, origin: int) -> void:
	var distance := Vector2(world.level.cell_coords(cell)).distance_to(Vector2(world.level.cell_coords(origin)))
	checked_cells.append({"pos":point(cell, false), "age":0.0, "delay":pow(maxf(0, distance - 1), 0.67) / 10})

func enchant(actor: WandActor, item: InventoryItem, color: Color) -> void:
	enchantments.append({"actor":actor, "texture":ItemAssets.get_texture(item.visual), "color":color, "age":0.0})

func flare_cell(cell: int, color: Color, rays: int, radius: float, duration: float) -> void:
	flares.append({"actor":null, "color":color, "age":0.0, "pos":point(cell, false), "rays":rays, "radius":radius, "duration":duration})

func advance(delta: float) -> void:
	super.advance(delta)
	for emitter in nature_emitters.duplicate():
		emitter.clock += delta
		while emitter.clock >= emitter.interval and emitter.left > 0:
			emitter.clock -= emitter.interval; emitter.left -= 1; _emit_nature(emitter)
		if emitter.left <= 0: nature_emitters.erase(emitter)
	for particle in nature_particles.duplicate():
		particle.age += delta
		if particle.age >= particle.life: nature_particles.erase(particle); continue
		particle.pos += particle.velocity * delta
		particle.velocity += particle.acc * delta
	for record in checked_cells.duplicate():
		record.age += delta
		if record.age >= record.delay + 0.8: checked_cells.erase(record)
	for record in enchantments.duplicate():
		record.age += delta
		if record.age >= 1.6 or not is_instance_valid(record.actor.sprite): enchantments.erase(record)
	checked_canvas.queue_redraw()

func _draw() -> void:
	super._draw()
	_draw_nature(self, false)
	for record in enchantments:
		if not is_instance_valid(record.actor.sprite) or not record.actor.sprite.visible: continue
		var age := float(record.age)
		var alpha := age / 0.2 * 0.6 if age < 0.2 else 0.6 if age < 1.2 else (1.6 - age) / 0.4 * 0.6
		var size_factor := age / 0.2 if age < 0.2 else 1.0 if age < 1.2 else 1 + (age - 1.2) / 0.4
		var size: Vector2 = record.texture.get_size() * size_factor
		var at := actor_point(record.actor) + Vector2(0, -15.5)
		var tint := Color.WHITE.lerp(record.color, clampf((age - 0.2) * 0.8, 0, 0.8)); tint.a = alpha
		draw_texture_rect(record.texture, Rect2(at - size / 2, size), false, tint)

func _draw_light() -> void:
	super._draw_light()
	_draw_nature(light, true)

func _draw_nature(canvas: Node2D, additive: bool) -> void:
	for particle in nature_particles:
		if particle.light != additive: continue
		var p := float(particle.age) / float(particle.life)
		var left := 1 - p
		var size := Vector2.ONE * float(particle.size) * left
		var color: Color = particle.color
		if particle.kind == "shaft":
			if p < 0: continue
			color.a = minf(p, left); size = Vector2(p * 4, 16 + p * 16)
		elif particle.kind == "earth": size = Vector2.ONE * minf(p, left) * float(particle.size)
		elif particle.kind == "blast": color.a = (1 - left) * 5 if left > 0.8 else 1.0
		elif particle.kind == "smoke": color.a = left * 0.6
		canvas.draw_set_transform(particle.pos, particle.angle)
		canvas.draw_rect(Rect2(-size / 2, size), color)
	canvas.draw_set_transform(Vector2.ZERO)

func _draw_checked() -> void:
	for record in checked_cells:
		var age := float(record.age) - float(record.delay)
		if age < 0: continue
		var alpha := maxf(0, 0.8 - age)
		var size := Vector2.ONE * 16 * alpha
		checked_canvas.draw_rect(Rect2(Vector2(record.pos) - size / 2, size), Color(0.3333, 0.6667, 1, alpha))

func clear() -> void:
	super.clear()
	nature_particles.clear(); nature_emitters.clear(); checked_cells.clear(); enchantments.clear()
	if checked_canvas != null: checked_canvas.queue_redraw()
