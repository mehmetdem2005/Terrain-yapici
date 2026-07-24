@tool
extends Node
class_name IslandTerrainMacroHeightSync

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const RegionRepository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")
const MemoryBudget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")

var _manifest: Manifest
var _coordinates: Coordinates
var _repository: RegionRepository
var _budget: MemoryBudget
var _macro_image: Image
var _height_texture: ImageTexture
var _base_height_sampler: Callable
var _dirty_regions: Dictionary = {}
var _configured: bool = false
var _last_upload_bytes: int = 0


func configure(
	manifest: Manifest,
	coordinates: Coordinates,
	repository: RegionRepository,
	budget: MemoryBudget,
	macro_image: Image,
	height_texture: ImageTexture,
	base_height_sampler: Callable
) -> void:
	_manifest = manifest
	_coordinates = coordinates
	_repository = repository
	_budget = budget
	_base_height_sampler = base_height_sampler
	replace_targets(macro_image, height_texture)
	_configured = true
	set_process(true)


func replace_targets(macro_image: Image, height_texture: ImageTexture) -> void:
	_macro_image = macro_image
	_height_texture = height_texture


func queue_region_rect(coord: Vector2i, rect: Rect2i) -> void:
	if not _configured or rect.size.x <= 0 or rect.size.y <= 0:
		return
	if _dirty_regions.has(coord):
		var existing: Rect2i = _dirty_regions[coord]
		_dirty_regions[coord] = existing.merge(rect)
	else:
		_dirty_regions[coord] = rect


func pending_region_count() -> int:
	return _dirty_regions.size()


func last_upload_bytes() -> int:
	return _last_upload_bytes


func flush_all() -> Error:
	if not _configured:
		return ERR_UNCONFIGURED
	while not _dirty_regions.is_empty():
		_process_dirty_regions(-1)
	return OK


func _process(_delta: float) -> void:
	if not _configured or _dirty_regions.is_empty():
		return
	var budget_usec: int = maxi(250, int(_budget.frame_work_budget_ms * 500.0))
	_process_dirty_regions(budget_usec)


func _process_dirty_regions(budget_usec: int) -> void:
	var start_usec: int = Time.get_ticks_usec()
	var processed_any: bool = false
	while not _dirty_regions.is_empty():
		var keys: Array = _dirty_regions.keys()
		var coord: Vector2i = keys[0]
		var rect: Rect2i = _dirty_regions[coord]
		_dirty_regions.erase(coord)
		_update_macro_from_region_rect(coord, rect)
		processed_any = true
		if budget_usec >= 0 and Time.get_ticks_usec() - start_usec >= budget_usec:
			break
	if processed_any:
		_upload_macro_texture()


func _update_macro_from_region_rect(coord: Vector2i, rect: Rect2i) -> void:
	if _macro_image == null or _macro_image.is_empty():
		return
	var region: RegionData = _repository.get_or_create(coord)
	if region == null:
		return
	var first_world: Vector3 = _coordinates.region_pixel_to_world(coord, rect.position)
	var last_pixel := Vector2i(rect.end.x - 1, rect.end.y - 1)
	var last_world: Vector3 = _coordinates.region_pixel_to_world(coord, last_pixel)
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
			var height_m: float
			if sample_region.is_height_valid(sample_pixel):
				height_m = sample_region.get_height(sample_pixel)
			elif _base_height_sampler.is_valid():
				height_m = float(_base_height_sampler.call(world_position))
			else:
				height_m = 0.0
			var normalized: float = clampf(height_m / maxf(_manifest.max_height_m, 0.001), 0.0, 1.0)
			_macro_image.set_pixel(x, y, Color(normalized, 0.0, 0.0, 1.0))


func _upload_macro_texture() -> void:
	if _height_texture == null or _macro_image == null:
		return
	_macro_image.generate_mipmaps()
	# Godot's public Texture2D APIs replace the whole image. Dirty rectangles
	# limit CPU work and uploads are coalesced to once per frame; the macro image
	# is capped at 257²/513² on runtime profiles.
	_height_texture.update(_macro_image)
	_last_upload_bytes = _macro_image.get_width() * _macro_image.get_height() * 4


func _world_to_macro_pixel(world_position: Vector3) -> Vector2i:
	var origin: Vector2 = _coordinates.origin_world_xz()
	var half: float = float(_manifest.world_size_m) * 0.5
	var uv := Vector2(
		(world_position.x - origin.x + half) / float(_manifest.world_size_m),
		(world_position.z - origin.y + half) / float(_manifest.world_size_m)
	)
	return Vector2i(
		clampi(roundi(uv.x * float(_macro_image.get_width() - 1)), 0, _macro_image.get_width() - 1),
		clampi(roundi(uv.y * float(_macro_image.get_height() - 1)), 0, _macro_image.get_height() - 1)
	)


func _macro_pixel_to_world(pixel: Vector2i) -> Vector3:
	var origin: Vector2 = _coordinates.origin_world_xz()
	var denominator_x: float = float(maxi(1, _macro_image.get_width() - 1))
	var denominator_y: float = float(maxi(1, _macro_image.get_height() - 1))
	var normalized_x: float = float(pixel.x) / denominator_x - 0.5
	var normalized_y: float = float(pixel.y) / denominator_y - 0.5
	return Vector3(
		origin.x + normalized_x * float(_manifest.world_size_m),
		0.0,
		origin.y + normalized_y * float(_manifest.world_size_m)
	)
