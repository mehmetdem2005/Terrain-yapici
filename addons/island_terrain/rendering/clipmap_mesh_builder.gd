@tool
extends RefCounted
class_name IslandTerrainClipmapMeshBuilder


static func build_level(base_quads: int, level: int, add_outer_skirt: bool = false) -> ArrayMesh:
	var quads: int = maxi(4, base_quads)
	var spacing: float = float(1 << level)
	var half: float = float(quads) * 0.5
	var inner_half: float = float(quads) * 0.25 if level > 0 else -1.0
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize((quads + 1) * (quads + 1))
	normals.resize(vertices.size())
	uvs.resize(vertices.size())
	colors.resize(vertices.size())
	for z in range(quads + 1):
		for x in range(quads + 1):
			var index: int = z * (quads + 1) + x
			vertices[index] = Vector3((float(x) - half) * spacing, 0.0, (float(z) - half) * spacing)
			normals[index] = Vector3.UP
			uvs[index] = Vector2(float(x) / float(quads), float(z) / float(quads))
			colors[index] = Color(0.0, 0.0, 0.0, 1.0)
	for z in range(quads):
		for x in range(quads):
			var cell_x: float = float(x) + 0.5 - half
			var cell_z: float = float(z) + 0.5 - half
			if level > 0 and absf(cell_x) < inner_half and absf(cell_z) < inner_half:
				continue
			var a: int = z * (quads + 1) + x
			var b: int = a + 1
			var c: int = a + quads + 1
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	# Only the outermost clipmap level may own a vertical skirt. Adding a skirt
	# to every ring creates the large green walls seen in the mobile editor.
	if add_outer_skirt:
		_append_outer_skirts(vertices, normals, uvs, colors, indices, quads, spacing, half)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.resource_name = "IslandClipmapLOD%d" % level
	return mesh


static func _append_outer_skirts(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	quads: int,
	spacing: float,
	half: float
) -> void:
	for i in range(quads):
		var p0: Vector3 = Vector3((float(i) - half) * spacing, 0.0, -half * spacing)
		var p1: Vector3 = Vector3((float(i + 1) - half) * spacing, 0.0, -half * spacing)
		_append_skirt_segment(vertices, normals, uvs, colors, indices, p0, p1)
		p0 = Vector3(half * spacing, 0.0, (float(i) - half) * spacing)
		p1 = Vector3(half * spacing, 0.0, (float(i + 1) - half) * spacing)
		_append_skirt_segment(vertices, normals, uvs, colors, indices, p0, p1)
		p0 = Vector3((half - float(i)) * spacing, 0.0, half * spacing)
		p1 = Vector3((half - float(i + 1)) * spacing, 0.0, half * spacing)
		_append_skirt_segment(vertices, normals, uvs, colors, indices, p0, p1)
		p0 = Vector3(-half * spacing, 0.0, (half - float(i)) * spacing)
		p1 = Vector3(-half * spacing, 0.0, (half - float(i + 1)) * spacing)
		_append_skirt_segment(vertices, normals, uvs, colors, indices, p0, p1)


static func _append_skirt_segment(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	p0: Vector3,
	p1: Vector3
) -> void:
	var base: int = vertices.size()
	vertices.append_array(PackedVector3Array([p0, p1, p0, p1]))
	normals.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]))
	uvs.append_array(PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2.ZERO, Vector2.ONE]))
	colors.append_array(PackedColorArray([
		Color(0.0, 0.0, 0.0, 1.0),
		Color(0.0, 0.0, 0.0, 1.0),
		Color(1.0, 0.0, 0.0, 1.0),
		Color(1.0, 0.0, 0.0, 1.0),
	]))
	indices.append_array(PackedInt32Array([
		base, base + 2, base + 1,
		base + 1, base + 2, base + 3,
	]))