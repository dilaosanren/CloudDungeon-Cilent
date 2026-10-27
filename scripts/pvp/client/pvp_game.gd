extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")

const Nature = preload("res://scripts/nature/nature_rules.gd")
const NatureEffects = preload("res://scripts/nature/nature_effects.gd")
const MarketView = preload("res://scripts/pvp/client/market_view.gd")
const EquipmentPreview = preload("res://scripts/menu/equipment_preview.gd")
const ArenaPreview = preload("res://scripts/pvp/client/arena_preview.gd")
const WaitButtonView = preload("res://scripts/ui/dungeon_wait_button.gd")
const TargetPromptView = preload("res://scripts/ui/dungeon_target_prompt.gd")
const ExamineButtonView = preload("res://scripts/ui/dungeon_examine_button.gd")
const ExamineWindowView = preload("res://scripts/ui/dungeon_examine_window.gd")
const ExamineInfo = preload("res://scripts/ui/dungeon_examine_info.gd")
const BattleBannerView = preload("res://scripts/ui/battle_start_banner.gd")
const MapGestures = preload("res://scripts/pvp/client/map_gestures.gd")
const TickSound = preload("res://scripts/pvp/client/countdown_sound.gd")
const PressHighlight = preload("res://scripts/pvp/client/cell_press_highlight.gd")
const ArenaWarning = preload("res://scripts/pvp/client/arena_warning.gd")
const ArenaRockfall = preload("res://scripts/pvp/client/arena_rockfall.gd")
const TurnIndicator = preload("res://scripts/status/turn_indicator.gd")
const BattleActions = preload("res://scripts/pvp/client/battle_actions.gd")
const HERO_NAMES := ["战士", "法师", "盗贼", "女猎手", "决斗家", "牧师"]
const PREVIEW_SYNC_GRACE_MS := 1000
const PREVIEW_RECONNECT_MS := 12000
const MATCH_VIBRATION_MS := 120
var _vibrated_match_id := ""
var interface: Control
var lobby: PanelContainer
var lobby_status: Label
var player_name: LineEdit
var hero_choice: OptionButton
var join_button: Button
var create_room_button: Button
var enter_room_button: Button
var room_code_input: LineEdit
var room_code_label: Label
var copy_room_button: Button
var reconnect_overlay: ColorRect
var reconnect_label: Label
var draft_view: MarketView
var arena_preview: ArenaPreview
var draft_map_preview: ArenaPreview
var battle_ui: Control
var hud: DungeonStatusUI
var turn_indicator: TurnIndicator
var status := DungeonStatus.new()
var turn_label: Label
var turn_row: HBoxContainer
var turn_times_label: Label
var battle_time_label: Label
var _battle_remaining := PackedInt64Array()
var _battle_clock_active := -1
var _battle_clock_received := 0
var _battle_clock_seat := 0
var _battle_tick: TickSound
var _last_battle_state_key := ""
var battle_start_banner: BattleBannerView
var _banner_match_id := ""
var action_status_label: Label
var report: Label
var wait_button: WaitButtonView
var target_prompt: TargetPromptView
var examine_button: ExamineButtonView
var examine_window: ExamineWindowView
var _examining := false
var battle_actions: BattleActions
var _menu_inventory_input := true
var _menu_inventory_keys := true
var stage: Control
var dungeon: DungeonMap
var _press_highlight: PressHighlight
var _arena_warning: ArenaWarning
var _arena_rockfall: ArenaRockfall
var map_gestures: MapGestures
var visual := PvpVisualWorld.new()
var effects: NatureEffects
var inventory := PvpRemoteInventory.new()
var inventory_ui: InventoryUI
var detail_inventory := DungeonInventory.new()
var detail_ui: InventoryUI
var _draft_item_preview: Control
var actor_models: Dictionary = {}
var ground_views: Array[DungeonItemSprite] = []
var _ground_latest: Array = []
var _ground_displayed: Array = []
var _ground_flights: Dictionary = {}
var _state_queue: Array[Dictionary] = []
var _impact_state: Dictionary = {}
var _impact_flights := 0
var _impact_cells: Array[int] = []
var _push_eligible: Dictionary = {}
var _push_events: Dictionary = {} # Actor id -> events held until a push or pre-attack move lands.
var _finish_pending := false
var _finish_reason := ""
const FINISH_STALL_SECONDS := 2.0
var _terminal_state: Dictionary = {}
var _finish_stall := 0.0
var _finish_progress: Array = []
var current: Dictionary = {}
var _offers_key := ""
var _inventory_key := ""
var _event_sequence := -1
var _pending := false
var _ending := false
var _returning := false
var _connected_at := 0
var _join_pending := false
var _lobby_connection_state := ""
var _visual_busy_until := 0
var _plant_cells: Array[int] = []
var _ui_built := false
var _prewarm_finished := false
var _previous_quit_on_back := true
var _owns_go_back := false
var _preview_sync_match := ""
var _preview_sync_at := 0
var _preview_reconnect_started := false

func _ready() -> void:
	var warming := has_meta("prewarm")
	if not warming:
		_previous_quit_on_back = get_tree().quit_on_go_back
		get_tree().quit_on_go_back = false
		_owns_go_back = true
	if not warming and not OS.has_feature("mobile"): get_window().min_size = Vector2i(320, 568)
	theme = UiAssets.make_theme()
	theme.default_font_size = 13
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	await _build(warming)
	_battle_tick = TickSound.new()
	add_child(_battle_tick)
	if warming:
		_layout()
		_prewarm_finished = true
		return
	PvpNet.state_received.connect(_state)
	PvpNet.notice.connect(_notice)
	PvpNet.connection_changed.connect(_connection)
	PvpNet.command_finished.connect(_ack)
	PvpNet.server_status_changed.connect(_refresh_lobby_connection)
	get_viewport().size_changed.connect(_layout)
	_layout()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hero="):
			var index := HeroAssets.HERO_KEYS.find(arg.trim_prefix("--hero="))
			if index >= 0: hero_choice.select(index)
	# Save edits immediately; the session identity survives scene recreation.
	player_name.text_changed.connect(_player_name_changed)
	_refresh_window_title()
	PvpNet.monitor_server()
	_refresh_lobby_connection()

func _player_name_changed(text: String) -> void:
	ClientPrefs.set_value(&"player_name", text)
	_refresh_window_title()

func _refresh_window_title() -> void:
	get_window().title = L10n.text("云地牢") + (" · " + player_name.text if not player_name.text.is_empty() else "")

func _label(text: String, size: int = 13, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	UiAssets.apply_text_outline(label)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 30
	UiAssets.apply_button_style(button)
	button.pressed.connect(callback)
	return button

func _build(staged: bool = false) -> void:
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	add_child(stage)
	dungeon = DungeonMap.new()
	dungeon.auto_refresh_visibility = false
	stage.add_child(dungeon)
	_press_highlight = PressHighlight.new()
	dungeon.add_child(_press_highlight)
	_arena_warning = ArenaWarning.new()
	dungeon.add_child(_arena_warning)
	_arena_rockfall = ArenaRockfall.new()
	dungeon.add_child(_arena_rockfall)
	var canvas := CanvasLayer.new()
	canvas.layer = 30
	add_child(canvas)
	interface = Control.new()
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interface.theme = theme
	canvas.add_child(interface)
	await _build_lobby(staged)
	lobby.minimum_size_changed.connect(func(): _layout.call_deferred())
	if staged: await get_tree().process_frame
	_build_draft()
	if staged: await get_tree().process_frame
	arena_preview = ArenaPreview.new()
	interface.add_child(arena_preview)
	arena_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arena_preview.leave_requested.connect(_return_menu)
	draft_map_preview = ArenaPreview.new()
	interface.add_child(draft_map_preview)
	draft_map_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	draft_view.minimum_size_changed.connect(func(): _layout.call_deferred())
	_build_battle()
	if staged: await get_tree().process_frame
	_build_reconnect_overlay()
	detail_ui = InventoryUI.new()
	detail_ui.toolbar_enabled = false
	interface.add_child(detail_ui)
	detail_ui.setup(detail_inventory)
	if staged: await get_tree().process_frame
	inventory_ui = InventoryUI.new()
	inventory_ui.toolbar_leading_width = 44
	interface.add_child(inventory_ui)
	inventory_ui.setup(inventory)
	inventory_ui.hide()
	if staged: await get_tree().process_frame
	inventory.intent.connect(_send)
	inventory.message.connect(_notice)
	inventory.selection_needed.connect(_select_item)
	inventory.targeting_requested.connect(func(_item, _action):
		_examining = false
		_refresh_target_prompt())
	var inspection_layer := CanvasLayer.new()
	inspection_layer.layer = 60
	add_child(inspection_layer)
	examine_window = ExamineWindowView.new()
	inspection_layer.add_child(examine_window)
	examine_window.chosen.connect(_show_examine_entry)
	var banner_layer := CanvasLayer.new()
	banner_layer.layer = 40
	add_child(banner_layer)
	battle_start_banner = BattleBannerView.new()
	banner_layer.add_child(battle_start_banner)
	map_gestures = MapGestures.new()
	map_gestures.stage = stage
	map_gestures.map = dungeon
	map_gestures.available = _can_navigate_map
	map_gestures.tapped.connect(_map_tap)
	map_gestures.pressing.connect(_map_press)
	map_gestures.press_ended.connect(_press_highlight.clear)
	add_child(map_gestures)
	lobby.show()
	draft_view.hide()
	battle_ui.hide()
	stage.hide()
	_ui_built = true

func _build_lobby(staged: bool = false) -> void:
	lobby = PanelContainer.new()
	lobby.add_theme_stylebox_override("panel", UiAssets.get_style("WINDOW"))
	interface.add_child(lobby)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	lobby.add_child(column)
	var title := _label(L10n.text("云地牢"), 21, Color("ffff44"))
	title.name = "LobbyTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	if staged: await get_tree().process_frame
	column.add_child(_label(L10n.text("选择英雄，两人就绪后进入战前选装。"), 11))
	if staged: await get_tree().process_frame
	player_name = LineEdit.new()
	player_name.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	player_name.placeholder_text = L10n.text("玩家名字（可留空）")
	player_name.max_length = 16
	player_name.text = ClientPrefs.session_player_name()
	column.add_child(player_name)
	if staged: await get_tree().process_frame
	hero_choice = OptionButton.new()
	for name_value in HERO_NAMES: hero_choice.add_item(L10n.title_case(L10n.text(name_value)))
	hero_choice.select(HeroAssets.HERO_KEYS.find("warrior"))
	column.add_child(hero_choice)
	if staged: await get_tree().process_frame
	join_button = _button(L10n.text("随机匹配"), _join)
	join_button.disabled = true
	column.add_child(join_button)
	create_room_button = _button(L10n.text("创建独立房间"), func(): _join("create"))
	column.add_child(create_room_button)
	if staged: await get_tree().process_frame
	var row := HBoxContainer.new()
	column.add_child(row)
	room_code_input = LineEdit.new()
	room_code_input.placeholder_text = L10n.text("6位房间号")
	room_code_input.max_length = 6
	room_code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(room_code_input)
	enter_room_button = _button(L10n.text("加入房间"), func(): _join("private"))
	row.add_child(enter_room_button)
	if staged: await get_tree().process_frame
	room_code_label = _label("", 20, Color("ffff44"))
	room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(room_code_label)
	room_code_label.hide()
	copy_room_button = _button(L10n.text("复制房间号"), _copy_room_code)
	column.add_child(copy_room_button)
	copy_room_button.hide()
	if staged: await get_tree().process_frame
	lobby_status = _label(L10n.text("双方连接成功后，开始轮流购买战斗物资。"), 11)
	lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_status.custom_minimum_size.y = 40
	column.add_child(lobby_status)
	column.add_child(_button(L10n.text("返回主菜单"), _return_menu))

func _build_draft() -> void:
	draft_view = MarketView.new()
	interface.add_child(draft_view)
	draft_view.buy_requested.connect(func(option: int): _send({"kind":"buy", "option":option}))
	draft_view.skip_requested.connect(func(): _send({"kind":"skip"}))
	draft_view.inspect_requested.connect(_inspect_draft_item)
	draft_view.visibility_changed.connect(func():
		if not draft_view.is_visible_in_tree(): _close_draft_item_preview())
	draft_view.leave_requested.connect(_return_menu)
	draft_view.map_requested.connect(_show_draft_map)

func _inspect_draft_item(item: InventoryItem) -> void:
	if _ending or current.get("phase",-1) != PvpProtocol.Phase.DRAFT: return
	_close_draft_item_preview()
	detail_ui._close_detail()
	if not EquipmentPreview.has_animation(item):
		detail_ui.show_item(item,true)
		return
	var preview := EquipmentPreview.new()
	# Collection/preview rules must never mutate a market offer or owned gear.
	preview.item = item.copy_item()
	preview.handle_cancel_input = true
	_draft_item_preview = preview
	preview.closed.connect(func():
		if _draft_item_preview == preview: _draft_item_preview = null)
	get_viewport().gui_release_focus()
	interface.add_child(preview)

func _close_draft_item_preview() -> void:
	if is_instance_valid(_draft_item_preview): _draft_item_preview.close()
	_draft_item_preview = null

func _show_draft_map() -> void:
	if current.get("phase",-1)!=PvpProtocol.Phase.DRAFT or not current.has("terrain"): return
	_close_draft_item_preview()
	detail_ui._close_detail()
	draft_map_preview.show_inspection(current)

func _copy_room_code() -> void:
	var code := str(current.get("room_code", ""))
	if code.is_empty(): return
	DisplayServer.clipboard_set(code)
	lobby_status.text = L10n.text("房间号已复制，发给朋友即可加入。")

func _build_reconnect_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	reconnect_overlay = ColorRect.new()
	reconnect_overlay.color = Color(0, 0, 0, 0.8)
	reconnect_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(reconnect_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reconnect_overlay.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	reconnect_label = _label("", 15, Color("ffff44"))
	reconnect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(reconnect_label)
	column.add_child(_button(L10n.text("返回主菜单"), _return_menu))
	reconnect_overlay.hide()

func _build_battle() -> void:
	battle_ui = Control.new()
	battle_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interface.add_child(battle_ui)
	hud = DungeonStatusUI.new()
	hud.buff_right_reserved_width = 68
	hud.setup(status)
	status.changed.connect(func(): _layout.call_deferred())
	battle_ui.add_child(hud)
	turn_indicator = TurnIndicator.new()
	turn_indicator.name = "OwnTurnIndicator"
	# The status pane omits the original XP band; keep the disc just below it.
	turn_indicator.position = Vector2(1, 32)
	hud.pane.add_child(turn_indicator)
	turn_row = HBoxContainer.new()
	turn_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	turn_row.add_theme_constant_override("separation", 10)
	battle_ui.add_child(turn_row)
	turn_label = _label("", 13, Color("ffff44"))
	turn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_row.add_child(turn_label)
	turn_times_label = _label("", 11, Color("cccccc"))
	turn_times_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	turn_times_label.tooltip_text = L10n.text("你的行动时间 t / 对手行动时间 t")
	turn_row.add_child(turn_times_label)
	battle_time_label = _label("", 11, Color("cccccc"))
	battle_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_time_label.tooltip_text = L10n.text("你的剩余思考时间 / 对手剩余思考时间；仅行动方计时，耗尽判负。")
	battle_ui.add_child(battle_time_label)
	action_status_label = _label("", 11, Color("cccccc"))
	action_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_ui.add_child(action_status_label)
	wait_button = WaitButtonView.new()
	battle_ui.add_child(wait_button)
	wait_button.size = Vector2(20, 26)
	wait_button.pressed.connect(_wait)
	examine_button = ExamineButtonView.new()
	battle_ui.add_child(examine_button)
	examine_button.size = Vector2(20, 26)
	examine_button.toggle_mode = true
	examine_button.pressed.connect(_toggle_examine)
	target_prompt = TargetPromptView.new()
	battle_ui.add_child(target_prompt)
	target_prompt.cancelled.connect(_cancel_target)
	report = _label(L10n.text("点击地面移动，点击敌人近战，点击自己拾取。"), 11)
	report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	battle_ui.add_child(report)
	battle_actions = BattleActions.new()
	battle_ui.add_child(battle_actions)
	battle_actions.opened.connect(_battle_menu_opened)
	battle_actions.closed.connect(_battle_menu_closed)
	battle_actions.control_requested.connect(_send_battle_control)

func _battle_menu_opened() -> void:
	_cancel_target()
	map_gestures.reset()
	_press_highlight.clear()
	inventory_ui.close_bag()
	inventory_ui._close_detail()
	detail_ui._close_detail()
	hud.close_inspector()
	examine_window.close()
	_menu_inventory_input = inventory_ui.is_processing_input()
	_menu_inventory_keys = inventory_ui.is_processing_unhandled_key_input()
	inventory_ui.set_process_input(false)
	inventory_ui.set_process_unhandled_key_input(false)

func _battle_menu_closed() -> void:
	if not is_instance_valid(inventory_ui): return
	inventory_ui.set_process_input(_menu_inventory_input)
	inventory_ui.set_process_unhandled_key_input(_menu_inventory_keys)

func _send_battle_control(intent: Dictionary) -> void:
	if _ending or _returning or PvpNet.is_reconnecting() or not PvpNet.is_server_ready():
		battle_actions.complete({"error":"尚未连接到对局。"})
		return
	battle_actions.expect_ack_serial(PvpNet._command_serial + 1)
	PvpNet.send_intent(intent)

func _join(mode: String = "public") -> void:
	if _join_pending or not PvpNet.is_server_ready(): return
	var code := room_code_input.text.strip_edges()
	if mode == "private" and (code.length() != 6 or not code.is_valid_int() or str(int(code)) != code):
		lobby_status.text = L10n.text("请输入有效的6位房间号。")
		return
	_join_pending = true
	_refresh_lobby_connection()
	_connected_at = Time.get_ticks_msec()
	var error := PvpNet.join_match(HeroAssets.HERO_KEYS[hero_choice.selected], player_name.text, mode, code)
	if error != OK:
		_join_pending = false
		_refresh_lobby_connection()
		lobby_status.text = L10n.text("进入对战失败 (%d)") % error

func _refresh_lobby_connection() -> void:
	if not is_instance_valid(join_button): return
	join_button.disabled = _join_pending or not PvpNet.is_server_ready()
	create_room_button.disabled = join_button.disabled
	enter_room_button.disabled = join_button.disabled
	room_code_input.editable = not _join_pending
	hero_choice.disabled = _join_pending
	player_name.editable = not _join_pending
	if _lobby_connection_state == PvpNet.connection_state: return
	_lobby_connection_state = PvpNet.connection_state
	if not lobby.visible: return
	if PvpNet.is_server_ready():
		if not _join_pending: lobby_status.text = L10n.text("选择英雄，然后开始对战。")
	elif PvpNet.connection_state == "incompatible":
		lobby_status.text = L10n.text("服务器：版本不一致")
	elif PvpNet.connection_state == "unconfigured":
		lobby_status.text = L10n.text("服务器：未配置")
	elif PvpNet.connection_state == "failed":
		lobby_status.text = L10n.text("连接失败：请先启动服务器并检查地址／端口。")
	else:
		lobby_status.text = L10n.text("正在连接服务器…")

func _connection(text: String) -> void:
	lobby_status.text = L10n.render(text)
	if PvpNet.is_reconnecting():
		_pending = false
		_cancel_target()
		_refresh_input()
		return
	if text == "已恢复对局。":
		_pending = false
		_refresh_input()
		return
	if "失败" in text or "断开" in text or "正在对战" in text or "已经" in text or "无效" in text or PvpNet.connection_state in ["incompatible", "failed"] or PvpNet._monitor_only:
		_join_pending = false
		if current.get("phase", -1) in [PvpProtocol.Phase.BATTLE, PvpProtocol.Phase.DRAFT, PvpProtocol.Phase.MAP_PREVIEW]:
			_notice(text)
			_end(text)
			return
		current.clear()
		room_code_label.hide()
		copy_room_button.hide()
		_refresh_lobby_connection()
		if not PvpNet.is_server_ready(): PvpNet.monitor_server()

func _send(intent: Dictionary) -> void:
	if _returning: return
	if _pending and intent.get("kind") != "quickslot": return
	if current.get("phase", -1) == PvpProtocol.Phase.BATTLE and intent.get("kind") != "quickslot" and (not inventory.can_act or Time.get_ticks_msec() < _visual_busy_until): return
	var value := intent.duplicate(true)
	if value.has("target_xy"):
		value.cell = int(value.target_xy[0]) + int(value.target_xy[1]) * dungeon.map_size.x
		value.erase("target_xy")
	_pending = true
	_refresh_input()
	inventory.can_act = false
	if current.get("phase", -1) == PvpProtocol.Phase.BATTLE: _visual_busy_until = Time.get_ticks_msec()+250
	PvpNet.send_intent(value)

func _ack(_result: Dictionary) -> void:
	if _result.get("kind", "") in ["chat", "surrender"]:
		battle_actions.complete(_result)
		return
	_pending = false
	_refresh_input()

func _refresh_input() -> void:
	if battle_actions != null: battle_actions.set_available(not _ending and not _returning and not PvpNet.is_reconnecting())
	if draft_view != null and draft_view.visible: draft_view.set_pending(_pending or PvpNet.is_reconnecting())
	inventory.can_act = current.get("phase", -1) == PvpProtocol.Phase.BATTLE and current.get("active", -1) == current.get("seat", -2) and not _pending and not _ending and not _returning and not PvpNet.is_reconnecting() and _impact_state.is_empty() and _push_events.is_empty() and _state_queue.is_empty() and Time.get_ticks_msec() >= _visual_busy_until
	wait_button.disabled = not inventory.can_act
	turn_indicator.visible = current.get("phase", -1) == PvpProtocol.Phase.BATTLE and not _ending
	if current.has("times"):
		turn_indicator.set_state(float(current.times[int(current.seat)]), status.health > 0, inventory.can_act)
	_refresh_action_status()
	_refresh_target_prompt()

func _refresh_action_status() -> void:
	if current.get("phase",-1)!=PvpProtocol.Phase.BATTLE:
		action_status_label.text = ""
	elif _pending:
		action_status_label.text = L10n.text("正在发送操作...")
	elif current.get("active",-1)==current.get("seat",-2):
		action_status_label.text = L10n.text("等待操作")
	else:
		action_status_label.text = "^o^"

func _refresh_target_prompt() -> void:
	var aiming := battle_ui.visible and inventory.pending_item != null and not _ending
	var examining := battle_ui.visible and _examining and not _ending
	examine_button.set_pressed_no_signal(examining)
	target_prompt.visible = aiming or examining
	report.visible = not target_prompt.visible
	if target_prompt.visible:
		target_prompt.set_action("EXAMINE" if examining else inventory.pending_action)
		target_prompt.place(ScreenLayout.safe_rect(get_viewport()))

func _cancel_target() -> void:
	_examining = false
	inventory.cancel_target()
	_refresh_target_prompt()

func _toggle_examine() -> void:
	if not battle_ui.visible or _ending: return
	inventory.cancel_target()
	inventory_ui.close_bag()
	inventory_ui._close_detail()
	detail_ui._close_detail()
	hud.close_inspector()
	examine_window.close()
	_examining = not _examining
	_refresh_target_prompt()

func _wait() -> void:
	# Toolbar.btnWait first cancels an active cell selector without spending time.
	if inventory.pending_item != null or _examining:
		_cancel_target()
	elif inventory.can_act:
		_send({"kind":"wait"})

func _notice(text: String) -> void:
	var localized := L10n.render_for_match(text, current)
	report.text = localized
	if draft_view.visible: draft_view.show_notice(localized)

func _state(state_value: Dictionary) -> void:
	if _ending: return
	battle_actions.sync(state_value)
	# Keep the authority's result even when a missing local landing/impact
	# callback currently prevents this snapshot from reaching _apply_state.
	if state_value.get("phase", -1) == PvpProtocol.Phase.FINISHED and _terminal_state.is_empty():
		_terminal_state = state_value.duplicate(true)
		_finish_stall = 0.0
		_finish_progress.clear()
		if effects != null: effects.finish_actions = true
	if _finish_pending: return
	_sync_battle_clock(state_value)
	var key := "%s:%d:%d" % [state_value.get("match_id", ""), state_value.get("phase", -1), state_value.get("revision", -1)]
	# Clock ticks must not close item details, reload the map or replay effects.
	if state_value.get("phase", -1) == PvpProtocol.Phase.BATTLE and key == _last_battle_state_key:
		var was_offline := current.has("opponent_reconnect_msec")
		current.erase("opponent_reconnect_msec")
		if state_value.has("opponent_reconnect_msec"): current.opponent_reconnect_msec = state_value.opponent_reconnect_msec
		elif was_offline and not current.get("log", []).is_empty(): report.text = L10n.render_for_match(str(current.log[-1]), current)
		return
	_last_battle_state_key = key
	_state_queue.append(state_value.duplicate(true))
	_present_next_state()

func _sync_battle_clock(value: Dictionary) -> void:
	if not value.has("battle_remaining_msec"): return
	_battle_remaining = PackedInt64Array(value.battle_remaining_msec)
	_battle_clock_active = int(value.active) if value.phase == PvpProtocol.Phase.BATTLE else -1
	_battle_clock_seat = int(value.seat)
	_battle_clock_received = Time.get_ticks_msec()
	_refresh_battle_clock()

func _refresh_battle_clock() -> void:
	if battle_time_label == null or _battle_remaining.size() != 2: return
	var remaining := _battle_remaining.duplicate()
	if _battle_clock_active >= 0:
		remaining[_battle_clock_active] = maxi(0, remaining[_battle_clock_active] - (Time.get_ticks_msec() - _battle_clock_received))
	var own := _clock_text(remaining[_battle_clock_seat])
	var opponent := _clock_text(remaining[1 - _battle_clock_seat])
	if not _ending and _battle_clock_active == _battle_clock_seat and remaining[_battle_clock_seat] > 0:
		_battle_tick.set_seconds(ceili(remaining[_battle_clock_seat] / 1000.0))
	else:
		_battle_tick.reset()
	battle_time_label.text = L10n.text("剩余 %s / %s") % [own, opponent]
	battle_time_label.add_theme_color_override("font_color", Color("ff4444") if remaining[_battle_clock_seat] <= 10000 else Color("cccccc"))

func _clock_text(msec: int) -> String:
	var seconds := ceili(maxi(0, msec) / 1000.0)
	return "%02d:%02d" % [int(seconds / 60), seconds % 60]

func _present_next_state() -> void:
	if not _impact_state.is_empty() or not _push_events.is_empty() or _finish_pending or _ending: return
	while not _state_queue.is_empty():
		var next: Dictionary = _state_queue.pop_front()
		var flights: Array[Dictionary] = []
		if effects != null and current.get("phase", -1) == PvpProtocol.Phase.BATTLE and int(next.get("event_sequence", -1)) != _event_sequence:
			for event in next.get("events", []):
				var action := str(event.get("action", ""))
				if action not in ["hero_throw", "hero_zap", "missile_return", "dragon_breath"]: continue
				if action in ["hero_throw", "missile_return"] and (not event.get("item") is Dictionary or not event.item.has("item_data")): continue
				if action == "hero_zap" and not event.get("bolt") is Dictionary: continue
				# An attack may reveal a previously invisible opponent. Create its
				# visible sprite from server data without applying the hit result.
				if _actor_ref(event.get("actor")) == null and event.get("actor") is Dictionary:
					for data in next.get("actors", []):
						if int(data.id) == int(event.actor.get("actor_ref", -1)):
							_ensure_actor(data)
							break
				if _actor_ref(event.get("actor")) != null: flights.append(event)
		if not flights.is_empty():
			# The server has already resolved this action. Keep its post-impact
			# snapshot queued while drawing the flight against the previous state.
			# This holds HP, shields, buffs, hit sounds, popups, knockback and death
			# together; a later snapshot cannot bypass this presentation barrier.
			_impact_state = next
			_impact_flights = flights.size()
			_impact_cells.clear()
			_refresh_input()
			for event in flights:
				if event.action in ["hero_throw", "missile_return"]:
					if event.action == "missile_return" and flights.any(func(other): return other.action == "hero_throw" and _same_projectile(other,event)):
						continue # Its outbound flight starts this return on arrival.
					var cell := int(event.to)
					_impact_cells.append(cell)
					if event.action == "missile_return": _play_return(event, _throw_arrived)
					else:
						var following: Array[Dictionary] = flights.filter(func(other): return other.action == "missile_return" and _same_projectile(event,other))
						for returned in following: _impact_cells.append(int(returned.to))
						_play_throw(event, _outbound_arrived.bind(following) if not following.is_empty() else _throw_arrived)
				elif event.action == "dragon_breath":
					effects.breathe(_actor_ref(event.get("actor")),event,_throw_arrived)
				else:
					_wand_effect(event, _actor_ref(event.get("actor")), _throw_arrived)
			return
		_apply_state(next)
		if not _push_events.is_empty() or _finish_pending: return
		if _ending:
			_state_queue.clear()
			return
	_refresh_input()

# Shared completion barrier for thrown items and wand flights.
func _same_projectile(first: Dictionary, second: Dictionary) -> bool:
	return first.get("actor",{}).get("actor_ref",-1) == second.get("actor",{}).get("actor_ref",-2) and first.item.item_data.get("uid","") == second.item.item_data.get("uid","")

func _outbound_arrived(returns: Array[Dictionary]) -> void:
	_throw_arrived()
	if _impact_state.is_empty(): return
	for returned in returns: _play_return(returned, _throw_arrived)

func _throw_arrived() -> void:
	if not is_inside_tree() or _impact_state.is_empty(): return
	_impact_flights -= 1
	if _impact_flights > 0: return
	var landed_state := _impact_state
	var landed_cells: Array[int] = _impact_cells.duplicate()
	_impact_state = {}
	_impact_cells.clear()
	# Apply the authoritative result once, omitting flights already played.
	_apply_state(landed_state, true)
	for cell in landed_cells: _ground_impact(cell)
	_present_next_state.call_deferred()

func _apply_state(state_value: Dictionary, flights_played: bool = false) -> void:
	current = state_value
	if state_value.get("waiting", false):
		_close_draft_item_preview()
		if state_value.get("private_room", false):
			room_code_label.text = L10n.text("房间号：%s") % str(state_value.room_code)
			room_code_label.show()
			copy_room_button.show()
			lobby_status.text = L10n.text("把房间号发给朋友，等待朋友加入。")
		else:
			room_code_label.hide()
			copy_room_button.hide()
			lobby_status.text = L10n.text("已连接，等待第二位玩家加入…")
		return
	var phase: int = state_value.phase
	_notify_match_found(state_value)
	if phase != PvpProtocol.Phase.DRAFT: _close_draft_item_preview()
	if phase not in [PvpProtocol.Phase.BATTLE,PvpProtocol.Phase.FINISHED]: _arena_rockfall.clear()
	if phase!=PvpProtocol.Phase.DRAFT or draft_map_preview._match_id!=str(state_value.match_id): draft_map_preview.hide()
	lobby.hide()
	arena_preview.visible = phase == PvpProtocol.Phase.MAP_PREVIEW
	draft_view.visible = phase == PvpProtocol.Phase.DRAFT
	battle_ui.visible = phase in [PvpProtocol.Phase.BATTLE, PvpProtocol.Phase.FINISHED] and state_value.has("actors")
	stage.visible = battle_ui.visible
	inventory_ui.visible = battle_ui.visible
	$Background.visible = not stage.visible
	if phase == PvpProtocol.Phase.MAP_PREVIEW: arena_preview.show_state(state_value)
	elif phase == PvpProtocol.Phase.DRAFT: _draft_state(state_value)
	elif state_value.has("actors"): _battle_state(state_value, flights_played)
	if phase == PvpProtocol.Phase.FINISHED:
		var reason := str(state_value.get("reason", L10n.text("对局结束。")))
		_request_finish(reason)
	_layout()
	# Repeated snapshots (including impact playback) must not restart the intro.
	if phase == PvpProtocol.Phase.BATTLE and battle_ui.visible and str(state_value.match_id) != _banner_match_id:
		_banner_match_id = str(state_value.match_id)
		battle_start_banner.play(int(state_value.seat) == int(state_value.first_seat))

func _notify_match_found(value: Dictionary) -> void:
	# Only a locally requested new match is a notification. Timer snapshots,
	# resumed rooms and the offscreen prewarm must not vibrate again.
	if not _join_pending or value.get("waiting", false): return
	if int(value.get("phase", -1)) not in [PvpProtocol.Phase.MAP_PREVIEW, PvpProtocol.Phase.DRAFT, PvpProtocol.Phase.BATTLE]: return
	var match_id := str(value.get("match_id", ""))
	if match_id.is_empty() or match_id == _vibrated_match_id: return
	_vibrated_match_id = match_id
	_vibrate_match_found()

func _vibrate_match_found() -> void:
	if OS.has_feature("mobile") and DisplayServer.get_name() != "headless":
		Input.vibrate_handheld(MATCH_VIBRATION_MS)

func _draft_state(value: Dictionary) -> void:
	draft_view.show_state(value)
	if draft_map_preview.visible: draft_map_preview.show_inspection(value)
	var key := str(value.match_id)
	if key != _offers_key:
		_offers_key = key
		_close_draft_item_preview()
		detail_ui._close_detail()
		detail_inventory = draft_view.preview_inventory
		detail_ui.setup(detail_inventory)
	draft_view.set_pending(_pending)

func _ensure_actor(data: Dictionary) -> WandActor:
	var id := int(data.id)
	var actor: WandActor = actor_models.get(id)
	if actor != null:
		if is_instance_valid(actor.sprite) and not actor.sprite.is_queued_for_deletion(): return actor
		# Summon death animations free their sprites. Keep the public model,
		# without recreating dead summons on subsequent server snapshots.
		if int(data.hp) <= 0: return actor
	else: actor = WandActor.new()
	actor.species = data.species
	actor.data.tier = data.tier
	actor.data.net_id = id
	actor.data.net_owner = data.seat
	actor.data.hero_class = data.hero
	actor.data.armor_tier = data.armor
	actor_models[id] = actor
	# A newly connected viewer must not create already-dead summons.
	if int(data.hp) <= 0 and data.species != "hero": return actor
	var sprite: Node2D
	if data.species == "mirror_image":
		sprite = ScrollMirrorSprite.new()
		sprite.actor = actor
	elif data.species == "hero":
		sprite = DungeonHeroSprite.new()
		sprite.hero_class = data.hero
		sprite.armor_tier = data.armor
	else:
		sprite = WandSummonSprite.new()
		sprite.actor = actor
	dungeon.add_child(sprite)
	dungeon.move_child(sprite, dungeon.layers["RaisedGrass"].get_index())
	actor.sprite = sprite
	actor_models[id] = actor
	actor.cell = data.cell
	if sprite.has_method("place_cell"): sprite.place_cell(dungeon.ballistic_level.cell_coords(actor.cell))
	elif sprite.has_method("place"): sprite.place(dungeon.ballistic_level.cell_coords(actor.cell))
	if sprite is DungeonHeroSprite: sprite.motion_finished.connect(_settle_motion.bind(actor))
	sprite.show()
	return actor

func _battle_state(value: Dictionary, flights_played: bool = false) -> void:
	detail_ui._close_detail()
	var size_value := Vector2i(value.map_size[0], value.map_size[1])
	var terrain_value := PackedInt32Array(value.terrain)
	var region_value := int(value.get("map_region", 0))
	var bounds: Array = value.get("battle_bounds", [0, 0, size_value.x, size_value.y])
	map_gestures.view_bounds = Rect2i(bounds[0], bounds[1], bounds[2], bounds[3])
	if dungeon.map_size != size_value:
		dungeon.region = region_value
		dungeon.set_map(size_value, terrain_value, int(value.map_seed))
		visual.level = dungeon.ballistic_level
		effects = NatureEffects.new()
		effects.world = visual
		dungeon.add_child(effects)
		dungeon.move_child(effects, dungeon.fog_renderer.get_index())
	else:
		if dungeon.region != region_value: dungeon.set_region(region_value)
		# Client updates only art and cached terrain. It does not call observe or
		# environment.step_turn; visibility comes exclusively from the server.
		dungeon.apply_terrain_snapshot(terrain_value)
	dungeon.visibility_state.restore(value.visibility)
	dungeon.environment.scaling_depth = int(value.get("depth",PvpProtocol.BATTLE_DEPTH))
	dungeon.set_fog_enabled(true)
	# Arena warnings are public and survive reconnects; no hidden actor is exposed.
	_arena_warning.sync(value.get("collapse",{}).get("warning_cells",[]),size_value.x)
	visual.visible = dungeon.visibility_state.visible.duplicate()
	# Only replay server-tagged pushes for actors already displayed. A newly
	# revealed actor starts at its public position, without exposing a hidden path.
	_push_eligible.clear()
	if int(value.event_sequence) != _event_sequence:
		for event in value.events:
			if event.action != "move" or event.get("motion", "") != "push": continue
			var pushed := _actor_ref(event.get("actor"))
			if pushed != null and pushed.sprite is DungeonHeroSprite and pushed.sprite.visible:
				_push_eligible[int(pushed.data.net_id)] = true
	var present_ids := []
	visual.actors.clear()
	for data in value.actors:
		var id: int = data.id
		present_ids.append(id)
		var a := _ensure_actor(data)
		visual.actors.append(a)
		var old_cell := a.cell
		a.cell = data.cell
		a.hp = data.hp
		a.max_hp = data.max_hp
		a.shield = data.shield
		a.species = data.species
		a.data.hero_class = data.hero
		a.data.tier = data.tier
		a.data.level = data.level
		a.statuses.clear()
		for key in data.statuses: a.statuses[key] = INF if float(data.statuses[key]) < 0 else float(data.statuses[key])
		a.flying = bool(data.get("flying", a.has_status("levitation")))
		if not is_instance_valid(a.sprite) or a.sprite.is_queued_for_deletion(): continue
		if a.sprite is DungeonHeroSprite:
			a.sprite.set_local_player_marker(data.species == "hero" and int(data.seat) == int(value.seat) and int(data.hp) > 0)
			a.sprite.set_opponent_vitals(data.species == "hero" and int(data.seat) != int(value.seat), int(data.hp), int(data.max_hp), int(data.shield))
			a.sprite.flying = a.flying
			if a.sprite.hero_class != data.hero or a.sprite.armor_tier != data.armor: a.sprite.set_appearance(data.hero, data.armor)
			if old_cell != a.cell and not a.sprite.moving and not _push_eligible.has(id):
				var from := dungeon.ballistic_level.cell_coords(old_cell)
				var to := dungeon.ballistic_level.cell_coords(a.cell)
				if maxi(absi(from.x-to.x), absi(from.y-to.y)) == 1: a.sprite.move_to_cell(to)
				else: a.sprite.place_cell(to)
		elif a.sprite is WandSummonSprite:
			a.sprite.refresh()
			var swapped: bool = value.events.any(func(event):
				return event.get("motion", "") == "swap" and event.get("actor", {}).get("actor_ref", -1) == id)
			if old_cell != a.cell and swapped:
				a.sprite.move_to(dungeon.ballistic_level.cell_coords(a.cell))
			elif a.sprite._motion == null or not a.sprite._motion.is_running():
				a.sprite.place(dungeon.ballistic_level.cell_coords(a.cell))
		a.sprite.visible = true
		if int(data.seat) == int(value.seat) and data.species == "hero":
			var item_context: Dictionary = value.get("item_context", {})
			a.data.strength = int(item_context.get("strength", 10))
			a.data.magic_charge_level = int(item_context.get("magic_charge_level", 0))
			inventory.ring_actor = a
			_update_status(data)
	for id in actor_models:
		if id not in present_ids and is_instance_valid(actor_models[id].sprite): actor_models[id].sprite.hide()
	var saved_inventory := str(value.inventory)
	if saved_inventory != _inventory_key:
		_inventory_key = saved_inventory
		var aiming_uid := inventory.pending_item.uid if inventory.pending_item != null else ""
		var aiming_action := inventory.pending_action
		inventory.cancel_target()
		inventory.load_data(value.inventory)
		# A charge/quickslot refresh replaces item objects, not the player's aim.
		# Restore by authoritative uid without any visibility/terrain check.
		if not aiming_uid.is_empty() and int(value.active) == int(value.seat):
			for refreshed_item in inventory.all_items():
				if refreshed_item.uid == aiming_uid and inventory.usable(refreshed_item) and aiming_action in inventory.actions(refreshed_item):
					inventory.pending_item = refreshed_item
					inventory.pending_action = aiming_action
					break
	_refresh_input()
	var your_turn := int(value.active) == int(value.seat)
	turn_label.text = L10n.text("你的回合") if your_turn else L10n.text("对手回合")
	turn_label.add_theme_color_override("font_color", Color("ffff44") if your_turn else Color("ff4444"))
	turn_times_label.text = "%.3f / %.3f" % [value.times[int(value.seat)], value.times[1-int(value.seat)]]
	wait_button.disabled = not inventory.can_act
	dungeon.environment.fields.clear()
	for data in value.fields:
		var field := EnvironmentField.new(data.kind, terrain_value.size())
		field.cur = PackedInt32Array(data.cur)
		field.volume = 0
		for c in field.cur.size():
			if field.cur[c] > 0: field.include_cell(c, size_value.x); field.volume += field.cur[c]
		dungeon.environment.fields[data.kind] = field
	var next_plants: Array[int] = []
	for plant in value.get("plants", []):
		var index: int = Nature.PLANT_FRAMES.get(plant.kind, -1)
		if index >= 0:
			dungeon.set_feature(dungeon.ballistic_level.cell_coords(plant.cell), 112+index)
			next_plants.append(int(plant.cell))
	for cell in _plant_cells:
		if cell not in next_plants: dungeon.set_feature(dungeon.ballistic_level.cell_coords(cell), -1)
	_plant_cells = next_plants
	if int(value.event_sequence) != _event_sequence:
		var had_event_state := _event_sequence >= 0
		_event_sequence = value.event_sequence
		for event in value.events:
			# The first full view must not replay historical wait/buff notices.
			if event.action in ["hero_wait", "buff_added"] and not had_event_state: continue
			if flights_played and event.action in ["hero_throw", "hero_zap", "missile_return", "dragon_breath"]: continue
			_event(event)
	# Events describe only the latest action batch. After a missed batch or a
	# reconnect, an existing mirror can already be dead without a death event.
	# Reconcile from authoritative HP after normal event/impact playback;
	# ScrollMirrorSprite keeps repeated death requests from restarting its fade.
	for actor in visual.actors:
		if actor.hp <= 0 and is_instance_valid(actor.sprite) and actor.sprite is ScrollMirrorSprite and not actor.sprite.is_queued_for_deletion():
			actor.sprite.play_action(&"die")
	# Register flights before applying their already-resolved ground snapshot.
	_sync_ground(value.ground)
	_refresh_examine_actor()
	if not value.log.is_empty(): report.text = L10n.render_for_match(str(value.log[-1]), value)

func _settle_motion(a: WandActor) -> void:
	var id := int(a.data.net_id)
	if _push_events.has(id):
		var held: Array = _push_events[id]
		_push_events.erase(id)
		for event in held: _event(event)
		# A second push in the same action gets its own landing and event queue.
		if _push_events.has(id): return
		if _push_events.is_empty():
			_present_next_state.call_deferred()
	if a.sprite.cell == dungeon.ballistic_level.cell_coords(a.cell): return
	var destination := dungeon.ballistic_level.cell_coords(a.cell)
	if not a.sprite.move_to_cell(destination): a.sprite.place_cell(destination)

func _sync_ground(entries: Array, bounce_cell: int = -1) -> void:
	_ground_latest = entries
	# Keep existing floor art at an impact cell while its missile is in flight.
	# Later snapshots still update _ground_latest, so landing never resurrects
	# an item that has already been picked up, destroyed or otherwise removed.
	var displayed: Array = []
	for entry in entries:
		if not _ground_flights.has(int(entry.cell)): displayed.append(entry)
	for flight in _ground_flights.values(): displayed.append_array(flight.entries)
	_ground_displayed = displayed
	# Reuse unchanged sprites: periodic server snapshots must not interrupt a
	# drop animation or restart it. Ground item uids are cleared by the server,
	# so distinguish matching artwork at each cell by its occurrence number.
	var previous: Dictionary = {}
	for ground_sprite in ground_views:
		previous[ground_sprite.get_meta("pvp_ground_key", "")] = ground_sprite
	ground_views.clear()
	var occurrences: Dictionary = {}
	for entry in displayed:
		var cell := int(entry.cell)
		var base := "%d:%s:%s" % [cell, entry.item.get("type_id", ""), entry.item.get("visual", "")]
		var occurrence := int(occurrences.get(base, 0))
		occurrences[base] = occurrence + 1
		var key := "%s:%d" % [base, occurrence]
		var ground_sprite: DungeonItemSprite = previous.get(key)
		if ground_sprite != null:
			previous.erase(key)
		else:
			var item := InventoryItem.from_dict(entry.item)
			ground_sprite = dungeon.place_item(dungeon.ballistic_level.cell_coords(cell), item.visual)
			if ground_sprite == null: continue
			ground_sprite.set_meta("pvp_ground_key", key)
			if cell == bounce_cell: ground_sprite.drop()
		ground_sprite.set_item(InventoryItem.from_dict(entry.item))
		ground_views.append(ground_sprite)
	for ground_sprite in previous.values():
		dungeon.untrack_visibility(ground_sprite)
		ground_sprite.hide()
		ground_sprite.queue_free()

func _hold_ground_until_impact(cell: int) -> void:
	if not _ground_flights.has(cell):
		var existing: Array = []
		for entry in _ground_displayed:
			if int(entry.cell) == cell: existing.append(entry)
		_ground_flights[cell] = {"count":0, "entries":existing}
	_ground_flights[cell].count += 1

func _ground_impact(cell: int) -> void:
	if not is_inside_tree() or not _ground_flights.has(cell): return
	_ground_flights[cell].count -= 1
	if int(_ground_flights[cell].count) > 0: return
	_ground_flights.erase(cell)
	_sync_ground(_ground_latest, cell)

func _update_status(data: Dictionary) -> void:
	status.set_appearance(data.hero, data.armor)
	status.set_vitals(data.hp, data.max_hp, data.shield)
	status.clear_buffs()
	# Descriptions, counters and colours are calculated from the authoritative buff state.
	for entry in data.get("buff_info", []):
		status.put_buff(StatusBuff.from_dict(entry))

func _actor_ref(value: Variant) -> WandActor:
	var actor: WandActor = actor_models.get(int(value.get("actor_ref", -1))) if value is Dictionary else null
	return actor if actor != null and is_instance_valid(actor.sprite) and not actor.sprite.is_queued_for_deletion() else null

func _event(event: Dictionary) -> void:
	var actor := _actor_ref(event.get("actor"))
	if actor != null and _push_events.has(int(actor.data.net_id)):
		_push_events[int(actor.data.net_id)].append(event)
		return
	var target := _actor_ref(event.get("target"))
	var cell := int(event.get("cell", -1))
	var item: InventoryItem
	if event.get("item") is Dictionary and event.item.has("item_data"): item = InventoryItem.from_dict(event.item.item_data)
	match str(event.action):
		"arena_collapse":
			_arena_rockfall.map_width = dungeon.map_size.x
			_arena_rockfall.play(event.cells)
			effects.sound("rocks")
		"move":
			if actor != null and event.get("motion", "") == "push" and _push_eligible.has(int(actor.data.net_id)):
				if actor.sprite.push_to_cell(dungeon.ballistic_level.cell_coords(cell)):
					_push_events[int(actor.data.net_id)] = []
					_refresh_input()
		"hero_step":
			if actor != null and actor.sprite is DungeonHeroSprite:
				actor.sprite.queue_footstep(str(event.sound), dungeon.ballistic_level.cell_coords(cell))
		"hero_wait":
			if actor != null and actor.sprite is DungeonHeroSprite:
				# Hero.rest(false) -> CharSprite.DEFAULT -> FloatingText (1s).
				actor.sprite.show_status(Color.WHITE, "...")
		"pickup":
			if int(event.get("seat", -1)) != int(current.get("seat", -2)) or item == null: return
			inventory_ui.play_pickup_sound(item.type_id == "Dewdrop")
			if item.type_id != "Dewdrop":
				# Toolbar.PickedUpItem starts at raisedTileCenterToWorld, in screen space.
				var map_transform := dungeon.get_global_transform_with_canvas()
				var origin := dungeon.cell_center(dungeon.ballistic_level.cell_coords(cell)) - Vector2(0, 6.4)
				inventory_ui.animate_pickup(item, map_transform * origin, map_transform.get_scale().abs())
		"drink", "scroll_read":
			if actor != null and actor.sprite is DungeonHeroSprite: actor.sprite.play_action(&"operate" if event.action == "drink" else &"read")
			if event.action == "drink": effects.sound("drink")
			elif item == null or item.type_id not in ["ScrollOfLullaby", "ScrollOfRage", "ScrollOfRetribution"]: effects.sound("read")
		"hero_attack", "mirror_attack":
			if actor != null and actor.sprite is DungeonHeroSprite:
				# A swap and the mirror's next attack can share one server batch.
				# Attack playback cancels a walking sprite's motion, so replay it
				# through the landing barrier before changing its pose or facing.
				if actor.sprite.moving:
					_push_events[int(actor.data.net_id)] = [event]
					_refresh_input()
					return
				actor.sprite.face_cell(dungeon.ballistic_level.cell_coords(target.cell if target != null else int(event.get("to", actor.cell))))
				actor.sprite.play_action(&"attack")
		"hero_throw":
			_play_throw(event, _ground_impact.bind(int(event.to)))
		"missile_return":
			_play_return(event, _ground_impact.bind(int(event.to)))
		"hero_zap": _wand_effect(event, actor)
		"dragon_breath":
			if actor != null: effects.breathe(actor,event,Callable())
		"melee_hit":
			if actor != null and actor.sprite is DungeonHeroSprite: actor.sprite.flash()
		"surprise":
			if actor != null: effects.surprise(actor)
		"plant": dungeon.grow_plant(dungeon.ballistic_level.cell_coords(cell), int(Nature.PLANT_FRAMES.get(event.kind, -1)))
		"nature_operate":
			if actor != null and actor.sprite is DungeonHeroSprite: actor.sprite.play_action(&"operate")
		"nature_particles": effects.nature_burst(cell, str(event.kind), int(event.count), float(event.get("interval", 0.0)))
		"potion_snow": effects.snow_at(cell,int(event.count),float(event.interval))
		"nature_lightning":
			for arc in event.arcs: effects.lightning(effects.point(int(arc[0]), false), effects.endpoint(int(arc[1])))
		"nature_flare": effects.flare_cell(cell, event.color, int(event.rays), float(event.radius), float(event.duration))
		"nature_checked":
			for checked_cell in event.cells: effects.checked(int(checked_cell), cell)
		"nature_enchant":
			if actor != null and item != null: effects.enchant(actor, item, event.color)
		"nature_notice": _notice(str(event.text))
		"damage", "healing", "shielding":
			if actor != null: _floating(actor, int(event.get("amount", 0)), str(event.action), str(event.get("source", "")))
		"buff_added":
			if actor != null: BuffAnnouncements.show(actor.sprite, str(event.effect))
		"dodge":
			if actor != null and actor.sprite.has_method("show_dodge"): actor.sprite.show_dodge()
		"missile_blocked":
			if actor != null and actor.sprite.has_method("show_block"): actor.sprite.show_block()
			if actor != null and actor.sprite is DungeonHeroSprite: actor.sprite.flash()
		"death":
			if actor != null:
				if actor.sprite is DungeonHeroSprite: actor.sprite.play_action(&"die")
				elif actor.sprite.has_method("die"): actor.sprite.die()
		"splash":
			if item != null: effects.splash_at(effects.actor_point(actor) if actor != null else effects.point(cell, false), effects.potion_color(item), event.get("count", 5))
		"spell":
			if actor != null: effects.spell(actor, event.index, event.color)
		"flare":
			if actor != null: effects.flare(actor, event.get("color", Color.YELLOW))
		"scroll_flare":
			if actor != null: effects.scroll_flare(actor, event.color, event.rays)
		"scroll_specks": effects.start_specks(actor, cell, event.kind, event.interval, event.count, event.center)
		"identification":
			if actor != null: effects.identification(actor)
		"scroll_teleport":
			if actor != null: effects.appear(actor, event.from)
		"scroll_flash": effects.flash(event.color)
		"sound", "melee_sound", "missile_hit_sound": effects.sound(str(event.sound), event.get("pitch", 1.0))
		"blast": effects.blast(cell)
		"burst": effects.burst(event.kind, effects.point(cell), event.count)
		"melee_bleed":
			if actor != null:
				var layer := CombatTextLayer.for_actor(actor.sprite)
				layer.show_status(layer.to_local(actor.sprite.to_global(Vector2(0,-13))), "Bleeding " + str(event.amount), Color("ff8800"), CombatTextAssets.Icon.NO_ICON, dungeon.ballistic_level.cell_coords(actor.cell))
		"missile_blood", "ring_blazing":
			if actor != null: effects.splash_at(effects.actor_point(actor), Color("bb0000"), event.get("count", 5))
		"ward_zap":
			if actor != null and target != null: effects.beam("death", effects.actor_point(actor), effects.actor_point(target), 0.5)

func _play_return(event: Dictionary, landed: Callable) -> void:
	var actor := _actor_ref(event.get("actor"))
	if actor == null or not event.get("item") is Dictionary or not event.item.has("item_data"):
		landed.call_deferred()
		return
	var item := InventoryItem.from_dict(event.item.item_data)
	var destination := int(event.to)
	_hold_ground_until_impact(destination)
	effects.throw_weapon(item, actor, destination, landed, int(event.from), true)

func _play_throw(event: Dictionary, landed: Callable) -> void:
	var actor := _actor_ref(event.get("actor"))
	if actor == null or not event.get("item") is Dictionary or not event.item.has("item_data"):
		landed.call_deferred()
		return
	var item := InventoryItem.from_dict(event.item.item_data)
	var destination := int(event.to)
	if actor.sprite is DungeonHeroSprite:
		actor.sprite.face_cell(dungeon.ballistic_level.cell_coords(destination))
		actor.sprite.play_action(&"zap")
	var anchors := _throw_anchors(int(event.cell), destination)
	_hold_ground_until_impact(destination)
	if MissileRules.is_weapon(item): effects.throw_weapon(item, actor, destination, landed, -1, false, anchors)
	else: effects.throw_item(item, actor, destination, landed, anchors)

func _wand_effect(event: Dictionary, actor: WandActor, arrived: Callable = Callable()) -> void:
	if actor == null:
		if arrived.is_valid(): arrived.call_deferred()
		return
	var anchors := _throw_anchors(int(event.cell), int(event.bolt.collision))
	var start: Vector2 = anchors.start
	var end: Vector2 = anchors.end
	if actor.sprite is DungeonHeroSprite: actor.sprite.face_cell(dungeon.ballistic_level.cell_coords(event.bolt.collision)); actor.sprite.play_action(&"zap")
	match str(event.type):
		"WandOfDisintegration":
			var path: Array = event.bolt.path
			end = effects.point(path[mini(int(event.bolt.dist), 6+2*int(event.level))])
			effects.beam("death", start, end, 0.5); effects.sound("ray")
			if arrived.is_valid(): arrived.call_deferred()
		"WandOfPrismaticLight", "WandOfTransfusion":
			effects.beam("light" if event.type == "WandOfPrismaticLight" else "health", start, end, 1); effects.sound("ray")
			if arrived.is_valid(): arrived.call_deferred()
		"WandOfLightning":
			for arc in event.arcs: effects.lightning(effects.endpoint(arc[0]), effects.endpoint(arc[1]))
			effects.sound("lightning")
			if arrived.is_valid(): arrived.call_deferred()
		"WandOfFireblast", "WandOfRegrowth":
			var rays: Array = event.get("rays", [])
			var last_ray := -1
			var longest := -1.0
			for index in rays.size():
				var distance := start.distance_squared_to(effects.point(int(rays[index].end)))
				if distance > longest:
					longest = distance
					last_ray = index
			# One completion per cast. Keep the result queued until the cone's
			# furthest flight arrives, so distant targets cannot take an early hit.
			for index in rays.size():
				effects.missile(WandEffects.KIND[event.type], start, effects.point(int(rays[index].end)), arrived if index == last_ray else Callable(), 200, 10, 0.03)
			if last_ray < 0 and arrived.is_valid(): arrived.call_deferred()
			effects.sound("zap")
		_:
			var kind: String = WandEffects.KIND.get(event.type, "white")
			var sizes := {"white":4, "frost":0, "corrosion":3, "force":0, "earth":4, "ward":4, "shadow":4}
			var speed := int(event.bolt.dist) * 20 if event.type == "WandOfWarding" and int(event.bolt.dist) > 10 else 200
			effects.missile(kind, start, end, arrived, speed, sizes.get(kind, 4), 0.01); effects.sound("zap")

func _throw_anchors(from_cell: int, to_cell: int) -> Dictionary:
	# Snapshots contain positions AFTER resolution (including knockback/teleport).
	# Replay the flight in map space at its recorded action cells, not at a
	# cached sprite position or a sprite currently jumping between cells.
	var center := DungeonHeroSprite.BODY_POSITION + Vector2(HeroAssets.FRAME_SIZE) / 2
	var start := dungeon.cell_center(dungeon.ballistic_level.cell_coords(from_cell)) + center
	var end := effects.point(to_cell)
	var victim := visual.actor_at(to_cell)
	if victim != null:
		if victim.sprite is DungeonHeroSprite:
			end = dungeon.cell_center(dungeon.ballistic_level.cell_coords(to_cell)) + center
		elif victim.sprite is WandSummonSprite:
			var body: AnimatedSprite2D = victim.sprite.body
			var frame := body.sprite_frames.get_frame_texture(body.animation, body.frame)
			end = dungeon.cell_center(dungeon.ballistic_level.cell_coords(to_cell)) + body.position + frame.get_size() / 2
	return {"start":start, "end":end}

func _floating(a: WandActor, amount: int, kind: String, source: String) -> void:
	if amount <= 0 or not a.sprite.visible: return
	var layer := CombatTextLayer.for_actor(a.sprite)
	var pos := layer.to_local(a.sprite.to_global(Vector2(0,-13)))
	var cell := dungeon.ballistic_level.cell_coords(a.cell)
	if kind != "damage": layer.show_status(pos, str(amount), Color.GREEN, CombatTextAssets.Icon.HEALING if kind == "healing" else CombatTextAssets.Icon.SHIELDING, cell); return
	if a.sprite is DungeonHeroSprite: a.sprite.flash()
	var icons := {"physical":CombatTextAssets.Icon.PHYS_DMG, "burning":CombatTextAssets.Icon.BURNING, "corrosion":CombatTextAssets.Icon.CORROSION, "poison":CombatTextAssets.Icon.POISON, "bleeding":CombatTextAssets.Icon.BLEEDING, "toxic_gas":CombatTextAssets.Icon.TOXIC, "corruption":CombatTextAssets.Icon.CORRUPTION, "electricity":CombatTextAssets.Icon.SHOCKING}
	layer.show_damage(pos, amount, icons.get(source, CombatTextAssets.Icon.MAGIC_DMG), cell)

func _select_item(item: InventoryItem, action: String) -> void:
	var prompt := L10n.text("选择灌注法杖") if action == "IMBUE" else L10n.text("选择符石作用物品") if action == "USE" else L10n.text("选择卷轴作用物品")
	var predicate := func(candidate: InventoryItem):
		if action == "USE": return Nature.selectable(item, candidate)
		if action == "IMBUE": return candidate.category == "wand" and not candidate.cursed
		if item.type_id == "ScrollOfUpgrade": return ScrollWorld.upgradable(candidate)
		if item.type_id == "ScrollOfRemoveCurse": return candidate.cursed or candidate.metadata.get("enchantment_curse", false) or candidate.metadata.get("glyph_curse", false) or inventory.is_equipped(candidate) and inventory.ring_actor.has_status("degrade")
		return candidate != item and candidate.category in ["weapon", "wand", "ring", "missile"] and candidate.type_id not in ["Dart", "SpiritBow", "MagesStaff"]
	inventory_ui.select_item(prompt, predicate, func(selected):
		if selected == null: return
		var confirm := func(): inventory_ui._close_detail(); _send({"kind":"item", "uid":item.uid, "action":action, "selected_uid":selected.uid})
		if item.type_id == "StoneOfAugmentation":
			_select_augment(item, selected)
		elif item.type_id == "ScrollOfUpgrade": inventory_ui.show_upgrade_preview(item, selected, confirm, func(): _select_item(item, action))
		else: confirm.call())

func _select_augment(stone: InventoryItem, selected: InventoryItem) -> void:
	var values := ["evasion", "defense", "none"] if selected.category == "armor" else ["speed", "damage", "none"]
	var labels := {"speed":L10n.text("攻速上升 伤害下降"), "damage":L10n.text("伤害上升 攻速下降"), "evasion":L10n.text("闪避上升 防御下降"), "defense":L10n.text("防御上升 闪避下降"), "none":L10n.text("移除强化")}
	values.erase(str(selected.metadata.get("augment", "none")))
	var options := []
	for value in values: options.append(labels[value])
	options.append(L10n.text("算了"))
	inventory_ui.show_options(selected, L10n.text("强化一项属性也会弱化另一项属性。你想强化哪个属性？"), options, func(index):
		if index < 0 or index >= values.size():
			_select_item(stone, "USE")
			return
		_send({"kind":"item", "uid":stone.uid, "action":"USE", "selected_uid":selected.uid, "augment":values[index]}))

func _pickup() -> void:
	for a in current.get("actors", []):
		if a.species == "hero" and a.seat == current.seat: _send({"kind":"pickup", "cell":a.cell}); return

func _interact_self() -> void:
	var hero := inventory.ring_actor
	if hero == null: return
	# Hero.handle gives floor loot precedence over an in-place plant press.
	for entry in current.get("ground", []):
		if int(entry.cell) == hero.cell:
			_pickup()
			return
	for plant in current.get("plants", []):
		if int(plant.cell) == hero.cell:
			_send({"kind":"move", "cell":hero.cell})
			return
	_pickup()

func _examine_cell(cell: int) -> void:
	_cancel_target()
	var entries: Array[Dictionary] = []
	# Never query hidden actors cached in actor_models or reconstruct unseen loot.
	for data in current.get("actors", []):
		if int(data.hp) <= 0 and data.species != "hero": continue
		if int(data.cell) == cell:
			entries.append({"kind":"actor", "id":int(data.id), "title":ExamineInfo.actor_name(data, current)})
	for ground in current.get("ground", []):
		if int(ground.cell) != cell: continue
		var item := InventoryItem.from_dict(ground.item)
		var title := item.display_name()
		if item.level > 0: title += " +%d" % item.level
		if item.quantity > 1: title += " x%d" % item.quantity
		entries.append({"kind":"item", "cell":cell, "item":ground.item, "title":title})
	for plant in current.get("plants", []):
		if int(plant.cell) == cell:
			entries.append({"kind":"plant", "cell":cell, "plant":plant.kind,
				"title":L10n.title_case(ExamineInfo.message("plants.%s.name" % plant.kind))})
	var terrain_entry := {"kind":"terrain", "cell":cell,
		"title":ExamineInfo.tile_name(int(current.terrain[cell]))}
	if entries.is_empty(): _show_examine_entry(terrain_entry)
	elif entries.size() == 1: _show_examine_entry(entries[0])
	else:
		entries.append(terrain_entry)
		examine_window.show_choices(entries)

func _show_examine_entry(entry: Dictionary) -> void:
	match str(entry.kind):
		"actor":
			for data in current.get("actors", []):
				if int(data.id) != int(entry.id): continue
				var model: WandActor = actor_models.get(int(data.id))
				if model == null or not is_instance_valid(model.sprite) or model.sprite.is_queued_for_deletion(): return
				var body: AnimatedSprite2D = model.sprite.body
				var frame := body.sprite_frames.get_frame_texture(&"idle", 0)
				examine_window.show_actor(data, ExamineInfo.actor_name(data, current), frame)
				return
		"item":
			for ground in current.get("ground", []):
				if int(ground.cell) == int(entry.cell) and ground.item == entry.item:
					examine_window.close()
					detail_ui.show_item(InventoryItem.from_dict(ground.item), true)
					return
		"plant":
			for plant in current.get("plants", []):
				if int(plant.cell) != int(entry.cell) or str(plant.kind) != str(entry.plant): continue
				var frame_index := 112 + int(Nature.PLANT_FRAMES.get(plant.kind, 0))
				var frame := AtlasTexture.new()
				frame.atlas = preload("res://assets/environment/terrain_features.png")
				var columns := int(frame.atlas.get_width() / 16)
				frame.region = Rect2((frame_index % columns) * 16, int(frame_index / columns) * 16, 16, 16)
				examine_window.show_text(L10n.title_case(ExamineInfo.message("plants.%s.name" % plant.kind)), frame,
					ExamineInfo.message("plants.%s.desc" % plant.kind))
				return
		"terrain":
			var cell := int(entry.cell)
			if cell < 0 or cell >= current.get("terrain", []).size(): return
			var tile := int(current.terrain[cell])
			var description := ExamineInfo.tile_description(tile)
			for field in current.get("fields", []):
				if cell >= field.cur.size() or int(field.cur[cell]) <= 0: continue
				var field_description := ExamineInfo.message("actors.blobs.%s.desc" % str(field.kind).replace("_", ""))
				if not field_description.is_empty(): description += ("\n\n" if not description.is_empty() else "") + field_description
			if description.is_empty(): description = ExamineInfo.message("windows.wndinfocell.nothing")
			examine_window.show_text(ExamineInfo.tile_name(tile),
				dungeon.inspection_texture(dungeon.ballistic_level.cell_coords(cell)), description)

func _refresh_examine_actor() -> void:
	if not examine_window.visible or examine_window.actor_id < 0: return
	for data in current.get("actors", []):
		if int(data.id) == examine_window.actor_id:
			if int(data.hp) <= 0 and data.species != "hero":
				examine_window.close()
				return
			examine_window.update_actor(data)
			return
	# Leaving visibility must close the inspector, including an open buff page.
	examine_window.close()

func _unhandled_input(event: InputEvent) -> void:
	if not stage.visible or _ending: return
	if battle_actions.is_open():
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_BACK]: battle_actions.back()
		get_viewport().set_input_as_handled()
		return
	# Desktop mouse clicks also generate an emulated touch in this project.
	# Handle the real mouse event once: otherwise the touch opens the inspector
	# and the same mouse press immediately closes its new modal backdrop.
	if event is InputEventScreenTouch and event.device == InputEvent.DEVICE_ID_EMULATION: return
	if examine_window.visible:
		if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_BACK]: examine_window.close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_E: _toggle_examine(); get_viewport().set_input_as_handled(); return
		if event.keycode in [KEY_I, KEY_B]: inventory_ui.toggle_bag(); get_viewport().set_input_as_handled(); return
		if event.keycode in [KEY_ESCAPE, KEY_BACK]:
			_battle_back()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SPACE and inventory.can_act: _wait(); return
		if event.keycode == KEY_G and inventory.can_act: _pickup(); return
	map_gestures.begin(event)

func _battle_back() -> void:
	if battle_actions.is_open(): battle_actions.back()
	elif examine_window.visible: examine_window.close()
	elif inventory_ui.detail_layer != null: inventory_ui._close_detail()
	elif detail_ui.detail_layer != null: detail_ui._close_detail()
	elif inventory_ui.bag_layer != null: inventory_ui.close_bag()
	elif hud.modal_layer != null: hud.close_inspector()
	else:
		_cancel_target()
		battle_actions.open_menu()

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or not _owns_go_back or not _ui_built or _returning: return
	if is_instance_valid(_draft_item_preview): return # The preview owns its Back action.
	if stage.visible and not _ending: _battle_back()
	elif not _ending: _return_menu()

func _can_navigate_map() -> bool:
	return stage.visible and not _ending and not battle_actions.is_open() and not examine_window.visible and hud.modal_layer == null and inventory_ui.bag_layer == null and inventory_ui.detail_layer == null and detail_ui.detail_layer == null

func _hits_hero(pos: Vector2) -> bool:
	var hero := inventory.ring_actor
	if hero == null or not hero.sprite is DungeonHeroSprite: return false
	var body: AnimatedSprite2D = hero.sprite.body
	return body.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(HeroAssets.FRAME_SIZE)).has_point(body.get_global_transform_with_canvas().affine_inverse() * pos)

func _hit_sheep(pos: Vector2) -> int:
	for data in current.get("actors", []):
		if data.species != "sheep" or int(data.hp) <= 0: continue
		var actor: WandActor = actor_models.get(int(data.id))
		if actor == null or not is_instance_valid(actor.sprite) or not actor.sprite.is_visible_in_tree(): continue
		var body: AnimatedSprite2D = actor.sprite.body
		var frame := body.sprite_frames.get_frame_texture(body.animation, body.frame)
		if Rect2(Vector2.ZERO, frame.get_size()).has_point(body.get_global_transform_with_canvas().affine_inverse()*pos): return int(data.cell)
	return -1

func _map_press(pos: Vector2) -> void:
	if not _can_navigate_map() or not inventory.can_act or _examining:
		_press_highlight.clear()
		return
	var cell_pos := dungeon.local_to_cell(dungeon.get_global_transform_with_canvas().affine_inverse()*pos)
	if not dungeon.contains(cell_pos):
		_press_highlight.clear()
		return
	if (inventory.pending_item == null or inventory.pending_action == "THROW") and _hits_hero(pos):
		cell_pos = dungeon.ballistic_level.cell_coords(inventory.ring_actor.cell)
	elif inventory.pending_item == null:
		var sheep := _hit_sheep(pos)
		if sheep >= 0: cell_pos = dungeon.ballistic_level.cell_coords(sheep)
	_press_highlight.hold(cell_pos)

func _map_tap(pos: Vector2) -> void:
	if not _can_navigate_map(): return
	var cell_pos := dungeon.local_to_cell(dungeon.get_global_transform_with_canvas().affine_inverse()*pos)
	if not dungeon.contains(cell_pos):
		if inventory.can_act and inventory.pending_item == null and not _examining:
			_notice("只能移动到相邻的格子")
		return
	get_viewport().set_input_as_handled()
	if _examining:
		# Inspect the raised artwork at the actor's actual authoritative cell.
		for data in current.get("actors", []):
			var model: WandActor = actor_models.get(int(data.id))
			if model == null or not is_instance_valid(model.sprite): continue
			if model.sprite.is_queued_for_deletion() or not model.sprite.visible: continue
			if int(data.hp) <= 0 and data.species != "hero": continue
			var body: AnimatedSprite2D = model.sprite.body
			var frame := body.sprite_frames.get_frame_texture(body.animation, body.frame)
			if Rect2(Vector2.ZERO, frame.get_size()).has_point(body.get_global_transform_with_canvas().affine_inverse() * pos):
				cell_pos = dungeon.ballistic_level.cell_coords(int(data.cell))
				break
		_examine_cell(dungeon.ballistic_level.cell_id(cell_pos))
		return
	if not inventory.can_act: _notice(L10n.text("还未轮到你行动。")); return
	# The raised hero artwork extends above its floor tile. Both self-throws
	# and normal pickup clicks must resolve to the tile under the hero's feet.
	var hero := inventory.ring_actor
	var clicked_hero := _hits_hero(pos)
	if inventory.pending_item != null:
		if inventory.pending_action == "THROW" and clicked_hero:
			cell_pos = dungeon.ballistic_level.cell_coords(hero.cell)
		inventory.finish_target(cell_pos)
		return
	if clicked_hero:
		_interact_self()
		return
	var sheep := _hit_sheep(pos)
	if sheep >= 0: cell_pos = dungeon.ballistic_level.cell_coords(sheep)
	var cell := dungeon.ballistic_level.cell_id(cell_pos)
	for actor in current.get("actors", []):
		if int(actor.hp) <= 0: continue
		if actor.cell == cell and actor.species == "hero" and actor.seat == current.seat:
			_interact_self()
			return
		if actor.cell == cell and (actor.species == "sheep" or actor.seat != current.seat):
			# Mind vision may show an invisible hostile. A step still reveals it.
			if actor.statuses.has("invisibility") and _can_step_to(cell, hero): _send({"kind":"move", "cell":cell})
			else: _send({"kind":"attack", "cell":cell})
			return
	if not _can_step_to(cell, hero):
		_notice("只能移动到相邻的格子")
		return
	_send({"kind":"move", "cell":cell})

func _can_step_to(cell: int, hero: WandActor) -> bool:
	if hero == null or not dungeon.ballistic_level.inside_map(cell): return false
	var delta := dungeon.ballistic_level.cell_coords(cell) - dungeon.ballistic_level.cell_coords(hero.cell)
	if maxi(absi(delta.x), absi(delta.y)) != 1: return false
	var level := dungeon.ballistic_level
	if not (level.passable[cell] or hero.flying and level.avoid[cell]): return false
	for actor in current.get("actors", []):
		if int(actor.cell) == cell and int(actor.hp) > 0:
			if int(actor.seat) == int(current.seat):
				if bool(actor.get("immovable", false)): return false
				for effect in ["paralysis", "frost", "roots", "vertigo"]:
					if hero.has_status(effect) or actor.statuses.has(effect): return false
				return true
			return int(actor.seat) != int(current.seat) and actor.statuses.has("invisibility") and actor.species != "sheep"
	return true

func _process(delta: float) -> void:
	if not _ui_built or has_meta("prewarm"): return
	_watch_preview()
	var reconnecting := PvpNet.is_reconnecting() and not _ending
	reconnect_overlay.visible = reconnecting
	if reconnecting:
		reconnect_label.text = L10n.text("正在恢复连接…\n剩余等待时间：%d秒\n思考时间仍会继续计算。") % ceili(PvpNet.reconnect_remaining_msec()/1000.0)
	if _finish_pending: _try_finish()
	_watch_finish(delta)
	if battle_ui.visible:
		_refresh_input()
		_refresh_battle_clock()
		if current.has("opponent_reconnect_msec") and not _ending:
			report.text = L10n.text("对手暂时离线，等待重连：%d秒") % ceili(int(current.opponent_reconnect_msec)/1000.0)
	if _join_pending and current.is_empty() and _connected_at > 0 and Time.get_ticks_msec()-_connected_at > PvpNet.SESSION_TIMEOUT_MS:
		_join_pending = false
		_connected_at = 0
		await PvpNet.leave()
		PvpNet.monitor_server()
		_refresh_lobby_connection()
		lobby_status.text = L10n.text("进入对战超时，请稍后重试。")

func _layout() -> void:
	if not is_node_ready() or not _ui_built: return
	var safe := ScreenLayout.safe_rect(get_viewport())
	lobby.size = Vector2(minf(320, safe.size.x-20), 0)
	lobby.size.y = lobby.get_combined_minimum_size().y
	lobby.position = safe.position + (safe.size-lobby.size)/2
	draft_view.position = safe.position
	draft_view.size = safe.size
	draft_view.refresh_layout()
	arena_preview._layout()
	draft_map_preview._layout()
	battle_ui.position = Vector2.ZERO
	battle_ui.size = get_viewport_rect().size
	hud.refresh_layout()
	var top := maxf(safe.position.y+65, hud.pane.get_global_rect().end.y+3)
	ScreenLayout.place(turn_row, Rect2(safe.position.x, top, safe.size.x, 22))
	ScreenLayout.place(battle_time_label, Rect2(safe.position.x, top+22, safe.size.x, 20))
	ScreenLayout.place(action_status_label, Rect2(safe.position.x, top+42, safe.size.x, 20))
	battle_actions.place(safe, maxf(1, hud.pane.scale.x))
	if inventory_ui != null and inventory_ui.toolbar != null:
		var toolbar := inventory_ui.toolbar
		wait_button.scale = toolbar.scale
		wait_button.position = Vector2(safe.position.x + 2, toolbar.position.y - 2 * toolbar.scale.y).floor()
		examine_button.scale = toolbar.scale
		examine_button.position = wait_button.position + Vector2(22 * toolbar.scale.x, 0)
	target_prompt.place(safe)
	ScreenLayout.place(report, Rect2(safe.position.x+8, safe.end.y-80, safe.size.x-16, 24))
	# GameScene draws the dungeon behind its UI camera. Clip only at the screen
	# edge; reserving header/footer bands here hid the map behind black strips.
	ScreenLayout.place(stage, get_viewport_rect())
	if dungeon.map_size != Vector2i.ZERO:
		map_gestures.update_layout(str(current.get("match_id", "")))

func _watch_preview() -> void:
	if _ending or _returning: return
	if current.get("phase", -1) != PvpProtocol.Phase.MAP_PREVIEW:
		_preview_sync_match = ""
		_preview_sync_at = 0
		_preview_reconnect_started = false
		return
	var match_id := str(current.get("match_id", ""))
	if match_id != _preview_sync_match:
		_preview_sync_match = match_id
		_preview_sync_at = 0
		_preview_reconnect_started = false
	# A scene can miss the signal even though the network cache is current.
	# Apply only an actual later server phase, never predict selection locally.
	var cached: Dictionary = PvpNet.latest
	if str(cached.get("match_id", "")) == match_id and cached.get("phase", -1) in [PvpProtocol.Phase.DRAFT, PvpProtocol.Phase.BATTLE, PvpProtocol.Phase.FINISHED]:
		print("PVP_PREVIEW_RECOVER_CACHE room=%s phase=%d" % [match_id, int(cached.phase)])
		_state(cached)
		return
	var now := Time.get_ticks_msec()
	var stale := now - arena_preview._deadline
	if stale < PREVIEW_SYNC_GRACE_MS or PvpNet.is_reconnecting(): return
	# If the reliable stream remains stalled, replace the transport using the
	# existing resume credential, keeping this room and all authority timers.
	if stale >= PREVIEW_RECONNECT_MS and not _preview_reconnect_started:
		if PvpNet.recover_match_connection(match_id) == OK:
			_preview_reconnect_started = true
			print("PVP_PREVIEW_RECOVER_CONNECTION room=%s stale_ms=%d" % [match_id, stale])
			return
	if now < _preview_sync_at: return
	_preview_sync_at = now + PvpNet.STATE_SYNC_INTERVAL_MS
	if PvpNet.request_match_state(match_id) == OK:
		print("PVP_PREVIEW_SYNC_REQUEST room=%s stale_ms=%d" % [match_id, stale])

func _watch_finish(delta: float) -> void:
	if _terminal_state.is_empty() or _ending or _returning: return
	# Track finite presentation only: idle loops and ambient particles must
	# never hide a stalled action. Slow actions still reset this every frame.
	var progress: Array = [_event_sequence, _impact_flights, _push_events.size()]
	for actor in actor_models.values():
		var sprite: Node2D = actor.sprite
		if not is_instance_valid(sprite) or sprite.is_queued_for_deletion(): continue
		if sprite is DungeonHeroSprite:
			if sprite.moving: progress.append(sprite.position)
			if sprite._flash_time > 0: progress.append(sprite._flash_time)
		elif sprite is WandSummonSprite:
			if sprite._motion != null and sprite._motion.is_running(): progress.append(sprite.position)
		var body: AnimatedSprite2D = sprite.get("body")
		if body != null and body.sprite_frames != null and body.is_playing() and not body.sprite_frames.get_animation_loop(body.animation):
			progress.append([body.animation, body.frame, body.frame_progress])
		if sprite.get("_fading_out") == true: progress.append(sprite.modulate.a)
	if effects != null:
		for key in ["missiles", "beams", "flights", "spells", "flares", "teleports", "transmutations"]:
			for effect in effects.get(key): progress.append([key, effect.age])
		if effects._flash_age < 1: progress.append(effects._flash_age)
	for emitter in _arena_rockfall.emitters: progress.append([emitter.left, emitter.clock])
	for particle in _arena_rockfall.particles: progress.append(particle.age)
	if progress != _finish_progress:
		_finish_progress = progress
		_finish_stall = 0.0
		return
	# Count rendered game time, excluding time spent suspended in the background.
	_finish_stall += minf(delta, 0.25)
	if _finish_stall < FINISH_STALL_SECONDS: return
	_recover_finish()

func _recover_finish() -> void:
	var result := _terminal_state
	print("PVP_FINISH_RECOVERED match=", result.get("match_id", ""))
	_state_queue.clear()
	_impact_state.clear()
	_impact_cells.clear()
	_impact_flights = 0
	_push_events.clear()
	_push_eligible.clear()
	# Reconcile the final HP/positions without replaying old attacks or flights.
	_event_sequence = int(result.get("event_sequence", _event_sequence))
	_apply_state(result, true)
	for actor in actor_models.values():
		var sprite: Node2D = actor.sprite
		if not is_instance_valid(sprite) or sprite.is_queued_for_deletion() or not sprite is DungeonHeroSprite: continue
		sprite._death_pending = false
		sprite.place_cell(dungeon.ballistic_level.cell_coords(actor.cell))
		sprite.play_action(&"die" if actor.hp <= 0 else &"idle")
		if actor.hp <= 0:
			var frames: SpriteFrames = sprite.body.sprite_frames
			sprite.body.set_frame_and_progress(frames.get_frame_count(sprite.body.animation) - 1, 1.0)
			sprite.body.pause()
		sprite._action_in_progress = false
	_end(str(result.get("reason", L10n.text("对局结束。"))))

func _request_finish(reason: String) -> void:
	_finish_pending = true
	_finish_reason = reason
	_state_queue.clear()
	_battle_tick.reset()
	_press_highlight.clear()
	_cancel_target()
	_refresh_input()
	if effects != null: effects.finish_actions = true
	_try_finish()

func _try_finish() -> void:
	if not _finish_pending or _ending: return
	if _arena_rockfall.is_presenting_action(): return
	if not _impact_state.is_empty() or not _push_events.is_empty(): return
	for actor in actor_models.values():
		var sprite: Node2D = actor.sprite
		if not is_instance_valid(sprite) or sprite.is_queued_for_deletion() or not sprite.is_visible_in_tree(): continue
		if sprite.has_method("is_presenting_action") and sprite.is_presenting_action(): return
	if effects != null and effects.is_presenting_action(): return
	_end(_finish_reason)

func _end(text: String) -> void:
	text = L10n.render_for_match(text, current)
	if _ending: return
	_ending = true
	battle_actions.close()
	_close_draft_item_preview()
	_terminal_state = {}
	_finish_progress.clear()
	_finish_stall = 0.0
	reconnect_overlay.hide()
	arena_preview.hide()
	draft_map_preview.hide()
	draft_view.cancel_intro()
	_press_highlight.clear()
	_battle_tick.reset()
	map_gestures.reset()
	_arena_warning.clear()
	_arena_rockfall.clear()
	battle_start_banner.cancel()
	_examining = false
	examine_window.close()
	_state_queue.clear()
	_impact_state.clear()
	_impact_cells.clear()
	_impact_flights = 0
	_push_eligible.clear()
	_push_events.clear()
	_finish_pending = false
	_finish_reason = ""
	inventory.can_act = false
	inventory_ui.close_bag()
	inventory_ui._close_detail()
	detail_ui._close_detail()
	var overlay := ColorRect.new()
	overlay.name = "MatchResult"
	overlay.color = Color(0,0,0,0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 120)
	panel.add_theme_stylebox_override("panel", UiAssets.get_style("WINDOW"))
	center.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var label := _label(text, 18, Color("ffff44"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	column.add_child(_label(L10n.text("5 秒后返回主菜单。"), 12))
	column.add_child(_button(L10n.text("返回主菜单"), _return_menu))
	get_tree().create_timer(5).timeout.connect(func(): if is_inside_tree(): _return_menu())

func _return_menu() -> void:
	if _returning: return
	_returning = true
	_close_draft_item_preview()
	_battle_tick.reset()
	print("PVP_CLIENT_RETURN_MENU")
	await PvpNet.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	if _owns_go_back: get_tree().quit_on_go_back = _previous_quit_on_back
	if _battle_tick != null: _battle_tick.reset()
	print("PVP_CLIENT_SCENE_EXIT")
	for binding in [[PvpNet.state_received,_state], [PvpNet.notice,_notice], [PvpNet.connection_changed,_connection], [PvpNet.command_finished,_ack], [PvpNet.server_status_changed,_refresh_lobby_connection]]:
		if binding[0].is_connected(binding[1]): binding[0].disconnect(binding[1])
