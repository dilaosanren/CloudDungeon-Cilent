extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")

signal buy_requested(option: int)
signal skip_requested
signal inspect_requested(item: InventoryItem)
signal leave_requested
signal map_requested

const CellView = preload("res://scripts/pvp/client/market_cell.gd")
const Art = preload("res://scripts/ui/ui_assets.gd")
const CountdownView = preload("res://scripts/pvp/client/market_countdown.gd")
const IntroView = preload("res://scripts/ui/draft_match_intro.gd")
const GOLD_SOUND = preload("res://assets/menu/source/gold.mp3")
const GOLD_SOUND_INTERVAL_MSEC := 75
const BASE_SIZE := Vector2(180, 342)
var canvas: Control
var status_label: Label
var map_button: Button
var skip_button: Button
var opponent_label: Label
var own_label: Label
var opponent_scroll: ScrollContainer
var own_scroll: ScrollContainer
var opponent_row: HBoxContainer
var own_row: HBoxContainer
var cells: Array[CellView] = []
var items: Array[InventoryItem] = []
var preview_inventory := DungeonInventory.new()
var _state: Dictionary = {}
var _match_id := ""
var _pending := false
var _own_key := ""
var _opponent_key := ""
var _drag_strip: ScrollContainer
var _drag_slot: InventorySlot
var _drag_x := 0.0
var _drag_start := 0
var countdown: CountdownView
var _timer_turn := -1
var _timer_revision := -1
var _timer_deadline := 0
var _timer_is_own := false
var _intro: IntroView
var _gold_sound: AudioStreamPlayer
var _intro_active := false
var _intro_deadline := 0
var _intro_duration := 0
var _intro_name_msec := 2000
var _intro_gold_msec := 4000
var _shown_gold := Vector2i(-1, -1)
var _last_gold_sound := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas = Control.new()
	canvas.size = BASE_SIZE
	canvas.theme = Art.make_theme()
	canvas.theme.default_font_size = 8
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	var intro_layer := CanvasLayer.new()
	intro_layer.layer = 70
	add_child(intro_layer)
	_intro = IntroView.new()
	intro_layer.add_child(_intro)
	_gold_sound = AudioStreamPlayer.new()
	_gold_sound.bus = &"SFX"
	_gold_sound.stream = GOLD_SOUND
	_gold_sound.max_polyphony = 4
	_gold_sound.volume_db = -8
	add_child(_gold_sound)
	opponent_label = _label("", Rect2(3, 2, 143, 12), 8, Color("ffff44"))
	countdown = CountdownView.new()
	canvas.add_child(countdown)
	countdown.position = Vector2(148, 0)
	countdown.size = Vector2(30, 18)
	countdown.hide()
	opponent_scroll = _strip(Rect2(2, 18, 176, 25))
	opponent_row = _row(opponent_scroll)
	status_label = _label(L10n.text("等待物资…"), Rect2(3, 46, 128, 14), 8, Color("ffff44"))
	map_button = Button.new()
	map_button.icon = ItemAssets.get_texture(InventoryCatalog.SCROLL_VISUALS.ScrollOfMagicMapping)
	map_button.expand_icon = true
	map_button.add_theme_constant_override("icon_max_width",12)
	map_button.tooltip_text = L10n.text("查看战斗地图")
	map_button.focus_mode = Control.FOCUS_NONE
	Art.apply_button_style(map_button,"GREY_BUTTON")
	canvas.add_child(map_button)
	map_button.position = Vector2(134,44)
	map_button.size = Vector2(18,18)
	map_button.disabled = true
	map_button.pressed.connect(func(): map_requested.emit())
	var leave := Button.new()
	leave.text = L10n.text("退出")
	leave.add_theme_font_size_override("font_size", 7)
	Art.apply_button_style(leave)
	canvas.add_child(leave)
	leave.position = Vector2(156, 46)
	leave.size = Vector2(22, 14)
	leave.pressed.connect(func(): leave_requested.emit())
	for i in 36:
		var cell := CellView.new()
		canvas.add_child(cell)
		cell.position = Vector2(10 + (i % 6) * 27, 65 + int(i / 6) * 32)
		cell.size = Vector2(25, 30)
		cell.clicked.connect(_buy.bind(i))
		cell.long_clicked.connect(_inspect.bind(i))
		cell.right_clicked.connect(_inspect.bind(i))
		cells.append(cell)
	_label(L10n.text("价格单位：金币 · 长按查看物品"), Rect2(3, 256, 174, 8), 6, Color("bbbbbb"))
	own_label = _label("", Rect2(3, 265, 174, 12), 8, Color("ffff44"))
	own_scroll = _strip(Rect2(2, 279, 176, 28))
	own_row = _row(own_scroll)
	_label(L10n.text("先手 → 后手 → 后手 → 先手 · 循环购买"), Rect2(3, 309, 174, 10), 6, Color("bbbbbb"))
	skip_button = Button.new()
	skip_button.text = L10n.text("跳过本次选择")
	skip_button.tooltip_text = L10n.text("保留金币，按选装顺序继续。")
	skip_button.add_theme_font_size_override("font_size", 7)
	skip_button.focus_mode = Control.FOCUS_NONE
	Art.apply_button_style(skip_button)
	canvas.add_child(skip_button)
	skip_button.position = Vector2(40, 322)
	skip_button.size = Vector2(100, 18)
	skip_button.disabled = true
	skip_button.pressed.connect(func():
		if not skip_button.disabled: skip_requested.emit())
	resized.connect(refresh_layout)
	visibility_changed.connect(_visibility_changed)
	refresh_layout()

func _label(text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", Art.get_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.apply_text_outline(label)
	canvas.add_child(label)
	label.position = rect.position
	label.size = rect.size
	label.text = text
	label.clip_text = true
	return label

func _strip(rect: Rect2) -> ScrollContainer:
	var strip := ScrollContainer.new()
	strip.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(strip)
	strip.position = rect.position
	strip.size = rect.size
	return strip

func _row(strip: ScrollContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	strip.add_child(row)
	return row

func refresh_layout() -> void:
	if canvas == null: return
	var factor := minf(size.x / BASE_SIZE.x, size.y / BASE_SIZE.y)
	canvas.scale = Vector2.ONE * factor
	canvas.position = ((size - BASE_SIZE * factor) / 2).floor()

func show_state(value: Dictionary) -> void:
	_state = value
	var draft: Dictionary = value.draft
	var own_seat := int(value.seat)
	if _match_id != str(value.match_id):
		cancel_intro()
		_match_id = str(value.match_id)
		_timer_turn = -1
		_timer_revision = -1
		items.clear()
		preview_inventory = DungeonInventory.new()
		for saved in value.offers: items.append(InventoryItem.from_dict(saved))
		preview_inventory.backpack.items.append_array(items)
		for i in cells.size(): cells[i].set_item(items[i], preview_inventory)
		_own_key = ""
		_opponent_key = ""
		_intro_duration = int(draft.get("intro_duration_msec", 0))
		_intro_name_msec = int(draft.get("intro_name_msec", 2000))
		_intro_gold_msec = int(draft.get("intro_gold_msec", 4000))
		var remaining := int(draft.get("intro_remaining_msec", 0))
		_intro_active = remaining > 0 and _intro_duration > 0
		_intro_deadline = Time.get_ticks_msec() + remaining
		var names := L10n.player_names(value)
		_intro.configure(str(names[1 - own_seat]), str(names[own_seat]))
		_shown_gold = Vector2i(-1, -1)
	if _intro_active:
		# New snapshots can shorten this deadline, but cannot restart the intro.
		_intro_deadline = mini(_intro_deadline, Time.get_ticks_msec() + int(draft.get("intro_remaining_msec", 0)))
		_update_intro()
	map_button.disabled = _intro_active or not value.has("terrain")
	_refresh_gold()
	if _intro_active: status_label.text = L10n.text("匹配成功") if _intro_elapsed_msec() < _intro_name_msec else L10n.text("正在发放金币…")
	elif bool(draft.own_finished): status_label.text = L10n.text("金币不足，等待对方完成购买")
	elif bool(draft.can_buy): status_label.text = L10n.text("轮到你购买 · 第 %d 手") % int(draft.turn)
	else: status_label.text = L10n.text("等待对方购买 · 第 %d 手") % int(draft.turn)
	if _pending: status_label.text = L10n.text("正在提交…")
	skip_button.disabled = _intro_active or not bool(draft.can_buy) or _pending
	for i in cells.size():
		var price := int(draft.prices[i])
		cells[i].set_market_state(price, int(draft.owners[i]), not _intro_active and bool(draft.can_buy) and not _pending and int(draft.owners[i]) < 0 and price <= int(draft.gold), price <= int(draft.gold))
	var own_key := str(draft.own_items)
	if own_key != _own_key:
		_own_key = own_key
		_fill_strip(own_row, own_scroll, draft.own_items)
	var opponent_key := str(draft.opponent_items)
	if opponent_key != _opponent_key:
		_opponent_key = opponent_key
		_fill_strip(opponent_row, opponent_scroll, draft.opponent_items)
	_sync_countdown(value)

func _sync_countdown(value: Dictionary) -> void:
	var draft: Dictionary = value.draft
	var next_turn := int(draft.turn)
	var next_revision := int(value.revision)
	# set_pending() redraws the cached snapshot; it must never extend the timer.
	if next_turn != _timer_turn or next_revision != _timer_revision:
		var deadline := Time.get_ticks_msec() + int(draft.get("remaining_msec", 0)) + int(draft.get("intro_remaining_msec", 0))
		if next_turn != _timer_turn:
			_timer_deadline = deadline
			countdown.reset()
		else:
			_timer_deadline = mini(_timer_deadline, deadline)
		_timer_turn = next_turn
		_timer_revision = next_revision
	_timer_is_own = bool(draft.can_buy)
	_refresh_countdown()

func _process(_delta: float) -> void:
	if _intro_active:
		_update_intro()
		_refresh_gold()
		if not _intro_active: show_state(_state)
	_refresh_countdown()

func _intro_elapsed_msec() -> int:
	return clampi(_intro_duration - maxi(0, _intro_deadline - Time.get_ticks_msec()), 0, _intro_duration)

func _update_intro() -> void:
	var elapsed := _intro_elapsed_msec()
	_intro.seek(elapsed / 1000.0)
	if elapsed >= _intro_duration:
		cancel_intro()
		return
	if elapsed >= _intro_name_msec:
		status_label.text = L10n.text("正在发放金币…")
		var now := Time.get_ticks_msec()
		if _last_gold_sound < 0 or now - _last_gold_sound >= GOLD_SOUND_INTERVAL_MSEC:
			_last_gold_sound = now
			_gold_sound.pitch_scale = randf_range(0.9, 1.1)
			if DisplayServer.get_name() != "headless": _gold_sound.play()

func _refresh_gold() -> void:
	if _state.is_empty(): return
	var draft: Dictionary = _state.draft
	var own := int(draft.gold)
	var opponent := int(draft.opponent_gold)
	if _intro_active:
		var progress := clampf(float(_intro_elapsed_msec() - _intro_name_msec) / maxi(1, _intro_gold_msec), 0, 1)
		own = floori(int(draft.get("initial_gold", own)) * progress)
		opponent = floori(int(draft.get("opponent_initial_gold", opponent)) * progress)
	var amounts := Vector2i(own, opponent)
	if amounts == _shown_gold: return
	_shown_gold = amounts
	var own_seat := int(_state.seat)
	var names := L10n.player_names(_state)
	opponent_label.text = L10n.text("%s · %d 金币") % [str(names[1 - own_seat]).left(10), opponent]
	own_label.text = L10n.text("%s · %s · %d 金币") % [str(names[own_seat]).left(8), L10n.text("先手") if own_seat == int(_state.first_seat) else L10n.text("后手"), own]

func cancel_intro() -> void:
	_intro_active = false
	_last_gold_sound = -1
	if _intro != null: _intro.hide()
	if _gold_sound != null: _gold_sound.stop()

func _visibility_changed() -> void:
	if not is_visible_in_tree(): cancel_intro()
	_refresh_countdown()

func _refresh_countdown() -> void:
	if countdown == null: return
	var active := is_visible_in_tree() and _timer_is_own and not _intro_active
	countdown.visible = active
	if not active:
		countdown.reset()
		return
	var seconds := ceili(maxi(0, _timer_deadline - Time.get_ticks_msec()) / 1000.0)
	countdown.set_seconds(seconds)
	if seconds <= 0:
		skip_button.disabled = true
		# The client only blocks late clicks; the server chooses the next buyer.
		for cell in cells: cell.can_purchase = false

func set_pending(value: bool) -> void:
	if _pending == value: return
	_pending = value
	if not _state.is_empty(): show_state(_state)

func show_notice(text: String) -> void:
	status_label.text = text
	status_label.tooltip_text = text

func _fill_strip(row: HBoxContainer, strip: ScrollContainer, saved_items: Array) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	if saved_items.is_empty():
		var empty := Label.new()
		empty.text = L10n.text("尚未购买")
		empty.add_theme_font_size_override("font_size", 7)
		empty.add_theme_color_override("font_color", Color("999999"))
		Art.apply_text_outline(empty)
		row.add_child(empty)
	for saved in saved_items:
		var item := InventoryItem.from_dict(saved)
		var slot := InventorySlot.new()
		slot.item = item
		slot.show_extra = true
		slot.custom_minimum_size = Vector2(25, 23)
		row.add_child(slot)
		slot.clicked.connect(func(): inspect_requested.emit(item))
		slot.long_clicked.connect(func(): inspect_requested.emit(item))
		slot.right_clicked.connect(func(): inspect_requested.emit(item))
		slot.gui_input.connect(_strip_input.bind(strip, slot))
	strip.set_deferred("scroll_horizontal", 100000)

func _strip_input(event: InputEvent, strip: ScrollContainer, slot: InventorySlot) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_drag_strip = strip
		_drag_slot = slot
		_drag_x = event.global_position.x
		_drag_start = strip.scroll_horizontal

func _input(event: InputEvent) -> void:
	if not visible or not is_instance_valid(_drag_strip): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_drag_strip = null
		_drag_slot = null
	elif event is InputEventMouseMotion:
		var distance: float = (event.global_position.x - _drag_x) / canvas.scale.x
		if absf(distance) > 6:
			if is_instance_valid(_drag_slot): _drag_slot.cancel_press()
			_drag_strip.scroll_horizontal = _drag_start - roundi(distance)

func _buy(index: int) -> void:
	if index < cells.size() and cells[index].can_purchase: buy_requested.emit(index)

func _inspect(index: int) -> void:
	if index < items.size(): inspect_requested.emit(items[index])
