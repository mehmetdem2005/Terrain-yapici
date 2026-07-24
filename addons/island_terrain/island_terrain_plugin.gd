@tool
extends EditorPlugin

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")


func _enter_tree() -> void:
	add_custom_type("IslandTerrain3D", "Node3D", TerrainNode, null)
	call_deferred("_validate_project_renderer")


func _exit_tree() -> void:
	remove_custom_type("IslandTerrain3D")


func _validate_project_renderer() -> void:
	var rendering_method: String = str(
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "mobile")
	)
	if rendering_method != "mobile":
		push_warning(
			"IT-W04: IslandTerrain is tuned for Godot Mobile Renderer; current rendering method is '%s'" \
			% rendering_method
		)
