@tool
extends RefCounted
class_name IslandTerrainHealthSnapshot

enum PressureLevel {
	NORMAL,
	SOFT,
	HARD,
	CRITICAL,
}

var timestamp_msec: int = 0
var fps: float = 0.0
var process_time_ms: float = 0.0
var physics_time_ms: float = 0.0
var static_memory_bytes: int = 0
var video_memory_bytes: int = 0
var texture_memory_bytes: int = 0
var draw_calls: int = 0
var node_count: int = 0
var region_cache_bytes: int = 0
var cached_region_count: int = 0
var dirty_region_count: int = 0
var generation_working_bytes: int = 0
var material_working_bytes: int = 0
var active_clipmap_levels: int = 0
var pending_clipmap_levels: int = 0
var active_collision_patches: int = 0
var pending_collision_builds: int = 0
var runtime_quality_level: int = 0
var pressure_level: int = PressureLevel.NORMAL
var pressure_reasons: PackedStringArray = PackedStringArray()


func terrain_owned_memory_bytes() -> int:
	return region_cache_bytes + generation_working_bytes + material_working_bytes


func has_pressure() -> bool:
	return pressure_level > PressureLevel.NORMAL


func duplicate_snapshot() -> IslandTerrainHealthSnapshot:
	var copy := IslandTerrainHealthSnapshot.new()
	copy.timestamp_msec = timestamp_msec
	copy.fps = fps
	copy.process_time_ms = process_time_ms
	copy.physics_time_ms = physics_time_ms
	copy.static_memory_bytes = static_memory_bytes
	copy.video_memory_bytes = video_memory_bytes
	copy.texture_memory_bytes = texture_memory_bytes
	copy.draw_calls = draw_calls
	copy.node_count = node_count
	copy.region_cache_bytes = region_cache_bytes
	copy.cached_region_count = cached_region_count
	copy.dirty_region_count = dirty_region_count
	copy.generation_working_bytes = generation_working_bytes
	copy.material_working_bytes = material_working_bytes
	copy.active_clipmap_levels = active_clipmap_levels
	copy.pending_clipmap_levels = pending_clipmap_levels
	copy.active_collision_patches = active_collision_patches
	copy.pending_collision_builds = pending_collision_builds
	copy.runtime_quality_level = runtime_quality_level
	copy.pressure_level = pressure_level
	copy.pressure_reasons = pressure_reasons.duplicate()
	return copy


func to_dictionary() -> Dictionary:
	return {
		"timestamp_msec": timestamp_msec,
		"fps": fps,
		"process_time_ms": process_time_ms,
		"physics_time_ms": physics_time_ms,
		"static_memory_bytes": static_memory_bytes,
		"video_memory_bytes": video_memory_bytes,
		"texture_memory_bytes": texture_memory_bytes,
		"draw_calls": draw_calls,
		"node_count": node_count,
		"region_cache_bytes": region_cache_bytes,
		"cached_region_count": cached_region_count,
		"dirty_region_count": dirty_region_count,
		"generation_working_bytes": generation_working_bytes,
		"material_working_bytes": material_working_bytes,
		"active_clipmap_levels": active_clipmap_levels,
		"pending_clipmap_levels": pending_clipmap_levels,
		"active_collision_patches": active_collision_patches,
		"pending_collision_builds": pending_collision_builds,
		"runtime_quality_level": runtime_quality_level,
		"pressure_level": pressure_level,
		"pressure_reasons": pressure_reasons,
	}
