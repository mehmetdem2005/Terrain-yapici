@tool
extends RefCounted
class_name IslandTerrainFoliagePlanner

const Library = preload("res://addons/island_terrain/foliage/terrain_foliage_library.gd")
const Layer = preload("res://addons/island_terrain/foliage/terrain_foliage_layer.gd")
const CellPlan = preload("res://addons/island_terrain/foliage/terrain_foliage_cell_plan.gd")

var _world_seed: int = 1
var _library: Library
var _terrain_origin_xz: Vector2 = Vector2.ZERO
var _height_sampler: Callable
var _normal_sampler: Callable
var _biome_sampler: Callable
var _moisture_sampler: Callable
var _foliage_mask_sampler: Callable
var _configured: bool = false


func configure(
	world_seed: int,
	library: Library,
	terrain_origin_xz: Vector2,
	height_sampler: Callable,
	normal_sampler: Callable,
	biome_sampler: Callable,
	moisture_sampler: Callable,
	foliage_mask_sampler: Callable
) -> Error:
	if library == null:
		return ERR_INVALID_PARAMETER
	if not height_sampler.is_valid() \
		or not normal_sampler.is_valid() \
		or not biome_sampler.is_valid() \
		or not moisture_sampler.is_valid() \
		or not foliage_mask_sampler.is_valid():
		return ERR_INVALID_PARAMETER
	_world_seed = world_seed
	_library = library.duplicate(true) as Library
	if _library == null:
		return ERR_CANT_CREATE
	_library.sanitize()
	_terrain_origin_xz = terrain_origin_xz
	_height_sampler = height_sampler
	_normal_sampler = normal_sampler
	_biome_sampler = biome_sampler
	_moisture_sampler = moisture_sampler
	_foliage_mask_sampler = foliage_mask_sampler
	_configured = true
	return OK


func is_configured() -> bool:
	return _configured


func world_to_cell(world_position: Vector3) -> Vector2i:
	if _library == null:
		return Vector2i.ZERO
	var size: float = float(_library.cell_size_m)
	return Vector2i(
		floori((world_position.x - _terrain_origin_xz.x) / size),
		floori((world_position.z - _terrain_origin_xz.y) / size)
	)


func cell_min_world(cell_coord: Vector2i) -> Vector3:
	if _library == null:
		return Vector3.ZERO
	return Vector3(
		_terrain_origin_xz.x + float(cell_coord.x * _library.cell_size_m),
		0.0,
		_terrain_origin_xz.y + float(cell_coord.y * _library.cell_size_m)
	)


func cell_center_world(cell_coord: Vector2i) -> Vector3:
	var half: float = float(_library.cell_size_m) * 0.5 if _library != null else 0.0
	return cell_min_world(cell_coord) + Vector3(half, 0.0, half)


func plan_cell(cell_coord: Vector2i) -> CellPlan:
	if not _configured:
		return null
	var plan := CellPlan.new()
	plan.initialize(cell_coord)
	var cell_min: Vector3 = cell_min_world(cell_coord)
	var cell_size: float = float(_library.cell_size_m)
	for layer_index in range(_library.layers.size()):
		var layer: Layer = _library.layers[layer_index]
		var requested: int = layer.requested_instances(cell_size, _library.density_scale)
		if requested <= 0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = _mixed_seed(cell_coord, layer_index)
		var accepted: int = 0
		var attempts: int = 0
		var max_attempts: int = maxi(requested, requested * 4)
		while accepted < requested and attempts < max_attempts:
			attempts += 1
			var world_position := Vector3(
				cell_min.x + rng.randf() * cell_size,
				0.0,
				cell_min.z + rng.randf() * cell_size
			)
			world_position.y = float(_height_sampler.call(world_position))
			var normal: Vector3 = _normal_sampler.call(world_position)
			var biome: int = int(_biome_sampler.call(world_position))
			var moisture: float = clampf(float(_moisture_sampler.call(world_position)), 0.0, 1.0)
			var foliage_mask: float = clampf(float(_foliage_mask_sampler.call(world_position)), 0.0, 1.0)
			if not layer.accepts_sample(
				biome,
				world_position.y,
				normal,
				moisture,
				foliage_mask
			):
				continue
			if foliage_mask < 0.999 and rng.randf() > foliage_mask:
				continue
			var yaw: float = rng.randf_range(-PI, PI) if layer.random_yaw else 0.0
			var scale: float = rng.randf_range(layer.min_scale, layer.max_scale)
			plan.append_instance(layer_index, world_position, normal, yaw, scale)
			accepted += 1
	return plan


func estimated_plan_memory_bytes(cell_coord: Vector2i) -> int:
	var plan: CellPlan = plan_cell(cell_coord)
	return plan.estimated_memory_bytes() if plan != null else 0


func _mixed_seed(cell_coord: Vector2i, layer_index: int) -> int:
	var value: int = int(_world_seed) ^ int(_library.seed_salt)
	value ^= int(cell_coord.x) * 73856093
	value ^= int(cell_coord.y) * 19349663
	value ^= layer_index * 83492791
	value = (value ^ (value >> 13)) * 1274126177
	value ^= value >> 16
	return value & 0x7fffffff
