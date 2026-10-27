# Lightweight first scene. Prepare the real menu and battle caches behind black.
extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")
const MENU_PATH := "res://scenes/main_menu.tscn"
const WARRIOR_FRAMES = preload("res://assets/heroes/animations/warrior_6.tres")
var warrior: AnimatedSprite2D
var caption: Label
var retry_button: Button
var background: ColorRect
var _menu: Control
var _loading := false
var _failed := false
var _settle_frames := 0
var _transitioning := false

func _ready() -> void:
	set_process(false)
	if not OS.has_feature("mobile"): get_window().min_size = Vector2i(240,320)
	get_window().title = str(ProjectSettings.get_setting("application/config/name", "Cloud Dungeon"))
	var layer := CanvasLayer.new()
	layer.layer = 1000
	add_child(layer)
	background = ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)
	warrior = AnimatedSprite2D.new()
	warrior.sprite_frames = WARRIOR_FRAMES
	warrior.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.add_child(warrior)
	warrior.play(&"run")
	caption = Label.new()
	caption.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	caption.add_theme_font_override("font", UiAssets.get_font())
	caption.add_theme_font_size_override("font_size", 18)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.text = L10n.text("加载中...")
	background.add_child(caption)
	retry_button = Button.new()
	retry_button.text = L10n.text("重试")
	retry_button.add_theme_font_size_override("font_size", 14)
	background.add_child(retry_button)
	retry_button.hide()
	retry_button.pressed.connect(_begin_loading)
	get_viewport().size_changed.connect(_layout)
	_layout()
	# Draw the runner before requesting the larger dependency graphs.
	await get_tree().process_frame
	await get_tree().process_frame
	_begin_loading()

func _begin_loading() -> void:
	if _loading or _transitioning: return
	_failed = false
	caption.text = L10n.text("加载中...")
	retry_button.hide()
	warrior.play(&"run")
	_settle_frames = 0
	PvpNet.monitor_server()
	if BattleEntry.failed: BattleEntry.retry()
	elif not "--no-battle-prewarm" in OS.get_cmdline_user_args(): BattleEntry.prepare()
	if _menu == null:
		var status := ResourceLoader.load_threaded_get_status(MENU_PATH)
		if status not in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED] and ResourceLoader.load_threaded_request(MENU_PATH,"PackedScene",true) != OK:
			_show_failure()
			return
	_loading = true
	set_process(true)

func _process(_delta: float) -> void:
	if not _loading: return
	if BattleEntry.failed:
		_show_failure()
		return
	if _menu == null:
		var status := ResourceLoader.load_threaded_get_status(MENU_PATH)
		if status in [ResourceLoader.THREAD_LOAD_FAILED,ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_show_failure()
			return
		if status != ResourceLoader.THREAD_LOAD_LOADED: return
		var scene := ResourceLoader.load_threaded_get(MENU_PATH) as PackedScene
		if scene == null or not scene.can_instantiate():
			_show_failure()
			return
		_menu = scene.instantiate() as Control
		_menu.set_meta("startup",true)
		_menu.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(_menu)
	if not _menu.get("startup_ready"): return
	if not BattleEntry.prepared and not "--no-battle-prewarm" in OS.get_cmdline_user_args(): return
	# The real menu renders behind the opaque loading layer. Let its fonts and
	# art draw before making it interactive; no artificial loading percentage.
	_settle_frames += 1
	if _settle_frames < 3: return
	_transitioning = true
	_loading = false
	set_process(false)
	_reveal.call_deferred()

func _reveal() -> void:
	var menu := _menu
	_menu = null
	menu.reparent(get_tree().root,false)
	menu.activate_startup()
	get_tree().current_scene = menu
	queue_free()

func _show_failure() -> void:
	_loading = false
	_failed = true
	set_process(false)
	caption.text = L10n.text("加载失败，请重试。")
	retry_button.theme = UiAssets.make_theme()
	UiAssets.apply_button_style(retry_button)
	retry_button.show()
	_layout()

func _layout() -> void:
	if warrior == null: return
	var safe := ScreenLayout.safe_rect(get_viewport())
	var factor := clampf(floorf(minf(safe.size.x/72.0,safe.size.y/90.0)),2,4)
	warrior.scale = Vector2.ONE * factor
	warrior.position = safe.get_center().floor()
	caption.position = Vector2(safe.position.x+8,warrior.position.y+7.5*factor+10).floor()
	caption.size = Vector2(safe.size.x-16,48)
	retry_button.size = Vector2(112,32)
	retry_button.position = Vector2(safe.get_center().x-56,caption.position.y+caption.size.y+8).floor()
