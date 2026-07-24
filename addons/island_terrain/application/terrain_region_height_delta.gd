@tool
extends RefCounted
class_name IslandTerrainRegionHeightDelta

const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")

var coord: Vector2i = Vector2i.ZERO
var rect: Rect2i = Rect2i()
var before_values: PackedFloat32Array = PackedFloat32Array()
var after_values: PackedFloat32Array = PackedFloat32Array()


func configure(
	p_coord: Vector2i,
	p_rect: Rect2i,
	p_before: PackedFloat32Array,
	p_after: PackedFloat32Array
) -> void:
	coord = p_coord
	rect = p_rect
	before_values = p_before
	after_values = p_after


func is_valid() -> bool:
	var expected: int = rect.size.x * rect.size.y
	return rect.size.x > 0 and rect.size.y > 0 \
		and before_values.size() == expected \
		and after_values.size() == expected


func memory_bytes() -> int:
	return (before_values.size() + after_values.size()) * 4


func apply_before(region: RegionData) -> Error:
	return _apply(region, before_values)


func apply_after(region: RegionData) -> Error:
	return _apply(region, after_values)


func _apply(region: RegionData, values: PackedFloat32Array) -> Error:
	if region == null or not is_valid() or region.coord != coord:
		return ERR_INVALID_DATA
	if rect.position.x < 0 or rect.position.y < 0 \
		or rect.end.x > region.sample_count or rect.end.y > region.sample_count:
		return ERR_INVALID_PARAMETER
	var source_index: int = 0
	for y in range(rect.position.y, rect.end.y):
		var target_index: int = y * region.sample_count + rect.position.x
		for x in range(rect.size.x):
			region.height_data[target_index + x] = values[source_index]
			source_index += 1
	region.revision += 1
	return OK
