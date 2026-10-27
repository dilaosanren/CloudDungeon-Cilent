# Original Messages formatting and RenderedTextBlock emphasis. GPL-3.0-or-later.
# Pure presentation: values come from the existing item/rule state.
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")
# Loaded explicitly by its callers, including launches before an editor scan.

static var _catalog: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/inventory/description_catalog.json"))
	return _catalog

static func message(key: String, values: Array = []) -> String:
	var template := str(catalog().messages.get(key, ""))
	if L10n.is_english(): template = L10n.english_message(key, template)
	return format_message(template, values)

static func for_item(type_id: String, suffix: String, values: Array = []) -> String:
	for prefix in catalog().item_keys.get(type_id, []):
		var key := str(prefix) + "." + suffix
		if catalog().messages.has(key): return message(key, values)
	return ""

## Support Java's indexed placeholders, ordinary placeholders and escaped %.
static func format_message(template: String, values: Array = []) -> String:
	var pattern := RegEx.new()
	pattern.compile("%(?:(\\d+)\\$)?(?:\\.(\\d+))?([dsf%])")
	var result := ""
	var offset := 0
	var sequential := 0
	for found in pattern.search_all(template):
		var token: RegExMatch = found
		result += template.substr(offset, token.get_start() - offset)
		var kind := token.get_string(3)
		if kind == "%":
			result += "%"
		else:
			var index := int(token.get_string(1)) - 1 if not token.get_string(1).is_empty() else sequential
			if token.get_string(1).is_empty(): sequential += 1
			if index >= 0 and index < values.size():
				var value: Variant = values[index]
				if kind == "d": result += str(int(value))
				elif kind == "f": result += ("%." + (token.get_string(2) if not token.get_string(2).is_empty() else "6") + "f") % float(value)
				else: result += str(value)
			else:
				# Keep a missing value visible while authoring instead of replacing
				# every placeholder with the first argument (the old wand behavior).
				result += token.get_string()
		offset = token.get_end()
	return result + template.substr(offset)

static func plain(value: String) -> String:
	return value.replace("_", "").replace("%%", "%")

static func markup(value: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("_([^_]+)_")
	return pattern.sub(value.replace("[", "[lb]").replace("%%", "%"), "[color=#ffff44]$1[/color]", true)
