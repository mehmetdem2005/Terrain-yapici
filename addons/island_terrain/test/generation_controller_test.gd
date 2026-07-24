extends SceneTree

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Budget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const Profile = preload("res://addons/island_terrain/generation/terrain_generation_profile.gd")
const Controller = preload("res://addons/island_terrain/generation/terrain_generation_controller.gd")

var _controller: Controller
var _completed: bool = false
var _failed: String = ""
var _last_progress: float = 0.0
var _frames: int = 0


func _init() -> void:
	call_deferred("_start_test")


func _start_test() -> void:
	var manifest := Manifest.new()
	manifest.world_size_m = 1024
	manifest.region_size_m = 256
	manifest.region_samples = 65
	manifest.max_height_m = 256.0
	manifest.world_seed = 4107
	var budget := Budget.create_for_profile(Budget.DeviceProfile.LOW)
	budget.frame_work_budget_ms = 0.25
	var profile := Profile.new()
	profile.thermal_iterations = 1
	_controller = Controller.new()
	get_root().add_child(_controller)
	_controller.configure(manifest, budget, profile)
	_controller.generation_progress.connect(_on_progress)
	_controller.generation_completed.connect(_on_completed)
	_controller.generation_failed.connect(_on_failed)
	var error: Error = _controller.start(65)
	if error != OK:
		_fail("controller failed to start: %d" % error)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _failed.is_empty():
		_fail(_failed)
		return false
	if _completed:
		if _frames <= 1:
			_fail("generation completed synchronously instead of respecting frame budget")
			return false
		print("IslandTerrain generation controller tests: PASS")
		quit(0)
		return false
	if _frames > 20000:
		_fail("generation controller timed out")
	return false


func _on_progress(value: float, _stage_name: String) -> void:
	if value + 0.000001 < _last_progress:
		_failed = "generation progress regressed"
	_last_progress = value


func _on_completed(_result) -> void:
	_completed = true


func _on_failed(message: String) -> void:
	_failed = "generation controller failed: %s" % message


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
