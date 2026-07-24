@tool
extends Node
class_name IslandTerrainMaterialOverrideSync

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const RegionRepository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")
const MemoryBudget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")

signal override_texture_changed(texture: ImageTexture)

var _manifest: Manifest
var _coordinates: Coordinates
var _repository: RegionRepository
var _budget: MemoryBudget
var _override_image: Image
var _override_texture: ImageTexture
var _dirty_regions: Dictionary = {}
var _configured: bool = false
var _last_upload_bytes: int = 0


func configure(
	manifest: Manifest,
	coordinates: Coordinates,
	repository: RegionRepository,
	budget: MemoryBudget
) -> Error:
	if manifest == null or coordinates == null or repository == null or budget == null:
		return ERR_INVALID_PARAMETER
	_manifest = manifest
	_coordinates = coordinates
	_repository = repository
	_budget = budget
	var resolution: int = _budget.macro_height_resolution
	_override_image = Image.create_empty(resolution, resolution, true, Image.FORMAT_RGBA8)
	_override_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_override_image.generate_mipmaps()
	_override_texture = ImageTexture.create_from_image(_override_image)
	_dirty_regions.clear()
	_configured = _override_texture != null
	set_process(_configured)
	if not _configured:
		return ERR_CANT_CREATE
	_queue_persisted_regions()
	override_texture_changed.emit(_override_texture)
	return OK


func queue_region_rect(coord: Vector2i, rect: Rect2i) -> void:
	if not _configured or rect.size.x <= 0 or rect.size.y <= 0:
		return
	if _dirty_regions.has(coord):
		var existing: Rect2i = _dirty_regions[coord]
		_dirty_regions[coord] = existing.merge(rect)
	else:
		_dirty_regions[coord] = rect


func texture() -> ImageTexture:
	return _override_texture


func pending_region_count() -> int:
	return _dirty_regions.size()


func last_upload_bytes() -> int:
	return _last_upload_bytes


func estimated_memory_bytes() -> int:
	if _override_image == null or _override_image.is_empty():
		return 0
	return _override_image.get_width() * _override_image.get_height() * 4


func flush_all() -> Error:
	if not _configured:
		return ERR_UNCONFIGURED
	while not _dirty_regions.is_empty():
		_process_dirty_regions(-1)
	return OK


func _process(_delta: float) -> void:
	if not _configured or _dirty_regions.is_empty():
		return
	var budget_usec: int = maxi(250, int(_budget.frame_work_budget_ms * 450.0))
	_process_dirty_regions(budget_usec)


func _process_dirty_regions(budget_usec: int) -> void:
	var start_usec: int = Time.get_ticks_usec()
	var processed_any: bool = false
	while not _dirty_regions.is_empty():
		var keys: Array = _dirty_regions.keys()
		var coord: Vector2i = keys[0]
		var rect: Rect2i = _dirty_regions[coord]
		_dirty_regions.erase(coord)
		_update_override_from_region_rect(coord, rect)
		processed_any = true
		if budget_usec >= 0 and Time.get_ticks_usec() - start_usec >= budget_usec:
			break
	if processed_any:
		_upload_override_texture()


func _update_override_from_region_rect(coord: Vector2i, rect: Rect2i) -> void:
	if _override_image == null or _override_image.is_empty():
		return
	var region: RegionData = _repository.get_or_create(coord)
	if region == null:
		return
	var first_world: Vector3 = _coordinates.region_pixel_to_world(coord, rect.position)
	var last_world: Vector3 = _coordinates.region_pixel_to_world(
		coord,
		Vector2i(rect.end.x - 1, rect.end.y - 1)
	)
	var macro_min: Vector2i = _world_to_macro_pixel(first_world)
	var macro_max: Vector2i = _world_to_macro_pixel(last_world)
	var min_x: int = mini(macro_min.x, macro_max.x)
	var min_y: int = mini(macro_min.y, macro_max.y)
	var max_x: int = maxi(macro_min.x, macro_max.x)
	var max_y: int = maxi(macro_min.y, macro_max.y)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var world_position: Vector3 = _macro_pixel_to_world(Vector2i(x, y))
			var sample_coord: Vector2i = _coordinates.world_to_region_clamped(world_position)
			var sample_region: RegionData = _repository.get_or_create(sample_coord)
			if sample_region == null:
				continue
			var sample_pixel: Vector2i = _coordinates.world_to_region_pixel(world_position, sample_coord)
			var biome_id: float = float(sample_region.biome_override_id(sample_pixel)) / 7.0
			var biome_strength: float = float(sample_region.biome_override_strength(sample_pixel)) / 255.0
			var material_id: float = float(sample_region.material_override_id(sample_pixel)) / 5.0
			var material_strength: float = float(sample_region.material_override_strength(sample_pixel)) / 255.0
			_override_image.set_pixel(
				x,
				y,
				Color(biome_id, biome_strength, material_id, material_strength)
			)


func _upload_override_texture() -> void:
	if _override_texture == null or _override_image == null:
		return
	_override_image.generate_mipmaps()
	_override_texture.update(_override_image)
	_last_upload_bytes = _override_image.get_width() * _override_image.get_height() * 4
	override_texture_changed.emit(_override_texture)


func _queue_persisted_regions() -> void:
	var region_count: int = _manifest.region_count_axis()
	var full_rect := Rect2i(0, 0, _manifest.region_samples, _manifest.region_samples)
	for region_y in range(region_count):
		for region_x in range(region_count):
			var coord := Vector2i(region_x, region_y)
			if ResourceLoader.exists(_repository.writable_region_file_path(coord)) \
				or ResourceLoader.exists(_repository.source_region_file_path(coord)):
				queue_region_rect(coord, full_rect)


func _world_to_macro_pixel(world_position: Vector3) -> Vector2i:
	var origin: Vector2 = _coordinates.origin_world_xz()
	var half: float = float(_manifest.world_size_m) * 0.5
	var uv := Vector2(
		(world_position.x - origin.x + half) / float(_manifest.world_size_m),
		(world_position.z - origin.y + half) / float(_manifest.world_size_m)
	)
	return Vector2i(
		clampi(roundi(uv.x * float(_override_image.get_width() - 1)), 0, _override_image.get_width() - 1),
		clampi(roundi(uv.y * float(_override_image.get_height() - 1)), 0, _override_image.get_height() - 1)
	)


func _macro_pixel_to_world(pixel: Vector2i) -> Vector3:
	var origin: Vector2 = _coordinates.origin_world_xz()
	var denominator_x: float = float(maxi(1, _override_image.get_width() - 1))
	var denominator_y: float = float(maxi(1, _override_image.get_height() - 1))
	var normalized_x: float = float(pixel.x) / denominator_x - 0.5
	var normalized_y: float = float(pixel.y) / denominator_y - 0.5
	return Vector3(
		origin.x + normalized_x * float(_manifest.world_size_m),
		0.0,
		origin.y + normalized_y * float(_manifest.world_size_m)
	)
