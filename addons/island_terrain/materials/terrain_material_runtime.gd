@tool
extends Node
class_name IslandTerrainMaterialRuntime

const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Result = preload("res://addons/island_terrain/generation/terrain_generation_result.gd")
const Library = preload("res://addons/island_terrain/materials/terrain_material_library.gd")
const MaterialService = preload("res://addons/island_terrain/materials/terrain_material_service.gd")
const MetadataBuilder = preload("res://addons/island_terrain/rendering/terrain_metadata_texture_builder.gd")

signal metadata_progress(progress: float)
signal metadata_completed(texture: ImageTexture)
signal metadata_failed(message: String)

var _budget: Budget
var _library: Library
var _material_service: MaterialService
var _metadata_builder: MetadataBuilder
var _metadata_texture: ImageTexture


func configure(
	shader_material: ShaderMaterial,
	library: Library,
	budget: Budget
) -> Error:
	if shader_material == null or budget == null:
		return ERR_INVALID_PARAMETER
	_budget = budget
	_library = library if library != null else Library.create_default()
	if _material_service == null:
		_material_service = MaterialService.new()
	var service_error: Error = _material_service.configure(shader_material, _library)
	if service_error != OK:
		return service_error
	_ensure_builder()
	if _metadata_texture != null:
		_material_service.set_metadata_texture(_metadata_texture)
	return OK


func rebuild_metadata(result: Result) -> Error:
	if _budget == null or _material_service == null:
		return ERR_UNCONFIGURED
	_ensure_builder()
	_metadata_texture = null
	_material_service.set_metadata_texture(null)
	return _metadata_builder.start(result, _budget)


func cancel() -> void:
	if _metadata_builder != null:
		_metadata_builder.cancel()


func is_building_metadata() -> bool:
	return _metadata_builder != null and _metadata_builder.is_running()


func effective_backend() -> int:
	return _material_service.effective_backend() \
		if _material_service != null else Library.Backend.COLOR_ONLY


func metadata_texture() -> ImageTexture:
	return _metadata_texture


func estimated_working_memory_bytes() -> int:
	return _metadata_builder.estimated_working_memory_bytes() \
		if _metadata_builder != null else 0


func _ensure_builder() -> void:
	if _metadata_builder != null:
		return
	_metadata_builder = MetadataBuilder.new()
	_metadata_builder.name = "MetadataTextureBuilder"
	add_child(_metadata_builder, false, Node.INTERNAL_MODE_BACK)
	_metadata_builder.build_progress.connect(_on_build_progress)
	_metadata_builder.build_completed.connect(_on_build_completed)
	_metadata_builder.build_failed.connect(_on_build_failed)


func _on_build_progress(progress: float) -> void:
	metadata_progress.emit(progress)


func _on_build_completed(texture: ImageTexture) -> void:
	_metadata_texture = texture
	_material_service.set_metadata_texture(texture)
	metadata_completed.emit(texture)


func _on_build_failed(message: String) -> void:
	metadata_failed.emit(message)
