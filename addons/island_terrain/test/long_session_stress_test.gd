extends SceneTree

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Repository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")
const GenerationProfile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")
const GenerationJob = preload("res://addons/island_terrain/generation/terrain_generation_job.gd")

var _failures := PackedStringArray()


func _init() -> void:
	_test_repeated_generation_lifecycle()
	_test_region_cache_churn()
	if _failures.is_empty():
		print("IslandTerrain long-session stress tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_repeated_generation_lifecycle() -> void:
	var manifest := _make_manifest()
	var profile := GenerationProfile.new()
	profile.thermal_iterations = 1
	profile.river_accumulation_fraction = 0.002
	var peak_working_bytes: int = 0
	for cycle in range(24):
		var job := GenerationJob.new()
		var begin_error: Error = job.begin(manifest, profile, 65)
		_check(begin_error == OK, "generation stress cycle %d failed to begin" % cycle)
		if begin_error != OK:
			continue
		if cycle % 6 == 5:
			job.process_budget(250)
			job.cancel()
			_check(job.is_cancelled(), "generation stress cancellation failed at cycle %d" % cycle)
			_check(job.estimated_working_memory_bytes() < 512 * 1024, "cancelled generation retained excessive working memory")
			continue
		var guard: int = 0
		while not job.is_complete() and not job.has_failed() and guard < 50000:
			job.process_budget(500)
			peak_working_bytes = maxi(peak_working_bytes, job.estimated_working_memory_bytes())
			guard += 1
		_check(job.is_complete(), "generation stress cycle %d did not complete" % cycle)
		_check(not job.has_failed(), "generation stress cycle %d failed: %s" % [cycle, job.error_message()])
		_check(guard < 50000, "generation stress cycle %d exceeded iteration guard" % cycle)
		if job.is_complete():
			var result = job.result()
			_check(result != null and result.validate().is_empty(), "generation stress result %d is invalid" % cycle)
	_check(peak_working_bytes < 1024 * 1024, "65² repeated generation exceeded the 1 MB working-set guard")


func _test_region_cache_churn() -> void:
	var manifest := _make_manifest()
	var budget := Budget.create_for_profile(Budget.DeviceProfile.LOW)
	budget.max_cached_regions = 2
	budget.terrain_ram_budget_mb = 32
	budget.sanitize(false)
	var root: String = "user://island_terrain_hardening_stress_%d" % Time.get_ticks_usec()
	var repository := Repository.new(root, root, manifest, budget)
	var pinned_coord := Vector2i(0, 0)
	var pinned = repository.get_or_create(pinned_coord)
	pinned.ensure_channel(&"height_valid")
	pinned.ensure_channel(&"material_weight")
	pinned.ensure_channel(&"color_tint")
	pinned.set_height(Vector2i(4, 4), 12.0)
	repository.mark_dirty(pinned_coord)

	var coords := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	for cycle in range(40):
		var coord: Vector2i = coords[cycle % coords.size()]
		var region = repository.get_or_create(coord)
		region.ensure_channel(&"material_index")
		region.ensure_channel(&"biome")
		region.ensure_channel(&"wetness")
		region.ensure_channel(&"foliage_mask")
		_check(repository.is_dirty(pinned_coord), "dirty pinned region lost dirty state during cache churn")
		_check(repository.get_cached(pinned_coord) != null, "dirty pinned region was evicted during cache churn")
		_check(repository.cached_region_count() <= 2, "clean region cache exceeded max_cached_regions")
		_check(repository.cached_memory_bytes() <= budget.terrain_ram_budget_bytes(), "tracked region memory exceeded RAM budget")

	repository.clear_clean_cache()
	_check(repository.cached_region_count() == 1, "clear_clean_cache removed dirty data or retained clean regions")
	_check(repository.get_cached(pinned_coord) != null, "dirty region was removed by clear_clean_cache")
	_check(repository.flush_all() == OK, "stress repository failed to flush dirty data")
	_check(repository.dirty_region_count() == 0, "dirty region remained after flush")
	repository.clear_clean_cache()
	_check(repository.cached_region_count() == 0, "clean cache did not empty after flush")
	_check(repository.cached_memory_bytes() == 0, "cache memory accounting did not return to zero")


func _make_manifest() -> Manifest:
	var manifest := Manifest.new()
	manifest.world_size_m = 512
	manifest.region_size_m = 256
	manifest.region_samples = 65
	manifest.max_height_m = 128.0
	manifest.world_seed = 29173
	return manifest


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
