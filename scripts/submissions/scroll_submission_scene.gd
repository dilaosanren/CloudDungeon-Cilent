extends Control
const Idea = preload("res://scripts/submissions/scroll_idea.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const DRAFT_PATH := "user://scroll-submission-draft.json"
const BASE_SIZE := Vector2(180, 280)
var _canvas: Control
var _header: Label
var _hint: Label
var _idea_input: TextEdit
var _counter: Label
var _status: Label
var _submit: Button
var _back: Button
var _pending_id := 0
var _request_deadline := 0
var _save_at := -1
var _syncing := false
var _previous_back := true

func _ready() -> void:
	_previous_back = get_tree().quit_on_go_back
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
	_header = _label("秘卷投稿", Rect2(8, 6, 164, 18), 12, Color("ffff44"))
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint = _label("写下你想设计的秘卷效果，最多150字。", Rect2(8, 30, 164, 30), 8)
	_idea_input = TextEdit.new()
	_idea_input.name = "IdeaInput"
	_idea_input.placeholder_text = L10n.text("描述秘卷使用后的效果…")
	_idea_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_idea_input.add_theme_font_size_override("font_size", 8)
	_canvas.add_child(_idea_input)
	_idea_input.position = Vector2(8, 64)
	_idea_input.size = Vector2(164, 136)
	_counter = _label("", Rect2(8, 204, 164, 12), 7, Color("bbbbbb"))
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status = _label("", Rect2(8, 220, 164, 24), 7, Color("bbbbbb"))
	_submit = _button("提交投稿", Rect2(8, 250, 104, 22), _submit_idea)
	_back = _button("返回", Rect2(116, 250, 56, 22), _return_menu)
	_load_draft()
	_idea_input.text_changed.connect(_text_changed)
	_text_changed()
	PvpNet.map_submission_result.connect(_result)
	PvpNet.server_status_changed.connect(_connection_changed)
	get_viewport().size_changed.connect(_layout)
	PvpNet.monitor_server()
	_connection_changed()
	_layout()

func _label(caption: String, rect: Rect2, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiAssets.apply_text_outline(label)
	_canvas.add_child(label)
	label.position = rect.position
	label.size = rect.size
	# Establish wrapping width before text, avoiding a stale tall minimum size.
	label.text = L10n.text(caption)
	return label

func _button(caption: String, rect: Rect2, action: Callable) -> Button:
	var button := Button.new()
	button.text = L10n.text(caption)
	button.add_theme_font_size_override("font_size", 8)
	UiAssets.apply_button_style(button, "GREY_BUTTON_TR")
	_canvas.add_child(button)
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(action)
	return button

func _text_changed() -> void:
	if _syncing: return
	if _idea_input.text.length() > Idea.MAX_LENGTH:
		_syncing = true
		var line := _idea_input.get_caret_line()
		var column := _idea_input.get_caret_column()
		_idea_input.text = _idea_input.text.left(Idea.MAX_LENGTH)
		_idea_input.set_caret_line(mini(line, _idea_input.get_line_count() - 1))
		_idea_input.set_caret_column(column)
		_syncing = false
		_status.text = L10n.text("秘卷设计想法最多150字。")
	_counter.text = "%d / %d" % [_idea_input.text.length(), Idea.MAX_LENGTH]
	_save_at = Time.get_ticks_msec() + 350
	_refresh_submit()

func _refresh_submit() -> void:
	_submit.disabled = _pending_id > 0 or not PvpNet.is_server_ready() or _idea_input.text.strip_edges().is_empty()
	_idea_input.editable = _pending_id == 0

func _connection_changed() -> void:
	if not PvpNet.is_server_ready():
		_pending_id = 0
		_status.text = L10n.text("服务器未连接，可先填写，草稿会保存在本机。")
	elif _status.text == L10n.text("服务器未连接，可先填写，草稿会保存在本机。"):
		_status.text = ""
	_refresh_submit()

func _submit_idea() -> void:
	if _pending_id > 0: return
	var checked := Idea.validate({"idea":_idea_input.text, "author":ClientPrefs.session_player_name()})
	if checked.has("error"):
		_status.text = L10n.text(str(checked.error))
		return
	_save_draft()
	var payload: Dictionary = checked.data.duplicate()
	payload.op = "submit_scroll"
	_pending_id = PvpNet.request_map_submissions(payload)
	if _pending_id == 0:
		_connection_changed()
		return
	_request_deadline = Time.get_ticks_msec() + 10000
	_status.text = L10n.text("正在提交…")
	_refresh_submit()

func _result(request_id: int, result: Dictionary) -> void:
	if _pending_id == 0 or request_id != _pending_id: return
	_pending_id = 0
	if result.has("error"):
		var message := str(result.error)
		_status.text = L10n.text("服务器暂不支持秘卷投稿，请稍后再试。" if message == "不支持的投稿操作。" else message)
	elif result.get("submission") is Dictionary:
		_idea_input.text = ""
		_save_draft()
		_status.text = L10n.text("投稿成功，感谢你的设计想法！")
	else: _status.text = L10n.text("投稿未完成，请重试。")
	_refresh_submit()

func _load_draft() -> void:
	if not FileAccess.file_exists(DRAFT_PATH): return
	var file := FileAccess.open(DRAFT_PATH, FileAccess.READ)
	if file == null or file.get_length() > 4096: return
	var saved: Variant = JSON.parse_string(file.get_as_text())
	if saved is Dictionary and saved.get("idea") is String: _idea_input.text = str(saved.idea).left(Idea.MAX_LENGTH)

func _save_draft() -> void:
	_save_at = -1
	if _idea_input.text.is_empty():
		if FileAccess.file_exists(DRAFT_PATH): DirAccess.remove_absolute(DRAFT_PATH)
		return
	var file := FileAccess.open(DRAFT_PATH, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify({"idea":_idea_input.text}))

func _layout() -> void:
	if _canvas == null: return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var factor := minf(2, minf(safe.size.x / BASE_SIZE.x, safe.size.y / BASE_SIZE.y))
	_canvas.scale = Vector2.ONE * factor
	_canvas.size = BASE_SIZE
	_canvas.position = (safe.position + (safe.size - BASE_SIZE * factor) / 2).floor()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _save_at >= 0 and now >= _save_at: _save_draft()
	if _pending_id > 0 and now >= _request_deadline:
		_pending_id = 0
		_status.text = L10n.text("投稿请求超时，想法已保留，请重试。")
		_refresh_submit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_return_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _return_menu()

func _return_menu() -> void:
	_save_draft()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	if is_instance_valid(_idea_input): _save_draft()
	get_tree().quit_on_go_back = _previous_back
	if PvpNet.map_submission_result.is_connected(_result): PvpNet.map_submission_result.disconnect(_result)
	if PvpNet.server_status_changed.is_connected(_connection_changed): PvpNet.server_status_changed.disconnect(_connection_changed)
