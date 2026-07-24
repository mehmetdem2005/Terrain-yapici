from pathlib import Path


def once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


path = Path("addons/island_terrain/island_terrain_3d.gd")
text = path.read_text()
text = once(
    text,
    'const MaterialRuntime = preload("res://addons/island_terrain/materials/terrain_material_runtime.gd")\nconst HealthPolicy',
    'const MaterialRuntime = preload("res://addons/island_terrain/materials/terrain_material_runtime.gd")\n'
    'const FoliageLibrary = preload("res://addons/island_terrain/foliage/terrain_foliage_library.gd")\n'
    'const FoliageStreamer = preload("res://addons/island_terrain/foliage/terrain_foliage_streamer.gd")\n'
    'const HealthPolicy',
    "foliage imports",
)
text = once(
    text,
    '''@export_range(0.05, 1.0, 0.05) var collision_update_interval_s: float = 0.20

@export_category("Runtime Health")''',
    '''@export_range(0.05, 1.0, 0.05) var collision_update_interval_s: float = 0.20

@export_category("Foliage Streaming")
@export var foliage_enabled: bool = false:
\tset = _set_foliage_enabled
@export var foliage_library: FoliageLibrary
@export var foliage_target_path: NodePath

@export_category("Runtime Health")''',
    "foliage exports",
)
text = once(
    text,
    'var _collision_service: CollisionService\nvar _generation_controller: GenerationController',
    'var _collision_service: CollisionService\nvar _foliage_streamer: FoliageStreamer\n'
    'var _generation_controller: GenerationController',
    "foliage field",
)
text = once(
    text,
    '''\tif _collision_service != null:
\t\t_collision_service.refresh_now()
\tif _transform_warning_emitted:''',
    '''\tif _collision_service != null:
\t\t_collision_service.refresh_now()
\tif _foliage_streamer != null and _generation_result != null:
\t\t_configure_foliage_streamer()
\tif _transform_warning_emitted:''',
    "transform refresh",
)
text = once(
    text,
    '''func get_active_collision_patch_count() -> int:
\treturn _collision_service.active_patch_count() if _collision_service != null else 0


func get_terrain_base_y()''',
    '''func get_active_collision_patch_count() -> int:
\treturn _collision_service.active_patch_count() if _collision_service != null else 0


func set_foliage_tracking_target(target: Node3D) -> void:
\tif _foliage_streamer != null:
\t\t_foliage_streamer.set_tracking_target(target)


func refresh_foliage_now() -> void:
\tif _foliage_streamer != null:
\t\t_foliage_streamer.refresh_now()


func refresh_foliage_library() -> Error:
\tif not _initialized or _generation_result == null:
\t\treturn ERR_UNCONFIGURED
\treturn _configure_foliage_streamer()


func get_active_foliage_cell_count() -> int:
\treturn _foliage_streamer.active_cell_count() if _foliage_streamer != null else 0


func get_active_foliage_instance_count() -> int:
\treturn _foliage_streamer.active_instance_count() if _foliage_streamer != null else 0


func get_foliage_transform_memory_bytes() -> int:
\treturn _foliage_streamer.estimated_transform_memory_bytes() if _foliage_streamer != null else 0


func get_terrain_base_y()''',
    "foliage public api",
)
text = once(
    text,
    '''\tif transaction != null and not transaction.is_empty():
\t\t_has_height_edits = true
\t\t_queue_collision_transaction(transaction)
\t\tterrain_edited.emit(transaction)''',
    '''\tif transaction != null and not transaction.is_empty():
\t\t_has_height_edits = true
\t\t_queue_collision_transaction(transaction)
\t\t_queue_foliage_transaction(transaction)
\t\tterrain_edited.emit(transaction)''',
    "sculpt foliage invalidation",
)
text = once(
    text,
    '''\tvar error: Error = _edit_service.apply_transaction_before(transaction)
\tif error == OK:
\t\t_queue_collision_transaction(transaction)
\treturn error''',
    '''\tvar error: Error = _edit_service.apply_transaction_before(transaction)
\tif error == OK:
\t\t_queue_collision_transaction(transaction)
\t\t_queue_foliage_transaction(transaction)
\treturn error''',
    "sculpt undo foliage invalidation",
)
text = once(
    text,
    '''\tvar error: Error = _edit_service.apply_transaction_after(transaction)
\tif error == OK:
\t\t_has_height_edits = true
\t\t_queue_collision_transaction(transaction)
\treturn error''',
    '''\tvar error: Error = _edit_service.apply_transaction_after(transaction)
\tif error == OK:
\t\t_has_height_edits = true
\t\t_queue_collision_transaction(transaction)
\t\t_queue_foliage_transaction(transaction)
\treturn error''',
    "sculpt redo foliage invalidation",
)
text = once(
    text,
    '''\tvar transaction: PaintTransaction = _paint_service.apply_paint(command)
\tif transaction != null and not transaction.is_empty():
\t\tterrain_painted.emit(transaction)
\treturn transaction


func apply_paint_transaction_before(transaction: PaintTransaction) -> Error:
\treturn _paint_service.apply_transaction_before(transaction) if _paint_service != null else ERR_UNCONFIGURED


func apply_paint_transaction_after(transaction: PaintTransaction) -> Error:
\treturn _paint_service.apply_transaction_after(transaction) if _paint_service != null else ERR_UNCONFIGURED''',
    '''\tvar transaction: PaintTransaction = _paint_service.apply_paint(command)
\tif transaction != null and not transaction.is_empty():
\t\t_queue_foliage_transaction(transaction)
\t\tterrain_painted.emit(transaction)
\treturn transaction


func apply_paint_transaction_before(transaction: PaintTransaction) -> Error:
\tif _paint_service == null:
\t\treturn ERR_UNCONFIGURED
\tvar error: Error = _paint_service.apply_transaction_before(transaction)
\tif error == OK:
\t\t_queue_foliage_transaction(transaction)
\treturn error


func apply_paint_transaction_after(transaction: PaintTransaction) -> Error:
\tif _paint_service == null:
\t\treturn ERR_UNCONFIGURED
\tvar error: Error = _paint_service.apply_transaction_after(transaction)
\tif error == OK:
\t\t_queue_foliage_transaction(transaction)
\treturn error''',
    "paint foliage invalidation",
)
text = once(
    text,
    '''func get_material_override_at_world(world_position: Vector3) -> Dictionary:
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
    '''func get_material_override_at_world(world_position: Vector3) -> Dictionary:
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


func get_foliage_mask_at_world(world_position: Vector3) -> float:
\tif _coordinate_system == null or _region_repository == null:
\t\treturn 1.0
\tvar coord: Vector2i = _coordinate_system.world_to_region_clamped(world_position)
\tvar region: RegionData = _get_existing_paint_region(coord)
\tif region == null or region.foliage_mask.is_empty():
\t\treturn 1.0
\tvar pixel: Vector2i = _coordinate_system.world_to_region_pixel(world_position, coord)
\tvar index: int = pixel.y * region.sample_count + pixel.x
\treturn float(region.foliage_mask[index]) / 255.0


func set_collision_tracking_target''',
    "foliage mask api",
)
text = once(
    text,
    '''\telse:
\t\t_collision_service = CollisionService.new()
\t\t_collision_service.name = "__TerrainCollision"
\t\tadd_child(_collision_service, false, Node.INTERNAL_MODE_BACK)

\t_generation_controller = GenerationController.new()''',
    '''\telse:
\t\t_collision_service = CollisionService.new()
\t\t_collision_service.name = "__TerrainCollision"
\t\tadd_child(_collision_service, false, Node.INTERNAL_MODE_BACK)

\tvar foliage_node: Node = get_node_or_null("__TerrainFoliage")
\tif foliage_node != null:
\t\t_foliage_streamer = foliage_node as FoliageStreamer
\t\tif _foliage_streamer == null:
\t\t\tpush_error("IT-051: Reserved child name __TerrainFoliage is occupied")
\t\t\treturn false
\telse:
\t\t_foliage_streamer = FoliageStreamer.new()
\t\t_foliage_streamer.name = "__TerrainFoliage"
\t\tadd_child(_foliage_streamer, false, Node.INTERNAL_MODE_BACK)
\t_foliage_streamer.set_enabled(false)

\t_generation_controller = GenerationController.new()''',
    "foliage service node",
)
text = once(
    text,
    '''\t_configure_collision_service()
\t_generation_controller.release_completed_job()''',
    '''\t_configure_collision_service()
\tvar foliage_error: Error = _configure_foliage_streamer()
\tif foliage_error != OK:
\t\tpush_error("IT-052: Terrain foliage configuration failed: %d" % foliage_error)
\t_generation_controller.release_completed_job()''',
    "foliage generation completion",
)
text = once(
    text,
    '''func _configure_collision_service() -> void:
\tif _collision_service == null or manifest == null or memory_budget == null:
\t\treturn''',
    '''func _ensure_foliage_library() -> void:
\tif foliage_library == null:
\t\tfoliage_library = FoliageLibrary.create_default()
\telse:
\t\tfoliage_library.sanitize()


func _configure_foliage_streamer() -> Error:
\tif _foliage_streamer == null or manifest == null or _generation_result == null:
\t\treturn ERR_UNCONFIGURED
\t_ensure_foliage_library()
\tvar error: Error = _foliage_streamer.configure(
\t\tmanifest.world_seed,
\t\tfloat(manifest.world_size_m),
\t\tfoliage_library,
\t\tVector2(global_position.x, global_position.z),
\t\tCallable(self, "get_height_at_world"),
\t\tCallable(self, "get_normal_at_world"),
\t\tCallable(self, "get_biome_at_world"),
\t\tCallable(self, "get_moisture_at_world"),
\t\tCallable(self, "get_foliage_mask_at_world")
\t)
\tif error != OK:
\t\t_foliage_streamer.set_enabled(false)
\t\treturn error
\t_foliage_streamer.set_enabled(foliage_enabled)
\tvar target: Node3D = null
\tif not foliage_target_path.is_empty():
\t\ttarget = get_node_or_null(foliage_target_path) as Node3D
\t_foliage_streamer.set_tracking_target(target)
\treturn OK


func _configure_collision_service() -> void:
\tif _collision_service == null or manifest == null or memory_budget == null:
\t\treturn''',
    "foliage configure function",
)
text = once(
    text,
    '''func _queue_collision_transaction(transaction: EditTransaction) -> void:
\tif _collision_service != null and transaction != null:
\t\t_collision_service.queue_transaction(transaction)


func _get_existing_paint_region''',
    '''func _queue_collision_transaction(transaction: EditTransaction) -> void:
\tif _collision_service != null and transaction != null:
\t\t_collision_service.queue_transaction(transaction)


func _queue_foliage_transaction(transaction: Variant) -> void:
\tif _foliage_streamer == null or transaction == null or _coordinate_system == null:
\t\treturn
\tfor delta in transaction.deltas:
\t\tvar first_world: Vector3 = _coordinate_system.region_pixel_to_world(
\t\t\tdelta.coord,
\t\t\tdelta.rect.position
\t\t)
\t\tvar last_world: Vector3 = _coordinate_system.region_pixel_to_world(
\t\t\tdelta.coord,
\t\t\tVector2i(delta.rect.end.x - 1, delta.rect.end.y - 1)
\t\t)
\t\tvar center: Vector3 = (first_world + last_world) * 0.5
\t\tvar radius: float = Vector2(first_world.x, first_world.z).distance_to(
\t\t\tVector2(last_world.x, last_world.z)
\t\t) * 0.5
\t\t_foliage_streamer.invalidate_world_circle(center, radius)


func _get_existing_paint_region''',
    "foliage transaction invalidation",
)
text = once(
    text,
    '''func _metric_pending_collision_builds() -> int:
\treturn _collision_service.pending_build_count() if _collision_service != null else 0


func _metric_resident_memory_bytes() -> int:
\treturn _metric_region_cache_bytes() \\
\t\t+ get_material_working_memory_bytes() \\
\t\t+ get_material_resident_memory_bytes()''',
    '''func _metric_pending_collision_builds() -> int:
\treturn _collision_service.pending_build_count() if _collision_service != null else 0


func _metric_pending_foliage_builds() -> int:
\treturn _foliage_streamer.pending_build_count() if _foliage_streamer != null else 0


func _metric_resident_memory_bytes() -> int:
\treturn _metric_region_cache_bytes() \\
\t\t+ get_material_working_memory_bytes() \\
\t\t+ get_material_resident_memory_bytes() \\
\t\t+ get_foliage_transform_memory_bytes()''',
    "foliage metrics",
)
text = once(
    text,
    '''\tif _collision_service != null:
\t\t_collision_service.trim_pool(4)''',
    '''\tif _collision_service != null:
\t\t_collision_service.trim_pool(4)
\tif _foliage_streamer != null:
\t\t_foliage_streamer.release_pool(4)''',
    "foliage reclaim",
)
text = once(
    text,
    '''\t\t_configure_collision_service()
\t\t_configure_runtime_protection()
\t\trequest_preview_rebuild()''',
    '''\t\t_configure_collision_service()
\t\tif _generation_result != null:
\t\t\t_configure_foliage_streamer()
\t\t_configure_runtime_protection()
\t\trequest_preview_rebuild()''',
    "profile foliage reconfigure",
)
text = once(
    text,
    '''func _set_collision_enabled(value: bool) -> void:
\tcollision_enabled = value
\tif _collision_service != null:
\t\t_collision_service.set_enabled(collision_enabled)


func _set_rebuild_preview_requested''',
    '''func _set_collision_enabled(value: bool) -> void:
\tcollision_enabled = value
\tif _collision_service != null:
\t\t_collision_service.set_enabled(collision_enabled)


func _set_foliage_enabled(value: bool) -> void:
\tfoliage_enabled = value
\tif _foliage_streamer != null:
\t\t_foliage_streamer.set_enabled(foliage_enabled and _generation_result != null)


func _set_rebuild_preview_requested''',
    "foliage enabled setter",
)
path.write_text(text)
