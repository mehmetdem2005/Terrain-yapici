@tool
extends Node3D
class_name IslandTerrainFoliageCellRuntime

const Library = preload("res://addons/island_terrain/foliage/terrain_foliage_library.gd")
const Layer = preload("res://addons/island_terrain/foliage/terrain_foliage_layer.gd")
const CellPlan = preload("res://addons/island_terrain/foliage/terrain_foliage_cell_plan.gd")

var cell_coord: Vector2i = Vector2i.ZERO
var _layer_nodes: Array[MultiMeshInstance3D] = []
var _visible_instances: int = 0


func populate(
	plan: CellPlan,
	library: Library,
	world_to_local: Callable
) -> Error:
	if plan == null or library == null or not world_to_local.is_valid():
		return ERR_INVALID_PARAMETER
	var errors: PackedStringArray = plan.validate(library.layers.size())
	if not errors.is_empty():
		return ERR_INVALID_DATA
	cell_coord = plan.cell_coord
	_ensure_layer_nodes(library.layers.size())
	var counts := PackedInt32Array()
	counts.resize(library.layers.size())
	counts.fill(0)
	for layer_index in plan.layer_indices:
		counts[layer_index] += 1

	for layer_index in range(library.layers.size()):
		var layer: Layer = library.layers[layer_index]
		var instance_node: MultiMeshInstance3D = _layer_nodes[layer_index]
		var count: int = counts[layer_index]
		if layer.mesh == null or count <= 0:
			instance_node.visible = false
			if instance_node.multimesh != null:
				instance_node.multimesh.visible_instance_count = 0
			continue
		var multimesh: MultiMesh = instance_node.multimesh
		if multimesh == null:
			multimesh = MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_colors = false
			multimesh.use_custom_data = false
			instance_node.multimesh = multimesh
		multimesh.instance_count = 0
		multimesh.mesh = layer.mesh
		multimesh.instance_count = count
		multimesh.visible_instance_count = count
		instance_node.cast_shadow = layer.cast_shadow
		instance_node.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		instance_node.visibility_range_end = library.active_radius_m + float(library.cell_size_m)
		instance_node.extra_cull_margin = float(library.cell_size_m) * 0.25
		instance_node.visible = true

	var write_indices := PackedInt32Array()
	write_indices.resize(library.layers.size())
	write_indices.fill(0)
	for index in range(plan.instance_count()):
		var layer_index: int = plan.layer_indices[index]
		var layer: Layer = library.layers[layer_index]
		if layer.mesh == null:
			continue
		var local_position: Vector3 = world_to_local.call(plan.positions[index])
		var normal: Vector3 = plan.normals[index]
		var alignment := Quaternion.IDENTITY.slerp(
			Quaternion(Vector3.UP, normal),
			layer.align_to_normal
		)
		var basis := Basis(alignment) * Basis(Vector3.UP, plan.yaw_radians[index])
		basis = basis.scaled(Vector3.ONE * plan.uniform_scales[index])
		var transform := Transform3D(basis, local_position)
		_layer_nodes[layer_index].multimesh.set_instance_transform(
			write_indices[layer_index],
			transform
		)
		write_indices[layer_index] += 1
	_visible_instances = plan.instance_count()
	visible = true
	return OK


func clear_for_pool(release_multimeshes: bool = false) -> void:
	visible = false
	_visible_instances = 0
	for instance_node in _layer_nodes:
		instance_node.visible = false
		if instance_node.multimesh != null:
			if release_multimeshes:
				instance_node.multimesh = null
			else:
				instance_node.multimesh.visible_instance_count = 0


func visible_instance_count() -> int:
	return _visible_instances


func allocated_layer_count() -> int:
	var count: int = 0
	for instance_node in _layer_nodes:
		if instance_node.multimesh != null:
			count += 1
	return count


func estimated_transform_memory_bytes() -> int:
	# MultiMesh 3D transform is 12 floats. This excludes mesh resources shared by layers.
	return _visible_instances * 48


func _ensure_layer_nodes(layer_count: int) -> void:
	while _layer_nodes.size() < layer_count:
		var node := MultiMeshInstance3D.new()
		node.name = "Layer_%d" % _layer_nodes.size()
		node.visible = false
		add_child(node)
		_layer_nodes.append(node)
