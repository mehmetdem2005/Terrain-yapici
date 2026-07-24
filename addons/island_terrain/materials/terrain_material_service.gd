@tool
extends RefCounted
class_name IslandTerrainMaterialService

const Library = preload("res://addons/island_terrain/materials/terrain_material_library.gd")
const Layer = preload("res://addons/island_terrain/materials/terrain_material_layer.gd")
const AtlasBuilder = preload("res://addons/island_terrain/materials/terrain_fallback_atlas_builder.gd")

var _shader_material: ShaderMaterial
var _library: Library
var _generated_atlas: ImageTexture
var _metadata_texture: Texture2D
var _override_texture: Texture2D
var _effective_backend: int = Library.Backend.COLOR_ONLY
var _runtime_detail_lod_limit: int = 0


func configure(shader_material: ShaderMaterial, library: Library) -> Error:
	if shader_material == null or shader_material.shader == null:
		return ERR_INVALID_PARAMETER
	_shader_material = shader_material
	_library = library if library != null else Library.create_default()
	_library.sanitize()
	_runtime_detail_lod_limit = _library.detail_lod_limit
	_resolve_backend()
	_apply_parameters()
	return OK


func set_metadata_texture(texture: Texture2D) -> void:
	_metadata_texture = texture
	if _shader_material != null:
		_shader_material.set_shader_parameter(&"terrain_metadata_texture", texture)
		_shader_material.set_shader_parameter(&"has_metadata_texture", texture != null)


func set_override_texture(texture: Texture2D) -> void:
	_override_texture = texture
	if _shader_material != null:
		_shader_material.set_shader_parameter(&"terrain_override_texture", texture)
		_shader_material.set_shader_parameter(&"has_override_texture", texture != null)


func set_runtime_detail_lod_limit(value: int) -> void:
	_runtime_detail_lod_limit = clampi(value, 0, 7)
	if _shader_material != null:
		_shader_material.set_shader_parameter(
			&"detail_lod_limit",
			float(_runtime_detail_lod_limit)
		)


func get_runtime_detail_lod_limit() -> int:
	return _runtime_detail_lod_limit


func effective_backend() -> int:
	return _effective_backend


func effective_albedo_atlas() -> Texture2D:
	if _library != null and _library.albedo_atlas != null:
		return _library.albedo_atlas
	return _generated_atlas


func library() -> Library:
	return _library


func _resolve_backend() -> void:
	var requested_backend: int = _library.backend
	_effective_backend = _library.effective_backend()
	_generated_atlas = null
	if requested_backend == Library.Backend.TEXTURE_ARRAY and _library.albedo_array == null:
		push_warning("IT-W10: Texture array backend has no albedo array; using the mobile-safe fallback backend")
	if _effective_backend == Library.Backend.ATLAS \
		and _library.albedo_atlas == null \
		and _library.generate_fallback_atlas:
		_generated_atlas = AtlasBuilder.build_albedo(_library)
		if _generated_atlas == null:
			_effective_backend = Library.Backend.COLOR_ONLY
	if _effective_backend == Library.Backend.ATLAS \
		and _library.albedo_atlas == null \
		and _generated_atlas == null:
		_effective_backend = Library.Backend.COLOR_ONLY


func _apply_parameters() -> void:
	_shader_material.set_shader_parameter(&"material_backend", _effective_backend)
	_shader_material.set_shader_parameter(
		&"atlas_grid",
		Vector2(float(_library.atlas_columns), float(_library.atlas_rows))
	)
	set_runtime_detail_lod_limit(_runtime_detail_lod_limit)
	_shader_material.set_shader_parameter(
		&"metadata_blend_strength",
		_library.metadata_blend_strength
	)
	_shader_material.set_shader_parameter(&"albedo_atlas", effective_albedo_atlas())
	_shader_material.set_shader_parameter(&"albedo_array", _library.albedo_array)
	_shader_material.set_shader_parameter(
		&"has_albedo_atlas",
		effective_albedo_atlas() != null
	)
	_shader_material.set_shader_parameter(
		&"has_albedo_array",
		_library.albedo_array != null
	)
	set_metadata_texture(_metadata_texture)
	set_override_texture(_override_texture)
	_apply_layer(&"sand", _library.sand)
	_apply_layer(&"grass", _library.grass)
	_apply_layer(&"forest", _library.forest)
	_apply_layer(&"wetland", _library.wetland)
	_apply_layer(&"rock", _library.rock)
	_apply_layer(&"mountain", _library.mountain)


func _apply_layer(prefix: StringName, layer: Layer) -> void:
	_shader_material.set_shader_parameter(
		StringName("%s_tint" % prefix),
		Vector3(layer.tint.r, layer.tint.g, layer.tint.b)
	)
	_shader_material.set_shader_parameter(
		StringName("%s_slot" % prefix),
		float(layer.atlas_slot)
	)
	_shader_material.set_shader_parameter(
		StringName("%s_meters_per_tile" % prefix),
		layer.meters_per_tile
	)
	_shader_material.set_shader_parameter(
		StringName("%s_roughness" % prefix),
		layer.roughness
	)
	_shader_material.set_shader_parameter(
		StringName("%s_metallic" % prefix),
		layer.metallic
	)
