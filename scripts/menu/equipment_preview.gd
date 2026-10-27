# Journal/market inspection: shared WndInfoItem text followed by the demonstration.
extends Control
signal closed
const Sandbox = preload("res://scripts/menu/equipment_sandbox.gd")
const PotionSandbox = preload("res://scripts/menu/potion_sandbox.gd")
const SnapFreezeSandbox = preload("res://scripts/menu/snap_freeze_sandbox.gd")
const RestorativePotionSandbox = preload("res://scripts/menu/restorative_potion_sandbox.gd")
const ShroudingFogSandbox = preload("res://scripts/menu/shrouding_fog_sandbox.gd")
const ElementalPotionSandbox = preload("res://scripts/menu/elemental_potion_sandbox.gd")
const ProtectivePotionSandbox = preload("res://scripts/menu/protective_potion_sandbox.gd")
const ScrollSandbox = preload("res://scripts/menu/scroll_sandbox.gd")
const WandSandbox = preload("res://scripts/menu/wand_sandbox.gd")
const SeedSandbox = preload("res://scripts/menu/seed_sandbox.gd")
const StoneSandbox = preload("res://scripts/menu/stone_sandbox.gd")
const MissileSandbox = preload("res://scripts/menu/missile_sandbox.gd")
const EnchantmentSandbox = preload("res://scripts/menu/enchantment_sandbox.gd")
const GlyphSandbox = preload("res://scripts/menu/glyph_sandbox.gd")
const Catalog = preload("res://scripts/menu/equipment_catalog.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const PANEL_WIDTH := 148.0
const HEADER_HEIGHT := 28.0
const ANIMATION_HEIGHT := 48.0
const SECTION_GAP := 2.0
const BOTTOM_MARGIN := 6.0
const CLOSE_HEIGHT := 20.0
const ANIMATED_CATEGORIES := ["weapon", "armor", "missile", "potion", "scroll", "wand", "seed", "stone"]
var item: InventoryItem
## Journal owns its own Back handling; standalone market inspections own theirs.
var handle_cancel_input := false
var panel: Panel
var sandbox: Control
var _canvas: Control
var _content: Control
var _details: InventoryUI
var _info: Dictionary
var _notice: Label
var _back: Button
var _description := ""
var _layout_pending := false
var _owns_back_request := false
var _previous_quit_on_back := true

static func has_animation(value: InventoryItem) -> bool:
	return value != null and value.category in ANIMATED_CATEGORIES

func _ready() -> void:
	if handle_cancel_input:
		_previous_quit_on_back = get_tree().quit_on_go_back
		get_tree().quit_on_go_back = false
		_owns_back_request = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = UiAssets.make_theme()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			get_viewport().set_input_as_handled()
			close())
	add_child(shade)
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	panel = Panel.new()
	panel.size.x = PANEL_WIDTH
	panel.add_theme_stylebox_override("panel", UiAssets.get_style("WINDOW"))
	_canvas.add_child(panel)
	_back = Button.new()
	_back.icon = MenuAssets.icon("EXIT")
	_back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		_back.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_canvas.add_child(_back)
	_back.pressed.connect(close)
	var model := DungeonInventory.new()
	model.collect(item)
	_details = InventoryUI.new()
	_details.toolbar_enabled = false
	_details.setup(model)
	add_child(_details)
	_details.hide()
	_details.set_process_input(false)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_content)
	_info = _details.build_item_info(_content, item, PANEL_WIDTH, 20)
	Catalog.add_type_icon(_content, item, Rect2(6, 6, 16, 16))
	_info.text.minimum_size_changed.connect(_queue_layout)
	if has_animation(item):
		if Catalog.is_glyph(item): sandbox = GlyphSandbox.new()
		elif Catalog.is_enchantment(item): sandbox = EnchantmentSandbox.new()
		else:
			match item.category:
				"missile": sandbox = MissileSandbox.new()
				"stone": sandbox = StoneSandbox.new()
				"seed": sandbox = SeedSandbox.new()
				"wand": sandbox = WandSandbox.new()
				"scroll": sandbox = ScrollSandbox.new()
				"potion":
					if item.type_id == "PotionOfSnapFreeze": sandbox = SnapFreezeSandbox.new()
					elif item.type_id == "PotionOfShroudingFog": sandbox = ShroudingFogSandbox.new()
					elif item.type_id in ["PotionOfStormClouds","PotionOfDragonsBreath"]: sandbox = ElementalPotionSandbox.new()
					elif item.type_id in ["PotionOfEarthenArmor","PotionOfCleansing"]: sandbox = ProtectivePotionSandbox.new()
					elif item.type_id in ["PotionOfStamina","PotionOfShielding"]: sandbox = RestorativePotionSandbox.new()
					else: sandbox = PotionSandbox.new()
				_: sandbox = Sandbox.new()
		sandbox.item = item
		# Floating damage stays inside the animation, clear of the text above.
		sandbox.clip_contents = true
		_content.add_child(sandbox)
	else:
		_notice = Label.new()
		_notice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_notice.add_theme_font_size_override("font_size", 6)
		UiAssets.apply_text_outline(_notice)
		_content.add_child(_notice)
	refresh_text()
	get_viewport().size_changed.connect(_queue_layout)
	_layout()
	if sandbox != null: sandbox.set_active(is_visible_in_tree())

func refresh_text() -> void:
	# Match normal equipment inspection, including the current PvP stats.
	_description = Catalog.entry_description(item) if Catalog.is_runic(item) else _details._item_description(item)
	_info.text.text = InventoryUI.ItemText.markup(_description)
	for child in _content.get_children():
		if child is Label and child != _notice: child.text = Catalog.entry_title(item)
	if _notice != null: _notice.text = L10n.text("动画展示正在制作")
	_back.tooltip_text = L10n.text("返回")
	_queue_layout()

func _queue_layout() -> void:
	if _layout_pending or not is_inside_tree(): return
	_layout_pending = true
	_layout.call_deferred()

func _layout() -> void:
	_layout_pending = false
	if _info.is_empty() or not is_inside_tree(): return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var tail_height := ANIMATION_HEIGHT if sandbox != null else 20.0
	var fixed_height := HEADER_HEIGHT + SECTION_GAP + tail_height + BOTTOM_MARGIN
	# Fit the shortest useful window first. Long text scrolls at the same font
	# size instead of making the animation or all text progressively smaller.
	var minimum_height := fixed_height + 12 + CLOSE_HEIGHT
	var zoom := minf(2, minf((safe.size.x - 12) / PANEL_WIDTH, (safe.size.y - 12) / minimum_height))
	var max_panel_height := (safe.size.y - 12) / zoom - CLOSE_HEIGHT
	var measured := ceilf(_info.text.get_content_height())
	if measured <= 0: measured = ceilf(_details._description_height(_description, PANEL_WIDTH - 19))
	var text_height := clampf(measured + 2, 12, maxf(12, max_panel_height - fixed_height))
	panel.size = Vector2(PANEL_WIDTH, fixed_height + text_height)
	_content.size = panel.size
	ScreenLayout.place(_info.scroll, Rect2(6, HEADER_HEIGHT, PANEL_WIDTH - 12, text_height))
	var tail := Rect2(6, HEADER_HEIGHT + text_height + SECTION_GAP, PANEL_WIDTH - 12, tail_height)
	if sandbox != null: ScreenLayout.place(sandbox, tail)
	else: ScreenLayout.place(_notice, tail)
	var extent := panel.size + Vector2(0, CLOSE_HEIGHT)
	_canvas.scale = Vector2.ONE * zoom
	_canvas.position = (safe.position + (safe.size - extent * zoom) / 2 + Vector2(0, CLOSE_HEIGHT * zoom)).floor()
	ScreenLayout.place(_back, Rect2(PANEL_WIDTH - 20, -CLOSE_HEIGHT, 20, CLOSE_HEIGHT))
	var font := UiAssets.get_font_at_scale(zoom * get_viewport().get_final_transform().get_scale().x)
	for child in panel.find_children("*", "Label", true, false): child.add_theme_font_override("font", font)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and sandbox != null:
		sandbox.set_active(is_visible_in_tree())
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and handle_cancel_input and is_visible_in_tree():
		close()

func _input(event: InputEvent) -> void:
	if handle_cancel_input and is_visible_in_tree() and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if is_queued_for_deletion(): return
	if sandbox != null: sandbox.set_active(false)
	hide()
	_restore_back_request()
	closed.emit()
	queue_free()

func _restore_back_request() -> void:
	if not _owns_back_request: return
	_owns_back_request = false
	if get_tree() != null: get_tree().quit_on_go_back = _previous_quit_on_back

func _exit_tree() -> void:
	_restore_back_request()
