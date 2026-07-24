@tool
extends RefCounted
class_name IslandTerrainDeformationBackend

# Stable contract for the later voxel/SDF phase. The heightfield renderer never
# depends on a concrete volumetric implementation; a native GDExtension backend
# can replace this class without changing terrain/editor callers.

func is_available() -> bool:
	return false


func apply_sphere(_center_world: Vector3, _radius_m: float, _strength: float) -> Error:
	return ERR_UNAVAILABLE


func apply_capsule(_from_world: Vector3, _to_world: Vector3, _radius_m: float, _strength: float) -> Error:
	return ERR_UNAVAILABLE


func apply_box(_transform_world: Transform3D, _extents_m: Vector3, _strength: float) -> Error:
	return ERR_UNAVAILABLE


func subtract_volume(_shape: Dictionary) -> Error:
	return ERR_UNAVAILABLE


func add_volume(_shape: Dictionary) -> Error:
	return ERR_UNAVAILABLE


func query_density(_world_position: Vector3) -> float:
	return 1.0


func rebuild_mesh(_patch_coord: Vector3i) -> Error:
	return ERR_UNAVAILABLE


func rebuild_collision(_patch_coord: Vector3i) -> Error:
	return ERR_UNAVAILABLE


func serialize_delta(_patch_coord: Vector3i) -> PackedByteArray:
	return PackedByteArray()
