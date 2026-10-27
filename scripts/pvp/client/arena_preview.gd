extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")
const Maps = preload("res://scripts/pvp/net/pvp_protocol.gd")
signal leave_requested

var map: DungeonMap
var title: Label
var countdown: Label
var leave: Button
var _match_id := ""
var _deadline := 0
var _map_name := ""
var _inspect_mode := false
var _inspection_turn := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = Color("080a0c")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	map = DungeonMap.new()
	add_child(map)
	title = _label(20, Color("ffff44"))
	countdown = _label(13, Color("cccccc"))
	leave = Button.new()
	leave.text = L10n.text("退出")
	UiAssets.apply_button_style(leave)
	leave.pressed.connect(_leave_pressed)
	add_child(leave)
	resized.connect(_layout)
	hide()

func _label(size_value: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", color)
	UiAssets.apply_text_outline(label)
	add_child(label)
	return label

func show_state(value: Dictionary) -> void:
	_inspect_mode = false
	leave.text = L10n.text("退出")
	var deadline := Time.get_ticks_msec() + int(value.preview_remaining_msec)
	_deadline = deadline if str(value.match_id)!=_match_id else mini(_deadline,deadline)
	_show_map(value)

func show_inspection(value: Dictionary) -> void:
	_inspect_mode = true
	leave.text = L10n.text("返回选购")
	var turn := int(value.draft.turn)
	var deadline := Time.get_ticks_msec()+int(value.draft.remaining_msec)
	_deadline = deadline if turn!=_inspection_turn or str(value.match_id)!=_match_id else mini(_deadline,deadline)
	_inspection_turn = turn
	_show_map(value)

func _leave_pressed() -> void:
	if _inspect_mode: hide()
	else: leave_requested.emit()

func _show_map(value: Dictionary) -> void:
	var key := str(value.match_id)
	if key != _match_id:
		_match_id = key
		_map_name = str(value.map_name)
		map.region = int(value.map_region)
		map.set_map(Maps.BATTLE_SIZE, Maps.cropped(PackedInt32Array(value.terrain)), int(value.map_seed))
	title.text = L10n.text("战场预览：%s") % L10n.text(_map_name)
	show()
	_process(0)
	_layout()

func _process(_delta: float) -> void:
	if not visible or countdown == null: return
	var seconds := ceili(maxi(0,_deadline-Time.get_ticks_msec())/1000.0)
	countdown.text = (L10n.text("选购继续计时：%d秒") if _inspect_mode else L10n.text("%d 秒后进入选装")) % seconds

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and _inspect_mode and event.is_action_pressed("ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()

func _layout() -> void:
	if map == null: return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var top := safe.position.y + 62
	var bottom := safe.end.y - 76
	var extent := Vector2(Maps.BATTLE_SIZE * 16)
	var fit := minf((safe.size.x-32) / extent.x, (bottom-top) / extent.y)
	var scale_value := maxf(0.1, floorf(fit*2) / 2)
	map.scale = Vector2.ONE * scale_value
	map.position = (Vector2(safe.get_center().x, (top+bottom)/2) - extent*scale_value/2).floor()
	ScreenLayout.place(title, Rect2(safe.position.x+8, safe.position.y+20, safe.size.x-16, 32))
	ScreenLayout.place(countdown, Rect2(safe.position.x+8, safe.end.y-61, safe.size.x-16, 24))
	var button_width := maxf(58,leave.get_combined_minimum_size().x+8)
	ScreenLayout.place(leave, Rect2(safe.end.x-button_width-8, safe.end.y-32, button_width, 28))
