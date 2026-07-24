@tool
extends Node
class_name IslandTerrainMetadataTextureBuilder

const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Result = preload("res://addons/island_terrain/generation/terrain_generation_result.gd")

enum Stage {
	IDLE,
	SCAN_FLOW,
	ENCODE,
	COMPLETE,
	FAILED,
	CANCELLED,
}

signal build_progress(progress: float)
signal build_completed(texture: ImageTexture)
signal build_failed(message: String)
signal build_cancelled

var _result: Result
var _budget: Budget
var _stage: int = Stage.IDLE
var _row: int = 0
var _max_flow: float = 1.0
var _rgba_data: PackedByteArray = PackedByteArray()
var _error_message: String = ""


func start(result: Result, budget: Budget) -> Error:
	if result == null or budget == null:
		return ERR_INVALID_PARAMETER
	var errors: PackedStringArray = result.validate()
	if not errors.is_empty():
		_error_message = "; ".join(errors)
		_stage = Stage.FAILED
		build_failed.emit(_error_message)
		return ERR_INVALID_DATA
	_result = result
	_budget = budget
	_budget.sanitize(Engine.is_editor_hint())
	_rgba_data.resize(_result.resolution * _result.resolution * 4)
	_rgba_data.fill(0)
	_row = 0
	_max_flow = 1.0
	_error_message = ""
	_stage = Stage.SCAN_FLOW
	set_process(true)
	build_progress.emit(0.0)
	return OK


func cancel() -> void:
	if _stage in [Stage.IDLE, Stage.COMPLETE, Stage.FAILED, Stage.CANCELLED]:
		return
	_stage = Stage.CANCELLED
	_rgba_data = PackedByteArray()
	set_process(false)
	build_cancelled.emit()


func is_running() -> bool:
	return _stage in [Stage.SCAN_FLOW, Stage.ENCODE]


func estimated_working_memory_bytes() -> int:
	return _rgba_data.size()


func _process(_delta: float) -> void:
	if not is_running():
		return
	var budget_usec: int = maxi(250, int(_budget.frame_work_budget_ms * 500.0))
	var start_usec: int = Time.get_ticks_usec()
	while Time.get_ticks_usec() - start_usec < budget_usec:
		if _stage == Stage.SCAN_FLOW:
			_step_scan_flow()
		elif _stage == Stage.ENCODE:
			_step_encode()
		else:
			break


func _step_scan_flow() -> void:
	if _row >= _result.resolution:
		_row = 0
		_stage = Stage.ENCODE
		build_progress.emit(0.15)
		return
	var start_index: int = _row * _result.resolution
	var end_index: int = start_index + _result.resolution
	for index in range(start_index, end_index):
		if _result.flow_accumulation.size() > index:
			_max_flow = maxf(_max_flow, _result.flow_accumulation[index])
	_row += 1
	build_progress.emit(float(_row) / float(_result.resolution) * 0.15)


func _step_encode() -> void:
	if _row >= _result.resolution:
		_finalize_texture()
		return
	var denominator: float = log(1.0 + maxf(_max_flow, 1.0))
	for x in range(_result.resolution):
		var index: int = _row * _result.resolution + x
		var target: int = index * 4
		var biome_normalized: float = float(_result.biome_data[index]) \
			/ float(maxi(1, Result.Biome.size() - 1))
		var flow: float = _result.flow_accumulation[index] \
			if _result.flow_accumulation.size() > index else 1.0
		var flow_normalized: float = log(1.0 + maxf(flow, 0.0)) / denominator
		_rgba_data[target] = clampi(roundi(biome_normalized * 255.0), 0, 255)
		_rgba_data[target + 1] = _result.moisture_data[index]
		_rgba_data[target + 2] = _result.river_mask[index]
		_rgba_data[target + 3] = clampi(roundi(flow_normalized * 255.0), 0, 255)
	_row += 1
	build_progress.emit(0.15 + float(_row) / float(_result.resolution) * 0.85)


func _finalize_texture() -> void:
	var image := Image.create_from_data(
		_result.resolution,
		_result.resolution,
		false,
		Image.FORMAT_RGBA8,
		_rgba_data
	)
	if image == null or image.is_empty():
		_fail("failed to create terrain metadata image")
		return
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	if texture == null:
		_fail("failed to create terrain metadata texture")
		return
	_rgba_data = PackedByteArray()
	_stage = Stage.COMPLETE
	set_process(false)
	build_progress.emit(1.0)
	build_completed.emit(texture)


func _fail(message: String) -> void:
	_error_message = message
	_stage = Stage.FAILED
	_rgba_data = PackedByteArray()
	set_process(false)
	build_failed.emit(message)
