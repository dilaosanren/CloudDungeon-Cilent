# AboutScene.java / ExitButton.java adaptation from SPD 4.0.2. GPL-3.0-or-later.
extends Control

const L10n = preload("res://scripts/menu/game_locale.gd")
const CreditBlock = preload("res://scripts/menu/about_credit_block.gd")
const PROJECT_SOURCE_URL := "https://github.com/dilaosanren/CloudDungeon-Cilent"
const ZH := {
	"shpx": {"title":"破碎的像素地牢", "body":"开发者：_Evan Debenham_\n基于 Pixel Dungeon 的开源代码"},
	"aleks": {"title":"主视觉与地牢美术："},
	"lumine": {"title":"作曲："},
	"pumpkin": {"title":"物品像素美术："},
	"celesti": {"title":"音效："},
	"alastair": {"title":"其他像素美术："},
	"wata": {"title":"像素地牢", "body":"开发者：_Watabou_\n灵感来自 Brian Walker 的 Brogue"},
	"cube": {"title":"音乐："},
	"gdx": {"body":"破碎的像素地牢原版使用 _libGDX_ 引擎。"},
	"arcnor": {"title":"Pixel Dungeon GDX："},
	"purigro": {"title":"破碎 GDX 移植协助："},
	"transifex": {"body":"破碎的像素地牢由社区通过 _Transifex_ 翻译！感谢所有自愿参与翻译的贡献者！"},
}
var _catalog: Dictionary
var _interface: Control
var _scroll: ScrollContainer
var _content: Control
var _blocks: Dictionary = {}
var _lines: Array[ColorRect] = []
var _back_button: Button
var _click: AudioStreamPlayer
var _previous_go_back := true
var _layout_pending := false

func _ready() -> void:
	_previous_go_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/menu/about_credits.json"))
	var background := DungeonTitleBackground.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0x44 / 255.0)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_interface = Control.new()
	_interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interface.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_interface.theme = UiAssets.make_theme()
	add_child(_interface)
	_scroll = ScrollContainer.new()
	_scroll.name = "CreditsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.scroll_deadzone = 6
	_interface.add_child(_scroll)
	# ScrollPane's thumb is two logical pixels wide and half opaque at rest.
	var scrollbar := _scroll.get_v_scroll_bar()
	scrollbar.add_theme_stylebox_override("scroll", StyleBoxEmpty.new())
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color(1, 1, 1, 0.5 if state == "grabber" else 1.0)
		thumb.content_margin_left = 1
		thumb.content_margin_right = 1
		scrollbar.add_theme_stylebox_override(state, thumb)
	_scroll.get_v_scroll_bar().visibility_changed.connect(_schedule_layout)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	_click = AudioStreamPlayer.new()
	_click.bus = &"SFX"
	_click.stream = preload("res://assets/inventory/click.mp3")
	add_child(_click)
	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.icon = _icon("EXIT")
	_back_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		_back_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_back_button.button_down.connect(func(): _click.play(); _back_button.self_modulate = Color(1.5, 1.5, 1.5))
	_back_button.button_up.connect(func(): _back_button.self_modulate = Color.WHITE)
	_back_button.pressed.connect(_return_menu)
	_interface.add_child(_back_button)
	get_viewport().size_changed.connect(_schedule_layout)
	_build_credits()
	_layout()
	_schedule_layout()

func _icon(key: String) -> AtlasTexture:
	var rect: Array = _catalog.icons[key]
	var texture := AtlasTexture.new()
	texture.atlas = preload("res://assets/ui/source/icons.png")
	texture.region = Rect2(rect[0], rect[1], rect[2], rect[3])
	return texture

func _build_credits() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_blocks.clear()
	_lines.clear()
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var game_name := str(ProjectSettings.get_setting("application/config/name", "Cloud Dungeon"))
	_add_block("project", {"large":true, "color":"d97757", "title":game_name + "  v" + version,
		"body": "双人回合制 PvP 地牢 · Godot\n基于破碎的像素地牢 4.0.2\n以下为原版作者与贡献者鸣谢。\n\n项目开源地址：" if not L10n.is_english() else "Turn-based PvP dungeon · Godot\nBased on Shattered Pixel Dungeon 4.0.2\nOriginal game credits follow.\n\nProject source:",
		"link_text":PROJECT_SOURCE_URL,"link_url":PROJECT_SOURCE_URL})
	for original in _catalog.blocks:
		var data: Dictionary = original.duplicate(true)
		if not L10n.is_english():
			data.merge(ZH.get(str(data.id), {}), true)
			if data.id == "freesound":
				data.body = str(data.body).replace("Shattered Pixel Dungeon uses the following sound samples from _freesound.org_:", "破碎的像素地牢使用了以下来自 _freesound.org_ 的音效：").replace("Creative Commons Attribution License:", "知识共享署名许可（CC BY）：").replace("Creative Commons Zero License:", "知识共享零许可（CC0）：")
		elif data.id == "gdx":
			data.body = "The original ShatteredPD is powered by _libGDX_!"
		_add_block(str(data.id), data)
	for i in 5:
		var line := ColorRect.new()
		line.color = Color("333333")
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(line)
		_lines.append(line)
	_add_block("license", {"large":true, "color":"bbbbbb", "body":"原版代码与素材遵循 GPL-3.0-or-later。" if not L10n.is_english() else "Original code and art: GPL-3.0-or-later."})
	_back_button.tooltip_text = "Back" if L10n.is_english() else "返回主菜单"

func _add_block(key: String, data: Dictionary) -> void:
	var block := CreditBlock.new()
	block.name = key.to_pascal_case()
	_content.add_child(block)
	var key_icon := str(data.get("icon", ""))
	block.configure(data, _icon(key_icon) if not key_icon.is_empty() else null)
	block.minimum_size_changed.connect(_schedule_layout)
	if block.link_button != null: block.link_button.button_down.connect(_click.play)
	_blocks[key] = block

func _place(key: String, x: float, y: float, width: float) -> float:
	return y + _blocks[key].layout_at(Vector2(x, y), width)

func _line(index: int, y: float, width: float) -> void:
	ScreenLayout.place(_lines[index], Rect2(0, floorf(y), width, 1))

func _schedule_layout() -> void:
	if _layout_pending or not is_inside_tree(): return
	_layout_pending = true
	_layout.call_deferred()

func _layout() -> void:
	_layout_pending = false
	if not is_instance_valid(_content): return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var factor := minf(2, minf(safe.size.x / 160, safe.size.y / 200))
	_interface.scale = Vector2.ONE * factor
	_interface.position = safe.position
	_interface.size = safe.size / factor
	_scroll.size = _interface.size
	var bar := _scroll.get_v_scroll_bar()
	var width := _scroll.size.x - (bar.size.x if bar.visible else 0.0)
	var landscape := safe.size.x > safe.size.y
	var col := 120.0 if landscape else 130.0
	var left := (width - col * (2 if landscape else 1)) / 2
	var center := (width - col) / 2
	var top := _place("project", center, 6, col) + 8
	_line(0, top - 4, width)
	var shpx_bottom := _place("shpx", left, top + (20 if landscape else 0), col)
	var artists_left := left + col if landscape else left
	var artists_top := top if landscape else shpx_bottom + 6
	var row := maxf(_place("aleks", artists_left, artists_top, col / 2), _place("lumine", artists_left + col / 2, artists_top, col / 2)) + 6
	row = maxf(_place("pumpkin", artists_left, row, col / 2), _place("celesti", artists_left + col / 2, row, col / 2)) + 6
	top = maxf(shpx_bottom, _place("alastair", artists_left, row, col / 2)) + 8
	_line(1, top - 4, width)
	var wata_bottom := _place("wata", left, top, col)
	var cube_bottom := _place("cube", left + col * 1.25 if landscape else left + col / 4, top if landscape else wata_bottom + 6, col / 2)
	top = maxf(wata_bottom, cube_bottom) + 8
	_line(2, top - 4, width)
	var gdx_bottom := _place("gdx", left, top, col)
	var helpers_left := left + col if landscape else left
	var helpers_top := top if landscape else gdx_bottom + 6
	top = maxf(gdx_bottom, maxf(_place("arcnor", helpers_left, helpers_top, col / 2), _place("purigro", helpers_left + col / 2, helpers_top, col / 2))) + 12
	_line(3, top - 4, width)
	top = _place("transifex", center, top, col) + 8
	_line(4, top - 4, width)
	top = _place("freesound", center - 10, top, col + 20) + 8
	top = _place("license", center, top, col) + 10
	_content.custom_minimum_size = Vector2(0, ceilf(top))
	ScreenLayout.place(_back_button, Rect2(_interface.size.x - 24, 4, 20, 20))

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_return_menu()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST: _return_menu()
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_instance_valid(_content):
		_build_credits()
		_schedule_layout()

func _return_menu() -> void:
	if not is_inside_tree(): return
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu.tscn")

func _exit_tree() -> void:
	get_tree().quit_on_go_back = _previous_go_back
