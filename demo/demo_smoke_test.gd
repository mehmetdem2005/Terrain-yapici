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
	print("IslandTerrain touch demo smoke test: PASS")
	quit(0)


func _on_demo_failed(message: String) -> void:
	_finished = true
	push_error("IslandTerrain demo failed: %s" % message)
	quit(1)
