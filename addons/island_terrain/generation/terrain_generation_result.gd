@tool
extends RefCounted
class_name IslandTerrainGenerationResult

enum Biome {
	OCEAN,
	BEACH,
	GRASSLAND,
	FOREST,
	WETLAND,
	HIGHLAND,
	MOUNTAIN,
	CLIFF,
}

var resolution: int = 0
var height_data: PackedFloat32Array = PackedFloat32Array()
var moisture_data: PackedByteArray = PackedByteArray()
var biome_data: PackedByteArray = PackedByteArray()
var river_mask: PackedByteArray = PackedByteArray()
var flow_accumulation: PackedFloat32Array = PackedFloat32Array()
var seed: int = 0


func initialize(p_resolution: int, p_seed: int) -> void:
	resolution = p_resolution
	seed = p_seed
	var count: int = resolution * resolution
	height_data.resize(count)
	height_data.fill(0.0)
	moisture_data.resize(count)
	moisture_data.fill(0)
	biome_data.resize(count)
	biome_data.fill(Biome.OCEAN)
	river_mask.resize(count)
	river_mask.fill(0)
	flow_accumulation.resize(count)
	flow_accumulation.fill(1.0)


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if resolution < 3:
		errors.append("resolution must be at least 3")
	var expected: int = resolution * resolution
	if height_data.size() != expected:
		errors.append("height_data size mismatch")
	if moisture_data.size() != expected:
		errors.append("moisture_data size mismatch")
	if biome_data.size() != expected:
		errors.append("biome_data size mismatch")
	if river_mask.size() != expected:
		errors.append("river_mask size mismatch")
	if not flow_accumulation.is_empty() and flow_accumulation.size() != expected:
		errors.append("flow_accumulation size mismatch")
	return errors


func create_height_image(with_mipmaps: bool = true) -> Image:
	if not validate().is_empty():
		return null
	var image := Image.create_from_data(
		resolution,
		resolution,
		false,
		Image.FORMAT_RF,
		height_data.to_byte_array()
	)
	if image != null and with_mipmaps:
		image.generate_mipmaps()
	return image


func estimated_memory_bytes() -> int:
	return height_data.size() * 4 \
		+ moisture_data.size() \
		+ biome_data.size() \
		+ river_mask.size() \
		+ flow_accumulation.size() * 4


func release_flow_data() -> void:
	flow_accumulation = PackedFloat32Array()
