extends Node2D
## DelayedRockFall / Speck.ROCK, SPD 4.0.2. Public arena effects above fog.
const SPECKS = preload("res://assets/effects/specks.png")
const INTERVAL := 0.07
const COUNT := 10
const LIFE := 0.2
var emitters: Array[Dictionary] = []
var particles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var map_width := 36

func _ready() -> void:
	z_index = 111
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rng.randomize()
	set_process(false)

func play(cells: Array) -> void:
	for cell in cells: emitters.append({"cell":int(cell),"clock":0.0,"left":COUNT})
	set_process(not emitters.is_empty())

func is_presenting_action() -> bool:
	return not emitters.is_empty() or not particles.is_empty()

func clear() -> void:
	emitters.clear()
	particles.clear()
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	for particle in particles.duplicate():
		particle.age += delta
		if particle.age>=LIFE: particles.erase(particle); continue
		particle.pos.y += 64*delta
		particle.angle += particle.spin*delta
	for emitter in emitters.duplicate():
		emitter.clock += delta
		while emitter.clock>=INTERVAL and emitter.left>0:
			emitter.clock -= INTERVAL
			emitter.left -= 1
			var cell: int = emitter.cell
			particles.append({"age":0.0,"pos":Vector2(cell%map_width,cell/map_width)*16+Vector2(rng.randf_range(0,16),rng.randf_range(0,16)-64*LIFE),
				"angle":rng.randf()*TAU,"spin":rng.randf_range(-TAU,TAU),"scale":rng.randf_range(1,2)})
		if emitter.left==0: emitters.erase(emitter)
	queue_redraw()
	if not is_presenting_action(): set_process(false)

func _draw() -> void:
	var columns := SPECKS.get_width()/7
	var frame := Rect2((8%columns)*7,int(8/columns)*7,7,7)
	for particle in particles:
		var left := 1-float(particle.age)/LIFE
		var alpha := left*5 if left<0.2 else 1.0
		draw_set_transform(particle.pos,particle.angle,Vector2.ONE*float(particle.scale))
		draw_texture_rect_region(SPECKS,Rect2(-3.5,-3.5,7,7),frame,Color(1,1,1,alpha))
	draw_set_transform(Vector2.ZERO)
