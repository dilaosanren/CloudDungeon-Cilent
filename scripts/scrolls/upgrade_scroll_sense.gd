# Owner-only ground-item sensing. Never return the rest of a hidden heap.
extends RefCounted

static func cells_for(hero: WandActor, ground: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if hero == null or not hero.data.get("upgrade_scroll_sense", false): return result
	for cell in ground:
		for item: InventoryItem in ground[cell]:
			if item.type_id == "ScrollOfUpgrade" and item.quantity > 0:
				result.append(int(cell))
				break
	result.sort()
	return result
