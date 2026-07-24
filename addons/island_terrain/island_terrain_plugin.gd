@tool
extends EditorPlugin

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const Toolbar = preload("res://addons/island_terrain/editor/terrain_sculpt_toolbar.gd")
const SculptCommand = preload("res://addons/island_terrain/application/terrain_sculpt_command.gd")
const EditTransaction = preload("res://addons/island_terrain/application/terrain_edit_transaction.gd")

var _toolbar: Toolbar
var _selected_terrain: TerrainNode
var _stroke_transaction: EditTransaction
var _is_stroking: bool = false
var _last_dab_world: Vector3 = Vector3.INF
var _last_dab_usec: int = 0
var _flatten_target_height: float = 0.0


func _enter_tree() -> void:
	add_custom_type("IslandTerrain3D", "Node3D", TerrainNode, null)
	_toolbar = Toolbar.new()
	_toolbar.visible = false
	_toolbar.undo_requested.connect(_undo_selected_terrain)
	_toolbar.redo_requested.connect(_redo_selected_terrain)
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UR, _toolbar)
	call_deferred("_validate_project_renderer")


func _exit_tree() -> void:
	_finalize_stroke()
	if is_instance_valid(_toolbar):
		remove_control_from_docks(_toolbar)
		_toolbar.queue_free()
	_toolbar = null
	_selected_terrain = null
	remove_custom_type("IslandTerrain3D")


func _handles(object: Object) -> bool:
	return object is TerrainNode


func _edit(object: Object) -> void:
	_finalize_stroke()
	_selected_terrain = object as TerrainNode
	if is_instance_valid(_toolbar) and is_instance_valid(_selected_terrain):
		_toolbar.set_terrain_name(_selected_terrain.name)


func _make_visible(visible: bool) -> void:
	if is_instance_valid(_toolbar):
		_toolbar.visible = visible
	if not visible:
		_finalize_stroke()
		_selected_terrain = null


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(_selected_terrain) \
		or not _selected_terrain.is_initialized() \
		or not is_instance_valid(_toolbar) \
		or not _toolbar.is_sculpt_enabled():
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index > 0:
			if touch.pressed:
				_finalize_stroke()
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if touch.pressed:
			_begin_stroke(camera, touch.position)
		else:
			_finalize_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index > 0:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if _is_stroking:
			_apply_dab(camera, drag.position, false)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT or button.alt_pressed:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if button.pressed:
			_begin_stroke(camera, button.position)
		else:
			_finalize_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _is_stroking and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_apply_dab(camera, motion.position, false)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _begin_stroke(camera: Camera3D, screen_position: Vector2) -> void:
	_finalize_stroke()
	_stroke_transaction = EditTransaction.new()
	_stroke_transaction.action_name = "Terrain Sculpt Stroke"
	_is_stroking = true
	_last_dab_world = Vector3.INF
	_last_dab_usec = 0
	var hit: Dictionary = _raycast_terrain(camera, screen_position)
	if hit.is_empty():
		return
	var hit_position: Vector3 = hit.get("position", Vector3.INF)
	if _toolbar.selected_tool() == SculptCommand.Tool.FLATTEN:
		_flatten_target_height = _selected_terrain.height_sample_from_world_y(hit_position.y)
	_apply_hit(hit_position, true)


func _apply_dab(camera: Camera3D, screen_position: Vector2, force: bool) -> void:
	var hit: Dictionary = _raycast_terrain(camera, screen_position)
	if hit.is_empty():
		return
	_apply_hit(hit.get("position", Vector3.INF), force)


func _apply_hit(hit_position: Vector3, force: bool) -> void:
	if hit_position == Vector3.INF or not _is_stroking:
		return
	var now_usec: int = Time.get_ticks_usec()
	var min_spacing: float = maxf(0.5, _toolbar.brush_radius_m() * _toolbar.spacing_ratio())
	if not force and _last_dab_world != Vector3.INF:
		if _last_dab_world.distance_to(hit_position) < min_spacing:
			return
		if now_usec - _last_dab_usec < 16000:
			return

	var command := SculptCommand.new()
	command.tool = _toolbar.selected_tool()
	command.center_world = hit_position
	command.radius_m = _toolbar.brush_radius_m()
	command.strength = _toolbar.brush_strength()
	command.falloff_exponent = _toolbar.falloff_exponent()
	command.target_height_m = _flatten_target_height
	var dab_transaction: EditTransaction = _selected_terrain.apply_sculpt_command(command)
	if dab_transaction == null or dab_transaction.is_empty():
		return
	var append_error: Error = _stroke_transaction.append_transaction(dab_transaction)
	if append_error != OK:
		_toolbar.set_message("Stroke bellek sınırına ulaştı; işlem güvenli şekilde kapatıldı.")
		_finalize_stroke()
		return
	_last_dab_world = hit_position
	_last_dab_usec = now_usec
	_toolbar.set_message("Düzenleniyor · %d KB undo" % (_stroke_transaction.memory_bytes() / 1024))


func _finalize_stroke() -> void:
	if not _is_stroking:
		return
	_is_stroking = false
	if _stroke_transaction == null or _stroke_transaction.is_empty() \
		or not is_instance_valid(_selected_terrain):
		_stroke_transaction = null
		return
	var undo_redo: EditorUndoRedoManager = get_undo_redo()
	undo_redo.create_action(
		_stroke_transaction.action_name,
		UndoRedo.MERGE_DISABLE,
		_selected_terrain
	)
	undo_redo.add_do_method(
		_selected_terrain,
		&"apply_edit_transaction_after",
		_stroke_transaction
	)
	undo_redo.add_undo_method(
		_selected_terrain,
		&"apply_edit_transaction_before",
		_stroke_transaction
	)
	undo_redo.commit_action(false)
	_toolbar.set_message("Stroke kaydedildi · Geri Al kullanılabilir")
	_stroke_transaction = null


func _raycast_terrain(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	if not is_instance_valid(camera):
		return {}
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	return _selected_terrain.intersect_ray_heightfield(ray_origin, ray_direction)


func _undo_selected_terrain() -> void:
	_operate_selected_history(true)


func _redo_selected_terrain() -> void:
	_operate_selected_history(false)


func _operate_selected_history(undo_operation: bool) -> void:
	if not is_instance_valid(_selected_terrain):
		return
	_finalize_stroke()
	var manager: EditorUndoRedoManager = get_undo_redo()
	var history_id: int = manager.get_object_history_id(_selected_terrain)
	var history: UndoRedo = manager.get_history_undo_redo(history_id)
	if history == null:
		return
	if undo_operation and history.has_undo():
		history.undo()
		_toolbar.set_message("Geri alındı")
	elif not undo_operation and history.has_redo():
		history.redo()
		_toolbar.set_message("Yinelendi")


func _validate_project_renderer() -> void:
	var rendering_method: String = str(
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "mobile")
	)
	if rendering_method != "mobile":
		push_warning(
			"IT-W04: IslandTerrain is tuned for Godot Mobile Renderer; current rendering method is '%s'" \
			% rendering_method
		)
