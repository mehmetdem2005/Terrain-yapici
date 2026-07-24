extends SceneTree

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const Policy = preload("res://addons/island_terrain/diagnostics/terrain_health_policy.gd")
const Snapshot = preload("res://addons/island_terrain/diagnostics/terrain_health_snapshot.gd")
const Evaluator = preload("res://addons/island_terrain/diagnostics/terrain_health_evaluator.gd")
const QualityController = preload("res://addons/island_terrain/diagnostics/terrain_runtime_quality_controller.gd")
const Clipmap = preload("res://addons/island_terrain/rendering/clipmap_controller.gd")
const Collision = preload("res://addons/island_terrain/physics/terrain_collision_service.gd")
const MaterialRuntime = preload("res://addons/island_terrain/materials/terrain_material_runtime.gd")
const MaterialLibrary = preload("res://addons/island_terrain/materials/terrain_material_library.gd")
const TERRAIN_SHADER = preload("res://addons/island_terrain/rendering/shaders/island_terrain.gdshader")

var _failures := PackedStringArray()


func _init() -> void:
	_test_allocation_preflight()
	_test_health_hysteresis()
	_test_reversible_quality_controls()
	if _failures.is_empty():
		print("IslandTerrain production hardening tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_allocation_preflight() -> void:
	var budget := Budget.create_for_profile(Budget.DeviceProfile.LOW)
	_check(budget.terrain_ram_budget_bytes() == 80 * 1024 * 1024, "low RAM budget byte conversion failed")
	_check(budget.safe_terrain_ram_bytes() < budget.terrain_ram_budget_bytes(), "allocation safety margin was not applied")
	_check(budget.can_start_generation(257, 0, true), "safe 257² generation was rejected")
	_check(not budget.can_start_generation(2049, 0, true), "unsafe 2049² generation was accepted")
	var nearly_full: int = budget.safe_terrain_ram_bytes() - 1024 * 1024
	_check(not budget.can_start_generation(257, nearly_full, true), "generation ignored resident terrain memory")
	_check(
		budget.estimated_generation_peak_bytes(513) > budget.estimated_generation_result_bytes(513),
		"generation peak estimate does not include working memory"
	)


func _test_health_hysteresis() -> void:
	var budget := Budget.create_for_profile(Budget.DeviceProfile.LOW)
	var policy := Policy.new()
	policy.low_fps_threshold = 30.0
	policy.recovery_fps_threshold = 45.0
	policy.consecutive_bad_samples = 3
	policy.consecutive_good_samples = 2
	policy.quality_change_cooldown_s = 5.0
	policy.auto_degrade_enabled = true
	policy.auto_recover_enabled = true
	policy.sanitize()
	var evaluator := Evaluator.new()
	var low_fps := Snapshot.new()
	low_fps.fps = 20.0
	low_fps.region_cache_bytes = 1024 * 1024

	var first: Dictionary = evaluator.evaluate(low_fps, policy, budget, 0, 0)
	var second: Dictionary = evaluator.evaluate(low_fps, policy, budget, 0, 1000)
	var third: Dictionary = evaluator.evaluate(low_fps, policy, budget, 0, 2000)
	_check(int(first.get("quality_delta", 0)) == 0, "single low-FPS sample degraded quality")
	_check(int(second.get("quality_delta", 0)) == 0, "second low-FPS sample degraded quality too early")
	_check(int(third.get("quality_delta", 0)) == 1, "sustained low FPS did not degrade quality")

	var cooldown_sample: Dictionary = evaluator.evaluate(low_fps, policy, budget, 1, 3000)
	_check(int(cooldown_sample.get("quality_delta", 0)) == 0, "quality cooldown did not block repeated degradation")

	var critical := Snapshot.new()
	critical.fps = 60.0
	critical.region_cache_bytes = int(float(budget.terrain_ram_budget_bytes()) * 1.05)
	var critical_result: Dictionary = evaluator.evaluate(critical, policy, budget, 1, 8000)
	_check(
		int(critical_result.get("pressure_level", 0)) == Snapshot.PressureLevel.CRITICAL,
		"critical terrain RAM pressure was not classified"
	)
	_check(bool(critical_result.get("clear_clean_cache", false)), "critical pressure did not request clean-cache release")
	_check(int(critical_result.get("quality_delta", 0)) == 1, "critical pressure did not bypass the bad-sample streak")

	var recovery_evaluator := Evaluator.new()
	var healthy := Snapshot.new()
	healthy.fps = 60.0
	var recovery_first: Dictionary = recovery_evaluator.evaluate(healthy, policy, budget, 1, 0)
	var recovery_second: Dictionary = recovery_evaluator.evaluate(healthy, policy, budget, 1, 1000)
	_check(int(recovery_first.get("quality_delta", 0)) == 0, "quality recovered after one good sample")
	_check(int(recovery_second.get("quality_delta", 0)) == -1, "enabled quality recovery did not run after hysteresis")


func _test_reversible_quality_controls() -> void:
	var manifest := Manifest.new()
	manifest.world_size_m = 512
	manifest.region_size_m = 256
	manifest.region_samples = 65
	manifest.max_height_m = 128.0
	var budget := Budget.create_for_profile(Budget.DeviceProfile.BALANCED)
	budget.clipmap_levels = 3
	budget.base_quads = 16
	budget.shadow_lod_count = 2
	budget.collision_radius_m = 96.0
	var image := Image.create_empty(3, 3, true, Image.FORMAT_RF)
	image.fill(Color.BLACK)
	image.generate_mipmaps()
	var height_texture := ImageTexture.create_from_image(image)
	var shader_material := ShaderMaterial.new()
	shader_material.shader = TERRAIN_SHADER

	var clipmap := Clipmap.new()
	clipmap.configure(manifest, budget, shader_material, height_texture)
	var coordinates := Coordinates.new(manifest, Vector2.ZERO)
	var collision := Collision.new()
	collision.configure(
		manifest,
		coordinates,
		Callable(self, "_flat_height"),
		Callable(self, "_terrain_base_y"),
		64,
		96.0,
		1,
		1,
		0.2
	)
	var library := MaterialLibrary.create_default()
	library.detail_lod_limit = 2
	var material_runtime := MaterialRuntime.new()
	var material_error: Error = material_runtime.configure(shader_material, library, budget)
	_check(material_error == OK, "material runtime failed to configure for quality test")

	var quality := QualityController.new()
	var configure_error: Error = quality.configure(clipmap, collision, material_runtime)
	_check(configure_error == OK, "quality controller failed to configure")
	_check(quality.set_level(QualityController.QualityReduction.REDUCED_DETAIL) == OK, "detail reduction failed")
	_check(material_runtime.get_runtime_detail_lod_limit() == 1, "detail LOD reduction was not applied")
	_check(quality.set_level(QualityController.QualityReduction.REDUCED_SHADOWS) == OK, "shadow reduction failed")
	_check(clipmap.get_shadow_lod_count() == 0, "shadow LODs were not disabled")
	_check(quality.set_level(QualityController.QualityReduction.REDUCED_COLLISION) == OK, "collision reduction failed")
	_check(is_equal_approx(collision.get_collision_radius_m(), 64.0), "collision radius was not reduced")
	_check(quality.restore_full_quality() == OK, "full-quality restore failed")
	_check(material_runtime.get_runtime_detail_lod_limit() == 2, "material detail did not restore")
	_check(clipmap.get_shadow_lod_count() == 2, "shadow LODs did not restore")
	_check(is_equal_approx(collision.get_collision_radius_m(), 96.0), "collision radius did not restore")


func _flat_height(_world_position: Vector3) -> float:
	return 0.0


func _terrain_base_y() -> float:
	return 0.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
