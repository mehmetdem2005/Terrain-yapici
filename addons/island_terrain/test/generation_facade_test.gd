extends SceneTree

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Profile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")

var _terrain: TerrainNode
var _completed: bool = false
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
	manifest.world_seed = 19077

	var budget := Budget.create_for_profile(Budget.DeviceProfile.LOW)
	budget.macro_height_resolution = 65
	budget.clipmap_levels = 3
	budget.base_quads = 16
	budget.shadow_lod_count = 0
	budget.frame_work_budget_ms = 0.25

	var profile := Profile.new()
	profile.thermal_iterations = 1
	profile.river_accumulation_fraction = 0.001
	profile.river_depth_m = 3.0

	_terrain = TerrainNode.new()
	_terrain.manifest = manifest
	_terrain.memory_budget = budget
	_terrain.generation_profile = profile
	_terrain.device_profile = Budget.DeviceProfile.LOW
	_terrain.generate_preview_on_ready = true
	_terrain.collision_enabled = false
	_terrain.world_data_root = "user://generation_facade/source"
	_terrain.runtime_data_root = "user://generation_facade/runtime"
	_terrain.preview_generation_completed.connect(_on_completed)
	_terrain.preview_generation_failed.connect(_on_failed)
	get_root().add_child(_terrain)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _failure.is_empty():
		push_error(_failure)
		quit(1)
		return false
	if _completed:
		_validate_result()
		return false
	if _frames > 30000:
		push_error("generation facade test timed out")
		quit(1)
	return false


func _on_completed() -> void:
	_completed = true


func _on_failed(message: String) -> void:
	_failure = "generation facade failed: %s" % message


func _validate_result() -> void:
	var result = _terrain.get_generation_result()
	if result == null:
		_fail("generation facade returned no result")
		return
	if result.resolution != 65:
		_fail("generation facade ignored the mobile macro resolution")
		return
	if not result.validate().is_empty():
		_fail("generation facade returned invalid metadata")
		return
	var center := Vector3.ZERO
	var center_height: float = _terrain.get_height_at_world(center)
	if center_height <= _terrain.global_position.y + _terrain.manifest.sea_level_m:
		_fail("generated island centre did not rise above sea level")
		return
	var biome: int = _terrain.get_biome_at_world(center)
	if biome < 0:
		_fail("generation facade biome query failed")
		return
	var moisture: float = _terrain.get_moisture_at_world(center)
	if moisture < 0.0 or moisture > 1.0:
		_fail("generation facade moisture query is out of range")
		return
	if _terrain.is_generation_running():
		_fail("generation controller remained active after completion")
		return
	print("IslandTerrain generation facade tests: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
