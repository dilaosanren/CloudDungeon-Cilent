extends RefCounted
## Client-owned summaries. No account, upload, replay, or server-side storage.
const FILE := "user://battle_history.json"
static var _loaded := false
static var _records: Array[Dictionary] = []
static var _active: Dictionary = {}
static var save_error := OK

static func records() -> Array[Dictionary]:
	_load()
	return _records.duplicate(true)

static func _load() -> void:
	if _loaded: return
	_loaded = true
	if not FileAccess.file_exists(FILE): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if not parsed is Dictionary or parsed.get("version") != 1 or not parsed.get("records") is Array:
		save_error = ERR_FILE_CORRUPT
		return
	for record in parsed.records:
		if not _valid_record(record): continue
		record.seat = int(record.seat)
		if not record.get("default_names") is Array or record.default_names.size() != 2:
			record.default_names = [false, false]
		for selection in record.selected_items:
			for item in selection:
				item.level = int(item.get("level", 0))
				item.quantity = int(item.get("quantity", 1))
		_records.append(record)

static func _valid_record(record: Variant) -> bool:
	if not record is Dictionary or str(record.get("match_id", "")).is_empty(): return false
	if int(record.get("seat", -1)) not in [0, 1]: return false
	for key in ["names", "times", "selected_items"]:
		if not record.get(key) is Array or record[key].size() != 2: return false
	if record.get("outcome") not in ["win", "loss", "draw", "interrupted"]: return false
	for name in record.names:
		if not name is String: return false
	for time in record.times + [record.get("turns")]:
		if not (time is float or time is int) or not is_finite(float(time)) or float(time) < 0: return false
	for selection in record.selected_items:
		if not selection is Array: return false
		for item in selection:
			if not item is Dictionary or not item.get("type_id") is String: return false
	return true

static func observe(state: Dictionary) -> void:
	var phase := int(state.get("phase", -1))
	if phase not in [PvpProtocol.Phase.BATTLE, PvpProtocol.Phase.FINISHED]: return
	if not state.has("times") or not state.has("selected_items"): return
	var seat := int(state.get("seat", -1))
	if seat not in [0, 1] or str(state.get("match_id", "")).is_empty(): return
	if state.get("names", []).size() != 2 or state.times.size() != 2 or state.selected_items.size() != 2: return
	_active = {"match_id":str(state.match_id), "seat":seat, "names":state.names.duplicate(),
		"default_names":state.get("default_names", [false, false]).duplicate(),
		"turns":float(state.get("now", 0)), "times":state.times.duplicate(),
		"selected_items":state.selected_items.duplicate(true)}
	if phase == PvpProtocol.Phase.FINISHED:
		var winner := int(state.get("winner", -1))
		_active.outcome = "draw" if winner < 0 else "win" if winner == seat else "loss"
		_commit()

static func interrupted() -> void:
	if _active.is_empty(): return
	# A local exit/lost connection cannot prove the authoritative winner.
	_active.outcome = "interrupted"
	_commit()

static func _commit() -> void:
	_load()
	var record := _active.duplicate(true)
	_active.clear()
	record.finished_at = Time.get_datetime_string_from_system(false, true)
	for existing in _records:
		if existing.match_id == record.match_id and int(existing.seat) == int(record.seat):
			# Repeated final/timer snapshots never duplicate a match. A real result
			# may replace an earlier interrupted summary of the same match.
			if existing.outcome != "interrupted": return
			_records.erase(existing)
			break
	_records.push_front(record)
	_save()

static func _save() -> void:
	# Keep the last intact file if opening/writing the replacement fails.
	if save_error == ERR_FILE_CORRUPT: return
	var temporary := FILE + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		save_error = FileAccess.get_open_error()
		return
	file.store_string(JSON.stringify({"version":1, "records":_records}))
	file.flush()
	save_error = file.get_error()
	file.close()
	if save_error != OK: return
	save_error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(FILE))
