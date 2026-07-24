@tool
extends Node3D
class_name IslandTerrainCollisionService

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const EditTransaction = preload("res://addons/island_terrain/application/terrain_edit_transaction.gd")

var _manifest: Manifest
var _coordinates: Coordinates
var _height_sampler: Callable
var _terrain_base_y_sampler: Callable
var _tracking_target: Node3D
var _patch_size_m: int = 64
var _collision_radius_m: float = 96.0
var _collision_layer: int = 1
var _collision_mask: int = 1
var _update_interval_s: float = 0.20
var _update_accumulator: float = 0.0
var _last_target_position: Vector3 = Vector3.INF
var _active_patches: Dictionary = {}
var _patch_pool: Array[StaticBody3D] = []
var _build_queue: Array[Vector2i] = []
var _queued: Dictionary = {}
var _configured: bool = false
var _enabled: bool = true


func _ready() -> void:
	set_process(_configured and _enabled)
	if _configured and _enabled:
		call_deferred("refresh_now")


func configure(
	manifest: Manifest,
	coordinates: Coordinates,
	height_sampler: Callable,
	terrain_base_y_sampler: Callable,
	patch_size_m: int,
	collision_radius_m: float,
	collision_layer: int,
	collision_mask: int,
	update_interval_s: float
) -> void:
	_manifest = manifest
	_coordinates = coordinates
	_height_sampler = height_sampler
	_terrain_base_y_sampler = terrain_base_y_sampler
	_patch_size_m = clampi(patch_size_m, 16, 128)
	_collision_radius_m = clampf(collision_radius_m, float(_patch_size_m), 512.0)
	_collision_layer = collision_layer
	_collision_mask = collision_mask
	_update_interval_s = clampf(update_interval_s, 0.05, 1.0)
	_configured = _height_sampler.is_valid() and _terrain_base_y_sampler.is_valid()
	set_process(_configured and _enabled)
	if _configured and _enabled and is_inside_tree():
		call_deferred("refresh_now")


func set_enabled(value: bool) -> void:
	_enabled = value
	set_process(_configured and _enabled)
	if not _enabled:
		_deactivate_all()
	elif is_inside_tree():
		call_deferred("refresh_now")


func set_tracking_target(target: Node3D) -> void:
	_tracking_target = target
	_last_target_position = Vector3.INF
	if is_inside_tree():
		call_deferred("refresh_now")


func refresh_now() -> void:
	if not _configured or not _enabled or not is_inside_tree():
		return
	var target_position: Vector3 = _resolve_target_position()
	if target_position == Vector3.INF:
		return
	_refresh_desired_patches(target_position)
	_last_target_position = target_position


func queue_region_rect(coord: Vector2i, rect: Rect2i) -> void:
	if not _configured or rect.size.x <= 0 or rect.size.y <= 0:
		return
	var first_world: Vector3 = _coordinates.region_pixel_to_world(coord, rect.position)
	var last_world: Vector3 = _coordinates.region_pixel_to_world(
		coord,
		Vector2i(rect.end.x - 1, rect.end.y - 1)
	)
	var min_patch: Vector2i = _world_to_patch(Vector3(
		minf(first_world.x, last_world.x),
		0.0,
		minf(first_world.z, last_world.z)
	))
	var max_patch: Vector2i = _world_to_patch(Vector3(
		maxf(first_world.x, last_world.x),
		0.0,
		maxf(first_world.z, last_world.z)
	))
	for patch_y in range(min_patch.y, max_patch.y + 1):
		for patch_x in range(min_patch.x, max_patch.x + 1):
			var patch_coord := Vector2i(patch_x, patch_y)
			if _active_patches.has(patch_coord):
				_queue_patch_build(patch_coord)


func queue_transaction(transaction: EditTransaction) -> void:
	if transaction == null:
		return
	for delta in transaction.deltas:
		queue_region_rect(delta.coord, delta.rect)


func active_patch_count() -> int:
	return _active_patches.size()


func active_patch_coords() -> Array:
	return _active_patches.keys()


func pooled_patch_count() -> int:
	return _patch_pool.size()


func pending_build_count() -> int:
	return _build_queue.size()


func process_pending_immediately(max_patches: int = -1) -> int:
	var processed: int = 0
	while not _build_queue.is_empty() and (max_patches < 0 or processed < max_patches):
		var coord: Vector2i = _build_queue.pop_front()
		_queued.erase(coord)
		_build_patch(coord)
		processed += 1
	return processed


func get_patch_shape(patch_coord: Vector2i) -> HeightMapShape3D:
	if not _active_patches.has(patch_coord):
		return null
	var body: StaticBody3D = _active_patches[patch_coord]
	var collision_shape := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return collision_shape.shape as HeightMapShape3D if collision_shape != null else null


func _process(delta: float) -> void:
	if not _configured or not _enabled:
		return
	_update_accumulator += delta
	var target_position: Vector3 = _resolve_target_position()
	if target_position != Vector3.INF:
		var movement_threshold: float = maxf(4.0, float(_patch_size_m) * 0.125)
		if _last_target_position == Vector3.INF \
			or target_position.distance_to(_last_target_position) >= movement_threshold \
			or _update_accumulator >= _update_interval_s:
			_update_accumulator = 0.0
			_refresh_desired_patches(target_position)
			_last_target_position = target_position
	process_pending_immediately(1)


func _refresh_desired_patches(target_position: Vector3) -> void:
	var desired: Dictionary = {}
	var center_patch: Vector2i = _world_to_patch(target_position)
	var patch_radius: int = ceili(_collision_radius_m / float(_patch_size_m))
	for offset_y in range(-patch_radius, patch_radius + 1):
		for offset_x in range(-patch_radius, patch_radius + 1):
			var coord := center_patch + Vector2i(offset_x, offset_y)
			if not _is_patch_inside_world(coord):
				continue
			var center_world: Vector3 = _patch_center_world(coord)
			if Vector2(center_world.x, center_world.z).distance_to(
				Vector2(target_position.x, target_position.z)
			) > _collision_radius_m + float(_patch_size_m) * 0.71:
				continue
			desired[coord] = true

	# Retire old bodies before acquiring new ones so the pool is reused within
	# the same refresh instead of temporarily growing on every patch boundary.
	var active_coords: Array = _active_patches.keys()
	for untyped_coord in active_coords:
		var active_coord: Vector2i = untyped_coord
		if not desired.has(active_coord):
			_deactivate_patch(active_coord)

	for untyped_coord in desired.keys():
		var desired_coord: Vector2i = untyped_coord
		if not _active_patches.has(desired_coord):
			_activate_patch(desired_coord)


func _activate_patch(coord: Vector2i) -> void:
	var body: StaticBody3D = _acquire_body()
	body.name = "CollisionPatch_%d_%d" % [coord.x, coord.y]
	body.collision_layer = _collision_layer
	body.collision_mask = _collision_mask
	body.process_mode = Node.PROCESS_MODE_INHERIT
	var center_world: Vector3 = _patch_center_world(coord)
	var terrain_origin: Vector2 = _coordinates.origin_world_xz()
	body.position = Vector3(
		center_world.x - terrain_origin.x,
		float(_manifest.sea_level_m),
		center_world.z - terrain_origin.y
	)
	var collision_shape := body.get_node("CollisionShape3D") as CollisionShape3D
	collision_shape.disabled = true
	_active_patches[coord] = body
	_queue_patch_build(coord)


func _deactivate_patch(coord: Vector2i) -> void:
	if not _active_patches.has(coord):
		return
	var body: StaticBody3D = _active_patches[coord]
	_active_patches.erase(coord)
	_queued.erase(coord)
	_build_queue.erase(coord)
	var collision_shape := body.get_node("CollisionShape3D") as CollisionShape3D
	collision_shape.disabled = true
	body.process_mode = Node.PROCESS_MODE_DISABLED
	body.name = "PooledCollisionPatch"
	_patch_pool.append(body)


func _deactivate_all() -> void:
	var coords: Array = _active_patches.keys()
	for untyped_coord in coords:
		_deactivate_patch(untyped_coord)
	_build_queue.clear()
	_queued.clear()


func _acquire_body() -> StaticBody3D:
	if not _patch_pool.is_empty():
		return _patch_pool.pop_back()
	var body := StaticBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	body.add_child(collision_shape)
	add_child(body)
	return body


func _queue_patch_build(coord: Vector2i) -> void:
	if _queued.has(coord):
		return
	_queued[coord] = true
	_build_queue.append(coord)


func _build_patch(coord: Vector2i) -> void:
	if not _active_patches.has(coord):
		return
	var body: StaticBody3D = _active_patches[coord]
	var collision_shape := body.get_node("CollisionShape3D") as CollisionShape3D
	var sample_count: int = _patch_size_m + 1
	var data := PackedFloat32Array()
	data.resize(sample_count * sample_count)
	var patch_min: Vector3 = _patch_min_world(coord)
	var base_y: float = float(_terrain_base_y_sampler.call()) + float(_manifest.sea_level_m)
	var index: int = 0
	for z in range(sample_count):
		for x in range(sample_count):
			var world_position := Vector3(
				patch_min.x + float(x),
				base_y,
				patch_min.z + float(z)
			)
			data[index] = float(_height_sampler.call(world_position)) - base_y
			index += 1
	var shape := HeightMapShape3D.new()
	shape.map_width = sample_count
	shape.map_depth = sample_count
	shape.map_data = data
	collision_shape.shape = shape
	collision_shape.disabled = false


func _resolve_target_position() -> Vector3:
	if is_instance_valid(_tracking_target):
		if not _tracking_target.is_inside_tree():
			return Vector3.INF
		return _tracking_target.global_position
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector3.INF
	var camera: Camera3D = viewport.get_camera_3d()
	return camera.global_position if is_instance_valid(camera) else Vector3.INF


func _world_to_patch(world_position: Vector3) -> Vector2i:
	var half: float = float(_manifest.world_size_m) * 0.5
	var origin: Vector2 = _coordinates.origin_world_xz()
	var world_min := Vector2(origin.x - half, origin.y - half)
	return Vector2i(
		floori((world_position.x - world_min.x) / float(_patch_size_m)),
		floori((world_position.z - world_min.y) / float(_patch_size_m))
	)


func _patch_min_world(coord: Vector2i) -> Vector3:
	var half: float = float(_manifest.world_size_m) * 0.5
	var origin: Vector2 = _coordinates.origin_world_xz()
	return Vector3(
		origin.x - half + float(coord.x * _patch_size_m),
		0.0,
		origin.y - half + float(coord.y * _patch_size_m)
	)


func _patch_center_world(coord: Vector2i) -> Vector3:
	return _patch_min_world(coord) + Vector3(
		float(_patch_size_m) * 0.5,
		0.0,
		float(_patch_size_m) * 0.5
	)


func _is_patch_inside_world(coord: Vector2i) -> bool:
	var patch_count: int = ceili(float(_manifest.world_size_m) / float(_patch_size_m))
	return coord.x >= 0 and coord.y >= 0 and coord.x < patch_count and coord.y < patch_count
