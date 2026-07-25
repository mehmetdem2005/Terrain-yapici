extends Node3D

signal demo_ready
signal demo_failed(message: String)

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")
const COMPATIBILITY_GRID_SIZE: int = 129

var _terrain: TerrainNode
var _camera: Camera3D
var _status_label: Label
var _diagnostic_label: Label
var _progress_bar: ProgressBar
var _renderer_button: Button
var _compatibility_preview: MeshInstance3D
var _yaw: float = -0.65
var _pitch: float = 0.72
var _distance: float = 1150.0
var _target: Vector3 = Vector3(0.0, 80.0, 0.0)
var _using_compatibility_preview: bool = true
var _terrain_ready: bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.55, 0.76, 0.92))
	_create_lighting()
	_create_camera()
	_create_interface()
	_create_terrain()
	_update_camera()


func _create_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	add_child(sun)

	var environment_node := WorldEnvironment.new()
	environment_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.76, 0.92)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.76, 0.84)
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	add_child(environment_node)


func _create_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "OrbitCamera"
	_camera.current = true
	_camera.fov = 62.0
	_camera.near = 0.5
	_camera.far = 10000.0
	add_child(_camera)


func _create_interface() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "DemoUI"
	add_child(canvas)

	var info_panel := PanelContainer.new()
	info_panel.position = Vector2(18.0, 18.0)
	info_panel.size = Vector2(560.0, 168.0)
	canvas.add_child(info_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	info_panel.add_child(margin)

	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 6)
	margin.add_child(info_box)

	var title := Label.new()
	title.text = "IslandTerrain 0.5 — Telefon Testi v2"
	title.add_theme_font_size_override("font_size", 22)
	info_box.add_child(title)

	_status_label = Label.new()
	_status_label.text = "Ada sistemi hazırlanıyor..."
	_status_label.add_theme_font_size_override("font_size", 17)
	info_box.add_child(_status_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	_progress_bar.show_percentage = true
	_progress_bar.custom_minimum_size = Vector2(510.0, 24.0)
	info_box.add_child(_progress_bar)

	_diagnostic_label = Label.new()
	_diagnostic_label.text = "Render doğrulaması bekleniyor..."
	_diagnostic_label.add_theme_font_size_override("font_size", 14)
	info_box.add_child(_diagnostic_label)

	var hint := Label.new()
	hint.text = "Ekranı sürükle: döndür • Düğmeler: yakınlaştır / görünüm değiştir"
	hint.position = Vector2(20.0, 194.0)
	hint.add_theme_font_size_override("font_size", 16)
	canvas.add_child(hint)

	_renderer_button = Button.new()
	_renderer_button.text = "Clipmap Testi"
	_renderer_button.disabled = true
	_renderer_button.anchor_left = 1.0
	_renderer_button.anchor_right = 1.0
	_renderer_button.offset_left = -192.0
	_renderer_button.offset_top = 18.0
	_renderer_button.offset_right = -18.0
	_renderer_button.offset_bottom = 78.0
	_renderer_button.add_theme_font_size_override("font_size", 17)
	_renderer_button.pressed.connect(_toggle_renderer_mode)
	canvas.add_child(_renderer_button)

	var controls := HBoxContainer.new()
	controls.anchor_left = 1.0
	controls.anchor_top = 1.0
	controls.anchor_right = 1.0
	controls.anchor_bottom = 1.0
	controls.offset_left = -356.0
	controls.offset_top = -90.0
	controls.offset_right = -18.0
	controls.offset_bottom = -18.0
	controls.add_theme_constant_override("separation", 10)
	canvas.add_child(controls)

	var zoom_out := Button.new()
	zoom_out.text = "− Uzak"
	zoom_out.custom_minimum_size = Vector2(102.0, 64.0)
	zoom_out.add_theme_font_size_override("font_size", 18)
	zoom_out.pressed.connect(_zoom_out)
	controls.add_child(zoom_out)

	var reset := Button.new()
	reset.text = "Sıfırla"
	reset.custom_minimum_size = Vector2(102.0, 64.0)
	reset.add_theme_font_size_override("font_size", 18)
	reset.pressed.connect(_reset_camera)
	controls.add_child(reset)

	var zoom_in := Button.new()
	zoom_in.text = "+ Yakın"
	zoom_in.custom_minimum_size = Vector2(102.0, 64.0)
	zoom_in.add_theme_font_size_override("font_size", 18)
	zoom_in.pressed.connect(_zoom_in)
	controls.add_child(zoom_in)


func _create_terrain() -> void:
	_terrain = TerrainNode.new()
	_terrain.name = "IslandTerrain3D"
	_terrain.device_profile = 1
	_terrain.generate_preview_on_ready = true
	_terrain.collision_enabled = false
	_terrain.preview_generation_progress.connect(_on_generation_progress)
	_terrain.preview_generation_stage_changed.connect(_on_generation_stage_changed)
	_terrain.preview_generation_completed.connect(_on_generation_completed)
	_terrain.preview_generation_failed.connect(_on_generation_failed)
	add_child(_terrain)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch + event.relative.y * 0.004, 0.18, 1.38)
		_update_camera()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_yaw -= event.relative.x * 0.005
		_pitch = clampf(_pitch + event.relative.y * 0.004, 0.18, 1.38)
		_update_camera()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_out()


func _update_camera() -> void:
	if _camera == null:
		return
	var horizontal: float = cos(_pitch)
	var offset := Vector3(
		sin(_yaw) * horizontal,
		sin(_pitch),
		cos(_yaw) * horizontal
	) * _distance
	_camera.global_position = _target + offset
	_camera.look_at(_target, Vector3.UP)


func _zoom_in() -> void:
	_distance = maxf(180.0, _distance * 0.78)
	_update_camera()


func _zoom_out() -> void:
	_distance = minf(4800.0, _distance * 1.28)
	_update_camera()


func _reset_camera() -> void:
	_yaw = -0.65
	_pitch = 0.72
	_distance = 1720.0 if _terrain_ready else 1150.0
	_update_camera()


func _toggle_renderer_mode() -> void:
	if not _terrain_ready:
		return
	_using_compatibility_preview = not _using_compatibility_preview
	_apply_renderer_mode()


func _apply_renderer_mode() -> void:
	var clipmap := _get_clipmap_node()
	if _compatibility_preview != null:
		_compatibility_preview.visible = _using_compatibility_preview
	if clipmap != null:
		clipmap.visible = not _using_compatibility_preview
	if _using_compatibility_preview:
		_renderer_button.text = "Clipmap Testi"
		_status_label.text = "Ada hazır • Telefon uyumluluk görünümü"
	else:
		_renderer_button.text = "Uyumlu Görünüm"
		_status_label.text = "Clipmap renderer testi aktif"


func _get_clipmap_node() -> Node3D:
	if _terrain == null:
		return null
	return _terrain.get_node_or_null("__IslandClipmap") as Node3D


func _on_generation_progress(progress: float) -> void:
	if _progress_bar != null:
		_progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0


func _on_generation_stage_changed(stage_name: String) -> void:
	if _status_label != null:
		_status_label.text = "Üretiliyor: %s" % stage_name


func _on_generation_completed() -> void:
	if _progress_bar != null:
		_progress_bar.value = 100.0
	if _status_label != null:
		_status_label.text = "Görünür telefon önizlemesi oluşturuluyor..."
	call_deferred("_finish_generation_setup")


func _finish_generation_setup() -> void:
	var error: Error = _build_compatibility_preview()
	if error != OK:
		_on_generation_failed("Görünür önizleme kurulamadı: %d" % error)
		return
	var center_height: float = _terrain.get_height_at_world(Vector3.ZERO)
	_target.y = center_height * 0.35 + 35.0
	_distance = 1720.0
	_update_camera()
	_terrain_ready = true
	_using_compatibility_preview = true
	_renderer_button.disabled = false
	_apply_renderer_mode()
	var clipmap := _get_clipmap_node()
	var clipmap_levels: int = clipmap.get_child_count() if clipmap != null else 0
	_diagnostic_label.text = "Görünür mesh: %d tepe • Clipmap: %d seviye" % [
		get_compatibility_vertex_count(),
		clipmap_levels,
	]
	demo_ready.emit()


func _build_compatibility_preview() -> Error:
	var result = _terrain.get_generation_result()
	if result == null or _terrain.manifest == null:
		return ERR_UNCONFIGURED
	var result_errors: PackedStringArray = result.validate()
	if not result_errors.is_empty():
		return ERR_INVALID_DATA

	var grid_size: int = mini(COMPATIBILITY_GRID_SIZE, result.resolution)
	if grid_size < 3:
		return ERR_INVALID_DATA
	var vertex_count: int = grid_size * grid_size
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	uvs.resize(vertex_count)

	var world_size: float = float(_terrain.manifest.world_size_m)
	var half_world: float = world_size * 0.5
	var max_height: float = _terrain.manifest.max_height_m
	var sea_level: float = _terrain.manifest.sea_level_m
	var sample_step: float = world_size / float(grid_size - 1)
	for z in range(grid_size):
		for x in range(grid_size):
			var vertex_index: int = z * grid_size + x
			var source_x: int = roundi(float(x) * float(result.resolution - 1) / float(grid_size - 1))
			var source_z: int = roundi(float(z) * float(result.resolution - 1) / float(grid_size - 1))
			var source_index: int = source_z * result.resolution + source_x
			var height_m: float = sea_level + result.height_data[source_index] * max_height
			vertices[vertex_index] = Vector3(
				-half_world + float(x) * sample_step,
				height_m + 0.35,
				-half_world + float(z) * sample_step
			)
			uvs[vertex_index] = Vector2(
				float(x) / float(grid_size - 1),
				float(z) / float(grid_size - 1)
			)
			var left_x: int = maxi(0, source_x - 1)
			var right_x: int = mini(result.resolution - 1, source_x + 1)
			var down_z: int = maxi(0, source_z - 1)
			var up_z: int = mini(result.resolution - 1, source_z + 1)
			var h_l: float = result.height_data[source_z * result.resolution + left_x] * max_height
			var h_r: float = result.height_data[source_z * result.resolution + right_x] * max_height
			var h_d: float = result.height_data[down_z * result.resolution + source_x] * max_height
			var h_u: float = result.height_data[up_z * result.resolution + source_x] * max_height
			normals[vertex_index] = Vector3(h_l - h_r, sample_step * 2.0, h_d - h_u).normalized()
			var elevation: float = clampf(result.height_data[source_index], 0.0, 1.0)
			colors[vertex_index] = _biome_color(int(result.biome_data[source_index])).lightened(elevation * 0.08)

	indices.resize((grid_size - 1) * (grid_size - 1) * 6)
	var write_index: int = 0
	for z in range(grid_size - 1):
		for x in range(grid_size - 1):
			var a: int = z * grid_size + x
			var b: int = a + 1
			var c: int = a + grid_size
			var d: int = c + 1
			indices[write_index] = a
			indices[write_index + 1] = c
			indices[write_index + 2] = b
			indices[write_index + 3] = b
			indices[write_index + 4] = c
			indices[write_index + 5] = d
			write_index += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() == 0:
		return ERR_CANT_CREATE

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.96
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	mesh.surface_set_material(0, material)

	_compatibility_preview = MeshInstance3D.new()
	_compatibility_preview.name = "PhoneCompatibilityPreview"
	_compatibility_preview.mesh = mesh
	_compatibility_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_compatibility_preview.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_compatibility_preview)
	_compatibility_preview.global_position = _terrain.global_position
	return OK


func _biome_color(biome: int) -> Color:
	match biome:
		0:
			return Color(0.08, 0.24, 0.38)
		1:
			return Color(0.76, 0.67, 0.43)
		2:
			return Color(0.26, 0.47, 0.17)
		3:
			return Color(0.09, 0.29, 0.10)
		4:
			return Color(0.22, 0.32, 0.16)
		5:
			return Color(0.42, 0.48, 0.25)
		6:
			return Color(0.63, 0.64, 0.61)
		7:
			return Color(0.34, 0.34, 0.33)
	return Color(0.30, 0.45, 0.20)


func has_visible_preview_geometry() -> bool:
	if _compatibility_preview == null or _compatibility_preview.mesh == null:
		return false
	if _compatibility_preview.mesh.get_surface_count() <= 0:
		return false
	var bounds: AABB = _compatibility_preview.get_aabb()
	return bounds.size.x > 1000.0 and bounds.size.z > 1000.0 and bounds.size.y > 1.0


func get_compatibility_vertex_count() -> int:
	if _compatibility_preview == null or _compatibility_preview.mesh == null:
		return 0
	if _compatibility_preview.mesh.get_surface_count() <= 0:
		return 0
	var arrays: Array = _compatibility_preview.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	return vertices.size()


func _on_generation_failed(message: String) -> void:
	if _status_label != null:
		_status_label.text = "Ada üretilemedi: %s" % message
	if _diagnostic_label != null:
		_diagnostic_label.text = "İlk kırmızı Godot hatasını gönder."
	demo_failed.emit(message)
