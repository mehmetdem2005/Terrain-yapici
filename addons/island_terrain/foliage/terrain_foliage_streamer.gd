@tool
extends Node3D
class_name IslandTerrainFoliageStreamer

const Library = preload("res://addons/island_terrain/foliage/terrain_foliage_library.gd")
const Planner = preload("res://addons/island_terrain/foliage/terrain_foliage_planner.gd")
const CellPlan = preload("res://addons/island_terrain/foliage/terrain_foliage_cell_plan.gd")
const CellRuntime = preload("res://addons/island_terrain/foliage/terrain_foliage_cell_runtime.gd")

var _world_seed: int = 1
var _world_size_m: float = 4096.0
var _terrain_origin_xz: Vector2 = Vector2.ZERO
var _library: Library
var _planner: Planner
var _height_sampler: Callable
var _normal_sampler: Callable
var _biome_sampler: Callable
var _moisture_sampler: Callable
var _foliage_mask_sampler: Callable
var _tracking_target: Node3D
var _active_cells: Dictionary = {}
var _cell_pool: Array[CellRuntime] = []
var _build_queue: Array[Vector2i] = []
var _queued: Dictionary = {}
var _configured: bool = false
var _enabled: bool = true
var _update_accumulator: float = 0.0
var _last_target_position: Vector3 = Vector3.INF


func configure(
	world_seed: int,
	world_size_m: float,
	library: Library,
	terrain_origin_xz: Vector2,
	height_sampler: Callable,
	normal_sampler: Callable,
	biome_sampler: Callable,
	moisture_sampler: Callable,
	foliage_mask_sampler: Callable
) -> Error:
	if world_size_m <= 0.0 or library == null:
		return ERR_INVALID_PARAMETER
	_world_seed = world_seed
	_world_size_m = world_size_m
	_terrain_origin_xz = terrain_origin_xz
	_library = library.duplicate(true) as Library
	if _library == null:
		return ERR_CANT_CREATE
	_library.sanitize()
	_height_sampler = height_sampler
	_normal_sampler = normal_sampler
	_biome_sampler = biome_sampler
	_moisture_sampler = moisture_sampler
	_foliage_mask_sampler = foliage_mask_sampler
	if _planner == null:
		_planner = Planner.new()
	var planner_error: Error = _configure_planner()
	if planner_error != OK:
		return planner_error
	_deactivate_all()
	_configured = true
	_last_target_position = Vector3.INF
	set_process(_enabled)
	if is_inside_tree():
		refresh_now()
	return OK


func set_enabled(value: bool) -> void:
	_enabled = value
	set_process(_configured and _enabled)
	if not _enabled:
		_deactivate_all()
	elif _configured:
		refresh_now()


func set_tracking_target(target: Node3D) -> void:
	_tracking_target = target
	_last_target_position = Vector3.INF
	if _configured and _enabled:
		refresh_now()


func set_density_scale(value: float) -> void:
	if _library == null:
		return
	_library.density_scale = clampf(value, 0.1, 2.0)
	_configure_planner()
	_queue_all_active_cells()


func set_active_radius_m(value: float) -> void:
	if _library == null:
		return
	_library.active_radius_m = clampf(value, float(_library.cell_size_m), 256.0)
	_last_target_position = Vector3.INF
	refresh_now()


func refresh_now() -> void:
	if not _configured or not _enabled or not is_inside_tree():
		return
	var target_position: Vector3 = _resolve_target_position()
	if target_position == Vector3.INF:
		return
	_refresh_desired_cells(target_position)
	_last_target_position = target_position


func invalidate_cell(cell_coord: Vector2i) -> void:
	if _active_cells.has(cell_coord):
		_queue_cell_build(cell_coord)


func invalidate_world_circle(center_world: Vector3, radius_m: float) -> void:
	if _planner == null:
		return
	var safe_radius: float = maxf(0.0, radius_m)
	for untyped_coord in _active_cells.keys():
		var coord: Vector2i = untyped_coord
		var center: Vector3 = _planner.cell_center_world(coord)
		if Vector2(center.x, center.z).distance_to(Vector2(center_world.x, center_world.z)) \
			<= safe_radius + float(_library.cell_size_m) * 0.71:
			_queue_cell_build(coord)


func active_cell_count() -> int:
	return _active_cells.size()


func pooled_cell_count() -> int:
	return _cell_pool.size()


func pending_build_count() -> int:
	return _build_queue.size()


func active_instance_count() -> int:
	var total: int = 0
	for runtime_variant in _active_cells.values():
		var runtime: CellRuntime = runtime_variant
		total += runtime.visible_instance_count()
	return total


func estimated_transform_memory_bytes() -> int:
	var total: int = 0
	for runtime_variant in _active_cells.values():
		var runtime: CellRuntime = runtime_variant
		total += runtime.estimated_transform_memory_bytes()
	return total


func active_cell_coords() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for coord in _active_cells.keys():
		result.append(coord)
	result.sort()
	return result


func process_pending_immediately(max_cells: int = -1) -> int:
	var processed: int = 0
	while not _build_queue.is_empty() and (max_cells < 0 or processed < max_cells):
		var coord: Vector2i = _build_queue.pop_front()
		_queued.erase(coord)
		_build_cell(coord)
		processed += 1
	return processed


func release_pool(max_keep: int = 0) -> int:
	var safe_keep: int = clampi(max_keep, 0, _cell_pool.size())
	var released: int = 0
	while _cell_pool.size() > safe_keep:
		var runtime: CellRuntime = _cell_pool.pop_back()
		runtime.queue_free()
		released += 1
	return released


func _process(delta: float) -> void:
	if not _configured or not _enabled:
		return
	_update_accumulator += delta
	var target_position: Vector3 = _resolve_target_position()
	if target_position != Vector3.INF:
		var threshold: float = maxf(4.0, float(_library.cell_size_m) * 0.25)
		if _last_target_position == Vector3.INF \
			or target_position.distance_to(_last_target_position) >= threshold \
			or _update_accumulator >= _library.update_interval_s:
			_update_accumulator = 0.0
			_refresh_desired_cells(target_position)
			_last_target_position = target_position
	_process_build_budget()


func _process_build_budget() -> void:
	var start_usec: int = Time.get_ticks_usec()
	var budget_usec: int = maxi(250, int(_library.frame_build_budget_ms * 1000.0))
	var built: int = 0
	while not _build_queue.is_empty() and built < _library.max_cell_builds_per_frame:
		var coord: Vector2i = _build_queue.pop_front()
		_queued.erase(coord)
		_build_cell(coord)
		built += 1
		if Time.get_ticks_usec() - start_usec >= budget_usec:
			break


func _refresh_desired_cells(target_position: Vector3) -> void:
	var center_cell: Vector2i = _planner.world_to_cell(target_position)
	var radius_cells: int = ceili(_library.active_radius_m / float(_library.cell_size_m))
	var candidates: Array[Dictionary] = []
	for offset_y in range(-radius_cells, radius_cells + 1):
		for offset_x in range(-radius_cells, radius_cells + 1):
			var coord := center_cell + Vector2i(offset_x, offset_y)
			if not _cell_overlaps_world(coord):
				continue
			var center_world: Vector3 = _planner.cell_center_world(coord)
			var distance_squared: float = Vector2(center_world.x, center_world.z).distance_squared_to(
				Vector2(target_position.x, target_position.z)
			)
			var maximum_distance: float = _library.active_radius_m \
				+ float(_library.cell_size_m) * 0.71
			if distance_squared > maximum_distance * maximum_distance:
				continue
			candidates.append({"coord": coord, "distance_squared": distance_squared})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance_squared"]) < float(b["distance_squared"])
	)

	var desired: Dictionary = {}
	var desired_count: int = mini(candidates.size(), _library.max_active_cells)
	for index in range(desired_count):
		var coord: Vector2i = candidates[index]["coord"]
		desired[coord] = true
		if not _active_cells.has(coord):
			_activate_cell(coord)

	for untyped_coord in _active_cells.keys().duplicate():
		var coord: Vector2i = untyped_coord
		if not desired.has(coord):
			_deactivate_cell(coord)


func _activate_cell(coord: Vector2i) -> void:
	var runtime: CellRuntime = _acquire_cell_runtime()
	runtime.cell_coord = coord
	runtime.name = "FoliageCell_%d_%d" % [coord.x, coord.y]
	runtime.visible = false
	_active_cells[coord] = runtime
	_queue_cell_build(coord)


func _deactivate_cell(coord: Vector2i) -> void:
	if not _active_cells.has(coord):
		return
	var runtime: CellRuntime = _active_cells[coord]
	_active_cells.erase(coord)
	_queued.erase(coord)
	_build_queue.erase(coord)
	runtime.clear_for_pool(false)
	runtime.name = "PooledFoliageCell"
	if _cell_pool.size() < _library.max_pooled_cells:
		_cell_pool.append(runtime)
	else:
		runtime.queue_free()


func _deactivate_all() -> void:
	for untyped_coord in _active_cells.keys().duplicate():
		_deactivate_cell(untyped_coord)
	_build_queue.clear()
	_queued.clear()


func _acquire_cell_runtime() -> CellRuntime:
	if not _cell_pool.is_empty():
		return _cell_pool.pop_back()
	var runtime := CellRuntime.new()
	add_child(runtime)
	return runtime


func _queue_cell_build(coord: Vector2i) -> void:
	if _queued.has(coord):
		return
	_queued[coord] = true
	_build_queue.append(coord)


func _queue_all_active_cells() -> void:
	for coord in _active_cells.keys():
		_queue_cell_build(coord)


func _build_cell(coord: Vector2i) -> void:
	if not _active_cells.has(coord):
		return
	var plan: CellPlan = _planner.plan_cell(coord)
	if plan == null:
		return
	var runtime: CellRuntime = _active_cells[coord]
	var error: Error = runtime.populate(
		plan,
		_library,
		Callable(self, "_world_to_local_position")
	)
	if error != OK:
		push_error("IT-050: Foliage cell %s build failed with error %d" % [coord, error])


func _configure_planner() -> Error:
	return _planner.configure(
		_world_seed,
		_library,
		_terrain_origin_xz,
		_height_sampler,
		_normal_sampler,
		_biome_sampler,
		_moisture_sampler,
		_foliage_mask_sampler
	)


func _world_to_local_position(world_position: Vector3) -> Vector3:
	return to_local(world_position)


func _resolve_target_position() -> Vector3:
	if is_instance_valid(_tracking_target) and _tracking_target.is_inside_tree():
		return _tracking_target.global_position
	if not is_inside_tree() or get_viewport() == null:
		return Vector3.INF
	var camera: Camera3D = get_viewport().get_camera_3d()
	return camera.global_position if is_instance_valid(camera) else Vector3.INF


func _cell_overlaps_world(coord: Vector2i) -> bool:
	var cell_min: Vector3 = _planner.cell_min_world(coord)
	var cell_max := cell_min + Vector3(
		float(_library.cell_size_m),
		0.0,
		float(_library.cell_size_m)
	)
	var half: float = _world_size_m * 0.5
	var world_min := Vector2(_terrain_origin_xz.x - half, _terrain_origin_xz.y - half)
	var world_max := Vector2(_terrain_origin_xz.x + half, _terrain_origin_xz.y + half)
	return cell_max.x > world_min.x \
		and cell_max.z > world_min.y \
		and cell_min.x < world_max.x \
		and cell_min.z < world_max.y
