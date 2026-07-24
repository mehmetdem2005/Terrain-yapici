@tool
extends Resource
class_name IslandTerrainRegionData

const Constants = preload("res://addons/island_terrain/core/terrain_constants.gd")

signal memory_size_changed(previous_bytes: int, current_bytes: int)

@export var coord: Vector2i = Vector2i.ZERO
@export var sample_count: int = Constants.DEFAULT_REGION_SAMPLES
@export var height_data: PackedFloat32Array = PackedFloat32Array()
@export var material_index_data: PackedByteArray = PackedByteArray()
@export var material_weight_data: PackedByteArray = PackedByteArray()
@export var biome_data: PackedByteArray = PackedByteArray()
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
	revision = 1
	checksum = 0
	_emit_memory_change(previous_bytes)


func ensure_channel(channel_name: StringName) -> void:
	var previous_bytes: int = estimated_memory_bytes()
	var pixel_count: int = sample_count * sample_count
	match channel_name:
		&"material_index":
			if material_index_data.size() != pixel_count:
				material_index_data.resize(pixel_count)
				material_index_data.fill(0)
		&"material_weight":
			if material_weight_data.size() != pixel_count * 4:
				material_weight_data.resize(pixel_count * 4)
				material_weight_data.fill(0)
		&"biome":
			if biome_data.size() != pixel_count:
				biome_data.resize(pixel_count)
				biome_data.fill(0)
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
	if not material_index_data.is_empty() and material_index_data.size() != expected:
		errors.append("material_index_data size mismatch")
	if not material_weight_data.is_empty() and material_weight_data.size() != expected * 4:
		errors.append("material_weight_data size mismatch")
	if not biome_data.is_empty() and biome_data.size() != expected:
		errors.append("biome_data size mismatch")
	if not color_tint_data.is_empty() and color_tint_data.size() != expected * 4:
		errors.append("color_tint_data size mismatch")
	if not wetness_data.is_empty() and wetness_data.size() != expected:
		errors.append("wetness_data size mismatch")
	if not hole_mask.is_empty() and hole_mask.size() != expected:
		errors.append("hole_mask size mismatch")
	if not foliage_mask.is_empty() and foliage_mask.size() != expected:
		errors.append("foliage_mask size mismatch")
	return errors


func get_height(pixel: Vector2i) -> float:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= sample_count or pixel.y >= sample_count:
		return 0.0
	return height_data[pixel.y * sample_count + pixel.x]


func set_height(pixel: Vector2i, value: float) -> void:
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= sample_count or pixel.y >= sample_count:
		return
	height_data[pixel.y * sample_count + pixel.x] = value
	revision += 1


func estimated_memory_bytes() -> int:
	return height_data.size() * 4 \
		+ material_index_data.size() \
		+ material_weight_data.size() \
		+ biome_data.size() \
		+ color_tint_data.size() \
		+ wetness_data.size() \
		+ hole_mask.size() \
		+ foliage_mask.size() \
		+ runtime_delta_data.size()


func _emit_memory_change(previous_bytes: int) -> void:
	var current_bytes: int = estimated_memory_bytes()
	if current_bytes != previous_bytes:
		memory_size_changed.emit(previous_bytes, current_bytes)
