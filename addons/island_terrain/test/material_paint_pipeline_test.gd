extends SceneTree

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const MemoryBudget = preload("res://addons/island_terrain/core/terrain_memory_budget.gd")
const RegionRepository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")
const PaintCommand = preload("res://addons/island_terrain/application/terrain_paint_command.gd")
const PaintTransaction = preload("res://addons/island_terrain/application/terrain_paint_transaction.gd")
const PaintService = preload("res://addons/island_terrain/application/terrain_material_paint_service.gd")
const OverrideSync = preload("res://addons/island_terrain/rendering/terrain_material_override_sync.gd")

class SyncSpy:
	extends Node
	var queued: Array[Dictionary] = []

	func queue_region_rect(coord: Vector2i, rect: Rect2i) -> void:
		queued.append({"coord": coord, "rect": rect})

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_sparse_paint_undo_redo_and_persistence()
	_test_override_texture_encoding_and_erase()
	if _failures.is_empty():
		print("IslandTerrain material paint pipeline tests: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_sparse_paint_undo_redo_and_persistence() -> void:
	var test_root: String = "user://island_terrain_paint_%d" % Time.get_ticks_usec()
	var manifest := _make_manifest()
	var coordinates := Coordinates.new(manifest)
	var budget := MemoryBudget.create_for_profile(MemoryBudget.DeviceProfile.LOW)
	var repository := RegionRepository.new(test_root, test_root, manifest, budget)
	var sync := SyncSpy.new()
	var service := PaintService.new(manifest, coordinates, repository, sync)
	var untouched: RegionData = repository.get_or_create(Vector2i(1, 1))
	_check(untouched.biome_data.is_empty(), "unused region allocated biome data")
	_check(untouched.material_index_data.is_empty(), "unused region allocated material data")

	var biome_command := PaintCommand.new()
	biome_command.tool = PaintCommand.Tool.BIOME
	biome_command.center_world = Vector3(-128.0, 0.0, -128.0)
	biome_command.radius_m = 10.0
	biome_command.strength = 1.0
	biome_command.biome_id = 3
	var biome_transaction: PaintTransaction = service.apply_paint(biome_command)
	_check(biome_transaction != null and not biome_transaction.is_empty(), "biome paint produced no transaction")

	var material_command := PaintCommand.new()
	material_command.tool = PaintCommand.Tool.MATERIAL
	material_command.center_world = biome_command.center_world
	material_command.radius_m = 10.0
	material_command.strength = 1.0
	material_command.material_id = 4
	var material_transaction: PaintTransaction = service.apply_paint(material_command)
	_check(material_transaction != null and not material_transaction.is_empty(), "material paint produced no transaction")
	_check(not sync.queued.is_empty(), "paint did not queue override synchronization")

	var region: RegionData = repository.get_or_create(Vector2i.ZERO)
	var center := Vector2i(32, 32)
	_check(region.biome_override_id(center) == 3, "biome override id was not stored")
	_check(region.biome_override_strength(center) == 255, "biome override strength was not stored")
	_check(region.material_override_id(center) == 4, "material override id was not stored")
	_check(region.material_override_strength(center) == 255, "material override strength was not stored")
	_check(biome_transaction.memory_bytes() < 1024 * 1024, "small biome stroke used excessive undo memory")

	_check(service.apply_transaction_before(material_transaction) == OK, "material undo failed")
	_check(region.material_override_strength(center) == 0, "material undo did not restore procedural state")
	_check(service.apply_transaction_after(material_transaction) == OK, "material redo failed")
	_check(region.material_override_id(center) == 4, "material redo did not restore id")
	_check(service.apply_transaction_before(biome_transaction) == OK, "biome undo failed")
	_check(region.biome_override_strength(center) == 0, "biome undo did not restore procedural state")
	_check(service.apply_transaction_after(biome_transaction) == OK, "biome redo failed")
	_check(region.biome_override_id(center) == 3, "biome redo did not restore id")

	_check(repository.flush_all() == OK, "paint region persistence failed")
	var reloaded_repository := RegionRepository.new(test_root, test_root, manifest, budget)
	var reloaded: RegionData = reloaded_repository.get_or_create(Vector2i.ZERO)
	_check(reloaded.biome_override_id(center) == 3, "saved biome override did not reload")
	_check(reloaded.biome_override_strength(center) == 255, "saved biome strength did not reload")
	_check(reloaded.material_override_id(center) == 4, "saved material override did not reload")
	_check(reloaded.material_override_strength(center) == 255, "saved material strength did not reload")
	_remove_tree(test_root)


func _test_override_texture_encoding_and_erase() -> void:
	var test_root: String = "user://island_terrain_override_%d" % Time.get_ticks_usec()
	var manifest := _make_manifest()
	var coordinates := Coordinates.new(manifest)
	var budget := MemoryBudget.create_for_profile(MemoryBudget.DeviceProfile.LOW)
	budget.macro_height_resolution = 65
	var repository := RegionRepository.new(test_root, test_root, manifest, budget)
	var sync := OverrideSync.new()
	get_root().add_child(sync)
	_check(sync.configure(manifest, coordinates, repository, budget) == OK, "override sync configuration failed")
	var service := PaintService.new(manifest, coordinates, repository, sync)

	var biome_command := PaintCommand.new()
	biome_command.tool = PaintCommand.Tool.BIOME
	biome_command.center_world = Vector3(-128.0, 0.0, -128.0)
	biome_command.radius_m = 12.0
	biome_command.strength = 1.0
	biome_command.biome_id = 6
	service.apply_paint(biome_command)
	var material_command := PaintCommand.new()
	material_command.tool = PaintCommand.Tool.MATERIAL
	material_command.center_world = biome_command.center_world
	material_command.radius_m = 12.0
	material_command.strength = 1.0
	material_command.material_id = 5
	service.apply_paint(material_command)
	_check(sync.flush_all() == OK, "override sync flush failed")
	var image: Image = sync.texture().get_image()
	var sample: Color = image.get_pixel(16, 16)
	_check(absf(sample.r - 6.0 / 7.0) < 0.02, "override texture biome id encoding is incorrect")
	_check(sample.g > 0.95, "override texture biome strength is incorrect")
	_check(sample.b > 0.95, "override texture material id encoding is incorrect")
	_check(sample.a > 0.95, "override texture material strength is incorrect")

	var erase := PaintCommand.new()
	erase.tool = PaintCommand.Tool.ERASE_ALL
	erase.center_world = biome_command.center_world
	erase.radius_m = 12.0
	erase.strength = 1.0
	service.apply_paint(erase)
	sync.flush_all()
	image = sync.texture().get_image()
	sample = image.get_pixel(16, 16)
	_check(sample.g < 0.02 and sample.a < 0.02, "erase did not restore transparent procedural override")
	sync.queue_free()
	_remove_tree(test_root)


func _make_manifest() -> Manifest:
	var manifest := Manifest.new()
	manifest.world_size_m = 512
	manifest.region_size_m = 256
	manifest.region_samples = 65
	manifest.max_height_m = 200.0
	return manifest


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
