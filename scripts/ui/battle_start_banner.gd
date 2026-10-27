# Non-blocking match introduction; movement and turns remain server-owned.
extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")
const HOLD_SECONDS := 3.0
const ENTER_SECONDS := 0.35
const EXIT_SECONDS := 0.45

var _panel: Panel
var _label: Label
var _motion: Tween
var _phase := 0
var _progress := 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiAssets.get_style("TOAST_TR_HEAVY"))
	add_child(_panel)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", UiAssets.get_font())
	_label.add_theme_font_size_override("font_size", 26)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiAssets.apply_text_outline(_label)
	_panel.add_child(_label)
	get_viewport().size_changed.connect(_layout)
	hide()

func play(you_first: bool) -> void:
	cancel()
	_label.text = L10n.text("你先手！") if you_first else L10n.text("对手先手")
	_label.add_theme_color_override("font_color", Color("ffff44") if you_first else Color("ff4444"))
	show()
	_enter(0.0)
	_motion = create_tween()
	_motion.tween_method(_enter, 0.0, 1.0, ENTER_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_motion.tween_callback(_hold)
	_motion.tween_interval(HOLD_SECONDS)
	_motion.tween_method(_exit, 0.0, 1.0, EXIT_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_motion.finished.connect(_finished)

func cancel() -> void:
	if _motion != null:
		_motion.kill()
		_motion = null
	hide()

func _finished() -> void:
	_motion = null
	hide()

func _enter(value: float) -> void:
	_phase = 0
	_progress = value
	_layout()

func _hold() -> void:
	_phase = 1
	_progress = 1.0
	_layout()

func _exit(value: float) -> void:
	_phase = 2
	_progress = value
	_layout()

func _layout() -> void:
	if not visible or _panel == null: return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var width := minf(320, safe.size.x - 24)
	var height := 64.0
	_panel.size = Vector2(width, height)
	_label.position = Vector2(8, 4)
	_label.size = _panel.size - Vector2(16, 8)
	var middle := safe.position.y + (safe.size.y - height) / 2
	var y := middle
	if _phase == 0: y = lerpf(safe.end.y + height, middle, _progress)
	elif _phase == 2: y = lerpf(middle, -height - 8, _progress)
	_panel.position = Vector2(safe.position.x + (safe.size.x - width) / 2, y).floor()
