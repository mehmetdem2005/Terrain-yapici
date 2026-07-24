extends SceneTree

const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const GenerationResult = preload("res://addons/island_terrain/generation/terrain_generation_result.gd")
const Library = preload("res://addons/island_terrain/materials/terrain_material_library.gd")
const AtlasBuilder = preload("res://addons/island_terrain/materials/terrain_fallback_atlas_builder.gd")
const MaterialService = preload("res://addons/island_terrain/materials/terrain_material_service.gd")
const MetadataBuilder = preload("res://addons/island_terrain/rendering/terrain_metadata_texture_builder.gd")
const TERRAIN_SHADER = preload("res://addons/island_terrain/rendering/shaders/island_terrain.gdshader")

var _builder: MetadataBuilder
var _completed_texture: ImageTexture
var _failure: String = ""
var _frames: int = 0


func _init() -> void:
	call_deferred("_start_test")


func _start_test() -> void:
	var library := Library.create_default()
	library.fallback_tile_resolution = 16
	library.backend = Library.Backend.TEXTURE_ARRAY
	library.albedo_array = null
	library.albedo_atlas = null
	library.generate_fallback_atlas = true
	library.sanitize()

	var atlas: ImageTexture = AtlasBuilder.build_albedo(library)
	if atlas == null:
		_fail("fallback atlas was not created")
		return
	var atlas_image: Image = atlas.get_image()
	if atlas_image.get_width() != 64 or atlas_image.get_height() != 32:
		_fail("fallback atlas dimensions are incorrect")
		return
	if not atlas_image.has_mipmaps():
		_fail("fallback atlas has no mipmaps")
		return

	var shader_material := ShaderMaterial.new()
	shader_material.shader = TERRAIN_SHADER
	var service := MaterialService.new()
	var service_error: Error = service.configure(shader_material, library)
	if service_error != OK:
		_fail("material service configuration failed: %d" % service_error)
		return
	if service.effective_backend() != Library.Backend.ATLAS:
		_fail("missing texture array did not fall back to atlas")
		return
	if service.effective_albedo_atlas() == null:
		_fail("material service has no effective fallback atlas")
		return

	var result := GenerationResult.new()
	result.initialize(65, 9917)
	var center_x: int = floori(float(result.resolution) * 0.5)
	for y in range(result.resolution):
		for x in range(result.resolution):
			var index: int = y * result.resolution + x
			var biome_x: int = floori(float(x) / 9.0)
			var biome_y: int = floori(float(y) / 11.0)
			result.biome_data[index] = (biome_x + biome_y) % GenerationResult.Biome.size()
			result.moisture_data[index] = clampi((x * 4 + y * 2) % 256, 0, 255)
			result.river_mask[index] = 255 if x == center_x else 0
			result.flow_accumulation[index] = 1.0 + float(x * y)

	var budget := Budget.create_for_profile(Budget.DeviceProfile.LOW)
	budget.frame_work_budget_ms = 0.25
	_builder = MetadataBuilder.new()
	_builder.build_completed.connect(_on_builder_completed)
	_builder.build_failed.connect(_on_builder_failed)
	get_root().add_child(_builder)
	var build_error: Error = _builder.start(result, budget)
	if build_error != OK:
		_fail("metadata builder failed to start: %d" % build_error)
		return
	if _builder.estimated_working_memory_bytes() != 65 * 65 * 4:
		_fail("metadata builder working memory accounting is incorrect")


func _process(_delta: float) -> bool:
	_frames += 1
	if not _failure.is_empty():
		push_error(_failure)
		quit(1)
		return false
	if _completed_texture != null:
		_validate_texture()
		return false
	if _frames > 10000:
		_fail("material metadata builder timed out")
	return false


func _on_builder_completed(texture: ImageTexture) -> void:
	_completed_texture = texture


func _on_builder_failed(message: String) -> void:
	_failure = "material metadata builder failed: %s" % message


func _validate_texture() -> void:
	var image: Image = _completed_texture.get_image()
	if image.get_width() != 65 or image.get_height() != 65:
		_fail("metadata texture dimensions are incorrect")
		return
	if image.get_format() != Image.FORMAT_RGBA8:
		_fail("metadata texture format is not RGBA8")
		return
	if not image.has_mipmaps():
		_fail("metadata texture has no mipmaps")
		return
	var center: Color = image.get_pixel(32, 32)
	if center.g <= 0.0 or center.a <= 0.0:
		_fail("metadata texture did not encode moisture and flow")
		return
	if _builder.estimated_working_memory_bytes() != 0:
		_fail("metadata builder did not release temporary RGBA memory")
		return
	print("IslandTerrain material system tests: PASS")
	quit(0)


func _fail(message: String) -> void:
	_failure = message
