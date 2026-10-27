# Literal geometry port of mechanics/ConeAOE.java (SPD 4.0.2), GPL-3.0-or-later.
class_name WandCone
extends RefCounted
var cells: Array[int] = []
var rays: Array[Ballistica] = []
var outer_rays: Array[Ballistica] = []
const G2R := 0.01745329238474369 # PointF's float32(3.1415926f / 180).

static func f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

func _init(core: Ballistica, max_distance: float, degrees: float, flags: int, level: BallisticLevel) -> void:
	var from := Vector2(level.cell_coords(core.source_pos)) + Vector2(0.5, 0.5)
	var to := Vector2(level.cell_coords(core.collision_pos)) + Vector2(0.5, 0.5)
	if from.distance_to(to) > max_distance: to = from.lerp(to, max_distance / from.distance_to(to))
	var radius := f32(from.distance_to(to) + 0.5)
	var initial_angle := f32((to - from).angle() / G2R)
	var angle := f32(initial_angle + degrees / 2.0)
	var targets: Array[int] = []
	var outer: Array[int] = []
	while angle >= f32(initial_angle - degrees / 2.0):
		for r in [radius, radius - 1] if radius >= 4 else [radius]:
			var p: Vector2 = from + Vector2.from_angle(f32(angle * G2R)) * r
			p += Vector2(0.5 if from.x > p.x else -0.5, 0.5 if from.y > p.y else -0.5)
			var cell := level.cell_id(Vector2i(clampi(int(floor(p.x)), 0, level.size.x - 1), clampi(int(floor(p.y)), 0, level.size.y - 1)))
			if cell not in targets: targets.append(cell)
			if r == radius and cell not in outer: outer.append(cell)
		angle = f32(angle - 0.5)
	for cell in targets:
		var ray := Ballistica.new(core.source_pos, cell, flags, level)
		rays.append(ray)
		for c in ray.sub_path(1, ray.dist):
			if c not in cells: cells.append(c)
		if cell in outer: outer_rays.append(ray)
