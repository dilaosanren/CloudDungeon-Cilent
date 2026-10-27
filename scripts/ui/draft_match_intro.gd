extends Control
## Presentation only, driven by the market's authoritative intro deadline.
const ENTER_SECONDS := 0.4
const HOLD_UNTIL := 1.4
const NAME_SECONDS := 2.0
var opponent_bar: ColorRect
var own_bar: ColorRect
var opponent_name: Label
var own_name: Label
var vs: Label
var elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	opponent_bar = _bar()
	own_bar = _bar()
	opponent_name = _name(opponent_bar, 26)
	own_name = _name(own_bar, 26)
	vs = _name(self, 32)
	vs.text = "vs"
	vs.add_theme_color_override("font_color", Color("ffff44"))
	get_viewport().size_changed.connect(_layout)
	hide()

func _bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.65)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	return bar

func _name(parent: Node, font_size: int) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_override("font", UiAssets.get_native_ui_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiAssets.apply_text_outline(label)
	parent.add_child(label)
	return label

func configure(opponent: String, own: String) -> void:
	opponent_name.text = opponent
	own_name.text = own

func seek(seconds: float) -> void:
	elapsed = seconds
	visible = seconds >= 0 and seconds < NAME_SECONDS
	if visible: _layout()

func _layout() -> void:
	if not visible or opponent_bar == null: return
	var dimensions := get_viewport_rect().size
	position = Vector2.ZERO
	size = dimensions
	var width := dimensions.x
	var height := clampf(dimensions.y * 0.1, 42, 68)
	var top_x := 0.0
	if elapsed < ENTER_SECONDS:
		var progress := clampf(elapsed / ENTER_SECONDS, 0, 1)
		top_x = -width * pow(1 - progress, 3)
	elif elapsed >= HOLD_UNTIL:
		var progress := clampf((elapsed - HOLD_UNTIL) / (NAME_SECONDS - HOLD_UNTIL), 0, 1)
		top_x = width * progress * progress * progress
	ScreenLayout.place(opponent_bar, Rect2(top_x, dimensions.y * 0.37 - height / 2, width, height))
	ScreenLayout.place(own_bar, Rect2(-top_x, dimensions.y * 0.63 - height / 2, width, height))
	for label in [opponent_name, own_name]:
		var font := UiAssets.get_native_ui_font()
		var font_size := 26
		while font_size > 10 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width - 24:
			font_size -= 1
		label.add_theme_font_size_override("font_size", font_size)
		ScreenLayout.place(label, Rect2(12, 0, width - 24, height))
	ScreenLayout.place(vs, Rect2(0, dimensions.y / 2 - 24, width, 48))
	vs.visible = elapsed >= ENTER_SECONDS and elapsed < HOLD_UNTIL
