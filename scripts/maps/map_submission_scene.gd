extends Control
const Data = preload("res://scripts/maps/submitted_map.gd")
const MapView = preload("res://scripts/maps/map_canvas.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const DRAFT_PATH := "user://map-submission-draft.json"
var document: Dictionary = Data.empty()
var brush := DungeonTerrain.Type.WALL
var _undo: Array[Dictionary] = []
var _stroke_before: Dictionary = {}
var _canvas: Control
var _header: Label
var _back: Button
var _tabs: Array[Button] = []
var _scroll: ScrollContainer
var _body: VBoxContainer
var _gallery: VBoxContainer
var _cards: VBoxContainer
var _page_label: Label
var _previous: Button
var _next: Button
var _editor: Control
var editor_map: Control
var _properties: VBoxContainer
var _brush_label: Label
var _name: LineEdit
var _author: LineEdit
var _region: OptionButton
var _mirror: CheckBox
var _undo_button: Button
var _submit: Button
var _status: Label
var _draft_status: Label
var _viewer: Control
var _viewer_panel: PanelContainer
var _current_tab := 0
var _page := 0
var _pages := 1
var _loaded := false
var _pending_id := 0
var _pending_kind := ""
var _request_deadline := 0
var _save_at := -1
var _previous_back := true
var _known_ready := false
var _syncing := false

func _ready() -> void:
	_previous_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	var background := DungeonTitleBackground.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0,0,0,0.65)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_canvas = Control.new()
	_canvas.theme = UiAssets.make_theme()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_canvas)
	_header = _label(_canvas,"地图投稿",12,Color("ffff44"))
	_back = _button(_canvas,"返回",_return_menu)
	for index in 2:
		_tabs.append(_button(_canvas,"地图广场" if index == 0 else "编辑投稿",_select_tab.bind(index)))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 8
	_canvas.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	_status = _label(_canvas,"",7)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_gallery()
	_build_editor()
	_load_draft()
	_sync_fields()
	PvpNet.map_submission_result.connect(_result)
	PvpNet.server_status_changed.connect(_connection_changed)
	get_viewport().size_changed.connect(_layout)
	PvpNet.monitor_server()
	_select_tab(0)
	_connection_changed()
	_layout()

func _label(parent: Node, caption: String, font_size: int = 7, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = L10n.text(caption)
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	UiAssets.apply_text_outline(label)
	parent.add_child(label)
	return label

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = L10n.text(caption)
	button.add_theme_font_size_override("font_size",7)
	button.custom_minimum_size.y = 18
	UiAssets.apply_button_style(button,"GREY_BUTTON_TR")
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _build_gallery() -> void:
	_gallery = VBoxContainer.new()
	_gallery.add_theme_constant_override("separation",6)
	_body.add_child(_gallery)
	var actions := HBoxContainer.new()
	_gallery.add_child(actions)
	_button(actions,"刷新",func(): _load_page(_page))
	_previous = _button(actions,"上一页",func(): _load_page(_page-1))
	_page_label = _label(actions,"1 / 1",8)
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_next = _button(actions,"下一页",func(): _load_page(_page+1))
	var hint := _label(_gallery,"点击地图查看完整投稿和编号。",7,Color("aaaaaa"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation",6)
	_gallery.add_child(_cards)

func _build_editor() -> void:
	_editor = Control.new()
	_body.add_child(_editor)
	editor_map = MapView.new()
	editor_map.editable = true
	_editor.add_child(editor_map)
	editor_map.position = Vector2(2,0)
	editor_map.size = Vector2(192,192)
	editor_map.stroke_started.connect(func(): _stroke_before = document.duplicate(true))
	editor_map.painted.connect(_paint)
	editor_map.stroke_finished.connect(_finish_stroke)
	_brush_label = _label(_editor,"",7,Color("ffff44"))
	_brush_label.position = Vector2(2,195)
	_properties = VBoxContainer.new()
	_properties.add_theme_constant_override("separation",3)
	_editor.add_child(_properties)
	_properties.minimum_size_changed.connect(_layout.call_deferred)
	var palette := GridContainer.new()
	palette.columns = 4
	_properties.add_child(palette)
	for index in Data.TERRAINS.size():
		var tile: int = Data.TERRAINS[index]
		_button(palette,Data.TITLES[index],_choose_brush.bind(tile))
	_button(palette,"出生点A",_choose_brush.bind(-1))
	_button(palette,"出生点B",_choose_brush.bind(-2))
	_label(_properties,"地图名称",7)
	_name = LineEdit.new()
	_name.max_length = Data.MAX_TITLE
	_name.add_theme_font_size_override("font_size",9)
	_properties.add_child(_name)
	_name.text_changed.connect(func(value):
		if not _syncing: document.name = value; _schedule_save())
	_label(_properties,"作者",7)
	_author = LineEdit.new()
	_author.max_length = Data.MAX_AUTHOR
	_author.add_theme_font_size_override("font_size",9)
	_properties.add_child(_author)
	_author.text_changed.connect(func(value):
		if not _syncing: document.author = value; _schedule_save())
	_region = OptionButton.new()
	_region.add_theme_font_size_override("font_size",8)
	for caption in ["下水道","监狱","洞穴","矮人都市","恶魔大厅"]: _region.add_item(L10n.text(caption))
	_properties.add_child(_region)
	_region.item_selected.connect(func(index): document.region = index; editor_map.set_document(document); _schedule_save())
	_mirror = CheckBox.new()
	_mirror.text = L10n.text("中心对称绘制")
	_mirror.button_pressed = true
	_mirror.add_theme_font_size_override("font_size",7)
	_properties.add_child(_mirror)
	var actions := HBoxContainer.new()
	_properties.add_child(actions)
	_undo_button = _button(actions,"撤销",_undo_stroke)
	_button(actions,"新建",_new_map)
	_submit = _button(actions,"提交投稿",_submit_map)
	_submit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_draft_status = _label(_properties,"草稿自动保存在本机",7,Color("aaaaaa"))
	_draft_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := _label(_properties,"拖动绘制地形，再设置双方出生点。",7,Color("aaaaaa"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _choose_brush(value: int) -> void:
	brush = value
	_brush_label.text = L10n.text("出生点A" if value == -1 else "出生点B" if value == -2 else Data.TITLES[Data.TERRAINS.find(value)])

func _paint(cell: Vector2i) -> void:
	if brush < 0:
		var index := 0 if brush == -1 else 1
		var other: Array = document.spawns[1-index]
		if [cell.x,cell.y] == other: return
		document.spawns[index] = [cell.x,cell.y]
		if _mirror.button_pressed: document.spawns[1-index] = [11-cell.x,11-cell.y]
	else:
		document.tiles[cell.x+cell.y*12] = brush
		if _mirror.button_pressed: document.tiles[11-cell.x+(11-cell.y)*12] = brush
	editor_map.set_document(document)
	_schedule_save()

func _finish_stroke() -> void:
	if not _stroke_before.is_empty() and document != _stroke_before:
		_undo.append({"tiles":_stroke_before.tiles,"spawns":_stroke_before.spawns})
		if _undo.size() > 32: _undo.pop_front()
	_stroke_before = {}
	_undo_button.disabled = _undo.is_empty()

func _undo_stroke() -> void:
	editor_map.finish_stroke()
	if _undo.is_empty(): return
	var previous: Dictionary = _undo.pop_back()
	if previous.has("name"): document = previous
	else:
		document.tiles = previous.tiles
		document.spawns = previous.spawns
	_sync_fields()
	_schedule_save()

func _new_map() -> void:
	editor_map.finish_stroke()
	_undo.append(document.duplicate(true))
	if _undo.size() > 32: _undo.pop_front()
	document = Data.empty()
	document.author = ClientPrefs.session_player_name().left(16)
	_sync_fields()
	_schedule_save()

func _sync_fields() -> void:
	_syncing = true
	_name.text = str(document.name)
	_author.text = str(document.author)
	_region.select(int(document.region))
	_syncing = false
	editor_map.set_document(document)
	_choose_brush(brush)
	_undo_button.disabled = _undo.is_empty()

func _load_draft() -> void:
	document = Data.empty()
	document.author = ClientPrefs.session_player_name().left(16)
	if not FileAccess.file_exists(DRAFT_PATH): return
	var file := FileAccess.open(DRAFT_PATH,FileAccess.READ)
	if file == null or file.get_length() > 16384: return
	var stored: Variant = JSON.parse_string(file.get_as_text())
	if not stored is Dictionary: return
	var checked := Data.validate(stored,false)
	if checked.has("map"): document = checked.map

func _schedule_save() -> void:
	_save_at = Time.get_ticks_msec()+400
	_draft_status.text = L10n.text("正在保存草稿…")

func _save_draft() -> void:
	_save_at = -1
	var file := FileAccess.open(DRAFT_PATH+".tmp",FileAccess.WRITE)
	if file == null:
		_draft_status.text = L10n.text("草稿保存失败，请检查本机存储空间。")
		return
	file.store_string(JSON.stringify(document))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(DRAFT_PATH+".tmp",DRAFT_PATH)
	_draft_status.text = L10n.text("草稿已保存在本机" if error == OK else "草稿保存失败，请检查本机存储空间。")

func _select_tab(index: int) -> void:
	editor_map.finish_stroke()
	_current_tab = index
	_gallery.visible = index == 0
	_editor.visible = index == 1
	for at in 2: _tabs[at].set_pressed_no_signal(at == index)
	_scroll.scroll_vertical = 0
	if index == 0 and not _loaded and _pending_id == 0: _load_page(0)
	_layout()

func _connection_changed() -> void:
	var ready: bool = PvpNet.is_server_ready()
	_submit.disabled = not ready or _pending_id > 0
	if ready and not _known_ready and not _loaded and _pending_id == 0: _load_page(0)
	if not ready and _known_ready: _status.text = L10n.text("服务器未连接，可先编辑并保存草稿。")
	_known_ready = ready

func _request(payload: Dictionary, kind: String) -> void:
	if _pending_id > 0: return
	_pending_id = PvpNet.request_map_submissions(payload)
	if _pending_id == 0:
		_status.text = L10n.text("服务器未连接，可先编辑并保存草稿。")
		return
	_pending_kind = kind
	_request_deadline = Time.get_ticks_msec()+10000
	_status.text = L10n.text("正在提交…" if kind == "submit" else "正在加载投稿…")
	_submit.disabled = true

func _load_page(page: int) -> void:
	_request({"op":"list","page":maxi(0,page)},"list")

func _submit_map() -> void:
	editor_map.finish_stroke()
	var checked := Data.validate(document)
	if checked.has("error"):
		_status.text = L10n.text(str(checked.error))
		return
	_save_draft()
	_request({"op":"submit","map":checked.map},"submit")

func _result(request_id: int, result: Dictionary) -> void:
	if request_id != _pending_id: return
	var kind := _pending_kind
	_pending_id = 0
	_pending_kind = ""
	_submit.disabled = not PvpNet.is_server_ready()
	if result.has("error"):
		_status.text = L10n.text(str(result.error))
		return
	if kind == "list":
		_loaded = true
		_page = int(result.page)
		_pages = int(result.pages)
		_page_label.text = "%d / %d"%[_page+1,_pages]
		_previous.disabled = _page == 0
		_next.disabled = _page+1 >= _pages
		for child in _cards.get_children(): child.free()
		for entry in result.maps: _add_card(entry)
		if result.maps.is_empty(): _label(_cards,"还没有投稿，来制作第一张地图吧。",8)
		_status.text = L10n.text("共%d张投稿地图")%int(result.total)
		_scroll.scroll_vertical = 0
	elif kind in ["submit","view"]:
		_status.text = L10n.text("投稿已公开" if kind == "submit" else "")
		if kind == "submit":
			_loaded = false
			_select_tab(0)
		_show_viewer(result.map)

func _add_card(entry: Dictionary) -> void:
	var card := _button(_cards,"",func(): _request({"op":"get","id":entry.id},"view"))
	card.custom_minimum_size.y = 104
	var thumbnail := MapView.new()
	thumbnail.document = entry
	card.add_child(thumbnail)
	thumbnail.position = Vector2(4,4)
	thumbnail.size = Vector2(96,96)
	var labels := VBoxContainer.new()
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(labels)
	labels.position = Vector2(106,5)
	var title := _label(labels,str(entry.name),9,Color("ffff44"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var author := _label(labels,L10n.text("作者：%s")%str(entry.author),7)
	author.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(labels,Time.get_datetime_string_from_unix_time(int(entry.created_at)).replace("T"," ")+" UTC",6,Color("aaaaaa"))
	var id_label := _label(labels,str(entry.id),6,Color("aaaaaa"))
	id_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	card.resized.connect(func(): labels.size.x = maxf(40,card.size.x-112))
	labels.size.x = maxf(40,_scroll.size.x-116)

func _show_viewer(entry: Dictionary) -> void:
	_close_viewer()
	_viewer = Control.new()
	_viewer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_viewer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_viewer)
	var shade := ColorRect.new()
	shade.color = Color(0,0,0,0.8)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: _close_viewer(); get_viewport().set_input_as_handled())
	_viewer.add_child(shade)
	_viewer_panel = PanelContainer.new()
	_viewer_panel.theme = UiAssets.make_theme()
	_viewer_panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewer_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewer_panel.add_theme_stylebox_override("panel",UiAssets.get_style("WINDOW"))
	_viewer.add_child(_viewer_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",4)
	column.custom_minimum_size.x = 200
	_viewer_panel.add_child(column)
	var title := _label(column,str(entry.name),10,Color("ffff44"))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(column,L10n.text("作者：%s")%str(entry.author),7)
	var map_view := MapView.new()
	map_view.document = entry
	map_view.custom_minimum_size = Vector2(192,192)
	column.add_child(map_view)
	var id_field := LineEdit.new()
	id_field.text = str(entry.id)
	id_field.editable = false
	id_field.add_theme_font_size_override("font_size",7)
	column.add_child(id_field)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_button(actions,"复制编号",func(): DisplayServer.clipboard_set(str(entry.id)); _status.text = L10n.text("投稿编号已复制"))
	_button(actions,"关闭",_close_viewer)
	_viewer_panel.minimum_size_changed.connect(_layout.call_deferred)
	_layout.call_deferred()

func _close_viewer() -> void:
	if is_instance_valid(_viewer):
		remove_child(_viewer)
		_viewer.queue_free()
	_viewer = null
	_viewer_panel = null

func _layout() -> void:
	if not is_node_ready(): return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var zoom := minf(2,(safe.size.x-12)/224)
	_canvas.scale = Vector2.ONE*zoom
	_canvas.position = safe.position+Vector2(6,4)
	_canvas.size = (safe.size-Vector2(12,8))/zoom
	var width := _canvas.size.x
	var height := _canvas.size.y
	_header.position = Vector2(2,2)
	_back.position = Vector2(width-30,0)
	_back.size = Vector2(30,18)
	for index in 2:
		_tabs[index].position = Vector2(index*width/2,23)
		_tabs[index].size = Vector2(width/2-2,20)
	_scroll.position = Vector2(0,48)
	_scroll.size = Vector2(width,maxf(80,height-76))
	_status.position = Vector2(0,height-25)
	_status.size = Vector2(width,24)
	var usable := width-10
	_properties.position = Vector2(202,0) if usable >= 398 else Vector2(2,213)
	_properties.size.x = usable-204 if usable >= 398 else 192
	_editor.custom_minimum_size = Vector2(196,maxf(211,_properties.get_combined_minimum_size().y)) if usable >= 398 else Vector2(196,217+_properties.get_combined_minimum_size().y)
	if is_instance_valid(_viewer_panel):
		_viewer_panel.size = _viewer_panel.get_combined_minimum_size()
		var factor := minf(2,minf((safe.size.x-12)/_viewer_panel.size.x,(safe.size.y-12)/_viewer_panel.size.y))
		_viewer_panel.scale = Vector2.ONE*factor
		_viewer_panel.position = (safe.position+(safe.size-_viewer_panel.size*factor)/2).floor()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _save_at >= 0 and now >= _save_at: _save_draft()
	if _pending_id > 0 and now >= _request_deadline:
		_pending_id = 0
		_pending_kind = ""
		_submit.disabled = not PvpNet.is_server_ready()
		_status.text = L10n.text("请求超时，请刷新后重试。")

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_viewer): _close_viewer()
		else: _return_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_instance_valid(_viewer): _close_viewer()
		else: _return_menu()

func _return_menu() -> void:
	editor_map.finish_stroke()
	_save_draft()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	if _save_at >= 0: _save_draft()
	get_tree().quit_on_go_back = _previous_back
	if PvpNet.map_submission_result.is_connected(_result): PvpNet.map_submission_result.disconnect(_result)
	if PvpNet.server_status_changed.is_connected(_connection_changed): PvpNet.server_status_changed.disconnect(_connection_changed)
