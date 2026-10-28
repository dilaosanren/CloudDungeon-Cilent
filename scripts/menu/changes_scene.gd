# Original ChangesScene palette, toast panel, icons and title background.
extends Control
const Log = preload("res://scripts/menu/change_log.gd")
const ChangeRow = preload("res://scripts/menu/change_row.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
var _canvas: Control
var _heading: Label
var _heading_icon: TextureRect
var _version: Label
var _back: Button
var _panel: Panel
var _scroll: ScrollContainer
var _content: Control
var _blocks: Array[Control] = []
var _click: AudioStreamPlayer
var _previous_go_back := true
var _layout_pending := false
var _laying_out := false

func _ready() -> void:
	_previous_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	var background := DungeonTitleBackground.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_canvas = Control.new()
	_canvas.theme = UiAssets.make_theme()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_canvas)
	_heading_icon = TextureRect.new()
	_heading_icon.texture = MenuAssets.icon("CHANGES")
	_heading_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_heading_icon)
	_heading = _label(_canvas, "", 12, Color("ffff44"))
	_version = _label(_canvas, "v%s · %s" % [Log.VERSION, Log.DATE], 8, Color("bbbbbb"))
	_back = Button.new()
	_back.add_theme_font_size_override("font_size", 8)
	UiAssets.apply_button_style(_back, "GREY_BUTTON_TR")
	_canvas.add_child(_back)
	_back.pressed.connect(func(): _click.play(); _return_menu())
	_panel = Panel.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", UiAssets.get_style("TOAST"))
	_canvas.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 6
	_canvas.add_child(_scroll)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_content.resized.connect(_queue_layout)
	_click = AudioStreamPlayer.new()
	_click.bus = &"SFX"
	_click.stream = preload("res://assets/inventory/click.mp3")
	add_child(_click)
	_build_entries()
	get_viewport().size_changed.connect(_layout)
	_layout()

func _label(parent: Node, caption: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = caption
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	UiAssets.apply_text_outline(label)
	parent.add_child(label)
	return label

func _build_entries() -> void:
	_heading.text = L10n.text("改动")
	_back.text = L10n.text("返回")
	for block in _blocks:
		_content.remove_child(block)
		block.queue_free()
	_blocks.clear()
	for section in Log.SECTIONS.size():
		var label := _label(_content, L10n.text(Log.SECTIONS[section]), 10, Color("ffff44"))
		_blocks.append(label)
		for entry in Log.ENTRIES:
			if entry.section != section: continue
			var row := ChangeRow.new()
			_content.add_child(row)
			row.configure(entry, Log.icon(entry.icon))
			row.minimum_size_changed.connect(_queue_layout)
			_blocks.append(row)
	_queue_layout()

func _layout() -> void:
	if not is_instance_valid(_canvas): return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var factor := minf(2, minf(safe.size.x / 220, safe.size.y / 190))
	_canvas.scale = Vector2.ONE * factor
	var dimensions := Vector2(minf(460, safe.size.x / factor), safe.size.y / factor)
	_canvas.size = dimensions
	_canvas.position = safe.position + Vector2((safe.size.x - dimensions.x * factor) / 2, 0)
	ScreenLayout.place(_heading_icon, Rect2(9, 10, 15, 15))
	ScreenLayout.place(_heading, Rect2(30, 7, dimensions.x - 84, 22))
	ScreenLayout.place(_back, Rect2(dimensions.x - 44, 8, 36, 20))
	ScreenLayout.place(_version, Rect2(9, 33, dimensions.x - 18, 15))
	ScreenLayout.place(_panel, Rect2(5, 53, dimensions.x - 10, dimensions.y - 60))
	ScreenLayout.place(_scroll, Rect2(11, 59, dimensions.x - 22, dimensions.y - 72))
	_queue_layout()

func _queue_layout() -> void:
	if _layout_pending or _laying_out or not is_inside_tree(): return
	_layout_pending = true
	_layout_content.call_deferred()

func _layout_content() -> void:
	_layout_pending = false
	if not is_instance_valid(_content): return
	_laying_out = true
	var width := maxf(1, _content.size.x)
	var top := 0.0
	for block in _blocks:
		block.position = Vector2(0, top)
		if block is Label:
			block.position = Vector2(4, top + 6)
			block.size = Vector2(width - 8, 18)
			top += 28
		else:
			top += block.layout_width(width)
	_content.custom_minimum_size.y = ceilf(top + 5)
	_laying_out = false

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_return_menu()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _return_menu()
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_build_entries()
		_layout()

func _return_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	get_tree().quit_on_go_back = _previous_go_back
