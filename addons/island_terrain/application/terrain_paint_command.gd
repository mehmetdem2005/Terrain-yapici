@tool
extends RefCounted
class_name IslandTerrainPaintCommand

enum Tool {
	BIOME,
	MATERIAL,
	ERASE_BIOME,
	ERASE_MATERIAL,
	ERASE_ALL,
}

var tool: int = Tool.BIOME
var center_world: Vector3 = Vector3.ZERO
var radius_m: float = 8.0
var strength: float = 0.65
var falloff_exponent: float = 2.0
var biome_id: int = 2
var material_id: int = 1


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if tool < Tool.BIOME or tool > Tool.ERASE_ALL:
		errors.append("unknown paint tool")
	if radius_m <= 0.0 or radius_m > 256.0:
		errors.append("radius_m must be within (0, 256]")
	if strength <= 0.0 or strength > 1.0:
		errors.append("strength must be within (0, 1]")
	if falloff_exponent < 0.25 or falloff_exponent > 8.0:
		errors.append("falloff_exponent must be within [0.25, 8]")
	if biome_id < 0 or biome_id > 7:
		errors.append("biome_id must be within [0, 7]")
	if material_id < 0 or material_id > 5:
		errors.append("material_id must be within [0, 5]")
	return errors


func weight_for_distance(distance_m: float) -> float:
	if distance_m >= radius_m:
		return 0.0
	var normalized: float = clampf(distance_m / maxf(radius_m, 0.001), 0.0, 1.0)
	return pow(1.0 - normalized, falloff_exponent)


func label() -> String:
	match tool:
		Tool.BIOME:
			return "Paint Terrain Biome"
		Tool.MATERIAL:
			return "Paint Terrain Material"
		Tool.ERASE_BIOME:
			return "Restore Procedural Biome"
		Tool.ERASE_MATERIAL:
			return "Restore Procedural Material"
		Tool.ERASE_ALL:
			return "Restore Procedural Terrain Metadata"
	return "Terrain Paint"
