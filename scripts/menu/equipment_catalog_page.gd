# SPD 4.0.2 WndJournal.CatalogTab / ScrollingGridPane, GPL-3.0-or-later.
# Equipment and potion groups with per-item journal preview navigation.
extends Control
signal item_requested(type_id: String)
const Catalog = preload("res://scripts/menu/equipment_catalog.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const ITEM_SIZE := 17.0
const ITEM_STEP := 18.0
var _scroll: ScrollContainer
var _content: Control
var _groups: Array[Dictionary] = []
var _layout_pending := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll = ScrollContainer.new()
	_scroll.name = "EquipmentScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 6
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_scroll)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_content.resized.connect(_queue_layout)
	resized.connect(_queue_layout)
	for index in Catalog.CATEGORIES.size():
		var title := Label.new()
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title.add_theme_font_size_override("font_size", 7)
		title.add_theme_color_override("font_color", Color("ffff44"))
		UiAssets.apply_text_outline(title)
		_content.add_child(title)
		var tiles: Array[Control] = []
		for type_id in Catalog.types(Catalog.CATEGORIES[index]):
			var item := Catalog.create(type_id)
			var tile := Button.new()
			tile.name = type_id
			var background := StyleBoxFlat.new()
			background.bg_color = Color(0.325, 0.337, 0.302, 0.6)
			for state in ["normal", "hover", "pressed", "focus"]:
				tile.add_theme_stylebox_override(state, background)
			tile.mouse_filter = Control.MOUSE_FILTER_PASS
			tile.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			tile.pressed.connect(func(): item_requested.emit(type_id))
			tile.set_meta("type_id", type_id)
			_content.add_child(tile)
			var icon := TextureRect.new()
			icon.texture = ItemAssets.get_texture(item.visual)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			tile.add_child(icon)
			if Catalog.is_runic(item): ItemGlow.apply(icon,item)
			Catalog.add_type_icon(tile, item, Rect2(0, 0, ITEM_SIZE, ITEM_SIZE))
			tiles.append(tile)
		_groups.append({"title":title, "tiles":tiles})
	refresh_text()
	_queue_layout()

func refresh_text() -> void:
	for index in _groups.size():
		_groups[index].title.text = "%s (%d)" % [L10n.text(Catalog.TITLES[index]), _groups[index].tiles.size()]
	_queue_layout()

func _queue_layout() -> void:
	if _layout_pending or not is_inside_tree(): return
	_layout_pending = true
	_layout_content.call_deferred()

func _layout_content() -> void:
	_layout_pending = false
	if not is_instance_valid(_content): return
	var width := maxf(ITEM_SIZE, _content.size.x - 2)
	var columns := maxi(1, floori((width + 1) / ITEM_STEP))
	var top := 0.0
	for group in _groups:
		var title: Label = group.title
		var height := ceilf(title.get_minimum_size().y) + 3
		ScreenLayout.place(title, Rect2(1, top + 1, width, height - 2))
		top += height
		var tiles: Array = group.tiles
		for index in tiles.size():
			ScreenLayout.place(tiles[index], Rect2(1 + (index % columns) * ITEM_STEP, top + floori(float(index) / columns) * ITEM_STEP, ITEM_SIZE, ITEM_SIZE))
		top += ceili(float(tiles.size()) / columns) * ITEM_STEP + 5
	_content.custom_minimum_size.y = ceilf(top)
