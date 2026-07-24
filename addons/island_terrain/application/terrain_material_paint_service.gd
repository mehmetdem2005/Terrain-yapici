@tool
extends RefCounted
class_name IslandTerrainMaterialPaintService

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const RegionRepository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")
const PaintCommand = preload("res://addons/island_terrain/application/terrain_paint_command.gd")
const RegionDelta = preload("res://addons/island_terrain/application/terrain_region_paint_delta.gd")
const PaintTransaction = preload("res://addons/island_terrain/application/terrain_paint_transaction.gd")

var _manifest: Manifest
var _coordinates: Coordinates
var _repository: RegionRepository
var _override_sync: Node


func _init(
	manifest: Manifest,
	coordinates: Coordinates,
	repository: RegionRepository,
	override_sync: Node
) -> void:
	_manifest = manifest
	_coordinates = coordinates
	_repository = repository
	_override_sync = override_sync


func apply_paint(command: PaintCommand) -> PaintTransaction:
	if command == null:
		push_error("IT-040: Paint command is null")
		return null
	var validation: PackedStringArray = command.validate()
	if not validation.is_empty():
		push_error("IT-040: Invalid paint command: %s" % "; ".join(validation))
		return null

	var transaction := PaintTransaction.new()
	transaction.action_name = command.label()
	var min_world := command.center_world - Vector3(command.radius_m, 0.0, command.radius_m)
	var max_world := command.center_world + Vector3(command.radius_m, 0.0, command.radius_m)
	var min_region: Vector2i = _coordinates.world_to_region_clamped(min_world)
	var max_region: Vector2i = _coordinates.world_to_region_clamped(max_world)

	for region_y in range(min_region.y, max_region.y + 1):
		for region_x in range(min_region.x, max_region.x + 1):
			var coord := Vector2i(region_x, region_y)
			var region: RegionData = _repository.get_or_create(coord)
			if region == null:
				continue
			var rect: Rect2i = _brush_rect_for_region(command, coord, region.sample_count)
			if rect.size.x <= 0 or rect.size.y <= 0:
				continue
			var delta: RegionDelta = _build_and_apply_delta(command, coord, region, rect)
			if delta == null:
				continue
			var add_error: Error = transaction.add_delta(delta)
			if add_error != OK:
				delta.apply_before(region)
				transaction.apply_before(_repository)
				push_error("IT-041: Paint transaction exceeded its memory budget")
				return null
			_repository.mark_dirty(coord)
			_queue_rect(coord, rect)
	return transaction


func apply_transaction_before(transaction: PaintTransaction) -> Error:
	if transaction == null:
		return ERR_INVALID_DATA
	var error: Error = transaction.apply_before(_repository)
	if error == OK:
		_queue_transaction_sync(transaction)
	return error


func apply_transaction_after(transaction: PaintTransaction) -> Error:
	if transaction == null:
		return ERR_INVALID_DATA
	var error: Error = transaction.apply_after(_repository)
	if error == OK:
		_queue_transaction_sync(transaction)
	return error


func _brush_rect_for_region(
	command: PaintCommand,
	coord: Vector2i,
	sample_count: int
) -> Rect2i:
	var local_center: Vector2 = _coordinates.world_to_region_local(command.center_world, coord)
	var samples_per_meter: float = float(sample_count - 1) / float(_manifest.region_size_m)
	var min_x: int = clampi(floori((local_center.x - command.radius_m) * samples_per_meter), 0, sample_count - 1)
	var min_y: int = clampi(floori((local_center.y - command.radius_m) * samples_per_meter), 0, sample_count - 1)
	var max_x: int = clampi(ceili((local_center.x + command.radius_m) * samples_per_meter), 0, sample_count - 1)
	var max_y: int = clampi(ceili((local_center.y + command.radius_m) * samples_per_meter), 0, sample_count - 1)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _build_and_apply_delta(
	command: PaintCommand,
	coord: Vector2i,
	region: RegionData,
	rect: Rect2i
) -> RegionDelta:
	var count: int = rect.size.x * rect.size.y
	var total_pixels: int = region.sample_count * region.sample_count
	var before_biome := PackedByteArray()
	var after_biome := PackedByteArray()
	var before_biome_strength := PackedByteArray()
	var after_biome_strength := PackedByteArray()
	var before_material := PackedByteArray()
	var after_material := PackedByteArray()
	var before_material_strength := PackedByteArray()
	var after_material_strength := PackedByteArray()
	for values in [
		before_biome,
		after_biome,
		before_biome_strength,
		after_biome_strength,
		before_material,
		after_material,
		before_material_strength,
		after_material_strength,
	]:
		values.resize(count)

	var has_biome: bool = region.biome_data.size() == total_pixels
	var has_biome_strength: bool = region.biome_valid_mask.size() == total_pixels
	var has_material: bool = region.material_index_data.size() == total_pixels
	var has_material_strength: bool = region.material_valid_mask.size() == total_pixels
	var center_xz := Vector2(command.center_world.x, command.center_world.z)
	var changed: bool = false
	var value_index: int = 0

	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var linear_index: int = y * region.sample_count + x
			var old_biome: int = int(region.biome_data[linear_index]) if has_biome else 0
			var old_biome_strength: int = int(region.biome_valid_mask[linear_index]) \
				if has_biome_strength else 0
			var old_material: int = int(region.material_index_data[linear_index]) \
				if has_material else 0
			var old_material_strength: int = int(region.material_valid_mask[linear_index]) \
				if has_material_strength else 0
			var new_biome: int = old_biome
			var new_biome_strength: int = old_biome_strength
			var new_material: int = old_material
			var new_material_strength: int = old_material_strength

			var world_position: Vector3 = _coordinates.region_pixel_to_world(coord, Vector2i(x, y))
			var distance_m: float = Vector2(world_position.x, world_position.z).distance_to(center_xz)
			var amount: int = clampi(
				roundi(command.weight_for_distance(distance_m) * command.strength * 255.0),
				0,
				255
			)
			if amount > 0:
				match command.tool:
					PaintCommand.Tool.BIOME:
						new_biome = command.biome_id
						new_biome_strength = maxi(old_biome_strength, amount) \
							if old_biome == command.biome_id else amount
					PaintCommand.Tool.MATERIAL:
						new_material = command.material_id
						new_material_strength = maxi(old_material_strength, amount) \
							if old_material == command.material_id else amount
					PaintCommand.Tool.ERASE_BIOME:
						new_biome_strength = maxi(0, old_biome_strength - amount)
						if new_biome_strength == 0:
							new_biome = 0
					PaintCommand.Tool.ERASE_MATERIAL:
						new_material_strength = maxi(0, old_material_strength - amount)
						if new_material_strength == 0:
							new_material = 0
					PaintCommand.Tool.ERASE_ALL:
						new_biome_strength = maxi(0, old_biome_strength - amount)
						new_material_strength = maxi(0, old_material_strength - amount)
						if new_biome_strength == 0:
							new_biome = 0
						if new_material_strength == 0:
							new_material = 0

			before_biome[value_index] = old_biome
			after_biome[value_index] = new_biome
			before_biome_strength[value_index] = old_biome_strength
			after_biome_strength[value_index] = new_biome_strength
			before_material[value_index] = old_material
			after_material[value_index] = new_material
			before_material_strength[value_index] = old_material_strength
			after_material_strength[value_index] = new_material_strength
			if old_biome != new_biome \
				or old_biome_strength != new_biome_strength \
				or old_material != new_material \
				or old_material_strength != new_material_strength:
				changed = true
			value_index += 1

	if not changed:
		return null
	region.ensure_channel(&"biome")
	region.ensure_channel(&"biome_valid")
	region.ensure_channel(&"material_index")
	region.ensure_channel(&"material_valid")
	value_index = 0
	for y in range(rect.position.y, rect.end.y):
		var target_index: int = y * region.sample_count + rect.position.x
		for x in range(rect.size.x):
			var linear_index: int = target_index + x
			region.biome_data[linear_index] = after_biome[value_index]
			region.biome_valid_mask[linear_index] = after_biome_strength[value_index]
			region.material_index_data[linear_index] = after_material[value_index]
			region.material_valid_mask[linear_index] = after_material_strength[value_index]
			value_index += 1
	region.revision += 1
	var delta := RegionDelta.new()
	delta.configure(
		coord,
		rect,
		before_biome,
		after_biome,
		before_biome_strength,
		after_biome_strength,
		before_material,
		after_material,
		before_material_strength,
		after_material_strength
	)
	return delta


func _queue_rect(coord: Vector2i, rect: Rect2i) -> void:
	if _override_sync != null and _override_sync.has_method("queue_region_rect"):
		_override_sync.queue_region_rect(coord, rect)


func _queue_transaction_sync(transaction: PaintTransaction) -> void:
	if _override_sync == null or not _override_sync.has_method("queue_region_rect"):
		return
	for delta in transaction.deltas:
		_override_sync.queue_region_rect(delta.coord, delta.rect)
