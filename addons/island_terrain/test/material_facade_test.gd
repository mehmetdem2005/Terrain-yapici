extends SceneTree

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Profile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")
const Library = preload("res://addons/island_terrain/materials/terrain_material_library.gd")

var _terrain: TerrainNode
var _generation_completed: bool = false
var _material_completed: bool = false
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
	manifest.world_seed = 77881

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

	var library := Library.create_default()
	library.backend = Library.Backend.ATLAS
	library.fallback_tile_resolution = 16
	library.detail_lod_limit = 1

	_terrain = TerrainNode.new()
	_terrain.manifest = manifest
	_terrain.memory_budget = budget
	_terrain.generation_profile = profile
	_terrain.material_library = library
	_terrain.device_profile = Budget.DeviceProfile.LOW
	_terrain.generate_preview_on_ready = true
	_terrain.collision_enabled = false
	_terrain.world_data_root = "user://material_facade/source"
	_terrain.runtime_data_root = "user://material_facade/runtime"
	_terrain.preview_generation_completed.connect(_on_generation_completed)
	_terrain.preview_generation_failed.connect(_on_generation_failed)
	_terrain.material_metadata_completed.connect(_on_material_completed)
	_terrain.material_metadata_failed.connect(_on_material_failed)
	get_root().add_child(_terrain)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _failure.is_empty():
		push_error(_failure)
		quit(1)
		return false
	if _generation_completed and _material_completed:
		_validate_material_runtime()
		return false
	if _frames > 30000:
		_fail("material facade test timed out")
	return false


func _on_generation_completed() -> void:
	_generation_completed = true


func _on_generation_failed(message: String) -> void:
	_failure = "terrain generation failed: %s" % message


func _on_material_completed(_texture: ImageTexture) -> void:
	_material_completed = true


func _on_material_failed(message: String) -> void:
	_failure = "terrain material metadata failed: %s" % message


func _validate_material_runtime() -> void:
	if _terrain.get_generation_result() == null:
		_fail("material facade has no generation result")
		return
	var texture: ImageTexture = _terrain.get_material_metadata_texture()
	if texture == null:
		_fail("material facade has no metadata texture")
		return
	var image: Image = texture.get_image()
	if image.get_width() != 65 or image.get_height() != 65:
		_fail("material facade metadata resolution is incorrect")
		return
	if _terrain.get_effective_material_backend() != Library.Backend.ATLAS:
		_fail("material facade did not use atlas backend")
		return
	if _terrain.is_material_metadata_building():
		_fail("material metadata builder remained active after completion")
		return
	if _terrain.get_material_working_memory_bytes() != 0:
		_fail("material metadata temporary memory was not released")
		return
	if _terrain.refresh_material_library() != OK:
		_fail("material library refresh failed")
		return
	print("IslandTerrain material facade tests: PASS")
	quit(0)


func _fail(message: String) -> void:
	_failure = message
