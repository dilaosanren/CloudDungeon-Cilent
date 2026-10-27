# Scroll / InventoryScroll and twelve normal ScrollOf classes, SPD 4.0.2.
# Copyright Oleg Dolya / Evan Debenham. GPL-3.0-or-later.
class_name ScrollWorld
extends PotionWorld

const SCROLL_TYPES = ["ScrollOfIdentify", "ScrollOfLullaby", "ScrollOfMagicMapping", "ScrollOfMirrorImage",
	"ScrollOfRage", "ScrollOfRecharging", "ScrollOfRemoveCurse", "ScrollOfRetribution",
	"ScrollOfTeleportation", "ScrollOfTerror", "ScrollOfTransmutation", "ScrollOfUpgrade"]
const INVENTORY_SCROLLS = ["ScrollOfRemoveCurse", "ScrollOfTransmutation", "ScrollOfUpgrade"]
var inventory: DungeonInventory
var visited := PackedByteArray()
var catalog: Dictionary
var available_artifacts: Array[String] = []
var last_read_time := 1.0

func bind(env: DungeonEnvironment, ballistics: BallisticLevel, seed_value: int = 402) -> void:
	super.bind(env, ballistics, seed_value)
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/scrolls/source_catalog.json").trim_prefix("\ufeff"))
	visited.resize(env.terrain.size())
	var pool: Dictionary = catalog.pools.ARTIFACT
	for i in pool.types.size():
		if pool.weights[i] > 0: available_artifacts.append(pool.types[i])

func visible_creatures(hero: WandActor, hostile_only: bool = false) -> Array[WandActor]:
	var result: Array[WandActor] = []
	for a in actors:
		if a != hero and a.hp > 0 and visible[a.cell] and (not hostile_only or a.alignment != "ally"): result.append(a)
	return result

func cleansing_spirit(hero: WandActor) -> WandActor:
	for a in actors:
		if a.hp > 0 and a.species == "tormented_spirit" and adjacent(hero.cell, a.cell): return a
	return null

func selectable(scroll: InventoryItem, item: InventoryItem, hero: WandActor) -> bool:
	if inventory == null or not inventory.usable(item) or item is InventoryBag: return false
	match scroll.type_id:
		"ScrollOfUpgrade": return upgradable(item)
		"ScrollOfRemoveCurse":
			return (inventory.is_equipped(item) and hero.has_status("degrade")) or (item.category in ["weapon", "armor", "wand", "ring", "artifact", "missile"] and item.cursed) or bool(item.metadata.get("enchantment_curse", false)) or bool(item.metadata.get("glyph_curse", false))
		"ScrollOfTransmutation": return can_transmute(item) and (item != scroll or item.quantity > 1)
	return false

static func upgradable(item: InventoryItem) -> bool:
	return item.category in ["weapon", "armor", "wand", "ring", "missile"] and item.type_id not in ["Dart", "SpiritBow"] and not item.type_id.ends_with("Dart")

func apply_scroll(item: InventoryItem, hero: WandActor, selected: InventoryItem = null) -> bool:
	last_read_time = 1
	match item.type_id:
		"ScrollOfIdentify": _emit("identification", hero.cell, {"actor": hero})
		"ScrollOfLullaby":
			for a in visible_creatures(hero) + [hero]:
				a.status("drowsy", 5 * a.resistance("drowsy"))
				_emit("scroll_specks", a.cell, {"actor": a, "kind": "note", "interval": 0.3, "count": 5, "center": true})
			_emit("sound", hero.cell, {"sound": "lullaby"})
		"ScrollOfMagicMapping":
			for c in mapped.size():
				if not discoverable[c]: continue
				mapped[c] = 1
				var tile: int = environment.terrain[c]
				if tile == T.SECRET_DOOR or tile == T.SECRET_TRAP:
					environment.set_terrain(c, T.DOOR if tile == T.SECRET_DOOR else T.TRAP)
					if visible[c]:
						_emit("scroll_specks", c, {"kind": "discover", "interval": 0.1, "count": 4, "center": false})
						_emit("sound", c, {"sound": "secret"})
			_emit("mapping", hero.cell)
			_emit("spell", hero.cell, {"actor": hero, "index": 1, "color": Color.WHITE})
		"ScrollOfMirrorImage": spawn_images(hero, 2)
		"ScrollOfRage":
			for a in actors:
				if a != hero and a.hp > 0:
					a.data.beckon = hero.cell
					if a.alignment != "ally" and visible[a.cell]: a.status("amok", 5 * a.resistance("amok"))
			_emit("scroll_specks", hero.cell, {"actor": hero, "kind": "scream", "interval": 0.3, "count": 3, "center": true})
			_emit("sound", hero.cell, {"sound": "challenge"})
		"ScrollOfRecharging":
			hero.status("recharging", 30)
			_emit("scroll_specks", hero.cell, {"actor": hero, "kind": "energy", "interval": 0.0, "count": 15, "center": true})
			_emit("spell", hero.cell, {"actor": hero, "index": 2, "color": Color.WHITE})
			_emit("sound", hero.cell, {"sound": "chargeup"})
		"ScrollOfRemoveCurse":
			var spirit := cleansing_spirit(hero)
			if spirit != null:
				spirit.alignment = "ally"; spirit.data.cleansed = true; _emit("spirit_cleansed", spirit.cell, {"actor": spirit})
			elif selected != null: uncurse(selected, hero)
			else: return false
			hero.statuses.erase("degrade")
			_emit("scroll_flare", hero.cell, {"actor": hero, "rays": 6, "color": Color.WHITE})
		"ScrollOfRetribution":
			# Keep the existing area/FOV targets; only the control duration scales
			# with the caster's missing HP. No damage or caster penalty remains.
			var targets := visible_creatures(hero)
			var duration := retribution_duration(hero.hp, hero.max_hp)
			if duration > 0:
				for a in targets:
					for effect in ["blindness", "paralysis"]:
						var resisted_duration := duration * a.resistance(effect)
						if resisted_duration > 0: a.status(effect, resisted_duration)
			_emit("scroll_flash", hero.cell, {"color": Color(1, 1, 1, 128.0 / 255)})
			_emit("sound", hero.cell, {"sound": "blast"})
		"ScrollOfTeleportation":
			if not teleport_preferring_unseen(hero): last_read_time = 0
		"ScrollOfTerror":
			apply_terror(hero)
			_emit("scroll_flare", hero.cell, {"actor": hero, "rays": 5, "color": Color.RED})
		"ScrollOfUpgrade":
			if selected == null or not upgradable(selected): return false
			upgrade_item(selected, hero)
		"ScrollOfTransmutation":
			if selected == null: return false
			var result := change_item(selected)
			if result == null: return false
			var old := selected.copy_item()
			if result != selected: replace_item(selected, result)
			_emit("transmutation", hero.cell, {"actor": hero, "old": old, "new": result})
			_emit("scroll_specks", hero.cell, {"actor": hero, "kind": "change", "interval": 0.2, "count": 10, "center": false})
		_: return false
	if last_read_time > 0: hero.dispel()
	hero.update_ring_health()
	if last_read_time > 0 and hooks.has("on_scroll_used"): hooks.on_scroll_used.call(hero, item, 2.0 if item.type_id in ["ScrollOfUpgrade", "ScrollOfTransmutation"] else 1.0)
	_cleanup()
	_emit("scroll_read", hero.cell, {"actor": hero, "item": item})
	hero.changed.emit()
	return true

func apply_terror(hero: WandActor) -> void:
	for a in visible_creatures(hero, true):
		a.status("terror", 20 * a.resistance("terror"))
		a.data.fear_source_id = hero.get_instance_id()

static func retribution_duration(hp: int, max_hp: int) -> float:
	if max_hp <= 0: return 0.0
	return 10.0 * clampf(float(max_hp - hp) / max_hp, 0.0, 1.0)

func teleport_preferring_unseen(a: WandActor) -> bool:
	if "immovable" in a.properties: _emit("scroll_failed", a.cell, {"reason": "当前位置无法传送，卷轴已消耗。"}); return false
	var passable := level.passable.duplicate()
	if "large" in a.properties:
		for c in passable.size(): passable[c] &= int(_open_space(c))
	pathfinder.build_distance_map(a.cell, passable)
	var unseen: Array[int] = []; var hidden: Array[int] = []; var seen: Array[int] = []
	for c in pathfinder.size:
		if pathfinder.distance[c] == DungeonPathFinder.INFINITE or (environment.flags(c) & DungeonTerrain.SECRET) != 0 or actor_at(c) != null: continue
		if not visited[c]: unseen.append(c)
		elif visible[c]: seen.append(c)
		else: hidden.append(c)
	var choices: Array[int] = unseen if not unseen.is_empty() else hidden if not hidden.is_empty() else seen
	if choices.is_empty(): _emit("scroll_failed", a.cell, {"reason": "没有可达的传送落点，卷轴已消耗。"}); return false
	appear(a, choices[rng.randi_range(0, choices.size() - 1)])
	a.statuses.erase("roots")
	return true

func _open_space(cell: int) -> bool:
	if not level.inside_map(cell): return false
	if environment.is_solid(cell): return false
	for j in range(1, 8, 2):
		if not environment.is_solid(cell + pathfinder.circle8[j]) and not environment.is_solid(cell + pathfinder.circle8[(j + 1) % 8]) and not environment.is_solid(cell + pathfinder.circle8[(j + 2) % 8]): return true
	return false

func try_swap(hero: WandActor, ally: WandActor) -> Dictionary:
	if ally == null or ally == hero or ally.hp <= 0 or hero.hp <= 0 or ally.alignment != "ally" or not adjacent(hero.cell, ally.cell):
		return {"error":"无法与该角色换位"}
	for actor in [hero, ally]:
		if "immovable" in actor.properties: return {"error":"无法与该角色换位"}
		for effect in ["paralysis", "frost", "roots", "vertigo"]:
			if actor.has_status(effect): return {"error":"当前状态无法换位"}
	if not level.inside_map(ally.cell) or not (level.passable[ally.cell] or hero.flying and level.avoid[ally.cell]):
		return {"error":"无法移动到这里"}
	if "large" in hero.properties and not _open_space(ally.cell) or "large" in ally.properties and not _open_space(hero.cell):
		return {"error":"目标空间不足，无法换位"}
	return {"cell":ally.cell, "cost":movement_cost(hero)}

func appear(a: WandActor, cell: int) -> void:
	var old := a.cell
	move(a, cell)
	_emit("scroll_teleport", cell, {"actor": a, "from": old})

func spawn_images(hero: WandActor, count: int) -> int:
	var choices: Array[int] = []
	# Original NEIGHBOURS9 order matters when sampling respawn cells.
	for offset in pathfinder.neighbours9:
		var c: int = hero.cell + offset
		if level.inside_map(c) and level.passable[c] and actor_at(c) == null: choices.append(c)
	var spawned := 0
	while count > 0 and not choices.is_empty():
		var index := rng.randi_range(0, choices.size() - 1); var cell := choices[index]; choices.remove_at(index)
		var image := WandActor.new(); image.species = "mirror_image"; image.alignment = "ally"; image.hp = 1; image.max_hp = 1
		image.data.hero_id = hero.get_instance_id(); image.data.hero_class = RingRules.hero_class(hero)
		image.data.armor_tier = hero.sprite.armor_tier if hero.sprite is DungeonHeroSprite else int(hero.data.get("armor_tier", 0))
		image.attack_skill = 9 + hero.hero_level; image.defense_skill = 4 + hero.hero_level
		image.immunities.assign(["toxic_gas", "corrosive_gas", "burning", "ally_buff"])
		image.status("invisibility", 32767); add_actor(image, cell)
		_emit("mirror_spawn", cell, {"actor": image}); _emit("scroll_teleport", cell, {"actor": image, "from": cell})
		count -= 1; spawned += 1
	return spawned

func uncurse(item: InventoryItem, hero: WandActor) -> void:
	var procced := item.cursed or bool(item.metadata.get("enchantment_curse", false)) or bool(item.metadata.get("glyph_curse", false))
	item.cursed = false
	for pair in [["enchantment_curse", "enchantment"], ["glyph_curse", "glyph"]]:
		if item.metadata.get(pair[0], false): item.metadata.erase(pair[0]); item.metadata.erase(pair[1])
	if item.category == "wand": item.max_charges = WandState.capacity(item); item.charges = mini(item.charges, item.max_charges)
	if procced: _emit("scroll_specks", hero.cell, {"actor": hero, "kind": "shadow_up", "interval": 0.05, "count": 10, "center": false})

func upgrade_item(item: InventoryItem, hero: WandActor) -> void:
	hero.statuses.erase("degrade")
	# WndUpgrade and ScrollOfUpgrade both start UP emitters in the source.
	for i in 2: _emit("scroll_specks", hero.cell, {"actor": hero, "kind": "up", "interval": 0.2, "count": 3, "center": false})
	var was_cursed := item.cursed
	var had_curse := bool(item.metadata.get("enchantment_curse", false)) or bool(item.metadata.get("glyph_curse", false))
	if item.category == "wand": WandState.upgrade(item, rng)
	else:
		if item.category == "ring" and rng.randi_range(0, 2) == 0: item.cursed = false
		if item.category in ["weapon", "armor", "missile"]:
			var enchant := "glyph" if item.category == "armor" else "enchantment"
			if item.metadata.has(enchant):
				if item.metadata.get(enchant + "_hardened", false):
					if item.level >= 6 and rng.randf() * 10 < pow(2, item.level - 6): item.metadata[enchant + "_hardened"] = false
				elif item.metadata.get(enchant + "_curse", false):
					if rng.randi_range(0, 2) == 0: item.metadata.erase(enchant); item.metadata.erase(enchant + "_curse")
				elif item.level >= 4 and rng.randf() * 10 < pow(2, item.level - 4): item.metadata.erase(enchant)
			item.cursed = false
		item.level += 1
		if item.category == "missile":
			MissileRules.initialize(item)
			if was_cursed and item.metadata.get("enchantment_curse", false): item.cursed = true
			if MissileRules.is_weapon(item) and inventory != null: MissileRules.upgraded(item, inventory)
	var curse_removed: bool = had_curse and not item.metadata.get("enchantment_curse", false) and not item.metadata.get("glyph_curse", false)
	if curse_removed or (was_cursed and not item.cursed):
		_emit("scroll_specks", hero.cell, {"actor": hero, "kind": "shadow_up", "interval": 0.05, "count": 10 if curse_removed or item.category in ["wand", "ring"] else 5, "center": false})

func can_transmute(item: InventoryItem) -> bool:
	if item.type_id == "MagesStaff": return not str(item.metadata.get("wand_type", "")).is_empty()
	if item.category == "weapon": return item.type_id != "SpiritBow" and not (item.type_id == "Pickaxe" and hooks.get("mining_level", false))
	if item.category == "missile": return item.type_id != "Dart"
	if item.category == "artifact": return not item.unique and item.type_id not in ["HolyTome", "CloakOfShadows"]
	if item.category in ["scroll", "potion"]: return catalog.exotic_pairs.has(item.type_id) or item.type_id in catalog.exotic_pairs.values()
	return item.category in ["ring", "wand", "trinket", "seed", "stone"]

func _pick(pool_name: String, exclude: String) -> String:
	var pool: Dictionary = catalog.pools[pool_name]
	var total := 0.0
	var definitions := InventoryCatalog.definitions()
	for i in pool.types.size():
		if pool.types[i] != exclude and definitions.has(pool.types[i]): total += pool.weights[i]
	if total <= 0: return ""
	var roll := rng.randf() * total
	for i in pool.types.size():
		if pool.types[i] == exclude or not definitions.has(pool.types[i]): continue
		roll -= pool.weights[i]
		if roll < 0: return pool.types[i]
	return ""

func change_item(item: InventoryItem) -> InventoryItem:
	if not can_transmute(item): return null
	if item.type_id == "MagesStaff":
		item.metadata.wand_type = _pick("WAND", item.metadata.wand_type)
		if item.metadata.has("staff_wand"):
			var wand := InventoryCatalog.create(item.metadata.wand_type); wand.level = item.level
			WandState.initialize(wand); wand.metadata.staff_capacity_bonus = 1; wand.max_charges = WandState.capacity(wand); wand.charges = wand.max_charges
			MeleeStaff.sync_level(item,wand)
		return item
	var type := ""
	match item.category:
		"scroll", "potion":
			type = catalog.exotic_pairs.get(item.type_id, "")
			if type.is_empty():
				for original in catalog.exotic_pairs:
					if catalog.exotic_pairs[original] == item.type_id: type = original; break
		"weapon", "missile":
			if item.type_id.ends_with("Dart"):
				var darts: Array[String] = []
				for key in InventoryCatalog.definitions():
					if key.ends_with("Dart") and key != "Dart" and key != item.type_id: darts.append(key)
				if not darts.is_empty(): type = darts[rng.randi_range(0, darts.size() - 1)]
			else: type = _pick(("WEP_T" if item.category == "weapon" else "MIS_T") + str(int(item.metadata.get("tier", 1))), item.type_id)
		"ring": type = _pick("RING", item.type_id)
		"wand": type = _pick("WAND", item.type_id)
		"seed": type = _pick("SEED", item.type_id)
		"stone": type = _pick("STONE", item.type_id)
		"trinket": type = _pick("TRINKET", item.type_id)
		"artifact":
			var choices: Array[String] = []
			for candidate in available_artifacts:
				if candidate != item.type_id: choices.append(candidate)
			if not choices.is_empty(): type = choices[rng.randi_range(0, choices.size() - 1)]; available_artifacts.erase(type)
			else: type = _pick("RING", item.type_id)
	if type.is_empty(): return null
	var result := InventoryCatalog.create(type)
	if item.category in ["weapon", "missile", "ring", "wand", "artifact", "trinket"] and not item.type_id.ends_with("Dart"):
		result.level = item.level; result.cursed = item.cursed
		if item.category in ["weapon", "missile"]:
			result.quantity = item.quantity
			for key in ["enchantment", "enchantment_curse", "enchantment_hardened", "curse_infusion", "mastery_bonus", "augment", "durability", "crystal_uses_left", "crystal_shattered"]:
				if item.metadata.has(key): result.metadata[key] = item.metadata[key]
		if item.category == "wand":
			result.metadata.wand_state.resin = item.metadata.wand_state.resin
			result.metadata.wand_state.curse_infusion = item.metadata.wand_state.curse_infusion
			result.max_charges = WandState.capacity(result); result.charges = mini(item.charges, result.max_charges)
		if item.category == "artifact":
			if result.category == "ring": result.level = 2 if item.level >= 10 else 1 if item.level >= 5 else 0
			for key in ["ghost_weapon", "ghost_armor"]:
				if item.metadata.get(key) is InventoryItem: inventory.dropped.emit(item.metadata[key], inventory.hero_cell)
	return result

func replace_item(old: InventoryItem, replacement: InventoryItem) -> void:
	var slots: Array[int] = []
	for i in inventory.quickslots.size():
		if inventory.quickslots[i] == old: slots.append(i)
	if inventory.is_equipped(old):
		for slot in inventory.equipment:
			if inventory.equipment[slot] != old: continue
			if old.category == "artifact" and replacement.category == "ring": inventory.equipment[slot] = null
			else: inventory.equipment[slot] = replacement; replacement.uid = old.uid; replacement.metadata.equipped_slot = slot
		if replacement.uid.is_empty() and not inventory.collect(replacement): inventory.dropped.emit(replacement, inventory.hero_cell)
	else:
		inventory.detach(old, old.quantity if old.category == "missile" and not old.type_id.ends_with("Dart") else 1, false)
		if not inventory.collect(replacement): inventory.dropped.emit(replacement, inventory.hero_cell)
	if replacement.quantity == 0:
		for existing in inventory.all_items():
			if existing.similar(replacement): replacement = existing; break
	for i in slots:
		if not replacement.default_action.is_empty() and inventory.contains(replacement): inventory.set_quickslot(i, replacement)
	inventory.refresh_equipment()

func step_turn() -> void:
	var sleepers: Array[WandActor] = []
	for a in actors:
		if a.has_status("drowsy") and a.statuses.drowsy <= 1:
			a.data.sleep_interrupted = false
			sleepers.append(a)
		if a.has_status("magical_sleep") and a.alignment == "ally":
			a.heal(1)
			if a.hp == a.max_hp: a.statuses.erase("magical_sleep")
	super.step_turn()
	for a in sleepers:
		if a.hp > 0 and not a.data.get("sleep_interrupted", false) and (a.species != "hero" and a.alignment != "ally" or a.hp < a.max_hp): a.status("magical_sleep", INF)
	for a in actors.duplicate():
		if a.hp > 0 and a.species == "mirror_image": _mirror_turn(a)

func _mirror_turn(a: WandActor) -> void:
	var hero := _actor_by_id(int(a.data.hero_id))
	if hero == null or hero.hp <= 0: a.hp = 0; _cleanup(); return
	a.data.hero_class = RingRules.hero_class(hero)
	a.data.armor_tier = hero.sprite.armor_tier if hero.sprite is DungeonHeroSprite else int(hero.data.get("armor_tier", 0))
	var item: InventoryItem = hero.data.get("melee_weapon")
	a.attack_skill = int((9 + hero.hero_level) * RingRules.accuracy(hero) * MeleeRules.accuracy(item, a))
	var base_evasion := 4 + hero.hero_level
	a.defense_skill = int((base_evasion + int(base_evasion * RingRules.evasion(hero))) / 2)
	# MirrorImage.attackDelay reads the hero's current weapon and furor ring.
	var remaining := float(a.data.get("mirror_action_delay", 0)) - 1.0
	for attempt in 64:
		if remaining > -0.00001 or a.hp <= 0: break
		var cost := _mirror_act(a, hero, item)
		remaining += maxf(0.01, cost / a.action_time_scale())
	a.data.mirror_action_delay = maxf(0, remaining)
	_cleanup()

func _mirror_act(a: WandActor, hero: WandActor, item: InventoryItem) -> float:
	var target := _enemy(a, 8)
	if target == null or a.has_status("magical_sleep") or a.has_status("paralysis") or a.has_status("frost"): return 1.0
	if a.has_status("terror"):
		var retreat := retreat_step(a)
		if retreat >= 0: move(a, retreat)
		return 1.0
	if _mirror_can_attack(a, target, item):
		_emit("mirror_attack", target.cell, {"actor": a, "target": target})
		if rng.randf() * a.effective_accuracy() >= rng.randf() * target.effective_evasion():
			a.statuses.erase("invisibility")
			_mirror_hit(a, target, hero, item)
		else: _emit("dodge", target.cell, {"actor": target})
		return MeleeRules.delay(item, hero)
	_move_toward(a, target.cell)
	return 1.0

func _mirror_can_attack(a: WandActor, target: WandActor, _item: InventoryItem) -> bool:
	return adjacent(a.cell, target.cell)

func _mirror_hit(a: WandActor, target: WandActor, hero: WandActor, item: InventoryItem) -> void:
	# Weapon.damageRoll(image), or Hero.damageRoll() when unarmed; round up half.
	var damage := MeleeRules.damage_roll(item, a if item != null else hero, rng)
	target.interrupt_healing()
	target.damage(int((damage + 1) / 2), "physical")
	target.data.enemy = a

func _cleanup() -> void:
	super._cleanup()
	for a in actors:
		if a.has_status("terror") and a.data.has("fear_source_id"):
			var source := _actor_by_id(int(a.data.fear_source_id))
			if source == null or source.hp <= 0: a.statuses.erase("terror")

func dispose() -> void:
	inventory = null
	super.dispose()

func _actor_by_id(id: int) -> WandActor:
	for a in actors:
		if a.get_instance_id() == id: return a
	return null

func _move_toward(a: WandActor, target: int) -> void:
	var mask := level.passable.duplicate()
	for other in actors:
		if other.hp > 0: mask[other.cell] = 0
	var step := pathfinder.get_step(a.cell, target, mask)
	if step >= 0 and actor_at(step) == null: move(a, step)

## Small arena host for observing fear/amok/beckoning; production PvP controls
## can call retreat_step instead of forcing AI on player-controlled characters.
func retreat_step(a: WandActor) -> int:
	var source := _actor_by_id(int(a.data.get("fear_source_id", 0)))
	if source == null or source.hp <= 0: a.statuses.erase("terror"); return -1
	var mask := level.passable.duplicate(); mask[a.cell] = 1
	var step := pathfinder.get_step_back(a.cell, source.cell, 4, mask, false)
	while step >= 0 and actor_at(step) != null:
		mask[step] = 0; step = pathfinder.get_step_back(a.cell, source.cell, 4, mask, false)
	return step

func act_demo_enemies(hero: WandActor) -> void:
	for a in actors.duplicate():
		if a == hero or a.hp <= 0 or a.alignment == "ally" or a.has_status("magical_sleep") or a.has_status("paralysis") or a.has_status("frost"): continue
		if a.has_status("terror"):
			var step := retreat_step(a)
			if step >= 0: move(a, step)
			continue
		var target := hero
		if a.has_status("amok"):
			for other in actors:
				if other != a and other != hero and other.hp > 0 and (target == hero or distance(a.cell, other.cell) < distance(a.cell, target.cell)): target = other
		if adjacent(a.cell, target.cell):
			_emit("mirror_attack", target.cell, {"actor": a, "target": target}); target.damage(S.normal_int(rng, 1, 4), "physical")
		else: _move_toward(a, int(a.data.get("beckon", target.cell)) if not a.has_status("amok") else target.cell)
	_cleanup()
