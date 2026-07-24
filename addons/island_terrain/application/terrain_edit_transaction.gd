@tool
extends RefCounted
class_name IslandTerrainEditTransaction

const RegionDelta = preload("res://addons/island_terrain/application/terrain_region_height_delta.gd")
const RegionRepository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")

var action_name: String = "Terrain Sculpt"
var deltas: Array[RegionDelta] = []
var max_memory_bytes: int = 8 * 1024 * 1024
var _memory_bytes: int = 0


func add_delta(delta: RegionDelta) -> Error:
	if delta == null or not delta.is_valid():
		return ERR_INVALID_DATA
	var next_size: int = _memory_bytes + delta.memory_bytes()
	if next_size > max_memory_bytes:
		return ERR_OUT_OF_MEMORY
	deltas.append(delta)
	_memory_bytes = next_size
	return OK


func append_transaction(other: IslandTerrainEditTransaction) -> Error:
	if other == null:
		return ERR_INVALID_DATA
	for delta in other.deltas:
		var error: Error = add_delta(delta)
		if error != OK:
			return error
	return OK


func is_empty() -> bool:
	return deltas.is_empty()


func memory_bytes() -> int:
	return _memory_bytes


func apply_before(repository: RegionRepository) -> Error:
	if repository == null:
		return ERR_INVALID_DATA
	for index in range(deltas.size() - 1, -1, -1):
		var delta: RegionDelta = deltas[index]
		var region = repository.get_or_create(delta.coord)
		var error: Error = delta.apply_before(region)
		if error != OK:
			return error
		repository.mark_dirty(delta.coord)
	return OK


func apply_after(repository: RegionRepository) -> Error:
	if repository == null:
		return ERR_INVALID_DATA
	for delta in deltas:
		var region = repository.get_or_create(delta.coord)
		var error: Error = delta.apply_after(region)
		if error != OK:
			return error
		repository.mark_dirty(delta.coord)
	return OK


func affected_regions() -> Array[Vector2i]:
	var unique: Dictionary = {}
	for delta in deltas:
		unique[delta.coord] = true
	var result: Array[Vector2i] = []
	for coord in unique.keys():
		result.append(coord)
	return result
