extends SceneTree

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const MemoryBudget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const RegionRepository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")
const SculptCommand = preload("res://addons/island_terrain/application/terrain_sculpt_command.gd")
const EditTransaction = preload("res://addons/island_terrain/application/terrain_edit_transaction.gd")
const EditService = preload("res://addons/island_terrain/application/terrain_edit_service.gd")

class MacroSyncSpy:
	extends Node
	var queued: Array[Dictionary] = []

	func queue_region_rect(coord: Vector2i, rect: Rect2i) -> void:
		queued.append({"coord": coord, "rect": rect})

var _failures := PackedStringArray()


func _init() -> void:
	_test_raise_undo_redo_sparse_base()
	_test_transaction_memory_limit()
	if _failures.is_empty():
		print("IslandTerrain sculpt pipeline tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_raise_undo_redo_sparse_base() -> void:
	var test_root: String = "user://island_terrain_sculpt_%d" % Time.get_ticks_usec()
	var manifest := Manifest.new()
	manifest.world_size_m = 512
	manifest.region_size_m = 256
	manifest.region_samples = 65
	manifest.max_height_m = 200.0
	var coordinates := Coordinates.new(manifest)
	var budget := MemoryBudget.create_for_profile(MemoryBudget.DeviceProfile.LOW)
	var repository := RegionRepository.new(test_root, test_root, manifest, budget)
	var sync := MacroSyncSpy.new()
	var service := EditService.new(
		manifest,
		coordinates,
		repository,
		sync,
		Callable(self, "_constant_base_height")
	)
	var command := SculptCommand.new()
	command.tool = SculptCommand.Tool.RAISE
	command.center_world = Vector3(-128.0, 100.0, -128.0)
	command.radius_m = 8.0
	command.strength = 10.0
	command.falloff_exponent = 2.0
	var transaction: EditTransaction = service.apply_sculpt(command)
	_check(transaction != null and not transaction.is_empty(), "raise command produced no transaction")
	if transaction == null or transaction.is_empty():
		_remove_tree(test_root)
		return
	_check(transaction.memory_bytes() < 1024 * 1024, "small brush delta used excessive memory")
	_check(not sync.queued.is_empty(), "dirty macro synchronization was not queued")
	var region: RegionData = repository.get_or_create(Vector2i.ZERO)
	var center_pixel := Vector2i(32, 32)
	_check(region.is_height_valid(center_pixel), "edited sample was not marked valid")
	_check(region.get_height(center_pixel) > 100.0, "raise command did not build on procedural base height")
	_check(service.apply_transaction_before(transaction) == OK, "undo transaction failed")
	_check(not region.is_height_valid(center_pixel), "undo did not restore unedited sparse state")
	_check(service.apply_transaction_after(transaction) == OK, "redo transaction failed")
	_check(region.is_height_valid(center_pixel), "redo did not restore sparse validity")
	_check(region.get_height(center_pixel) > 100.0, "redo did not restore edited height")
	_remove_tree(test_root)


func _test_transaction_memory_limit() -> void:
	var transaction := EditTransaction.new()
	transaction.max_memory_bytes = 16
	var oversized_delta = preload("res://addons/island_terrain/application/terrain_region_height_delta.gd").new()
	var values := PackedFloat32Array([1.0, 2.0, 3.0, 4.0])
	var validity := PackedByteArray([1, 1, 1, 1])
	oversized_delta.configure(Vector2i.ZERO, Rect2i(0, 0, 2, 2), values, values, validity, validity)
	_check(transaction.add_delta(oversized_delta) == ERR_OUT_OF_MEMORY, "transaction memory cap was not enforced")
	_check(transaction.is_empty(), "rejected delta was added to transaction")


func _constant_base_height(_world_position: Vector3) -> float:
	return 100.0


func _remove_tree(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry: String = directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path: String = "%s/%s" % [path, entry]
			if directory.current_is_dir():
				_remove_tree(child_path)
			else:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(child_path))
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
