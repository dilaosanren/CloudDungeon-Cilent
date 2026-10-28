class_name MeleeEffects
extends MissileEffects
const SURPRISE_FRAME := Rect2(0, 16, 6, 9) # SPD Effects.EXCLAMATION.
var surprises: Array[Dictionary] = []
var surprise_canvas: Node2D

func _ready() -> void:
	super._ready()
	surprise_canvas = Node2D.new()
	surprise_canvas.name = "Surprises"
	surprise_canvas.z_index = 120
	surprise_canvas.draw.connect(_draw_surprises)
	add_child(surprise_canvas)

func surprise(actor: WandActor) -> void:
	var center := actor_point(actor)
	surprises.append({"pos":center, "age":0.0})
	history.append({"kind":"surprise", "pos":center, "actor":int(actor.data.get("net_id", -1))})
	surprise_canvas.queue_redraw()

func advance(delta: float) -> void:
	super.advance(delta)
	for effect in surprises.duplicate():
		effect.age += delta
		if effect.age >= 1: surprises.erase(effect)
	if surprise_canvas != null: surprise_canvas.queue_redraw()

func _draw_surprises() -> void:
	# SPD Surprise: fixed sprite center, 1s fade, alpha=sqrt(p), scale=(1+p/4,1+p).
	for effect in surprises:
		var p := maxf(0, 1 - float(effect.age))
		var size := SURPRISE_FRAME.size * Vector2(1 + p / 4, 1 + p)
		surprise_canvas.draw_texture_rect_region(ATLAS, Rect2(effect.pos - size / 2, size), SURPRISE_FRAME, Color(1, 1, 1, sqrt(p)))

func clear() -> void:
	super.clear()
	surprises.clear()
	if surprise_canvas != null: surprise_canvas.queue_redraw()

func sound(name: String, pitch: float = 1.0) -> void:
	var path := "res://assets/melee/source/%s.mp3" % name
	if not ResourceLoader.exists(path): super.sound(name, pitch); return
	if not sound_enabled or not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var player := AudioStreamPlayer.new(); player.stream = load(path); player.pitch_scale = pitch
	player.bus = &"SFX"
	add_child(player); player.finished.connect(player.queue_free); player.play()
