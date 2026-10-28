# StatusPane / BuffIndicator / WndInfoBuff adaptation, GPL-3.0-or-later.
class_name DungeonStatusUI
extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")

signal hero_pressed
signal buff_pressed(key: String)

@export_range(1, 4) var preferred_scale: int = 2:
	set(value):
		preferred_scale = clampi(value, 1, 4)
		if is_node_ready(): _layout()
@export var margin: int = 4:
	set(value):
		margin = maxi(0, value)
		if is_node_ready(): _layout()
## Default opens the local buff inspector; hosts may disable and handle the signals.
@export var show_inspector: bool = true
var status: DungeonStatus
var pane: Control
var avatar: TextureRect
var buttons: Dictionary = {}
var all_buffs_visible: bool = true
## Space at the safe area's right edge reserved for a host's top-row controls.
var buff_right_reserved_width: float = 0.0
var pixel_zoom: int = 2
var modal_layer: Control
var modal_panel: PanelContainer
var _modal_key: String = ""
var _hero_modal: bool = false
var _warning: float = 0.0
var _pending: bool = false
var _background: StyleBoxTexture
var _avatar_material: ShaderMaterial
var _click: AudioStreamPlayer
var _modal_height: float = 100
var _modal_body: VBoxContainer
var _modal_column: VBoxContainer
var _modal_desc: RichTextLabel

func setup(model: DungeonStatus) -> void:
	if status != null and status.changed.is_connected(_schedule_refresh): status.changed.disconnect(_schedule_refresh)
	status = model
	if status != null: status.changed.connect(_schedule_refresh)
	if is_node_ready(): _refresh()

## Call after changing a platform/simulated safe area without resizing the window.
func refresh_layout() -> void:
	_layout()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pane = Control.new()
	pane.name = "StatusPane"
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pane)
	pane.draw.connect(_draw_pane)
	avatar = TextureRect.new()
	avatar.name = "Avatar"
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar.position = Vector2(9.5, 8.5)
	avatar.size = Vector2(11, 15)
	_avatar_material = ShaderMaterial.new()
	_avatar_material.shader = preload("res://scripts/status/avatar_tint.gdshader")
	avatar.material = _avatar_material
	pane.add_child(avatar)
	_click = AudioStreamPlayer.new()
	_click.bus = &"SFX"
	_click.stream = preload("res://assets/inventory/click.mp3")
	add_child(_click)
	var portrait_hit := _hit("HeroHit", Rect2(0, 0, 30, 29), _on_hero)
	portrait_hit.tooltip_text = L10n.text("角色状态")
	_hit("HealthHit", Rect2(), _on_hero)
	get_viewport().size_changed.connect(_layout)
	_refresh()

func _hit(label: String, rect: Rect2, callback: Callable) -> BaseButton:
	var button := BaseButton.new()
	button.name = label
	button.focus_mode = Control.FOCUS_NONE
	button.position = rect.position
	button.size = rect.size
	button.pressed.connect(callback)
	pane.add_child(button)
	return button

func _schedule_refresh() -> void:
	if not _pending:
		_pending = true
		_refresh.call_deferred()

func _refresh() -> void:
	_pending = false
	if not is_inside_tree() or pane == null: return
	_layout()
	if status == null:
		pane.hide()
		close_inspector()
		return
	pane.show()
	avatar.texture = StatusAssets.avatar_texture(status.hero_class, status.armor_tier)
	var active: Dictionary = {}
	for buff in status.buffs():
		if buff.icon_id != StatusAssets.NONE: active[buff.key] = buff
	for key in buttons.keys():
		if not active.has(key):
			_fade_out(buttons[key])
			buttons[key].queue_free()
			pane.remove_child(buttons[key])
			buttons.erase(key)
	for key in active:
		if not buttons.has(key):
			var button := StatusBuffButton.new()
			button.name = "Buff_" + key
			button.pressed.connect(_on_buff.bind(key))
			button.button_down.connect(_click.play)
			pane.add_child(button)
			buttons[key] = button
		var button: StatusBuffButton = buttons[key]
		button.buff = active[key]
		button.tooltip_text = button.buff.display_name
	var ordered: Dictionary = {}
	for key in active: ordered[key] = buttons[key]
	buttons = ordered
	_layout_buffs()
	_update_avatar(0)
	pane.queue_redraw()
	if not _modal_key.is_empty():
		if status.find_buff(_modal_key) == null: close_inspector()
		else: show_buff(_modal_key)
	elif _hero_modal: show_hero()

func _layout() -> void:
	if pane == null: return
	var safe := ScreenLayout.safe_rect(get_viewport()).grow(-margin)
	# Keep the original large layout; narrow windows scale the whole pane uniformly.
	var dimensions := Vector2(174, 29)
	pixel_zoom = mini(preferred_scale, ScreenLayout.integer_fit(dimensions, safe.size))
	pane.scale = Vector2.ONE * pixel_zoom
	pane.position = safe.position.round()
	pane.size = dimensions
	_background = UiAssets.get_style("STATUS_PANE_LARGE").duplicate()
	# Remove the native bottom band containing XP and level compartments, without stretching art.
	_background.region_rect.size.y = 29
	avatar.position = (Vector2(9.5, 8.5) * pixel_zoom).floor() / pixel_zoom
	var health_hit: BaseButton = pane.get_node("HealthHit")
	health_hit.position = Vector2(30, 19)
	health_hit.size = Vector2(130, 9)
	_layout_buffs()
	pane.queue_redraw()
	_layout_modal()

func _layout_buffs() -> void:
	if pane == null: return
	var side := StatusAssets.LARGE_SIZE
	var origin := Vector2(31, 0)
	var width := 142.0
	if buff_right_reserved_width > 0:
		var right := ScreenLayout.safe_rect(get_viewport()).end.x - buff_right_reserved_width
		width = clampf((right - pane.position.x) / pixel_zoom - origin.x, 0.0, width)
	var column := 0
	var count := 0
	var last_row: Array[StatusBuffButton] = []
	all_buffs_visible = true
	for key in buttons:
		var button: StatusBuffButton = buttons[key]
		button.pixel_zoom = pixel_zoom
		button.visible = count < 14
		count += 1
		if not button.visible:
			all_buffs_visible = false
			continue
		button.position = origin + Vector2(column * (side + 1), 0)
		button.size = Vector2(side + 1, side)
		button.queue_redraw()
		last_row.append(button)
		column += 1
	if last_row.size() > 1:
		var last: StatusBuffButton = last_row.back()
		var excess: float = last.position.x + last.size.x - 1 - origin.x - width
		if excess > 0:
			var adjustment := excess / (last_row.size() - 1)
			if adjustment >= side * 0.48: adjustment = side * 0.5
			for i in last_row.size():
				var button := last_row[i]
				button.position.x = floorf((button.position.x - adjustment * i) * pixel_zoom) / pixel_zoom
				button.visible = button.position.x + button.size.x <= origin.x + width + 1
				if not button.visible: all_buffs_visible = false
			# Original brings overlapping icons forward in reverse order (leftmost priority).
			last_row.reverse()
			for button in last_row: pane.move_child(button, -1)

func _draw_pane() -> void:
	if status == null or _background == null: return
	pane.draw_style_box(_background, Rect2(0, 0, 160, 29))
	var rect := Rect2(30, 19, 128, 9)
	var fractions := status.bar_fractions()
	var hp_texture := UiAssets.get_texture("HP_LARGE")
	var shield_texture := UiAssets.get_texture("SHIELD_LARGE")
	if fractions.y > 0: pane.draw_texture_rect(shield_texture, Rect2(rect.position, Vector2(rect.size.x * fractions.y, rect.size.y)), false)
	if fractions.x > 0: pane.draw_texture_rect(hp_texture, Rect2(rect.position, Vector2(rect.size.x * fractions.x, rect.size.y)), false)
	if fractions.z > 0:
		var dot_rect := Rect2(rect.position + Vector2(rect.size.x * (fractions.y - fractions.z), 0), Vector2(rect.size.x * fractions.z, rect.size.y))
		pane.draw_texture_rect(hp_texture, dot_rect, false, Color(0, 0, 0, 0.25))
	var text := status.health_text()
	# Handle very large network values while keeping all glyphs inside the HP region.
	var factor := minf(1.0, (rect.size.x - 2) / maxf(1, SpdPixelText.measure(text).x))
	var point := rect.position + Vector2((rect.size.x - SpdPixelText.measure(text).x * factor) / 2, 1)
	point = (point * pixel_zoom).floor() / pixel_zoom
	SpdPixelText.draw(pane, point, text, Color(1, 1, 1, 0.6), factor)

func _process(delta: float) -> void:
	_update_avatar(delta)

func _update_avatar(delta: float) -> void:
	if status == null or _avatar_material == null: return
	var ratio := float(status.health) / status.max_health
	var tint := Color.BLACK
	var strength := 0.0
	if status.health <= 0: strength = 0.5
	elif ratio < 0.334:
		_warning = fmod(_warning + delta * 5 * (0.4 - ratio), 1)
		var phase := _warning * 2 if _warning < 0.5 else (1 - _warning) * 2
		tint = UiPalette.color(Color("660000").lerp(Color("cc0000"), phase))
		strength = 0.5
	_avatar_material.set_shader_parameter("tint_color", tint)
	_avatar_material.set_shader_parameter("strength", strength)

func _fade_out(button: StatusBuffButton) -> void:
	if not button.visible: return
	var ghost := TextureRect.new()
	ghost.texture = StatusAssets.icon_texture(button.buff.icon_id)
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.position = button.position + button.icon_rect().position
	ghost.size = button.icon_rect().size
	ghost.pivot_offset = ghost.size / 2
	ghost.modulate = button.buff.tint
	ghost.modulate.a = 0.6
	pane.add_child(ghost)
	var tween := ghost.create_tween().set_parallel(true)
	tween.tween_property(ghost, "scale", Vector2.ONE * 6, 0.6)
	tween.tween_property(ghost, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(ghost.queue_free)

func _on_hero() -> void:
	_click.play()
	hero_pressed.emit()
	if show_inspector: show_hero()

func _on_buff(key: String) -> void:
	buff_pressed.emit(key)
	if show_inspector: show_buff(key)

func close_inspector() -> void:
	if is_instance_valid(modal_layer):
		remove_child(modal_layer)
		modal_layer.queue_free()
	modal_layer = null
	modal_panel = null
	_modal_body = null
	_modal_column = null
	_modal_desc = null
	_modal_key = ""
	_hero_modal = false

func _make_modal() -> VBoxContainer:
	close_inspector()
	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal_layer)
	modal_layer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: close_inspector())
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.5)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal_layer.add_child(shade)
	modal_panel = PanelContainer.new()
	modal_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_panel.add_theme_stylebox_override("panel", UiAssets.get_style("WINDOW"))
	modal_layer.add_child(modal_panel)
	var column := VBoxContainer.new()
	_modal_column = column
	column.add_theme_constant_override("separation", 4)
	modal_panel.add_child(column)
	return column

func _label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UiAssets.get_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	UiAssets.apply_text_outline(label)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _title(column: VBoxContainer, texture: Texture2D, text: String, tint: Color = Color.WHITE) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	column.add_child(row)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.modulate = tint
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(16, 16)
	row.add_child(icon)
	var title := _label(text, 9, Color("ffff44"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(title)

func _scroll(column: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var body := VBoxContainer.new()
	_modal_body = body
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 3)
	scroll.add_child(body)
	body.minimum_size_changed.connect(func(): _fit_modal_to_content.call_deferred())
	return body

func _fit_modal_to_content() -> void:
	if not is_instance_valid(_modal_body) or not is_instance_valid(_modal_column): return
	var height := 16.0 # Window's two 6px borders plus 4px breathing room.
	for child in _modal_column.get_children():
		if child is ScrollContainer: height += _modal_body.get_combined_minimum_size().y
		else: height += child.get_combined_minimum_size().y
	height += (_modal_column.get_child_count() - 1) * 4
	if not is_equal_approx(_modal_height, height):
		_modal_height = height
		_layout_modal()

func show_buff(key: String) -> void:
	if status == null: return
	var buff := status.find_buff(key)
	if buff == null or buff.icon_id == StatusAssets.NONE: return
	# Refresh live values in place so a server snapshot does not reset reading position.
	if _modal_key == key and is_instance_valid(_modal_desc):
		_modal_desc.text = _description_markup(buff.description)
		_fit_modal_to_content.call_deferred()
		return
	var column := _make_modal()
	_modal_key = key
	_title(column, StatusAssets.icon_texture(buff.icon_id), buff.display_name, buff.tint)
	var body := _scroll(column)
	var desc := RichTextLabel.new()
	_modal_desc = desc
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_override("normal_font", UiAssets.get_font())
	desc.add_theme_font_size_override("normal_font_size", 6)
	desc.add_theme_color_override("default_color", Color.WHITE)
	UiAssets.apply_text_outline(desc)
	desc.text = _description_markup(buff.description)
	body.add_child(desc)
	_modal_height = 16 + 4 + UiAssets.get_font().get_multiline_string_size(buff.description, HORIZONTAL_ALIGNMENT_LEFT, 120, 6, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y + 18
	_layout_modal()

## SPD RenderedTextBlock uses paired underscores for yellow emphasis.
func _description_markup(value: String) -> String:
	var safe := value.replace("[", "[lb]")
	var pattern := RegEx.new()
	pattern.compile("_([^_]+)_")
	return pattern.sub(safe, "[color=#ffff44]$1[/color]", true)

## All visible-status buffs remain reachable here, even when their HUD icons overflow.
func show_hero() -> void:
	if status == null: return
	var column := _make_modal()
	_hero_modal = true
	var hero_index := HeroAssets.HERO_KEYS.find(status.hero_class)
	_title(column, avatar.texture, HeroAssets.HERO_NAMES[hero_index])
	column.add_child(_label(L10n.text("生命 ") + status.health_text(), 8))
	var body := _scroll(column)
	for buff in status.buffs():
		if buff.icon_id == StatusAssets.NONE: continue
		var row := HBoxContainer.new()
		body.add_child(row)
		var icon := TextureRect.new()
		icon.texture = StatusAssets.icon_texture(buff.icon_id)
		icon.modulate = buff.tint
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# Keep native 16px artwork square when the neighboring button makes the row taller.
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.custom_minimum_size = Vector2(16, 16)
		row.add_child(icon)
		var button := Button.new()
		button.text = buff.display_name
		button.custom_minimum_size.y = 20
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_override("font", UiAssets.get_font())
		button.add_theme_font_size_override("font_size", 8)
		UiAssets.apply_button_style(button, "GREY_BUTTON")
		button.pressed.connect(show_buff.bind(buff.key))
		row.add_child(button)
	if body.get_child_count() == 0: body.add_child(_label(L10n.text("当前没有状态效果。"), 6))
	_modal_height = 16 + 16 + 14 + maxf(12, body.get_child_count() * 23)
	_layout_modal()

func _layout_modal() -> void:
	if not is_instance_valid(modal_panel): return
	var safe := ScreenLayout.safe_rect(get_viewport()).grow(-8)
	var zoom := mini(preferred_scale, ScreenLayout.integer_fit(Vector2(134, 100), safe.size))
	modal_panel.scale = Vector2.ONE * zoom
	modal_panel.size = Vector2(134, minf(_modal_height, safe.size.y / zoom))
	modal_panel.position = (safe.position + (safe.size - modal_panel.size * zoom) / 2).floor()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode in [KEY_ESCAPE, KEY_BACK] and modal_layer != null:
		close_inspector()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: close_inspector()
