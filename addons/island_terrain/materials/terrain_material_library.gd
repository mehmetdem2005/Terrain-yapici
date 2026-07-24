@tool
extends Resource
class_name IslandTerrainMaterialLibrary

const Layer = preload("res://addons/island_terrain/materials/terrain_material_layer.gd")

enum Backend {
	COLOR_ONLY,
	ATLAS,
	TEXTURE_ARRAY,
}

@export_category("Backend")
@export_enum("Color Only", "Atlas", "Texture Array") var backend: int = Backend.ATLAS
@export var albedo_atlas: Texture2D
@export var albedo_array: Texture2DArray
@export_range(1, 8, 1) var atlas_columns: int = 4
@export_range(1, 8, 1) var atlas_rows: int = 2
@export_range(16, 128, 16) var fallback_tile_resolution: int = 32
@export var generate_fallback_atlas: bool = true
@export_range(0, 7, 1) var detail_lod_limit: int = 2
@export_range(0.0, 1.0, 0.01) var metadata_blend_strength: float = 1.0

@export_category("Layers")
@export var sand: Layer
@export var grass: Layer
@export var forest: Layer
@export var wetland: Layer
@export var rock: Layer
@export var mountain: Layer


static func create_default() -> IslandTerrainMaterialLibrary:
	var library := IslandTerrainMaterialLibrary.new()
	library._ensure_default_layers()
	library.sanitize()
	return library


func sanitize() -> void:
	backend = clampi(backend, Backend.COLOR_ONLY, Backend.TEXTURE_ARRAY)
	atlas_columns = clampi(atlas_columns, 1, 8)
	atlas_rows = clampi(atlas_rows, 1, 8)
	fallback_tile_resolution = clampi(fallback_tile_resolution, 16, 128)
	detail_lod_limit = clampi(detail_lod_limit, 0, 7)
	metadata_blend_strength = clampf(metadata_blend_strength, 0.0, 1.0)
	_ensure_default_layers()
	var max_slots: int = atlas_columns * atlas_rows
	for layer in all_layers():
		layer.sanitize(max_slots)


func all_layers() -> Array[Layer]:
	return [sand, grass, forest, wetland, rock, mountain]


func effective_backend() -> int:
	if backend == Backend.TEXTURE_ARRAY and albedo_array == null:
		return Backend.ATLAS if albedo_atlas != null or generate_fallback_atlas else Backend.COLOR_ONLY
	if backend == Backend.ATLAS and albedo_atlas == null and not generate_fallback_atlas:
		return Backend.COLOR_ONLY
	return backend


func _ensure_default_layers() -> void:
	if sand == null:
		sand = _make_layer(&"Sand", 0, Color(0.72, 0.62, 0.40), 3.0, 0.92)
	if grass == null:
		grass = _make_layer(&"Grass", 1, Color(0.25, 0.39, 0.14), 2.5, 0.94)
	if forest == null:
		forest = _make_layer(&"Forest", 2, Color(0.10, 0.24, 0.09), 3.5, 0.96)
	if wetland == null:
		wetland = _make_layer(&"Wetland", 3, Color(0.18, 0.24, 0.13), 2.0, 0.86)
	if rock == null:
		rock = _make_layer(&"Rock", 4, Color(0.36, 0.35, 0.33), 4.5, 0.82)
	if mountain == null:
		mountain = _make_layer(&"Mountain", 5, Color(0.58, 0.59, 0.57), 6.0, 0.88)


static func _make_layer(
	name: StringName,
	slot: int,
	color: Color,
	meters_per_tile: float,
	roughness_value: float
) -> Layer:
	var layer := Layer.new()
	layer.display_name = name
	layer.atlas_slot = slot
	layer.tint = color
	layer.meters_per_tile = meters_per_tile
	layer.roughness = roughness_value
	return layer
