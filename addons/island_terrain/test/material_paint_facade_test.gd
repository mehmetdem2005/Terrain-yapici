extends SceneTree

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Profile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")
const Library = preload("res://addons/island_terrain/materials/terrain_material_library.gd")
const PaintCommand = preload("res://addons/island_terrain/application/terrain_paint_command.gd")
const PaintTransaction = preload("res://addons/island_terrain/application/terrain_paint_transaction.gd")

var _terrain: TerrainNode
var _generation_completed: bool = false
var _material_completed: bool = false
var _validated: bool = false
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
	manifest.world_seed = 190731

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

	var unique_root: String = "user://material_paint_facade_%d" % Time.get_ticks_usec()
	_terrain = TerrainNode.new()
	_terrain.manifest = manifest
	_terrain.memory_budget = budget
	_terrain.generation_profile = profile
	_terrain.material_library = library
	_terrain.device_profile = Budget.DeviceProfile.LOW
	_terrain.generate_preview_on_ready = true
	_terrain.collision_enabled = false
	_terrain.world_data_root = "%s/source" % unique_root
	_terrain.runtime_data_root = "%s/runtime" % unique_root
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
	if _generation_completed and _material_completed and not _validated:
		_validated = true
		_validate_paint_facade()
		return false
	if _frames > 30000:
		_fail("material paint facade test timed out")
	return false


func _validate_paint_facade() -> void:
	var world_position := Vector3.ZERO
	var biome_command := PaintCommand.new()
	biome_command.tool = PaintCommand.Tool.BIOME
	biome_command.center_world = world_position
	biome_command.radius_m = 16.0
	biome_command.strength = 1.0
	biome_command.biome_id = 3
	var biome_transaction: PaintTransaction = _terrain.apply_paint_command(biome_command)
	if biome_transaction == null or biome_transaction.is_empty():
		_fail("facade biome paint produced no transaction")
		return

	var material_command := PaintCommand.new()
	material_command.tool = PaintCommand.Tool.MATERIAL
	material_command.center_world = world_position
	material_command.radius_m = 16.0
	material_command.strength = 1.0
	material_command.material_id = 4
	var material_transaction: PaintTransaction = _terrain.apply_paint_command(material_command)
	if material_transaction == null or material_transaction.is_empty():
		_fail("facade material paint produced no transaction")
		return
	if _terrain.flush_material_override_sync() != OK:
		_fail("facade override texture flush failed")
		return

	var biome_override: Dictionary = _terrain.get_biome_override_at_world(world_position)
	var material_override: Dictionary = _terrain.get_material_override_at_world(world_position)
	if int(biome_override.get("id", -1)) != 3 \
		or float(biome_override.get("strength", 0.0)) < 0.95:
		_fail("facade biome override query is incorrect")
		return
	if int(material_override.get("id", -1)) != 4 \
		or float(material_override.get("strength", 0.0)) < 0.95:
		_fail("facade material override query is incorrect")
		return
	if _terrain.get_biome_at_world(world_position) != 3:
		_fail("effective biome query ignored manual override")
		return
	var override_texture: ImageTexture = _terrain.get_material_override_texture()
	if override_texture == null \
		or override_texture.get_width() != 65 \
		or override_texture.get_height() != 65:
		_fail("facade override texture is missing or incorrectly sized")
		return
	if _terrain.get_material_working_memory_bytes() != 0:
		_fail("paint facade changed temporary material memory semantics")
		return
	if _terrain.get_material_resident_memory_bytes() != 65 * 65 * 4:
		_fail("paint facade resident override memory is incorrect")
		return

	if _terrain.apply_paint_transaction_before(material_transaction) != OK:
		_fail("facade material undo failed")
		return
	_terrain.flush_material_override_sync()
	material_override = _terrain.get_material_override_at_world(world_position)
	biome_override = _terrain.get_biome_override_at_world(world_position)
	if float(material_override.get("strength", 0.0)) > 0.01:
		_fail("facade material undo did not restore procedural state")
		return
	if int(biome_override.get("id", -1)) != 3:
		_fail("facade material undo modified biome channel")
		return

	if _terrain.apply_paint_transaction_after(material_transaction) != OK:
		_fail("facade material redo failed")
		return
	if _terrain.apply_paint_transaction_before(biome_transaction) != OK:
		_fail("facade biome undo failed")
		return
	material_override = _terrain.get_material_override_at_world(world_position)
	if int(material_override.get("id", -1)) != 4 \
		or float(material_override.get("strength", 0.0)) < 0.95:
		_fail("facade biome undo modified material channel")
		return

	print("IslandTerrain material paint facade tests: PASS")
	quit(0)


func _on_generation_completed() -> void:
	_generation_completed = true


func _on_generation_failed(message: String) -> void:
	_failure = "terrain generation failed: %s" % message


func _on_material_completed(_texture: ImageTexture) -> void:
	_material_completed = true


func _on_material_failed(message: String) -> void:
	_failure = "terrain material metadata failed: %s" % message


func _fail(message: String) -> void:
	_failure = message
