class_name ItemVisualResource
extends Resource

## Artwork identity; this is not a gameplay item type or an identification state.
@export var key: StringName
@export var sprite_id: int = 0
@export var category: StringName
@export var atlas_kind: StringName = &"items"
@export var texture: AtlasTexture
@export var source_references := PackedStringArray()

