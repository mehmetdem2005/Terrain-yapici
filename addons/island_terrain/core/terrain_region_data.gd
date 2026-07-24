@tool
extends Resource
class_name IslandTerrainRegionData

const Constants = preload("res://addons/island_terrain/core/terrain_constants.gd")

signal memory_size_changed(previous_bytes: int, current_bytes: int)

@export var coord: Vector2i = Vector2i.ZERO
@export var sample_count: int = Constants.DEFAULT_REGION_SAMPLES
@export var height_data: PackedFloat32Array = PackedFloat32Array()
@export var height_valid_mask: PackedByteArray = PackedByteArray()
@export var height_is_dense: bool = false
@export var material_index_data: PackedByteArray = PackedByteArray()
@export var material_valid_mask: PackedByteArray = PackedByteArray()
@export var material_weight_data: PackedByteArray = PackedByteArray()
@export var biome_data: PackedByteArray = PackedByteArray()
@export var biome_valid_mask: PackedByteArray = PackedByteArray()
@export var color_tint_data: PackedByteArray = PackedByteArray()
@export var wetness_data: PackedByteArray = PackedByteArray()
@export var hole_mask: PackedByteArray = PackedByteArray()
@export var foliage_mask: PackedByteArray = PackedByteArray()
@export var runtime_delta_data: PackedByteArray = PackedByteArray()
@export var revision: int = 0
@export var checksum: int = 0


func initialize(p_coord: Vector2i, p_sample_count: int) -> void:
	var previous_bytes: int = estimated_memory_bytes()
	coord = p_coord
	sample_count = p_sample_count
	var count: int = sample_count * sample_count
	height_data.resize(count)
	height_data.fill(0.0)
	height_valid_mask = PackedByteArray()
	height_is_dense = false
	material_index_data = PackedByteArray()
	material_valid_mask = PackedByteArray()
	material_weight_data = PackedByteArray()
	biome_data = PackedByteArray()
	biome_valid_mask = PackedByteArray()
	color_tint_data = PackedByteArray()
	wetness_data = PackedByteArray()
	hole_mask = PackedByteArray()
	foliage_mask = PackedByteArray()
	runtime_delta_data = PackedByteArray()
	revision = 1
	checksum = 0
	_emit_memory_change(previous_bytes)


func ensure_channel(channel_name: StringName) -> void:
	var previous_bytes: int = estimated_memory_bytes()
	var pixel_count: int = sample_count * sample_count
	match channel_name:
		&"height_valid":
			if not height_is_dense and height_valid_mask.size() != pixel_count:
				height_valid_mask.resize(pixel_count)
				height_valid_mask.fill(0)
		&"material_index":
			if material_index_data.size() != pixel_count:
				material_index_data.resize(pixel_count)
				material_index_data.fill(0)
		&"material_valid":
			if material_valid_mask.size() != pixel_count:
				material_valid_mask.resize(pixel_count)
				material_valid_mask.fill(0)
		&"material_weight":
			if material_weight_data.size() != pixel_count * 4:
				material_weight_data.resize(pixel_count * 4)
				material_weight_data.fill(0)
		&"biome":
			if biome_data.size() != pixel_count:
				biome_data.resize(pixel_count)
				biome_data.fill(0)
		&"biome_valid":
			if biome_valid_mask.size() != pixel_count:
				biome_valid_mask.resize(pixel_count)
				biome_valid_mask.fill(0)
		&"color_tint":
			if color_tint_data.size() != pixel_count * 4:
				color_tint_data.resize(pixel_count * 4)
				color_tint_data.fill(255)
		&"wetness":
			if wetness_data.size() != pixel_count:
				wetness_data.resize(pixel_count)
				wetness_data.fill(0)
		&"hole_mask":
			if hole_mask.size() != pixel_count:
				hole_mask.resize(pixel_count)
				hole_mask.fill(0)
		&"foliage_mask":
			if foliage_mask.size() != pixel_count:
				foliage_mask.resize(pixel_count)
				foliage_mask.fill(255)
		&"runtime_delta":
			pass
		_:
			push_warning("IT-W01: Unknown terrain channel requested: %s" % channel_name)
	_emit_memory_change(previous_bytes)


func set_runtime_delta_bytes(data: PackedByteArray) -> void:
	var previous_bytes: int = estimated_memory_bytes()
	runtime_delta_data = data
	revision += 1
	_emit_memory_change(previous_bytes)


func validate_dimensions() -> PackedStringArray:
	var errors := PackedStringArray()
	if not Constants.is_valid_sample_count(sample_count):
		errors.append("sample_count must be 2^n + 1")
	var expected: int = sample_count * sample_count
	if height_data.size() != expected:
		errors.append("height_data size mismatch: expected %d, got %d" % [expected, height_data.size()])
	if not height_valid_mask.is_empty() and height_valid_mask.size() != expected:
		errors.append("height_valid_mask size mismatch")
	if not material_index_data.is_empty() and material_index_data.size() != expected:
		errors.append("material_index_data size mismatch")
	if not material_valid_mask.is_empty() and material_valid_mask.size() != expected:
		errors.append("material_valid_mask size mismatch")
	if not material_weight_data.is_empty() and material_weight_data.size() != expected * 4:
		errors.append("material_weight_data size mismatch")
	if not biome_data.is_empty() and biome_data.size() != expected:
		errors.append("biome_data size mismatch")
	if not biome_valid_mask.is_empty() and biome_valid_mask.size() != expected:
		errors.append("biome_valid_mask size mismatch")
	if not color_tint_data.is_empty() and color_tint_data.size() != expected * 4:
		errors.append("color_tint_data size mismatch")
	if not wetness_data.is_empty() and wetness_data.size() != expected:
		errors.append("wetness_data size mismatch")
	if not hole_mask.is_empty() and hole_mask.size() != expected:
		errors.append("hole_mask size mismatch")
	if not foliage_mask.is_empty() and foliage_mask.size() != expected:
		errors.append("foliage_mask size mismatch")
	return errors


func is_height_valid(pixel: Vector2i) -> bool:
	if not _contains_pixel(pixel):
		return false
	if height_is_dense:
		return true
	if height_valid_mask.is_empty():
		return false
	return height_valid_mask[_linear_index(pixel)] != 0


func get_height(pixel: Vector2i) -> float:
	if not _contains_pixel(pixel):
		return 0.0
	return height_data[_linear_index(pixel)]


func set_height(pixel: Vector2i, value: float, dense: bool = false) -> void:
	if not _contains_pixel(pixel):
		return
	var previous_bytes: int = estimated_memory_bytes()
	var index: int = _linear_index(pixel)
	height_data[index] = value
	if dense:
		height_is_dense = true
		height_valid_mask = PackedByteArray()
	else:
		if height_valid_mask.size() != sample_count * sample_count:
			height_valid_mask.resize(sample_count * sample_count)
			height_valid_mask.fill(0)
		height_valid_mask[index] = 1
	revision += 1
	_emit_memory_change(previous_bytes)


func set_height_valid(pixel: Vector2i, valid: bool) -> void:
	if height_is_dense or not _contains_pixel(pixel):
		return
	var previous_bytes: int = estimated_memory_bytes()
	if height_valid_mask.size() != sample_count * sample_count:
		height_valid_mask.resize(sample_count * sample_count)
		height_valid_mask.fill(0)
	height_valid_mask[_linear_index(pixel)] = 1 if valid else 0
	_emit_memory_change(previous_bytes)


func biome_override_strength(pixel: Vector2i) -> int:
	if not _contains_pixel(pixel) or biome_valid_mask.is_empty():
		return 0
	return int(biome_valid_mask[_linear_index(pixel)])


func biome_override_id(pixel: Vector2i) -> int:
	if not _contains_pixel(pixel) or biome_data.is_empty():
		return 0
	return int(biome_data[_linear_index(pixel)])


func material_override_strength(pixel: Vector2i) -> int:
	if not _contains_pixel(pixel) or material_valid_mask.is_empty():
		return 0
	return int(material_valid_mask[_linear_index(pixel)])


func material_override_id(pixel: Vector2i) -> int:
	if not _contains_pixel(pixel) or material_index_data.is_empty():
		return 0
	return int(material_index_data[_linear_index(pixel)])


func estimated_memory_bytes() -> int:
	return height_data.size() * 4 \
		+ height_valid_mask.size() \
		+ material_index_data.size() \
		+ material_valid_mask.size() \
		+ material_weight_data.size() \
		+ biome_data.size() \
		+ biome_valid_mask.size() \
		+ color_tint_data.size() \
		+ wetness_data.size() \
		+ hole_mask.size() \
		+ foliage_mask.size() \
		+ runtime_delta_data.size()


func _contains_pixel(pixel: Vector2i) -> bool:
	return pixel.x >= 0 and pixel.y >= 0 and pixel.x < sample_count and pixel.y < sample_count


func _linear_index(pixel: Vector2i) -> int:
	return pixel.y * sample_count + pixel.x


func _emit_memory_change(previous_bytes: int) -> void:
	var current_bytes: int = estimated_memory_bytes()
	if current_bytes != previous_bytes:
		memory_size_changed.emit(previous_bytes, current_bytes)
