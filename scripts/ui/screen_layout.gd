## Shared viewport/safe-area layout for portrait phones, tablets and desktop previews.
class_name ScreenLayout
extends RefCounted

## Empty uses the platform safe area. Tests can supply a physical screen rectangle.
static var safe_area_override := Rect2i()

static func safe_rect(viewport: Viewport) -> Rect2:
	var logical := viewport.get_visible_rect().size
	var window := viewport.get_window()
	var physical := Rect2(Vector2(window.position), Vector2(window.size))
	var area := safe_area_override
	if area.size == Vector2i.ZERO:
		if not OS.has_feature("mobile"):
			return Rect2(Vector2.ZERO, logical)
		area = DisplayServer.get_display_safe_area()
	return project_safe_rect(logical, physical, Rect2(area))

static func project_safe_rect(logical: Vector2, window: Rect2, device_safe: Rect2) -> Rect2:
	if window.size.x <= 0 or window.size.y <= 0:
		return Rect2(Vector2.ZERO, logical)
	var clipped := window.intersection(device_safe)
	if not clipped.has_area():
		return Rect2(Vector2.ZERO, logical)
	var ratio := logical / window.size
	# Round inward so a border cannot land under a notch due to fractional scaling.
	var start := ((clipped.position - window.position) * ratio).ceil()
	var end := ((clipped.end - window.position) * ratio).floor()
	return Rect2(start, (end - start).max(Vector2.ZERO))

static func integer_fit(content: Vector2, available: Vector2) -> int:
	return maxi(1, floori(minf(available.x / content.x, available.y / content.y)))

static func place(control: Control, rect: Rect2) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.position = rect.position
	control.size = rect.size
