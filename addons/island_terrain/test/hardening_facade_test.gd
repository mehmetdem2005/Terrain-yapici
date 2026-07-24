extends SceneTree

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Profile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")
const MaterialLibrary = preload("res://addons/island_terrain/materials/terrain_material_library.gd")
const HealthPolicy = preload("res://addons/island_terrain/diagnostics/terrain_health_policy.gd")
const HealthSnapshot = preload("res://addons/island_terrain/diagnostics/terrain_health_snapshot.gd")

var _terrain: TerrainNode
var _generation_completed: bool = false
var _material_completed: bool = false
var _snapshot_signal_count: int = 0
var _failure: String = ""
var _frames: int = 0


func _init() -> void:
	call_deferred("_start_test")


func _start_test() -> void:
	var manifest := Manifest.new()
	manifest.world_size_m = 512
	manifest.region_size_m = 256
	manifest.region_samples = 65
	manifest.max_height_m = 128.0
	manifest.world_seed = 44931

	var budget := Budget.create_for_profile(Budget.DeviceProfile.LOW)
	budget.macro_height_resolution = 65
	budget.clipmap_levels = 3
	budget.base_quads = 16
	budget.shadow_lod_count = 1
	budget.frame_work_budget_ms = 0.25
	budget.collision_radius_m = 64.0

	var profile := Profile.new()
	profile.thermal_iterations = 1
	profile.river_accumulation_fraction = 0.001
	profile.river_depth_m = 3.0

	var materials := MaterialLibrary.create_default()
	materials.fallback_tile_resolution = 16
	materials.detail_lod_limit = 1

	var policy := HealthPolicy.new()
	policy.sample_interval_s = 0.25
	policy.auto_degrade_enabled = true
	policy.auto_recover_enabled = false
	policy.register_custom_performance_monitors = false
	policy.sanitize()

	_terrain = TerrainNode.new()
	_terrain.manifest = manifest
	_terrain.memory_budget = budget
	_terrain.generation_profile = profile
	_terrain.material_library = materials
	_terrain.health_policy = policy
	_terrain.auto_quality_protection_enabled = false
	_terrain.device_profile = Budget.DeviceProfile.LOW
	_terrain.generate_preview_on_ready = true
	_terrain.collision_enabled = false
	_terrain.world_data_root = "user://hardening_facade/source"
	_terrain.runtime_data_root = "user://hardening_facade/runtime"
	_terrain.preview_generation_completed.connect(_on_generation_completed)
	_terrain.preview_generation_failed.connect(_on_generation_failed)
	_terrain.material_metadata_completed.connect(_on_material_completed)
	_terrain.material_metadata_failed.connect(_on_material_failed)
	_terrain.health_snapshot_updated.connect(_on_health_snapshot)
	get_root().add_child(_terrain)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _failure.is_empty():
		push_error(_failure)
		quit(1)
		return false
	if _generation_completed and _material_completed:
		_validate_runtime_protection()
		return false
	if _frames > 30000:
		_fail("hardening facade test timed out")
	return false


func _on_generation_completed() -> void:
	_generation_completed = true


func _on_generation_failed(message: String) -> void:
	_failure = "hardening facade generation failed: %s" % message


func _on_material_completed(_texture: ImageTexture) -> void:
	_material_completed = true


func _on_material_failed(message: String) -> void:
	_failure = "hardening facade material failed: %s" % message


func _on_health_snapshot(_snapshot: HealthSnapshot) -> void:
	_snapshot_signal_count += 1


func _validate_runtime_protection() -> void:
	var snapshot: HealthSnapshot = _terrain.sample_health_now()
	if snapshot == null:
		_fail("hardening facade returned no health snapshot")
		return
	if snapshot.region_cache_bytes < 0 or snapshot.generation_working_bytes < 0:
		_fail("hardening facade returned negative memory metrics")
		return
	if snapshot.active_clipmap_levels < 0 or snapshot.pending_clipmap_levels < 0:
		_fail("hardening facade returned invalid clipmap metrics")
		return
	if snapshot.runtime_quality_level != 0:
		_fail("disabled auto protection changed runtime quality")
		return
	if _snapshot_signal_count < 1:
		_fail("manual health sample did not emit facade signal")
		return
	var copied: HealthSnapshot = _terrain.get_last_health_snapshot()
	if copied == null or copied.timestamp_msec != snapshot.timestamp_msec:
		_fail("last health snapshot API is inconsistent")
		return
	if _terrain.restore_runtime_quality() != OK:
		_fail("runtime quality restore API failed")
		return
	_terrain.set_auto_quality_protection_enabled(true)
	if Engine.is_editor_hint():
		_fail("headless runtime unexpectedly reports editor hint")
		return
	_terrain.set_auto_quality_protection_enabled(false)
	print("IslandTerrain hardening facade tests: PASS")
	quit(0)


func _fail(message: String) -> void:
	_failure = message
