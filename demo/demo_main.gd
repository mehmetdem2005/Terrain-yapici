extends Node3D

signal demo_ready
signal demo_failed(message: String)

const TerrainNode = preload("res://addons/island_terrain/island_terrain_3d.gd")

var _terrain: TerrainNode
var _camera: Camera3D
var _status_label: Label
var _progress_bar: ProgressBar
var _yaw: float = -0.65
var _pitch: float = 0.72
var _distance: float = 1150.0
var _target: Vector3 = Vector3(0.0, 80.0, 0.0)


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
	info_panel.size = Vector2(520.0, 132.0)
	canvas.add_child(info_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	info_panel.add_child(margin)

	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 7)
	margin.add_child(info_box)

	var title := Label.new()
	title.text = "IslandTerrain 0.5 — Telefon Testi"
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
	_progress_bar.custom_minimum_size = Vector2(470.0, 24.0)
	info_box.add_child(_progress_bar)

	var hint := Label.new()
	hint.text = "Ekranı sürükle: döndür • Alttaki düğmeler: yakınlaştır / sıfırla"
	hint.position = Vector2(20.0, 158.0)
	hint.add_theme_font_size_override("font_size", 16)
	canvas.add_child(hint)

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
	_distance = minf(3600.0, _distance * 1.28)
	_update_camera()


func _reset_camera() -> void:
	_yaw = -0.65
	_pitch = 0.72
	_distance = 1150.0
	_update_camera()


func _on_generation_progress(progress: float) -> void:
	if _progress_bar != null:
		_progress_bar.value = clampf(progress, 0.0, 1.0) * 100.0


func _on_generation_stage_changed(stage_name: String) -> void:
	if _status_label != null:
		_status_label.text = "Üretiliyor: %s" % stage_name


func _on_generation_completed() -> void:
	var center_height: float = _terrain.get_height_at_world(Vector3.ZERO)
	_target.y = center_height + 55.0
	_distance = 980.0
	_update_camera()
	if _progress_bar != null:
		_progress_bar.value = 100.0
	if _status_label != null:
		_status_label.text = "Ada hazır. Dokunup sürükleyerek incele."
	demo_ready.emit()


func _on_generation_failed(message: String) -> void:
	if _status_label != null:
		_status_label.text = "Ada üretilemedi: %s" % message
	demo_failed.emit(message)
