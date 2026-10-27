class_name ItemCatalogResource
extends Resource

const Visual = preload("res://scripts/items/item_visual_resource.gd")
@export var upstream_version: String
@export var source_sha256: String
@export var items: Array[Visual] = []
@export var icons: Array[Visual] = []
## Every original TextureFilm slot, including unnamed and reserved artwork.
@export var item_slots: Array[AtlasTexture] = []
@export var icon_slots: Array[AtlasTexture] = []
@export var amulet_large: Texture2D
