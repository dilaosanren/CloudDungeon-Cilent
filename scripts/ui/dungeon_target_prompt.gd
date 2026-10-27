# GameScene.prompt / Toast / Icons.CLOSE from SPD 4.0.2. GPL-3.0-or-later.
extends Control
const L10n = preload("res://scripts/menu/game_locale.gd")

signal cancelled

var text_label: Label
var close_button: TextureButton
var _background: Panel
var _sound: AudioStreamPlayer
var _action := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background = Panel.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.add_theme_stylebox_override("panel", UiAssets.get_style("TOAST_TR"))
	add_child(_background)
	text_label = Label.new()
	text_label.add_theme_font_override("font", UiAssets.get_font())
	text_label.add_theme_font_size_override("font_size", 8)
	UiAssets.apply_text_outline(text_label)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_label)
	var close_icon := AtlasTexture.new()
	close_icon.atlas = preload("res://assets/ui/source/icons.png")
	close_icon.region = Rect2(80, 32, 11, 11)
	close_button = TextureButton.new()
	close_button.texture_normal = close_icon
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = L10n.text("取消瞄准（Esc）")
	add_child(close_button)
	_sound = AudioStreamPlayer.new()
	_sound.stream = preload("res://assets/inventory/click.mp3")
	add_child(_sound)
	close_button.button_down.connect(func():
		close_button.self_modulate = Color(1.5, 1.5, 1.5)
		if DisplayServer.get_name() != "headless": _sound.play())
	close_button.button_up.connect(func(): close_button.self_modulate = Color.WHITE)
	close_button.pressed.connect(func(): cancelled.emit())
	hide()

func set_action(action: String) -> void:
	if _action == action: return
	_action = action
	close_button.tooltip_text = L10n.text("取消") if action == "EXAMINE" else L10n.text("取消瞄准（Esc）")
	if action == "EXAMINE": text_label.text = L10n.text("点选一个地格以获得其信息。")
	elif action == "DRINK": text_label.text = L10n.text("选择喷吐火焰的方向")
	else: text_label.text = L10n.text("选择要释放魔法的位置") if action == "ZAP" else L10n.text("选择丢出的方位")
	var text_size := text_label.get_minimum_size().ceil()
	# Toast: 4px frame margins, 2px gaps, native 11x11 close icon.
	size = Vector2(text_size.x + 25, maxf(text_size.y, 11) + 12)
	_background.size = size
	close_button.position = Vector2(size.x - 17, floorf((size.y - 11) / 2))
	close_button.size = Vector2(11, 11)
	text_label.position = Vector2(6, floorf((size.y - text_size.y) / 2))
	text_label.size = text_size

func place(safe: Rect2) -> void:
	if size.x <= 0: return
	var factor := minf(2.0, (safe.size.x - 8) / size.x)
	scale = Vector2.ONE * factor
	position = Vector2(safe.position.x + (safe.size.x - size.x * factor) / 2,
		safe.end.y - 60 * factor).floor()
