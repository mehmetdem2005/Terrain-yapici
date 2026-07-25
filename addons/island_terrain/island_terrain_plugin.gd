@tool
extends EditorPlugin

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const AuthoringTerrainNode = preload("res://addons/island_terrain/editor/island_terrain_authoring_3d.gd")
const ToolsPanel = preload("res://addons/island_terrain/editor/terrain_tools_panel.gd")
const SculptToolbar = preload("res://addons/island_terrain/editor/terrain_sculpt_toolbar.gd")
const SculptSession = preload("res://addons/island_terrain/editor/terrain_sculpt_session.gd")
const PaintToolbar = preload("res://addons/island_terrain/editor/terrain_paint_toolbar.gd")
const PaintSession = preload("res://addons/island_terrain/editor/terrain_paint_session.gd")

var _tools_panel: ToolsPanel
var _sculpt_toolbar: SculptToolbar
var _sculpt_session: SculptSession
var _paint_toolbar: PaintToolbar
var _paint_session: PaintSession
var _selected_terrain: TerrainNode


func _enter_tree() -> void:
	# The custom editor node starts flat. Runtime projects may still instantiate
	# the core IslandTerrain3D script directly and opt into generation.
	add_custom_type("IslandTerrain3D", "Node3D", AuthoringTerrainNode, null)

	_tools_panel = ToolsPanel.new()
	_sculpt_toolbar = SculptToolbar.new()
	_paint_toolbar = PaintToolbar.new()
	_tools_panel.configure(_sculpt_toolbar, _paint_toolbar)
	_tools_panel.generate_island_requested.connect(_on_generate_island_requested)
	add_control_to_bottom_panel(_tools_panel, "IslandTerrain")

	_sculpt_session = SculptSession.new()
	_sculpt_session.configure(_sculpt_toolbar, get_undo_redo())
	_sculpt_toolbar.undo_requested.connect(_sculpt_session.undo)
	_sculpt_toolbar.redo_requested.connect(_sculpt_session.redo)
	_sculpt_toolbar.sculpt_mode_changed.connect(_on_sculpt_mode_changed)

	_paint_session = PaintSession.new()
	_paint_session.configure(_paint_toolbar, get_undo_redo())
	_paint_toolbar.undo_requested.connect(_paint_session.undo)
	_paint_toolbar.redo_requested.connect(_paint_session.redo)
	_paint_toolbar.paint_mode_changed.connect(_on_paint_mode_changed)
	call_deferred("_validate_project_renderer")


func _exit_tree() -> void:
	_selected_terrain = null
	if _paint_session != null:
		_paint_session.finalize_stroke()
		_paint_session.clear_terrain()
	_paint_session = null

	if _sculpt_session != null:
		_sculpt_session.finalize_stroke()
		_sculpt_session.clear_terrain()
	_sculpt_session = null

	if is_instance_valid(_tools_panel):
		remove_control_from_bottom_panel(_tools_panel)
		_tools_panel.queue_free()
	_tools_panel = null
	_sculpt_toolbar = null
	_paint_toolbar = null
	remove_custom_type("IslandTerrain3D")


func _handles(object: Object) -> bool:
	return object is TerrainNode


func _edit(object: Object) -> void:
	var terrain := object as TerrainNode
	_selected_terrain = terrain
	if _sculpt_session != null:
		_sculpt_session.set_terrain(terrain)
	if _paint_session != null:
		_paint_session.set_terrain(terrain)
	if terrain != null and is_instance_valid(_tools_panel):
		_tools_panel.set_terrain(terrain.name)
		make_bottom_panel_item_visible(_tools_panel)


func _make_visible(visible: bool) -> void:
	if visible and is_instance_valid(_tools_panel):
		make_bottom_panel_item_visible(_tools_panel)
	if not visible:
		_selected_terrain = null
		if _sculpt_session != null:
			_sculpt_session.clear_terrain()
		if _paint_session != null:
			_paint_session.clear_terrain()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _paint_session != null:
		var paint_result: int = _paint_session.route_input(camera, event)
		if paint_result == EditorPlugin.AFTER_GUI_INPUT_STOP:
			return paint_result
	return _sculpt_session.route_input(camera, event) \
		if _sculpt_session != null \
		else EditorPlugin.AFTER_GUI_INPUT_PASS


func _on_generate_island_requested() -> void:
	if not is_instance_valid(_selected_terrain):
		if is_instance_valid(_tools_panel):
			_tools_panel.set_message("Önce IslandTerrain3D node'unu seç.")
		return
	_selected_terrain.request_preview_rebuild()
	if is_instance_valid(_tools_panel):
		_tools_panel.set_message("Prosedürel ada üretimi başlatıldı…")


func _on_sculpt_mode_changed(enabled: bool) -> void:
	if enabled and is_instance_valid(_paint_toolbar):
		_paint_toolbar.disable_paint()
	if enabled and _paint_session != null:
		_paint_session.finalize_stroke()
	if enabled and is_instance_valid(_tools_panel):
		_tools_panel.select_sculpt_tab()


func _on_paint_mode_changed(enabled: bool) -> void:
	if enabled and is_instance_valid(_sculpt_toolbar):
		_sculpt_toolbar.disable_sculpt()
	if enabled and _sculpt_session != null:
		_sculpt_session.finalize_stroke()
	if enabled and is_instance_valid(_tools_panel):
		_tools_panel.select_paint_tab()


func _validate_project_renderer() -> void:
	var rendering_method: String = str(
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "mobile")
	)
	if rendering_method != "mobile":
		push_warning(
			"IT-W04: IslandTerrain is tuned for Godot Mobile Renderer; current rendering method is '%s'" \
			% rendering_method
		)