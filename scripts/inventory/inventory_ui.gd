# WndBag / WndUseItem / WndQuickBag / RightClickMenu / QuickSlotButton port.
# All dimensions below are upstream UI pixels; scale 2 at the 360x640 viewport.
# GPL-3.0-or-later; see LICENSE-SPD.txt.
class_name InventoryUI
extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")
const ItemText = preload("res://scripts/inventory/item_text.gd")
const Glow = preload("res://scripts/items/item_glow.gd")
const NativeRichText = preload("res://scripts/ui/native_rich_text.gd")
const ArmorStats = preload("res://scripts/combat/armor_rules.gd")

signal item_selected(item: InventoryItem)
signal bag_opened
signal bag_closed

const PLACEHOLDERS = ["WEAPON_HOLDER", "ARMOR_HOLDER", "ARTIFACT_HOLDER", "SOMETHING", "RING_HOLDER"]
const TITLE_COLOR := Color("ffff44")
# IconTitle.FONT_SIZE and WndInfoItem's renderTextBlock size in SPD.
const ITEM_TITLE_FONT_SIZE := 9
const ITEM_DESCRIPTION_FONT_SIZE := 6
var inventory: DungeonInventory
var last_bag: InventoryBag
var current_bag: InventoryBag
var bag_layer: Control
var bag_panel: Panel
var detail_layer: Control
var detail_panel: Panel
var toolbar: Control
## Native toolbar pixels reserved at the left for the PvP wait control.
var toolbar_leading_width := 0.0
var bag_button: Button
var slots: Array[InventorySlot] = []
var quick_buttons: Array[InventorySlot] = []
var selector: Callable
var selection_callback: Callable
var selection_prompt: String = ""
var hide_after_select: bool = true
var _quick_bag: bool = false
var _refresh_pending: bool = false
var _detail_item: InventoryItem
var _font: Font
var _note_edit: TextEdit
var _detail_cancel: Callable
var toolbar_enabled := true

func setup(model: DungeonInventory) -> void:
	if inventory != null and inventory.changed.is_connected(_schedule_refresh):
		inventory.changed.disconnect(_schedule_refresh)
		inventory.choice_requested.disconnect(_choose_potion)
	inventory = model
	last_bag = model.backpack
	model.changed.connect(_schedule_refresh)
	model.choice_requested.connect(_choose_potion)
	if is_node_ready(): _refresh()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = UiAssets.get_font()
	get_viewport().size_changed.connect(_layout)
	_build_toolbar()
	_layout()

func _schedule_refresh() -> void:
	if not _refresh_pending:
		_refresh_pending = true
		_refresh.call_deferred()

func _refresh() -> void:
	_refresh_pending = false
	if not is_inside_tree() or inventory == null: return
	_build_toolbar()
	if bag_layer != null:
		if current_bag == null or not inventory.bags().has(current_bag): current_bag = inventory.backpack
		_build_bag()
	if _detail_item != null and not inventory.contains(_detail_item): _close_detail()
	if detail_layer != null: move_child(detail_layer, -1)
	_layout()

func _clear(node: Node) -> void:
	if is_instance_valid(node):
		remove_child(node)
		node.queue_free()

func _layer(dim: bool = true) -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	if dim:
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.45)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(shade)
	return layer

func _panel(parent: Control, dimensions: Vector2, style: String = "WINDOW") -> Panel:
	var panel := Panel.new()
	panel.size = dimensions
	panel.add_theme_stylebox_override("panel", UiAssets.get_style(style))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(panel)
	return panel

func _label(parent: Control, text: String, rect: Rect2, font_size: int = 8, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	UiAssets.apply_text_outline(label)
	label.clip_text = true
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.position = rect.position
	label.size = rect.size
	return label

func _button(parent: Control, text: String, rect: Rect2, callback: Callable, style: String = "ORANGE_BUTTON") -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 8)
	UiAssets.apply_button_style(button, style)
	button.pressed.connect(callback)
	parent.add_child(button)
	# Resolve the small font and inherited theme before assigning the final size.
	# A size clamped by the default font does not shrink after changing fonts.
	var padding := floorf(maxf(0, (rect.size.y - _font.get_height(8)) / 2))
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var box: StyleBox = button.get_theme_stylebox(state)
		box.set_content_margin(SIDE_TOP, minf(box.get_content_margin(SIDE_TOP), padding))
		box.set_content_margin(SIDE_BOTTOM, minf(box.get_content_margin(SIDE_BOTTOM), padding))
	button.position = rect.position
	button.size = rect.size
	return button

func _texture(parent: Control, texture: Texture2D, rect: Rect2, native_size: bool = false) -> TextureRect:
	var view := TextureRect.new()
	view.texture = texture
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED if native_size else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.position = rect.position
	view.size = rect.size
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(view)
	return view

func _item_texture(parent: Control, item: InventoryItem, rect: Rect2, native_size: bool = false) -> void:
	var view := _texture(parent, ItemAssets.get_texture(item.visual), rect, native_size)
	Glow.apply(view, item)

func _slot(parent: Control, item: InventoryItem, rect: Rect2, placeholder: String = "", allow_empty: bool = false) -> InventorySlot:
	var slot := InventorySlot.new()
	slot.inventory = inventory
	slot.item = item
	slot.placeholder_visual = placeholder
	slot.position = rect.position
	slot.size = rect.size
	slot.equipped = inventory.is_equipped(item)
	slot.enabled = inventory.usable(item) or allow_empty
	parent.add_child(slot)
	return slot

func _build_toolbar() -> void:
	_clear(toolbar)
	bag_button = null
	toolbar = Control.new()
	toolbar.visible = toolbar_enabled
	toolbar.size = Vector2(144, 24)
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toolbar)
	quick_buttons.clear()
	if inventory == null: return
	for i in 6:
		var bg := TextureRect.new()
		bg.texture = UiAssets.get_texture("QUICKSLOT_LEFT" if i == 0 else ("QUICKSLOT_RIGHT" if i == 5 else "QUICKSLOT_MIDDLE"))
		bg.position = Vector2(i * 20, 0)
		bg.size = Vector2(20, 24)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toolbar.add_child(bg)
		var item: InventoryItem = inventory.quickslots[i]
		var slot := _slot(toolbar, item, Rect2(i * 20 + 1, 1, 18, 22), "", true)
		slot.quick = true
		# SPD keeps identified item icons visible in quickslots, beside the quantity.
		slot.show_extra = item != null and item.category in ["potion", "scroll"]
		slot.clicked.connect(_use_quickslot.bind(i))
		slot.long_clicked.connect(_select_quickslot.bind(i))
		slot.right_clicked.connect(_select_quickslot.bind(i))
		quick_buttons.append(slot)
		if item != null and item.quantity == 0:
			slot.modulate.a = 0.3
	bag_button = _button(toolbar, "", Rect2(123, 0, 21, 24), toggle_bag, "GREY_BUTTON")
	_texture(bag_button, _bag_icon(inventory.backpack), Rect2(5, 7, 10, 10))
	bag_button.tooltip_text = L10n.text("背包 (I/B) · 长按物品放入快捷栏")

func play_pickup_sound(dew: bool = false) -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var player := AudioStreamPlayer.new()
	player.bus = &"SFX"
	player.stream = load("res://assets/inventory/dewdrop.mp3" if dew else "res://assets/inventory/item.mp3")
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

# SPD Toolbar.PickedUpItem: 0.5s linear flight with sqrt(remaining) scale.
# It lives in the HUD canvas, so fog cannot obscure its flight into the backpack.
func animate_pickup(item: InventoryItem, screen_origin: Vector2, map_scale: Vector2) -> void:
	if not is_instance_valid(bag_button) or not toolbar.visible: return
	var texture := ItemAssets.get_texture(item.visual)
	if texture == null: return
	var icon := Sprite2D.new()
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.z_index = 100
	add_child(icon)
	Glow.apply(icon, item)
	_pickup_frame(0.0, icon, screen_origin, map_scale)
	var flight := create_tween()
	flight.tween_method(_pickup_frame.bind(icon, screen_origin, map_scale), 0.0, 1.0, 0.5)
	flight.tween_callback(icon.queue_free)

func _pickup_frame(progress: float, icon: Sprite2D, screen_origin: Vector2, map_scale: Vector2) -> void:
	if not is_instance_valid(bag_button): icon.hide(); return
	var hud_transform := get_global_transform_with_canvas()
	var from := hud_transform.affine_inverse() * screen_origin
	var to := hud_transform.affine_inverse() * (bag_button.get_global_transform_with_canvas() * (bag_button.size / 2.0))
	icon.position = from.lerp(to, progress)
	icon.scale = map_scale / hud_transform.get_scale().abs() * sqrt(maxf(0.0, 1.0 - progress))

func toggle_bag() -> void:
	if bag_layer != null: close_bag()
	else: open_bag()

func open_bag(bag: InventoryBag = null) -> void:
	if inventory == null: return
	_close_detail()
	_quick_bag = false
	if bag == null:
		bag = last_bag if inventory.bags().has(last_bag) else inventory.backpack
	current_bag = bag
	last_bag = bag
	_build_bag()
	bag_opened.emit()

func select_item(prompt: String, predicate: Callable, callback: Callable = Callable(), preferred_kind: String = "", hide_after: bool = true) -> void:
	selector = predicate
	selection_callback = callback
	selection_prompt = prompt
	hide_after_select = hide_after
	var preferred: InventoryBag
	for bag in inventory.bags():
		if bag.kind == preferred_kind: preferred = bag
	if not preferred_kind.is_empty() and preferred == null: preferred = inventory.backpack
	open_bag(preferred)

func _end_selection(item: InventoryItem) -> void:
	var callback := selection_callback
	selector = Callable()
	selection_callback = Callable()
	selection_prompt = ""
	if callback.is_valid(): callback.call(item)
	item_selected.emit(item)

func close_bag(cancel_selection: bool = true) -> void:
	_close_detail()
	_clear(bag_layer)
	bag_layer = null
	bag_panel = null
	slots.clear()
	if cancel_selection and selector.is_valid(): _end_selection(null)
	bag_closed.emit()

func _bag_icon(bag: InventoryBag) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = load("res://assets/ui/source/icons.png")
	texture.region = Rect2(InventoryBag.DEFINITIONS[bag.kind][2], 80, 10, 10)
	return texture

func _build_bag() -> void:
	_clear(bag_layer)
	bag_layer = _layer()
	bag_layer.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_bag())
	slots.clear()
	if _quick_bag:
		_build_quick_bag()
		return
	bag_panel = _panel(bag_layer, Vector2(156, 178))
	_label(bag_panel, selection_prompt if selector.is_valid() else current_bag.display_name(), Rect2(7, 6, 142, 13), 8, TITLE_COLOR)
	var entries: Array[InventoryItem] = []
	for equipment_slot in DungeonInventory.EQUIPMENT_SLOTS:
		entries.append(inventory.equipment[equipment_slot])
	if current_bag != inventory.backpack:
		entries.append(current_bag)
	for item in current_bag.items:
		if not item is InventoryBag: entries.append(item)
	while entries.size() < 25: entries.append(null)
	var extra_height := maxi(0, ceili(entries.size() / 5.0) - 5) * 29
	bag_panel.size.y += extra_height
	for i in entries.size():
		var item := entries[i]
		var placeholder: String = PLACEHOLDERS[i] if i < 5 and item == null else ""
		var slot := _slot(bag_panel, item, Rect2(6 + (i % 5) * 29, 20 + int(i / 5) * 29, 28, 28), placeholder)
		if selector.is_valid() and item != null: slot.enabled = slot.enabled and bool(selector.call(item))
		slot.clicked.connect(_click_item.bind(item))
		slot.right_clicked.connect(_right_click_item.bind(item, slot))
		slot.long_clicked.connect(_long_click_item.bind(item))
		slots.append(slot)
	var all_bags := inventory.bags()
	var tab_width := minf(28, 144.0 / all_bags.size())
	for i in all_bags.size():
		var bag := all_bags[i]
		var tab := _button(bag_panel, "", Rect2(6 + i * (tab_width + 1), 165 + extra_height, tab_width, 20), _switch_bag.bind(bag), "TAB_SELECTED" if bag == current_bag else "TAB_UNSELECTED")
		_texture(tab, _bag_icon(bag), Rect2((tab_width - 10) / 2, 5, 10, 10))
		tab.tooltip_text = bag.display_name()
	_layout()

func _switch_bag(bag: InventoryBag) -> void:
	current_bag = bag
	last_bag = bag
	_close_detail()
	_build_bag()

func _click_item(item: InventoryItem) -> void:
	if not inventory.usable(item): return
	if selector.is_valid() and not bool(selector.call(item)): return
	if _quick_bag:
		close_bag(false)
		_run_action(item, inventory.default_action(item))
	elif selector.is_valid():
		if hide_after_select:
			close_bag(false)
			_end_selection(item)
		else:
			if selection_callback.is_valid(): selection_callback.call(item)
			item_selected.emit(item)
	else:
		show_item(item)

func _long_click_item(item: InventoryItem) -> void:
	if not inventory.usable(item): return
	if selector.is_valid() or _quick_bag:
		show_item(item, selector.is_valid())
	elif not item.default_action.is_empty():
		close_bag()
		inventory.auto_quickslot(item)
		inventory.message.emit(L10n.text("已将%s放入快捷栏") % item.display_name())

func _right_click_item(item: InventoryItem, slot: Control) -> void:
	if selector.is_valid():
		_click_item(item)
	else:
		show_item(item, false, true, slot.get_global_mouse_position())

func _close_detail() -> void:
	_clear(detail_layer)
	detail_layer = null
	detail_panel = null
	_detail_item = null
	_detail_cancel = Callable()

func _cancel_detail() -> void:
	var callback := _detail_cancel
	_close_detail()
	if callback.is_valid(): callback.call()

## WndUpgrade: known-item preview, source 120px content and 16px buttons.
func show_upgrade_preview(scroll: InventoryItem, target: InventoryItem, confirm: Callable, back: Callable) -> void:
	_close_detail(); _detail_cancel = back
	detail_layer = _layer()
	detail_layer.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _cancel_detail())
	detail_panel = _panel(detail_layer, Vector2(132, 136))
	_item_texture(detail_panel, scroll, Rect2(6, 6, 16, 16), true)
	_label(detail_panel, L10n.text("升级一件物品"), Rect2(25, 6, 100, 16), ITEM_TITLE_FONT_SIZE, TITLE_COLOR)
	_label(detail_panel, L10n.text("确认升级？剩余卷轴：%d") % scroll.quantity, Rect2(6, 24, 120, 12), 6)
	var current := target.copy_item(); current.charges = -1; current.quantity = 1
	var upgraded := current.copy_item(); upgraded.level += 1
	if target.category == "wand" and int(target.metadata.wand_state.resin) > 0: upgraded.level -= 1
	for spec in [[current, 72], [upgraded, 102]]:
		var slot := InventorySlot.new(); slot.item = spec[0]; slot.show_extra = false
		slot.position = Vector2(spec[1], 39); slot.size = Vector2(18, 18); slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail_panel.add_child(slot); slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows: Array = [[L10n.text("等级"), "%+d" % target.level, "%+d" % upgraded.level]]
	if target.category == "wand":
		var level_from := WandState.level(target)
		var level_to := level_from + (0 if int(target.metadata.wand_state.resin) > 0 else 1)
		var damage := WandState.damage_range(target.type_id, level_from, WandState.cost(target))
		var new_damage := WandState.damage_range(target.type_id, level_to, WandState.cost(target))
		if damage != Vector2i.ZERO: rows.append([L10n.text("伤害"), str(damage.x) if damage.x == damage.y else "%d~%d" % [damage.x, damage.y], str(new_damage.x) if new_damage.x == new_damage.y else "%d~%d" % [new_damage.x, new_damage.y]])
		rows.append([L10n.text("充能上限"), str(target.max_charges), str(mini(10, target.max_charges + (0 if int(target.metadata.wand_state.resin) > 0 else 1)))])
	var bottom := 60
	for row in rows:
		for i in 3:
			var label := _label(detail_panel, row[i], Rect2(6 if i == 0 else 66 if i == 1 else 96, bottom, 60 if i == 0 else 30, 10), 6)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bottom += 11
	if target.cursed:
		_label(detail_panel, L10n.text("升级可弱化或清除诅咒。"), Rect2(6, bottom, 120, 12), 6, Color("44ff44")); bottom += 13
	for x in [66, 96]:
		var line := ColorRect.new(); line.color = Color("222222"); line.position = Vector2(x, 37); line.size = Vector2(1, bottom - 37); line.mouse_filter = Control.MOUSE_FILTER_IGNORE; detail_panel.add_child(line)
	bottom += 4
	_button(detail_panel, L10n.text("升级"), Rect2(6, bottom, 59, 16), confirm)
	_button(detail_panel, L10n.text("返回"), Rect2(66, bottom, 60, 16), _cancel_detail)
	detail_panel.size.y = bottom + 22
	_layout()

## WndOptions-sized item dialog, shared by projectile warning and dart preparation.
func show_options(item: InventoryItem, message: String, options: Array, chosen: Callable) -> void:
	_close_detail(); _detail_cancel = func(): chosen.call(-1)
	detail_layer = _layer()
	detail_layer.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _cancel_detail())
	var height := clampf(_font.get_multiline_string_size(message, HORIZONTAL_ALIGNMENT_LEFT, 120, ITEM_DESCRIPTION_FONT_SIZE).y + 6, 18, 100)
	detail_panel = _panel(detail_layer, Vector2(132, 40 + height + options.size() * 18))
	_item_texture(detail_panel, item, Rect2(6, 6, 16, 16), true)
	_label(detail_panel, item.display_name(), Rect2(25, 6, 100, 16), ITEM_TITLE_FONT_SIZE, TITLE_COLOR)
	var scroll := ScrollContainer.new(); scroll.position = Vector2(6, 28); scroll.size = Vector2(120, height); scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; detail_panel.add_child(scroll)
	var label := Label.new(); label.text = message; label.custom_minimum_size.x = 114; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.add_theme_font_size_override("font_size", ITEM_DESCRIPTION_FONT_SIZE); UiAssets.apply_text_outline(label); scroll.add_child(label)
	for i in options.size():
		_button(detail_panel, options[i], Rect2(6, 32 + height + 18 * i, 120, 16), func(): _close_detail(); chosen.call(i))
	_layout()

func _item_magic_description(item: InventoryItem) -> String:
	if item.category == "weapon" and item.metadata.get("enchantment") == "crystal":
		return L10n.text("魔晶附魔：命中时追加魔法伤害。武器在命中5次后碎裂，剩余_%d_次；未命中不消耗，不会自行修复。") % clampi(int(item.metadata.get("crystal_uses_left",5)),0,5)
	if item.category == "missile" and item.metadata.get("enchantment") == "crystal": return L10n.text("水晶附魔：命中时追加水晶伤害。")
	var armor := item.category == "armor"
	var prefix := "glyph" if armor else "enchantment"
	var family := "items.armor.armor." if armor else "items.weapon.weapon."
	var hardened := bool(item.metadata.get(prefix + "_hardened", false))
	if item.metadata.has(prefix) and item.metadata.has(prefix + "_description"):
		var name := L10n.gear_text("armor" if armor else "weapon", str(item.metadata[prefix]), "name", str(item.metadata.get(prefix + "_name", "")))
		var generic := L10n.english_message("items.item.curse") if bool(item.metadata.get(prefix + "_curse", false)) else L10n.english_message("items.armor.armor$glyph.glyph" if armor else "items.weapon.weapon$enchantment.enchant")
		name = name.replace("%s", generic if L10n.is_english() else "").strip_edges()
		var text := ItemText.message(family + ("inscribed" if armor else "enchanted"), [name])
		if hardened: text += " " + ItemText.message(family + ("glyph_hardened" if armor else "enchant_hardened"))
		return text + " " + L10n.text(str(item.metadata[prefix + "_description"]))
	if hardened: return ItemText.message(family + ("hardened_no_glyph" if armor else "hardened_no_enchant"))
	return ""

func _item_curse_description(item: InventoryItem) -> String:
	if not item.cursed: return ""
	var worn := inventory.is_equipped(item)
	match item.category:
		"weapon", "missile": return ItemText.message("items.weapon.weapon." + ("cursed_worn" if worn and item.category == "weapon" else "cursed"))
		"armor": return ItemText.message("items.armor.armor." + ("cursed_worn" if worn else "cursed"))
		"ring": return ItemText.message("items.rings.ring." + ("cursed_worn" if worn else "curse_known"))
		"wand": return ItemText.message("items.wands.wand.cursed")
	return L10n.text("被诅咒")

## Match the original known-item info branches, using live presentation state.
## The PvP omissions (strength requirements, identification and Duelist skills)
## are deliberate and never restored by the original translation templates.
func _item_description(item: InventoryItem) -> String:
	var description := L10n.item_description(item.type_id, item.description)
	if item.type_id == "RingOfSharpshooting": description = L10n.text("提升投掷武器的有效伤害等级。投掷物命中后消耗，不提供耐久加成。")
	var actor := inventory.ring_actor
	var magic := _item_magic_description(item) if item.category in ["weapon", "missile", "armor"] else ""
	var curse := _item_curse_description(item)
	if MissileRules.is_weapon(item):
		return MissileRules.stats(item, actor, false, magic)
	elif MeleeRules.is_weapon(item):
		description += "\n\n" + MeleeRules.stats(item, actor, magic, curse)
	elif item.category == "armor":
		var augmentation := str(item.metadata.get("augment", "none"))
		description += "\n\n" + ArmorStats.stats(item, actor)
		if augmentation in ["evasion", "defense"]: description += " " + ItemText.message("items.armor.armor." + augmentation)
		if not magic.is_empty(): description += "\n\n" + magic
		if not curse.is_empty(): description += "\n\n" + curse
	elif item.type_id in WandState.TYPES:
		description += "\n\n" + WandState.stats(item, actor.max_hp if actor != null else 50, actor)
		var resin := int(item.metadata.get("wand_state", {}).get("resin", 0))
		if resin > 0: description += "\n\n" + ItemText.message("items.wands.wand." + ("resin_one" if resin == 1 else "resin_many"), [resin])
		if not curse.is_empty(): description += "\n\n" + curse
		if actor != null and actor.data.get("battlemage", false): description += "\n\n" + ItemText.for_item(item.type_id, "bmage_desc")
	elif item.type_id in RingRules.TYPES:
		if not curse.is_empty(): description += "\n\n" + curse
		description += "\n\n" + inventory.ring_stats(item)
	elif not curse.is_empty():
		description += "\n\n" + curse
	if item.type_id == "StoneOfIntuition" and int(item.metadata.get("intuition_uses", 0)) > 0: description += L10n.text("\n\n这颗符石已使用过一次，下次使用后将会碎裂。")
	if item.level != 0: description += L10n.text("\n升级等级：%+d") % item.level
	if not item.note.is_empty(): description += L10n.text("\n\n记录：") + item.note
	return description

func _description_height(description: String, width: float) -> float:
	# The body is drawn by NativeRichText with the native raster font. Measuring
	# it with _font generates unused MSDF glyphs for every Chinese character,
	# blocking the first item open for over a second on desktop (more on mobile).
	return UiAssets.get_native_ui_font().get_multiline_string_size(ItemText.plain(description), HORIZONTAL_ALIGNMENT_LEFT, width, ITEM_DESCRIPTION_FONT_SIZE).y

## Shared WndInfoItem content for inventory dialogs and journal previews.
## The caller owns sizing/navigation; this never adds inventory actions.
func build_item_info(parent: Control, item: InventoryItem, width: float, body_height: float,
		info_only: bool = true, context_menu: bool = false) -> Dictionary:
	_item_texture(parent, item, Rect2(6, 6, 16, 16), true)
	var title := _label(parent, item.display_name(), Rect2(25, 6, width - (31 if info_only else 45), 16), ITEM_TITLE_FONT_SIZE, TITLE_COLOR)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not info_only:
		_button(parent, "≡", Rect2(width - 20, 6, 14, 16), _show_notes.bind(item), "GREY_BUTTON_TR").tooltip_text = L10n.text("物品记录")
	if context_menu: return {}
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, 28)
	scroll.size = Vector2(width - 12, body_height - 2)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var text := NativeRichText.new()
	text.custom_minimum_size.x = width - 19
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.font_size = ITEM_DESCRIPTION_FONT_SIZE
	text.text = ItemText.markup(_item_description(item))
	scroll.add_child(text)
	return {"text":text, "scroll":scroll}

func show_item(item: InventoryItem, info_only: bool = false, context_menu: bool = false, at: Vector2 = Vector2.ZERO) -> void:
	if item == null: return
	_close_detail()
	_detail_item = item
	detail_layer = _layer(not context_menu)
	detail_layer.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: _close_detail())
	var available := inventory.actions(item) if not info_only else []
	var default_action := inventory.default_action(item)
	if context_menu and available.has(default_action):
		available.erase(default_action)
		available.push_front(default_action)
	var width := 90.0 if context_menu else 132.0
	var description := _item_description(item)
	var body_height := 0.0 if context_menu else clampf(_description_height(description, width - 21) + 8, 18, 130)
	detail_panel = _panel(detail_layer, Vector2(width, 32 + body_height))
	var info := build_item_info(detail_panel, item, width, body_height, info_only, context_menu)
	var description_view: NativeRichText
	var description_scroll: ScrollContainer
	if not context_menu:
		description_view = info.text
		description_scroll = info.scroll
	var buttons: Array[Button] = []
	for action in available:
		var button := _button(detail_panel, InventoryCatalog.action_label(item, action), Rect2(6, 28 + body_height, 1, 16), _run_action.bind(item, action))
		if action == default_action: button.add_theme_color_override("font_color", TITLE_COLOR)
		buttons.append(button)
	var bottom := _layout_action_buttons(buttons, width - 12, 28 + body_height, context_menu)
	detail_panel.size.y = maxf(32 + body_height, bottom + 6)
	_layout()
	if not context_menu:
		description_view.minimum_size_changed.connect(_fit_item_text.bind(description_view, description_scroll, buttons), CONNECT_DEFERRED)
		_fit_item_text.call_deferred(description_view, description_scroll, buttons)
	if context_menu:
		var safe := ScreenLayout.safe_rect(get_viewport())
		detail_panel.position = (at - Vector2(6, 6)).clamp(safe.position, (safe.end - detail_panel.size * detail_panel.scale).max(safe.position))

func _fit_item_text(text: NativeRichText, scroll: ScrollContainer, buttons: Array[Button]) -> void:
	if not is_instance_valid(text) or not is_instance_valid(detail_panel): return
	if not detail_panel.is_ancestor_of(text): return
	var height := clampf(text.get_content_height() + 8, 18, 130)
	if is_equal_approx(scroll.size.y, height - 2): return
	scroll.size.y = height - 2
	var bottom := _layout_action_buttons(buttons, detail_panel.size.x - 12, 28 + height, false)
	detail_panel.size.y = maxf(32 + height, bottom + 6)
	_layout()

func _layout_action_buttons(buttons: Array[Button], content_width: float, y: float, context_menu: bool) -> float:
	var index := 0
	while index < buttons.size():
		var row: Array[Button] = []
		var used_width := 0.0
		var height := 16.0
		while index < buttons.size() and row.size() < (1 if context_menu else 3):
			var button := buttons[index]
			# Very long custom action names must still fit a single-row menu.
			if button.get_combined_minimum_size().x > content_width:
				button.clip_text = true
				button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				button.tooltip_text = button.text
			var minimum := button.get_combined_minimum_size()
			var required_width := ceilf(minimum.x)
			if not row.is_empty() and used_width + 1 + required_width > content_width: break
			if not row.is_empty(): used_width += 1
			used_width += required_width
			height = maxf(height, ceilf(minimum.y))
			row.append(button)
			index += 1
		var remaining := maxf(0, content_width - used_width)
		var x := 6.0
		for i in row.size():
			var button := row[i]
			var extra := floorf(remaining / (row.size() - i))
			remaining -= extra
			var width := ceilf(button.get_combined_minimum_size().x) + extra
			button.position = Vector2(x, y)
			button.size = Vector2(width, height)
			x += width + 1
		y += height + 1
	return y - 1 if not buttons.is_empty() else y

func _run_action(item: InventoryItem, action: String) -> void:
	close_bag()
	if not inventory.usable(item): return
	if action == "OPEN" and item is InventoryBag:
		open_quick_bag(item)
	elif action == "EQUIP" and inventory.equipment_options(item).size() > 1:
		if inventory.equipment_needs_choice(item):
			_choose_equipment(item, inventory.replacement_options(item))
		else: inventory.equip(item)
	else:
		if item.category == "potion" and ((action == "DRINK" and inventory.default_action(item) == "THROW") or (action == "THROW" and inventory.default_action(item) == "DRINK")):
			_confirm_potion(item, action)
		else: inventory.execute(item, action)

func _confirm_potion(item: InventoryItem, action: String) -> void:
	_close_detail()
	_detail_item = item
	detail_layer = _layer()
	detail_panel = _panel(detail_layer, Vector2(132, 80))
	_label(detail_panel, L10n.text("确认使用药剂"), Rect2(6, 6, 120, 14), 8, TITLE_COLOR)
	var text := _label(detail_panel, L10n.text("确定饮用有害药剂？") if action == "DRINK" else L10n.text("确定扔出有益药剂？"), Rect2(6, 25, 120, 20), 8)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(detail_panel, L10n.text("是"), Rect2(6, 54, 59, 18), func(): _close_detail(); inventory.execute(item, action))
	_button(detail_panel, L10n.text("否"), Rect2(66, 54, 60, 18), _close_detail)
	_layout()

func _choose_potion(item: InventoryItem) -> void:
	_close_detail()
	_detail_item = item
	detail_layer = _layer()
	detail_layer.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			detail_layer.accept_event()
			_cancel_detail())
	detail_panel = _panel(detail_layer, Vector2(132, 94))
	_label(detail_panel, item.display_name(), Rect2(6, 6, 120, 16), ITEM_TITLE_FONT_SIZE, TITLE_COLOR)
	_label(detail_panel, L10n.text("如何使用这瓶药剂？"), Rect2(6, 25, 120, 14))
	_button(detail_panel, L10n.text("饮用"), Rect2(6, 48, 59, 18), func(): _run_action(item, "DRINK"))
	_button(detail_panel, L10n.text("扔出"), Rect2(66, 48, 60, 18), func(): _run_action(item, "THROW"))
	_button(detail_panel, L10n.text("取消"), Rect2(6, 70, 120, 18), _cancel_detail)
	_layout()

func _choose_equipment(item: InventoryItem, options: Array) -> void:
	_close_detail()
	_detail_item = item
	detail_layer = _layer()
	detail_panel = _panel(detail_layer, Vector2(132, 108))
	_label(detail_panel, L10n.text("选择替换的装备"), Rect2(6, 6, 120, 16), 8, TITLE_COLOR)
	for i in 3:
		var slot: String = ["artifact", "misc", "ring"][i]
		var worn: InventoryItem = inventory.equipment[slot]
		var button := _button(detail_panel, worn.display_name() if worn != null else "---", Rect2(6, 29 + i * 23, 120, 20), func():
			_close_detail()
			inventory.equip(item, slot))
		button.disabled = worn == null or not options.has(slot)
	_layout()

func _select_quickslot(index: int) -> void:
	select_item(L10n.text("选择快捷栏物品"), func(item): return not item.default_action.is_empty(), func(item):
		if item != null: inventory.set_quickslot(index, item))

func _use_quickslot(index: int) -> void:
	var item := inventory.quickslots[index]
	if not inventory.usable(item):
		_select_quickslot(index)
		return
	_run_action(item, inventory.default_action(item))

func open_quick_bag(bag: InventoryBag = null) -> void:
	close_bag()
	_quick_bag = true
	current_bag = bag if bag != null else inventory.backpack
	_build_bag()

func _build_quick_bag() -> void:
	var items: Array[InventoryItem] = []
	var candidates := inventory.all_items() if current_bag == inventory.backpack else current_bag.items
	for item in candidates:
		if item is InventoryBag or item.default_action.is_empty(): continue
		if item.category == "artifact" and not inventory.is_equipped(item): continue
		items.append(item)
	inventory.sort_items(items, true)
	var rows := maxi(1, ceili(items.size() / 8.0))
	bag_panel = _panel(bag_layer, Vector2(147, 24 + rows * 21), "TOAST_TR")
	_label(bag_panel, L10n.text("快速使用"), Rect2(6, 4, 135, 10), 8, TITLE_COLOR).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in items.size():
		var item := items[i]
		var slot := _slot(bag_panel, item, Rect2(6 + (i % 8) * 17, 16 + int(i / 8) * 21, 16, 20))
		slot.show_extra = false
		slot.clicked.connect(_click_item.bind(item))
		slot.long_clicked.connect(_long_click_item.bind(item))
		slot.right_clicked.connect(show_item.bind(item))
		slots.append(slot)
	_layout()

func _show_notes(item: InventoryItem) -> void:
	_close_detail()
	_detail_item = item
	detail_layer = _layer()
	detail_panel = _panel(detail_layer, Vector2(132, 120))
	_label(detail_panel, item.display_name() + L10n.text(" · 记录"), Rect2(6, 6, 120, 16), ITEM_TITLE_FONT_SIZE, TITLE_COLOR)
	_note_edit = TextEdit.new()
	_note_edit.text = item.note
	_note_edit.position = Vector2(6, 25)
	_note_edit.size = Vector2(120, 63)
	_note_edit.add_theme_font_override("font", _font)
	_note_edit.add_theme_font_size_override("font_size", 8)
	UiAssets.apply_text_outline(_note_edit)
	detail_panel.add_child(_note_edit)
	_button(detail_panel, L10n.text("保存记录"), Rect2(6, 96, 120, 18), func():
		item.note = _note_edit.text
		inventory.changed.emit()
		show_item(item))
	_layout()

func _layout() -> void:
	if not is_inside_tree(): return
	var safe := ScreenLayout.safe_rect(get_viewport())
	if toolbar != null:
		if toolbar_leading_width > 0:
			var factor := minf(2.0, (safe.size.x - 4) / (toolbar.size.x + toolbar_leading_width))
			toolbar.scale = Vector2.ONE * factor
			toolbar.position = Vector2(safe.end.x - 2 - toolbar.size.x * factor,
				safe.end.y - 29 * factor).floor()
		else:
			toolbar.scale = Vector2.ONE * 2
			toolbar.position = Vector2(safe.position.x + (safe.size.x - toolbar.size.x * 2) / 2, safe.end.y - 58).floor()
	for panel in [bag_panel, detail_panel]:
		if not is_instance_valid(panel): continue
		var factor := minf(2.0, minf((safe.size.x - 12) / panel.size.x, (safe.size.y - 24) / (panel.size.y + 8)))
		panel.scale = Vector2.ONE * factor
		panel.position = (safe.position + (safe.size - panel.size * factor) / 2).floor()
		# Generate enough source pixels for the actual panel + device scale.
		var raster_font := UiAssets.get_font_at_scale(factor * get_viewport().get_final_transform().get_scale().x)
		for child in panel.find_children("*", "Control", true, false):
			if child is NativeRichText:
				child.refresh_pixels()
				continue
			if child.get_parent() is NativeRichText: continue
			var key := "normal_font" if child is RichTextLabel else "font"
			if child is Label or child is RichTextLabel or child is BaseButton or child is TextEdit:
				if child.get_theme_font(key) != raster_font: child.add_theme_font_override(key, raster_font)
	if _quick_bag and bag_panel != null:
		bag_panel.position.y = safe.end.y - 66 - bag_panel.size.y * bag_panel.scale.y

func _input(event: InputEvent) -> void:
	if inventory == null: return
	if event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if (focus is TextEdit or focus is LineEdit) and event.keycode != KEY_ESCAPE: return
		if event.keycode == KEY_ESCAPE:
			if detail_layer != null: _cancel_detail()
			elif bag_layer != null: close_bag()
			else: inventory.cancel_target()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_I, KEY_B]:
			toggle_bag()
			get_viewport().set_input_as_handled()
		elif bag_layer != null and not _quick_bag and event.keycode >= KEY_1 and event.keycode <= KEY_5:
			var index: int = event.keycode - KEY_1
			if index < inventory.bags().size(): _switch_bag(inventory.bags()[index])
			get_viewport().set_input_as_handled()
		elif bag_layer == null and event.keycode >= KEY_1 and event.keycode <= KEY_6:
			_use_quickslot(event.keycode - KEY_1)
			get_viewport().set_input_as_handled()
