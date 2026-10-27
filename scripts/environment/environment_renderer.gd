# Sprite atlas and particle equations adapted from SPD BlobEmitter / Speck / PixelParticle.
# GPL-3.0-or-later; see LICENSE-SPD.txt. Rendering never advances gameplay time.
class_name EnvironmentRenderer
extends Node2D

const World = preload("res://scripts/environment/dungeon_environment.gd")
const SPECKS = preload("res://assets/effects/specks.png")
const RATES = {"fire": 0.03, "freezing": 0.05, "web": 0.25, "toxic_gas": 0.4,
	"corrosive_gas": 0.4, "confusion_gas": 0.4, "paralytic_gas": 0.4, "stench_gas": 0.4,
	"smoke_screen": 0.1, "electricity": 0.05, "inferno": 0.4, "blizzard": 0.4,
	"storm_cloud": 0.4, "regrowth": 0.2, "foliage": 0.9, "alchemy": 0.33,
	"sacrificial_fire": 0.1, "goo_warn": 0.03, "vault_flame_traps": 0.3,
	"water_of_health": 0.5, "water_of_awareness": 0.3, "eternal_fire": 0.02,
	"pylon_energy": 0.08, "light_wall": 0.02, "hallowed_terrain": 1.0,
	"key_wall": 0.05, "tengu_fire": 0.2, "tengu_shocker": 0.1}
const GAS_COLORS = {"toxic_gas": Color("50ff60"), "corrosive_gas": Color("aaaaaa"),
	"paralytic_gas": Color("ffff66"), "stench_gas": Color("003300"),
	"smoke_screen": Color.BLACK, "storm_cloud": Color("8ad8d8"),
	"inferno": Color("ee7722"), "blizzard": Color.WHITE}
const LIGHT_TYPES = ["fire", "eternal_fire", "sacrificial_fire", "electricity",
	"pylon_energy", "tengu_shocker", "foliage", "hallowed_terrain", "light_wall", "goo_warn", "inferno", "blizzard", "vault_flame_traps"]

var world: DungeonEnvironment
var particles: Array[Dictionary] = []
var clocks: Dictionary = {}
var visual_rng := RandomNumberGenerator.new()
## Optional visibility array. Empty means visible; hidden cells stop emitting, as BlobEmitter does.
var visible_cells := PackedByteArray()
var _light: Node2D
var _source: DungeonEnvironment
var max_particles := 12000
var region := 0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual_rng.randomize()
	_light = Node2D.new()
	_light.name = "AdditiveParticles"
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_light.material = blend
	_light.draw.connect(_draw_light)
	add_child(_light)

func bind_environment(value: DungeonEnvironment) -> void:
	if _source != null and _source.reacted.is_connected(_reaction):
		_source.reacted.disconnect(_reaction)
	world = value
	_source = value
	if _source != null:
		_source.reacted.connect(_reaction)
	particles.clear()
	clocks.clear()

func _process(delta: float) -> void:
	if world == null:
		return
	# Cap catch-up emission after stalls without changing the independent simulation.
	var elapsed := minf(delta, 0.1)
	for f in world.fields.values():
		if f.volume <= 0 or not RATES.has(f.kind):
			continue
		var interval := float(RATES[f.kind])
		for c in f.cur.size():
			if f.cur[c] <= 0 or (not visible_cells.is_empty() and visible_cells[c] == 0
				and f.kind not in ["alchemy", "water_of_health", "water_of_awareness", "light_wall", "key_wall"]):
				continue
			if f.kind == "sacrificial_fire":
				interval = 0.01 + (float(f.volume) / (6 + world.scaling_depth * 4)) * 0.09
			var key: String = f.kind + ":" + str(c)
			var timer := float(clocks.get(key, visual_rng.randf_range(0, interval))) + elapsed
			while timer >= interval:
				timer -= interval
				_emit(f.kind, c)
			clocks[key] = timer
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.age += delta
		if p.age >= p.life:
			particles.remove_at(i)
		else:
			p.pos += p.velocity * delta
			p.velocity += p.acceleration * delta
			p.angle += p.spin * delta
	queue_redraw()
	if _light != null:
		_light.queue_redraw()

func _reaction(event: Dictionary) -> void:
	if event.action == "flame_burst":
		for i in 20:
			_emit("fire", event.cell)
	elif event.action == "shock_burst":
		for i in 10:
			_emit("electricity", event.cell)
	elif event.action == "vault_flame_burst":
		for i in 10:
			_emit("goo_warn", event.cell)

func _emit(kind: String, cell: int) -> void:
	if particles.size() >= max_particles:
		return
	var point := Vector2(cell % world.size.x, cell / world.size.x) * 16
	point += Vector2(visual_rng.randf_range(0, 16), visual_rng.randf_range(0, 16))
	var p := {"kind": kind, "pos": point, "age": 0.0, "life": 1.0,
		"velocity": Vector2.ZERO, "acceleration": Vector2.ZERO, "angle": 0.0,
		"spin": 0.0, "color": Color.WHITE, "size": Vector2.ONE, "frame": -1,
		"light": kind in LIGHT_TYPES}
	if kind in World.DIFFUSING and kind != "regrowth":
		p.frame = 13
		p.life = visual_rng.randf_range(1, 1.5 if kind == "smoke_screen" else 3)
		p.color = GAS_COLORS.get(kind, Color(visual_rng.randf(), visual_rng.randf(), visual_rng.randf_range(0.5, 1)))
		p.spin = deg_to_rad(-30 if kind in ["paralytic_gas", "stench_gas"] else 30)
		if kind in ["confusion_gas", "storm_cloud"]:
			p.spin = deg_to_rad(visual_rng.randf_range(-20, 20))
		elif kind in ["inferno", "blizzard"]:
			p.spin = deg_to_rad(visual_rng.randf_range(200, 300) * (-1 if visual_rng.randf() < 0.5 else 1))
	else:
		match kind:
			"fire", "eternal_fire", "sacrificial_fire", "goo_warn", "vault_flame_traps":
				p.life = 0.6
				p.size = Vector2.ONE * 4
				p.color = Color("4488ee") if kind == "sacrificial_fire" else Color("22ee66") if kind in ["goo_warn", "eternal_fire", "vault_flame_traps"] else Color("ee7722")
				p.acceleration = Vector2(0, -100 if kind == "sacrificial_fire" else -80)
				if kind == "sacrificial_fire":
					p.pos.y -= 4
				if kind == "vault_flame_traps":
					p.pos = Vector2(cell % world.size.x, cell / world.size.x) * 16 + Vector2(visual_rng.randf_range(6.4, 9.6), visual_rng.randf_range(6.4, 9.6))
			"freezing":
				p.life = 1.2
				p.velocity = Vector2(0, visual_rng.randf_range(5, 8))
				p.pos.y -= p.velocity.y * p.life
			"web":
				p.life = 2.0
				p.color = Color("cccccc")
				p.angle = visual_rng.randf_range(0, TAU)
				for i in 2:
					var thread := p.duplicate()
					thread.angle = visual_rng.randf_range(0, TAU)
					particles.append(thread)
			"electricity", "tengu_shocker", "pylon_energy":
				p.life = visual_rng.randf_range(0.25, 0.5) if kind == "tengu_shocker" else visual_rng.randf_range(0.5, 1)
				p.size = Vector2.ONE * 5
				if kind != "tengu_shocker":
					p.velocity = Vector2.from_angle(-visual_rng.randf() * PI) * visual_rng.randf_range(20, 40)
					p.acceleration = Vector2(0, 50)
				if kind == "pylon_energy":
					var source := Vector2(world.fields[kind].data.get("source_position", p.pos))
					p.velocity = (source - p.pos).normalized() * 48
					p.pos -= p.velocity / 8
					p.acceleration = Vector2.ZERO
					p.life = visual_rng.randf_range(0.2, 0.35)
			"regrowth":
				p.life = 1.2
				p.color = Color("004400").lerp(Color("88cc44"), visual_rng.randf())
				p.size = Vector2.ONE * visual_rng.randf_range(2, 3)
				p.velocity = Vector2(visual_rng.randf_range(-8, 8), -20)
				p.acceleration = Vector2(0, 25)
			"foliage", "hallowed_terrain":
				p.life = visual_rng.randf_range(1.2, 2.4)
				p.velocity = Vector2(0, -6)
				p.color = Color("ccffcc")
			"alchemy", "water_of_health", "water_of_awareness", "tengu_fire":
				p.frame = {"alchemy": 12, "water_of_health": 0, "water_of_awareness": 3}.get(kind, 13)
				p.life = visual_rng.randf_range(0.8, 1.5) if kind == "alchemy" else 0.8 if kind == "water_of_awareness" else 1.0
				p.velocity = Vector2(0, -15 if kind == "alchemy" else -20 if kind == "water_of_health" else -visual_rng.randf_range(10, 15))
				if kind == "vault_flame_traps":
					p.pos = Vector2(cell % world.size.x, cell / world.size.x) * 16 + Vector2(visual_rng.randf_range(6.4, 9.6), visual_rng.randf_range(6.4, 9.6))
			"key_wall":
				if (region == 1 and visual_rng.randi_range(0, 4) >= 3) or (region == 4 and visual_rng.randi_range(0, 4) >= 2):
					return
				p.life = 3.0
				p.color = Color("d4d4d4").lerp(Color("ababab"), visual_rng.randf())
				p.size = Vector2(6, 3)
				p.pos = Vector2(round(p.pos.x / 7) * 7, round(p.pos.y / 4) * 4 - 6)
				p.pos.x += round(fmod(p.pos.y, 8)) / 4 - 1
				match region:
					1:
						p.pos = Vector2(round(point.x / 7) * 7, round(point.y / 6) * 6 - 6)
						p.pos.x += round(fmod(p.pos.y, 8)) / 4 - 1
						p.color = Color("c4be9c").lerp(Color("9c927d"), visual_rng.randf())
						p.size = Vector2(6, 5)
					2:
						p.pos = point - Vector2(0, 6)
						var shade := fmod(point.x, 16) / 16 + fmod(p.pos.y, 16) / 16
						p.color = Color("b7b0a5").lerp(Color("6a6662"), 2 - shade if shade > 1 else shade)
						p.size = Vector2.ONE * 5
					3:
						p.pos = Vector2(round(point.x / 5) * 5, round(point.y / 5) * 5 - 6)
						p.pos.x += round(fmod(p.pos.y, 16)) / 5 - 2
						p.color = Color("d0bca3").lerp(Color("a38d81"), visual_rng.randf())
						p.size = Vector2.ONE * 4
					4:
						p.pos = Vector2(round(point.x / 4) * 4, round((point.y + 8) / 16) * 16 - 14)
						p.color = Color("a2947d").lerp(Color("594847"), visual_rng.randf())
						p.size = Vector2(4, 20)
				p.color.a = 0.6
			"light_wall":
				p.life = 2.0
				p.size = Vector2.ONE * 3
				p.color.a = 0.5
				p.pos = Vector2(round(p.pos.x / 4) * 4, round(p.pos.y / 4) * 4 - 6)
				p.pos.x += round(fmod(p.pos.y, 16)) / 4 - 2
	particles.append(p)

func _draw() -> void:
	_draw_particles(false)

func _draw_light() -> void:
	_draw_particles(true)

func _draw_particles(light: bool) -> void:
	var target: Node2D = _light if light else self
	for p in particles:
		if p.light != light:
			continue
		var elapsed: float = p.age / p.life
		var remaining := 1.0 - elapsed
		var color: Color = p.color
		var dimensions: Vector2 = p.size
		if p.frame >= 0:
			var scale_value := 1.0
			if p.kind in World.DIFFUSING or p.kind in ["vault_flame_traps", "tengu_fire"]:
				color.a = sqrt(minf(elapsed, remaining) * (1.0 if p.kind in ["stench_gas", "corrosive_gas", "smoke_screen"] else 0.5))
				scale_value = 1 + elapsed
				if p.kind == "corrosive_gas":
					color = Color("aaaaaa").lerp(Color("ff8800"), elapsed) * Color(1, 1, 1, color.a)
			elif p.kind == "water_of_health":
				color.a = 1 if elapsed < 0.5 else 2 - 2 * elapsed
			elif p.kind == "water_of_awareness":
				scale_value = sqrt(minf(elapsed, remaining)) * 3
			elif p.kind == "alchemy":
				color.a = minf(1, elapsed * 5)
			target.draw_set_transform(p.pos.round(), p.angle, Vector2.ONE * scale_value)
			var columns := SPECKS.get_width() / 7
			var atlas := Rect2((p.frame % columns) * 7, (p.frame / columns) * 7, 7, 7)
			target.draw_texture_rect_region(SPECKS, Rect2(-Vector2.ONE * 3.5, Vector2.ONE * 7), atlas, color)
		else:
			match p.kind:
				"fire", "eternal_fire", "sacrificial_fire", "goo_warn", "vault_flame_traps":
					dimensions *= remaining
					color.a = minf(1, elapsed * (4 if p.kind == "sacrificial_fire" else 5))
				"freezing": color.a = minf(elapsed, remaining) * 1.5
				"web":
					color.a = minf(elapsed, remaining)
					dimensions = Vector2(1, 12 + remaining * 6)
				"electricity", "pylon_energy", "tengu_shocker": dimensions *= visual_rng.randf() * remaining
				"regrowth", "light_wall", "key_wall": dimensions *= remaining
				"foliage", "hallowed_terrain":
					color.a = minf(elapsed, remaining)
					dimensions = Vector2(elapsed * 4, 16 + elapsed * 16)
			target.draw_set_transform(p.pos.round(), p.angle)
			target.draw_rect(Rect2(-dimensions / 2, dimensions), color)
	target.draw_set_transform(Vector2.ZERO)

