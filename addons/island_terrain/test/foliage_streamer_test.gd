extends SceneTree

const Layer = preload("res://addons/island_terrain/foliage/terrain_foliage_layer.gd")
const Library = preload("res://addons/island_terrain/foliage/terrain_foliage_library.gd")
const Streamer = preload("res://addons/island_terrain/foliage/terrain_foliage_streamer.gd")

var _failures := PackedStringArray()
var _root: Node3D
var _target: Node3D
var _streamer: Streamer


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	_target = Node3D.new()
	_root.add_child(_target)
	_streamer = Streamer.new()
	_root.add_child(_streamer)
	_test_streaming_lifecycle()
	if _failures.is_empty():
		print("IslandTerrain foliage streamer tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_streaming_lifecycle() -> void:
	var library := _make_library()
	var error: Error = _streamer.configure(
		77123,
		256.0,
		library,
		Vector2.ZERO,
		Callable(self, "_sample_height"),
		Callable(self, "_sample_normal"),
		Callable(self, "_sample_biome"),
		Callable(self, "_sample_moisture"),
		Callable(self, "_sample_foliage_mask")
	)
	_check(error == OK, "foliage streamer configure failed with error %d" % error)
	_streamer.set_tracking_target(_target)
	_streamer.refresh_now()
	_check(_streamer.active_cell_count() > 0, "foliage streamer activated no cells")
	_check(_streamer.active_cell_count() <= library.max_active_cells, "foliage streamer exceeded active cell cap")
	_check(_streamer.pending_build_count() > 0, "foliage streamer queued no builds")
	var first_coords: Array[Vector2i] = _streamer.active_cell_coords()
	var built: int = _streamer.process_pending_immediately()
	_check(built > 0, "foliage streamer built no cells")
	_check(_streamer.pending_build_count() == 0, "foliage streamer immediate build left pending cells")
	_check(_streamer.active_instance_count() > 0, "foliage streamer produced no MultiMesh instances")
	_check(
		_streamer.estimated_transform_memory_bytes() == _streamer.active_instance_count() * 48,
		"foliage streamer transform memory accounting is incorrect"
	)

	var initial_node_count: int = _streamer.active_cell_count() + _streamer.pooled_cell_count()
	_target.position = Vector3(96.0, 0.0, 0.0)
	_streamer.refresh_now()
	_streamer.process_pending_immediately()
	var moved_coords: Array[Vector2i] = _streamer.active_cell_coords()
	_check(moved_coords != first_coords, "foliage streamer did not change active cells after target movement")
	_check(_streamer.active_cell_count() <= library.max_active_cells, "moved foliage streamer exceeded active cell cap")
	var moved_node_count: int = _streamer.active_cell_count() + _streamer.pooled_cell_count()
	_check(
		moved_node_count <= initial_node_count + library.max_active_cells,
		"foliage streamer created an unbounded number of cell nodes"
	)

	_streamer.invalidate_world_circle(Vector3(96.0, 0.0, 0.0), 20.0)
	_check(_streamer.pending_build_count() > 0, "foliage invalidation queued no cell rebuild")
	_streamer.process_pending_immediately()
	_streamer.set_density_scale(0.25)
	_check(_streamer.pending_build_count() > 0, "foliage density change queued no rebuild")
	_streamer.process_pending_immediately()

	_target.position = Vector3(1000.0, 0.0, 1000.0)
	_streamer.refresh_now()
	_check(_streamer.active_cell_count() == 0, "out-of-world target kept foliage cells active")
	_check(_streamer.pooled_cell_count() <= library.max_pooled_cells, "foliage pool exceeded configured cap")
	var released: int = _streamer.release_pool(0)
	_check(released >= 0 and _streamer.pooled_cell_count() == 0, "foliage pool release failed")

	_streamer.set_enabled(false)
	_check(_streamer.active_cell_count() == 0, "disabled foliage streamer kept cells active")


func _make_library() -> Library:
	var layer := Layer.new()
	layer.layer_id = &"test_mesh"
	layer.allowed_biomes = PackedInt32Array([2])
	layer.density_per_100_m2 = 3.0
	layer.max_instances_per_cell = 24
	layer.min_scale = 0.8
	layer.max_scale = 1.2
	layer.max_slope_degrees = 40.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, 1.0, 0.25)
	layer.mesh = mesh
	var library := Library.new()
	library.cell_size_m = 32
	library.active_radius_m = 48.0
	library.density_scale = 1.0
	library.max_cell_builds_per_frame = 1
	library.frame_build_budget_ms = 0.5
	library.update_interval_s = 0.2
	library.max_active_cells = 12
	library.max_pooled_cells = 8
	library.layers = [layer]
	library.sanitize()
	return library


func _sample_height(_world_position: Vector3) -> float:
	return 4.0


func _sample_normal(_world_position: Vector3) -> Vector3:
	return Vector3.UP


func _sample_biome(_world_position: Vector3) -> int:
	return 2


func _sample_moisture(_world_position: Vector3) -> float:
	return 0.5


func _sample_foliage_mask(_world_position: Vector3) -> float:
	return 1.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
