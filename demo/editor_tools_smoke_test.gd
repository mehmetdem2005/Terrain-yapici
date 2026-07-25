extends SceneTree

const EditorScene = preload("res://editor/terrain_editor_demo.tscn")
const SculptCommand = preload("res://addons/island_terrain/application/terrain_sculpt_command.gd")

var _terrain
var _frames: int = 0
var _initialized: bool = false
var _finished: bool = false


func _init() -> void:
	call_deferred("_start_test")


func _start_test() -> void:
	_terrain = EditorScene.instantiate()
	_terrain.terrain_initialized.connect(_on_terrain_initialized)
	_terrain.preview_generation_failed.connect(_on_generation_failed)
	get_root().add_child(_terrain)


func _process(_delta: float) -> bool:
	_frames += 1
	if _initialized and not _finished and _frames > 12:
		_validate_flat_and_sculpt()
	if not _finished and _frames > 30000:
		push_error("Editor flat terrain sculpt smoke test timed out")
		quit(1)
	return false


func _on_terrain_initialized() -> void:
	_initialized = true


func _validate_flat_and_sculpt() -> void:
	_finished = true
	if not _terrain.is_initialized():
		_fail("IslandTerrain3D did not initialize")
		return
	if _terrain.is_generation_running() or _terrain.get_generation_result() != null:
		_fail("Editor authoring terrain must not auto-generate an island")
		return

	var center := Vector3.ZERO
	var before_height: float = _terrain.get_height_at_world(center)
	var expected_flat_height: float = _terrain.global_position.y + _terrain.manifest.sea_level_m
	if not is_equal_approx(before_height, expected_flat_height):
		_fail("Editor terrain did not start flat at sea level")
		return

	var clipmap = _terrain.get_node_or_null("__IslandClipmap")
	if clipmap == null or clipmap.active_level_count() <= 0:
		_fail("Flat editor clipmap did not create visible levels")
		return

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
		_fail("Raise sculpt did not increase flat terrain height")
		return
	if _terrain.apply_edit_transaction_before(transaction) != OK:
		_fail("Sculpt undo transaction failed")
		return
	if _terrain.flush_height_sync() != OK:
		_fail("Undo height sync failed")
		return
	var restored_height: float = _terrain.get_height_at_world(center)
	if not is_equal_approx(restored_height, before_height):
		_fail("Sculpt undo did not restore the flat terrain")
		return
	print("IslandTerrain flat editor scene and sculpt tools smoke test: PASS")
	quit(0)


func _on_generation_failed(message: String) -> void:
	_fail("Unexpected editor generation failure: %s" % message)


func _fail(message: String) -> void:
	_finished = true
	push_error(message)
	quit(1)