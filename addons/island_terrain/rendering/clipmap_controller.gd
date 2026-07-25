@tool
extends Node3D
class_name IslandTerrainClipmapController

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const MeshBuilder = preload("res://addons/island_terrain/rendering/clipmap_mesh_builder.gd")

var _manifest: Manifest
var _budget: Budget
var _source_material: ShaderMaterial
var _height_texture: Texture2D
var _camera: Camera3D
var _pending_levels: Array[int] = []
var _level_instances: Array[MeshInstance3D] = []
var _configured: bool = false
var _last_terrain_origin_xz := Vector2(1.0e30, 1.0e30)
var _last_shared_snap_position := Vector3(1.0e30, 0.0, 1.0e30)


func _ready() -> void:
	set_process(true)


func configure(
	manifest: Manifest,
	budget: Budget,
	material: ShaderMaterial,
	height_texture: Texture2D
) -> void:
	_manifest = manifest
	_budget = budget
	_source_material = material
	_height_texture = height_texture
	_budget.sanitize(Engine.is_editor_hint())
	_apply_shared_material_parameters()
	rebuild_deferred()


func set_tracking_camera(camera: Camera3D) -> void:
	_camera = camera


func set_height_texture(texture: Texture2D) -> void:
	_height_texture = texture
	if _source_material != null:
		_source_material.set_shader_parameter("height_texture", _height_texture)


func set_shadow_lod_count(value: int) -> void:
	if _budget == null:
		return
	_budget.shadow_lod_count = clampi(value, 0, _budget.clipmap_levels)
	for level in range(_level_instances.size()):
		var instance: MeshInstance3D = _level_instances[level]
		if not is_instance_valid(instance):
			continue
		instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if level < _budget.shadow_lod_count
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)


func get_shadow_lod_count() -> int:
	return _budget.shadow_lod_count if _budget != null else 0


func active_level_count() -> int:
	var count: int = 0
	for instance in _level_instances:
		if is_instance_valid(instance):
			count += 1
	return count


func pending_level_count() -> int:
	return _pending_levels.size()


func rebuild_deferred() -> void:
	_clear_levels()
	_pending_levels.clear()
	_last_shared_snap_position = Vector3(1.0e30, 0.0, 1.0e30)
	if _manifest == null or _budget == null or _source_material == null or _height_texture == null:
		_configured = false
		return
	for level in range(_budget.clipmap_levels):
		_pending_levels.append(level)
	_level_instances.resize(_budget.clipmap_levels)
	_configured = true


func _process(_delta: float) -> void:
	if not _configured:
		return
	_update_terrain_origin_parameter()
	_build_within_frame_budget()
	_update_camera_snapping()


func _build_within_frame_budget() -> void:
	if _pending_levels.is_empty():
		return
	var start_usec: int = Time.get_ticks_usec()
	var budget_usec: int = maxi(250, int(_budget.frame_work_budget_ms * 1000.0))
	var built_this_frame: int = 0
	while not _pending_levels.is_empty():
		var level: int = _pending_levels.pop_front()
		_build_level(level)
		built_this_frame += 1
		if built_this_frame >= 1 or Time.get_ticks_usec() - start_usec >= budget_usec:
			break


func _build_level(level: int) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "ClipmapLOD%d" % level
	var is_outermost: bool = level == _budget.clipmap_levels - 1
	instance.mesh = MeshBuilder.build_level(_budget.base_quads, level, is_outermost)
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if level < _budget.shadow_lod_count
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.extra_cull_margin = float(_manifest.max_height_m) + 32.0
	instance.material_override = _source_material
	instance.set_instance_shader_parameter(&"lod_level", float(level))
	instance.set_instance_shader_parameter(
		&"skirt_depth_m",
		maxf(4.0, float(1 << level) * 2.0) if is_outermost else 0.0
	)
	instance.position = _last_shared_snap_position \
		if _last_shared_snap_position.x < 1.0e20 \
		else Vector3.ZERO
	add_child(instance)
	_level_instances[level] = instance


func _apply_shared_material_parameters() -> void:
	if _source_material == null or _manifest == null:
		return
	_source_material.set_shader_parameter("height_texture", _height_texture)
	_source_material.set_shader_parameter("world_size_m", float(_manifest.world_size_m))
	_source_material.set_shader_parameter("max_height_m", _manifest.max_height_m)
	_source_material.set_shader_parameter("sea_level_m", _manifest.sea_level_m)
	_last_terrain_origin_xz = Vector2(global_position.x, global_position.z)
	_source_material.set_shader_parameter("terrain_origin_world_xz", _last_terrain_origin_xz)


func _update_terrain_origin_parameter() -> void:
	if _source_material == null:
		return
	var current_origin := Vector2(global_position.x, global_position.z)
	if current_origin.is_equal_approx(_last_terrain_origin_xz):
		return
	_last_terrain_origin_xz = current_origin
	_source_material.set_shader_parameter("terrain_origin_world_xz", current_origin)


func _update_camera_snapping() -> void:
	var camera: Camera3D = _camera
	if not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	if not is_instance_valid(camera) or _budget == null:
		return
	var camera_local: Vector3 = to_local(camera.global_position)
	var shared_snap: Vector3 = compute_shared_snap(camera_local, _budget.clipmap_levels)
	if shared_snap.is_equal_approx(_last_shared_snap_position):
		return
	_last_shared_snap_position = shared_snap
	for instance in _level_instances:
		if is_instance_valid(instance):
			instance.position = shared_snap


static func compute_shared_snap(camera_local: Vector3, clipmap_levels: int) -> Vector3:
	# Every ring must share a centre aligned to the coarsest grid. Snapping all
	# levels to arbitrary one-metre coordinates misaligns coarse vertices and
	# produces cracks/overlaps while orbiting in the editor.
	var safe_levels: int = maxi(1, clipmap_levels)
	var coarsest_spacing: float = float(1 << (safe_levels - 1))
	return Vector3(
		roundf(camera_local.x / coarsest_spacing) * coarsest_spacing,
		0.0,
		roundf(camera_local.z / coarsest_spacing) * coarsest_spacing
	)


func _clear_levels() -> void:
	for instance in _level_instances:
		if is_instance_valid(instance):
			instance.queue_free()
	_level_instances.clear()