@tool
extends Node3D
class_name IslandTerrain3D

const ManifestResource = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const MemoryBudget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const CoordinateSystem = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const RegionRepository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")
const ClipmapController = preload("res://addons/island_terrain/rendering/clipmap_controller.gd")
const MacroHeightSync = preload("res://addons/island_terrain/rendering/macro_height_sync.gd")
const SculptCommand = preload("res://addons/island_terrain/application/terrain_sculpt_command.gd")
const EditTransaction = preload("res://addons/island_terrain/application/terrain_edit_transaction.gd")
const EditService = preload("res://addons/island_terrain/application/terrain_edit_service.gd")
const TERRAIN_SHADER = preload("res://addons/island_terrain/rendering/shaders/island_terrain.gdshader")

signal terrain_initialized
signal preview_generation_progress(progress: float)
signal preview_generation_completed
signal terrain_edited(transaction: EditTransaction)

@export_category("Terrain Data")
@export var manifest: ManifestResource
@export_file("*.tres", "*.res") var manifest_path: String = "res://terrain_data/island_01/island_manifest.tres"
@export_dir var world_data_root: String = "res://terrain_data/island_01"
@export var runtime_data_root: String = "user://terrain_data/island_01"

@export_category("Mobile Performance")
@export_enum("Low", "Balanced", "High", "Editor Preview") var device_profile: int = 1:
	set = _set_device_profile
@export var memory_budget: MemoryBudget
@export var generate_preview_on_ready: bool = true
@export_range(0.1, 1.0, 0.01) var preview_height_scale: float = 0.72
@export_range(0, 4, 1) var runtime_shutdown_flush_limit: int = 2

@export_category("Editor Commands")
@export var rebuild_preview_requested: bool = false:
	set = _set_rebuild_preview_requested
@export var save_manifest_requested: bool = false:
	set = _set_save_manifest_requested

var _coordinate_system: CoordinateSystem
var _region_repository: RegionRepository
var _clipmap: ClipmapController
var _macro_sync: MacroHeightSync
var _edit_service: EditService
var _terrain_material: ShaderMaterial
var _height_texture: ImageTexture
var _macro_height_image: Image
var _preview_values := PackedFloat32Array()
var _preview_resolution: int = 0
var _preview_row: int = 0
var _preview_noise_a: FastNoiseLite
var _preview_noise_b: FastNoiseLite
var _preview_generation_active: bool = false
var _initialized: bool = false
var _transform_warning_emitted: bool = false


func _ready() -> void:
	set_notify_transform(true)
	call_deferred("_initialize_terrain")


func _exit_tree() -> void:
	if _region_repository == null or _region_repository.dirty_region_count() == 0:
		return
	if Engine.is_editor_hint():
		var editor_error: Error = _region_repository.flush_all()
		if editor_error != OK:
			push_error("IT-005: Failed to flush dirty terrain regions during editor shutdown")
		return
	if runtime_shutdown_flush_limit > 0:
		_region_repository.save_dirty(runtime_shutdown_flush_limit)
	var remaining: int = _region_repository.dirty_region_count()
	if remaining > 0:
		push_warning(
			"IT-W06: Runtime shutdown ended with %d unsaved terrain regions; call flush_pending_saves() at explicit save points" \
			% remaining
		)


func _process(_delta: float) -> void:
	if _preview_generation_active:
		_generate_preview_rows()
	if _region_repository != null and _region_repository.dirty_region_count() > 0:
		_region_repository.save_dirty(1)


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED:
		return
	if _coordinate_system != null:
		_coordinate_system.set_origin_world_xz(Vector2(global_position.x, global_position.z))
	if _transform_warning_emitted:
		return
	var basis: Basis = global_transform.basis
	var scale_value: Vector3 = basis.get_scale()
	var rotation_basis: Basis = basis.orthonormalized()
	var axis_aligned: bool = rotation_basis.x.is_equal_approx(Vector3.RIGHT) \
		and rotation_basis.y.is_equal_approx(Vector3.UP) \
		and rotation_basis.z.is_equal_approx(Vector3.BACK)
	if not scale_value.is_equal_approx(Vector3.ONE) or not axis_aligned:
		_transform_warning_emitted = true
		push_warning(
			"IT-W03: IslandTerrain3D supports translation but requires identity rotation and unit scale for exact heightfield coordinates"
		)


func is_initialized() -> bool:
	return _initialized


func request_preview_rebuild() -> void:
	if _initialized:
		_schedule_preview_generation()


func flush_pending_saves(max_regions: int = -1) -> Error:
	if _region_repository == null:
		return OK
	if max_regions < 0:
		return _region_repository.flush_all()
	if max_regions == 0:
		return OK
	_region_repository.save_dirty(max_regions)
	return OK if _region_repository.dirty_region_count() == 0 else ERR_BUSY


func flush_height_sync() -> Error:
	return _macro_sync.flush_all() if _macro_sync != null else ERR_UNCONFIGURED


func save_manifest() -> Error:
	if manifest == null:
		return ERR_INVALID_DATA
	var errors: PackedStringArray = manifest.validate()
	if not errors.is_empty():
		push_error("IT-001: Manifest validation failed: %s" % "; ".join(errors))
		return ERR_INVALID_DATA
	manifest.touch_modified_time()
	var target_path: String = manifest_path
	if target_path.is_empty():
		target_path = "%s/island_manifest.tres" % world_data_root.trim_suffix("/")
	if not Engine.is_editor_hint() and target_path.begins_with("res://"):
		push_error("IT-012: Runtime cannot write the packaged terrain manifest under res://")
		return ERR_UNAUTHORIZED
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(target_path.get_base_dir())
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
	return ResourceSaver.save(manifest, target_path, ResourceSaver.FLAG_COMPRESS)


func get_region(coord: Vector2i) -> RegionData:
	return _region_repository.get_or_create(coord) if _region_repository != null else null


func mark_region_dirty(coord: Vector2i) -> void:
	if _region_repository != null:
		_region_repository.mark_dirty(coord)


func apply_sculpt_command(command: SculptCommand) -> EditTransaction:
	if _edit_service == null:
		push_error("IT-022: Terrain edit service is not initialized")
		return null
	var transaction: EditTransaction = _edit_service.apply_sculpt(command)
	if transaction != null and not transaction.is_empty():
		terrain_edited.emit(transaction)
	return transaction


func apply_edit_transaction_before(transaction: EditTransaction) -> Error:
	return _edit_service.apply_transaction_before(transaction) if _edit_service != null else ERR_UNCONFIGURED


func apply_edit_transaction_after(transaction: EditTransaction) -> Error:
	return _edit_service.apply_transaction_after(transaction) if _edit_service != null else ERR_UNCONFIGURED


func height_sample_from_world_y(world_y: float) -> float:
	if manifest == null:
		return 0.0
	return clampf(world_y - global_position.y - manifest.sea_level_m, 0.0, manifest.max_height_m)


func get_height_at_world(world_position: Vector3) -> float:
	var terrain_base_y: float = global_position.y
	if _macro_height_image == null or manifest == null:
		return terrain_base_y + manifest.sea_level_m if manifest != null else terrain_base_y
	var terrain_origin := Vector2(global_position.x, global_position.z)
	var half: float = float(manifest.world_size_m) * 0.5
	var uv := Vector2(
		(world_position.x - terrain_origin.x + half) / float(manifest.world_size_m),
		(world_position.z - terrain_origin.y + half) / float(manifest.world_size_m)
	)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return terrain_base_y + manifest.sea_level_m
	var pixel := Vector2i(
		clampi(roundi(uv.x * float(_macro_height_image.get_width() - 1)), 0, _macro_height_image.get_width() - 1),
		clampi(roundi(uv.y * float(_macro_height_image.get_height() - 1)), 0, _macro_height_image.get_height() - 1)
	)
	return terrain_base_y + manifest.sea_level_m \
		+ _macro_height_image.get_pixelv(pixel).r * manifest.max_height_m


func get_normal_at_world(world_position: Vector3, sample_distance_m: float = 1.0) -> Vector3:
	var d: float = maxf(0.25, sample_distance_m)
	var h_l: float = get_height_at_world(world_position - Vector3(d, 0.0, 0.0))
	var h_r: float = get_height_at_world(world_position + Vector3(d, 0.0, 0.0))
	var h_d: float = get_height_at_world(world_position - Vector3(0.0, 0.0, d))
	var h_u: float = get_height_at_world(world_position + Vector3(0.0, 0.0, d))
	return Vector3(h_l - h_r, d * 2.0, h_d - h_u).normalized()


func intersect_ray_heightfield(
	ray_origin: Vector3,
	ray_direction: Vector3,
	max_distance_m: float = 8192.0,
	step_m: float = 4.0
) -> Dictionary:
	if not _initialized or ray_direction.is_zero_approx():
		return {}
	var direction: Vector3 = ray_direction.normalized()
	var safe_step: float = maxf(0.5, step_m)
	var previous_t: float = 0.0
	var previous_position: Vector3 = ray_origin
	var previous_signed: float = previous_position.y - get_height_at_world(previous_position)
	if previous_signed <= 0.0:
		return {
			"position": previous_position,
			"normal": get_normal_at_world(previous_position),
			"distance": 0.0,
		}
	var t: float = safe_step
	while t <= max_distance_m:
		var position: Vector3 = ray_origin + direction * t
		var signed_height: float = position.y - get_height_at_world(position)
		if previous_signed > 0.0 and signed_height <= 0.0:
			var low: float = previous_t
			var high: float = t
			for _iteration in range(10):
				var middle: float = (low + high) * 0.5
				var middle_position: Vector3 = ray_origin + direction * middle
				if middle_position.y - get_height_at_world(middle_position) > 0.0:
					low = middle
				else:
					high = middle
			var hit_distance: float = high
			var hit_position: Vector3 = ray_origin + direction * hit_distance
			hit_position.y = get_height_at_world(hit_position)
			return {
				"position": hit_position,
				"normal": get_normal_at_world(hit_position),
				"distance": hit_distance,
			}
		previous_t = t
		previous_signed = signed_height
		t += safe_step
	return {}


func _initialize_terrain() -> void:
	_ensure_manifest()
	_ensure_memory_budget()
	var errors: PackedStringArray = manifest.validate()
	if not errors.is_empty():
		push_error("IT-001: Manifest validation failed: %s" % "; ".join(errors))
		return
	var origin_xz := Vector2(global_position.x, global_position.z)
	_coordinate_system = CoordinateSystem.new(manifest, origin_xz)
	var writable_root: String = world_data_root if Engine.is_editor_hint() else runtime_data_root
	_region_repository = RegionRepository.new(world_data_root, writable_root, manifest, memory_budget)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = TERRAIN_SHADER
	_height_texture = _create_flat_height_texture()

	var sync_node: Node = get_node_or_null("__MacroHeightSync")
	if sync_node != null:
		_macro_sync = sync_node as MacroHeightSync
		if _macro_sync == null:
			push_error("IT-023: Reserved child name __MacroHeightSync is occupied")
			return
	else:
		_macro_sync = MacroHeightSync.new()
		_macro_sync.name = "__MacroHeightSync"
		add_child(_macro_sync, false, Node.INTERNAL_MODE_BACK)
	_macro_sync.configure(
		manifest,
		_coordinate_system,
		_region_repository,
		memory_budget,
		_macro_height_image,
		_height_texture
	)

	var clipmap_node: Node = get_node_or_null("__IslandClipmap")
	if clipmap_node != null:
		_clipmap = clipmap_node as ClipmapController
		if _clipmap == null:
			push_error("IT-011: Reserved child name __IslandClipmap is occupied by an incompatible node")
			return
	else:
		_clipmap = ClipmapController.new()
		_clipmap.name = "__IslandClipmap"
		add_child(_clipmap, false, Node.INTERNAL_MODE_BACK)
	_clipmap.configure(manifest, memory_budget, _terrain_material, _height_texture)
	_edit_service = EditService.new(manifest, _coordinate_system, _region_repository, _macro_sync)
	_initialized = true
	set_process(true)
	if generate_preview_on_ready:
		_schedule_preview_generation()
	terrain_initialized.emit()


func _ensure_manifest() -> void:
	if manifest != null:
		return
	if not manifest_path.is_empty() and ResourceLoader.exists(manifest_path):
		var loaded := ResourceLoader.load(
			manifest_path,
			"",
			ResourceLoader.CACHE_MODE_IGNORE
		) as ManifestResource
		if loaded != null:
			manifest = loaded
			return
	manifest = ManifestResource.new()
	manifest.world_seed = 1
	manifest.touch_modified_time()


func _ensure_memory_budget() -> void:
	if memory_budget == null:
		memory_budget = MemoryBudget.create_for_profile(device_profile)
	memory_budget.profile = clampi(device_profile, 0, 3)
	memory_budget.sanitize(Engine.is_editor_hint())


func _create_flat_height_texture() -> ImageTexture:
	var image := Image.create_empty(3, 3, true, Image.FORMAT_RF)
	image.fill(Color(0.0, 0.0, 0.0, 1.0))
	image.generate_mipmaps()
	_macro_height_image = image
	return ImageTexture.create_from_image(image)


func _schedule_preview_generation() -> void:
	_ensure_memory_budget()
	_preview_resolution = memory_budget.macro_height_resolution
	_preview_values = PackedFloat32Array()
	_preview_values.resize(_preview_resolution * _preview_resolution)
	_preview_values.fill(0.0)
	_preview_row = 0
	_preview_noise_a = FastNoiseLite.new()
	_preview_noise_a.seed = manifest.world_seed
	_preview_noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_preview_noise_a.frequency = 1.0 / maxf(256.0, float(manifest.world_size_m) * 0.23)
	_preview_noise_a.fractal_type = FastNoiseLite.FRACTAL_FBM
	_preview_noise_a.fractal_octaves = 5
	_preview_noise_a.fractal_gain = 0.48
	_preview_noise_a.fractal_lacunarity = 2.05
	_preview_noise_b = FastNoiseLite.new()
	_preview_noise_b.seed = manifest.world_seed ^ 0x5f3759df
	_preview_noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_preview_noise_b.frequency = 1.0 / maxf(128.0, float(manifest.world_size_m) * 0.11)
	_preview_noise_b.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_preview_noise_b.fractal_octaves = 4
	_preview_noise_b.fractal_gain = 0.52
	_preview_noise_b.fractal_lacunarity = 2.15
	_preview_generation_active = true
	preview_generation_progress.emit(0.0)


func _generate_preview_rows() -> void:
	var start_usec: int = Time.get_ticks_usec()
	var generation_budget_usec: int = maxi(250, int(memory_budget.frame_work_budget_ms * 700.0))
	var denominator: float = float(maxi(1, _preview_resolution - 1))
	var world_size: float = float(manifest.world_size_m)
	while _preview_row < _preview_resolution:
		var normalized_z: float = float(_preview_row) / denominator * 2.0 - 1.0
		var world_z: float = normalized_z * world_size * 0.5
		for x in range(_preview_resolution):
			var normalized_x: float = float(x) / denominator * 2.0 - 1.0
			var world_x: float = normalized_x * world_size * 0.5
			var coast_noise: float = _preview_noise_b.get_noise_2d(world_x * 0.42, world_z * 0.42)
			var radius: float = Vector2(normalized_x, normalized_z).length() * (1.0 + coast_noise * 0.16)
			var island_mask: float = 1.0 - smoothstep(0.58, 1.0, radius)
			var broad_noise: float = (_preview_noise_a.get_noise_2d(world_x, world_z) + 1.0) * 0.5
			var ridge_noise: float = 1.0 - absf(_preview_noise_b.get_noise_2d(world_x, world_z))
			var raw_height: float = island_mask * (0.12 + broad_noise * 0.58 + ridge_noise * 0.30) - 0.08
			var height_value: float = pow(clampf(raw_height, 0.0, 1.0), 1.28) * preview_height_scale
			_preview_values[_preview_row * _preview_resolution + x] = height_value
		_preview_row += 1
		if Time.get_ticks_usec() - start_usec >= generation_budget_usec:
			break
	preview_generation_progress.emit(float(_preview_row) / float(_preview_resolution))
	if _preview_row >= _preview_resolution:
		_finalize_preview_generation()


func _finalize_preview_generation() -> void:
	var image := Image.create_from_data(
		_preview_resolution,
		_preview_resolution,
		false,
		Image.FORMAT_RF,
		_preview_values.to_byte_array()
	)
	if image == null or image.is_empty():
		push_error("IT-006: Failed to create macro height image")
		_preview_generation_active = false
		return
	image.generate_mipmaps()
	_macro_height_image = image
	_height_texture = ImageTexture.create_from_image(image)
	_clipmap.set_height_texture(_height_texture)
	if _macro_sync != null:
		_macro_sync.replace_targets(_macro_height_image, _height_texture)
	_preview_values = PackedFloat32Array()
	_preview_noise_a = null
	_preview_noise_b = null
	_preview_generation_active = false
	preview_generation_progress.emit(1.0)
	preview_generation_completed.emit()


func _set_device_profile(value: int) -> void:
	device_profile = clampi(value, 0, 3)
	if is_inside_tree() and _initialized:
		memory_budget = MemoryBudget.create_for_profile(device_profile)
		_clipmap.configure(manifest, memory_budget, _terrain_material, _height_texture)
		_macro_sync.configure(
			manifest,
			_coordinate_system,
			_region_repository,
			memory_budget,
			_macro_height_image,
			_height_texture
		)
		_schedule_preview_generation()


func _set_rebuild_preview_requested(value: bool) -> void:
	rebuild_preview_requested = false
	if value and is_inside_tree():
		request_preview_rebuild()


func _set_save_manifest_requested(value: bool) -> void:
	save_manifest_requested = false
	if value and is_inside_tree():
		var error: Error = save_manifest()
		if error != OK:
			push_error("IT-007: Manifest save failed with error %d" % error)
