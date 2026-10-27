# WndInfoMob / HealthBar / BuffIndicator / WndTitledMessage, SPD 4.0.2.
# Read-only inspection of server-filtered information. GPL-3.0-or-later.
extends Control

const L10n = preload("res://scripts/menu/game_locale.gd")
const Text = preload("res://scripts/inventory/item_text.gd")
const Info = preload("res://scripts/ui/dungeon_examine_info.gd")
signal chosen(entry: Dictionary)

var actor_id := -1
var _panel: Panel
var _column: VBoxContainer
var _body: VBoxContainer
var _health: Label
var _health_bar: Control
var _buff_grid: HFlowContainer
var _buff_buttons: Dictionary = {}
var _buffs: Dictionary = {}
var _description: RichTextLabel
var _selected_buff := ""
var _actor_data: Dictionary = {}
var _actor_title := ""
var _actor_texture: Texture2D

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed: close())
	get_viewport().size_changed.connect(_layout)
	hide()

func close() -> void:
	hide()
	actor_id = -1
	_selected_buff = ""
	_actor_data = {}
	if is_instance_valid(_panel):
		remove_child(_panel)
		_panel.queue_free()
	_panel = null
	_buff_buttons.clear()
	_buffs.clear()

func _label(value: String, font_size: int = 6, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UiAssets.get_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	UiAssets.apply_text_outline(label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = value
	return label

func _open(title: String, texture: Texture2D) -> void:
	if is_instance_valid(_panel):
		remove_child(_panel)
		_panel.queue_free()
	_buff_buttons.clear()
	_health = null
	_health_bar = null
	_buff_grid = null
	_selected_buff = ""
	# Explicit window size avoids a scroll bar feeding its minimum width back
	# into the outer container while wrapped text is being laid out.
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", UiAssets.get_style("WINDOW"))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 4)
	_panel.add_child(_column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	_column.add_child(row)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(16, 16)
		row.add_child(icon)
	var name_label := _label("", 9, Color("ffff44"))
	name_label.custom_minimum_size.x = 100
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.text = title
	row.add_child(name_label)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)
	_body.minimum_size_changed.connect(func(): _layout.call_deferred())
	show()
	_layout.call_deferred()

func _text(value: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_override("normal_font", UiAssets.get_font())
	label.add_theme_font_size_override("normal_font_size", 6)
	UiAssets.apply_text_outline(label)
	label.text = Text.markup(value)
	_body.add_child(label)
	return label

func show_text(title: String, texture: Texture2D, description: String) -> void:
	actor_id = -1
	_buffs.clear()
	_open(title, texture)
	_description = _text(description)

func show_choices(entries: Array[Dictionary]) -> void:
	actor_id = -1
	_open(Info.message("scenes.gamescene.choose_examine"), UiAssets.get_texture("TOOLBAR_SEARCH_ICON"))
	_text(Info.message("scenes.gamescene.multiple_examine"))
	for entry in entries:
		var button := Button.new()
		button.text = entry.title
		button.custom_minimum_size.y = 18
		button.add_theme_font_override("font", UiAssets.get_font())
		button.add_theme_font_size_override("font_size", 8)
		button.clip_text = true
		button.tooltip_text = entry.title
		UiAssets.apply_button_style(button)
		button.pressed.connect(_choose.bind(entry))
		_body.add_child(button)

func _choose(entry: Dictionary) -> void:
	close()
	chosen.emit(entry)

func show_actor(data: Dictionary, title: String, texture: Texture2D) -> void:
	_actor_data = data
	_actor_title = title
	_actor_texture = texture
	actor_id = int(data.id)
	_open(title, texture)
	_health = _label("", 8)
	_body.add_child(_health)
	_health_bar = Control.new()
	_health_bar.custom_minimum_size.y = 2
	_health_bar.draw.connect(_draw_health)
	_body.add_child(_health_bar)
	_buff_grid = HFlowContainer.new()
	_buff_grid.add_theme_constant_override("h_separation", 2)
	_buff_grid.add_theme_constant_override("v_separation", 2)
	_body.add_child(_buff_grid)
	_description = _text(Info.actor_description(data))
	update_actor(data)

func update_actor(data: Dictionary) -> void:
	_actor_data = data
	_buffs.clear()
	for value in data.get("buff_info", []):
		var buff := StatusBuff.from_dict(value)
		if buff.icon_id != StatusAssets.NONE: _buffs[buff.key] = buff
	if not _selected_buff.is_empty():
		if _buffs.has(_selected_buff): _description.text = Text.markup(_buffs[_selected_buff].description)
		else: show_actor(data, _actor_title, _actor_texture)
		return
	var vitals := DungeonStatus.new()
	vitals.set_vitals(int(data.hp), int(data.max_hp), int(data.shield))
	_health.text = L10n.text("生命 ") + vitals.health_text()
	_health_bar.queue_redraw()
	for key in _buff_buttons.keys():
		if not _buffs.has(key):
			_buff_grid.remove_child(_buff_buttons[key])
			_buff_buttons[key].queue_free()
			_buff_buttons.erase(key)
	for key in _buffs:
		if not _buff_buttons.has(key):
			var button := StatusBuffButton.new()
			button.custom_minimum_size = Vector2(16, 16)
			button.pressed.connect(_show_buff.bind(key))
			_buff_grid.add_child(button)
			_buff_buttons[key] = button
		var button: StatusBuffButton = _buff_buttons[key]
		button.buff = _buffs[key]
		button.tooltip_text = button.buff.display_name
		button.pixel_zoom = _panel.scale.x
		button.queue_redraw()
	_description.text = Text.markup(Info.actor_description(data))

func _show_buff(key: String) -> void:
	if not _buffs.has(key): return
	var buff: StatusBuff = _buffs[key]
	_open(buff.display_name, StatusAssets.icon_texture(buff.icon_id))
	_selected_buff = key
	# Buff tint is the same server-provided colour used by BuffIndicator.
	var row := _column.get_child(0)
	row.get_child(0).modulate = buff.tint
	_description = _text(buff.description)
	var back := Button.new()
	back.text = L10n.text("返回")
	back.add_theme_font_size_override("font_size", 8)
	back.add_theme_font_override("font", UiAssets.get_font())
	back.custom_minimum_size.y = 18
	UiAssets.apply_button_style(back)
	back.pressed.connect(func(): show_actor(_actor_data, _actor_title, _actor_texture))
	_body.add_child(back)

func _draw_health() -> void:
	if _actor_data.is_empty(): return
	var hp := maxi(0, int(_actor_data.hp))
	var shield := maxi(0, int(_actor_data.shield))
	var maximum := float(maxi(1, maxi(int(_actor_data.max_hp), hp + shield)))
	var width := _health_bar.size.x
	_health_bar.draw_rect(Rect2(0, 0, width, 2), Color("aa0000"))
	_health_bar.draw_rect(Rect2(0, 0, ceilf(width * (hp + shield) / maximum), 2), Color.WHITE)
	_health_bar.draw_rect(Rect2(0, 0, ceilf(width * hp / maximum), 2), Color("00ee00"))

func _layout() -> void:
	if not visible or not is_instance_valid(_panel): return
	var safe := ScreenLayout.safe_rect(get_viewport()).grow(-8)
	var factor := minf(2, safe.size.x / 134)
	_panel.scale = Vector2.ONE * factor
	var title_height: float = (_column.get_child(0) as Control).get_combined_minimum_size().y
	var content_height: float = 18 + title_height + _body.get_combined_minimum_size().y
	_panel.size = Vector2(134, minf(maxf(42, content_height), safe.size.y / factor))
	_column.position = Vector2(6, 6)
	_column.size = _panel.size - Vector2(12, 12)
	_panel.position = (safe.position + (safe.size - _panel.size * factor) / 2).floor()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_BACK]:
		close()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible: close()
