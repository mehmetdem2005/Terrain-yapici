@tool
extends RefCounted
class_name IslandTerrainHealthEvaluator

const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Policy = preload("res://addons/island_terrain/diagnostics/terrain_health_policy.gd")
const Snapshot = preload("res://addons/island_terrain/diagnostics/terrain_health_snapshot.gd")

var _bad_streak: int = 0
var _good_streak: int = 0
var _last_quality_change_msec: int = -1


func reset() -> void:
	_bad_streak = 0
	_good_streak = 0
	_last_quality_change_msec = -1


func evaluate(
	snapshot: Snapshot,
	policy: Policy,
	budget: Budget,
	current_quality_reduction: int,
	now_msec: int
) -> Dictionary:
	if snapshot == null or policy == null or budget == null:
		return {
			"pressure_level": Snapshot.PressureLevel.NORMAL,
			"reasons": PackedStringArray(),
			"clear_clean_cache": false,
			"quality_delta": 0,
		}
	policy.sanitize()
	budget.sanitize(Engine.is_editor_hint())

	var reasons := PackedStringArray()
	var pressure: int = Snapshot.PressureLevel.NORMAL
	var owned_ratio: float = float(snapshot.terrain_owned_memory_bytes()) \
		/ float(maxi(1, budget.terrain_ram_budget_bytes()))
	var video_ratio: float = 0.0
	if snapshot.video_memory_bytes > 0:
		video_ratio = float(snapshot.video_memory_bytes) \
			/ float(maxi(1, budget.terrain_vram_budget_bytes()))

	if owned_ratio >= policy.memory_critical_ratio:
		pressure = Snapshot.PressureLevel.CRITICAL
		reasons.append("terrain_ram_critical")
	elif owned_ratio >= policy.memory_hard_ratio:
		pressure = maxi(pressure, Snapshot.PressureLevel.HARD)
		reasons.append("terrain_ram_hard")
	elif owned_ratio >= policy.memory_soft_ratio:
		pressure = maxi(pressure, Snapshot.PressureLevel.SOFT)
		reasons.append("terrain_ram_soft")

	if video_ratio >= policy.vram_hard_ratio:
		pressure = maxi(pressure, Snapshot.PressureLevel.HARD)
		reasons.append("video_memory_hard")
	elif video_ratio >= policy.vram_soft_ratio:
		pressure = maxi(pressure, Snapshot.PressureLevel.SOFT)
		reasons.append("video_memory_soft")

	if snapshot.fps > 0.0 and snapshot.fps < policy.low_fps_threshold:
		pressure = maxi(pressure, Snapshot.PressureLevel.SOFT)
		reasons.append("low_fps")

	if pressure > Snapshot.PressureLevel.NORMAL:
		_bad_streak += 1
		_good_streak = 0
	else:
		_bad_streak = 0
		if snapshot.fps <= 0.0 or snapshot.fps >= policy.recovery_fps_threshold:
			_good_streak += 1
		else:
			_good_streak = 0

	var cooldown_msec: int = int(policy.quality_change_cooldown_s * 1000.0)
	var cooldown_ready: bool = _last_quality_change_msec < 0 \
		or now_msec - _last_quality_change_msec >= cooldown_msec
	var quality_delta: int = 0
	var critical_now: bool = pressure >= Snapshot.PressureLevel.CRITICAL
	var sustained_pressure: bool = _bad_streak >= policy.consecutive_bad_samples

	if policy.auto_degrade_enabled \
		and current_quality_reduction < policy.maximum_quality_reduction \
		and cooldown_ready \
		and (critical_now or sustained_pressure):
		quality_delta = 1
		_last_quality_change_msec = now_msec
		_bad_streak = 0

	if quality_delta == 0 \
		and policy.auto_recover_enabled \
		and current_quality_reduction > 0 \
		and cooldown_ready \
		and pressure == Snapshot.PressureLevel.NORMAL \
		and _good_streak >= policy.consecutive_good_samples:
		quality_delta = -1
		_last_quality_change_msec = now_msec
		_good_streak = 0

	return {
		"pressure_level": pressure,
		"reasons": reasons,
		"clear_clean_cache": policy.clear_clean_cache_on_hard_pressure \
			and pressure >= Snapshot.PressureLevel.HARD,
		"quality_delta": quality_delta,
		"bad_streak": _bad_streak,
		"good_streak": _good_streak,
		"terrain_memory_ratio": owned_ratio,
		"video_memory_ratio": video_ratio,
	}
