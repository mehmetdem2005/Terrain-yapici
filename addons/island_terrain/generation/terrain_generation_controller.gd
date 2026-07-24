@tool
extends Node
class_name IslandTerrainGenerationController

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Profile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")
const Job = preload("res://addons/island_terrain/generation/terrain_generation_job.gd")
const Result = preload("res://addons/island_terrain/generation/terrain_generation_result.gd")

signal generation_progress(progress: float, stage_name: String)
signal generation_completed(result: Result)
signal generation_failed(message: String)
signal generation_cancelled

var _manifest: Manifest
var _budget: Budget
var _profile: Profile
var _job: Job
var _running: bool = false


func configure(manifest: Manifest, budget: Budget, profile: Profile) -> void:
	_manifest = manifest
	_budget = budget
	_profile = profile


func start(resolution: int) -> Error:
	if _manifest == null or _budget == null:
		return ERR_UNCONFIGURED
	if _profile == null:
		_profile = Profile.new()
	if _job != null and _running:
		_job.cancel()
	_job = Job.new()
	var error: Error = _job.begin(_manifest, _profile, resolution)
	if error != OK:
		generation_failed.emit(_job.error_message())
		return error
	_running = true
	set_process(true)
	generation_progress.emit(0.0, _job.stage_name())
	return OK


func cancel() -> void:
	if _job == null or not _running:
		return
	_job.cancel()
	_running = false
	set_process(false)
	generation_cancelled.emit()


func is_running() -> bool:
	return _running


func progress() -> float:
	return _job.progress() if _job != null else 0.0


func stage_name() -> String:
	return _job.stage_name() if _job != null else "Idle"


func estimated_working_memory_bytes() -> int:
	return _job.estimated_working_memory_bytes() if _job != null else 0


func _process(_delta: float) -> void:
	if not _running or _job == null:
		return
	var budget_usec: int = maxi(250, int(_budget.frame_work_budget_ms * 1000.0))
	_job.process_budget(budget_usec)
	generation_progress.emit(_job.progress(), _job.stage_name())
	if _job.has_failed():
		_running = false
		set_process(false)
		generation_failed.emit(_job.error_message())
	elif _job.is_cancelled():
		_running = false
		set_process(false)
		generation_cancelled.emit()
	elif _job.is_complete():
		_running = false
		set_process(false)
		generation_progress.emit(1.0, _job.stage_name())
		generation_completed.emit(_job.result())
