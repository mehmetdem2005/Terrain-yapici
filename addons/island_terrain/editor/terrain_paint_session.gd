@tool
extends RefCounted
class_name IslandTerrainPaintSession

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const Toolbar = preload("res://addons/island_terrain/editor/terrain_paint_toolbar.gd")
const PaintCommand = preload("res://addons/island_terrain/application/terrain_paint_command.gd")
const PaintTransaction = preload("res://addons/island_terrain/application/terrain_paint_transaction.gd")

var _toolbar: Toolbar
var _undo_redo: EditorUndoRedoManager
var _terrain: TerrainNode
var _stroke_transaction: PaintTransaction
var _is_stroking: bool = false
var _last_dab_world: Vector3 = Vector3.INF
var _last_dab_usec: int = 0


func configure(toolbar: Toolbar, undo_redo: EditorUndoRedoManager) -> void:
	_toolbar = toolbar
	_undo_redo = undo_redo


func set_terrain(terrain: TerrainNode) -> void:
	finalize_stroke()
	_terrain = terrain
	if is_instance_valid(_toolbar) and is_instance_valid(_terrain):
		_toolbar.set_terrain_name(_terrain.name)


func clear_terrain() -> void:
	finalize_stroke()
	_terrain = null


func route_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(_terrain) \
		or not _terrain.is_initialized() \
		or not is_instance_valid(_toolbar) \
		or not _toolbar.is_paint_enabled():
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.index > 0:
			if touch.pressed:
				finalize_stroke()
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		if touch.pressed:
			_begin_stroke(camera, touch.position)
		else:
			finalize_stroke()
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
			finalize_stroke()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _is_stroking and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_apply_dab(camera, motion.position, false)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func finalize_stroke() -> void:
	if not _is_stroking:
		return
	_is_stroking = false
	if _stroke_transaction == null or _stroke_transaction.is_empty() \
		or not is_instance_valid(_terrain):
		_stroke_transaction = null
		return
	_undo_redo.create_action(
		_stroke_transaction.action_name,
		UndoRedo.MERGE_DISABLE,
		_terrain
	)
	_undo_redo.add_do_method(
		_terrain,
		&"apply_paint_transaction_after",
		_stroke_transaction
	)
	_undo_redo.add_undo_method(
		_terrain,
		&"apply_paint_transaction_before",
		_stroke_transaction
	)
	_undo_redo.commit_action(false)
	_toolbar.set_message("Paint stroke kaydedildi · Geri Al kullanılabilir")
	_stroke_transaction = null


func undo() -> void:
	_operate_history(true)


func redo() -> void:
	_operate_history(false)


func _begin_stroke(camera: Camera3D, screen_position: Vector2) -> void:
	finalize_stroke()
	_stroke_transaction = PaintTransaction.new()
	_stroke_transaction.action_name = "Terrain Paint Stroke"
	_is_stroking = true
	_last_dab_world = Vector3.INF
	_last_dab_usec = 0
	_apply_dab(camera, screen_position, true)


func _apply_dab(camera: Camera3D, screen_position: Vector2, force: bool) -> void:
	var hit: Dictionary = _raycast_terrain(camera, screen_position)
	if hit.is_empty():
		return
	var hit_position: Vector3 = hit.get("position", Vector3.INF)
	if hit_position == Vector3.INF or not _is_stroking:
		return
	var now_usec: int = Time.get_ticks_usec()
	var min_spacing: float = maxf(0.5, _toolbar.brush_radius_m() * _toolbar.spacing_ratio())
	if not force and _last_dab_world != Vector3.INF:
		if _last_dab_world.distance_to(hit_position) < min_spacing:
			return
		if now_usec - _last_dab_usec < 16000:
			return

	var command := PaintCommand.new()
	command.tool = _toolbar.selected_tool()
	command.center_world = hit_position
	command.radius_m = _toolbar.brush_radius_m()
	command.strength = _toolbar.brush_strength()
	command.falloff_exponent = _toolbar.falloff_exponent()
	command.biome_id = _toolbar.selected_biome()
	command.material_id = _toolbar.selected_material()
	var dab_transaction: PaintTransaction = _terrain.apply_paint_command(command)
	if dab_transaction == null or dab_transaction.is_empty():
		return
	var append_error: Error = _stroke_transaction.append_transaction(dab_transaction)
	if append_error != OK:
		var rollback_error: Error = _terrain.apply_paint_transaction_before(dab_transaction)
		if rollback_error != OK:
			push_error("IT-042: Failed to roll back rejected paint dab")
		_toolbar.set_message("Paint stroke bellek sınırına ulaştı; son dab geri alındı.")
		finalize_stroke()
		return
	_last_dab_world = hit_position
	_last_dab_usec = now_usec
	_toolbar.set_message("Boyanıyor · %d KB undo" % (_stroke_transaction.memory_bytes() / 1024))


func _raycast_terrain(camera: Camera3D, screen_position: Vector2) -> Dictionary:
	if not is_instance_valid(camera):
		return {}
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	return _terrain.intersect_ray_heightfield(ray_origin, ray_direction)


func _operate_history(undo_operation: bool) -> void:
	if not is_instance_valid(_terrain):
		return
	finalize_stroke()
	var history_id: int = _undo_redo.get_object_history_id(_terrain)
	var history: UndoRedo = _undo_redo.get_history_undo_redo(history_id)
	if history == null:
		return
	if undo_operation and history.has_undo():
		history.undo()
		_toolbar.set_message("Geri alındı")
	elif not undo_operation and history.has_redo():
		history.redo()
		_toolbar.set_message("Yinelendi")
