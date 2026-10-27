# Toolbar.btnSearch: original tool base and magnifying glass. GPL-3.0-or-later.
extends "res://scripts/ui/dungeon_wait_button.gd"

func _ready() -> void:
	super._ready()
	_base.region = Rect2(44, 0, 20, 26)
	_clock = UiAssets.get_texture("TOOLBAR_SEARCH_ICON")
	tooltip_text = L10n.text("检视") + " (E)"
