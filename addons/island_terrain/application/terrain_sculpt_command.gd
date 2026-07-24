@tool
extends RefCounted
class_name IslandTerrainSculptCommand

enum Tool {
	RAISE,
	LOWER,
	SMOOTH,
	FLATTEN,
}

var tool: int = Tool.RAISE
var center_world: Vector3 = Vector3.ZERO
var radius_m: float = 8.0
var strength: float = 0.5
var falloff_exponent: float = 2.0
var target_height_m: float = 0.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if tool < Tool.RAISE or tool > Tool.FLATTEN:
		errors.append("invalid sculpt tool")
	if radius_m <= 0.0:
		errors.append("radius_m must be positive")
	if strength < 0.0:
		errors.append("strength must not be negative")
	if falloff_exponent <= 0.0:
		errors.append("falloff_exponent must be positive")
	return errors


func weight_for_distance(distance_m: float) -> float:
	if distance_m >= radius_m:
		return 0.0
	var normalized: float = 1.0 - clampf(distance_m / radius_m, 0.0, 1.0)
	return pow(normalized, falloff_exponent)


func label() -> String:
	match tool:
		Tool.RAISE:
			return "Terrain Raise"
		Tool.LOWER:
			return "Terrain Lower"
		Tool.SMOOTH:
			return "Terrain Smooth"
		Tool.FLATTEN:
			return "Terrain Flatten"
	return "Terrain Sculpt"
