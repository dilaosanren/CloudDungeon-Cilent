# MenuPane.MenuButton / WndGame: original icon, 120px buttons and 2px gaps.
extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")
const Social = preload("res://scripts/pvp/net/battle_social.gd")
signal opened
signal closed
signal control_requested(intent: Dictionary)
var menu_button: Button
var menu_buttons := {}
var chat_input: LineEdit
var send_button: Button
var confirm_button: Button
var panel: Panel
var messages: VBoxContainer
var transcript: ScrollContainer
var _badge: Label
var _shade: ColorRect
var _status: Label
var _state := {}
var _mode := ""
var _draft_text := ""
var _pending_kind := ""
var _pending_deadline := 0
var _pending_serial := -1
var _chat_key := ""
var _seen_chat_id := 0
var _available := true
var _safe := Rect2()
var _base_size := Vector2.ZERO
var _keyboard_height := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_button = Button.new()
	menu_button.name = "BattleMenuButton"
	menu_button.tooltip_text = L10n.text("菜单")
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var icon := AtlasTexture.new()
	icon.atlas = preload("res://assets/ui/source/menu_button.png")
	icon.region = Rect2(17, 2, 12, 11)
	menu_button.icon = icon
	for style in ["normal", "hover", "pressed", "disabled", "focus"]: menu_button.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	menu_button.pressed.connect(open_menu)
	add_child(menu_button)
	_badge = Label.new()
	_badge.text = "!"
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge.add_theme_font_size_override("font_size", 7)
	_badge.add_theme_color_override("font_color", Color("ffff44"))
	_badge.position = Vector2(12, 0)
	_badge.hide()
	menu_button.add_child(_badge)
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	_shade = ColorRect.new()
	_shade.color = Color(0, 0, 0, 0.55)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.gui_input.connect(_outside)
	layer.add_child(_shade)
	_shade.hide()
	visibility_changed.connect(func():
		if not is_visible_in_tree(): close())

func is_open() -> bool:
	return is_instance_valid(_shade) and _shade.visible

func set_available(value: bool) -> void:
	_available = value
	menu_button.disabled = not value or int(_state.get("phase", -1)) != PvpProtocol.Phase.BATTLE
	if not value: close()

func sync(state: Dictionary) -> void:
	if str(_state.get("match_id", "")) != str(state.get("match_id", "")):
		close()
		_seen_chat_id = 0
		_draft_text = ""
		_pending_kind = ""
		_pending_serial = -1
		_chat_key = ""
	_state = state
	if int(state.get("phase", -1)) != PvpProtocol.Phase.BATTLE: close()
	set_available(_available)
	var key := JSON.stringify(state.get("battle_chat", []))
	if key != _chat_key:
		_chat_key = key
		if _mode == "chat" and is_open(): _refresh_messages()
	_badge.visible = false
	for message in state.get("battle_chat", []):
		if int(message.id) > _seen_chat_id and int(message.seat) != int(state.get("seat", -1)): _badge.show()

func _show(mode: String, dimensions: Vector2) -> void:
	var was_open := is_open()
	if is_instance_valid(panel):
		panel.hide()
		panel.queue_free()
	_status = null
	chat_input = null
	send_button = null
	confirm_button = null
	menu_buttons.clear()
	_mode = mode
	_base_size = dimensions
	panel = Panel.new()
	panel.theme = UiAssets.make_theme()
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", UiAssets.get_style("WINDOW"))
	_shade.add_child(panel)
	panel.size = dimensions
	_shade.show()
	if not was_open: opened.emit()

func _label(text: String, rect: Rect2, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_text_outline(label)
	panel.add_child(label)
	label.position = rect.position
	label.size = rect.size
	label.text = text
	return label

func _button(text: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = L10n.text(text)
	button.add_theme_font_size_override("font_size", 8)
	UiAssets.apply_button_style(button)
	panel.add_child(button)
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(action)
	return button

func open_menu() -> void:
	if menu_button.disabled: return
	_show("menu", Vector2(132, 94))
	_label(L10n.text("菜单"), Rect2(6, 5, 120, 14), Color("ffff44")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_buttons.chat = _button("对话", Rect2(6, 24, 120, 20), open_chat)
	menu_buttons.emote = _button("发送表情", Rect2(6, 46, 120, 20), func(): pass)
	menu_buttons.emote.disabled = true
	menu_buttons.emote.tooltip_text = L10n.text("暂未开放")
	menu_buttons.surrender = _button("投降", Rect2(6, 68, 120, 20), _confirm_surrender)
	menu_buttons.chat.disabled = not _pending_kind.is_empty()
	menu_buttons.surrender.disabled = not _pending_kind.is_empty()
	place(_safe, menu_button.scale.x)

func open_chat() -> void:
	if menu_button.disabled: return
	_show("chat", Vector2(160, 210))
	_label(L10n.text("对话"), Rect2(6, 5, 148, 14), Color("ffff44")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transcript = ScrollContainer.new()
	transcript.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(transcript)
	transcript.position = Vector2(6, 25)
	transcript.size = Vector2(148, 108)
	messages = VBoxContainer.new()
	messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	messages.add_theme_constant_override("separation", 5)
	transcript.add_child(messages)
	chat_input = LineEdit.new()
	chat_input.max_length = Social.MAX_TEXT_LENGTH
	chat_input.placeholder_text = L10n.text("输入消息，最多80字")
	chat_input.add_theme_font_size_override("font_size", 8)
	panel.add_child(chat_input)
	chat_input.position = Vector2(6, 139)
	chat_input.size = Vector2(148, 20)
	chat_input.text = _draft_text
	chat_input.text_changed.connect(func(value): _draft_text = value)
	chat_input.text_submitted.connect(func(_value): _send_chat())
	_status = _label("", Rect2(6, 162, 148, 17))
	_status.add_theme_font_size_override("font_size", 6)
	send_button = _button("发送", Rect2(6, 184, 72, 20), _send_chat)
	_button("返回", Rect2(82, 184, 72, 20), open_menu)
	chat_input.editable = _pending_kind.is_empty()
	send_button.disabled = not _pending_kind.is_empty()
	_refresh_messages()
	place(_safe, menu_button.scale.x)

func _refresh_messages() -> void:
	if _mode != "chat" or not is_instance_valid(messages): return
	for child in messages.get_children(): child.free()
	var names := L10n.player_names(_state)
	for message in _state.get("battle_chat", []):
		var author := int(message.seat)
		var label := Label.new()
		label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 7)
		label.add_theme_color_override("font_color", Color("ffff88") if author == int(_state.get("seat", -1)) else Color.WHITE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text = "%s：%s" % [str(names[author]) if author >= 0 and author < names.size() else L10n.text("对方"), str(message.text)]
		messages.add_child(label)
		_seen_chat_id = maxi(_seen_chat_id, int(message.id))
	_badge.hide()
	transcript.set_deferred("scroll_vertical", 100000)

func _send_chat() -> void:
	if not _pending_kind.is_empty() or not is_instance_valid(chat_input): return
	if not Social.valid_text(chat_input.text):
		_status.text = L10n.text("请输入1至80字的消息。")
		return
	_request({"kind":"chat", "text":chat_input.text.strip_edges()})

func _confirm_surrender() -> void:
	_show("surrender", Vector2(148, 100))
	_label(L10n.text("确认投降？"), Rect2(6, 6, 136, 15), Color("ffff44")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(L10n.text("投降后本局判负。"), Rect2(6, 29, 136, 16))
	_status = _label("", Rect2(6, 48, 136, 18))
	_status.add_theme_font_size_override("font_size", 6)
	confirm_button = _button("投降", Rect2(6, 74, 66, 20), func(): _request({"kind":"surrender"}))
	_button("取消", Rect2(76, 74, 66, 20), open_menu)
	place(_safe, menu_button.scale.x)

func _request(intent: Dictionary) -> void:
	if not _pending_kind.is_empty(): return
	_pending_kind = str(intent.kind)
	_pending_serial = -1
	_pending_deadline = Time.get_ticks_msec() + 10000
	_status.text = L10n.text("正在发送…")
	if is_instance_valid(send_button): send_button.disabled = true
	if is_instance_valid(chat_input): chat_input.editable = false
	if is_instance_valid(confirm_button): confirm_button.disabled = true
	control_requested.emit(intent)

func expect_ack_serial(serial: int) -> void:
	_pending_serial = serial

func complete(result: Dictionary) -> void:
	if _pending_serial >= 0 and result.has("request_id") and int(result.request_id) != _pending_serial: return
	_pending_kind = ""
	_pending_serial = -1
	for key in ["chat", "surrender"]:
		if menu_buttons.has(key): menu_buttons[key].disabled = false
	if is_instance_valid(send_button): send_button.disabled = false
	if is_instance_valid(chat_input): chat_input.editable = true
	if is_instance_valid(confirm_button): confirm_button.disabled = false
	if result.has("error"):
		if is_instance_valid(_status): _status.text = L10n.render(str(result.error))
	elif result.get("kind") == "chat":
		_draft_text = ""
		if is_instance_valid(chat_input): chat_input.text = ""
		if is_instance_valid(_status): _status.text = ""

func close() -> void:
	if not is_open(): return
	if is_instance_valid(chat_input): chat_input.release_focus()
	_mode = ""
	_shade.hide()
	closed.emit()

func back() -> void:
	if _mode == "menu": close()
	else: open_menu()

func _outside(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed):
		close()
		get_viewport().set_input_as_handled()

func place(safe: Rect2, button_scale: float = 2.0) -> void:
	_safe = safe
	menu_button.scale = Vector2.ONE * button_scale
	menu_button.size = Vector2(16, 21)
	menu_button.position = Vector2(safe.end.x - 16 * button_scale - 6, safe.position.y + 2).floor()
	if not is_instance_valid(panel): return
	var available := safe
	if OS.has_feature("mobile"):
		var keyboard_top := (get_window().size.y - DisplayServer.virtual_keyboard_get_height()) * get_viewport_rect().size.y / maxf(1, get_window().size.y)
		available.size.y = maxf(80, minf(safe.end.y, keyboard_top) - safe.position.y)
	var factor := minf(2, minf((available.size.x - 12) / _base_size.x, (available.size.y - 12) / _base_size.y))
	panel.scale = Vector2.ONE * factor
	panel.position = (available.position + (available.size - _base_size * factor) / 2).floor()

func _process(_delta: float) -> void:
	if not _pending_kind.is_empty() and Time.get_ticks_msec() >= _pending_deadline:
		complete({"error":"请求超时，请重试。"})
	if OS.has_feature("mobile") and is_open():
		var height := DisplayServer.virtual_keyboard_get_height()
		if height != _keyboard_height:
			_keyboard_height = height
			place(_safe, menu_button.scale.x)
