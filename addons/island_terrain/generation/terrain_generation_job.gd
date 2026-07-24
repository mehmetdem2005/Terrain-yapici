@tool
extends RefCounted
class_name IslandTerrainGenerationJob

const Constants = preload("res://addons/island_terrain/core/terrain_constants.gd")
const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Profile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")
const Result = preload("res://addons/island_terrain/generation/terrain_generation_result.gd")

const FLOW_BUCKET_COUNT: int = 4096
const FLOW_CHUNK_SIZE: int = 4096

enum Stage {
	IDLE,
	SHAPE,
	EROSION_PREPARE,
	EROSION,
	FLOW_PREPARE,
	FLOW_DIRECTION,
	FLOW_ORDER_PREPARE,
	FLOW_ORDER_FILL,
	FLOW_ACCUMULATION,
	RIVER_CARVE,
	BIOME_CLASSIFICATION,
	COMPLETE,
	FAILED,
	CANCELLED,
}

var _manifest: Manifest
var _profile: Profile
var _result: Result
var _resolution: int = 0
var _world_size_m: float = 0.0
var _stage: int = Stage.IDLE
var _row: int = 0
var _erosion_iteration: int = 0
var _erosion_scratch: PackedFloat32Array = PackedFloat32Array()
var _downstream: PackedInt32Array = PackedInt32Array()
var _height_bucket_counts: PackedInt32Array = PackedInt32Array()
var _height_bucket_offsets: PackedInt32Array = PackedInt32Array()
var _height_bucket_cursors: PackedInt32Array = PackedInt32Array()
var _height_order: PackedInt32Array = PackedInt32Array()
var _flow_cursor: int = -1
var _broad_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _coast_noise: FastNoiseLite
var _moisture_noise: FastNoiseLite
var _error_message: String = ""


func begin(manifest: Manifest, profile: Profile, resolution: int) -> Error:
	if manifest == null or profile == null:
		return ERR_INVALID_PARAMETER
	if not Constants.is_valid_sample_count(resolution):
		_error_message = "generation resolution must be 2^n + 1"
		_stage = Stage.FAILED
		return ERR_INVALID_PARAMETER
	var manifest_errors: PackedStringArray = manifest.validate()
	if not manifest_errors.is_empty():
		_error_message = "; ".join(manifest_errors)
		_stage = Stage.FAILED
		return ERR_INVALID_DATA
	_manifest = manifest
	_profile = profile.duplicate(true) as Profile
	if _profile == null:
		_stage = Stage.FAILED
		_error_message = "generation profile duplication failed"
		return ERR_CANT_CREATE
	_profile.sanitize()
	_resolution = resolution
	_world_size_m = float(_manifest.world_size_m)
	_result = Result.new()
	_result.initialize(_resolution, _manifest.world_seed)
	_setup_noise()
	_row = 0
	_erosion_iteration = 0
	_error_message = ""
	_stage = Stage.SHAPE
	return OK


func process_budget(budget_usec: int) -> void:
	if _stage in [Stage.IDLE, Stage.COMPLETE, Stage.FAILED, Stage.CANCELLED]:
		return
	var safe_budget: int = maxi(250, budget_usec)
	var start_usec: int = Time.get_ticks_usec()
	var steps: int = 0
	while Time.get_ticks_usec() - start_usec < safe_budget:
		_step()
		steps += 1
		if _stage in [Stage.COMPLETE, Stage.FAILED, Stage.CANCELLED] or steps >= 128:
			break


func cancel() -> void:
	if _stage not in [Stage.COMPLETE, Stage.FAILED, Stage.CANCELLED]:
		_stage = Stage.CANCELLED
	_release_working_data()


func is_complete() -> bool:
	return _stage == Stage.COMPLETE


func has_failed() -> bool:
	return _stage == Stage.FAILED


func is_cancelled() -> bool:
	return _stage == Stage.CANCELLED


func result() -> Result:
	return _result


func error_message() -> String:
	return _error_message


func stage() -> int:
	return _stage


func stage_name() -> String:
	match _stage:
		Stage.IDLE:
			return "Idle"
		Stage.SHAPE:
			return "Island Shape"
		Stage.EROSION_PREPARE, Stage.EROSION:
			return "Thermal Erosion"
		Stage.FLOW_PREPARE, Stage.FLOW_DIRECTION, Stage.FLOW_ORDER_PREPARE, \
		Stage.FLOW_ORDER_FILL, Stage.FLOW_ACCUMULATION:
			return "River Flow"
		Stage.RIVER_CARVE:
			return "River Carving"
		Stage.BIOME_CLASSIFICATION:
			return "Biome Classification"
		Stage.COMPLETE:
			return "Complete"
		Stage.FAILED:
			return "Failed"
		Stage.CANCELLED:
			return "Cancelled"
	return "Unknown"


func progress() -> float:
	var row_fraction: float = float(_row) / float(maxi(1, _resolution))
	match _stage:
		Stage.IDLE:
			return 0.0
		Stage.SHAPE:
			return row_fraction * 0.30
		Stage.EROSION_PREPARE:
			return 0.30 + float(_erosion_iteration) \
				/ float(maxi(1, _profile.thermal_iterations)) * 0.20
		Stage.EROSION:
			var iteration_fraction: float = (
				float(_erosion_iteration) + row_fraction
			) / float(maxi(1, _profile.thermal_iterations))
			return 0.30 + iteration_fraction * 0.20
		Stage.FLOW_PREPARE:
			return 0.50
		Stage.FLOW_DIRECTION:
			return 0.50 + row_fraction * 0.08
		Stage.FLOW_ORDER_PREPARE:
			return 0.58
		Stage.FLOW_ORDER_FILL:
			return 0.58 + row_fraction * 0.06
		Stage.FLOW_ACCUMULATION:
			var count: int = maxi(1, _resolution * _resolution)
			var completed: float = 1.0 - float(maxi(_flow_cursor, 0)) / float(count)
			return 0.64 + completed * 0.11
		Stage.RIVER_CARVE:
			return 0.75 + row_fraction * 0.10
		Stage.BIOME_CLASSIFICATION:
			return 0.85 + row_fraction * 0.15
		Stage.COMPLETE:
			return 1.0
		Stage.FAILED, Stage.CANCELLED:
			return 0.0
	return 0.0


func estimated_working_memory_bytes() -> int:
	var bytes: int = _result.estimated_memory_bytes() if _result != null else 0
	bytes += _erosion_scratch.size() * 4
	bytes += _downstream.size() * 4
	bytes += _height_bucket_counts.size() * 4
	bytes += _height_bucket_offsets.size() * 4
	bytes += _height_bucket_cursors.size() * 4
	bytes += _height_order.size() * 4
	return bytes


func _step() -> void:
	match _stage:
		Stage.SHAPE:
			_step_shape()
		Stage.EROSION_PREPARE:
			_prepare_erosion_iteration()
		Stage.EROSION:
			_step_erosion()
		Stage.FLOW_PREPARE:
			_prepare_flow()
		Stage.FLOW_DIRECTION:
			_step_flow_direction()
		Stage.FLOW_ORDER_PREPARE:
			_prepare_flow_order()
		Stage.FLOW_ORDER_FILL:
			_step_flow_order_fill()
		Stage.FLOW_ACCUMULATION:
			_step_flow_accumulation()
		Stage.RIVER_CARVE:
			_step_river_carve()
		Stage.BIOME_CLASSIFICATION:
			_step_biome_classification()
		_:
			_fail("invalid generation stage")


func _setup_noise() -> void:
	_broad_noise = FastNoiseLite.new()
	_broad_noise.seed = _manifest.world_seed
	_broad_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_broad_noise.frequency = 1.0 / maxf(
		64.0,
		_world_size_m * _profile.broad_world_frequency_factor
	)
	_broad_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_broad_noise.fractal_octaves = _profile.broad_octaves
	_broad_noise.fractal_gain = _profile.fractal_gain
	_broad_noise.fractal_lacunarity = _profile.fractal_lacunarity

	_ridge_noise = FastNoiseLite.new()
	_ridge_noise.seed = _manifest.world_seed ^ 0x5f3759df
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge_noise.frequency = 1.0 / maxf(
		32.0,
		_world_size_m * _profile.ridge_world_frequency_factor
	)
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge_noise.fractal_octaves = _profile.ridge_octaves
	_ridge_noise.fractal_gain = clampf(_profile.fractal_gain + 0.04, 0.10, 0.90)
	_ridge_noise.fractal_lacunarity = _profile.fractal_lacunarity + 0.10

	_coast_noise = FastNoiseLite.new()
	_coast_noise.seed = _manifest.world_seed ^ 0x1f123bb5
	_coast_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_coast_noise.frequency = 1.0 / maxf(64.0, _world_size_m * 0.18)
	_coast_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_coast_noise.fractal_octaves = 3
	_coast_noise.fractal_gain = 0.50

	_moisture_noise = FastNoiseLite.new()
	_moisture_noise.seed = _manifest.world_seed ^ 0x2c1b3c6d
	_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_moisture_noise.frequency = 1.0 / maxf(64.0, _world_size_m * 0.16)
	_moisture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_moisture_noise.fractal_octaves = 3
	_moisture_noise.fractal_gain = 0.52


func _step_shape() -> void:
	if _row >= _resolution:
		_row = 0
		_stage = Stage.EROSION_PREPARE \
			if _profile.thermal_iterations > 0 and _profile.thermal_transfer_rate > 0.0 \
			else Stage.FLOW_PREPARE
		return
	var denominator: float = float(maxi(1, _resolution - 1))
	var normalized_z: float = float(_row) / denominator * 2.0 - 1.0
	var world_z: float = normalized_z * _world_size_m * 0.5
	for x in range(_resolution):
		var normalized_x: float = float(x) / denominator * 2.0 - 1.0
		var world_x: float = normalized_x * _world_size_m * 0.5
		var coast_warp: float = _coast_noise.get_noise_2d(world_x, world_z)
		var radius: float = Vector2(normalized_x, normalized_z).length() \
			* (1.0 + coast_warp * _profile.coast_warp_strength)
		var island_mask: float = 1.0 - smoothstep(
			_profile.coast_falloff_start,
			_profile.coast_falloff_end,
			radius
		)
		var broad: float = (_broad_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
		var ridge: float = 1.0 - absf(_ridge_noise.get_noise_2d(world_x, world_z))
		var raw_height: float = island_mask * (
			_profile.base_elevation
			+ broad * _profile.broad_elevation_weight
			+ ridge * _profile.ridge_weight
		) - 0.08
		var height_value: float = pow(
			clampf(raw_height, 0.0, 1.0),
			_profile.height_exponent
		) * _profile.output_height_scale
		_result.height_data[_row * _resolution + x] = clampf(height_value, 0.0, 1.0)
	_row += 1


func _prepare_erosion_iteration() -> void:
	if _erosion_iteration >= _profile.thermal_iterations:
		_erosion_scratch = PackedFloat32Array()
		_row = 0
		_stage = Stage.FLOW_PREPARE
		return
	_erosion_scratch = _result.height_data.duplicate()
	_row = 1
	_stage = Stage.EROSION


func _step_erosion() -> void:
	if _row >= _resolution - 1:
		_result.height_data = _erosion_scratch
		_erosion_iteration += 1
		_stage = Stage.EROSION_PREPARE
		return
	var talus_normalized: float = _profile.thermal_talus_m \
		/ maxf(_manifest.max_height_m, 0.001)
	for x in range(1, _resolution - 1):
		var index: int = _row * _resolution + x
		var height: float = _result.height_data[index]
		if height <= 0.001:
			continue
		var target_index: int = index - 1
		var max_difference: float = height - _result.height_data[target_index]
		var candidate_index: int = index + 1
		var difference: float = height - _result.height_data[candidate_index]
		if difference > max_difference:
			max_difference = difference
			target_index = candidate_index
		candidate_index = index - _resolution
		difference = height - _result.height_data[candidate_index]
		if difference > max_difference:
			max_difference = difference
			target_index = candidate_index
		candidate_index = index + _resolution
		difference = height - _result.height_data[candidate_index]
		if difference > max_difference:
			max_difference = difference
			target_index = candidate_index
		if max_difference > talus_normalized:
			var transfer: float = (max_difference - talus_normalized) \
				* _profile.thermal_transfer_rate
			_erosion_scratch[index] = maxf(0.0, _erosion_scratch[index] - transfer)
			_erosion_scratch[target_index] = minf(
				1.0,
				_erosion_scratch[target_index] + transfer
			)
	_row += 1


func _prepare_flow() -> void:
	var count: int = _resolution * _resolution
	_downstream.resize(count)
	_downstream.fill(-1)
	_result.flow_accumulation.resize(count)
	_result.flow_accumulation.fill(1.0)
	_height_bucket_counts.resize(FLOW_BUCKET_COUNT)
	_height_bucket_counts.fill(0)
	_height_bucket_offsets.resize(FLOW_BUCKET_COUNT + 1)
	_height_bucket_offsets.fill(0)
	_height_bucket_cursors.resize(FLOW_BUCKET_COUNT)
	_height_bucket_cursors.fill(0)
	_height_order.resize(count)
	_height_order.fill(-1)
	_row = 0
	_stage = Stage.FLOW_DIRECTION


func _step_flow_direction() -> void:
	if _row >= _resolution:
		_stage = Stage.FLOW_ORDER_PREPARE
		return
	for x in range(_resolution):
		var index: int = _row * _resolution + x
		var height: float = _result.height_data[index]
		var bucket: int = _height_bucket_for(height)
		_height_bucket_counts[bucket] += 1
		var lowest_height: float = height
		var lowest_index: int = -1
		for offset_y in range(-1, 2):
			for offset_x in range(-1, 2):
				if offset_x == 0 and offset_y == 0:
					continue
				var neighbor_x: int = x + offset_x
				var neighbor_y: int = _row + offset_y
				if neighbor_x < 0 or neighbor_y < 0 \
					or neighbor_x >= _resolution or neighbor_y >= _resolution:
					continue
				var neighbor_index: int = neighbor_y * _resolution + neighbor_x
				var neighbor_height: float = _result.height_data[neighbor_index]
				if neighbor_height < lowest_height:
					lowest_height = neighbor_height
					lowest_index = neighbor_index
		_downstream[index] = lowest_index
	_row += 1


func _prepare_flow_order() -> void:
	var running_offset: int = 0
	for bucket in range(FLOW_BUCKET_COUNT):
		_height_bucket_offsets[bucket] = running_offset
		_height_bucket_cursors[bucket] = running_offset
		running_offset += _height_bucket_counts[bucket]
	_height_bucket_offsets[FLOW_BUCKET_COUNT] = running_offset
	_row = 0
	_stage = Stage.FLOW_ORDER_FILL


func _step_flow_order_fill() -> void:
	if _row >= _resolution:
		_flow_cursor = _height_order.size() - 1
		_stage = Stage.FLOW_ACCUMULATION
		return
	for x in range(_resolution):
		var index: int = _row * _resolution + x
		var bucket: int = _height_bucket_for(_result.height_data[index])
		var order_index: int = _height_bucket_cursors[bucket]
		_height_order[order_index] = index
		_height_bucket_cursors[bucket] = order_index + 1
	_row += 1


func _step_flow_accumulation() -> void:
	var processed: int = 0
	while _flow_cursor >= 0 and processed < FLOW_CHUNK_SIZE:
		var index: int = _height_order[_flow_cursor]
		var downstream_index: int = _downstream[index]
		if downstream_index >= 0:
			_result.flow_accumulation[downstream_index] += \
				_result.flow_accumulation[index]
		_flow_cursor -= 1
		processed += 1
	if _flow_cursor < 0:
		_clear_flow_sort_working_data()
		_row = 0
		_stage = Stage.RIVER_CARVE \
			if _profile.rivers_enabled else Stage.BIOME_CLASSIFICATION


func _step_river_carve() -> void:
	if _row >= _resolution:
		_row = 0
		_stage = Stage.BIOME_CLASSIFICATION
		return
	var threshold: float = float(_resolution * _resolution) \
		* _profile.river_accumulation_fraction
	var depth_normalized: float = _profile.river_depth_m \
		/ maxf(_manifest.max_height_m, 0.001)
	for x in range(_resolution):
		var index: int = _row * _resolution + x
		var height: float = _result.height_data[index]
		var flow: float = _result.flow_accumulation[index]
		if height <= _profile.river_min_elevation or flow <= threshold:
			continue
		var intensity: float = smoothstep(threshold, threshold * 8.0, flow)
		_result.height_data[index] = maxf(
			0.0,
			height - depth_normalized * intensity
		)
		_result.river_mask[index] = clampi(roundi(intensity * 255.0), 0, 255)
	_row += 1


func _step_biome_classification() -> void:
	if _row >= _resolution:
		_stage = Stage.COMPLETE
		_release_working_data()
		return
	var denominator: float = float(maxi(1, _resolution - 1))
	var normalized_z: float = float(_row) / denominator * 2.0 - 1.0
	var world_z: float = normalized_z * _world_size_m * 0.5
	for x in range(_resolution):
		var index: int = _row * _resolution + x
		var height: float = _result.height_data[index]
		var normalized_x: float = float(x) / denominator * 2.0 - 1.0
		var world_x: float = normalized_x * _world_size_m * 0.5
		var noise_moisture: float = (
			_moisture_noise.get_noise_2d(world_x, world_z) + 1.0
		) * 0.5
		var river_influence: float = float(_result.river_mask[index]) / 255.0
		var lowland_moisture: float = 1.0 - smoothstep(0.10, 0.50, height)
		var moisture: float = clampf(
			noise_moisture * 0.58
			+ river_influence * 0.85
			+ lowland_moisture * 0.20,
			0.0,
			1.0
		)
		_result.moisture_data[index] = clampi(roundi(moisture * 255.0), 0, 255)
		var slope: float = _sample_slope(x, _row)
		_result.biome_data[index] = _classify_biome(
			height,
			slope,
			moisture,
			river_influence
		)
	_row += 1


func _height_bucket_for(height: float) -> int:
	return clampi(
		floori(clampf(height, 0.0, 1.0) * float(FLOW_BUCKET_COUNT - 1)),
		0,
		FLOW_BUCKET_COUNT - 1
	)


func _sample_slope(x: int, y: int) -> float:
	var center: float = _result.height_data[y * _resolution + x]
	var left: float = _result.height_data[y * _resolution + maxi(0, x - 1)]
	var right: float = _result.height_data[
		y * _resolution + mini(_resolution - 1, x + 1)
	]
	var down: float = _result.height_data[maxi(0, y - 1) * _resolution + x]
	var up: float = _result.height_data[
		mini(_resolution - 1, y + 1) * _resolution + x
	]
	return maxf(
		maxf(absf(center - left), absf(center - right)),
		maxf(absf(center - down), absf(center - up))
	)


func _classify_biome(
	height: float,
	slope: float,
	moisture: float,
	river_influence: float
) -> int:
	if height <= 0.001:
		return Result.Biome.OCEAN
	if height <= _profile.beach_max_elevation:
		return Result.Biome.BEACH
	if slope >= _profile.cliff_slope_threshold:
		return Result.Biome.CLIFF
	if river_influence >= 0.30 and height <= _profile.wetland_max_elevation:
		return Result.Biome.WETLAND
	if height >= _profile.mountain_min_elevation:
		return Result.Biome.MOUNTAIN
	if height >= _profile.highland_min_elevation:
		return Result.Biome.HIGHLAND
	if moisture >= _profile.forest_moisture_threshold:
		return Result.Biome.FOREST
	return Result.Biome.GRASSLAND


func _clear_flow_sort_working_data() -> void:
	_downstream = PackedInt32Array()
	_height_bucket_counts = PackedInt32Array()
	_height_bucket_offsets = PackedInt32Array()
	_height_bucket_cursors = PackedInt32Array()
	_height_order = PackedInt32Array()
	_flow_cursor = -1


func _release_working_data() -> void:
	_erosion_scratch = PackedFloat32Array()
	_clear_flow_sort_working_data()
	_broad_noise = null
	_ridge_noise = null
	_coast_noise = null
	_moisture_noise = null


func _fail(message: String) -> void:
	_error_message = message
	_stage = Stage.FAILED
	_release_working_data()
