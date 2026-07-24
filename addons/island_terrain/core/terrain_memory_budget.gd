@tool
extends Resource
class_name IslandTerrainMemoryBudget

const Constants = preload("res://addons/island_terrain/core/terrain_constants.gd")

enum DeviceProfile {
	LOW,
	BALANCED,
	HIGH,
	EDITOR_PREVIEW,
}

@export_enum("Low", "Balanced", "High", "Editor Preview") var profile: int = DeviceProfile.BALANCED
@export_range(1, 49, 1) var max_cached_regions: int = Constants.DEFAULT_MAX_CACHED_REGIONS
@export_range(65, 1025, 64) var macro_height_resolution: int = Constants.MOBILE_MACRO_RESOLUTION
@export_range(3, 7, 1) var clipmap_levels: int = Constants.DEFAULT_CLIPMAP_LEVELS
@export_range(16, 96, 2) var base_quads: int = Constants.DEFAULT_BASE_QUADS
@export_range(0, 7, 1) var shadow_lod_count: int = 3
@export_range(0.25, 4.0, 0.25) var frame_work_budget_ms: float = Constants.DEFAULT_FRAME_WORK_BUDGET_MS
@export_range(32.0, 256.0, 16.0) var collision_radius_m: float = Constants.DEFAULT_COLLISION_RADIUS_M
@export_range(32, 512, 16) var terrain_ram_budget_mb: int = 128
@export_range(32, 768, 16) var terrain_vram_budget_mb: int = 160
@export_range(0.50, 0.95, 0.01) var allocation_safety_ratio: float = 0.82


static func create_for_profile(target_profile: int) -> IslandTerrainMemoryBudget:
	var budget := IslandTerrainMemoryBudget.new()
	budget.profile = clampi(target_profile, DeviceProfile.LOW, DeviceProfile.EDITOR_PREVIEW)
	match budget.profile:
		DeviceProfile.LOW:
			budget.max_cached_regions = 5
			budget.macro_height_resolution = 257
			budget.clipmap_levels = 5
			budget.base_quads = 48
			budget.shadow_lod_count = 1
			budget.frame_work_budget_ms = 1.0
			budget.collision_radius_m = 64.0
			budget.terrain_ram_budget_mb = 80
			budget.terrain_vram_budget_mb = 96
			budget.allocation_safety_ratio = 0.78
		DeviceProfile.BALANCED:
			budget.max_cached_regions = 9
			budget.macro_height_resolution = 257
			budget.clipmap_levels = 6
			budget.base_quads = 64
			budget.shadow_lod_count = 2
			budget.frame_work_budget_ms = 2.0
			budget.collision_radius_m = 96.0
			budget.terrain_ram_budget_mb = 128
			budget.terrain_vram_budget_mb = 160
			budget.allocation_safety_ratio = 0.82
		DeviceProfile.HIGH:
			budget.max_cached_regions = 25
			budget.macro_height_resolution = 513
			budget.clipmap_levels = 7
			budget.base_quads = 80
			budget.shadow_lod_count = 4
			budget.frame_work_budget_ms = 3.0
			budget.collision_radius_m = 160.0
			budget.terrain_ram_budget_mb = 224
			budget.terrain_vram_budget_mb = 320
			budget.allocation_safety_ratio = 0.85
		DeviceProfile.EDITOR_PREVIEW:
			budget.max_cached_regions = 9
			budget.macro_height_resolution = 513
			budget.clipmap_levels = 7
			budget.base_quads = 64
			budget.shadow_lod_count = 2
			budget.frame_work_budget_ms = 2.0
			budget.collision_radius_m = 96.0
			budget.terrain_ram_budget_mb = 160
			budget.terrain_vram_budget_mb = 192
			budget.allocation_safety_ratio = 0.82
	budget.sanitize(Engine.is_editor_hint())
	return budget


func sanitize(editor_hint: bool) -> void:
	profile = clampi(profile, DeviceProfile.LOW, DeviceProfile.EDITOR_PREVIEW)
	max_cached_regions = clampi(max_cached_regions, 1, 49)
	macro_height_resolution = Constants.safe_macro_resolution(macro_height_resolution, editor_hint)
	clipmap_levels = Constants.clamp_clipmap_levels(clipmap_levels)
	base_quads = Constants.clamp_base_quads(base_quads)
	shadow_lod_count = clampi(shadow_lod_count, 0, clipmap_levels)
	frame_work_budget_ms = clampf(frame_work_budget_ms, 0.25, Constants.MAX_FRAME_WORK_BUDGET_MS)
	collision_radius_m = clampf(collision_radius_m, 32.0, 256.0)
	terrain_ram_budget_mb = clampi(terrain_ram_budget_mb, 32, 512)
	terrain_vram_budget_mb = clampi(terrain_vram_budget_mb, 32, 768)
	allocation_safety_ratio = clampf(allocation_safety_ratio, 0.50, 0.95)


func estimated_clipmap_vertices() -> int:
	return clipmap_levels * (base_quads + 1) * (base_quads + 1)


func estimated_macro_height_bytes() -> int:
	return macro_height_resolution * macro_height_resolution * 4


func clipmap_radius_m() -> float:
	return Constants.clipmap_radius_m(base_quads, clipmap_levels)


func terrain_ram_budget_bytes() -> int:
	return terrain_ram_budget_mb * 1024 * 1024


func terrain_vram_budget_bytes() -> int:
	return terrain_vram_budget_mb * 1024 * 1024


func safe_terrain_ram_bytes() -> int:
	return int(float(terrain_ram_budget_bytes()) * allocation_safety_ratio)


func estimated_generation_result_bytes(resolution: int) -> int:
	var safe_resolution: int = maxi(0, resolution)
	var sample_count: int = safe_resolution * safe_resolution
	# Height + moisture + biome + river + retained flow accumulation.
	return sample_count * 11


func estimated_generation_peak_bytes(resolution: int) -> int:
	var safe_resolution: int = maxi(0, resolution)
	var sample_count: int = safe_resolution * safe_resolution
	# Conservative upper bound: result channels, erosion scratch, downstream/order arrays,
	# counting-sort tables and allocator/alignment margin.
	return sample_count * 24 + 256 * 1024


func estimated_material_metadata_peak_bytes(resolution: int) -> int:
	var safe_resolution: int = maxi(0, resolution)
	var sample_count: int = safe_resolution * safe_resolution
	# RGBA8 staging plus mipmapped texture estimate and safety padding.
	return sample_count * 10 + 64 * 1024


func can_start_generation(
	resolution: int,
	resident_terrain_bytes: int = 0,
	include_material_metadata: bool = true
) -> bool:
	if resolution <= 0 or resident_terrain_bytes < 0:
		return false
	var required: int = resident_terrain_bytes + estimated_generation_peak_bytes(resolution)
	if include_material_metadata:
		required += estimated_material_metadata_peak_bytes(resolution)
	return required <= safe_terrain_ram_bytes()


func can_cache_region(region_bytes: int, currently_cached_bytes: int) -> bool:
	return region_bytes >= 0 \
		and currently_cached_bytes >= 0 \
		and currently_cached_bytes + region_bytes <= terrain_ram_budget_bytes()
