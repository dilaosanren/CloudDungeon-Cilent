extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")
const NativeText = preload("res://scripts/ui/native_rich_text.gd")
var _canvas: Control
var _heading: Label
var _icon: TextureRect
var _back: Button
var _refresh: Button
var _older: Button
var _newer: Button
var _page: Label
var _status: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _title: Label
var _date: Label
var _body: Control
var _click: AudioStreamPlayer
var _known: Array[String] = []
var _selected := ""
var _article := {}
var _index := 0
var _previous_go_back := true
var _was_ready := false

func _ready() -> void:
	_previous_go_back = get_tree().quit_on_go_back
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
	_icon = TextureRect.new()
	_icon.texture = MenuAssets.icon("NEWS")
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_icon)
	_heading = _label(_canvas,12,Color("ffff44"))
	_back = _button("返回",_return_menu)
	_refresh = _button("刷新",_refresh_latest)
	_older = _button("较早",func(): _select(_index+1))
	_newer = _button("较新",func(): _select(_index-1))
	_page = _label(_canvas,8,Color("bbbbbb"))
	_page.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status = _label(_canvas,7,Color("bbbbbb"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 6
	_canvas.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation",6)
	_scroll.add_child(_content)
	_title = _label(_content,10,Color("ffff44"))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_date = _label(_content,7,Color("aaaaaa"))
	_body = NativeText.new()
	_body.font_size = 8
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(_body)
	_body.content.bbcode_enabled = false
	_click = AudioStreamPlayer.new()
	_click.bus = &"SFX"
	_click.stream = preload("res://assets/inventory/click.mp3")
	add_child(_click)
	News.changed.connect(_news_changed)
	News.article_received.connect(_article_received)
	PvpNet.server_status_changed.connect(_connection)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_known = News.revisions()
	_select(0)
	PvpNet.monitor_server()
	_was_ready = PvpNet.is_server_ready()
	if not News.has_summary and _was_ready: _refresh_latest()

func _label(parent: Node, point: int, color: Color) -> Label:
	var label := Label.new()
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size",point)
	label.add_theme_color_override("font_color",color)
	UiAssets.apply_text_outline(label)
	parent.add_child(label)
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = L10n.text(text)
	button.add_theme_font_size_override("font_size",8)
	UiAssets.apply_button_style(button,"GREY_BUTTON_TR")
	_canvas.add_child(button)
	button.pressed.connect(func(): _click.play(); action.call())
	return button

func _select(index: int) -> void:
	_index = clampi(index,0,maxi(0,_known.size()-1))
	_selected = _known[_index] if not _known.is_empty() else ""
	_scroll.scroll_vertical = 0
	_article = News.cached_article(_selected)
	_show_article()
	if not _selected.is_empty() and _article.is_empty():
		_status.text = L10n.text("正在获取新闻…")
		News.request_article(_selected)

func _refresh_latest() -> void:
	_selected = ""
	_status.text = L10n.text("正在获取新闻…")
	News.request_article()

func _news_changed() -> void:
	var revisions := News.revisions()
	if revisions != _known:
		_known = revisions
		var next := _known.find(_selected)
		_select(next if next >= 0 else 0)
	_update_controls()

func _article_received(token: String, article: Dictionary, error: String) -> void:
	if not _selected.is_empty() and token != _selected: return
	if not error.is_empty():
		_status.text = L10n.text("服务器暂不支持新闻，请更新服务器。") if error == "不支持的投稿操作。" else L10n.render(error)
		_update_controls()
		return
	_selected = token
	_index = maxi(0,_known.find(token))
	_article = article
	_show_article()

func _show_article() -> void:
	if _article.is_empty():
		_title.text = L10n.text("暂无新闻。") if _known.is_empty() else ""
		_date.text = ""
		_body.text = ""
		_status.text = "" if PvpNet.is_server_ready() else L10n.text("服务器未连接，连接后可刷新。")
	else:
		var language := "en" if L10n.is_english() else "zh"
		_title.text = str(_article[language].title)
		_date.text = str(_article.published_at).replace("T"," ").trim_suffix("Z")+" UTC"
		_body.text = str(_article[language].body)
		_status.text = "" if PvpNet.is_server_ready() else L10n.text("离线：显示已缓存的新闻。")
		News.mark_read(_selected)
	_update_controls()

func _update_controls() -> void:
	_heading.text = L10n.text("新闻")
	_back.text = L10n.text("返回")
	_refresh.text = L10n.text("刷新")
	_older.text = L10n.text("较早")
	_newer.text = L10n.text("较新")
	_older.disabled = _index >= _known.size()-1
	_newer.disabled = _index <= 0
	_refresh.disabled = not PvpNet.is_server_ready() or News.loading
	_page.text = "%d / %d" % [_index+1,_known.size()] if not _known.is_empty() else "0 / 0"

func _connection() -> void:
	var ready := PvpNet.is_server_ready()
	if ready and not _was_ready and not News.has_summary: _refresh_latest()
	_was_ready = ready
	_update_controls()

func _layout() -> void:
	if _canvas == null: return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var zoom := minf(2,minf(safe.size.x/220,safe.size.y/190))
	var dimensions := Vector2(minf(460,safe.size.x/zoom),safe.size.y/zoom)
	_canvas.scale = Vector2.ONE*zoom
	_canvas.size = dimensions
	_canvas.position = safe.position+Vector2((safe.size.x-dimensions.x*zoom)/2,0)
	ScreenLayout.place(_icon,Rect2(9,10,16,15))
	ScreenLayout.place(_heading,Rect2(30,7,dimensions.x-128,22))
	ScreenLayout.place(_refresh,Rect2(dimensions.x-86,8,36,20))
	ScreenLayout.place(_back,Rect2(dimensions.x-44,8,36,20))
	ScreenLayout.place(_scroll,Rect2(10,37,dimensions.x-20,dimensions.y-98))
	ScreenLayout.place(_older,Rect2(10,dimensions.y-55,54,20))
	ScreenLayout.place(_newer,Rect2(dimensions.x-64,dimensions.y-55,54,20))
	ScreenLayout.place(_page,Rect2(68,dimensions.y-55,dimensions.x-136,20))
	ScreenLayout.place(_status,Rect2(8,dimensions.y-30,dimensions.x-16,27))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _return_menu()
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready(): _show_article()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_return_menu()
		get_viewport().set_input_as_handled()

func _return_menu() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
func _exit_tree() -> void: get_tree().quit_on_go_back = _previous_go_back
