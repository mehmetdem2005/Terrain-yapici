@tool
extends RefCounted
class_name IslandTerrainSculptCommand

enum Tool {
	RAISE,
	LOWER,
	SMOOTH,
	FLATTEN,
	NOISE,
	TERRACE,
}

var tool: int = Tool.RAISE
var center_world: Vector3 = Vector3.ZERO
var radius_m: float = 8.0
var strength: float = 0.5
var falloff_exponent: float = 2.0
var target_height_m: float = 0.0
var noise_scale_m: float = 24.0
var terrace_step_m: float = 4.0
var random_seed: int = 1


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if tool < Tool.RAISE or tool > Tool.TERRACE:
		errors.append("invalid sculpt tool")
	if radius_m <= 0.0 or radius_m > 256.0:
		errors.append("radius_m must be within (0, 256]")
	if strength < 0.0 or strength > 64.0:
		errors.append("strength must be within [0, 64]")
	if falloff_exponent <= 0.0 or falloff_exponent > 8.0:
		errors.append("falloff_exponent must be within (0, 8]")
	if noise_scale_m < 0.5 or noise_scale_m > 512.0:
		errors.append("noise_scale_m must be within [0.5, 512]")
	if terrace_step_m < 0.25 or terrace_step_m > 256.0:
		errors.append("terrace_step_m must be within [0.25, 256]")
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
		Tool.NOISE:
			return "Terrain Noise"
		Tool.TERRACE:
			return "Terrain Terrace"
	return "Terrain Sculpt"
