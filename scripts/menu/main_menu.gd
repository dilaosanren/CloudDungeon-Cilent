# TitleScene / StyledButton menu layout adaptation. GPL-3.0-or-later.
class_name DungeonMainMenu
extends Control

const L10n = preload("res://scripts/menu/game_locale.gd")

signal menu_selected(entry: StringName)

const SETTINGS_WINDOW_PATH := "res://scripts/menu/settings_window.gd"
const DonationWindow = preload("res://scripts/menu/donation_window.gd")
const ENTRIES := [
	["battle", "对战", "ENTER"],
	["news", "新闻", "NEWS"],
	["history", "对战记录", "RANKINGS"],
	["donate", "捐献", "GOLD"],
	["changes", "改动", "CHANGES"],
	["journal", "日志", "JOURNAL"],
	["settings", "设置", "PREFS"],
	["about", "关于", "SHPX"],
]
const BUTTON_HEIGHT := 20.0
@export var title_texture: Texture2D
# Other entries can be connected as their features are completed.
@export var destinations: Dictionary[String, String] = {
	"battle": "res://scenes/pvp/client.tscn",
	"news": "res://scenes/news.tscn",
	"history": "res://scenes/battle_history.tscn",
	"changes": "res://scenes/changes.tscn",
	"journal": "res://scenes/journal.tscn",
	"about": "res://scenes/about.tscn"
}
@onready var background: DungeonTitleBackground = $Background
@onready var interface: Control = $Interface
@onready var title_slot: TextureRect = $Interface/TitleSlot
var buttons: Dictionary[String, DungeonMenuButton] = {}
var _settings_window: CanvasLayer
var _donation_window: CanvasLayer
var _server_status: Label
var _version_label: Label
var _settings_open := false
var _entering_battle := false
var _startup_loading := false
var startup_ready := false
var _news_age := 0.0

func _ready() -> void:
	_startup_loading = has_meta("startup")
	if not OS.has_feature("mobile"): get_window().min_size = Vector2i(240, 320)
	var game_name := str(ProjectSettings.get_setting("application/config/name", "Cloud Dungeon"))
	get_window().title = game_name
	var player_name := ClientPrefs.session_player_name()
	if not player_name.is_empty(): get_window().title = game_name + " · " + player_name
	interface.theme = UiAssets.make_theme()
	interface.theme.default_font_size = 9
	title_slot.texture = title_texture
	for entry in ENTRIES:
		var button := DungeonMenuButton.new()
		button.name = String(entry[0]).to_pascal_case() + "Button"
		button.configure(entry[1], MenuAssets.icon(entry[2]), Color("ffff44") if entry[0] == "donate" else Color.WHITE)
		button.disabled = _startup_loading
		button.pressed.connect(_select.bind(StringName(entry[0])))
		interface.add_child(button)
		buttons[entry[0]] = button
		if _startup_loading: await get_tree().process_frame
	_server_status = Label.new()
	_server_status.name = "ServerStatus"
	_server_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_server_status.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_server_status.add_theme_font_size_override("font_size", 8)
	UiAssets.apply_text_outline(_server_status)
	interface.add_child(_server_status)
	_version_label = Label.new()
	_version_label.name = "Version"
	_version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_version_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	_version_label.add_theme_font_size_override("font_size", 8)
	_version_label.add_theme_color_override("font_color", Color("888888"))
	UiAssets.apply_text_outline(_version_label)
	interface.add_child(_version_label)
	PvpNet.server_status_changed.connect(_refresh_server_status)
	News.changed.connect(_refresh_news)
	if not _startup_loading: PvpNet.monitor_server()
	_refresh_server_status()
	get_viewport().size_changed.connect(_layout)
	_layout()
	startup_ready = true
	if not _startup_loading: Music.play_theme()

func activate_startup() -> void:
	_startup_loading = false
	Music.play_theme()
	process_mode = Node.PROCESS_MODE_INHERIT
	PvpNet.monitor_server()
	_refresh_server_status()

func _refresh_server_status() -> void:
	if not is_inside_tree() or not is_instance_valid(_server_status): return
	var caption := L10n.text("服务器：未连接")
	var color := Color("aaaaaa")
	match PvpNet.connection_state:
		"connecting":
			caption = L10n.text("服务器：连接中…")
			color = Color("ffff44")
		"connected":
			caption = L10n.text("服务器：已连接")
			color = Color("88cc88")
		"failed":
			caption = L10n.text("服务器：连接失败")
			color = Color("d97757")
		"incompatible":
			caption = L10n.text("服务器：版本不一致")
			color = Color("d97757")
		"unconfigured":
			caption = L10n.text("服务器：未配置")
			color = Color("d97757")
	var ping := "%d ms" % PvpNet.latency_ms if PvpNet.latency_ms >= 0 else "--"
	var count := str(PvpNet.online_count) if PvpNet.connection_state == "connected" and PvpNet.online_count >= 0 else "--"
	_server_status.text = caption + "\n" + L10n.text("延迟：%s") % ping + "\n" + L10n.text("在线：%s 人") % count
	_server_status.add_theme_color_override("font_color", color)
	_refresh_buttons()
	if is_node_ready(): _layout()

func _refresh_buttons() -> void:
	for entry in buttons:
		var blocked := _startup_loading or _settings_open or is_instance_valid(_donation_window) or _entering_battle or (entry == "battle" and not PvpNet.is_server_ready())
		buttons[entry].disabled = blocked
		buttons[entry].modulate = Color(1, 1, 1, 0.4 if blocked else 1.0)
	buttons.battle.tooltip_text = L10n.text("对战") if PvpNet.is_server_ready() else L10n.text("连接服务器后才能进入游戏。")
	if PvpNet.connection_state == "incompatible": buttons.battle.tooltip_text = L10n.text("客户端与服务器版本不一致。")
	# The full English title overflows TitleScene's half-width button at 9px.
	buttons.history.caption_view.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	buttons.history.caption_view.text = "History" if L10n.is_english() else "对战记录"
	buttons.history.tooltip_text = L10n.text("对战记录")
	buttons.journal.caption_view.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	buttons.journal.caption_view.text = L10n.text("日志")
	buttons.journal.tooltip_text = L10n.text("日志")
	_refresh_news()

func _refresh_news() -> void:
	if not buttons.has("news"): return
	var count := News.unread_count()
	buttons.news.caption_view.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	buttons.news.caption_view.text = L10n.text("新闻") + ("(%d)" % mini(9,count) if count > 0 else "")
	buttons.news.tooltip_text = L10n.text("新闻")
	if count == 0:
		_news_age = 0
		buttons.news.caption_view.add_theme_color_override("font_color",Color.WHITE)
	buttons.news._layout_content()

func _process(delta: float) -> void:
	if _startup_loading or not buttons.has("news") or buttons.news.disabled or News.unread_count() == 0: return
	_news_age += delta
	# TitleScene.NewsButton: white <-> SHPX green, sin(time * 5).
	buttons.news.caption_view.add_theme_color_override("font_color",Color.WHITE.lerp(Color("33bb33"),0.5+sin(_news_age*5)/2))

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED: _refresh_server_status()

func _select(entry: StringName) -> void:
	if _startup_loading or _settings_open or is_instance_valid(_donation_window) or _entering_battle or (entry == &"battle" and not PvpNet.is_server_ready()): return
	menu_selected.emit(entry)
	if entry == &"donate":
		_donation_window = DonationWindow.new()
		_donation_window.closed.connect(func():
			_donation_window = null
			_refresh_buttons()
			buttons.donate.grab_focus())
		add_child(_donation_window)
		_refresh_buttons()
		return
	if entry == &"settings":
		_open_settings()
		return
	var destination := destinations.get(String(entry), "") as String
	if entry==&"battle" and destination==BattleEntry.PATH:
		_entering_battle = true
		buttons.battle.caption_view.text = L10n.text("正在进入...")
		_refresh_buttons()
		BattleEntry.prepare()
		while not BattleEntry.prepared and not BattleEntry.failed:
			await get_tree().process_frame
			if not is_inside_tree(): return
		if BattleEntry.failed:
			_entering_battle = false
			buttons.battle.caption_view.text = L10n.text("对战")
			_refresh_buttons()
			return
		get_tree().change_scene_to_packed(BattleEntry.scene)
		return
	if not destination.is_empty(): get_tree().change_scene_to_file(destination)

func _open_settings() -> void:
	if is_instance_valid(_settings_window): return
	# Load this optional window independently so its script cannot prevent the
	# main menu from loading. can_instantiate belongs to this resource instance.
	var settings_script: GDScript = load(SETTINGS_WINDOW_PATH) as GDScript
	if settings_script == null or not settings_script.can_instantiate(): return
	_settings_window = settings_script.new() as CanvasLayer
	if not is_instance_valid(_settings_window): return
	_settings_window.connect("closed", _settings_closed)
	_settings_window.tree_exited.connect(_settings_closed)
	add_child(_settings_window)
	if not bool(_settings_window.get("setup_finished")):
		remove_child(_settings_window)
		_settings_window.queue_free()
		return
	_settings_open = true
	_refresh_buttons()

func _settings_closed() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	_settings_open = false
	_refresh_buttons()
	buttons.settings.grab_focus()

func _layout() -> void:
	if not is_inside_tree() or not is_node_ready(): return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var factor := minf(2, minf(safe.size.x / 139, safe.size.y / 238))
	interface.scale = Vector2.ONE * factor
	interface.position = safe.position
	interface.size = safe.size / factor
	var dimensions := interface.size
	var landscape := dimensions.x > dimensions.y
	var title_size := Vector2(240, 57) if landscape else Vector2(139, 100)
	var top_region := maxf(title_size.y - 6, dimensions.y * 0.45)
	var status_height := _server_status.get_minimum_size().y
	var footer_height := maxf(44, status_height + 8)
	# Eight buttons in four rows, with the existing font sizes and safe margins.
	var gap := maxf(2, floorf((dimensions.y - top_region - 4 * BUTTON_HEIGHT - footer_height) / (6 if landscape else 8)))
	top_region = minf(top_region, dimensions.y - footer_height - 4 * (BUTTON_HEIGHT + gap))
	title_slot.size = title_size
	title_slot.position = Vector2((dimensions.x - title_size.x) / 2, 2 + (top_region - title_size.y) / 2).floor()
	# Original 20px StyledButton, 2px horizontal gap, TitleScene vertical spacing.
	var area_width := minf(234 if landscape else 133, dimensions.x - 8)
	var left := floorf((dimensions.x - area_width) / 2)
	var top := floorf(top_region + gap)
	var half := floorf(area_width / 2 - 1)
	_place(buttons.battle, Rect2(left, top, half, BUTTON_HEIGHT))
	_place(buttons.news, Rect2(left + half + 2, top, area_width - half - 2, BUTTON_HEIGHT))
	_place(buttons.history, Rect2(left, top + BUTTON_HEIGHT + gap, half, BUTTON_HEIGHT))
	_place(buttons.donate, Rect2(left + half + 2, top + BUTTON_HEIGHT + gap, area_width - half - 2, BUTTON_HEIGHT))
	_place(buttons.changes, Rect2(left, top + 2 * (BUTTON_HEIGHT + gap), half, BUTTON_HEIGHT))
	_place(buttons.journal, Rect2(left + half + 2, top + 2 * (BUTTON_HEIGHT + gap), area_width - half - 2, BUTTON_HEIGHT))
	_place(buttons.settings, Rect2(left, top + 3 * (BUTTON_HEIGHT + gap), half, BUTTON_HEIGHT))
	_place(buttons.about, Rect2(left + half + 2, top + 3 * (BUTTON_HEIGHT + gap), area_width - half - 2, BUTTON_HEIGHT))
	_version_label.size = _version_label.get_minimum_size()
	_version_label.position = (dimensions - _version_label.size - Vector2(4, 2)).floor()
	_server_status.position = Vector2(4, dimensions.y - status_height - 4).floor()
	_server_status.size = Vector2(dimensions.x - _version_label.size.x - 12, status_height)

func _place(button: DungeonMenuButton, rect: Rect2) -> void:
	button.position = rect.position
	button.size = rect.size
	button._layout_content()
