@tool
extends RefCounted
class_name IslandTerrainEditService

const Manifest = preload("res://addons/island_terrain/core/terrain_manifest.gd")
const Coordinates = preload("res://addons/island_terrain/core/terrain_coordinate_system.gd")
const RegionData = preload("res://addons/island_terrain/core/terrain_region_data.gd")
const RegionRepository = preload("res://addons/island_terrain/infrastructure/terrain_region_repository.gd")
const SculptCommand = preload("res://addons/island_terrain/application/terrain_sculpt_command.gd")
const RegionDelta = preload("res://addons/island_terrain/application/terrain_region_height_delta.gd")
const EditTransaction = preload("res://addons/island_terrain/application/terrain_edit_transaction.gd")

var _manifest: Manifest
var _coordinates: Coordinates
var _repository: RegionRepository
var _macro_sync: Node
var _base_height_sampler: Callable


func _init(
	manifest: Manifest,
	coordinates: Coordinates,
	repository: RegionRepository,
	macro_sync: Node,
	base_height_sampler: Callable
) -> void:
	_manifest = manifest
	_coordinates = coordinates
	_repository = repository
	_macro_sync = macro_sync
	_base_height_sampler = base_height_sampler


func apply_sculpt(command: SculptCommand) -> EditTransaction:
	if command == null:
		push_error("IT-020: Sculpt command is null")
		return null
	var validation: PackedStringArray = command.validate()
	if not validation.is_empty():
		push_error("IT-020: Invalid sculpt command: %s" % "; ".join(validation))
		return null
	if not _base_height_sampler.is_valid():
		push_error("IT-024: Base terrain sampler is unavailable")
		return null

	var transaction := EditTransaction.new()
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
				push_error("IT-021: Sculpt transaction exceeded its memory budget")
				return null
			_repository.mark_dirty(coord)
			if _macro_sync != null and _macro_sync.has_method("queue_region_rect"):
				_macro_sync.queue_region_rect(coord, rect)

	return transaction


func apply_transaction_before(transaction: EditTransaction) -> Error:
	if transaction == null:
		return ERR_INVALID_DATA
	var error: Error = transaction.apply_before(_repository)
	if error == OK:
		_queue_transaction_sync(transaction)
	return error


func apply_transaction_after(transaction: EditTransaction) -> Error:
	if transaction == null:
		return ERR_INVALID_DATA
	var error: Error = transaction.apply_after(_repository)
	if error == OK:
		_queue_transaction_sync(transaction)
	return error


func _brush_rect_for_region(
	command: SculptCommand,
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
	command: SculptCommand,
	coord: Vector2i,
	region: RegionData,
	rect: Rect2i
) -> RegionDelta:
	var needs_snapshot: bool = command.tool == SculptCommand.Tool.SMOOTH
	var source: PackedFloat32Array = region.height_data.duplicate() \
		if needs_snapshot else region.height_data
	var source_valid := PackedByteArray()
	if needs_snapshot:
		source_valid.resize(region.sample_count * region.sample_count)
		if region.height_is_dense:
			source_valid.fill(1)
		elif region.height_valid_mask.size() == source_valid.size():
			source_valid = region.height_valid_mask.duplicate()
		else:
			source_valid.fill(0)

	if not region.height_is_dense:
		region.ensure_channel(&"height_valid")
	var count: int = rect.size.x * rect.size.y
	var before := PackedFloat32Array()
	var after := PackedFloat32Array()
	var before_valid := PackedByteArray()
	var after_valid := PackedByteArray()
	before.resize(count)
	after.resize(count)
	before_valid.resize(count)
	after_valid.resize(count)
	var changed: bool = false
	var value_index: int = 0
	var center_xz := Vector2(command.center_world.x, command.center_world.z)

	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var pixel := Vector2i(x, y)
			var linear_index: int = y * region.sample_count + x
			var world_pos: Vector3 = _coordinates.region_pixel_to_world(coord, pixel)
			var was_valid: bool = source_valid[linear_index] != 0 \
				if needs_snapshot else region.is_height_valid(pixel)
			var old_height: float = source[linear_index] if was_valid else _sample_base_height(world_pos)
			var distance_m: float = Vector2(world_pos.x, world_pos.z).distance_to(center_xz)
			var weight: float = command.weight_for_distance(distance_m)
			var new_height: float = old_height
			var will_be_valid: bool = was_valid
			if weight > 0.0:
				new_height = _evaluate_height(
					command,
					coord,
					source,
					source_valid,
					region.sample_count,
					pixel,
					world_pos,
					old_height,
					weight
				)
				new_height = clampf(new_height, 0.0, _manifest.max_height_m)
				if not is_equal_approx(old_height, new_height):
					will_be_valid = true
			before[value_index] = old_height
			after[value_index] = new_height
			before_valid[value_index] = 1 if was_valid else 0
			after_valid[value_index] = 1 if will_be_valid else 0
			if not is_equal_approx(old_height, new_height):
				region.height_data[linear_index] = new_height
				if not region.height_is_dense:
					region.height_valid_mask[linear_index] = 1
				changed = true
			value_index += 1

	if not changed:
		return null
	region.revision += 1
	var delta := RegionDelta.new()
	delta.configure(coord, rect, before, after, before_valid, after_valid)
	return delta


func _evaluate_height(
	command: SculptCommand,
	coord: Vector2i,
	source: PackedFloat32Array,
	source_valid: PackedByteArray,
	sample_count: int,
	pixel: Vector2i,
	world_position: Vector3,
	old_height: float,
	weight: float
) -> float:
	match command.tool:
		SculptCommand.Tool.RAISE:
			return old_height + command.strength * weight
		SculptCommand.Tool.LOWER:
			return old_height - command.strength * weight
		SculptCommand.Tool.FLATTEN:
			return lerpf(old_height, command.target_height_m, clampf(command.strength * weight, 0.0, 1.0))
		SculptCommand.Tool.SMOOTH:
			var average: float = _neighbor_average(coord, source, source_valid, sample_count, pixel)
			return lerpf(old_height, average, clampf(command.strength * weight, 0.0, 1.0))
		SculptCommand.Tool.NOISE:
			var signed_noise: float = _sample_editor_noise(world_position, command.noise_scale_m, command.random_seed)
			return old_height + signed_noise * command.strength * weight
		SculptCommand.Tool.TERRACE:
			var safe_step: float = maxf(0.25, command.terrace_step_m)
			var terraced_height: float = roundf(old_height / safe_step) * safe_step
			return lerpf(old_height, terraced_height, clampf(command.strength * weight, 0.0, 1.0))
	return old_height


func _sample_editor_noise(world_position: Vector3, scale_m: float, seed: int) -> float:
	var safe_scale: float = maxf(0.5, scale_m)
	var x: float = world_position.x / safe_scale
	var z: float = world_position.z / safe_scale
	var seed_phase: float = float(seed) * 0.17320508
	var octave_a: float = sin(x * 1.71 + seed_phase) * cos(z * 1.37 - seed_phase * 0.41)
	var octave_b: float = sin((x + z) * 3.11 + seed_phase * 1.83) * 0.38
	var octave_c: float = cos((x - z) * 6.07 - seed_phase * 0.77) * 0.16
	return clampf((octave_a + octave_b + octave_c) / 1.54, -1.0, 1.0)


func _neighbor_average(
	coord: Vector2i,
	source: PackedFloat32Array,
	source_valid: PackedByteArray,
	sample_count: int,
	pixel: Vector2i
) -> float:
	var total: float = 0.0
	var samples: int = 0
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var sample_pixel := Vector2i(
				clampi(pixel.x + offset_x, 0, sample_count - 1),
				clampi(pixel.y + offset_y, 0, sample_count - 1)
			)
			var index: int = sample_pixel.y * sample_count + sample_pixel.x
			if source_valid[index] != 0:
				total += source[index]
			else:
				var world_pos: Vector3 = _coordinates.region_pixel_to_world(coord, sample_pixel)
				total += _sample_base_height(world_pos)
			samples += 1
	return total / float(maxi(samples, 1))


func _sample_base_height(world_position: Vector3) -> float:
	return float(_base_height_sampler.call(world_position))


func _queue_transaction_sync(transaction: EditTransaction) -> void:
	if _macro_sync == null or not _macro_sync.has_method("queue_region_rect"):
		return
	for delta in transaction.deltas:
		_macro_sync.queue_region_rect(delta.coord, delta.rect)
