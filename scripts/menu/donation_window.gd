# WndSupportPrompt.java: original window, portrait/landscape widths and link/close buttons.
# Adapted for Cloud Dungeon's voluntary server and development support.
extends CanvasLayer
signal closed
const L10n = preload("res://scripts/menu/game_locale.gd")
const DONATION_URL := "https://afdian.com/a/dlsr1001"
const NOTICE := "捐献是用于服务器运行和游戏开发的自愿支付行为。\n\n正式版账号系统推出前，捐献不会提供任何福利。\n\n正式版推出后，捐献可能会给予外观奖励。"
var panel: Panel
var description: Label
var link_button: Button
var close_button: Button
var _scroll: ScrollContainer
var _status: Label
var _previous_go_back := true
var _closing := false

func _ready() -> void:
	layer = 100
	_previous_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = Panel.new()
	panel.theme = UiAssets.make_theme()
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_theme_stylebox_override("panel", UiAssets.get_style("WINDOW"))
	shade.add_child(panel)
	var icon := TextureRect.new()
	icon.texture = MenuAssets.icon("GOLD")
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(icon)
	icon.position = Vector2(6, 6)
	icon.size = icon.texture.get_size()
	var title := Label.new()
	title.text = L10n.text("捐献说明")
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color("ffff44"))
	UiAssets.apply_text_outline(title)
	panel.add_child(title)
	title.position = Vector2(10 + icon.size.x, 6)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_scroll)
	description = Label.new()
	description.text = L10n.text(NOTICE)
	description.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("font_size", 6)
	UiAssets.apply_text_outline(description)
	_scroll.add_child(description)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 6)
	_status.add_theme_color_override("font_color", Color("ffff44"))
	panel.add_child(_status)
	_status.hide()
	link_button = _button("前往爱发电", _donate)
	close_button = _button("关闭", close)
	get_viewport().size_changed.connect(_layout)
	_layout()
	close_button.grab_focus()

func _button(caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	button.text = "Close" if caption == "关闭" and L10n.is_english() else L10n.text(caption)
	button.add_theme_font_size_override("font_size", 7)
	UiAssets.apply_button_style(button)
	panel.add_child(button)
	button.pressed.connect(action)
	return button

func _layout() -> void:
	var safe := ScreenLayout.safe_rect(get_viewport())
	var width := 200.0 if safe.size.x > safe.size.y else 120.0
	var factor := minf(2, (safe.size.x - 12) / (width + 12))
	var available_height := (safe.size.y - 12) / factor
	# Measure the wrapped text at its actual width; scroll only on short screens.
	description.custom_minimum_size.x = width - 6
	description.size.x = width - 6
	var text_height := description.get_minimum_size().y
	var status_height := 24.0 if _status.visible else 0.0
	var body_height := minf(text_height, maxf(24, available_height - 76 - status_height))
	_scroll.position = Vector2(6, 26)
	_scroll.size = Vector2(width, body_height)
	_status.position = Vector2(6, 30 + body_height)
	_status.size = Vector2(width, status_height)
	link_button.position = Vector2(6, 30 + body_height + status_height)
	link_button.size = Vector2(width, 18)
	close_button.position = link_button.position + Vector2(0, 20)
	close_button.size = Vector2(width, 18)
	panel.size = Vector2(width + 12, close_button.position.y + 24)
	panel.scale = Vector2.ONE * factor
	panel.position = (safe.position + (safe.size - panel.size * factor) / 2).floor()

func _donate() -> void:
	if _open_url(DONATION_URL) == OK:
		close()
	else:
		_status.text = L10n.text("无法打开浏览器，请稍后重试。")
		_status.show()
		_layout()

func _open_url(url: String) -> Error:
	return OS.shell_open(url)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: close()

func close() -> void:
	if _closing: return
	_closing = true
	closed.emit()
	queue_free()

func _exit_tree() -> void:
	get_tree().quit_on_go_back = _previous_go_back
