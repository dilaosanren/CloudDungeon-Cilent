# WndSettings.java / CheckBox.java adaptation. GPL-3.0-or-later.
extends CanvasLayer

signal closed

const Art = preload("res://scripts/ui/ui_assets.gd")
const MenuArt = preload("res://scripts/menu/menu_assets.gd")
const OptionSliderView = preload("res://scripts/menu/settings_slider.gd")
const Layout = preload("res://scripts/ui/screen_layout.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const PANEL_SIZE := Vector2(158, 190)
const TOTAL_SIZE := Vector2(158, 215)
static var last_tab := 0
var setup_finished := false

var _blocker: Control
var _window: Control
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _heading: Label
var _save_status: Label
var _click: AudioStreamPlayer
var _close_button: Button
var _previous_go_back := true

func _ready() -> void:
	layer = 100
	_previous_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	_blocker = Control.new()
	add_child(_blocker)
	_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_blocker.gui_input.connect(_outside_input)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blocker.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window = Control.new()
	_window.theme = Art.make_theme()
	_window.theme.default_font_size = 9
	_window.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	_window.size = TOTAL_SIZE
	_blocker.add_child(_window)
	var panel := Panel.new()
	panel.size = PANEL_SIZE
	panel.add_theme_stylebox_override("panel", Art.get_style("WINDOW"))
	_window.add_child(panel)
	_heading = _label(panel, "", Rect2(8, 6, 142, 14), 9, Color("ffff44"))
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var separator := ColorRect.new()
	separator.color = Color.BLACK
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(separator, Rect2(8, 23, 142, 1))
	panel.add_child(separator)
	for i in 3:
		var page := Control.new()
		_place(page, Rect2(8, 27, 142, 116))
		panel.add_child(page)
		_pages.append(page)
	_build_display(_pages[0])
	_build_audio(_pages[1])
	_build_language(_pages[2])
	_save_status = _label(panel, "更改会自动生效并保存", Rect2(8, 145, 142, 14), 7, Color("bbbbbb"))
	_save_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var close := _button(panel, "关闭", Rect2(8, 165, 142, 18))
	_close_button = close
	close.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	close.text = "Close" if L10n.is_english() else "关闭"
	close.pressed.connect(func(): _click.play(); _close())
	for i in 3:
		var tab := _button(_window, ["显示", "音频", "语言"][i], Rect2(i * 53, 189, 52, 25))
		tab.add_theme_font_size_override("font_size", 7)
		if i < 2: tab.icon = MenuArt.icon("DISPLAY_PORT" if i == 0 else "AUDIO")
		tab.pressed.connect(func(): _click.play(); _select_tab(i))
		_tabs.append(tab)
	_click = AudioStreamPlayer.new()
	_click.stream = preload("res://assets/inventory/click.mp3")
	add_child(_click)
	ClientPrefs.save_finished.connect(_saved)
	get_viewport().size_changed.connect(_layout)
	_select_tab(last_tab)
	_layout()
	close.grab_focus()
	setup_finished = true

func _build_display(page: Control) -> void:
	var top := 0.0
	if not OS.has_feature("mobile"):
		_checkbox(page, "全屏模式", Rect2(0, top, 142, 20), &"fullscreen")
		top += 24
	_slider(page, "亮度", "暗", "亮", Rect2(0, top, 142, 29), &"brightness", -1, 1, ["暗", "标准", "亮"])
	_slider(page, "网格可视度", "关闭", "最高", Rect2(0, top + 33, 142, 29), &"visual_grid", -1, 2, ["关闭", "低", "中", "最高"])
	_label(page, "亮度与网格设置在地牢中生效。", Rect2(0, top + 69, 142, 20), 7, Color("bbbbbb"))

func _build_audio(page: Control) -> void:
	_slider(page, "音效音量", "0", "10", Rect2(0, 0, 142, 29), &"sfx_volume", 0, 10)
	_checkbox(page, "关闭音效", Rect2(0, 34, 142, 20), &"sfx_enabled", true)
	_label(page, "包括脚步、攻击、物品和界面音效。", Rect2(0, 62, 142, 30), 7, Color("bbbbbb"))

func _build_language(page: Control) -> void:
	_label(page, "选择界面语言", Rect2(0, 0, 142, 18), 9, Color("ffff44"))
	var language := OptionButton.new()
	language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language.add_item("中文")
	language.add_item("English")
	language.select(1 if str(ClientPrefs.value(&"language")) == "en" else 0)
	Art.apply_button_style(language)
	page.add_child(language)
	_place(language, Rect2(0, 24, 142, 24))
	language.item_selected.connect(func(index: int):
		ClientPrefs.set_value(&"language", "en" if index == 1 else "zh")
		_click.play())
	_label(page, "语言更改立即生效，并在下次启动时保留。", Rect2(0, 58, 142, 46), 7, Color("bbbbbb"))

func _slider(parent: Control, title: String, low: String, high: String, rect: Rect2, key: StringName, minimum: int, maximum: int, names: Array[String] = []) -> void:
	var slider := OptionSliderView.new()
	parent.add_child(slider)
	slider.configure(title, low, high, minimum, maximum, int(ClientPrefs.value(key)), names)
	_place(slider, rect)
	slider.selected.connect(func(selected: int):
		ClientPrefs.set_value(key, selected)
		if key == &"sfx_volume": _click.play())

func _checkbox(parent: Control, title: String, rect: Rect2, key: StringName, inverted: bool = false) -> void:
	var button := _button(parent, "", rect)
	button.toggle_mode = true
	button.button_pressed = bool(ClientPrefs.value(key)) != inverted
	button.tooltip_text = title
	_label(button, title, Rect2(5, 0, rect.size.x - 24, rect.size.y), 9)
	var icon := TextureRect.new()
	icon.texture = MenuArt.icon("CHECKED" if button.button_pressed else "UNCHECKED")
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(icon, Rect2(rect.size.x - 16, (rect.size.y - 12) / 2, 12, 12))
	button.add_child(icon)
	button.toggled.connect(func(checked: bool):
		icon.texture = MenuArt.icon("CHECKED" if checked else "UNCHECKED")
		ClientPrefs.set_value(key, checked != inverted)
		_click.play())

func _button(parent: Control, title: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.text = title
	Art.apply_button_style(button)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := button.get_theme_stylebox(state)
		for side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
			style.set_content_margin(side, 2)
	parent.add_child(button)
	_place(button, rect)
	return button

func _label(parent: Control, text: String, rect: Rect2, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", Art.get_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Art.apply_text_outline(label)
	parent.add_child(label)
	# Give wrapping a real width before adding text. Otherwise the initial
	# zero-width layout makes every character a line and clamps the height,
	# leaving centered captions far below their buttons even after reflow.
	_place(label, rect)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	_place(label, rect)
	return label

func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size

func _select_tab(index: int) -> void:
	last_tab = clampi(index, 0, 2)
	_heading.text = ["显示设置", "音频设置", "语言设置"][last_tab]
	for i in _pages.size():
		_pages[i].visible = i == last_tab
		var style_name := "TAB_SELECTED" if i == last_tab else "TAB_UNSELECTED"
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var style: StyleBoxTexture = Art.get_style(style_name).duplicate()
			for side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
				style.set_content_margin(side, 2)
			_tabs[i].add_theme_stylebox_override(state, style)
		_tabs[i].add_theme_color_override("font_color", Color("ffff44") if i == last_tab else Color.WHITE)

func _saved(success: bool) -> void:
	_save_status.text = "已自动保存" if success else "无法保存设置，本次更改仍然生效"
	_save_status.add_theme_color_override("font_color", Color("bbbbbb") if success else Color("ffff44"))

func _layout() -> void:
	var safe := Layout.safe_rect(get_viewport())
	_tabs[0].icon = MenuArt.icon("DISPLAY_LAND" if safe.size.x > safe.size.y else "DISPLAY_PORT")
	var factor := minf(2, minf((safe.size.x - 12) / TOTAL_SIZE.x, (safe.size.y - 16) / TOTAL_SIZE.y))
	_window.scale = Vector2.ONE * factor
	_window.position = (safe.position + (safe.size - TOTAL_SIZE * factor) / 2).floor()

func _outside_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _close()
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_close_button):
		_close_button.text = "Close" if L10n.is_english() else "关闭"

func _exit_tree() -> void:
	get_tree().quit_on_go_back = _previous_go_back

func _close() -> void:
	if is_queued_for_deletion(): return
	if is_instance_valid(_blocker): _blocker.hide()
	if is_instance_valid(_click) and _click.playing:
		_click.reparent(get_tree().root)
		_click.finished.connect(_click.queue_free, CONNECT_ONE_SHOT)
	closed.emit()
	queue_free()
