extends SceneTree

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const CollisionService = preload("res://addons/island_terrain/physics/terrain_collision_service.gd")

var _failures := PackedStringArray()
var _root: Node3D
var _target: Node3D
var _service: CollisionService


func _init() -> void:
	_root = Node3D.new()
	_root.position.y = 10.0
	get_root().add_child(_root)
	_target = Node3D.new()
	_root.add_child(_target)
	_service = CollisionService.new()
	_root.add_child(_service)
	_setup_service()
	var selected_case: String = _selected_case()
	match selected_case:
		"shape":
			_test_patch_shape()
		"movement":
			_test_patch_movement_and_pooling()
		"dirty":
			_test_dirty_rebuild_queue()
		_:
			_test_patch_shape()
			_test_patch_movement_and_pooling()
			_test_dirty_rebuild_queue()
	if _failures.is_empty():
		print("IslandTerrain collision streaming test %s: PASS" % selected_case)
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _setup_service() -> void:
	var manifest := Manifest.new()
	manifest.world_size_m = 256
	manifest.region_size_m = 256
	manifest.region_samples = 65
	manifest.max_height_m = 100.0
	var coordinates := Coordinates.new(manifest)
	_target.position = Vector3.ZERO
	_service.configure(
		manifest,
		coordinates,
		Callable(self, "_constant_world_height"),
		Callable(self, "_terrain_base_y"),
		32,
		32.0,
		1,
		1,
		0.2
	)
	_service.set_tracking_target(_target)
	_service.refresh_now()
	_service.process_pending_immediately()


func _test_patch_shape() -> void:
	_check(_service.active_patch_count() > 0, "no collision patches are active")
	var center_coord := Vector2i(4, 4)
	var shape: HeightMapShape3D = _service.get_patch_shape(center_coord)
	_check(shape != null, "center collision patch shape is missing")
	if shape == null:
		return
	_check(shape.map_width == 33 and shape.map_depth == 33, "collision patch sample dimensions are incorrect")
	_check(shape.map_data.size() == 33 * 33, "collision patch data size is incorrect")
	_check(is_equal_approx(shape.map_data[16 * 33 + 16], 32.0), "collision height was not converted to body-local Y")


func _test_patch_movement_and_pooling() -> void:
	var first_active: int = _service.active_patch_count()
	_target.position = Vector3(80.0, 0.0, 0.0)
	_service.refresh_now()
	_service.process_pending_immediately()
	_check(_service.active_patch_count() > 0, "moving target removed all collision patches")
	_check(
		_service.pooled_patch_count() > 0 or _service.active_patch_count() != first_active,
		"collision patches were not recycled after target movement"
	)


func _test_dirty_rebuild_queue() -> void:
	_service.queue_region_rect(Vector2i.ZERO, Rect2i(0, 0, 65, 65))
	_check(_service.pending_build_count() > 0, "terrain edit did not queue active collision rebuilds")


func _selected_case() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--case="):
			return argument.trim_prefix("--case=")
	return "all"


func _constant_world_height(_world_position: Vector3) -> float:
	return 42.0


func _terrain_base_y() -> float:
	return 10.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
