@tool
extends Resource
class_name IslandTerrainHealthPolicy

@export_category("Sampling")
@export_range(0.25, 5.0, 0.25) var sample_interval_s: float = 1.0
@export_range(5.0, 60.0, 1.0) var low_fps_threshold: float = 24.0
@export_range(10.0, 90.0, 1.0) var recovery_fps_threshold: float = 38.0
@export_range(1, 10, 1) var consecutive_bad_samples: int = 3
@export_range(2, 30, 1) var consecutive_good_samples: int = 10

@export_category("Memory Pressure")
@export_range(0.50, 0.95, 0.01) var memory_soft_ratio: float = 0.82
@export_range(0.60, 0.99, 0.01) var memory_hard_ratio: float = 0.93
@export_range(0.70, 1.20, 0.01) var memory_critical_ratio: float = 1.00
@export_range(0.50, 0.95, 0.01) var vram_soft_ratio: float = 0.84
@export_range(0.60, 0.99, 0.01) var vram_hard_ratio: float = 0.94

@export_category("Automatic Protection")
@export var auto_degrade_enabled: bool = true
@export var auto_recover_enabled: bool = false
@export_range(5.0, 120.0, 1.0) var quality_change_cooldown_s: float = 20.0
@export_range(0, 3, 1) var maximum_quality_reduction: int = 3
@export var clear_clean_cache_on_hard_pressure: bool = true
@export var register_custom_performance_monitors: bool = true


func sanitize() -> void:
	sample_interval_s = clampf(sample_interval_s, 0.25, 5.0)
	low_fps_threshold = clampf(low_fps_threshold, 5.0, 60.0)
	recovery_fps_threshold = clampf(
		recovery_fps_threshold,
		low_fps_threshold + 1.0,
		90.0
	)
	consecutive_bad_samples = clampi(consecutive_bad_samples, 1, 10)
	consecutive_good_samples = clampi(consecutive_good_samples, 2, 30)
	memory_soft_ratio = clampf(memory_soft_ratio, 0.50, 0.95)
	memory_hard_ratio = clampf(memory_hard_ratio, memory_soft_ratio + 0.01, 0.99)
	memory_critical_ratio = clampf(memory_critical_ratio, memory_hard_ratio + 0.01, 1.20)
	vram_soft_ratio = clampf(vram_soft_ratio, 0.50, 0.95)
	vram_hard_ratio = clampf(vram_hard_ratio, vram_soft_ratio + 0.01, 0.99)
	quality_change_cooldown_s = clampf(quality_change_cooldown_s, 5.0, 120.0)
	maximum_quality_reduction = clampi(maximum_quality_reduction, 0, 3)
