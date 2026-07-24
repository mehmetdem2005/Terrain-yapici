@tool
extends EditorPlugin

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const Toolbar = preload("res://addons/island_terrain/editor/terrain_sculpt_toolbar.gd")
const SculptSession = preload("res://addons/island_terrain/editor/terrain_sculpt_session.gd")

var _toolbar: Toolbar
var _session: SculptSession


func _enter_tree() -> void:
	add_custom_type("IslandTerrain3D", "Node3D", TerrainNode, null)
	_toolbar = Toolbar.new()
	_toolbar.visible = false
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, _toolbar)
	_session = SculptSession.new()
	_session.configure(_toolbar, get_undo_redo())
	_toolbar.undo_requested.connect(_session.undo)
	_toolbar.redo_requested.connect(_session.redo)
	call_deferred("_validate_project_renderer")


func _exit_tree() -> void:
	if _session != null:
		_session.finalize_stroke()
		_session.clear_terrain()
	_session = null
	if is_instance_valid(_toolbar):
		remove_control_from_docks(_toolbar)
		_toolbar.queue_free()
	_toolbar = null
	remove_custom_type("IslandTerrain3D")


func _handles(object: Object) -> bool:
	return object is TerrainNode


func _edit(object: Object) -> void:
	if _session != null:
		_session.set_terrain(object as TerrainNode)


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_toolbar):
		_toolbar.visible = visible
	if not visible and _session != null:
		_session.clear_terrain()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	return _session.route_input(camera, event) \
		if _session != null \
		else EditorPlugin.AFTER_GUI_INPUT_PASS


func _validate_project_renderer() -> void:
	var rendering_method: String = str(
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "mobile")
	)
	if rendering_method != "mobile":
		push_warning(
			"IT-W04: IslandTerrain is tuned for Godot Mobile Renderer; current rendering method is '%s'" \
			% rendering_method
		)
