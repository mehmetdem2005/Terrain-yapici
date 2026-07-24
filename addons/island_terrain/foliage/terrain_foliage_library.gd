@tool
extends Resource
class_name IslandTerrainFoliageLibrary

const Layer = preload("res://addons/island_terrain/foliage/terrain_foliage_layer.gd")

@export_range(16, 128, 16) var cell_size_m: int = 32
@export_range(32.0, 256.0, 16.0) var active_radius_m: float = 96.0
@export_range(0.1, 2.0, 0.05) var density_scale: float = 1.0
@export_range(1, 4, 1) var max_cell_builds_per_frame: int = 1
@export_range(8, 256, 1) var max_active_cells: int = 64
@export_range(0, 2147483647, 1) var seed_salt: int = 73471
@export var layers: Array[Layer] = []


static func create_default() -> IslandTerrainFoliageLibrary:
	var library := IslandTerrainFoliageLibrary.new()
	var grass := Layer.new()
	grass.layer_id = &"grass"
	grass.display_name = "Grass"
	grass.allowed_biomes = PackedInt32Array([2, 3, 5])
	grass.density_per_100_m2 = 8.0
	grass.max_slope_degrees = 32.0
	grass.min_moisture = 0.10
	grass.max_instances_per_cell = 96
	grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var fern := Layer.new()
	fern.layer_id = &"fern"
	fern.display_name = "Fern"
	fern.allowed_biomes = PackedInt32Array([3, 4])
	fern.density_per_100_m2 = 2.5
	fern.max_slope_degrees = 28.0
	fern.min_moisture = 0.42
	fern.max_instances_per_cell = 40
	fern.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shrub := Layer.new()
	shrub.layer_id = &"shrub"
	shrub.display_name = "Shrub"
	shrub.allowed_biomes = PackedInt32Array([2, 3, 5])
	shrub.density_per_100_m2 = 0.8
	shrub.min_scale = 0.75
	shrub.max_scale = 1.35
	shrub.max_slope_degrees = 38.0
	shrub.max_instances_per_cell = 16
	shrub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	library.layers = [grass, fern, shrub]
	library.sanitize()
	return library


func sanitize() -> void:
	cell_size_m = clampi(cell_size_m, 16, 128)
	active_radius_m = clampf(active_radius_m, float(cell_size_m), 256.0)
	density_scale = clampf(density_scale, 0.1, 2.0)
	max_cell_builds_per_frame = clampi(max_cell_builds_per_frame, 1, 4)
	max_active_cells = clampi(max_active_cells, 8, 256)
	seed_salt = maxi(0, seed_salt)
	var clean_layers: Array[Layer] = []
	var ids: Dictionary = {}
	for layer in layers:
		if layer == null:
			continue
		layer.sanitize()
		if ids.has(layer.layer_id):
			push_warning("IT-W20: Duplicate foliage layer id ignored: %s" % layer.layer_id)
			continue
		ids[layer.layer_id] = true
		clean_layers.append(layer)
	layers = clean_layers


func estimated_max_instances_per_cell() -> int:
	var total: int = 0
	for layer in layers:
		total += layer.requested_instances(float(cell_size_m), density_scale)
	return total


func estimated_active_cell_count() -> int:
	var radius_cells: int = ceili(active_radius_m / float(cell_size_m))
	var square_count: int = (radius_cells * 2 + 1) * (radius_cells * 2 + 1)
	return mini(max_active_cells, square_count)
