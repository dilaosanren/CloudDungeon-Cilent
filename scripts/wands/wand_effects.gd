# MagicMissile, Beam, Lightning and wand particles adapted from SPD 4.0.2.
# GPL-3.0-or-later. Logical coordinates are original 16px tiles.
class_name WandEffects
extends Node2D

const ATLAS = preload("res://assets/wands/source/effects.png")
const FRAMES = {"death": Rect2(16, 16, 16, 8), "light": Rect2(16, 23, 16, 8),
	"health": Rect2(16, 30, 16, 8), "lightning": Rect2(16, 0, 16, 8), "blast": Rect2(0, 0, 16, 16)}
const KIND = {"WandOfMagicMissile": "white", "WandOfFrost": "frost", "WandOfFireblast": "flame",
	"WandOfCorrosion": "corrosion", "WandOfBlastWave": "force", "WandOfLivingEarth": "earth",
	"WandOfWarding": "ward", "WandOfCorruption": "shadow", "WandOfRegrowth": "leaf"}
var world: WandWorld
var missiles: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var beams: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var light: Node2D
var sound_enabled := true
var history: Array[Dictionary] = [] # Useful for checking endpoint and callback timing.

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rng.randomize()
	light = Node2D.new()
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	light.material = blend
	light.draw.connect(_draw_light)
	add_child(light)

func point(cell: int, raised: bool = true) -> Vector2:
	return Vector2(world.level.cell_coords(cell)) * 16 + Vector2(8, 2 if raised else 8)

func actor_point(a: WandActor) -> Vector2:
	if is_instance_valid(a.sprite):
		if a.sprite is DungeonHeroSprite:
			# Use the animated body, including its jump displacement, rather than
			# an assumed offset from the foot/shadow anchor.
			var body: AnimatedSprite2D = a.sprite.body
			if body != null and body.sprite_frames != null:
				var frame := body.sprite_frames.get_frame_texture(body.animation, body.frame)
				return to_local(body.to_global(frame.get_size() / 2))
		if a.sprite.has_method("center_point"): return to_local(a.sprite.center_point())
		return to_local(a.sprite.global_position)
	return point(a.cell)

func endpoint(cell: int) -> Vector2:
	var a := world.actor_at(cell)
	return actor_point(a) if a != null else point(cell)

func play(p: Dictionary, callback: Callable) -> void:
	var start := actor_point(p.caster)
	var end := endpoint(p.bolt.collision_pos)
	match p.type:
		"WandOfDisintegration":
			end = point(p.bolt.path[mini(p.bolt.dist, 6 + 2 * p.level)])
			beam("death", start, end, 0.5)
			sound("ray")
			callback.call()
		"WandOfPrismaticLight", "WandOfTransfusion":
			beam("light" if p.type == "WandOfPrismaticLight" else "health", start, point(p.bolt.collision_pos), 1.0 if p.type == "WandOfPrismaticLight" else 0.75)
			sound("ray")
			callback.call()
		"WandOfLightning":
			for pair in p.arcs:
				lightning(endpoint(pair[0]), endpoint(pair[1]))
			sound("lightning")
			callback.call()
		"WandOfFireblast", "WandOfRegrowth":
			var longest: Ballistica
			for ray in p.cone.outer_rays:
				if longest == null or ray.dist > longest.dist: longest = ray
				missile(KIND[p.type], start, point(ray.collision_pos), Callable(), 200, 10, 0.03)
			if longest != null: missile(KIND[p.type], start, endpoint(longest.path[int(longest.dist / 2)]), callback, 200, 10, 0.03)
			else: callback.call()
			sound("zap")
			if p.type == "WandOfFireblast": sound("burning")
		_:
			var kind: String = KIND.get(p.type, "white")
			var sizes := {"white": 4, "frost": 0, "corrosion": 3, "force": 0, "earth": 4, "ward": 4, "shadow": 4}
			missile(kind, start, end, callback, p.bolt.dist * 20 if p.type == "WandOfWarding" and p.bolt.dist > 10 else 200, sizes.get(kind, 4), 0.01)
			sound("zap")

func sound(name: String, pitch: float = 1.0) -> void:
	if not sound_enabled or not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var path := "res://assets/wands/source/%s.mp3" % name
	if not ResourceLoader.exists(path): return
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = load(path)
	player.pitch_scale = pitch
	player.volume_db = 0
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func missile(kind: String, start: Vector2, end: Vector2, callback: Callable, speed: float = 200, spread: float = 4, rate: float = 0.01) -> void:
	var duration := start.distance_to(end) / speed
	missiles.append({"kind": kind, "start": start, "end": end, "age": 0.0, "duration": duration,
		"spread": spread, "rate": rate, "clock": 0.0, "callback": callback})
	history.append({"kind": kind, "start": start, "end": end, "duration": duration, "spread": spread, "rate": rate})

func beam(kind: String, start: Vector2, end: Vector2, duration: float) -> void:
	beams.append({"kind": kind, "start": start, "end": end, "age": 0.0, "duration": duration})
	history.append({"kind": kind, "start": start, "end": end, "duration": duration})
	queue_redraw()
	if light != null: light.queue_redraw()

func lightning(start: Vector2, end: Vector2) -> void:
	beam("lightning", start, end, 0.3)

func blast(cell: int) -> void:
	beam("blast", point(cell, false), point(cell, false), 0.2)
	sound("blast")

func burst(kind: String, pos: Vector2, count: int, attract: bool = false) -> void:
	for i in count:
		_emit_particle(kind, pos, pos, true, attract)

func _emit_particle(kind: String, pos: Vector2, emitter: Vector2, is_burst: bool = false, attract: bool = false) -> void:
	var p := {"kind": kind, "pos": pos, "age": 0.0, "life": 0.5, "velocity": Vector2.ZERO,
		"acc": Vector2.ZERO, "color": Color.WHITE, "size": 4.0, "alpha": 1.0, "light": true, "emitter": emitter}
	match kind:
		"white": p.life = 0.4; p.size = 3; p.alpha = 0.5
		"frost": p.color = Color("88ccff"); p.velocity = Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
		"flame": p.color = Color("ee7722"); p.life = 0.6; p.acc = Vector2(0, -80)
		"corrosion":
			p.light = false; p.life = 0.6; p.acc = Vector2(0, 30)
			p.velocity = Vector2.from_angle(-rng.randf_range(0, PI)) * rng.randf_range(0, 6)
		"leaf":
			p.light = false; p.life = 1.2; p.color = Color("004400").lerp(Color("88cc44"), rng.randf())
			p.acc = Vector2(0, 25); p.velocity = Vector2(rng.randf_range(-8, 8), -20); p.size = rng.randf_range(2, 3)
		"force": p.life = 0.6; p.color = Color("664422"); p.size = 2; p.velocity = Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
		"shadow": p.light = false; p.size = 6; p.velocity = Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5))
		"earth":
			p.light = false; p.acc = Vector2(0, 40)
			p.color = Color("fff266").lerp(Color("80771a"), rng.randf()) if rng.randi_range(0, 9) == 0 else Color("805500").lerp(Color("332500"), rng.randf())
			p.velocity = Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
		"ward": p.life = 0.6; p.color = Color("8822ff"); p.size = 8
		"purple": p.color = Color("ff0044")
		"rainbow": p.color = Color(rng.randf(), rng.randf(), rng.randf())
		"blood": p.color = Color("cc0000"); p.life = 0.8; p.acc = Vector2(0, 40)
		"spark": p.life = 0.5; p.color = Color("ffffaa"); p.size = 2
	if kind in ["purple", "rainbow", "blood", "spark"] or is_burst:
		p.velocity = Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(16, 32)
		if kind == "earth": p.velocity = Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(40, 60)
		if kind == "ward": p.velocity = Vector2(rng.randf_range(-8, 8), rng.randf_range(-48, -32))
	if attract:
		p.velocity = Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(24, 32)
		p.pos -= p.velocity * p.life
		p.acc = Vector2.ZERO
	particles.append(p)

func _process(delta: float) -> void: advance(delta)

func is_presenting_action() -> bool:
	return not missiles.is_empty() or not beams.is_empty()

func advance(delta: float) -> void:
	# Iterate a snapshot: impact callbacks may append new effects safely.
	for m in missiles.duplicate():
		var previous: float = m.age
		m.age += delta
		m.clock += minf(delta, maxf(0, m.duration - previous))
		while m.clock >= m.rate:
			m.clock -= m.rate
			var time: float = minf(m.duration, m.age - m.clock)
			var pos: Vector2 = m.start.lerp(m.end, minf(1, time / maxf(0.001, m.duration)))
			var spread: float = m.spread
			_emit_particle(m.kind, pos + Vector2(rng.randf_range(-spread / 2, spread / 2), rng.randf_range(-spread / 2, spread / 2)), pos)
		if m.age >= m.duration:
			missiles.erase(m)
			if m.callback.is_valid(): m.callback.call()
	for p in particles.duplicate():
		p.age += delta
		if p.age >= p.life: particles.erase(p); continue
		p.pos += p.velocity * delta
		if p.kind == "force": p.acc = (p.emitter - p.pos) * 10
		p.velocity += p.acc * delta
	for b in beams.duplicate():
		b.age += delta
		if b.age >= b.duration: beams.erase(b)
	queue_redraw()
	if light != null: light.queue_redraw()

func _draw() -> void:
	_draw_particles(false, self)
	for b in beams:
		if b.kind == "blast":
			var alpha: float = 1 - b.age / b.duration
			var side: float = 16 * (1 - alpha) * 3
			draw_texture_rect_region(ATLAS, Rect2(b.start - Vector2.ONE * side / 2, Vector2.ONE * side), FRAMES.blast, Color(1, 1, 1, alpha))

func _draw_light() -> void:
	_draw_particles(true, light)
	for b in beams:
		if b.kind == "blast": continue
		var alpha: float = 1 - b.age / b.duration
		if b.kind == "lightning":
			var mid: Vector2 = (b.start + b.end) / 2 + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4))
			_draw_segment(light, b.start, mid, FRAMES.lightning, alpha, 1)
			_draw_segment(light, mid, b.end, FRAMES.lightning, alpha, 1)
		else: _draw_segment(light, b.start, b.end, FRAMES[b.kind], alpha, alpha)
	light.draw_set_transform(Vector2.ZERO)

func _draw_segment(canvas: Node2D, start: Vector2, end: Vector2, frame: Rect2, alpha: float, thickness: float) -> void:
	canvas.draw_set_transform(start, (end - start).angle())
	canvas.draw_texture_rect_region(ATLAS, Rect2(0, -frame.size.y * thickness / 2, start.distance_to(end), frame.size.y * thickness), frame, Color(1, 1, 1, alpha))

func _draw_particles(additive: bool, canvas: Node2D) -> void:
	for p in particles:
		if p.light != additive: continue
		var remaining: float = 1 - p.age / p.life
		var size: float = p.size
		var color: Color = p.color
		color.a = p.alpha
		match p.kind:
			"white": size = 3 * remaining
			"frost": size = 4 - remaining * 3; color.a = remaining
			"flame": size *= remaining; color.a = (1 - remaining) * 5 if remaining > 0.8 else 1
			"corrosion": size = 4 - remaining * 3; color = Color("ff8800").lerp(Color("aaaaaa"), remaining); color.a = remaining
			"leaf", "earth", "spark": size *= remaining
			"force": color.a = remaining
			"shadow": size *= remaining; color = Color.BLACK.lerp(Color("440044"), remaining); color.a = remaining * remaining * 4 if remaining < 0.5 else (1 - remaining) * 2
			"ward": size *= remaining; color.a = 1 - remaining
			"purple": size = 5 - remaining * 4; color = Color("220066").lerp(Color("ff0044"), remaining); color.a = remaining
			"rainbow": size = 5 - remaining * 4; color.a = remaining
			"blood": size *= remaining; color.a = (1 - remaining) * 2.5 if remaining > 0.6 else 1
		canvas.draw_rect(Rect2(p.pos - Vector2.ONE * size / 2, Vector2.ONE * size), color)

func clear() -> void:
	missiles.clear(); particles.clear(); beams.clear(); history.clear()
	queue_redraw()
	if light != null: light.queue_redraw()
