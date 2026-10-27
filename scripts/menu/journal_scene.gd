# Title-menu JournalScene / IconTitle / ExitButton adaptation, SPD 4.0.2.
# GPL-3.0-or-later. Badges placeholder and equipment previews.
extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")
const EquipmentPage = preload("res://scripts/menu/equipment_catalog_page.gd")
const EquipmentPreview = preload("res://scripts/menu/equipment_preview.gd")
const EQUIPMENT_TAB := 0
const BADGES_TAB := 1
const PAGE_NAMES := ["装备预览", "徽章"]
const PAGE_ICONS := ["CATALOG", "BADGES"]
static var last_tab := EQUIPMENT_TAB
var current_tab := EQUIPMENT_TAB
var _canvas: Control
var _heading: Label
var _heading_icon: TextureRect
var _panel: Panel
var _back: Button
var _pages: Array[Control] = []
var _tabs: Array[DungeonMenuButton] = []
var _page_headings: Array[Label] = []
var _notices: Array[Control] = []
var _warning_icons: Array[TextureRect] = []
var _messages: Array[Label] = []
var _equipment: EquipmentPage
var _equipment_preview: EquipmentPreview
var _click: AudioStreamPlayer
var _previous_go_back := true
var _returning := false

func _ready() -> void:
	_previous_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	var background := DungeonTitleBackground.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_canvas = Control.new()
	_canvas.theme = UiAssets.make_theme()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_canvas)
	_click = AudioStreamPlayer.new()
	_click.stream = preload("res://assets/inventory/click.mp3")
	add_child(_click)
	_heading_icon = _icon(_canvas,"JOURNAL")
	_heading = _label(_canvas,Color("ffff44"))
	_back = Button.new()
	_back.name = "Back"
	_back.icon = MenuAssets.icon("EXIT")
	_back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		_back.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	_canvas.add_child(_back)
	_back.pressed.connect(func(): _click.play(); _return_menu())
	var group := ButtonGroup.new()
	for i in 2:
		var tab := DungeonMenuButton.new()
		tab.name = "EquipmentTab" if i==EQUIPMENT_TAB else "BadgesTab"
		tab.configure("",MenuAssets.icon(PAGE_ICONS[i]))
		tab.toggle_mode = true
		tab.button_group = group
		_canvas.add_child(tab)
		# JournalScene's selection is height/brightness, rather than a held-down button.
		tab.add_theme_stylebox_override("pressed",tab.get_theme_stylebox("normal").duplicate())
		tab.pressed.connect(_select_tab.bind(i))
		_tabs.append(tab)
	# Draw the panel over the upper 3px of the two tabs, like addToBack in SPD.
	_panel = Panel.new()
	_panel.name = "JournalPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel",UiAssets.get_style("TOAST"))
	_canvas.add_child(_panel)
	for i in 2:
		var page := Control.new()
		page.name = "EquipmentPreview" if i==EQUIPMENT_TAB else "Badges"
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(page)
		_pages.append(page)
		var heading := _label(page,Color("ffff44"))
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_page_headings.append(heading)
		var notice := Control.new()
		notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(notice)
		_notices.append(notice)
		_warning_icons.append(_icon(notice,"WARNING"))
		_messages.append(_label(notice,Color.WHITE))
	_notices[EQUIPMENT_TAB].hide()
	_equipment = EquipmentPage.new()
	_pages[EQUIPMENT_TAB].add_child(_equipment)
	_equipment.item_requested.connect(_open_equipment)
	_refresh_text()
	_select_tab(last_tab)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _label(parent: Node,color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",9)
	label.add_theme_color_override("font_color",color)
	UiAssets.apply_text_outline(label)
	parent.add_child(label)
	return label

func _icon(parent: Node,icon: String) -> TextureRect:
	var view := TextureRect.new()
	view.texture = MenuAssets.icon(icon)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(view)
	return view

func _refresh_text() -> void:
	_heading.text = L10n.text("日志")
	_back.tooltip_text = L10n.text("返回")
	for i in 2:
		_page_headings[i].text = L10n.text(PAGE_NAMES[i])
		_tabs[i].tooltip_text = L10n.text(PAGE_NAMES[i])
		_messages[i].text = L10n.text("正在施工")
	if is_instance_valid(_equipment): _equipment.refresh_text()
	if is_instance_valid(_equipment_preview): _equipment_preview.refresh_text()

func _open_equipment(type_id: String) -> void:
	if is_instance_valid(_equipment_preview): return
	var item := EquipmentPage.Catalog.create(type_id)
	if item == null: return
	_click.play()
	_equipment_preview = EquipmentPreview.new()
	_equipment_preview.item = item
	_equipment_preview.closed.connect(func(): _equipment_preview = null)
	add_child(_equipment_preview)

func _select_tab(index: int) -> void:
	current_tab = clampi(index,0,1)
	last_tab = current_tab
	for i in 2:
		_pages[i].visible = i==current_tab
		_tabs[i].set_pressed_no_signal(i==current_tab)
		_tabs[i].icon_view.modulate = Color.WHITE if i==current_tab else Color(0.6,0.6,0.6)
	_layout()

func _layout() -> void:
	if not is_instance_valid(_panel): return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var factor := minf(2,minf(safe.size.x/140,safe.size.y/160))
	_canvas.position = safe.position
	_canvas.scale = Vector2.ONE*factor
	_canvas.size = safe.size/factor
	var dimensions := _canvas.size
	var style := _panel.get_theme_stylebox("panel")
	var margins := style.get_minimum_size()
	var width := (216.0 if dimensions.x>dimensions.y else 126.0)+margins.x
	width = minf(width,dimensions.x-4)
	var height := floorf(dimensions.y-50+margins.y)
	ScreenLayout.place(_panel,Rect2(floorf((dimensions.x-width)/2),20,width,height))
	var title_size := _heading.get_minimum_size()
	var icon_size := _heading_icon.texture.get_size()
	var title_left := floorf((dimensions.x-icon_size.x-2-title_size.x)/2)
	ScreenLayout.place(_heading_icon,Rect2(title_left,floorf((20-icon_size.y)/2),icon_size.x,icon_size.y))
	ScreenLayout.place(_heading,Rect2(title_left+icon_size.x+2,floorf((20-title_size.y)/2),title_size.x,title_size.y))
	ScreenLayout.place(_back,Rect2(dimensions.x-20,0,20,20))
	for i in 2:
		ScreenLayout.place(_tabs[i],Rect2(_panel.position.x+i*(width/2-1),_panel.position.y+height-3,width/2+1,25 if i==current_tab else 20))
		ScreenLayout.place(_pages[i],Rect2(style.get_margin(SIDE_LEFT),style.get_margin(SIDE_TOP),width-margins.x,height-margins.y))
		ScreenLayout.place(_page_headings[i],Rect2(3,4,_pages[i].size.x-6,16))
		var text_size := _messages[i].get_minimum_size()
		var warning_size := _warning_icons[i].texture.get_size()
		var notice_size := Vector2(warning_size.x+4+text_size.x,maxf(warning_size.y,text_size.y))
		ScreenLayout.place(_notices[i],Rect2(((_pages[i].size-notice_size)/2).floor(),notice_size))
		ScreenLayout.place(_warning_icons[i],Rect2(0,floorf((notice_size.y-warning_size.y)/2),warning_size.x,warning_size.y))
		ScreenLayout.place(_messages[i],Rect2(warning_size.x+4,floorf((notice_size.y-text_size.y)/2),text_size.x,text_size.y))
	ScreenLayout.place(_equipment,Rect2(0,23,_pages[EQUIPMENT_TAB].size.x,maxf(1,_pages[EQUIPMENT_TAB].size.y-23)))

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_return_menu()

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST: _return_menu()
	if what==NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()
		_layout()

func _return_menu() -> void:
	if is_instance_valid(_equipment_preview):
		_equipment_preview.close()
		return
	if _returning or not is_inside_tree(): return
	_returning = true
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	get_tree().quit_on_go_back = _previous_go_back
