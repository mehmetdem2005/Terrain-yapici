@tool
extends RefCounted
class_name IslandTerrainRegionRepository

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const INVALID_COORD := Vector2i(-2147483648, -2147483648)

var _source_data_root: String
var _writable_data_root: String
var _manifest: Manifest
var _budget: Budget
var _cache: Dictionary = {}
var _lru: Array[Vector2i] = []
var _dirty: Dictionary = {}
var _region_memory_bytes: Dictionary = {}
var _region_memory_callbacks: Dictionary = {}
var _cached_bytes: int = 0


func _init(
	source_data_root: String,
	writable_data_root: String,
	manifest: Manifest,
	budget: Budget
) -> void:
	_source_data_root = source_data_root.trim_suffix("/")
	_writable_data_root = writable_data_root.trim_suffix("/")
	_manifest = manifest
	_budget = budget
	_ensure_writable_directories()


func get_or_create(coord: Vector2i) -> RegionData:
	if not _manifest.contains_region(coord):
		return null
	if _cache.has(coord):
		_touch(coord)
		return _cache[coord] as RegionData
	var region: RegionData = _load_region(coord)
	if region == null:
		region = RegionData.new()
		region.initialize(coord, _manifest.region_samples)
	_admit(coord, region)
	return region


func get_cached(coord: Vector2i) -> RegionData:
	if not _cache.has(coord):
		return null
	_touch(coord)
	return _cache[coord] as RegionData


func mark_dirty(coord: Vector2i) -> void:
	if _cache.has(coord):
		_dirty[coord] = true


func is_dirty(coord: Vector2i) -> bool:
	return _dirty.has(coord)


func save_dirty(max_regions: int = 1) -> int:
	var saved: int = 0
	var coords: Array = _dirty.keys()
	for untyped_coord in coords:
		if saved >= maxi(1, max_regions):
			break
		var coord: Vector2i = untyped_coord
		if not _cache.has(coord):
			_dirty.erase(coord)
			continue
		var region: RegionData = _cache[coord] as RegionData
		_refresh_region_memory_accounting(coord, region)
		var error: Error = _save_region(coord, region)
		if error == OK:
			_dirty.erase(coord)
			saved += 1
		else:
			push_error("IT-004: Region save failed for %s with error %d" % [coord, error])
	return saved


func flush_all() -> Error:
	while not _dirty.is_empty():
		var before: int = _dirty.size()
		save_dirty(before)
		if _dirty.size() == before:
			return ERR_CANT_CREATE
	return OK


func cached_region_count() -> int:
	return _cache.size()


func cached_memory_bytes() -> int:
	return _cached_bytes


func dirty_region_count() -> int:
	return _dirty.size()


func clear_clean_cache() -> void:
	var coords: Array[Vector2i] = _lru.duplicate()
	for coord in coords:
		if not _dirty.has(coord):
			_evict(coord)


func source_region_file_path(coord: Vector2i) -> String:
	return "%s/regions/region_%d_%d.res" % [_source_data_root, coord.x, coord.y]


func writable_region_file_path(coord: Vector2i) -> String:
	return "%s/regions/region_%d_%d.res" % [_writable_data_root, coord.x, coord.y]


func _load_region(coord: Vector2i) -> RegionData:
	var writable_path: String = writable_region_file_path(coord)
	var backup_path: String = _backup_path(writable_path)
	var writable_region: RegionData = _load_validated_region(writable_path, coord)
	if writable_region != null:
		return writable_region
	var backup_region: RegionData = _load_validated_region(backup_path, coord)
	if backup_region != null:
		_recover_backup(writable_path, backup_path)
		backup_region.take_over_path(writable_path)
		return backup_region
	var source_path: String = source_region_file_path(coord)
	if source_path == writable_path:
		return null
	return _load_validated_region(source_path, coord)


func _load_validated_region(path: String, coord: Vector2i) -> RegionData:
	if not ResourceLoader.exists(path):
		return null
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as RegionData
	if loaded == null:
		push_error("IT-003: Invalid region resource at %s" % path)
		return null
	var errors: PackedStringArray = loaded.validate_dimensions()
	if not errors.is_empty():
		push_error("IT-003: Corrupt region %s at %s: %s" % [coord, path, "; ".join(errors)])
		return null
	if loaded.checksum != 0:
		var current_checksum: int = _calculate_checksum(loaded)
		if loaded.checksum != current_checksum:
			var v2_checksum: int = _calculate_v2_checksum(loaded)
			var legacy_checksum: int = _calculate_legacy_height_checksum(loaded.height_data)
			if loaded.checksum == v2_checksum:
				loaded.checksum = current_checksum
			elif loaded.height_valid_mask.is_empty() \
				and not loaded.height_is_dense \
				and loaded.checksum == legacy_checksum:
				loaded.height_is_dense = true
				loaded.checksum = _calculate_checksum(loaded)
			else:
				push_error("IT-009: Region checksum mismatch for %s at %s" % [coord, path])
				return null
	return loaded


func _save_region(coord: Vector2i, region: RegionData) -> Error:
	_ensure_writable_directories()
	var final_path: String = writable_region_file_path(coord)
	var temporary_path: String = _temporary_path(final_path)
	var backup_path: String = _backup_path(final_path)
	var expected_checksum: int = _calculate_checksum(region)
	region.checksum = expected_checksum
	_remove_if_exists(temporary_path)
	var save_error: Error = ResourceSaver.save(region, temporary_path, ResourceSaver.FLAG_COMPRESS)
	if save_error != OK:
		return save_error
	var verified := ResourceLoader.load(temporary_path, "", ResourceLoader.CACHE_MODE_IGNORE) as RegionData
	if verified == null:
		_remove_if_exists(temporary_path)
		return ERR_FILE_CORRUPT
	if not verified.validate_dimensions().is_empty() \
		or verified.checksum != expected_checksum \
		or _calculate_checksum(verified) != expected_checksum:
		_remove_if_exists(temporary_path)
		return ERR_FILE_CORRUPT
	var final_absolute: String = ProjectSettings.globalize_path(final_path)
	var temporary_absolute: String = ProjectSettings.globalize_path(temporary_path)
	var backup_absolute: String = ProjectSettings.globalize_path(backup_path)
	_remove_if_exists(backup_path)
	var had_previous: bool = FileAccess.file_exists(final_path)
	if had_previous:
		var backup_error: Error = DirAccess.rename_absolute(final_absolute, backup_absolute)
		if backup_error != OK:
			_remove_if_exists(temporary_path)
			return backup_error
	var promote_error: Error = DirAccess.rename_absolute(temporary_absolute, final_absolute)
	if promote_error != OK:
		if had_previous and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_absolute, final_absolute)
		_remove_if_exists(temporary_path)
		return promote_error
	region.take_over_path(final_path)
	return OK


func _recover_backup(final_path: String, backup_path: String) -> void:
	if FileAccess.file_exists(final_path):
		var corrupt_path: String = "%s.corrupt.%d.res" % [
			final_path.trim_suffix(".res"),
			int(Time.get_unix_time_from_system()),
		]
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(final_path),
			ProjectSettings.globalize_path(corrupt_path)
		)
	if FileAccess.file_exists(backup_path):
		var recovery_error: Error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(backup_path),
			ProjectSettings.globalize_path(final_path)
		)
		if recovery_error != OK:
			push_error("IT-008: Failed to recover terrain region backup at %s" % backup_path)


func _admit(coord: Vector2i, region: RegionData) -> void:
	var bytes: int = region.estimated_memory_bytes()
	_make_room(bytes)
	_cache[coord] = region
	_lru.append(coord)
	_region_memory_bytes[coord] = bytes
	var callback := _on_region_memory_size_changed.bind(coord)
	_region_memory_callbacks[coord] = callback
	if not region.memory_size_changed.is_connected(callback):
		region.memory_size_changed.connect(callback)
	_cached_bytes += bytes


func _make_room(incoming_bytes: int) -> void:
	var guard: int = _lru.size() + 1
	while guard > 0 and (
		_cache.size() >= _budget.max_cached_regions
		or not _budget.can_cache_region(incoming_bytes, _cached_bytes)
	):
		guard -= 1
		var candidate: Vector2i = _find_oldest_clean_region()
		if candidate == INVALID_COORD:
			push_warning("IT-W02: Region cache budget reached but no clean region can be evicted; keeping data to avoid loss")
			break
		_evict(candidate)


func _enforce_memory_budget(excluded_coord: Vector2i) -> void:
	var guard: int = _lru.size() + 1
	while guard > 0 and not _budget.can_cache_region(0, _cached_bytes):
		guard -= 1
		var candidate: Vector2i = _find_oldest_clean_region(excluded_coord)
		if candidate == INVALID_COORD:
			push_warning("IT-W07: Lazy terrain channel growth exceeded the RAM budget and no clean region can be evicted")
			return
		_evict(candidate)


func _find_oldest_clean_region(excluded_coord: Vector2i = INVALID_COORD) -> Vector2i:
	for coord in _lru:
		if coord != excluded_coord and not _dirty.has(coord):
			return coord
	return INVALID_COORD


func _evict(coord: Vector2i) -> void:
	if not _cache.has(coord) or _dirty.has(coord):
		return
	var region: RegionData = _cache[coord] as RegionData
	var callback: Callable = _region_memory_callbacks.get(coord, Callable())
	if callback.is_valid() and region.memory_size_changed.is_connected(callback):
		region.memory_size_changed.disconnect(callback)
	_cached_bytes = maxi(0, _cached_bytes - int(_region_memory_bytes.get(coord, 0)))
	_region_memory_bytes.erase(coord)
	_region_memory_callbacks.erase(coord)
	_cache.erase(coord)
	_lru.erase(coord)


func _touch(coord: Vector2i) -> void:
	_lru.erase(coord)
	_lru.append(coord)


func _on_region_memory_size_changed(
	_previous_bytes: int,
	current_bytes: int,
	coord: Vector2i
) -> void:
	if not _cache.has(coord):
		return
	var tracked_bytes: int = int(_region_memory_bytes.get(coord, 0))
	_cached_bytes = maxi(0, _cached_bytes + current_bytes - tracked_bytes)
	_region_memory_bytes[coord] = current_bytes
	_enforce_memory_budget(coord)


func _refresh_region_memory_accounting(coord: Vector2i, region: RegionData) -> void:
	var current_bytes: int = region.estimated_memory_bytes()
	var tracked_bytes: int = int(_region_memory_bytes.get(coord, 0))
	if current_bytes == tracked_bytes:
		return
	_cached_bytes = maxi(0, _cached_bytes + current_bytes - tracked_bytes)
	_region_memory_bytes[coord] = current_bytes
	_enforce_memory_budget(coord)


func _ensure_writable_directories() -> void:
	var absolute_path: String = ProjectSettings.globalize_path("%s/regions" % _writable_data_root)
	var error: Error = DirAccess.make_dir_recursive_absolute(absolute_path)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("IT-002: Cannot create writable terrain data directory: %s" % absolute_path)


func _temporary_path(final_path: String) -> String:
	return "%s.tmp.res" % final_path.trim_suffix(".res")


func _backup_path(final_path: String) -> String:
	return "%s.bak.res" % final_path.trim_suffix(".res")


func _remove_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _calculate_checksum(region: RegionData) -> int:
	return int(hash([
		region.height_data,
		region.height_valid_mask,
		region.height_is_dense,
		region.material_index_data,
		region.material_valid_mask,
		region.material_weight_data,
		region.biome_data,
		region.biome_valid_mask,
		region.color_tint_data,
		region.wetness_data,
		region.hole_mask,
		region.foliage_mask,
		region.runtime_delta_data,
	])) & 0x7fffffff


func _calculate_v2_checksum(region: RegionData) -> int:
	return int(hash([
		region.height_data,
		region.height_valid_mask,
		region.height_is_dense,
	])) & 0x7fffffff


func _calculate_legacy_height_checksum(values: PackedFloat32Array) -> int:
	return int(hash(values)) & 0x7fffffff
