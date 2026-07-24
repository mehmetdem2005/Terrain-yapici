@tool
extends Resource
class_name IslandTerrainGenerationProfile

@export_category("Island Shape")
@export_range(0.30, 0.90, 0.01) var coast_falloff_start: float = 0.58
@export_range(0.60, 1.40, 0.01) var coast_falloff_end: float = 1.00
@export_range(0.0, 0.40, 0.01) var coast_warp_strength: float = 0.16
@export_range(0.0, 0.50, 0.01) var base_elevation: float = 0.12
@export_range(0.0, 1.0, 0.01) var broad_elevation_weight: float = 0.58
@export_range(0.0, 1.0, 0.01) var ridge_weight: float = 0.30
@export_range(0.50, 3.0, 0.01) var height_exponent: float = 1.28
@export_range(0.10, 1.0, 0.01) var output_height_scale: float = 0.72

@export_category("Noise")
@export_range(0.05, 1.0, 0.01) var broad_world_frequency_factor: float = 0.23
@export_range(0.03, 0.50, 0.01) var ridge_world_frequency_factor: float = 0.11
@export_range(1, 8, 1) var broad_octaves: int = 5
@export_range(1, 8, 1) var ridge_octaves: int = 4
@export_range(0.10, 0.90, 0.01) var fractal_gain: float = 0.48
@export_range(1.20, 4.0, 0.01) var fractal_lacunarity: float = 2.05

@export_category("Thermal Erosion")
@export_range(0, 8, 1) var thermal_iterations: int = 2
@export_range(0.0, 32.0, 0.1) var thermal_talus_m: float = 4.0
@export_range(0.0, 0.50, 0.01) var thermal_transfer_rate: float = 0.22

@export_category("Rivers")
@export var rivers_enabled: bool = true
@export_range(0.0001, 0.10, 0.0001) var river_accumulation_fraction: float = 0.006
@export_range(0.0, 64.0, 0.1) var river_depth_m: float = 8.0
@export_range(0.0, 0.50, 0.01) var river_min_elevation: float = 0.04

@export_category("Biomes")
@export_range(0.0, 0.30, 0.01) var beach_max_elevation: float = 0.055
@export_range(0.0, 0.60, 0.01) var wetland_max_elevation: float = 0.18
@export_range(0.10, 0.90, 0.01) var highland_min_elevation: float = 0.48
@export_range(0.20, 1.0, 0.01) var mountain_min_elevation: float = 0.70
@export_range(0.01, 0.40, 0.01) var cliff_slope_threshold: float = 0.12
@export_range(0.0, 1.0, 0.01) var forest_moisture_threshold: float = 0.52


func sanitize() -> void:
	coast_falloff_start = clampf(coast_falloff_start, 0.30, 0.90)
	coast_falloff_end = clampf(coast_falloff_end, coast_falloff_start + 0.01, 1.40)
	coast_warp_strength = clampf(coast_warp_strength, 0.0, 0.40)
	base_elevation = clampf(base_elevation, 0.0, 0.50)
	broad_elevation_weight = clampf(broad_elevation_weight, 0.0, 1.0)
	ridge_weight = clampf(ridge_weight, 0.0, 1.0)
	height_exponent = clampf(height_exponent, 0.50, 3.0)
	output_height_scale = clampf(output_height_scale, 0.10, 1.0)
	broad_world_frequency_factor = clampf(broad_world_frequency_factor, 0.05, 1.0)
	ridge_world_frequency_factor = clampf(ridge_world_frequency_factor, 0.03, 0.50)
	broad_octaves = clampi(broad_octaves, 1, 8)
	ridge_octaves = clampi(ridge_octaves, 1, 8)
	fractal_gain = clampf(fractal_gain, 0.10, 0.90)
	fractal_lacunarity = clampf(fractal_lacunarity, 1.20, 4.0)
	thermal_iterations = clampi(thermal_iterations, 0, 8)
	thermal_talus_m = clampf(thermal_talus_m, 0.0, 32.0)
	thermal_transfer_rate = clampf(thermal_transfer_rate, 0.0, 0.50)
	river_accumulation_fraction = clampf(river_accumulation_fraction, 0.0001, 0.10)
	river_depth_m = clampf(river_depth_m, 0.0, 64.0)
	river_min_elevation = clampf(river_min_elevation, 0.0, 0.50)
	beach_max_elevation = clampf(beach_max_elevation, 0.0, 0.30)
	wetland_max_elevation = clampf(wetland_max_elevation, beach_max_elevation, 0.60)
	highland_min_elevation = clampf(highland_min_elevation, wetland_max_elevation, 0.90)
	mountain_min_elevation = clampf(mountain_min_elevation, highland_min_elevation, 1.0)
	cliff_slope_threshold = clampf(cliff_slope_threshold, 0.01, 0.40)
	forest_moisture_threshold = clampf(forest_moisture_threshold, 0.0, 1.0)
