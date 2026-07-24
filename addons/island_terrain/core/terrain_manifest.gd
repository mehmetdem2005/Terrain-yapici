@tool
extends Resource
class_name IslandTerrainManifest

const Constants = preload("res://addons/island_terrain/core/terrain_constants.gd")

@export var format_version: int = Constants.DATA_FORMAT_VERSION
@export var world_seed: int = 1
@export_range(512, 32768, 256) var world_size_m: int = Constants.DEFAULT_WORLD_SIZE_M
@export_range(64, 1024, 64) var region_size_m: int = Constants.DEFAULT_REGION_SIZE_M
@export var region_samples: int = Constants.DEFAULT_REGION_SAMPLES
@export_range(1.0, 4096.0, 1.0) var max_height_m: float = Constants.DEFAULT_MAX_HEIGHT_M
@export_range(-1024.0, 1024.0, 0.1) var sea_level_m: float = 0.0
@export var active_regions: Array[Vector2i] = []
@export_file("*.tres", "*.res") var material_library_path: String = ""
@export_file("*.tres", "*.res") var generator_profile_path: String = ""
@export var created_unix_time: int = 0
@export var updated_unix_time: int = 0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if format_version <= 0 or format_version > Constants.DATA_FORMAT_VERSION:
		errors.append("Unsupported terrain data format version: %d" % format_version)
	if world_size_m <= 0:
		errors.append("world_size_m must be positive")
	if region_size_m <= 0:
		errors.append("region_size_m must be positive")
	if world_size_m % region_size_m != 0:
		errors.append("world_size_m must be divisible by region_size_m")
	if not Constants.is_valid_sample_count(region_samples):
		errors.append("region_samples must be 2^n + 1")
	if max_height_m <= 0.0:
		errors.append("max_height_m must be positive")
	return errors


func region_count_axis() -> int:
	if region_size_m <= 0:
		return 0
	return ceili(float(world_size_m) / float(region_size_m))


func contains_region(coord: Vector2i) -> bool:
	var count: int = region_count_axis()
	return coord.x >= 0 and coord.y >= 0 and coord.x < count and coord.y < count


func touch_modified_time() -> void:
	var now: int = int(Time.get_unix_time_from_system())
	if created_unix_time == 0:
		created_unix_time = now
	updated_unix_time = now
