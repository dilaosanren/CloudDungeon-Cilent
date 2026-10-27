## PvP presentation model: no experience, levels or gameplay buff rules.
class_name DungeonStatus
extends RefCounted

signal changed

var hero_class: String = "warrior"
var armor_tier: int = 0
var health: int = 100
var max_health: int = 100
var shielding: int = 0
var incoming_dot: int = 0
var _buffs: Array[StatusBuff] = []

func set_appearance(hero: String, tier: int) -> bool:
	if not HeroAssets.HERO_KEYS.has(hero) or tier < 0 or tier >= HeroAssets.ARMOR_ROWS: return false
	hero_class = hero
	armor_tier = tier
	changed.emit()
	return true

func set_vitals(hp: int, maximum: int, shield: int = 0, dot: int = 0) -> void:
	max_health = maxi(1, maximum)
	health = clampi(hp, 0, max_health)
	shielding = maxi(0, shield)
	incoming_dot = maxi(0, dot)
	changed.emit()

func health_text() -> String:
	return "%d/%d" % [health, max_health] if shielding == 0 else "%d+%d/%d" % [health, shielding, max_health]

## StatusPane: shield is underneath HP; normalize both when their sum exceeds HT.
func bar_fractions() -> Vector3:
	var denominator := float(maxi(max_health, health + shielding))
	return Vector3(health / denominator, (health + shielding) / denominator,
		minf(incoming_dot / denominator, (health + shielding) / denominator))

## Same key updates in place, preserving BuffIndicator's LinkedHashMap ordering.
## Copy boundaries ensure external data edits cannot leave the HUD stale.
func put_buff(buff: StatusBuff) -> bool:
	if buff == null or buff.key.is_empty() or buff.icon_id < 0 or buff.icon_id > StatusAssets.NONE: return false
	for i in _buffs.size():
		if _buffs[i].key == buff.key:
			_buffs[i] = buff.copy()
			changed.emit()
			return true
	_buffs.append(buff.copy())
	changed.emit()
	return true

func remove_buff(key: String) -> void:
	for i in _buffs.size():
		if _buffs[i].key == key:
			_buffs.remove_at(i)
			changed.emit()
			return

func clear_buffs() -> void:
	_buffs.clear()
	changed.emit()

func buffs() -> Array[StatusBuff]:
	var result: Array[StatusBuff] = []
	for buff in _buffs: result.append(buff.copy())
	return result

func find_buff(key: String) -> StatusBuff:
	for buff in _buffs:
		if buff.key == key: return buff.copy()
	return null
