extends RefCounted
## Public plain-text news schema, shared by storage, cache and presentation.
const MAX_ARTICLES := 20
const MAX_TITLE := 120
const MAX_BODY := 8000
const MAX_FILE_BYTES := 1024 * 1024

static func normalize(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	for key in ["id", "published_at"]:
		if not value.get(key) is String: return {}
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
	if pattern.search(value.id) == null: return {}
	pattern.compile("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
	if pattern.search(value.published_at) == null: return {}
	var result := {"id":value.id, "published_at":value.published_at}
	for language in ["zh", "en"]:
		var localized: Variant = value.get(language)
		if not localized is Dictionary or not localized.get("title") is String or not localized.get("body") is String: return {}
		var title: String = localized.title.strip_edges()
		var body: String = localized.body.replace("\r\n","\n").replace("\r","\n").strip_edges()
		if title.is_empty() or title.length() > MAX_TITLE or title.contains("\n") or title.contains("\r") or body.is_empty() or body.length() > MAX_BODY: return {}
		for text in [title,body]:
			for index in text.length():
				if text.unicode_at(index) == 0: return {}
		result[language] = {"title":title, "body":body}
	return result

static func revision(article: Dictionary) -> String:
	return str(article.id) + ":" + JSON.stringify(article).sha256_text()

static func valid_revision(value: Variant) -> bool:
	if not value is String or value.length() > 129: return false
	var parts: PackedStringArray = value.rsplit(":",true,1)
	return parts.size() == 2 and not parts[0].is_empty() and parts[1].length() == 64 and parts[1].is_valid_hex_number()

static func revisions(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array or value.size() > MAX_ARTICLES: return result
	for token in value:
		if not valid_revision(token) or token in result: return []
		result.append(token)
	return result
