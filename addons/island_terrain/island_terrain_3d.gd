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
const CollisionService = preload("res://addons/island_terrain/physics/terrain_collision_service.gd")
const SculptCommand = preload("res://addons/island_terrain/application/terrain_sculpt_command.gd")
const EditTransaction = preload("res://addons/island_terrain/application/terrain_edit_transaction.gd")
const EditService = preload("res://addons/island_terrain/application/terrain_edit_service.gd")
const GenerationProfile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")
const GenerationController = preload("res://addons/island_terrain/generation/terrain_generation_controller.gd")
const GenerationResult = preload("res://addons/island_terrain/generation/terrain_generation_result.gd")
const MaterialLibrary = preload("res://addons/island_terrain/materials/terrain_material_library.gd")
const MaterialRuntime = preload("res://addons/island_terrain/materials/terrain_material_runtime.gd")
const TERRAIN_SHADER = preload("res://addons/island_terrain/rendering/shaders/island_terrain.gdshader")

signal terrain_initialized
signal preview_generation_progress(progress: float)
signal preview_generation_stage_changed(stage_name: String)
signal preview_generation_completed
signal preview_generation_failed(message: String)
signal material_metadata_progress(progress: float)
signal material_metadata_completed(texture: ImageTexture)
signal material_metadata_failed(message: String)
signal terrain_edited(transaction: EditTransaction)

@export_category("Terrain Data")
@export var manifest: ManifestResource
@export_file("*.tres", "*.res") var manifest_path: String = "res://terrain_data/island_01/island_manifest.tres"
@export_dir var world_data_root: String = "res://terrain_data/island_01"
@export var runtime_data_root: String = "user://terrain_data/island_01"

@export_category("Generation")
@export var generation_profile: GenerationProfile
@export var generate_preview_on_ready: bool = true
@export_range(0.1, 1.0, 0.01) var preview_height_scale: float = 0.72

@export_category("Terrain Materials")
@export var material_library: MaterialLibrary

@export_category("Mobile Performance")
@export_enum("Low", "Balanced", "High", "Editor Preview") var device_profile: int = 1:
	set = _set_device_profile
@export var memory_budget: MemoryBudget
@export_range(0, 4, 1) var runtime_shutdown_flush_limit: int = 2

@export_category("Streamed Collision")
@export var collision_enabled: bool = true:
	set = _set_collision_enabled
@export var collision_target_path: NodePath
@export_range(16, 128, 16) var collision_patch_size_m: int = 64
@export var collision_layer: int = 1
@export var collision_mask: int = 1
@export_range(0.05, 1.0, 0.05) var collision_update_interval_s: float = 0.20

@export_category("Editor Commands")
@export var rebuild_preview_requested: bool = false:
	set = _set_rebuild_preview_requested
@export var save_manifest_requested: bool = false:
	set = _set_save_manifest_requested

var _coordinate_system: CoordinateSystem
var _region_repository: RegionRepository
var _clipmap: ClipmapController
var _macro_sync: MacroHeightSync
var _collision_service: CollisionService
var _generation_controller: GenerationController
var _material_runtime: MaterialRuntime
var _edit_service: EditService
var _terrain_material: ShaderMaterial
var _height_texture: ImageTexture
var _macro_height_image: Image
var _base_macro_height_image: Image
var _generation_result: GenerationResult
var _initialized: bool = false
var _transform_warning_emitted: bool = false
var _has_height_edits: bool = false


func _ready() -> void:
	set_notify_transform(true)
	call_deferred("_initialize_terrain")


func _exit_tree() -> void:
	if _material_runtime != null:
		_material_runtime.cancel()
	if _generation_controller != null and _generation_controller.is_running():
		_generation_controller.cancel()
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
	if _region_repository != null and _region_repository.dirty_region_count() > 0:
		_region_repository.save_dirty(1)


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED:
		return
	if _coordinate_system != null:
		_coordinate_system.set_origin_world_xz(Vector2(global_position.x, global_position.z))
	if _collision_service != null:
		_collision_service.refresh_now()
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


func is_generation_running() -> bool:
	return _generation_controller != null and _generation_controller.is_running()


func get_generation_progress() -> float:
	return _generation_controller.progress() if _generation_controller != null else 0.0


func get_generation_stage_name() -> String:
	return _generation_controller.stage_name() if _generation_controller != null else "Idle"


func get_generation_working_memory_bytes() -> int:
	return _generation_controller.estimated_working_memory_bytes() \
		if _generation_controller != null else 0


func get_generation_result() -> GenerationResult:
	return _generation_result


func is_material_metadata_building() -> bool:
	return _material_runtime != null and _material_runtime.is_building_metadata()


func get_effective_material_backend() -> int:
	return _material_runtime.effective_backend() if _material_runtime != null else 0


func get_material_metadata_texture() -> ImageTexture:
	return _material_runtime.metadata_texture() if _material_runtime != null else null


func get_material_working_memory_bytes() -> int:
	return _material_runtime.estimated_working_memory_bytes() if _material_runtime != null else 0


func refresh_material_library() -> Error:
	if _material_runtime == null or _terrain_material == null or memory_budget == null:
		return ERR_UNCONFIGURED
	_ensure_material_library()
	return _material_runtime.configure(_terrain_material, material_library, memory_budget)


func request_preview_rebuild() -> void:
	if not _initialized:
		return
	if _has_height_edits:
		push_warning("IT-W08: Preview rebuild is blocked after terrain edits to protect the immutable base surface")
		return
	_schedule_preview_generation()


func cancel_preview_generation() -> void:
	if _generation_controller != null:
		_generation_controller.cancel()


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
		_has_height_edits = true
		_queue_collision_transaction(transaction)
		terrain_edited.emit(transaction)
	return transaction


func apply_edit_transaction_before(transaction: EditTransaction) -> Error:
	if _edit_service == null:
		return ERR_UNCONFIGURED
	var error: Error = _edit_service.apply_transaction_before(transaction)
	if error == OK:
		_queue_collision_transaction(transaction)
	return error


func apply_edit_transaction_after(transaction: EditTransaction) -> Error:
	if _edit_service == null:
		return ERR_UNCONFIGURED
	var error: Error = _edit_service.apply_transaction_after(transaction)
	if error == OK:
		_has_height_edits = true
		_queue_collision_transaction(transaction)
	return error


func set_collision_tracking_target(target: Node3D) -> void:
	if _collision_service != null:
		_collision_service.set_tracking_target(target)


func refresh_collision_now() -> void:
	if _collision_service != null:
		_collision_service.refresh_now()


func get_active_collision_patch_count() -> int:
	return _collision_service.active_patch_count() if _collision_service != null else 0


func get_terrain_base_y() -> float:
	return global_position.y


func height_sample_from_world_y(world_y: float) -> float:
	if manifest == null:
		return 0.0
	return clampf(world_y - global_position.y - manifest.sea_level_m, 0.0, manifest.max_height_m)


func get_base_height_sample_at_world(world_position: Vector3) -> float:
	if _base_macro_height_image == null or _base_macro_height_image.is_empty() or manifest == null:
		return 0.0
	var pixel: Vector2i = _world_to_image_pixel(world_position, _base_macro_height_image)
	if pixel.x < 0:
		return 0.0
	return _base_macro_height_image.get_pixelv(pixel).r * manifest.max_height_m


func get_height_at_world(world_position: Vector3) -> float:
	var terrain_base_y: float = global_position.y
	if _macro_height_image == null or manifest == null:
		return terrain_base_y + manifest.sea_level_m if manifest != null else terrain_base_y
	var pixel: Vector2i = _world_to_image_pixel(world_position, _macro_height_image)
	if pixel.x < 0:
		return terrain_base_y + manifest.sea_level_m
	return terrain_base_y + manifest.sea_level_m \
		+ _macro_height_image.get_pixelv(pixel).r * manifest.max_height_m


func get_normal_at_world(world_position: Vector3, sample_distance_m: float = 1.0) -> Vector3:
	var d: float = maxf(0.25, sample_distance_m)
	var h_l: float = get_height_at_world(world_position - Vector3(d, 0.0, 0.0))
	var h_r: float = get_height_at_world(world_position + Vector3(d, 0.0, 0.0))
	var h_d: float = get_height_at_world(world_position - Vector3(0.0, 0.0, d))
	var h_u: float = get_height_at_world(world_position + Vector3(0.0, 0.0, d))
	return Vector3(h_l - h_r, d * 2.0, h_d - h_u).normalized()


func get_biome_at_world(world_position: Vector3) -> int:
	var index: int = _generation_index_at_world(world_position)
	return int(_generation_result.biome_data[index]) \
		if index >= 0 else GenerationResult.Biome.OCEAN


func get_moisture_at_world(world_position: Vector3) -> float:
	var index: int = _generation_index_at_world(world_position)
	return float(_generation_result.moisture_data[index]) / 255.0 if index >= 0 else 0.0


func get_river_mask_at_world(world_position: Vector3) -> float:
	var index: int = _generation_index_at_world(world_position)
	return float(_generation_result.river_mask[index]) / 255.0 if index >= 0 else 0.0


func get_flow_accumulation_at_world(world_position: Vector3) -> float:
	var index: int = _generation_index_at_world(world_position)
	if index < 0 or _generation_result.flow_accumulation.size() <= index:
		return 0.0
	return _generation_result.flow_accumulation[index]


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
	_ensure_generation_profile()
	_ensure_material_library()
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
	var base_sampler := Callable(self, "get_base_height_sample_at_world")

	if not _create_internal_services(base_sampler):
		return

	_edit_service = EditService.new(
		manifest,
		_coordinate_system,
		_region_repository,
		_macro_sync,
		base_sampler
	)
	_initialized = true
	set_process(true)
	if generate_preview_on_ready:
		_schedule_preview_generation()
	else:
		_configure_collision_service()
	terrain_initialized.emit()


func _create_internal_services(base_sampler: Callable) -> bool:
	var sync_node: Node = get_node_or_null("__MacroHeightSync")
	if sync_node != null:
		_macro_sync = sync_node as MacroHeightSync
		if _macro_sync == null:
			push_error("IT-023: Reserved child name __MacroHeightSync is occupied")
			return false
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
		_height_texture,
		base_sampler
	)

	var clipmap_node: Node = get_node_or_null("__IslandClipmap")
	if clipmap_node != null:
		_clipmap = clipmap_node as ClipmapController
		if _clipmap == null:
			push_error("IT-011: Reserved child name __IslandClipmap is occupied by an incompatible node")
			return false
	else:
		_clipmap = ClipmapController.new()
		_clipmap.name = "__IslandClipmap"
		add_child(_clipmap, false, Node.INTERNAL_MODE_BACK)
	_clipmap.configure(manifest, memory_budget, _terrain_material, _height_texture)

	var collision_node: Node = get_node_or_null("__TerrainCollision")
	if collision_node != null:
		_collision_service = collision_node as CollisionService
		if _collision_service == null:
			push_error("IT-026: Reserved child name __TerrainCollision is occupied")
			return false
	else:
		_collision_service = CollisionService.new()
		_collision_service.name = "__TerrainCollision"
		add_child(_collision_service, false, Node.INTERNAL_MODE_BACK)

	var generation_node: Node = get_node_or_null("__TerrainGeneration")
	if generation_node != null:
		_generation_controller = generation_node as GenerationController
		if _generation_controller == null:
			push_error("IT-030: Reserved child name __TerrainGeneration is occupied")
			return false
	else:
		_generation_controller = GenerationController.new()
		_generation_controller.name = "__TerrainGeneration"
		add_child(_generation_controller, false, Node.INTERNAL_MODE_BACK)
	_connect_generation_signals()
	_generation_controller.configure(manifest, memory_budget, generation_profile)

	var material_node: Node = get_node_or_null("__TerrainMaterialRuntime")
	if material_node != null:
		_material_runtime = material_node as MaterialRuntime
		if _material_runtime == null:
			push_error("IT-034: Reserved child name __TerrainMaterialRuntime is occupied")
			return false
	else:
		_material_runtime = MaterialRuntime.new()
		_material_runtime.name = "__TerrainMaterialRuntime"
		add_child(_material_runtime, false, Node.INTERNAL_MODE_BACK)
	var metadata_progress_callback := Callable(self, "_on_material_metadata_progress")
	var metadata_completed_callback := Callable(self, "_on_material_metadata_completed")
	var metadata_failed_callback := Callable(self, "_on_material_metadata_failed")
	if not _material_runtime.metadata_progress.is_connected(metadata_progress_callback):
		_material_runtime.metadata_progress.connect(metadata_progress_callback)
	if not _material_runtime.metadata_completed.is_connected(metadata_completed_callback):
		_material_runtime.metadata_completed.connect(metadata_completed_callback)
	if not _material_runtime.metadata_failed.is_connected(metadata_failed_callback):
		_material_runtime.metadata_failed.connect(metadata_failed_callback)
	var material_error: Error = _material_runtime.configure(
		_terrain_material,
		material_library,
		memory_budget
	)
	if material_error != OK:
		push_error("IT-035: Terrain material runtime configuration failed: %d" % material_error)
		return false
	return true


func _connect_generation_signals() -> void:
	var progress_callback := Callable(self, "_on_generation_progress")
	var completed_callback := Callable(self, "_on_generation_completed")
	var failed_callback := Callable(self, "_on_generation_failed")
	var cancelled_callback := Callable(self, "_on_generation_cancelled")
	if not _generation_controller.generation_progress.is_connected(progress_callback):
		_generation_controller.generation_progress.connect(progress_callback)
	if not _generation_controller.generation_completed.is_connected(completed_callback):
		_generation_controller.generation_completed.connect(completed_callback)
	if not _generation_controller.generation_failed.is_connected(failed_callback):
		_generation_controller.generation_failed.connect(failed_callback)
	if not _generation_controller.generation_cancelled.is_connected(cancelled_callback):
		_generation_controller.generation_cancelled.connect(cancelled_callback)


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


func _ensure_generation_profile() -> void:
	if generation_profile == null:
		generation_profile = GenerationProfile.new()
		generation_profile.output_height_scale = preview_height_scale
	generation_profile.sanitize()


func _ensure_material_library() -> void:
	if material_library == null:
		material_library = MaterialLibrary.create_default()
	material_library.sanitize()


func _create_flat_height_texture() -> ImageTexture:
	var image := Image.create_empty(3, 3, true, Image.FORMAT_RF)
	image.fill(Color(0.0, 0.0, 0.0, 1.0))
	image.generate_mipmaps()
	_macro_height_image = image
	_base_macro_height_image = image.duplicate()
	return ImageTexture.create_from_image(image)


func _schedule_preview_generation() -> void:
	if _generation_controller == null:
		push_error("IT-031: Terrain generation controller is unavailable")
		return
	_ensure_memory_budget()
	_ensure_generation_profile()
	_generation_controller.configure(manifest, memory_budget, generation_profile)
	var error: Error = _generation_controller.start(memory_budget.macro_height_resolution)
	if error != OK:
		var message := "Generation start failed with error %d" % error
		push_error("IT-032: %s" % message)
		preview_generation_failed.emit(message)


func _on_generation_progress(progress: float, stage_name: String) -> void:
	preview_generation_progress.emit(progress)
	preview_generation_stage_changed.emit(stage_name)


func _on_generation_completed(result: GenerationResult) -> void:
	if result == null:
		_on_generation_failed("Generation returned a null result")
		return
	var errors: PackedStringArray = result.validate()
	if not errors.is_empty():
		_on_generation_failed("; ".join(errors))
		return
	var image: Image = result.create_height_image(true)
	if image == null or image.is_empty():
		_on_generation_failed("Failed to create generated macro height image")
		return
	_generation_result = result
	_macro_height_image = image
	_base_macro_height_image = image.duplicate()
	_height_texture = ImageTexture.create_from_image(image)
	_clipmap.set_height_texture(_height_texture)
	_macro_sync.replace_targets(_macro_height_image, _height_texture)
	if _material_runtime != null:
		var material_error: Error = _material_runtime.rebuild_metadata(result)
		if material_error != OK:
			_on_material_metadata_failed("Metadata build start failed with error %d" % material_error)
	_configure_collision_service()
	preview_generation_progress.emit(1.0)
	preview_generation_stage_changed.emit("Complete")
	preview_generation_completed.emit()


func _on_generation_failed(message: String) -> void:
	push_error("IT-033: Terrain generation failed: %s" % message)
	preview_generation_failed.emit(message)


func _on_generation_cancelled() -> void:
	preview_generation_stage_changed.emit("Cancelled")


func _on_material_metadata_progress(progress: float) -> void:
	material_metadata_progress.emit(progress)


func _on_material_metadata_completed(texture: ImageTexture) -> void:
	material_metadata_completed.emit(texture)


func _on_material_metadata_failed(message: String) -> void:
	push_error("IT-036: Terrain material metadata failed: %s" % message)
	material_metadata_failed.emit(message)


func _configure_collision_service() -> void:
	if _collision_service == null or manifest == null or memory_budget == null:
		return
	_collision_service.configure(
		manifest,
		_coordinate_system,
		Callable(self, "get_height_at_world"),
		Callable(self, "get_terrain_base_y"),
		collision_patch_size_m,
		memory_budget.collision_radius_m,
		collision_layer,
		collision_mask,
		collision_update_interval_s
	)
	_collision_service.set_enabled(collision_enabled)
	var target: Node3D = null
	if not collision_target_path.is_empty():
		target = get_node_or_null(collision_target_path) as Node3D
	_collision_service.set_tracking_target(target)


func _queue_collision_transaction(transaction: EditTransaction) -> void:
	if _collision_service != null and transaction != null:
		_collision_service.queue_transaction(transaction)


func _world_to_image_pixel(world_position: Vector3, image: Image) -> Vector2i:
	if manifest == null or image == null or image.is_empty():
		return Vector2i(-1, -1)
	var terrain_origin := Vector2(global_position.x, global_position.z)
	var half: float = float(manifest.world_size_m) * 0.5
	var uv := Vector2(
		(world_position.x - terrain_origin.x + half) / float(manifest.world_size_m),
		(world_position.z - terrain_origin.y + half) / float(manifest.world_size_m)
	)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return Vector2i(-1, -1)
	return Vector2i(
		clampi(roundi(uv.x * float(image.get_width() - 1)), 0, image.get_width() - 1),
		clampi(roundi(uv.y * float(image.get_height() - 1)), 0, image.get_height() - 1)
	)


func _generation_index_at_world(world_position: Vector3) -> int:
	if _generation_result == null or _generation_result.resolution < 1 or manifest == null:
		return -1
	var terrain_origin := Vector2(global_position.x, global_position.z)
	var half: float = float(manifest.world_size_m) * 0.5
	var uv := Vector2(
		(world_position.x - terrain_origin.x + half) / float(manifest.world_size_m),
		(world_position.z - terrain_origin.y + half) / float(manifest.world_size_m)
	)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		return -1
	var max_index: int = _generation_result.resolution - 1
	var x: int = clampi(roundi(uv.x * float(max_index)), 0, max_index)
	var y: int = clampi(roundi(uv.y * float(max_index)), 0, max_index)
	return y * _generation_result.resolution + x


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
			_height_texture,
			Callable(self, "get_base_height_sample_at_world")
		)
		if _generation_controller != null:
			_generation_controller.configure(manifest, memory_budget, generation_profile)
		if _material_runtime != null:
			_material_runtime.configure(_terrain_material, material_library, memory_budget)
		_configure_collision_service()
		request_preview_rebuild()


func _set_collision_enabled(value: bool) -> void:
	collision_enabled = value
	if _collision_service != null:
		_collision_service.set_enabled(collision_enabled)


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
