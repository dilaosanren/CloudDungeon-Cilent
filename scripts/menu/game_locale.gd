# English source messages from the locally supplied SPD 4.0.2 release.
# Presentation only: language never changes serialized item IDs or game rules.
extends RefCounted

static var _catalog: Dictionary = {}
static var _registered := false
static var _patterns: Array[Dictionary] = []

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/catalog.json"))
	return _catalog

static func is_english() -> bool:
	return TranslationServer.get_locale().begins_with("en")

static func set_language(language: String) -> void:
	if not _registered:
		var english := Translation.new()
		english.set_locale("en")
		var chinese := Translation.new()
		chinese.set_locale("zh_CN")
		for original in catalog().text:
			english.add_message(original, str(catalog().text[original]))
			chinese.add_message(original, original)
		TranslationServer.add_translation(english)
		TranslationServer.add_translation(chinese)
		_registered = true
	TranslationServer.set_locale("en" if language == "en" else "zh_CN")

static func text(original: String) -> String:
	return str(catalog().text.get(original, original)) if is_english() else original

static func english_text(original: String) -> String:
	return str(catalog().text.get(original, original))

static func english_message(key: String, fallback: String = "") -> String:
	return str(catalog().messages.get(key, fallback))

## Messages.titleCase: preserve names such as DM-300, lowercase small words.
static func title_case(value: String) -> String:
	var words := RegEx.new()
	words.compile("\\S+")
	var digits := RegEx.new()
	digits.compile("[:0-9]")
	var result := value
	var matches := words.search_all(value)
	for i in range(matches.size() - 1, -1, -1):
		var found: RegExMatch = matches[i]
		var word := found.get_string()
		if digits.sub(word.to_lower(), "", true) not in ["a", "an", "and", "of", "by", "to", "the", "x", "for"]:
			result = result.substr(0, found.get_start()) + word.left(1).to_upper() + word.substr(1) + result.substr(found.get_end())
	return result.left(1).to_upper() + result.substr(1) if not result.is_empty() else result

static func item_name(type_id: String, fallback: String) -> String:
	if not is_english(): return fallback
	return title_case(str(catalog().items.get(type_id, {}).get("name", text(fallback))))

static func item_description(type_id: String, fallback: String) -> String:
	var entry: Dictionary = catalog().items.get(type_id, {})
	return str(entry.get("description", text(fallback))) if is_english() else fallback if not fallback.is_empty() else str(entry.get("zh_description", ""))

static func gear_text(family: String, key: String, field: String, fallback: String) -> String:
	return str(catalog().gear.get(family, {}).get(key, {}).get(field, fallback)) if is_english() else fallback

static func _regex_escape(value: String) -> String:
	var result := ""
	for character in value:
		if character in "\\.^$|?*+()[]{}": result += "\\"
		result += character
	return result

static func _build_patterns() -> void:
	var tokens := RegEx.new()
	tokens.compile("%(?:\\d+\\$)?[+\\-]?\\d*(?:\\.\\d+)?[sdf]")
	for key in catalog().dynamic_keys:
		var expression := "^"
		var offset := 0
		for token in tokens.search_all(key):
			expression += _regex_escape(str(key).substr(offset, token.get_start() - offset))
			expression += "([\\s\\S]*?)"
			offset = token.get_end()
		expression += _regex_escape(str(key).substr(offset)) + "$"
		var regex := RegEx.new()
		if regex.compile(expression) == OK: _patterns.append({"key":key, "regex":regex})

static func player_names(state: Dictionary) -> Array:
	var names: Array = state.get("names", []).duplicate()
	var defaults: Array = state.get("default_names", [])
	for i in names.size():
		if i < defaults.size() and bool(defaults[i]): names[i] = render(str(names[i]))
	return names

static func render_for_match(value: String, state: Dictionary) -> String:
	var original: Array = state.get("names", [])
	var names := player_names(state)
	var result := render(value, original)
	for i in original.size():
		if names[i] != original[i]: result = result.replace(str(original[i]), str(names[i]))
	return result

## Legacy authority notices contain already-formatted text. Translate their
## known templates while preserving player-supplied names and numeric values.
static func render(value: String, player_names: Array = []) -> String:
	if not is_english(): return value
	if catalog().text.has(value): return text(value)
	# Adjacent %s fields in the action log cannot be split by a regular expression.
	for player in player_names:
		var name := str(player)
		if name.is_empty() or not value.begins_with(name): continue
		var end := RegEx.new()
		end.compile("^([\\s\\S]*)，耗时 ([0-9.]+)。$")
		var found := end.search(value.substr(name.length()))
		if found != null: return "%s: %s (time %s)." % [name, render(found.get_string(1), player_names), found.get_string(2)]
	if _patterns.is_empty(): _build_patterns()
	for entry in _patterns:
		var found: RegExMatch = entry.regex.search(value)
		if found == null: continue
		var result := text(str(entry.key))
		var token_pattern := RegEx.new()
		token_pattern.compile("%(?:\\d+\\$)?[+\\-]?\\d*(?:\\.\\d+)?[sdf]")
		var replacements := token_pattern.search_all(result)
		for i in range(replacements.size() - 1, -1, -1):
			var token: RegExMatch = replacements[i]
			var argument := found.get_string(i + 1)
			if argument not in player_names: argument = text(argument)
			result = result.substr(0, token.get_start()) + argument + result.substr(token.get_end())
		return result
	for suffix in ["的魔晶化结构粉碎了。"]:
		if value.ends_with(suffix): return text(value.trim_suffix(suffix)) + text(suffix)
	var verbs := {"装备":"Equipped ", "饮用":"Drank ", "种植":"Planted ", "阅读":"Read ", "投掷":"Threw ", "使用":"Used "}
	for prefix in verbs:
		if value.begins_with(prefix) and catalog().text.has(value.trim_prefix(prefix)):
			return str(verbs[prefix]) + text(value.trim_prefix(prefix))
	if value.begins_with("所有物品均已鉴定。"):
		return text("所有物品均已鉴定。") + " " + render(value.trim_prefix("所有物品均已鉴定。"), player_names)
	return value
