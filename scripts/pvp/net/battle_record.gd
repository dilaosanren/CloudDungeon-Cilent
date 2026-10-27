# Public, bounded battle-result schema. No identities, transport secrets or chat.
extends RefCounted
const MAX_RECORDS := 100
const ITEM_FIELDS := ["type_id", "title", "visual", "category", "quantity", "level", "cursed"]

static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value)

static func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0

static func normalize(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	for key in ["match_id", "finished_at", "map_name"]:
		if not value.get(key) is String or value[key].length() > 128: return {}
	if value.match_id.is_empty() or not whole(value.get("winner")) or int(value.winner) not in [-1,0,1]: return {}
	if not number(value.get("turns")): return {}
	for key in ["names", "default_names", "times", "selected_items"]:
		if not value.get(key) is Array or value[key].size() != 2: return {}
	var result := {"match_id":value.match_id, "finished_at":value.finished_at, "map_name":value.map_name,
		"winner":int(value.winner), "turns":float(value.turns), "names":[], "default_names":[], "times":[], "selected_items":[]}
	var count := 0
	for seat in 2:
		if not value.names[seat] is String or value.names[seat].length() > 16 or not value.default_names[seat] is bool or not number(value.times[seat]): return {}
		result.names.append(value.names[seat])
		result.default_names.append(value.default_names[seat])
		result.times.append(float(value.times[seat]))
		if not value.selected_items[seat] is Array: return {}
		var selection := []
		for item in value.selected_items[seat]:
			count += 1
			if count > 36 or not item is Dictionary: return {}
			var saved := {}
			for field in ["type_id", "title", "visual", "category"]:
				if not item.get(field) is String or item[field].length() > 128: return {}
				saved[field] = item[field]
			if not whole(item.get("quantity")) or int(item.quantity) < 1 or int(item.quantity) > 1000: return {}
			if not whole(item.get("level")) or absf(float(item.level)) > 1000 or not item.get("cursed") is bool: return {}
			saved.quantity = int(item.quantity)
			saved.level = int(item.level)
			saved.cursed = item.cursed
			selection.append(saved)
		result.selected_items.append(selection)
	return result
