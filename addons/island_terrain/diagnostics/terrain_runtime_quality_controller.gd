@tool
extends RefCounted
class_name IslandTerrainRuntimeQualityController

const Clipmap = preload("res://addons/island_terrain/rendering/clipmap_controller.gd")
const Collision = preload("res://addons/island_terrain/physics/terrain_collision_service.gd")
const MaterialRuntime = preload("res://addons/island_terrain/materials/terrain_material_runtime.gd")

enum QualityReduction {
	FULL,
	REDUCED_DETAIL,
	REDUCED_SHADOWS,
	REDUCED_COLLISION,
}

var _clipmap: Clipmap
var _collision: Collision
var _material_runtime: MaterialRuntime
var _baseline_shadow_lods: int = 0
var _baseline_detail_lod_limit: int = 0
var _baseline_collision_radius_m: float = 64.0
var _current_level: int = QualityReduction.FULL
var _configured: bool = false


func configure(
	clipmap: Clipmap,
	collision: Collision,
	material_runtime: MaterialRuntime
) -> Error:
	if clipmap == null or collision == null or material_runtime == null:
		return ERR_INVALID_PARAMETER
	_clipmap = clipmap
	_collision = collision
	_material_runtime = material_runtime
	_baseline_shadow_lods = _clipmap.get_shadow_lod_count()
	_baseline_detail_lod_limit = _material_runtime.get_runtime_detail_lod_limit()
	_baseline_collision_radius_m = _collision.get_collision_radius_m()
	_current_level = QualityReduction.FULL
	_configured = true
	return OK


func current_level() -> int:
	return _current_level


func maximum_level() -> int:
	return QualityReduction.REDUCED_COLLISION


func set_level(value: int) -> Error:
	if not _configured:
		return ERR_UNCONFIGURED
	var target: int = clampi(value, QualityReduction.FULL, maximum_level())
	var detail_limit: int = _baseline_detail_lod_limit
	var shadow_lods: int = _baseline_shadow_lods
	var collision_radius: float = _baseline_collision_radius_m

	if target >= QualityReduction.REDUCED_DETAIL:
		detail_limit = maxi(0, _baseline_detail_lod_limit - 1)
	if target >= QualityReduction.REDUCED_SHADOWS:
		shadow_lods = 0
	if target >= QualityReduction.REDUCED_COLLISION:
		collision_radius = maxf(
			float(_collision.get_patch_size_m()),
			minf(_baseline_collision_radius_m, 64.0)
		)

	_material_runtime.set_runtime_detail_lod_limit(detail_limit)
	_clipmap.set_shadow_lod_count(shadow_lods)
	_collision.set_collision_radius_m(collision_radius)
	if target >= QualityReduction.REDUCED_COLLISION:
		_collision.trim_pool(4)
	_current_level = target
	return OK


func step_down() -> Error:
	return set_level(_current_level + 1)


func step_up() -> Error:
	return set_level(_current_level - 1)


func restore_full_quality() -> Error:
	return set_level(QualityReduction.FULL)


func refresh_baseline_from_services() -> void:
	if not _configured or _current_level != QualityReduction.FULL:
		return
	_baseline_shadow_lods = _clipmap.get_shadow_lod_count()
	_baseline_detail_lod_limit = _material_runtime.get_runtime_detail_lod_limit()
	_baseline_collision_radius_m = _collision.get_collision_radius_m()
