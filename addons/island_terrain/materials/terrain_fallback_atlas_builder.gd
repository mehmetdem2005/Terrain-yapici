@tool
extends RefCounted
class_name IslandTerrainFallbackAtlasBuilder

const Library = preload("res://addons/island_terrain/materials/terrain_material_library.gd")
const Layer = preload("res://addons/island_terrain/materials/terrain_material_layer.gd")


static func build_albedo(library: Library) -> ImageTexture:
	if library == null:
		return null
	library.sanitize()
	var tile_size: int = library.fallback_tile_resolution
	var width: int = library.atlas_columns * tile_size
	var height: int = library.atlas_rows * tile_size
	var image := Image.create_empty(width, height, true, Image.FORMAT_RGBA8)
	image.fill(Color(0.78, 0.78, 0.78, 1.0))
	var layer_index: int = 0
	for layer in library.all_layers():
		_draw_layer(image, layer, layer_index, library.atlas_columns, tile_size)
		layer_index += 1
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func _draw_layer(
	image: Image,
	layer: Layer,
	layer_index: int,
	columns: int,
	tile_size: int
) -> void:
	var slot_x: int = layer.atlas_slot % columns
	var slot_y: int = floori(float(layer.atlas_slot) / float(columns))
	var origin := Vector2i(slot_x * tile_size, slot_y * tile_size)
	var gutter: int = maxi(2, floori(float(tile_size) / 16.0))
	for local_y in range(tile_size):
		for local_x in range(tile_size):
			var sample_x: int = clampi(local_x, gutter, tile_size - gutter - 1)
			var sample_y: int = clampi(local_y, gutter, tile_size - gutter - 1)
			var noise: float = _hash_noise(sample_x, sample_y, layer_index + 17)
			var pattern: float = _layer_pattern(layer_index, sample_x, sample_y, noise)
			var brightness: float = clampf(0.82 + pattern * 0.30, 0.58, 1.0)
			var color := Color(brightness, brightness, brightness, 1.0)
			image.set_pixelv(origin + Vector2i(local_x, local_y), color)


static func _layer_pattern(
	layer_index: int,
	x: int,
	y: int,
	noise: float
) -> float:
	match layer_index:
		0:
			return noise * 0.55 + _hash_noise(x / 3, y / 3, 91) * 0.20
		1:
			var blade: float = 0.18 if (x * 3 + y * 5) % 17 == 0 else 0.0
			return noise * 0.58 + blade
		2:
			var litter: float = -0.20 if (x * 7 + y * 11) % 23 == 0 else 0.0
			return noise * 0.48 + litter
		3:
			var ripple: float = sin(float(x + y) * 0.32) * 0.08
			return noise * 0.40 + ripple
		4:
			var strata: float = sin(float(y) * 0.42 + noise * 2.4) * 0.17
			return noise * 0.36 + strata
		5:
			var grain: float = sin(float(x - y) * 0.24) * 0.10
			return noise * 0.30 + grain
	return noise * 0.50


static func _hash_noise(x: int, y: int, seed: int) -> float:
	var value: int = x * 374761393 + y * 668265263 + seed * 1442695041
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0xffff) / 65535.0
