extends SceneTree

const DemoScene = preload("res://demo/demo_main.tscn")

var _demo: Node
var _frames: int = 0
var _finished: bool = false


func _init() -> void:
	call_deferred("_start_test")


func _start_test() -> void:
	_demo = DemoScene.instantiate()
	_demo.demo_ready.connect(_on_demo_ready)
	_demo.demo_failed.connect(_on_demo_failed)
	get_root().add_child(_demo)


func _process(_delta: float) -> bool:
	_frames += 1
	if not _finished and _frames > 30000:
		push_error("IslandTerrain demo smoke test timed out")
		quit(1)
	return false


func _on_demo_ready() -> void:
	_finished = true
	if not _demo.has_visible_preview_geometry():
		push_error("IslandTerrain demo completed without visible preview geometry")
		quit(1)
		return
	var vertex_count: int = _demo.get_compatibility_vertex_count()
	if vertex_count < 4096:
		push_error("IslandTerrain compatibility preview is unexpectedly small: %d" % vertex_count)
		quit(1)
		return
	print("IslandTerrain visible phone demo smoke test: PASS (%d vertices)" % vertex_count)
	quit(0)


func _on_demo_failed(message: String) -> void:
	_finished = true
	push_error("IslandTerrain demo failed: %s" % message)
	quit(1)
