extends SceneTree

const EditorScene = preload("res://editor/terrain_editor_demo.tscn")
const SculptCommand = preload("res://addons/island_terrain/application/terrain_sculpt_command.gd")

var _terrain
var _frames: int = 0
var _finished: bool = false


func _init() -> void:
	call_deferred("_start_test")


func _start_test() -> void:
	_terrain = EditorScene.instantiate()
	_terrain.preview_generation_completed.connect(_on_generation_completed)
	_terrain.preview_generation_failed.connect(_on_generation_failed)
	get_root().add_child(_terrain)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _finished and _frames > 30000:
		push_error("Editor terrain scene sculpt smoke test timed out")
		quit(1)
	return false


func _on_generation_completed() -> void:
	if not _terrain.is_initialized():
		_fail("IslandTerrain3D did not initialize")
		return

	var center := Vector3.ZERO
	var before_height: float = _terrain.get_height_at_world(center)
	var command := SculptCommand.new()
	command.tool = SculptCommand.Tool.RAISE
	command.center_world = Vector3(center.x, before_height, center.z)
	command.radius_m = 16.0
	command.strength = 3.0
	command.falloff_exponent = 2.0
	var transaction = _terrain.apply_sculpt_command(command)
	if transaction == null or transaction.is_empty():
		_fail("Sculpt command produced no edit transaction")
		return
	if _terrain.flush_height_sync() != OK:
		_fail("Sculpt height sync failed")
		return
	var after_height: float = _terrain.get_height_at_world(center)
	if after_height <= before_height:
		_fail("Raise sculpt did not increase terrain height")
		return
	if _terrain.apply_edit_transaction_before(transaction) != OK:
		_fail("Sculpt undo transaction failed")
		return
	if _terrain.flush_height_sync() != OK:
		_fail("Undo height sync failed")
		return
	_finished = true
	print("IslandTerrain editor scene and sculpt tools smoke test: PASS")
	quit(0)


func _on_generation_failed(message: String) -> void:
	_fail("Editor scene generation failed: %s" % message)


func _fail(message: String) -> void:
	_finished = true
	push_error(message)
	quit(1)
