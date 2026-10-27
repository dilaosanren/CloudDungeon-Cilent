# Toolbar.btnWait / Tool from SPD 4.0.2. GPL-3.0-or-later.
extends Button
const L10n = preload("res://scripts/menu/game_locale.gd")

var _base: AtlasTexture
var _clock: Texture2D

func _ready() -> void:
	text = ""
	tooltip_text = L10n.text("等待一回合（空格）")
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_base = AtlasTexture.new()
	_base.atlas = UiAssets.get_texture("TOOLBAR")
	_base.region = Rect2(24, 0, 20, 26)
	_clock = UiAssets.get_texture("TOOLBAR_WAIT_ICON")
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)

func _draw() -> void:
	if _base == null: return
	var brightness := Color(1.4, 1.4, 1.4) if is_pressed() else Color.WHITE
	draw_texture_rect(_base, Rect2(Vector2.ZERO, size), false, brightness)
	var dimensions := Vector2(16, 16)
	draw_texture_rect(_clock, Rect2(((size - dimensions) / 2).floor(), dimensions),
		false, Color(1, 1, 1, 0.4 if disabled else 1.0))
