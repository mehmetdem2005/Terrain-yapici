@tool
extends Node3D
class_name IslandTerrainBrushPreview

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")

const RING_SEGMENTS: int = 64
const HEIGHT_OFFSET_M: float = 0.30

var _terrain: TerrainNode
var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _last_center: Vector3 = Vector3.INF
var _last_radius: float = -1.0
var _last_falloff: float = -1.0
var _last_color: Color = Color.TRANSPARENT
var _active: bool = false


func _ready() -> void:
	name = "__IslandTerrainBrushPreview"
	top_level = true
	_ensure_renderer()
	hide_preview()


func set_terrain(terrain: TerrainNode) -> void:
	_terrain = terrain
	_last_center = Vector3.INF
	hide_preview()


func show_brush(
	center_world: Vector3,
	radius_m: float,
	falloff_exponent: float,
	color: Color,
	active: bool = false
) -> void:
	if not is_instance_valid(_terrain) or not _terrain.is_initialized():
		hide_preview()
		return
	_ensure_renderer()
	var safe_radius: float = clampf(radius_m, 0.5, 256.0)
	var safe_falloff: float = clampf(falloff_exponent, 0.25, 8.0)
	var needs_rebuild: bool = not center_world.is_equal_approx(_last_center) \
		or not is_equal_approx(safe_radius, _last_radius) \
		or not is_equal_approx(safe_falloff, _last_falloff) \
		or not color.is_equal_approx(_last_color) \
		or active != _active
	if not needs_rebuild:
		_mesh_instance.visible = true
		return
	_last_center = center_world
	_last_radius = safe_radius
	_last_falloff = safe_falloff
	_last_color = color
	_active = active
	_rebuild_mesh(center_world, safe_radius, safe_falloff, color, active)
	_mesh_instance.visible = true


func hide_preview() -> void:
	if is_instance_valid(_mesh_instance):
		_mesh_instance.visible = false


func has_geometry() -> bool:
	return is_instance_valid(_mesh_instance) \
		and _mesh_instance.mesh != null \
		and _mesh_instance.mesh.get_surface_count() > 0


func _ensure_renderer() -> void:
	if is_instance_valid(_mesh_instance):
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.render_priority = 120

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "BrushPreviewMesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mesh_instance.extra_cull_margin = 1024.0
	add_child(_mesh_instance, false, Node.INTERNAL_MODE_BACK)


func _rebuild_mesh(
	center_world: Vector3,
	radius_m: float,
	falloff_exponent: float,
	color: Color,
	active: bool
) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	var outer_color := color
	outer_color.a = 1.0 if active else 0.88
	_append_ring(mesh, center_world, radius_m, outer_color)

	var falloff_ratio: float = pow(0.5, 1.0 / maxf(falloff_exponent, 0.25))
	var inner_color := Color(color.r, color.g, color.b, 0.40 if active else 0.28)
	_append_ring(mesh, center_world, radius_m * falloff_ratio, inner_color)

	var cross_size: float = minf(radius_m * 0.28, 12.0)
	var cross_color := Color(1.0, 1.0, 1.0, 0.72)
	_append_surface_line(
		mesh,
		center_world + Vector3(-cross_size, 0.0, 0.0),
		center_world + Vector3(cross_size, 0.0, 0.0),
		cross_color
	)
	_append_surface_line(
		mesh,
		center_world + Vector3(0.0, 0.0, -cross_size),
		center_world + Vector3(0.0, 0.0, cross_size),
		cross_color
	)
	mesh.surface_end()
	_mesh_instance.mesh = mesh


func _append_ring(mesh: ImmediateMesh, center_world: Vector3, radius_m: float, color: Color) -> void:
	for segment in range(RING_SEGMENTS):
		var next_segment: int = (segment + 1) % RING_SEGMENTS
		var angle_a: float = TAU * float(segment) / float(RING_SEGMENTS)
		var angle_b: float = TAU * float(next_segment) / float(RING_SEGMENTS)
		var point_a := center_world + Vector3(cos(angle_a) * radius_m, 0.0, sin(angle_a) * radius_m)
		var point_b := center_world + Vector3(cos(angle_b) * radius_m, 0.0, sin(angle_b) * radius_m)
		_append_surface_line(mesh, point_a, point_b, color)


func _append_surface_line(mesh: ImmediateMesh, a: Vector3, b: Vector3, color: Color) -> void:
	var surface_a := a
	var surface_b := b
	surface_a.y = _terrain.get_height_at_world(surface_a) + HEIGHT_OFFSET_M
	surface_b.y = _terrain.get_height_at_world(surface_b) + HEIGHT_OFFSET_M
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(surface_a)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(surface_b)
