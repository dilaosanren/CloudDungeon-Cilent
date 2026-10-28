extends Node
## Public client cache/read receipts. Publishing is deliberately absent.
signal changed
signal article_received(revision: String, article: Dictionary, error: String)
const Data = preload("res://scripts/pvp/net/news_data.gd")
var known: Array[String] = []
var loading := false
var has_summary := false
var save_error := OK
var _articles: Dictionary = {}
var _seen: Array[String] = []
var _scope := ""
var _serial := 0
var _requested := ""
var _deadline := 0
var _was_ready := false

func _ready() -> void:
	set_process(false)
	PvpNet.map_submission_result.connect(_reply)
	PvpNet.news_summary_received.connect(_summary_received)
	PvpNet.server_status_changed.connect(_connection)

func _summary_received(result: Dictionary) -> void: _reply(0,result)

func _ensure_scope() -> bool:
	var endpoint: Dictionary = PvpNet._endpoint
	if not PvpNet._endpoint_loaded:
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PvpNet.SERVER_CONFIG))
		if value is Dictionary: endpoint = value
	var scope := JSON.stringify([str(endpoint.get("address","")),int(endpoint.get("port",24567)),str(endpoint.get("transport","enet"))]).sha256_text()
	if scope == _scope: return false
	_scope = scope
	known.clear()
	_articles.clear()
	_seen.clear()
	has_summary = false
	loading = false
	_serial = 0
	set_process(false)
	var config := ConfigFile.new()
	if config.load(_cache_file()) == OK:
		var list: Variant = config.get_value("news","revisions",[])
		var revisions := Data.revisions(list)
		if list is Array and revisions.size() == list.size():
			known = revisions
			has_summary = true
		var seen: Variant = config.get_value("news","seen",[])
		if seen is Array and seen.size() <= 200:
			for token in seen:
				if Data.valid_revision(token) and token not in _seen: _seen.append(token)
		var cached: Variant = config.get_value("news","articles",{})
		if cached is Dictionary:
			for token in known:
				var article := Data.normalize(cached.get(token))
				if not article.is_empty() and Data.revision(article) == token: _articles[token] = article
	return true

func _cache_file() -> String: return "user://news-%s.cfg" % _scope

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("news","revisions",known)
	config.set_value("news","seen",_seen)
	config.set_value("news","articles",_articles)
	var target := ProjectSettings.globalize_path(_cache_file())
	var temporary := target + ".tmp"
	save_error = config.save(temporary)
	if save_error == OK: save_error = DirAccess.rename_absolute(temporary,target)
	if save_error != OK: push_warning("Unable to save news reading state")

func unread_count() -> int:
	_ensure_scope()
	var count := 0
	for token in known:
		if token not in _seen: count += 1
	return count

func revisions() -> Array[String]:
	_ensure_scope()
	return known.duplicate()

func cached_article(token: String) -> Dictionary:
	_ensure_scope()
	return _articles.get(token,{}).duplicate(true)

func mark_read(token: String) -> void:
	_ensure_scope()
	if token not in known or token in _seen or not _articles.has(token): return
	_seen.append(token)
	if _seen.size() > 200: _seen.pop_front()
	_save()
	changed.emit()

func request_article(token: String = "") -> void:
	_ensure_scope()
	if not PvpNet.is_server_ready():
		article_received.emit(token,{},"服务器未连接，连接后可刷新。")
		return
	_requested = token
	_serial = PvpNet.request_news(token)
	loading = _serial > 0
	_deadline = Time.get_ticks_msec()+10000
	set_process(loading)
	changed.emit()

func _accept_summary(result: Dictionary) -> bool:
	if result.get("op") != "news_summary": return false
	var value: Variant = result.get("revisions")
	var list := Data.revisions(value)
	if not value is Array or list.size() != value.size() or result.get("feed_revision") != JSON.stringify(list).sha256_text(): return false
	known = list
	has_summary = true
	for token in _articles.keys():
		if token not in known: _articles.erase(token)
	return true

func _reply(serial: int, result: Dictionary) -> void:
	if PvpNet.server_mode: return
	_ensure_scope()
	if serial == 0:
		if _accept_summary(result):
			_save()
			changed.emit()
		return
	if serial != _serial or not loading: return
	var requested := _requested
	loading = false
	_serial = 0
	set_process(false)
	if result.has("error"):
		article_received.emit(requested,{},str(result.error))
		changed.emit()
		return
	var article := Data.normalize(result.get("article"))
	var token: String = result.get("revision","") if result.get("revision","") is String else ""
	var summary: Variant = result.get("summary")
	var empty: bool = result.get("article") is Dictionary and result.article.is_empty() and token.is_empty()
	if result.get("op") != "news_article" or (not empty and (article.is_empty() or Data.revision(article) != token or (not requested.is_empty() and requested != token))) or not summary is Dictionary:
		article_received.emit(requested,{},"新闻数据无效，请刷新重试。")
		changed.emit()
		return
	if not _accept_summary(summary) or (not empty and token not in known) or (empty and not known.is_empty()):
		article_received.emit(requested,{},"新闻数据无效，请刷新重试。")
		changed.emit()
		return
	if not empty: _articles[token] = article
	_save()
	changed.emit()
	article_received.emit(token,article,"")

func _connection() -> void:
	if PvpNet.server_mode or DisplayServer.get_name() == "headless": return
	var switched := _ensure_scope()
	var ready := PvpNet.is_server_ready()
	if ready and (not _was_ready or switched): PvpNet.request_news_summary()
	_was_ready = ready
	if loading and not PvpNet.is_server_ready():
		loading = false
		_serial = 0
		set_process(false)
		article_received.emit(_requested,{},"服务器未连接，连接后可刷新。")
	if switched: changed.emit()

func _process(_delta: float) -> void:
	if loading and Time.get_ticks_msec() >= _deadline:
		loading = false
		_serial = 0
		set_process(false)
		article_received.emit(_requested,{},"获取新闻超时，请刷新重试。")
		changed.emit()
