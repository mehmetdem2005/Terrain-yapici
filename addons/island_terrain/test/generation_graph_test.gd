extends SceneTree

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Profile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")
const Result = preload("res://addons/island_terrain/generation/terrain_generation_result.gd")
const GenerationJob = preload("res://addons/island_terrain/generation/terrain_generation_job.gd")

var _failures := PackedStringArray()


func _init() -> void:
	_test_deterministic_generation()
	_test_cancellation()
	if _failures.is_empty():
		print("IslandTerrain generation graph tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_deterministic_generation() -> void:
	var manifest := Manifest.new()
	manifest.world_size_m = 1024
	manifest.region_size_m = 256
	manifest.region_samples = 65
	manifest.max_height_m = 256.0
	manifest.world_seed = 82341
	var profile := Profile.new()
	profile.thermal_iterations = 2
	profile.river_accumulation_fraction = 0.0015
	profile.river_depth_m = 5.0
	var first: Result = _run_job(manifest, profile, 65)
	var second: Result = _run_job(manifest, profile, 65)
	_check(first != null and second != null, "generation job did not complete")
	if first == null or second == null:
		return
	_check(first.validate().is_empty(), "first generation result is invalid")
	_check(second.validate().is_empty(), "second generation result is invalid")
	_check(first.height_data == second.height_data, "generation is not deterministic for identical seed/profile")
	_check(first.biome_data == second.biome_data, "biome classification is not deterministic")
	_check(first.river_mask == second.river_mask, "river graph is not deterministic")
	_check(first.estimated_memory_bytes() < 256 * 1024, "65² generation result exceeded expected memory envelope")

	var land_count: int = 0
	var ocean_count: int = 0
	var biome_types: Dictionary = {}
	var river_pixels: int = 0
	var maximum_height: float = 0.0
	for index in range(first.height_data.size()):
		var height: float = first.height_data[index]
		maximum_height = maxf(maximum_height, height)
		if height > 0.001:
			land_count += 1
		else:
			ocean_count += 1
		biome_types[int(first.biome_data[index])] = true
		if first.river_mask[index] > 0:
			river_pixels += 1
	_check(land_count > 0, "generation produced no land")
	_check(ocean_count > 0, "generation produced no surrounding ocean")
	_check(maximum_height > 0.20, "generation produced insufficient elevation range")
	_check(biome_types.size() >= 3, "generation produced insufficient biome diversity")
	_check(river_pixels > 0, "generation produced no river pixels with test threshold")
	_check(first.flow_accumulation.is_empty(), "temporary flow accumulation was not released after completion")

	var image: Image = first.create_height_image(false)
	_check(image != null and image.get_width() == 65 and image.get_height() == 65, "height image conversion failed")


func _test_cancellation() -> void:
	var manifest := Manifest.new()
	var profile := Profile.new()
	var job := GenerationJob.new()
	_check(job.begin(manifest, profile, 129) == OK, "cancellation job failed to begin")
	job.process_budget(250)
	job.cancel()
	_check(job.is_cancelled(), "generation job did not enter cancelled state")
	var stage_after_cancel: int = job.stage()
	job.process_budget(1000)
	_check(job.stage() == stage_after_cancel, "cancelled generation job continued processing")


func _run_job(manifest: Manifest, profile: Profile, resolution: int) -> Result:
	var job := GenerationJob.new()
	var begin_error: Error = job.begin(manifest, profile, resolution)
	_check(begin_error == OK, "generation job begin failed with error %d" % begin_error)
	if begin_error != OK:
		return null
	var previous_progress: float = 0.0
	var iterations: int = 0
	while not job.is_complete() and not job.has_failed() and iterations < 50000:
		job.process_budget(500)
		var current_progress: float = job.progress()
		_check(current_progress + 0.0001 >= previous_progress, "generation progress moved backwards")
		previous_progress = current_progress
		iterations += 1
	_check(not job.has_failed(), "generation job failed: %s" % job.error_message())
	_check(iterations < 50000, "generation job exceeded iteration guard")
	_check(is_equal_approx(job.progress(), 1.0), "completed generation progress is not 1.0")
	return job.result() if job.is_complete() else null


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
