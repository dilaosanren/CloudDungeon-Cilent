# Current PvP equipment only; journal previews do not use discovery state.
extends RefCounted
const Availability = preload("res://scripts/pvp/item_availability.gd")
const Nature = preload("res://scripts/nature/nature_rules.gd")
const Gear = preload("res://scripts/nature/runic_gear.gd")
const ProbabilityText = preload("res://scripts/menu/runic_probability_text.gd")
const ENCHANTMENT_PREFIX := "Enchantment_"
const GLYPH_PREFIX := "Glyph_"
const CATEGORIES := ["weapon", "armor", "missile", "wand", "potion", "scroll", "seed", "stone", "exotic_potion", "enchantment", "glyph"]
const TITLES := ["近战武器", "护甲", "投掷武器", "法杖", "药剂", "卷轴", "种子", "符石", "合剂", "武器附魔", "护甲刻印"]
const L10n = preload("res://scripts/menu/game_locale.gd")

static func is_enchantment(item: InventoryItem) -> bool:
	return item != null and item.has_meta("journal_enchantment")

static func is_glyph(item: InventoryItem) -> bool:
	return item != null and item.has_meta("journal_glyph")

static func is_runic(item: InventoryItem) -> bool:
	return is_enchantment(item) or is_glyph(item)

static func create(type_id: String) -> InventoryItem:
	if type_id.begins_with(GLYPH_PREFIX):
		if type_id not in types("glyph"): return null
		var key := type_id.trim_prefix(GLYPH_PREFIX)
		var armor := InventoryCatalog.create("ClothArmor")
		var info: Dictionary = Gear.catalog().gear.armor[key]
		# WndJournal displays glyphs on cloth armor, with their native glow.
		armor.set_meta("journal_glyph",key)
		armor.metadata.glyph = key
		armor.metadata.glyph_name = info.name
		armor.metadata.glyph_description = info.description
		return armor
	if not type_id.begins_with(ENCHANTMENT_PREFIX): return InventoryCatalog.create(type_id)
	var key := type_id.trim_prefix(ENCHANTMENT_PREFIX)
	if type_id not in types("enchantment"): return null
	# WndJournal uses a worn shortsword with the original enchantment glow.
	var item := InventoryCatalog.create("WornShortsword")
	var info: Dictionary = Gear.catalog().gear.weapon[key]
	item.set_meta("journal_enchantment",key)
	item.metadata.enchantment = key
	item.metadata.enchantment_name = info.name
	item.metadata.enchantment_description = info.description
	if key == "crystal": item.metadata.crystal_uses_left = Gear.CRYSTAL_USES
	return item

static func entry_title(item: InventoryItem) -> String:
	if not is_runic(item): return item.display_name()
	var family := "armor" if is_glyph(item) else "weapon"
	var key := str(item.get_meta("journal_glyph" if is_glyph(item) else "journal_enchantment"))
	var info: Dictionary = Gear.catalog().gear[family][key]
	var noun := L10n.text("刻印") if is_glyph(item) else ""
	return L10n.title_case(L10n.gear_text(family,key,"name",str(info.name)).replace("%s",noun).strip_edges())

static func entry_description(item: InventoryItem) -> String:
	var family := "armor" if is_glyph(item) else "weapon"
	var key := str(item.get_meta("journal_glyph" if is_glyph(item) else "journal_enchantment"))
	var description := L10n.gear_text(family,key,"description",str(Gear.catalog().gear[family][key].description))
	return description+"\n\n"+ProbabilityText.description(family,key)

# SPD WndJournal.addGridItems / ScrollingGridPane.GridItem.addSecondIcon.
# Use the identified consumable symbol at its native size in the upper right.
static func add_type_icon(parent: Control, item: InventoryItem, slot: Rect2) -> void:
	if item.category not in ["potion", "scroll"] or item.icon.is_empty(): return
	var texture := ItemAssets.get_texture(item.icon, true)
	if texture == null: return
	var icon := TextureRect.new()
	icon.name = "PotionTypeIcon" if item.category == "potion" else "ScrollTypeIcon"
	icon.texture = texture
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = slot.position + Vector2(slot.size.x - texture.get_width(), 0)
	icon.size = texture.get_size()
	parent.add_child(icon)

static func types(category: String) -> Array:
	var result: Array = []
	match category:
		"weapon":
			result = MeleeRules.types()
			result.erase("MagesStaff")
			result.erase("Pickaxe")
			# As in the source catalog, group melee weapons by tier.
			var profiles: Dictionary = MeleeRules.source().profiles
			result.sort_custom(func(a: String, b: String):
				var a_tier := int(profiles[a].tier)
				var b_tier := int(profiles[b].tier)
				return a_tier < b_tier if a_tier != b_tier else a < b)
		"armor": result = ArmorRules.TYPES.duplicate()
		"missile": result = MissileRules.NORMAL_TYPES.duplicate()
		"wand": result = WandState.TYPES.duplicate()
		"potion", "exotic_potion":
			# Catalog.POTIONS / EXOTIC_POTIONS are separate in SPD. Keep
			# InventoryItem.category unchanged so shared drink/throw previews work.
			var definitions := InventoryCatalog.definitions()
			for type_id in PotionWorld.TYPES:
				var source := str(definitions[type_id].metadata.get("source",""))
				if source.begins_with("items/potions/exotic/") == (category == "exotic_potion"):
					result.append(type_id)
		"scroll": result = ScrollWorld.SCROLL_TYPES.duplicate()
		"seed": result = Nature.SEEDS.duplicate()
		"stone": result = Nature.STONES.duplicate()
		"enchantment":
			for tier in Gear.catalog().pools.weapon:
				for key in tier: result.append(ENCHANTMENT_PREFIX+str(key))
		"glyph":
			for tier in Gear.catalog().pools.armor:
				for key in tier: result.append(GLYPH_PREFIX+str(key))
	return Availability.filter_types(result)
