@tool
extends "res://addons/island_terrain/island_terrain_3d.gd"
class_name IslandTerrainAuthoring3D


func _init() -> void:
	# Editor authoring starts from a predictable flat heightfield. Procedural
	# island generation is an explicit map-author action, not a node side effect.
	generate_preview_on_ready = false
	collision_enabled = false