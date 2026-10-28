# Speck, EnergyParticle, ShadowParticle.UP, Identification, Transmuting and Fader.
# Original textures/frames and equations from SPD 4.0.2; GPL-3.0-or-later.
class_name ScrollEffects
extends PotionEffects

const SCROLL_FRAMES = {"light": 2, "discover": 2, "up": 4, "scream": 5, "note": 9, "change": 10, "wool":7, "heart":11}
const DOTS = [Vector2i(-1, -3), Vector2i(0, -3), Vector2i(1, -3), Vector2i(-1, -2), Vector2i(1, -2), Vector2i(1, -1), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, 3)]
var scroll_particles: Array[Dictionary] = []
var emitters: Array[Dictionary] = []
var transmutations: Array[Dictionary] = []
var teleports: Array[Dictionary] = []
var _flash: ColorRect
var _flash_age := 1.0
var _flash_color := Color.WHITE

func _ready() -> void:
	super._ready()
	var map := get_parent().get_parent()
	if map is DungeonMap:
		_flare_canvas.reparent(map, false)
		map.move_child(_flare_canvas, map.item_layer.get_index())
	var canvas := CanvasLayer.new(); canvas.name = "ScrollFlash"; canvas.layer = 20; add_child(canvas)
	_flash = ColorRect.new(); _flash.mouse_filter = Control.MOUSE_FILTER_IGNORE; _flash.material = light.material
	canvas.add_child(_flash); _flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _flash.hide()

func sound(name: String, pitch: float = 1.0) -> void:
	history.append({"kind": "scroll_sound", "sound": name, "pitch": pitch})
	var path := "res://assets/scrolls/source/%s.mp3" % name
	if not ResourceLoader.exists(path): super.sound(name, pitch); return
	if not sound_enabled or not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var player := AudioStreamPlayer.new(); player.stream = load(path); player.pitch_scale = pitch
	player.bus = &"SFX"
	add_child(player); player.finished.connect(player.queue_free); player.play()

func start_specks(a: WandActor, cell: int, kind: String, interval: float, count: int, center: bool) -> void:
	var emitter := {"actor": a, "cell": cell, "kind": kind, "interval": interval, "clock": rng.randf_range(0, interval), "left": count, "center": center}
	history.append({"kind": kind, "interval": interval, "count": count, "cell": cell})
	if interval == 0:
		for i in count: _emit_scroll_particle(emitter)
	else: emitters.append(emitter)

func _emit_scroll_particle(emitter: Dictionary) -> void:
	var a: WandActor = emitter.actor
	if a != null and (not is_instance_valid(a.sprite) or not a.sprite.visible): return
	var pos := actor_point(a) if a != null else point(emitter.cell, false)
	if not emitter.center: pos += Vector2(rng.randf_range(-6, 6), rng.randf_range(-7.5, 7.5))
	var p := {"kind": emitter.kind, "pos": pos, "age": 0.0, "life": 1.0, "velocity": Vector2.ZERO, "acc": Vector2.ZERO,
		"angle": 0.0, "spin": 0.0, "frame": SCROLL_FRAMES.get(emitter.kind, -1), "light": false, "color": Color.WHITE, "size": 0.0}
	match emitter.kind:
		"wool": p.life = 0.5; p.velocity = Vector2(0, -50); p.angle = rng.randf_range(0, TAU); p.spin = rng.randf_range(-TAU, TAU)
		"heart": p.life = 1.0; p.velocity = Vector2(rng.randi_range(-10, 10), -40); p.spin = deg_to_rad(rng.randf_range(-45, 45))
		"note": p.spin = deg_to_rad(rng.randf_range(-30, 30)); p.velocity = Vector2.from_angle(p.spin - PI / 2) * 30
		"light", "discover": p.angle = rng.randf_range(0, TAU); p.spin = PI / 2; p.life = 0.5 if emitter.kind == "discover" else 1.0
		"up": p.velocity = Vector2(0, -20)
		"scream": p.life = 0.9
		"change": p.angle = rng.randf_range(0, TAU); p.velocity = Vector2.from_angle(p.angle - PI / 2) * rng.randf_range(4, 12); p.life = 1.5
		"energy":
			p.velocity = Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(24, 32); p.pos -= p.velocity
			p.color = Color("ffffaa"); p.light = true
		"shadow_up": p.velocity = Vector2(rng.randf_range(-8, 8), rng.randf_range(-48, -32))
	scroll_particles.append(p)

func identification(a: WandActor) -> void:
	var origin := actor_point(a) + Vector2(0, -16)
	for dot in DOTS:
		for i in 2:
			var start := origin + Vector2.from_angle(rng.randf_range(0, TAU)) * 8
			var delta := origin + Vector2(dot * 3) - start
			scroll_particles.append({"kind": "identification", "pos": start, "age": 0.0, "life": 2.0, "velocity": delta, "acc": -delta / 4,
				"angle": 0.0, "spin": 0.0, "frame": -1, "light": true, "color": Color("4488cc")})
	history.append({"kind": "identification", "count": 20, "life": 2.0})

func transmute(a: WandActor, old_item: InventoryItem, new_item: InventoryItem) -> void:
	transmutations.append({"actor": a, "old": ItemAssets.get_texture(old_item.visual), "new": ItemAssets.get_texture(new_item.visual), "age": 0.0})
	history.append({"kind": "transmuting", "fade_in": 0.2, "crossfade": 1.4, "fade_out": 0.4, "alpha": 0.6})

func appear(a: WandActor, old_cell: int) -> void:
	if not is_instance_valid(a.sprite): return
	if world.visible[old_cell] or world.visible[a.cell]: sound("teleport")
	if a.species != "hero" and world.visible[old_cell]: start_specks(null, old_cell, "light", 0.2, 3, false)
	if a.sprite is DungeonHeroSprite: a.sprite.place_cell(world.level.cell_coords(a.cell))
	if not a.has_status("invisibility"):
		a.sprite.modulate.a = 0
		teleports.append({"actor": a, "age": 0.0})
	if world.visible[a.cell] or a.species == "hero": start_specks(a, a.cell, "light", 0.2, 3, false)
	history.append({"kind": "teleport", "cell": a.cell, "fade": 0.4})

func flash(color: Color) -> void:
	_flash_color = color; _flash_age = 0; _flash.color = color; _flash.show()
	history.append({"kind": "flash", "life": 1.0, "color": color})

func scroll_flare(a: WandActor, color: Color, rays: int) -> void:
	flares.append({"actor": a, "color": color, "age": 0.0, "pos": actor_point(a), "rays": rays})
	history.append({"kind": "flare", "rays": rays, "radius": 32, "duration": 2.0})

func is_presenting_action() -> bool:
	return super.is_presenting_action() or not teleports.is_empty() or not transmutations.is_empty() or _flash_age < 1

func advance(delta: float) -> void:
	super.advance(delta)
	for emitter in emitters.duplicate():
		emitter.clock += delta
		while emitter.clock > emitter.interval and emitter.left > 0:
			emitter.clock -= emitter.interval; emitter.left -= 1; _emit_scroll_particle(emitter)
		if emitter.left == 0: emitters.erase(emitter)
	for p in scroll_particles.duplicate():
		p.age += delta
		if p.age >= p.life: scroll_particles.erase(p); continue
		p.pos += p.velocity * delta; p.velocity += p.acc * delta; p.angle += p.spin * delta
		if p.kind == "energy": p.size = rng.randf_range(0, 5 * (1 - p.age / p.life))
	for t in transmutations.duplicate():
		t.age += delta
		if t.age >= 2: transmutations.erase(t)
	for t in teleports.duplicate():
		t.age += delta
		if is_instance_valid(t.actor.sprite): t.actor.sprite.modulate.a = minf(1, t.age / 0.4)
		if t.age >= 0.4: teleports.erase(t)
	if _flash_age < 1:
		_flash_age += delta; _flash.color = Color(_flash_color, _flash_color.a * maxf(0, 1 - _flash_age))
		if _flash_age >= 1: _flash.hide()

func _draw() -> void:
	super._draw(); _draw_scroll_particles(self, false)
	for t in transmutations:
		if not is_instance_valid(t.actor.sprite) or not t.actor.sprite.visible: continue
		var age: float = t.age
		var old_alpha: float = 0.6 * (age / 0.2 if age < 0.2 else 1 - (age - 0.2) / 1.4 if age < 1.6 else 0)
		var new_alpha := 0.0 if age < 0.2 else 0.6 * ((age - 0.2) / 1.4 if age < 1.6 else 1 - (age - 1.6) / 0.4)
		for spec in [[t.old, old_alpha, minf(1, age / 0.2)], [t.new, new_alpha, 1.0 if age < 1.6 else 1 + (age - 1.6) / 0.4]]:
			var texture: Texture2D = spec[0]
			var size := texture.get_size() * float(spec[2])
			var pos := actor_point(t.actor) + Vector2(0, -7.5 - texture.get_height())
			draw_texture_rect(texture, Rect2(pos - Vector2(size.x / 2, 0), size), false, Color(1, 1, 1, spec[1]))

func _draw_light() -> void:
	super._draw_light(); _draw_scroll_particles(light, true)

func _draw_flares() -> void:
	for data in flares:
		var p: float = data.age / float(data.get("duration", 2)); var amplitude := p * 4 if p < 0.25 else (1 - p) * 1.333
		_flare_canvas.draw_set_transform(data.pos, PI / 4 + PI * data.age, Vector2.ONE * amplitude)
		var color: Color = data.color; color.a = amplitude; var rays: int = data.get("rays", 6)
		var radius: float = data.get("radius", 32)
		for ray in rays:
			var angle := ray * TAU / rays
			_flare_canvas.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2.from_angle(angle) * radius, Vector2.from_angle(angle + TAU / rays / 2) * radius]), PackedColorArray([color, color, color]), PackedVector2Array([Vector2(0.25, 0), Vector2(0.75, 0), Vector2(0.75, 0)]), _gradient)
	_flare_canvas.draw_set_transform(Vector2.ZERO)

func _draw_scroll_particles(canvas: Node2D, additive: bool) -> void:
	for particle in scroll_particles:
		if particle.light != additive: continue
		var p: float = particle.age / particle.life; var left := 1 - p
		var scale := Vector2.ONE; var color: Color = particle.color
		match particle.kind:
			"wool": scale = Vector2.ONE * left
			"heart": scale = Vector2.ONE * left; color.a = 1 - p * p
			"note": color.a = 1 - p * p
			"light": color.a = p * 5 if p < 0.2 else (1 - p) * 1.25; scale = Vector2.ONE * color.a
			"discover": color.a = 1 - p; scale = Vector2.ONE * minf(p, 1 - p) * 2
			"up": scale = Vector2.ONE * sqrt(minf(p, 1 - p) * 2)
			"scream": color.a = sqrt(minf(p, 1 - p) * 2); scale = Vector2.ONE * p * 7
			"change": color.a = sqrt(minf(p, 1 - p) * 2); scale.y = (1 + p) * 0.5; scale.x = scale.y * cos((particle.life - particle.age) * 15)
			"energy": color.a = left * left * 4 if left < 0.5 else (1 - left) * 2; scale = Vector2.ONE * float(particle.size)
			"shadow_up": color = Color(0.2667 * left, 0, 0.2667 * left, left * left * 4 if left < 0.5 else (1 - left) * 2); scale = Vector2.ONE * 6 * left
			"identification": color.a = pow(1 - absf(left - 0.5) * 2, 2); scale = Vector2.ONE * color.a * 3
		canvas.draw_set_transform(particle.pos, particle.angle, scale)
		if particle.frame < 0: canvas.draw_rect(Rect2(-0.5, -0.5, 1, 1), color)
		else:
			var columns := int(SPECKS.get_width() / 7); var frame: int = particle.frame
			canvas.draw_texture_rect_region(SPECKS, Rect2(-3.5, -3.5, 7, 7), Rect2((frame % columns) * 7, int(frame / columns) * 7, 7, 7), color)
	canvas.draw_set_transform(Vector2.ZERO)

func clear() -> void:
	super.clear(); scroll_particles.clear(); emitters.clear(); transmutations.clear()
	for t in teleports:
		if is_instance_valid(t.actor.sprite): t.actor.sprite.modulate.a = 1
	teleports.clear(); _flash_age = 1
	if _flash != null: _flash.hide()

func _exit_tree() -> void:
	if is_instance_valid(_flare_canvas) and _flare_canvas.get_parent() != self: _flare_canvas.queue_free()
