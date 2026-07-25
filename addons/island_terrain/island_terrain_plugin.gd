@tool
extends EditorPlugin

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const AuthoringTerrainNode = preload("res://addons/island_terrain/editor/island_terrain_authoring_3d.gd")
const ToolsPanel = preload("res://addons/island_terrain/editor/terrain_tools_panel.gd")
const SculptToolbar = preload("res://addons/island_terrain/editor/terrain_sculpt_toolbar.gd")
const SculptSession = preload("res://addons/island_terrain/editor/terrain_sculpt_session.gd")
const PaintToolbar = preload("res://addons/island_terrain/editor/terrain_paint_toolbar.gd")
const PaintSession = preload("res://addons/island_terrain/editor/terrain_paint_session.gd")
const BrushPreview = preload("res://addons/island_terrain/editor/terrain_brush_preview.gd")

var _tools_panel: ToolsPanel
var _sculpt_toolbar: SculptToolbar
var _sculpt_session: SculptSession
var _paint_toolbar: PaintToolbar
var _paint_session: PaintSession
var _brush_preview: BrushPreview
var _selected_terrain: TerrainNode
var _metrics_elapsed: float = 0.0


func _enter_tree() -> void:
	add_custom_type("IslandTerrain3D", "Node3D", AuthoringTerrainNode, null)

	_tools_panel = ToolsPanel.new()
	_sculpt_toolbar = SculptToolbar.new()
	_paint_toolbar = PaintToolbar.new()
	_tools_panel.configure(_sculpt_toolbar, _paint_toolbar)
	_tools_panel.generate_island_requested.connect(_on_generate_island_requested)
	_tools_panel.diagnostics_refresh_requested.connect(_refresh_metrics)
	add_control_to_bottom_panel(_tools_panel, "IslandTerrain")

	_brush_preview = BrushPreview.new()
	_sculpt_session = SculptSession.new()
	_sculpt_session.configure(_sculpt_toolbar, get_undo_redo(), _brush_preview)
	_sculpt_toolbar.undo_requested.connect(_sculpt_session.undo)
	_sculpt_toolbar.redo_requested.connect(_sculpt_session.redo)
	_sculpt_toolbar.sculpt_mode_changed.connect(_on_sculpt_mode_changed)

	_paint_session = PaintSession.new()
	_paint_session.configure(_paint_toolbar, get_undo_redo(), _brush_preview)
	_paint_toolbar.undo_requested.connect(_paint_session.undo)
	_paint_toolbar.redo_requested.connect(_paint_session.redo)
	_paint_toolbar.paint_mode_changed.connect(_on_paint_mode_changed)
	set_process(true)
	call_deferred("_validate_project_renderer")


func _exit_tree() -> void:
	_disconnect_selected_terrain()
	_selected_terrain = null
	if _paint_session != null:
		_paint_session.finalize_stroke()
		_paint_session.clear_terrain()
	_paint_session = null

	if _sculpt_session != null:
		_sculpt_session.finalize_stroke()
		_sculpt_session.clear_terrain()
	_sculpt_session = null

	if is_instance_valid(_brush_preview):
		_brush_preview.queue_free()
	_brush_preview = null

	if is_instance_valid(_tools_panel):
		remove_control_from_bottom_panel(_tools_panel)
		_tools_panel.queue_free()
	_tools_panel = null
	_sculpt_toolbar = null
	_paint_toolbar = null
	remove_custom_type("IslandTerrain3D")


func _process(delta: float) -> void:
	_metrics_elapsed += delta
	if _metrics_elapsed < 0.50:
		return
	_metrics_elapsed = 0.0
	_refresh_metrics()


func _handles(object: Object) -> bool:
	return object is TerrainNode


func _edit(object: Object) -> void:
	var terrain := object as TerrainNode
	if terrain == _selected_terrain:
		_refresh_metrics()
		return
	_disconnect_selected_terrain()
	_selected_terrain = terrain
	if _sculpt_session != null:
		_sculpt_session.set_terrain(terrain)
	if _paint_session != null:
		_paint_session.set_terrain(terrain)
	_attach_brush_preview(terrain)
	_connect_selected_terrain()
	if terrain != null and is_instance_valid(_tools_panel):
		_tools_panel.set_terrain(terrain.name, _collect_metrics())
		make_bottom_panel_item_visible(_tools_panel)


func _make_visible(visible: bool) -> void:
	if visible and is_instance_valid(_tools_panel):
		make_bottom_panel_item_visible(_tools_panel)
	if not visible:
		_disconnect_selected_terrain()
		_selected_terrain = null
		if _sculpt_session != null:
			_sculpt_session.clear_terrain()
		if _paint_session != null:
			_paint_session.clear_terrain()
		if is_instance_valid(_brush_preview):
			_brush_preview.hide_preview()
		if is_instance_valid(_tools_panel):
			_tools_panel.clear_terrain()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _paint_session != null:
		var paint_result: int = _paint_session.route_input(camera, event)
		if paint_result == EditorPlugin.AFTER_GUI_INPUT_STOP:
			return paint_result
	return _sculpt_session.route_input(camera, event) \
		if _sculpt_session != null \
		else EditorPlugin.AFTER_GUI_INPUT_PASS


func _on_generate_island_requested(settings: Dictionary) -> void:
	if not is_instance_valid(_selected_terrain):
		if is_instance_valid(_tools_panel):
			_tools_panel.set_message("Önce IslandTerrain3D node'unu seç", true)
		return
	if _selected_terrain.is_generation_running():
		_tools_panel.set_message("Generation zaten çalışıyor", true)
		return
	if _selected_terrain.manifest == null or _selected_terrain.generation_profile == null:
		_tools_panel.set_message("Terrain henüz hazırlanıyor; bir saniye sonra tekrar dene", true)
		return

	_selected_terrain.manifest.world_seed = int(settings.get("seed", 1))
	_selected_terrain.manifest.max_height_m = float(settings.get("max_height_m", 512.0))
	_selected_terrain.generation_profile.thermal_iterations = int(settings.get("thermal_iterations", 2))
	_selected_terrain.generation_profile.rivers_enabled = bool(settings.get("rivers_enabled", true))
	_apply_generation_preset(int(settings.get("preset", 0)))
	_selected_terrain.generation_profile.sanitize()
	_selected_terrain.request_preview_rebuild()
	if is_instance_valid(_tools_panel):
		_tools_panel.select_map_tab()
		_tools_panel.set_generation_progress(0.01, "Generation kuyruğa alındı")


func _apply_generation_preset(preset: int) -> void:
	var profile = _selected_terrain.generation_profile
	match preset:
		1:
			profile.coast_falloff_start = 0.62
			profile.coast_warp_strength = 0.18
			profile.base_elevation = 0.10
			profile.broad_elevation_weight = 0.62
			profile.ridge_weight = 0.56
			profile.height_exponent = 1.42
			profile.output_height_scale = 0.94
			profile.thermal_transfer_rate = 0.25
			profile.river_depth_m = 11.0
		2:
			profile.coast_falloff_start = 0.44
			profile.coast_falloff_end = 1.10
			profile.coast_warp_strength = 0.34
			profile.base_elevation = 0.08
			profile.broad_elevation_weight = 0.48
			profile.ridge_weight = 0.25
			profile.height_exponent = 1.18
			profile.output_height_scale = 0.68
			profile.river_depth_m = 5.0
		3:
			profile.coast_falloff_start = 0.60
			profile.coast_warp_strength = 0.10
			profile.base_elevation = 0.18
			profile.broad_elevation_weight = 0.42
			profile.ridge_weight = 0.10
			profile.height_exponent = 1.08
			profile.output_height_scale = 0.46
			profile.thermal_transfer_rate = 0.30
			profile.river_depth_m = 4.0
		_:
			profile.coast_falloff_start = 0.58
			profile.coast_falloff_end = 1.00
			profile.coast_warp_strength = 0.16
			profile.base_elevation = 0.12
			profile.broad_elevation_weight = 0.58
			profile.ridge_weight = 0.30
			profile.height_exponent = 1.28
			profile.output_height_scale = 0.72
			profile.thermal_transfer_rate = 0.22
			profile.river_depth_m = 8.0


func _on_sculpt_mode_changed(enabled: bool) -> void:
	if enabled and is_instance_valid(_paint_toolbar):
		_paint_toolbar.disable_paint()
	if enabled and _paint_session != null:
		_paint_session.finalize_stroke()
	if is_instance_valid(_brush_preview):
		_brush_preview.hide_preview()
	if enabled and is_instance_valid(_tools_panel):
		_tools_panel.select_sculpt_tab()


func _on_paint_mode_changed(enabled: bool) -> void:
	if enabled and is_instance_valid(_sculpt_toolbar):
		_sculpt_toolbar.disable_sculpt()
	if enabled and _sculpt_session != null:
		_sculpt_session.finalize_stroke()
	if is_instance_valid(_brush_preview):
		_brush_preview.hide_preview()
	if enabled and is_instance_valid(_tools_panel):
		_tools_panel.select_paint_tab()


func _attach_brush_preview(terrain: TerrainNode) -> void:
	if not is_instance_valid(_brush_preview):
		return
	var current_parent: Node = _brush_preview.get_parent()
	if current_parent != null and current_parent != terrain:
		current_parent.remove_child(_brush_preview)
	if terrain != null and _brush_preview.get_parent() == null:
		terrain.add_child(_brush_preview, false, Node.INTERNAL_MODE_BACK)
	_brush_preview.set_terrain(terrain)


func _connect_selected_terrain() -> void:
	if not is_instance_valid(_selected_terrain):
		return
	var progress_callback := Callable(self, "_on_generation_progress")
	var stage_callback := Callable(self, "_on_generation_stage_changed")
	var completed_callback := Callable(self, "_on_generation_completed")
	var failed_callback := Callable(self, "_on_generation_failed")
	if not _selected_terrain.preview_generation_progress.is_connected(progress_callback):
		_selected_terrain.preview_generation_progress.connect(progress_callback)
	if not _selected_terrain.preview_generation_stage_changed.is_connected(stage_callback):
		_selected_terrain.preview_generation_stage_changed.connect(stage_callback)
	if not _selected_terrain.preview_generation_completed.is_connected(completed_callback):
		_selected_terrain.preview_generation_completed.connect(completed_callback)
	if not _selected_terrain.preview_generation_failed.is_connected(failed_callback):
		_selected_terrain.preview_generation_failed.connect(failed_callback)


func _disconnect_selected_terrain() -> void:
	if not is_instance_valid(_selected_terrain):
		return
	var callbacks := [
		[_selected_terrain.preview_generation_progress, Callable(self, "_on_generation_progress")],
		[_selected_terrain.preview_generation_stage_changed, Callable(self, "_on_generation_stage_changed")],
		[_selected_terrain.preview_generation_completed, Callable(self, "_on_generation_completed")],
		[_selected_terrain.preview_generation_failed, Callable(self, "_on_generation_failed")],
	]
	for entry in callbacks:
		var signal_value: Signal = entry[0]
		var callback: Callable = entry[1]
		if signal_value.is_connected(callback):
			signal_value.disconnect(callback)


func _on_generation_progress(progress: float) -> void:
	if is_instance_valid(_tools_panel):
		_tools_panel.set_generation_progress(progress, _selected_terrain.get_generation_stage_name())


func _on_generation_stage_changed(stage_name: String) -> void:
	if is_instance_valid(_tools_panel):
		_tools_panel.set_generation_progress(_selected_terrain.get_generation_progress(), stage_name)


func _on_generation_completed() -> void:
	if is_instance_valid(_tools_panel):
		_tools_panel.set_generation_progress(1.0, "Ada üretimi tamamlandı")
		_tools_panel.set_message("Ada hazır · Şekillendir sekmesiyle sanat yönetimine geç")
	_refresh_metrics()


func _on_generation_failed(message: String) -> void:
	if is_instance_valid(_tools_panel):
		_tools_panel.set_message("Generation başarısız: %s" % message, true)


func _refresh_metrics() -> void:
	if not is_instance_valid(_tools_panel) or not is_instance_valid(_selected_terrain):
		return
	_tools_panel.update_metrics(_collect_metrics())


func _collect_metrics() -> Dictionary:
	if not is_instance_valid(_selected_terrain):
		return {}
	var manifest = _selected_terrain.manifest
	var budget = _selected_terrain.memory_budget
	return {
		"world_size_m": manifest.world_size_m if manifest != null else 0,
		"max_height_m": manifest.max_height_m if manifest != null else 0.0,
		"macro_resolution": budget.macro_height_resolution if budget != null else 0,
		"region_axis": manifest.region_count_axis() if manifest != null else 0,
		"clipmap_levels": budget.clipmap_levels if budget != null else 0,
		"collision_patches": _selected_terrain.get_active_collision_patch_count(),
		"generation_memory_bytes": _selected_terrain.get_generation_working_memory_bytes(),
		"material_memory_bytes": _selected_terrain.get_material_working_memory_bytes() \
			+ _selected_terrain.get_material_resident_memory_bytes(),
		"quality_level": _selected_terrain.get_runtime_quality_reduction(),
		"generation_stage": _selected_terrain.get_generation_stage_name(),
	}


func _validate_project_renderer() -> void:
	var rendering_method: String = str(
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "mobile")
	)
	if rendering_method != "mobile":
		push_warning(
			"IT-W04: IslandTerrain is tuned for Godot Mobile Renderer; current rendering method is '%s'" \
			% rendering_method
		)
