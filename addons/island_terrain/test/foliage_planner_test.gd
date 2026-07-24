extends SceneTree

const Layer = preload("res://addons/island_terrain/foliage/terrain_foliage_layer.gd")
const Library = preload("res://addons/island_terrain/foliage/terrain_foliage_library.gd")
const CellPlan = preload("res://addons/island_terrain/foliage/terrain_foliage_cell_plan.gd")
const Planner = preload("res://addons/island_terrain/foliage/terrain_foliage_planner.gd")

var _failures := PackedStringArray()
var _biome: int = 2
var _normal: Vector3 = Vector3.UP
var _moisture: float = 0.55
var _foliage_mask: float = 1.0


func _init() -> void:
	_test_deterministic_cell_plans()
	_test_environment_filters()
	_test_mobile_bounds()
	if _failures.is_empty():
		print("IslandTerrain foliage planner tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_deterministic_cell_plans() -> void:
	_reset_environment()
	var library: Library = _make_library()
	var planner: Planner = _make_planner(library)
	_check(planner != null and planner.is_configured(), "foliage planner did not configure")
	if planner == null:
		return
	var first: CellPlan = planner.plan_cell(Vector2i(2, -1))
	var second: CellPlan = planner.plan_cell(Vector2i(2, -1))
	var other: CellPlan = planner.plan_cell(Vector2i(3, -1))
	_check(first != null and second != null and other != null, "foliage planner returned null plan")
	if first == null or second == null or other == null:
		return
	_check(first.validate(library.layers.size()).is_empty(), "foliage cell plan dimensions are invalid")
	_check(first.positions == second.positions, "identical foliage cell position plans are not deterministic")
	_check(first.normals == second.normals, "identical foliage cell normal plans are not deterministic")
	_check(first.yaw_radians == second.yaw_radians, "identical foliage yaw plans are not deterministic")
	_check(first.uniform_scales == second.uniform_scales, "identical foliage scale plans are not deterministic")
	_check(first.layer_indices == second.layer_indices, "identical foliage layer plans are not deterministic")
	_check(first.positions != other.positions, "different foliage cells produced the same position plan")
	_check(first.instance_count() > 0, "accepted foliage cell produced no instances")
	_check(first.instance_count() <= library.estimated_max_instances_per_cell(), "foliage cell exceeded configured instance bound")
	for position in first.positions:
		_check(position.x >= 64.0 and position.x < 96.0, "foliage X position escaped cell bounds")
		_check(position.z >= -32.0 and position.z < 0.0, "foliage Z position escaped cell bounds")
		_check(is_equal_approx(position.y, 12.0), "foliage height sampler was ignored")
	_check(planner.world_to_cell(Vector3(95.9, 0.0, -0.1)) == Vector2i(2, -1), "world-to-foliage-cell conversion is incorrect")


func _test_environment_filters() -> void:
	var library: Library = _make_library()
	var planner: Planner = _make_planner(library)
	_biome = 6
	var rejected_biome: CellPlan = planner.plan_cell(Vector2i.ZERO)
	_check(rejected_biome.instance_count() == 0, "foliage planner ignored biome filter")

	_biome = 2
	_normal = Vector3(1.0, 0.0, 0.0)
	var rejected_slope: CellPlan = planner.plan_cell(Vector2i.ZERO)
	_check(rejected_slope.instance_count() == 0, "foliage planner ignored slope filter")

	_normal = Vector3.UP
	_foliage_mask = 0.0
	var rejected_mask: CellPlan = planner.plan_cell(Vector2i.ZERO)
	_check(rejected_mask.instance_count() == 0, "foliage planner ignored foliage mask")

	_foliage_mask = 1.0
	_moisture = 0.05
	var rejected_moisture: CellPlan = planner.plan_cell(Vector2i.ZERO)
	_check(rejected_moisture.instance_count() == 0, "foliage planner ignored moisture filter")
	_reset_environment()


func _test_mobile_bounds() -> void:
	var library: Library = _make_library()
	var planner: Planner = _make_planner(library)
	var plan: CellPlan = planner.plan_cell(Vector2i.ZERO)
	_check(plan.estimated_memory_bytes() == plan.instance_count() * 36, "foliage plan memory accounting is incorrect")
	_check(plan.estimated_memory_bytes() <= 64 * 36, "single foliage cell exceeded test memory envelope")
	_check(library.estimated_active_cell_count() <= library.max_active_cells, "foliage active-cell estimate exceeded hard cap")
	var default_library: Library = Library.create_default()
	_check(default_library.estimated_max_instances_per_cell() <= 152, "default foliage library has excessive cell density")


func _make_library() -> Library:
	var layer := Layer.new()
	layer.layer_id = &"test_grass"
	layer.allowed_biomes = PackedInt32Array([2, 3])
	layer.density_per_100_m2 = 12.0
	layer.max_instances_per_cell = 64
	layer.min_scale = 0.8
	layer.max_scale = 1.2
	layer.max_slope_degrees = 25.0
	layer.min_moisture = 0.20
	layer.max_moisture = 0.90
	var library := Library.new()
	library.cell_size_m = 32
	library.active_radius_m = 96.0
	library.density_scale = 1.0
	library.max_active_cells = 48
	library.seed_salt = 17731
	library.layers = [layer]
	library.sanitize()
	return library


func _make_planner(library: Library) -> Planner:
	var planner := Planner.new()
	var error: Error = planner.configure(
		912733,
		library,
		Vector2.ZERO,
		Callable(self, "_sample_height"),
		Callable(self, "_sample_normal"),
		Callable(self, "_sample_biome"),
		Callable(self, "_sample_moisture"),
		Callable(self, "_sample_foliage_mask")
	)
	_check(error == OK, "foliage planner configure failed with error %d" % error)
	return planner


func _sample_height(_world_position: Vector3) -> float:
	return 12.0


func _sample_normal(_world_position: Vector3) -> Vector3:
	return _normal


func _sample_biome(_world_position: Vector3) -> int:
	return _biome


func _sample_moisture(_world_position: Vector3) -> float:
	return _moisture


func _sample_foliage_mask(_world_position: Vector3) -> float:
	return _foliage_mask


func _reset_environment() -> void:
	_biome = 2
	_normal = Vector3.UP
	_moisture = 0.55
	_foliage_mask = 1.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
