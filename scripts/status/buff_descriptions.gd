# WndInfoBuff data derived from supplied SPD 4.0.2. GPL-3.0-or-later.
# Computed by the authority; the client receives presentation fields only.
extends RefCounted
const L10n = preload("res://scripts/menu/game_locale.gd")

static var _definitions: Dictionary = {}

static func definitions() -> Dictionary:
	if _definitions.is_empty():
		var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/status/buff_descriptions.json"))
		_definitions = catalog.definitions
	return _definitions

static func turns(value: float) -> String:
	if not is_finite(value) or value < 0: return "持续生效"
	return ("%.2f" % maxf(0, value)).trim_suffix("0").trim_suffix("0").trim_suffix(".")

static func _format(template: String, args: Array) -> String:
	var pattern := RegEx.new()
	pattern.compile("%(?:(\\d+)\\$)?([sd])")
	var result := template
	var matches := pattern.search_all(template)
	for index in range(matches.size() - 1, -1, -1):
		var part: RegExMatch = matches[index]
		var slot := index if part.get_string(1).is_empty() else int(part.get_string(1)) - 1
		var value := str(args[slot]) if slot < args.size() else "—"
		result = result.substr(0, part.get_start()) + value + result.substr(part.get_end())
	return result.replace("%%", "%")

static func build(key: String, remaining: float, values: Dictionary = {}) -> Dictionary:
	if key == "time_bubble": remaining = maxf(0, remaining)
	var source: Dictionary = definitions().get(key, {})
	if source.is_empty(): return {}
	var icon := StatusAssets.icon_id(str(source.icon))
	if icon == StatusAssets.NONE: return {}
	var count: Variant = int(maxf(0, remaining)) if is_finite(remaining) else 0
	var args: Array = [turns(remaining)]
	match key:
		"barkskin":
			count = maxi(0,ceili(remaining/3.0))
			args = [count,turns(maxf(0,remaining-3.0*(int(count)-1)))]
		"healing":
			if is_finite(remaining):
				count = ceili(maxf(0, remaining))
			else:
				count = int(values.get("healing_left", 0))
				var next := clampi(roundi(count * float(values.get("healing_percent", 0.25))) + int(values.get("healing_flat", 0)), 1, maxi(1, count))
				args = [next, count]
		"bleeding":
			count = roundi(float(values.get("bleed_level", 0)))
			args = [count]
		"corrosion":
			count = int(values.get("corrosion_damage", 1))
			args = [turns(remaining), count]
		"chill":
			args = [turns(remaining), turns((1 - maxf(0.5, 1 - remaining * 0.1)) * 100)]
		"block_shield":
			count = int(values.get("block_shield_left", 5))
			args = [int(values.get("block_shield", 0)), turns(float(values.get("block_shield_left", 5)))]
		"conserved_damage":
			count = ceili(float(values.get("conserved_damage", 0)))
			args = [count]
		"deferred_damage":
			count = int(values.get("deferred_damage", 0))
			args = [count]
		"barrier":
			count = int(values.get("shield", 0))
			args = [count]
		"opening_protection":
			count = ceili(maxf(0, remaining))
			args = [int(values.get("opening_shield", 0)), turns(remaining)]
		"rock_armor":
			count = int(values.get("rock_armor", 0))
			args = [count, 2 * (8 + 4 * int(values.get("rock_level", 0)))]
		"earthroot_armor":
			count = int(values.get("earthroot_armor", 0))
			args = [int(values.get("earthroot_block", 3)), count]
		"sungrass_heal":
			count = int(values.get("sungrass_heal", 0))
			args = [count]
		"magic_charge":
			args = [int(values.get("magic_charge_level", 0)), turns(remaining)]
		"time_bubble":
			count = int(maxf(0, remaining) + 0.001)
	var fade_base := float(source.duration)
	if key == "time_bubble": fade_base = 6
	var fade := clampf(1 - remaining / fade_base, 0, 1) if source.fade and fade_base > 0 and is_finite(remaining) else 0.0
	if key in ["earthroot_armor", "sungrass_heal"]:
		fade = clampf(1 - float(count) / maxi(1, int(values.get("max_hp", 1))), 0, 1)
	elif key == "rock_armor":
		fade = clampf(1 - float(count) / (2 * (8 + 4 * int(values.get("rock_level", 0)))), 0, 1)
	if key == "block_shield": fade = clampf(1 - float(values.get("block_shield_left", 5)) / 5, 0, 1)
	if key == "barkskin": fade = clampf(1-float(count)/8,0,1)
	var tint: Array = source.tint.duplicate()
	if key == "conserved_damage":
		tint = [1, 0, 0] if count >= 10 else [1, 1 - (count - 5) * 0.2, 0] if count >= 5 else [1, 1, 1 - count * 0.2]
	var description := _format(str(source.description), args)
	var english: Dictionary = L10n.catalog().buffs.get(key, {})
	var english_args: Array = args.map(func(value): return L10n.english_text(value) if value is String else value)
	var english_description := _format(str(english.get("description", "")), english_args)
	if key == "healing" and not is_finite(remaining):
		description = _format(str(source.get("legacy_description", source.description)), args)
		english_description = _format(str(english.get("legacy_description", english.get("description", ""))), english_args)
	# Original fear/AI text applies to monsters. Human PvP seats retain player control.
	if values.get("species", "") == "hero":
		match key:
			"amok":
				description = "狂乱会使生物不分敌我地攻击。\n\nPvP 玩家仍由本人控制行动，召唤物沿用狂乱的敌我判断。\n\n剩余时长：%s回合" % turns(remaining)
				english_description = L10n.english_text("狂乱会使生物不分敌我地攻击。\n\nPvP 玩家仍由本人控制行动，召唤物沿用狂乱的敌我判断。\n\n剩余时长：%s回合") % L10n.english_text(turns(remaining))
			"terror", "dread":
				description = ("魂飞魄散使移动速度翻倍。" if key == "dread" else "恐惧使生物试图远离施术者。") + "\n\n受伤会减少5回合的持续时间。PvP 玩家仍由本人控制行动，不会因离开视野被移出对局。\n\n剩余时长：%s回合" % turns(remaining)
				english_description = (L10n.english_text("魂飞魄散使移动速度翻倍。") if key == "dread" else L10n.english_text("恐惧使生物试图远离施术者。")) + L10n.english_text("\n\n受伤会减少5回合的持续时间。PvP 玩家仍由本人控制行动，不会因离开视野被移出对局。\n\n剩余时长：%s回合") % L10n.english_text(turns(remaining))
			"corruption":
				description = "腐化改变生物的阵营，并持续损耗生命。\n\nPvP 玩家仍由本人控制行动，效果持续至死亡。"
				english_description = L10n.english_text(description)
	return {"key":key, "icon_id":icon, "display_name":str(source.name), "description":description,
		"display_name_en":L10n.title_case(str(english.get("name", ""))), "description_en":english_description,
		"tint":tint, "kind":int(source.kind), "fade_percent":fade,
		"icon_text":str(count) if source.counter else ""}

static func for_actor(actor: WandActor) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var values := {
		"block_shield":actor.data.get("block_shield", 0), "block_shield_left":actor.data.get("block_shield_left", 5),
		"conserved_damage":actor.data.get("conserved_damage", 0), "deferred_damage":actor.data.get("deferred_damage", 0),
		"species":actor.species, "shield":actor.shield - actor.opening_shield(), "max_hp":actor.max_hp,
		"opening_shield":actor.opening_shield(),
		"healing_left":actor.data.get("healing_left", 0),
		"healing_percent":actor.data.get("healing_percent", 0.25),
		"healing_flat":actor.data.get("healing_flat", 0),
		"bleed_level":actor.data.get("bleed_level", 0),
		"corrosion_damage":maxf(float(actor.data.get("corrosion_damage", 1)), float(actor.statuses.get("corrosion_details", {}).get("strength", 1))),
		"rock_armor":actor.data.get("rock_armor", 0), "rock_level":actor.data.get("rock_level", 0),
		"earthroot_armor":actor.data.get("earthroot_armor", 0), "earthroot_block":actor.data.get("earthroot_block", 3),
		"sungrass_heal":actor.data.get("sungrass_heal", 0), "magic_charge_level":actor.data.get("magic_charge_level", 0)}
	for key in actor.statuses:
		if actor.statuses[key] is Dictionary: continue
		if float(actor.statuses[key]) <= 0 and key != "time_bubble": continue
		var info := build(str(key), float(actor.statuses[key]), values)
		if not info.is_empty(): result.append(info)
	for key in ["barrier", "rock_armor", "earthroot_armor", "sungrass_heal", "block_shield", "conserved_damage", "deferred_damage"]:
		var amount := float(values.get("shield" if key == "barrier" else key, 0))
		if key == "earthroot_armor" and actor.data.get("earthroot_pos", -1) != actor.cell: continue
		if key == "sungrass_heal" and actor.data.get("sungrass_pos", -1) != actor.cell: continue
		if amount <= 0 or actor.has_status(key): continue
		var info := build(key, INF, values)
		if not info.is_empty(): result.append(info)
	return result
