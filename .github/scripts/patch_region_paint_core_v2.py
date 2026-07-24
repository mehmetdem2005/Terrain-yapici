from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


facade_path = Path("addons/island_terrain/island_terrain_3d.gd")
text = facade_path.read_text()
text = replace_once(
    text,
    'const MaterialRuntime = preload("res://addons/island_terrain/materials/terrain_material_runtime.gd")\nconst TERRAIN_SHADER',
    'const MaterialRuntime = preload("res://addons/island_terrain/materials/terrain_material_runtime.gd")\n'
    'const MaterialOverrideSync = preload("res://addons/island_terrain/rendering/terrain_material_override_sync.gd")\n'
    'const PaintCommand = preload("res://addons/island_terrain/application/terrain_paint_command.gd")\n'
    'const PaintTransaction = preload("res://addons/island_terrain/application/terrain_paint_transaction.gd")\n'
    'const PaintService = preload("res://addons/island_terrain/application/terrain_material_paint_service.gd")\n'
    'const TERRAIN_SHADER',
    "facade imports",
)
text = replace_once(
    text,
    'signal material_metadata_failed(message: String)\nsignal terrain_edited(transaction: EditTransaction)',
    'signal material_metadata_failed(message: String)\nsignal terrain_edited(transaction: EditTransaction)\n'
    'signal terrain_painted(transaction: PaintTransaction)',
    "paint signal",
)
text = replace_once(
    text,
    'var _material_runtime: MaterialRuntime\nvar _edit_service: EditService',
    'var _material_runtime: MaterialRuntime\nvar _material_override_sync: MaterialOverrideSync\n'
    'var _edit_service: EditService\nvar _paint_service: PaintService',
    "paint fields",
)
text = replace_once(
    text,
    '''func get_material_working_memory_bytes() -> int:
\treturn _material_runtime.estimated_working_memory_bytes() if _material_runtime != null else 0


func refresh_material_library()''',
    '''func get_material_working_memory_bytes() -> int:
\tvar metadata_bytes: int = _material_runtime.estimated_working_memory_bytes() if _material_runtime != null else 0
\tvar override_bytes: int = _material_override_sync.estimated_memory_bytes() if _material_override_sync != null else 0
\treturn metadata_bytes + override_bytes


func get_material_override_texture() -> ImageTexture:
\treturn _material_override_sync.texture() if _material_override_sync != null else null


func flush_material_override_sync() -> Error:
\treturn _material_override_sync.flush_all() if _material_override_sync != null else ERR_UNCONFIGURED


func refresh_material_library()''',
    "material public api",
)
text = replace_once(
    text,
    '''func apply_edit_transaction_after(transaction: EditTransaction) -> Error:
\tif _edit_service == null:
\t\treturn ERR_UNCONFIGURED
\tvar error: Error = _edit_service.apply_transaction_after(transaction)
\tif error == OK:
\t\t_has_height_edits = true
\t\t_queue_collision_transaction(transaction)
\treturn error


func set_collision_tracking_target''',
    '''func apply_edit_transaction_after(transaction: EditTransaction) -> Error:
\tif _edit_service == null:
\t\treturn ERR_UNCONFIGURED
\tvar error: Error = _edit_service.apply_transaction_after(transaction)
\tif error == OK:
\t\t_has_height_edits = true
\t\t_queue_collision_transaction(transaction)
\treturn error


func apply_paint_command(command: PaintCommand) -> PaintTransaction:
\tif _paint_service == null:
\t\tpush_error("IT-043: Terrain paint service is not initialized")
\t\treturn null
\tvar transaction: PaintTransaction = _paint_service.apply_paint(command)
\tif transaction != null and not transaction.is_empty():
\t\tterrain_painted.emit(transaction)
\treturn transaction


func apply_paint_transaction_before(transaction: PaintTransaction) -> Error:
\treturn _paint_service.apply_transaction_before(transaction) if _paint_service != null else ERR_UNCONFIGURED


func apply_paint_transaction_after(transaction: PaintTransaction) -> Error:
\treturn _paint_service.apply_transaction_after(transaction) if _paint_service != null else ERR_UNCONFIGURED


func get_biome_override_at_world(world_position: Vector3) -> Dictionary:
\tif _coordinate_system == null or _region_repository == null:
\t\treturn {}
\tvar coord: Vector2i = _coordinate_system.world_to_region_clamped(world_position)
\tvar region: RegionData = _get_existing_paint_region(coord)
\tif region == null:
\t\treturn {}
\tvar pixel: Vector2i = _coordinate_system.world_to_region_pixel(world_position, coord)
\treturn {
\t\t"id": region.biome_override_id(pixel),
\t\t"strength": float(region.biome_override_strength(pixel)) / 255.0,
\t}


func get_material_override_at_world(world_position: Vector3) -> Dictionary:
\tif _coordinate_system == null or _region_repository == null:
\t\treturn {}
\tvar coord: Vector2i = _coordinate_system.world_to_region_clamped(world_position)
\tvar region: RegionData = _get_existing_paint_region(coord)
\tif region == null:
\t\treturn {}
\tvar pixel: Vector2i = _coordinate_system.world_to_region_pixel(world_position, coord)
\treturn {
\t\t"id": region.material_override_id(pixel),
\t\t"strength": float(region.material_override_strength(pixel)) / 255.0,
\t}


func set_collision_tracking_target''',
    "paint facade methods",
)
text = replace_once(
    text,
    '''func get_biome_at_world(world_position: Vector3) -> int:
\tvar index: int = _generation_index_at_world(world_position)
\treturn int(_generation_result.biome_data[index]) \\
\t\tif index >= 0 else GenerationResult.Biome.OCEAN''',
    '''func get_biome_at_world(world_position: Vector3) -> int:
\tvar override_data: Dictionary = get_biome_override_at_world(world_position)
\tif float(override_data.get("strength", 0.0)) > 0.0:
\t\treturn int(override_data.get("id", GenerationResult.Biome.OCEAN))
\tvar index: int = _generation_index_at_world(world_position)
\treturn int(_generation_result.biome_data[index]) \\
\t\tif index >= 0 else GenerationResult.Biome.OCEAN''',
    "biome override query",
)
text = replace_once(
    text,
    '''\t_edit_service = EditService.new(
\t\tmanifest,
\t\t_coordinate_system,
\t\t_region_repository,
\t\t_macro_sync,
\t\tbase_sampler
\t)
\t_initialized = true''',
    '''\t_edit_service = EditService.new(
\t\tmanifest,
\t\t_coordinate_system,
\t\t_region_repository,
\t\t_macro_sync,
\t\tbase_sampler
\t)
\t_paint_service = PaintService.new(
\t\tmanifest,
\t\t_coordinate_system,
\t\t_region_repository,
\t\t_material_override_sync
\t)
\t_initialized = true''',
    "paint service initialization",
)
text = replace_once(
    text,
    '''\tif material_error != OK:
\t\tpush_error("IT-035: Terrain material runtime configuration failed: %d" % material_error)
\t\treturn false
\treturn true''',
    '''\tif material_error != OK:
\t\tpush_error("IT-035: Terrain material runtime configuration failed: %d" % material_error)
\t\treturn false

\tvar override_node: Node = get_node_or_null("__TerrainMaterialOverrideSync")
\tif override_node != null:
\t\t_material_override_sync = override_node as MaterialOverrideSync
\t\tif _material_override_sync == null:
\t\t\tpush_error("IT-044: Reserved child name __TerrainMaterialOverrideSync is occupied")
\t\t\treturn false
\telse:
\t\t_material_override_sync = MaterialOverrideSync.new()
\t\t_material_override_sync.name = "__TerrainMaterialOverrideSync"
\t\tadd_child(_material_override_sync, false, Node.INTERNAL_MODE_BACK)
\tvar override_callback := Callable(self, "_on_material_override_texture_changed")
\tif not _material_override_sync.override_texture_changed.is_connected(override_callback):
\t\t_material_override_sync.override_texture_changed.connect(override_callback)
\tvar override_error: Error = _material_override_sync.configure(
\t\tmanifest,
\t\t_coordinate_system,
\t\t_region_repository,
\t\tmemory_budget
\t)
\tif override_error != OK:
\t\tpush_error("IT-045: Terrain material override sync failed: %d" % override_error)
\t\treturn false
\t_material_runtime.set_override_texture(_material_override_sync.texture())
\treturn true''',
    "override sync initialization",
)
text = replace_once(
    text,
    '''func _on_material_metadata_failed(message: String) -> void:
\tpush_error("IT-036: Terrain material metadata failed: %s" % message)
\tmaterial_metadata_failed.emit(message)


func _configure_collision_service()''',
    '''func _on_material_metadata_failed(message: String) -> void:
\tpush_error("IT-036: Terrain material metadata failed: %s" % message)
\tmaterial_metadata_failed.emit(message)


func _on_material_override_texture_changed(texture: ImageTexture) -> void:
\tif _material_runtime != null:
\t\t_material_runtime.set_override_texture(texture)


func _configure_collision_service()''',
    "override texture callback",
)
text = replace_once(
    text,
    '''func _queue_collision_transaction(transaction: EditTransaction) -> void:
\tif _collision_service != null and transaction != null:
\t\t_collision_service.queue_transaction(transaction)


func _world_to_image_pixel''',
    '''func _queue_collision_transaction(transaction: EditTransaction) -> void:
\tif _collision_service != null and transaction != null:
\t\t_collision_service.queue_transaction(transaction)


func _get_existing_paint_region(coord: Vector2i) -> RegionData:
\tvar cached: RegionData = _region_repository.get_cached(coord)
\tif cached != null:
\t\treturn cached
\tvar writable_exists: bool = ResourceLoader.exists(
\t\t_region_repository.writable_region_file_path(coord)
\t)
\tvar source_exists: bool = ResourceLoader.exists(
\t\t_region_repository.source_region_file_path(coord)
\t)
\tif not writable_exists and not source_exists:
\t\treturn null
\treturn _region_repository.get_or_create(coord)


func _world_to_image_pixel''',
    "read-only paint region query",
)
text = replace_once(
    text,
    '''\t\tif _material_runtime != null:
\t\t\t_material_runtime.configure(_terrain_material, material_library, memory_budget)
\t\t_configure_collision_service()''',
    '''\t\tif _material_runtime != null:
\t\t\t_material_runtime.configure(_terrain_material, material_library, memory_budget)
\t\tif _material_override_sync != null:
\t\t\t_material_override_sync.configure(
\t\t\t\tmanifest,
\t\t\t\t_coordinate_system,
\t\t\t\t_region_repository,
\t\t\t\tmemory_budget
\t\t\t)
\t\t\t_material_runtime.set_override_texture(_material_override_sync.texture())
\t\t_configure_collision_service()''',
    "profile override reconfigure",
)
facade_path.write_text(text)


repository_path = Path("addons/island_terrain/infrastructure/terrain_region_repository.gd")
text = repository_path.read_text()
text = replace_once(
    text,
    '''\tif loaded.checksum != 0:
\t\tvar current_checksum: int = _calculate_checksum(loaded)
\t\tif loaded.checksum != current_checksum:
\t\t\tvar legacy_checksum: int = _calculate_legacy_height_checksum(loaded.height_data)
\t\t\tif loaded.height_valid_mask.is_empty() \\
\t\t\t\tand not loaded.height_is_dense \\
\t\t\t\tand loaded.checksum == legacy_checksum:
\t\t\t\tloaded.height_is_dense = true
\t\t\t\tloaded.checksum = _calculate_checksum(loaded)
\t\t\telse:
\t\t\t\tpush_error("IT-009: Region checksum mismatch for %s at %s" % [coord, path])
\t\t\t\treturn null''',
    '''\tif loaded.checksum != 0:
\t\tvar current_checksum: int = _calculate_checksum(loaded)
\t\tif loaded.checksum != current_checksum:
\t\t\tvar v2_checksum: int = _calculate_v2_checksum(loaded)
\t\t\tvar legacy_checksum: int = _calculate_legacy_height_checksum(loaded.height_data)
\t\t\tif loaded.checksum == v2_checksum:
\t\t\t\tloaded.checksum = current_checksum
\t\t\telif loaded.height_valid_mask.is_empty() \\
\t\t\t\tand not loaded.height_is_dense \\
\t\t\t\tand loaded.checksum == legacy_checksum:
\t\t\t\tloaded.height_is_dense = true
\t\t\t\tloaded.checksum = _calculate_checksum(loaded)
\t\t\telse:
\t\t\t\tpush_error("IT-009: Region checksum mismatch for %s at %s" % [coord, path])
\t\t\t\treturn null''',
    "checksum migration",
)
text = replace_once(
    text,
    '''func _calculate_checksum(region: RegionData) -> int:
\treturn int(hash([
\t\tregion.height_data,
\t\tregion.height_valid_mask,
\t\tregion.height_is_dense,
\t])) & 0x7fffffff


func _calculate_legacy_height_checksum(values: PackedFloat32Array) -> int:''',
    '''func _calculate_checksum(region: RegionData) -> int:
\treturn int(hash([
\t\tregion.height_data,
\t\tregion.height_valid_mask,
\t\tregion.height_is_dense,
\t\tregion.material_index_data,
\t\tregion.material_valid_mask,
\t\tregion.material_weight_data,
\t\tregion.biome_data,
\t\tregion.biome_valid_mask,
\t\tregion.color_tint_data,
\t\tregion.wetness_data,
\t\tregion.hole_mask,
\t\tregion.foliage_mask,
\t\tregion.runtime_delta_data,
\t])) & 0x7fffffff


func _calculate_v2_checksum(region: RegionData) -> int:
\treturn int(hash([
\t\tregion.height_data,
\t\tregion.height_valid_mask,
\t\tregion.height_is_dense,
\t])) & 0x7fffffff


func _calculate_legacy_height_checksum(values: PackedFloat32Array) -> int:''',
    "combined checksum",
)
repository_path.write_text(text)


shader_path = Path("addons/island_terrain/rendering/shaders/island_terrain.gdshader")
text = shader_path.read_text()
text = replace_once(
    text,
    "\tALBEDO = mix(fallback_color, albedo, max(metadata_mix, manual_strength));",
    "\tfloat override_mix = max(override_data.g, manual_strength);\n"
    "\tALBEDO = mix(fallback_color, albedo, max(metadata_mix, override_mix));",
    "biome-only override blend",
)
shader_path.write_text(text)
