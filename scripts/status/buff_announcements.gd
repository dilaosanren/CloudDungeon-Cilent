# Char.add(Buff) / CharSprite status colors, SPD 4.0.2, GPL-3.0-or-later.
# Announce named gameplay states once; scheduler markers remain silent.
class_name BuffAnnouncements
extends RefCounted
const Info = preload("res://scripts/status/buff_descriptions.gd")
const L10n = preload("res://scripts/menu/game_locale.gd")
const SILENT := ["shuriken_cooldown", "opening_protection"]

static func is_announced(effect: String) -> bool:
	return effect not in SILENT and Info.definitions().has(effect)

static func label(effect: String) -> String:
	var info: Dictionary = Info.definitions().get(effect, {})
	if info.is_empty(): return ""
	if L10n.is_english():
		var english: Dictionary = L10n.catalog().buffs.get(effect, {})
		return L10n.title_case(str(english.get("name", L10n.text(str(info.name)))))
	return str(info.name)

static func color(effect: String) -> Color:
	var kind := int(Info.definitions().get(effect, {}).get("kind", 0))
	return Color("00ff00") if kind > 0 else Color("ff8800") if kind < 0 else Color("ffff00")

static func show(sprite: Node2D, effect: String) -> CombatFloatingText:
	if not is_announced(effect) or not is_instance_valid(sprite) or not sprite.is_visible_in_tree(): return null
	if sprite is DungeonHeroSprite:
		return sprite.show_status_with_icon(color(effect), label(effect), CombatTextAssets.Icon.NO_ICON, true)
	var layer := CombatTextLayer.for_actor(sprite)
	if layer == null: return null
	var body := sprite.get("body") as Node2D
	var anchor := layer.to_local(sprite.to_global(Vector2(0, body.position.y if body != null else -13)))
	var key := Vector2i((layer.to_local(sprite.global_position) / 16).floor())
	return layer.show_status(anchor, label(effect), color(effect), CombatTextAssets.Icon.NO_ICON, key, true, true)
