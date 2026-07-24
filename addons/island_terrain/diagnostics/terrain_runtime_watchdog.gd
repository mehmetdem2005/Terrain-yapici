@tool
extends Node
class_name IslandTerrainRuntimeWatchdog

const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Policy = preload("res://addons/island_terrain/diagnostics/terrain_health_policy.gd")
const Snapshot = preload("res://addons/island_terrain/diagnostics/terrain_health_snapshot.gd")
const Evaluator = preload("res://addons/island_terrain/diagnostics/terrain_health_evaluator.gd")
const QualityController = preload("res://addons/island_terrain/diagnostics/terrain_runtime_quality_controller.gd")

signal snapshot_updated(snapshot: Snapshot)
signal pressure_changed(level: int, reasons: PackedStringArray)
signal runtime_quality_changed(level: int)

const CUSTOM_MONITOR_NAMES := [
	&"IslandTerrain/Region Cache MB",
	&"IslandTerrain/Generation Working MB",
	&"IslandTerrain/Material Working MB",
	&"IslandTerrain/Collision Patches",
	&"IslandTerrain/Pressure Level",
	&"IslandTerrain/Runtime Quality Reduction",
]

var _policy: Policy
var _budget: Budget
var _quality_controller: QualityController
var _region_cache_bytes_provider: Callable
var _cached_region_count_provider: Callable
var _dirty_region_count_provider: Callable
var _generation_bytes_provider: Callable
var _material_bytes_provider: Callable
var _active_clipmap_provider: Callable
var _pending_clipmap_provider: Callable
var _active_collision_provider: Callable
var _pending_collision_provider: Callable
var _clear_clean_cache_callback: Callable
var _evaluator := Evaluator.new()
var _last_snapshot: Snapshot
var _sample_accumulator: float = 0.0
var _last_pressure_level: int = Snapshot.PressureLevel.NORMAL
var _auto_protection_enabled: bool = true
var _custom_monitors_registered: bool = false


func configure(
	policy: Policy,
	budget: Budget,
	quality_controller: QualityController,
	region_cache_bytes_provider: Callable,
	cached_region_count_provider: Callable,
	dirty_region_count_provider: Callable,
	generation_bytes_provider: Callable,
	material_bytes_provider: Callable,
	active_clipmap_provider: Callable,
	pending_clipmap_provider: Callable,
	active_collision_provider: Callable,
	pending_collision_provider: Callable,
	clear_clean_cache_callback: Callable
) -> Error:
	if policy == null or budget == null or quality_controller == null:
		return ERR_INVALID_PARAMETER
	_policy = policy
	_budget = budget
	_quality_controller = quality_controller
	_region_cache_bytes_provider = region_cache_bytes_provider
	_cached_region_count_provider = cached_region_count_provider
	_dirty_region_count_provider = dirty_region_count_provider
	_generation_bytes_provider = generation_bytes_provider
	_material_bytes_provider = material_bytes_provider
	_active_clipmap_provider = active_clipmap_provider
	_pending_clipmap_provider = pending_clipmap_provider
	_active_collision_provider = active_collision_provider
	_pending_collision_provider = pending_collision_provider
	_clear_clean_cache_callback = clear_clean_cache_callback
	_policy.sanitize()
	_budget.sanitize(Engine.is_editor_hint())
	_sample_accumulator = 0.0
	_evaluator.reset()
	_auto_protection_enabled = not Engine.is_editor_hint()
	_register_custom_monitors()
	set_process(true)
	return OK


func _exit_tree() -> void:
	_remove_custom_monitors()


func set_auto_protection_enabled(value: bool) -> void:
	_auto_protection_enabled = value


func is_auto_protection_enabled() -> bool:
	return _auto_protection_enabled


func get_last_snapshot() -> Snapshot:
	return _last_snapshot.duplicate_snapshot() if _last_snapshot != null else null


func sample_now() -> Snapshot:
	if _policy == null or _budget == null or _quality_controller == null:
		return null
	var snapshot := Snapshot.new()
	snapshot.timestamp_msec = Time.get_ticks_msec()
	snapshot.fps = float(Performance.get_monitor(Performance.TIME_FPS))
	snapshot.process_time_ms = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	snapshot.physics_time_ms = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	snapshot.static_memory_bytes = maxi(0, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	snapshot.video_memory_bytes = maxi(0, int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)))
	snapshot.texture_memory_bytes = maxi(0, int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)))
	snapshot.draw_calls = maxi(0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	snapshot.node_count = maxi(0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	snapshot.region_cache_bytes = _call_non_negative_int(_region_cache_bytes_provider)
	snapshot.cached_region_count = _call_non_negative_int(_cached_region_count_provider)
	snapshot.dirty_region_count = _call_non_negative_int(_dirty_region_count_provider)
	snapshot.generation_working_bytes = _call_non_negative_int(_generation_bytes_provider)
	snapshot.material_working_bytes = _call_non_negative_int(_material_bytes_provider)
	snapshot.active_clipmap_levels = _call_non_negative_int(_active_clipmap_provider)
	snapshot.pending_clipmap_levels = _call_non_negative_int(_pending_clipmap_provider)
	snapshot.active_collision_patches = _call_non_negative_int(_active_collision_provider)
	snapshot.pending_collision_builds = _call_non_negative_int(_pending_collision_provider)
	snapshot.runtime_quality_level = _quality_controller.current_level()

	var evaluation: Dictionary = _evaluator.evaluate(
		snapshot,
		_policy,
		_budget,
		snapshot.runtime_quality_level,
		snapshot.timestamp_msec
	)
	snapshot.pressure_level = int(evaluation.get(
		"pressure_level",
		Snapshot.PressureLevel.NORMAL
	))
	snapshot.pressure_reasons = evaluation.get(
		"reasons",
		PackedStringArray()
	) as PackedStringArray

	if bool(evaluation.get("clear_clean_cache", false)) \
		and _clear_clean_cache_callback.is_valid():
		_clear_clean_cache_callback.call()

	if _auto_protection_enabled:
		var quality_delta: int = int(evaluation.get("quality_delta", 0))
		if quality_delta != 0:
			var target_level: int = _quality_controller.current_level() + quality_delta
			var error: Error = _quality_controller.set_level(target_level)
			if error == OK:
				snapshot.runtime_quality_level = _quality_controller.current_level()
				runtime_quality_changed.emit(snapshot.runtime_quality_level)

	_last_snapshot = snapshot
	if snapshot.pressure_level != _last_pressure_level:
		_last_pressure_level = snapshot.pressure_level
		pressure_changed.emit(snapshot.pressure_level, snapshot.pressure_reasons)
	snapshot_updated.emit(snapshot.duplicate_snapshot())
	return snapshot.duplicate_snapshot()


func _process(delta: float) -> void:
	if _policy == null:
		return
	_sample_accumulator += delta
	if _sample_accumulator < _policy.sample_interval_s:
		return
	_sample_accumulator = fmod(_sample_accumulator, _policy.sample_interval_s)
	sample_now()


func _register_custom_monitors() -> void:
	_remove_custom_monitors()
	if _policy == null or not _policy.register_custom_performance_monitors:
		return
	Performance.add_custom_monitor(CUSTOM_MONITOR_NAMES[0], Callable(self, "_monitor_region_cache_mb"))
	Performance.add_custom_monitor(CUSTOM_MONITOR_NAMES[1], Callable(self, "_monitor_generation_mb"))
	Performance.add_custom_monitor(CUSTOM_MONITOR_NAMES[2], Callable(self, "_monitor_material_mb"))
	Performance.add_custom_monitor(CUSTOM_MONITOR_NAMES[3], Callable(self, "_monitor_collision_patches"))
	Performance.add_custom_monitor(CUSTOM_MONITOR_NAMES[4], Callable(self, "_monitor_pressure_level"))
	Performance.add_custom_monitor(CUSTOM_MONITOR_NAMES[5], Callable(self, "_monitor_quality_level"))
	_custom_monitors_registered = true


func _remove_custom_monitors() -> void:
	if not _custom_monitors_registered:
		return
	for monitor_name in CUSTOM_MONITOR_NAMES:
		Performance.remove_custom_monitor(monitor_name)
	_custom_monitors_registered = false


func _call_non_negative_int(callback: Callable) -> int:
	return maxi(0, int(callback.call())) if callback.is_valid() else 0


func _monitor_region_cache_mb() -> float:
	return float(_call_non_negative_int(_region_cache_bytes_provider)) / float(1024 * 1024)


func _monitor_generation_mb() -> float:
	return float(_call_non_negative_int(_generation_bytes_provider)) / float(1024 * 1024)


func _monitor_material_mb() -> float:
	return float(_call_non_negative_int(_material_bytes_provider)) / float(1024 * 1024)


func _monitor_collision_patches() -> int:
	return _call_non_negative_int(_active_collision_provider)


func _monitor_pressure_level() -> int:
	return _last_snapshot.pressure_level \
		if _last_snapshot != null else Snapshot.PressureLevel.NORMAL


func _monitor_quality_level() -> int:
	return _quality_controller.current_level() if _quality_controller != null else 0
