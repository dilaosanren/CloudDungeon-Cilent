# HeroClass.spritesheet / HeroSprite.updateArmor / TextureFilm, GPL-3.0-or-later.
class_name HeroAssets
extends RefCounted

const FRAME_SIZE := Vector2i(12, 15)
const ARMOR_ROWS := 7
const HERO_KEYS := ["warrior", "mage", "rogue", "huntress", "duelist", "cleric"]
const HERO_NAMES := ["战士", "法师", "盗贼", "女猎手", "决斗家", "牧师"]
const TIER_NAMES := ["无甲", "布甲", "皮甲", "链甲", "鳞甲", "板甲", "职业护甲"]
const ACTION_NAMES := {"idle": "待机", "run": "奔跑", "attack": "攻击", "zap": "施法",
	"operate": "操作", "read": "阅读", "fly": "飞行", "die": "死亡"}
static var _catalog: Dictionary = {}
static var _frames: Dictionary = {}

static func catalog() -> Dictionary:
	if _catalog.is_empty():
		# PowerShell's UTF-8 output can include a BOM.
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/heroes/source_catalog.json").trim_prefix("\ufeff"))
	return _catalog.duplicate(true)

static func frame_texture(hero: String, tier: int, column: int) -> AtlasTexture:
	if not HERO_KEYS.has(hero) or tier < 0 or tier >= ARMOR_ROWS or column < 0 or column >= 21:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = load("res://assets/heroes/source/%s.png" % hero)
	texture.region = Rect2(Vector2(column * FRAME_SIZE.x, tier * FRAME_SIZE.y), Vector2(FRAME_SIZE))
	return texture

## Cached resources are shared: callers should duplicate before editing them.
static func sprite_frames(hero: String, tier: int) -> SpriteFrames:
	if not HERO_KEYS.has(hero) or tier < 0 or tier >= ARMOR_ROWS: return null
	var key := "%s_%d" % [hero, tier]
	if not _frames.has(key):
		_frames[key] = load("res://assets/heroes/animations/%s.tres" % key)
	return _frames[key]
