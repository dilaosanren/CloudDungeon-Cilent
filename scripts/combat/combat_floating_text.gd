# FloatingText.reset/update + RenderedText logical height. GPL-3.0-or-later.
class_name CombatFloatingText
extends Node2D

signal expired(popup: CombatFloatingText)

const LIFESPAN := 1.0
const DISTANCE := 16.0
var text: String = ""
var text_color := Color.WHITE
var icon_id: int = CombatTextAssets.Icon.NO_ICON
var icon_left: bool = true
var stack_key: Variant = null
var is_buff_name := false
var time_left: float = LIFESPAN
var logical_size := Vector2.ZERO
var pixel_zoom: float = 2.0
var _runs: Array[Dictionary] = []
var _text_width: float = 0.0
var _finished: bool = false
var _raster_scale: float = 1.0
var _canvases: Array[Node2D] = []
var _icon: Sprite2D
var _pixel_material: ShaderMaterial
var _collision_bounds := Rect2()

func reset(anchor: Vector2, value: String, color: Color, icon: int, zoom: float, left: bool = true) -> void:
	text = value
	text_color = color
	icon_id = icon if CombatTextAssets.icon_texture(icon) != null else CombatTextAssets.Icon.NO_ICON
	icon_left = left
	pixel_zoom = maxf(1, zoom)
	# Rasterize 9*screenZoom, then draw at 1/screenZoom like FloatingText/RenderedText.
	_raster_scale = maxi(1, roundi(CombatTextAssets.FONT_SIZE * pixel_zoom)) / float(CombatTextAssets.FONT_SIZE)
	_build_text_runs()
	# SPD measures RenderedText at 9*defaultZoom, then scales back by 1/defaultZoom.
	logical_size = Vector2(_text_width + (6.5 if icon_id != CombatTextAssets.Icon.NO_ICON else 0),
		roundf(CombatTextAssets.FONT_SIZE * pixel_zoom * 0.75) / pixel_zoom)
	_measure_collision_bounds()
	position = ((anchor - Vector2(logical_size.x / 2, logical_size.y)) * pixel_zoom).floor() / pixel_zoom
	time_left = LIFESPAN
	_finished = false
	modulate = Color.WHITE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_visuals()
	_snap_visuals()

## Include CJK ascenders/descenders, outlines and 8px damage icons rather than
## treating every word as the shorter numeric font's logical line height.
func _measure_collision_bounds() -> void:
	var top := 0.0
	var bottom := maxf(logical_size.y, 8 if icon_id != CombatTextAssets.Icon.NO_ICON else 0)
	var padding := 0.0
	for run in _runs:
		var font: Font = run.font
		var factor := _raster_scale if run.pixel else 1.0
		var outline := float(run.outline) / factor
		padding = maxf(padding, outline)
		top = minf(top, logical_size.y - font.get_ascent(run.raster_size) / factor - outline)
		bottom = maxf(bottom, logical_size.y + font.get_descent(run.raster_size) / factor + outline)
	_collision_bounds = Rect2(-padding, top, logical_size.x + padding * 2, bottom - top)

func collision_rect() -> Rect2:
	return Rect2(position + _collision_bounds.position, _collision_bounds.size)

## Like PlatformSupport: the source pixel TTF for its supported glyphs, CJK fallback otherwise.
## Split runs so a Chinese word does not force neighboring digits/English into the CJK font.
func _build_text_runs() -> void:
	_runs.clear()
	var pixel_font := UiAssets.get_pixel_font()
	for character in text:
		var is_pixel := pixel_font.has_char(character.unicode_at(0))
		var font: Font = pixel_font if is_pixel else UiAssets.get_font()
		if _runs.is_empty() or _runs.back().font != font:
			_runs.append({"font": font, "text": character, "pixel": is_pixel})
		else:
			var run: Dictionary = _runs.back()
			run.text += character
	_text_width = 0
	for run in _runs:
		var font: Font = run.font
		run.offset = _text_width
		run.raster_size = roundi(CombatTextAssets.FONT_SIZE * _raster_scale) if run.pixel else CombatTextAssets.FONT_SIZE
		run.outline = maxi(1, roundi(run.raster_size / 10.0)) if run.pixel else UiAssets.TEXT_OUTLINE_SIZE
		var factor := _raster_scale if run.pixel else 1.0
		_text_width += font.get_string_size(run.text, HORIZONTAL_ALIGNMENT_LEFT, -1, run.raster_size).x / factor

func _build_visuals() -> void:
	for canvas in _canvases:
		remove_child(canvas)
		canvas.queue_free()
	_canvases.clear()
	if is_instance_valid(_icon):
		remove_child(_icon)
		_icon.queue_free()
	_icon = null
	_pixel_material = ShaderMaterial.new()
	_pixel_material.shader = preload("res://scripts/combat/pixel_font_coverage.gdshader")
	_pixel_material.set_shader_parameter("render_count", 2.0 if CombatTextAssets.FONT_SIZE * _raster_scale >= 20 else 3.0)
	for run in _runs:
		var canvas := Node2D.new()
		canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if run.pixel: canvas.material = _pixel_material
		add_child(canvas)
		canvas.draw.connect(_draw_text_run.bind(canvas, run))
		_canvases.append(canvas)
	var texture := CombatTextAssets.icon_texture(icon_id)
	if texture != null:
		_icon = Sprite2D.new()
		_icon.texture = texture
		_icon.centered = false
		_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Same as the source: draw the icon after the text, keeping its original colors.
		add_child(_icon)

func _draw_text_run(canvas: Node2D, run: Dictionary) -> void:
	var inset := 6.5 if icon_id != CombatTextAssets.Icon.NO_ICON and icon_left else 0.0
	var font: Font = run.font
	var factor := _raster_scale if run.pixel else 1.0
	var baseline := Vector2(roundf((inset + run.offset) * pixel_zoom) / pixel_zoom, logical_size.y) * factor
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE / factor)
	font.draw_string_outline(canvas.get_canvas_item(), baseline, run.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		run.raster_size, run.outline, Color.BLACK)
	font.draw_string(canvas.get_canvas_item(), baseline, run.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		run.raster_size, text_color)

## Keep the world trajectory continuous; align only the rendered glyphs/icon to display pixels.
func _snap_visuals() -> void:
	if not is_inside_tree(): return
	var transform := get_viewport().get_final_transform() * get_global_transform_with_canvas()
	# basis_xform_inv assumes an orthonormal basis; map/window scaling needs affine_inverse.
	var shift := transform.affine_inverse().basis_xform(transform.origin.round() - transform.origin)
	for canvas in _canvases: canvas.position = shift
	if is_instance_valid(_icon):
		var point := Vector2(0 if icon_left else logical_size.x - CombatTextAssets.ICON_SIZE.x, 0)
		point.x = roundf(point.x * pixel_zoom) / pixel_zoom
		_icon.position = shift + point

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if _finished or delta <= 0: return
	time_left -= delta
	if time_left <= 0:
		time_left = 0
		_finished = true
		expired.emit(self)
		queue_free()
		return
	position.y -= DISTANCE / LIFESPAN * delta
	_snap_visuals()
	var percent := time_left / LIFESPAN
	modulate.a = 1.0 if percent > 0.5 else percent * 2
