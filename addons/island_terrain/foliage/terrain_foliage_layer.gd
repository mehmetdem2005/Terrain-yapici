@tool
extends Resource
class_name IslandTerrainFoliageLayer

@export var layer_id: StringName = &"grass"
@export var display_name: String = "Grass"
@export var mesh: Mesh
@export var allowed_biomes: PackedInt32Array = PackedInt32Array([2, 3, 4])
@export_range(0.0, 64.0, 0.1) var density_per_100_m2: float = 8.0
@export_range(0.1, 4.0, 0.05) var min_scale: float = 0.80
@export_range(0.1, 4.0, 0.05) var max_scale: float = 1.20
@export_range(-512.0, 2048.0, 1.0) var min_elevation_m: float = -16.0
@export_range(-512.0, 2048.0, 1.0) var max_elevation_m: float = 512.0
@export_range(0.0, 89.0, 1.0) var max_slope_degrees: float = 35.0
@export_range(0.0, 1.0, 0.01) var min_moisture: float = 0.0
@export_range(0.0, 1.0, 0.01) var max_moisture: float = 1.0
@export_range(0.0, 1.0, 0.01) var align_to_normal: float = 0.15
@export var random_yaw: bool = true
@export_range(1, 512, 1) var max_instances_per_cell: int = 128
@export var cast_shadow: GeometryInstance3D.ShadowCastingSetting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func sanitize() -> void:
	if layer_id.is_empty():
		layer_id = &"foliage"
	density_per_100_m2 = clampf(density_per_100_m2, 0.0, 64.0)
	min_scale = clampf(min_scale, 0.1, 4.0)
	max_scale = clampf(max_scale, min_scale, 4.0)
	min_elevation_m = clampf(min_elevation_m, -512.0, 2048.0)
	max_elevation_m = clampf(max_elevation_m, min_elevation_m, 2048.0)
	max_slope_degrees = clampf(max_slope_degrees, 0.0, 89.0)
	min_moisture = clampf(min_moisture, 0.0, 1.0)
	max_moisture = clampf(max_moisture, min_moisture, 1.0)
	align_to_normal = clampf(align_to_normal, 0.0, 1.0)
	max_instances_per_cell = clampi(max_instances_per_cell, 1, 512)


func accepts_sample(
	biome: int,
	elevation_m: float,
	normal: Vector3,
	moisture: float,
	foliage_mask: float
) -> bool:
	if foliage_mask <= 0.001 or allowed_biomes.find(biome) < 0:
		return false
	if elevation_m < min_elevation_m or elevation_m > max_elevation_m:
		return false
	if moisture < min_moisture or moisture > max_moisture:
		return false
	var safe_normal: Vector3 = normal.normalized() if not normal.is_zero_approx() else Vector3.UP
	var slope_degrees: float = rad_to_deg(acos(clampf(safe_normal.y, -1.0, 1.0)))
	return slope_degrees <= max_slope_degrees


func requested_instances(cell_size_m: float, density_scale: float = 1.0) -> int:
	var cell_area_m2: float = maxf(1.0, cell_size_m * cell_size_m)
	var requested: int = roundi(
		density_per_100_m2 * clampf(density_scale, 0.0, 2.0) * cell_area_m2 / 100.0
	)
	return clampi(requested, 0, max_instances_per_cell)
