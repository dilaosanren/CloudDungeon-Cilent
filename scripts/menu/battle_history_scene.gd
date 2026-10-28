extends Control
const History = preload("res://scripts/menu/battle_history.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const NativeText = preload("res://scripts/ui/native_rich_text.gd")
const Record = preload("res://scripts/pvp/net/battle_record.gd")
var _records: Array[Dictionary] = []
var _index := 0
var _canvas: Control
var _scroll: ScrollContainer
var _content: VBoxContainer
var _columns: HBoxContainer
var _heading: Label
var _page: Label
var _previous: Button
var _next: Button
var _back: Button
var _note: Label
var _click: AudioStreamPlayer
var _previous_go_back := true
var _local_tab: Button
var _server_tab: Button
var _refresh: Button
var _source_server := false
var _server_record := {}
var _server_total := 0
var _server_loading := false
var _request_id := 0
var _request_deadline := 0
var _was_server_ready := false

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
	_heading = _label(_canvas, L10n.text("对战记录"), 12, Color("ffff44"))
	_back = _button(L10n.text("返回"), _return_menu)
	_local_tab = _button(L10n.text("本机记录"), func(): _choose_source(false))
	_server_tab = _button(L10n.text("服务器记录"), func(): _choose_source(true))
	_local_tab.toggle_mode = true
	_server_tab.toggle_mode = true
	_local_tab.button_pressed = true
	_refresh = _button(L10n.text("刷新"), func(): _request_server(0))
	_refresh.disabled = true
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 6
	_canvas.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 7)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_previous = _button(L10n.text("上一场"), func(): _select(_index + 1))
	_next = _button(L10n.text("下一场"), func(): _select(_index - 1))
	_page = _label(_canvas, "", 8, Color("bbbbbb"))
	_page.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note = _label(_canvas, L10n.text("记录保存在本机"), 6, Color("aaaaaa"))
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_click = AudioStreamPlayer.new()
	_click.bus = &"SFX"
	_click.stream = preload("res://assets/inventory/click.mp3")
	add_child(_click)
	_records = History.records()
	if History.save_error != OK:
		_note.text = L10n.text("对战记录保存失败，请检查本机存储空间。")
	get_viewport().size_changed.connect(_layout)
	_layout()
	_show_record()
	PvpNet.map_submission_result.connect(_history_reply)
	PvpNet.server_status_changed.connect(_connection_updated)
	PvpNet.monitor_server()
	_was_server_ready = PvpNet.is_server_ready()

func _label(parent: Node, caption: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.text = caption
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	UiAssets.apply_text_outline(label)
	parent.add_child(label)
	return label

func _text(parent: Node, caption: String, font_size: int = 8) -> Control:
	var text := NativeText.new()
	text.font_size = font_size
	text.text = caption
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(text)
	return text

func _escape(value: String) -> String:
	return value.replace("[", "[lb]")

func _button(caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.add_theme_font_size_override("font_size", 8)
	UiAssets.apply_button_style(button, "GREY_BUTTON_TR")
	_canvas.add_child(button)
	button.pressed.connect(func(): _click.play(); action.call())
	return button

func _select(index: int) -> void:
	if _source_server:
		_request_server(clampi(index, 0, maxi(0, _server_total - 1)))
		return
	_index = clampi(index, 0, maxi(0, _records.size() - 1))
	_show_record()
	_scroll.scroll_vertical = 0

func _choose_source(server: bool) -> void:
	_source_server = server
	_index = 0
	_request_id = 0
	_server_loading = false
	_local_tab.button_pressed = not server
	_server_tab.button_pressed = server
	if server:
		_request_server(0)
	else:
		_refresh.disabled = true
		_note.text = L10n.text("记录保存在本机") if History.save_error == OK else L10n.text("对战记录保存失败，请检查本机存储空间。")
		_show_record()
	_scroll.scroll_vertical = 0

func _request_server(index: int) -> void:
	if not _source_server or _server_loading: return
	_index = index
	_server_record = {}
	_refresh.disabled = true
	if not PvpNet.is_server_ready():
		_note.text = L10n.text("服务器未连接，连接后可刷新。")
		_show_record()
		return
	_server_loading = true
	_request_id = PvpNet.request_battle_history(index)
	_request_deadline = Time.get_ticks_msec() + 10000
	_note.text = L10n.text("服务器仅保留最近100局已结束的战斗")
	_show_record()
	_scroll.scroll_vertical = 0

func _history_reply(serial: int, result: Dictionary) -> void:
	if not _source_server or not _server_loading or serial != _request_id: return
	_request_id = 0
	_server_loading = false
	_refresh.disabled = not PvpNet.is_server_ready()
	if result.has("error"):
		_note.text = L10n.text("服务器暂不支持对战记录，请更新服务器。") if result.error == "不支持的投稿操作。" else L10n.render(str(result.error))
	else:
		var record := Record.normalize(result.get("record"))
		var total: Variant = result.get("total")
		var index: Variant = result.get("index")
		if not Record.whole(total) or int(total) < 0 or int(total) > Record.MAX_RECORDS or not Record.whole(index) or int(index) < 0 or int(index) >= maxi(1,int(total)) or (int(total) > 0 and record.is_empty()):
			_note.text = L10n.text("对战记录数据无效，请刷新重试。")
		else:
			_server_record = record
			_server_total = int(total)
			_index = int(index)
			_note.text = L10n.text("服务器仅保留最近100局已结束的战斗")
	_show_record()

func _connection_updated() -> void:
	var ready := PvpNet.is_server_ready()
	if _source_server:
		if not ready:
			_request_id = 0
			_server_loading = false
			_server_record = {}
			_note.text = L10n.text("服务器未连接，连接后可刷新。")
			_show_record()
		elif not _was_server_ready:
			_request_server(_index)
	_was_server_ready = ready

func _process(_delta: float) -> void:
	if _server_loading and Time.get_ticks_msec() >= _request_deadline:
		_request_id = 0
		_server_loading = false
		_refresh.disabled = not PvpNet.is_server_ready()
		_note.text = L10n.text("获取对战记录超时，请刷新重试。")
		_show_record()

static func turns_text(turns: float) -> String:
	var formatted := "%.3f" % turns
	while formatted.ends_with("0"): formatted = formatted.trim_suffix("0")
	return formatted.trim_suffix(".")

func _show_record() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_columns = null
	var count := _server_total if _source_server else _records.size()
	var blocked := _source_server and (_server_loading or not PvpNet.is_server_ready())
	_previous.disabled = blocked or _index >= count - 1
	_next.disabled = blocked or _index <= 0
	_refresh.disabled = not _source_server or blocked
	_page.text = "%d / %d" % [_index + 1, count] if count > 0 else "0 / 0"
	if _source_server and _server_loading:
		_text(_content, L10n.text("正在获取服务器对战记录…"), 9)
		return
	if (_source_server and _server_record.is_empty()) or (not _source_server and _records.is_empty()):
		_text(_content, L10n.text("暂无对战记录"), 10)
		_text(_content, L10n.text("查看服务器所有玩家最近结束的对战。") if _source_server else L10n.text("完成一场对战后，可在这里查看双方名称、回合和选购物品。"))
		return
	var record: Dictionary = _server_record if _source_server else _records[_index]
	var seat := 0 if _source_server else int(record.seat)
	var names := L10n.player_names(record)
	var outcome := str(record.get("outcome", "interrupted"))
	var result: String = {"win":"胜利", "loss":"失败", "draw":"平局", "interrupted":"中途退出／断线"}.get(outcome, "对局结束。")
	var color := "88ff88" if outcome == "win" else "ff8888" if outcome == "loss" else "ffff44"
	var caption := L10n.text(result)
	if _source_server:
		var winner := int(record.winner)
		caption = L10n.text("平局") if winner < 0 else L10n.text("%s获胜") % str(names[winner])
		color = "ffff44"
	_text(_content, "[color=#%s]%s[/color]  [color=#bbbbbb]%s[/color]" % [color, _escape(caption), _escape(str(record.get("finished_at", "")))], 8)
	_text(_content, "[color=#ffff44]%s[/color]  vs  [color=#ffff44]%s[/color]" % [_escape(str(names[seat])), _escape(str(names[1 - seat]))], 10)
	_text(_content, L10n.text("对局耗时：%s 回合") % turns_text(float(record.get("turns", 0))), 9)
	_text(_content, L10n.text("按游戏内回合时间统计，计入攻速和移速。"), 6)
	if _source_server: _text(_content, _escape(L10n.text("地图：%s") % L10n.text(str(record.map_name))), 7)
	var divider := ColorRect.new()
	divider.color = Color("77776b")
	divider.custom_minimum_size.y = 1
	_content.add_child(divider)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 8)
	_content.add_child(_columns)
	var selections: Array = record.get("selected_items", [[], []])
	var times: Array = record.get("times", [0, 0])
	for player in [seat, 1 - seat]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.size_flags_stretch_ratio = 1
		column.add_theme_constant_override("separation", 4)
		_columns.add_child(column)
		var selection_title := L10n.text("%s的选购物品") % str(names[player]) if _source_server else L10n.text("己方选购物品" if player == seat else "对手选购物品")
		_text(column, "[color=#ffff44]%s[/color]" % _escape(selection_title), 8)
		_text(column, L10n.text("消耗 %s 回合") % turns_text(float(times[player])), 7)
		if selections[player].is_empty(): _text(column, L10n.text("未选购物品"), 7)
		for saved in selections[player]: _item_row(column, saved)

func _item_row(parent: Control, saved: Dictionary) -> void:
	# The public summary already includes canonical art, name, level and count.
	# Do not deep-copy the entire item catalog for every row.
	var item := InventoryItem.from_dict(saved)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	parent.add_child(row)
	var icon := TextureRect.new()
	icon.texture = ItemAssets.get_texture(item.visual)
	icon.custom_minimum_size = Vector2(18, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(icon)
	var caption := item.display_name()
	if item.level != 0: caption += " %+d" % item.level
	if item.quantity > 1: caption += " ×%d" % item.quantity
	_text(row, _escape(caption), 7)

func _layout() -> void:
	if not is_instance_valid(_canvas): return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var factor := minf(2, minf(safe.size.x / 220, safe.size.y / 190))
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = safe.position
	_canvas.size = safe.size / factor
	var dimensions := _canvas.size
	ScreenLayout.place(_heading, Rect2(8, 7, dimensions.x - 56, 22))
	ScreenLayout.place(_back, Rect2(dimensions.x - 44, 8, 36, 20))
	var tab_width := (dimensions.x - 60) / 2
	ScreenLayout.place(_local_tab, Rect2(8, 35, tab_width, 20))
	ScreenLayout.place(_server_tab, Rect2(12 + tab_width, 35, tab_width, 20))
	ScreenLayout.place(_refresh, Rect2(dimensions.x - 44, 35, 36, 20))
	ScreenLayout.place(_scroll, Rect2(8, 62, dimensions.x - 16, dimensions.y - 108))
	ScreenLayout.place(_previous, Rect2(8, dimensions.y - 38, 54, 21))
	ScreenLayout.place(_next, Rect2(dimensions.x - 62, dimensions.y - 38, 54, 21))
	ScreenLayout.place(_page, Rect2(66, dimensions.y - 36, dimensions.x - 132, 18))
	ScreenLayout.place(_note, Rect2(6, dimensions.y - 13, dimensions.x - 12, 11))

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_return_menu()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _return_menu()

func _return_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	get_tree().quit_on_go_back = _previous_go_back
