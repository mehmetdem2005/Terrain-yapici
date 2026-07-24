@tool
extends RefCounted
class_name IslandTerrainRegionPaintDelta

const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")

var coord: Vector2i = Vector2i.ZERO
var rect: Rect2i = Rect2i()
var before_biome: PackedByteArray = PackedByteArray()
var after_biome: PackedByteArray = PackedByteArray()
var before_biome_strength: PackedByteArray = PackedByteArray()
var after_biome_strength: PackedByteArray = PackedByteArray()
var before_material: PackedByteArray = PackedByteArray()
var after_material: PackedByteArray = PackedByteArray()
var before_material_strength: PackedByteArray = PackedByteArray()
var after_material_strength: PackedByteArray = PackedByteArray()


func configure(
	p_coord: Vector2i,
	p_rect: Rect2i,
	p_before_biome: PackedByteArray,
	p_after_biome: PackedByteArray,
	p_before_biome_strength: PackedByteArray,
	p_after_biome_strength: PackedByteArray,
	p_before_material: PackedByteArray,
	p_after_material: PackedByteArray,
	p_before_material_strength: PackedByteArray,
	p_after_material_strength: PackedByteArray
) -> void:
	coord = p_coord
	rect = p_rect
	before_biome = p_before_biome
	after_biome = p_after_biome
	before_biome_strength = p_before_biome_strength
	after_biome_strength = p_after_biome_strength
	before_material = p_before_material
	after_material = p_after_material
	before_material_strength = p_before_material_strength
	after_material_strength = p_after_material_strength


func is_valid() -> bool:
	var expected: int = rect.size.x * rect.size.y
	return rect.size.x > 0 and rect.size.y > 0 \
		and before_biome.size() == expected \
		and after_biome.size() == expected \
		and before_biome_strength.size() == expected \
		and after_biome_strength.size() == expected \
		and before_material.size() == expected \
		and after_material.size() == expected \
		and before_material_strength.size() == expected \
		and after_material_strength.size() == expected


func memory_bytes() -> int:
	return before_biome.size() + after_biome.size() \
		+ before_biome_strength.size() + after_biome_strength.size() \
		+ before_material.size() + after_material.size() \
		+ before_material_strength.size() + after_material_strength.size()


func apply_before(region: RegionData) -> Error:
	return _apply(
		region,
		before_biome,
		before_biome_strength,
		before_material,
		before_material_strength
	)


func apply_after(region: RegionData) -> Error:
	return _apply(
		region,
		after_biome,
		after_biome_strength,
		after_material,
		after_material_strength
	)


func _apply(
	region: RegionData,
	biome_values: PackedByteArray,
	biome_strength: PackedByteArray,
	material_values: PackedByteArray,
	material_strength: PackedByteArray
) -> Error:
	if region == null or not is_valid() or region.coord != coord:
		return ERR_INVALID_DATA
	if rect.position.x < 0 or rect.position.y < 0 \
		or rect.end.x > region.sample_count or rect.end.y > region.sample_count:
		return ERR_INVALID_PARAMETER
	region.ensure_channel(&"biome")
	region.ensure_channel(&"biome_valid")
	region.ensure_channel(&"material_index")
	region.ensure_channel(&"material_valid")
	var source_index: int = 0
	for y in range(rect.position.y, rect.end.y):
		var target_index: int = y * region.sample_count + rect.position.x
		for x in range(rect.size.x):
			var index: int = target_index + x
			region.biome_data[index] = biome_values[source_index]
			region.biome_valid_mask[index] = biome_strength[source_index]
			region.material_index_data[index] = material_values[source_index]
			region.material_valid_mask[index] = material_strength[source_index]
			source_index += 1
	region.revision += 1
	return OK
