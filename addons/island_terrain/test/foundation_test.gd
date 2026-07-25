extends SceneTree

const Constants = preload("res://addons/island_terrain/core/terrain_constants.gd")
const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const MemoryBudget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const RegionRepository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")
const MeshBuilder = preload("res://addons/island_terrain/rendering/clipmap_mesh_builder.gd")
const ClipmapController = preload("res://addons/island_terrain/rendering/clipmap_controller.gd")

var _failures := PackedStringArray()


func _init() -> void:
	_test_constants()
	_test_manifest_and_coordinates()
	_test_sparse_region_channels()
	_test_memory_profiles()
	_test_clipmap_mesh()
	_test_region_copy_on_write_roundtrip()
	if _failures.is_empty():
		print("IslandTerrain foundation tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_constants() -> void:
	_check(Constants.is_valid_sample_count(257), "257 must be a valid 2^n + 1 sample count")
	_check(not Constants.is_valid_sample_count(256), "256 must be rejected as a region sample count")
	_check(Constants.safe_macro_resolution(7000, false) <= 513, "mobile macro resolution hard cap failed")
	_check(Constants.clamp_base_quads(65) % 2 == 0, "base quads must remain even")
	_check(
		is_equal_approx(Constants.clipmap_radius_m(64, 7), 2048.0),
		"seven 64-quad clipmap levels must cover the default island radius"
	)


func _test_manifest_and_coordinates() -> void:
	var manifest := Manifest.new()
	_check(manifest.validate().is_empty(), "default manifest must validate")
	_check(manifest.region_count_axis() == 16, "4096m / 256m must produce 16 regions per axis")
	var coordinates := Coordinates.new(manifest)
	_check(coordinates.world_to_region(Vector3(-2048.0, 0.0, -2048.0)) == Vector2i.ZERO, "world minimum region mismatch")
	_check(coordinates.world_to_region(Vector3.ZERO) == Vector2i(8, 8), "world centre region mismatch")
	_check(coordinates.world_to_region_clamped(Vector3(9000.0, 0.0, 9000.0)) == Vector2i(15, 15), "region clamp mismatch")
	var world_point: Vector3 = coordinates.region_pixel_to_world(Vector2i(1, 2), Vector2i(128, 128), 12.0)
	_check(is_equal_approx(world_point.y, 12.0), "region pixel height conversion mismatch")
	var translated := Coordinates.new(manifest, Vector2(100.0, -250.0))
	_check(
		translated.world_to_region(Vector3(100.0, 0.0, -250.0)) == Vector2i(8, 8),
		"translated terrain centre region mismatch"
	)
	var translated_min: Vector3 = translated.region_origin_world(Vector2i.ZERO)
	_check(
		translated_min.is_equal_approx(Vector3(-1948.0, 0.0, -2298.0)),
		"translated region origin mismatch"
	)
	translated.set_origin_world_xz(Vector2(-400.0, 600.0))
	_check(
		translated.world_to_region(Vector3(-400.0, 0.0, 600.0)) == Vector2i(8, 8),
		"updated terrain origin was not applied"
	)


func _test_sparse_region_channels() -> void:
	var region := RegionData.new()
	region.initialize(Vector2i(2, 3), 257)
	var height_only_bytes: int = 257 * 257 * 4
	_check(region.estimated_memory_bytes() == height_only_bytes, "new region must allocate height only")
	_check(region.material_weight_data.is_empty(), "material weights must be lazy")
	region.ensure_channel(&"wetness")
	_check(region.wetness_data.size() == 257 * 257, "wetness lazy allocation failed")
	_check(region.validate_dimensions().is_empty(), "initialized region dimensions must validate")


func _test_memory_profiles() -> void:
	var low := MemoryBudget.create_for_profile(MemoryBudget.DeviceProfile.LOW)
	var high := MemoryBudget.create_for_profile(MemoryBudget.DeviceProfile.HIGH)
	_check(low.macro_height_resolution == 257, "low profile height resolution mismatch")
	_check(low.max_cached_regions < high.max_cached_regions, "profile cache scaling mismatch")
	_check(low.estimated_clipmap_vertices() < high.estimated_clipmap_vertices(), "profile clipmap scaling mismatch")
	_check(low.shadow_lod_count < high.shadow_lod_count, "profile shadow scaling mismatch")
	_check(low.can_cache_region(1024, 0), "low profile must admit a small region")


func _test_clipmap_mesh() -> void:
	var quads: int = 32
	var base_vertex_count: int = (quads + 1) * (quads + 1)
	var centre: ArrayMesh = MeshBuilder.build_level(quads, 0, false)
	var ring: ArrayMesh = MeshBuilder.build_level(quads, 1, false)
	var outer_ring: ArrayMesh = MeshBuilder.build_level(quads, 2, true)
	_check(centre.get_surface_count() == 1, "centre clipmap mesh surface missing")
	_check(ring.get_surface_count() == 1, "ring clipmap mesh surface missing")
	_check(outer_ring.get_surface_count() == 1, "outer clipmap mesh surface missing")
	_check(centre.surface_get_array_len(0) == base_vertex_count, "centre clipmap must not contain skirt walls")
	_check(ring.surface_get_array_len(0) == base_vertex_count, "inner LOD ring must not contain skirt walls")
	_check(outer_ring.surface_get_array_len(0) > base_vertex_count, "outermost LOD must retain the world-edge skirt")
	_check(ring.surface_get_array_index_len(0) > 0, "ring clipmap mesh has no indices")
	_check(
		ring.surface_get_array_index_len(0) < centre.surface_get_array_index_len(0),
		"LOD ring must remove its centre indices"
	)
	var snap: Vector3 = ClipmapController.compute_shared_snap(Vector3(37.0, 12.0, 47.0), 6)
	_check(snap.is_equal_approx(Vector3(32.0, 0.0, 32.0)), "clipmap levels were not aligned to the coarsest grid")


func _test_region_copy_on_write_roundtrip() -> void:
	var test_id: String = str(Time.get_ticks_usec())
	var test_root: String = "user://island_terrain_foundation_%s" % test_id
	var source_root: String = "%s/source" % test_root
	var runtime_root: String = "%s/runtime" % test_root
	var manifest := Manifest.new()
	manifest.world_size_m = 512
	manifest.region_size_m = 256
	manifest.region_samples = 65
	var budget := MemoryBudget.create_for_profile(MemoryBudget.DeviceProfile.LOW)
	budget.max_cached_regions = 2
	var authoring_repo := RegionRepository.new(source_root, source_root, manifest, budget)
	var authored: RegionData = authoring_repo.get_or_create(Vector2i.ZERO)
	authored.set_height(Vector2i(10, 12), 42.5)
	authoring_repo.mark_dirty(Vector2i.ZERO)
	_check(authoring_repo.flush_all() == OK, "authoring region flush failed")
	_check(
		FileAccess.file_exists(authoring_repo.writable_region_file_path(Vector2i.ZERO)),
		"authored source region file missing"
	)
	var runtime_repo := RegionRepository.new(source_root, runtime_root, manifest, budget)
	var runtime_region: RegionData = runtime_repo.get_or_create(Vector2i.ZERO)
	_check(
		is_equal_approx(runtime_region.get_height(Vector2i(10, 12)), 42.5),
		"runtime repository failed to fall back to packaged/source region"
	)
	var cached_before_channel: int = runtime_repo.cached_memory_bytes()
	runtime_region.ensure_channel(&"wetness")
	_check(
		runtime_repo.cached_memory_bytes() == cached_before_channel + 65 * 65,
		"repository failed to account for lazy channel memory growth"
	)
	runtime_region.set_height(Vector2i(10, 12), 77.25)
	runtime_repo.mark_dirty(Vector2i.ZERO)
	_check(runtime_repo.flush_all() == OK, "runtime copy-on-write flush failed")
	_check(
		FileAccess.file_exists(runtime_repo.writable_region_file_path(Vector2i.ZERO)),
		"runtime override region file missing"
	)
	var reload_repo := RegionRepository.new(source_root, runtime_root, manifest, budget)
	var reloaded: RegionData = reload_repo.get_or_create(Vector2i.ZERO)
	_check(
		is_equal_approx(reloaded.get_height(Vector2i(10, 12)), 77.25),
		"runtime region roundtrip value mismatch"
	)
	var source_reload_repo := RegionRepository.new(source_root, source_root, manifest, budget)
	var source_reloaded: RegionData = source_reload_repo.get_or_create(Vector2i.ZERO)
	_check(
		is_equal_approx(source_reloaded.get_height(Vector2i(10, 12)), 42.5),
		"runtime copy-on-write modified the packaged/source region"
	)
	_remove_tree(test_root)


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path: String = "%s/%s" % [path, entry]
			if directory.current_is_dir():
				_remove_tree(child_path)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child_path))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)