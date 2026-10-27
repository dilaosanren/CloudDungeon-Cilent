# BuffIndicator / BuffIcon visual data. GPL-3.0-or-later.
class_name StatusBuff
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")

var key: String
var icon_id: int = 127
var display_name: String = ""
var description: String = ""
var tint := Color.WHITE
## Positive = 1, neutral = 0, negative = -1 (affects original bitmap counters).
var kind: int = 0
## 0 = unfaded; 1 = completely covered by the original grey elapsed overlay.
var fade_percent: float = 0.0
## Empty means grey overlay, otherwise the large icon displays this text instead.
var icon_text: String = ""

func copy() -> StatusBuff:
	var result := StatusBuff.new()
	result.key = key
	result.icon_id = icon_id
	result.display_name = display_name
	result.description = description
	result.tint = tint
	result.kind = kind
	result.fade_percent = clampf(fade_percent, 0, 1)
	result.icon_text = icon_text
	return result

# Wire fields deliberately contain no actor data, targets, or random state.
static func from_dict(value: Dictionary) -> StatusBuff:
	var result := StatusBuff.new()
	result.key = str(value.get("key", ""))
	result.icon_id = int(value.get("icon_id", 127))
	result.display_name = str(value.get("display_name", ""))
	result.description = str(value.get("description", ""))
	if L10n.is_english():
		result.display_name = str(value.get("display_name_en", L10n.text(result.display_name)))
		result.description = str(value.get("description_en", L10n.render(result.description)))
	var color: Array = value.get("tint", [1, 1, 1])
	result.tint = Color(float(color[0]), float(color[1]), float(color[2]))
	result.kind = int(value.get("kind", 0))
	result.fade_percent = clampf(float(value.get("fade_percent", 0)), 0, 1)
	result.icon_text = str(value.get("icon_text", ""))
	return result
