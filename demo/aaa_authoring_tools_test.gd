extends SceneTree

const EditorScene = preload("res://editor/terrain_editor_demo.tscn")
const SculptCommand = preload("res://addons/island_terrain/application/terrain_sculpt_command.gd")
const BrushPreview = preload("res://addons/island_terrain/editor/terrain_brush_preview.gd")

var _terrain
var _frames: int = 0
var _tested: bool = false


func _init() -> void:
	call_deferred("_start_test")


func _start_test() -> void:
	_terrain = EditorScene.instantiate()
	var test_id: String = str(Time.get_ticks_usec())
	_terrain.world_data_root = "user://aaa_authoring_%s/source" % test_id
	_terrain.runtime_data_root = "user://aaa_authoring_%s/runtime" % test_id
	get_root().add_child(_terrain)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _tested and is_instance_valid(_terrain) and _terrain.is_initialized():
		_tested = true
		_run_authoring_checks()
	if not _tested and _frames > 2400:
		_fail("AAA authoring tools test timed out")
	return false


func _run_authoring_checks() -> void:
	if _terrain.is_generation_running():
		_fail("Authoring terrain started procedural generation automatically")
		return
	var flat_height: float = _terrain.get_height_at_world(Vector3.ZERO)
	if not is_equal_approx(flat_height, _terrain.manifest.sea_level_m):
		_fail("Authoring terrain did not start flat")
		return

	var raise_command := SculptCommand.new()
	raise_command.tool = SculptCommand.Tool.RAISE
	raise_command.center_world = Vector3(24.0, flat_height, 24.0)
	raise_command.radius_m = 36.0
	raise_command.strength = 7.3
	var raise_transaction = _terrain.apply_sculpt_command(raise_command)
	if raise_transaction == null or raise_transaction.is_empty():
		_fail("AAA raise tool produced no edit")
		return

	var noise_command := SculptCommand.new()
	noise_command.tool = SculptCommand.Tool.NOISE
	noise_command.center_world = Vector3(24.0, flat_height, 24.0)
	noise_command.radius_m = 28.0
	noise_command.strength = 3.0
	noise_command.noise_scale_m = 18.0
	noise_command.random_seed = 991
	var noise_transaction = _terrain.apply_sculpt_command(noise_command)
	if noise_transaction == null or noise_transaction.is_empty():
		_fail("AAA noise tool produced no edit")
		return

	var terrace_command := SculptCommand.new()
	terrace_command.tool = SculptCommand.Tool.TERRACE
	terrace_command.center_world = Vector3(24.0, flat_height, 24.0)
	terrace_command.radius_m = 24.0
	terrace_command.strength = 1.0
	terrace_command.terrace_step_m = 4.0
	var terrace_transaction = _terrain.apply_sculpt_command(terrace_command)
	if terrace_transaction == null or terrace_transaction.is_empty():
		_fail("AAA terrace tool produced no edit")
		return

	if _terrain.flush_height_sync() != OK:
		_fail("AAA tools height synchronization failed")
		return

	var preview := BrushPreview.new()
	_terrain.add_child(preview)
	preview.set_terrain(_terrain)
	var center := Vector3(24.0, _terrain.get_height_at_world(Vector3(24.0, 0.0, 24.0)), 24.0)
	preview.show_brush(center, 20.0, 2.0, Color(0.2, 0.62, 1.0), true)
	if not preview.has_geometry():
		_fail("AAA brush preview generated no geometry")
		return

	print("IslandTerrain AAA authoring tools test: PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
