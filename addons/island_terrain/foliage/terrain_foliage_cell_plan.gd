@tool
extends RefCounted
class_name IslandTerrainFoliageCellPlan

var cell_coord: Vector2i = Vector2i.ZERO
var positions: PackedVector3Array = PackedVector3Array()
var normals: PackedVector3Array = PackedVector3Array()
var yaw_radians: PackedFloat32Array = PackedFloat32Array()
var uniform_scales: PackedFloat32Array = PackedFloat32Array()
var layer_indices: PackedInt32Array = PackedInt32Array()


func initialize(coord: Vector2i) -> void:
	cell_coord = coord
	positions = PackedVector3Array()
	normals = PackedVector3Array()
	yaw_radians = PackedFloat32Array()
	uniform_scales = PackedFloat32Array()
	layer_indices = PackedInt32Array()


func append_instance(
	layer_index: int,
	position: Vector3,
	normal: Vector3,
	yaw: float,
	uniform_scale: float
) -> void:
	layer_indices.append(layer_index)
	positions.append(position)
	normals.append(normal.normalized() if not normal.is_zero_approx() else Vector3.UP)
	yaw_radians.append(yaw)
	uniform_scales.append(uniform_scale)


func instance_count() -> int:
	return positions.size()


func count_for_layer(layer_index: int) -> int:
	var count: int = 0
	for value in layer_indices:
		if value == layer_index:
			count += 1
	return count


func validate(layer_count: int) -> PackedStringArray:
	var errors := PackedStringArray()
	var count: int = positions.size()
	if normals.size() != count:
		errors.append("normals size mismatch")
	if yaw_radians.size() != count:
		errors.append("yaw_radians size mismatch")
	if uniform_scales.size() != count:
		errors.append("uniform_scales size mismatch")
	if layer_indices.size() != count:
		errors.append("layer_indices size mismatch")
	for layer_index in layer_indices:
		if layer_index < 0 or layer_index >= layer_count:
			errors.append("layer index out of range")
			break
	return errors


func estimated_memory_bytes() -> int:
	# Two Vector3 arrays, two float arrays and one int array.
	return positions.size() * 36
