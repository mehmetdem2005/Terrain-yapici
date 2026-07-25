@tool
extends VBoxContainer
class_name IslandTerrainSculptToolbar

signal undo_requested
signal redo_requested
signal sculpt_mode_changed(enabled: bool)
signal brush_settings_changed
signal tool_changed(tool: int)

const SculptCommand = preload("res://addons/island_terrain/application/terrain_sculpt_command.gd")
const Style = preload("res://addons/island_terrain/editor/terrain_editor_style.gd")

var _enabled_toggle: CheckButton
var _tool_group: ButtonGroup
var _tool_buttons: Dictionary = {}
var _radius_slider: HSlider
var _radius: SpinBox
var _strength_slider: HSlider
var _strength: SpinBox
var _falloff: SpinBox
var _spacing: SpinBox
var _noise_scale: SpinBox
var _terrace_step: SpinBox
var _seed: SpinBox
var _advanced_box: VBoxContainer
var _tool_description: Label
var _status: Label
var _selected_tool: int = SculptCommand.Tool.RAISE


func _ready() -> void:
	name = "Terrain Sculpt"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 0.0)
	add_theme_constant_override("separation", int(10.0 * Style.editor_scale()))
	_build_ui()
	_refresh_tool_state()


func is_sculpt_enabled() -> bool:
	return _enabled_toggle != null and _enabled_toggle.button_pressed


func selected_tool() -> int:
	return _selected_tool


func brush_radius_m() -> float:
	return float(_radius.value) if _radius != null else 8.0


func brush_strength() -> float:
	return float(_strength.value) if _strength != null else 0.5


func falloff_exponent() -> float:
	return float(_falloff.value) if _falloff != null else 2.0


func spacing_ratio() -> float:
	return float(_spacing.value) if _spacing != null else 0.20


func noise_scale_m() -> float:
	return float(_noise_scale.value) if _noise_scale != null else 24.0


func terrace_step_m() -> float:
	return float(_terrace_step.value) if _terrace_step != null else 4.0


func random_seed() -> int:
	return int(_seed.value) if _seed != null else 1


func brush_color() -> Color:
	match _selected_tool:
		SculptCommand.Tool.RAISE:
			return Color(0.25, 0.72, 1.0, 1.0)
		SculptCommand.Tool.LOWER:
			return Color(1.0, 0.36, 0.32, 1.0)
		SculptCommand.Tool.SMOOTH:
			return Color(0.36, 0.88, 0.62, 1.0)
		SculptCommand.Tool.FLATTEN:
			return Color(1.0, 0.72, 0.24, 1.0)
		SculptCommand.Tool.NOISE:
			return Color(0.74, 0.46, 1.0, 1.0)
		SculptCommand.Tool.TERRACE:
			return Color(0.95, 0.52, 0.22, 1.0)
	return Style.COLOR_ACCENT


func set_terrain_name(terrain_name: String) -> void:
	set_message("Hazır · %s" % terrain_name)


func set_message(message: String) -> void:
	if _status != null:
		_status.text = message


func disable_sculpt() -> void:
	if _enabled_toggle != null:
		_enabled_toggle.button_pressed = false


func _build_ui() -> void:
	if get_child_count() > 0:
		return
	_build_mode_header()
	_build_tool_card()
	_build_brush_card()
	_build_advanced_card()
	_build_history_card()


func _build_mode_header() -> void:
	var card: Dictionary = Style.make_card(
		"Şekillendirme Atölyesi",
		"Yüksekliği gerçek zamanlı düzenle. Fırça halkası sahne üzerinde sonucu gösterir."
	)
	add_child(card.panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(12.0 * Style.editor_scale()))
	card.content.add_child(row)

	_enabled_toggle = CheckButton.new()
	_enabled_toggle.text = "Şekillendirme Aktif"
	_enabled_toggle.custom_minimum_size = Vector2(240.0, 48.0) * Style.editor_scale()
	_enabled_toggle.toggled.connect(_on_mode_toggled)
	row.add_child(_enabled_toggle)

	_status = Style.make_chip("IslandTerrain3D seç", Style.COLOR_TEXT_MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(_status)


func _build_tool_card() -> void:
	var card: Dictionary = Style.make_card("Araçlar", "Her araç farklı bir üretim problemi için optimize edilmiştir.")
	add_child(card.panel)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(8.0 * Style.editor_scale()))
	grid.add_theme_constant_override("v_separation", int(8.0 * Style.editor_scale()))
	card.content.add_child(grid)

	_tool_group = ButtonGroup.new()
	_add_tool_button(grid, "Yükselt", SculptCommand.Tool.RAISE, "Dağ, tepe ve kabartı")
	_add_tool_button(grid, "Alçalt", SculptCommand.Tool.LOWER, "Vadi, kanal ve çukur")
	_add_tool_button(grid, "Yumuşat", SculptCommand.Tool.SMOOTH, "Keskin geçişleri temizle")
	_add_tool_button(grid, "Düzleştir", SculptCommand.Tool.FLATTEN, "Seçilen kotu yay")
	_add_tool_button(grid, "Gürültü", SculptCommand.Tool.NOISE, "Doğal mikro varyasyon")
	_add_tool_button(grid, "Teras", SculptCommand.Tool.TERRACE, "Basamaklı arazi üret")

	_tool_description = Label.new()
	_tool_description.add_theme_color_override("font_color", Style.COLOR_TEXT_MUTED)
	_tool_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.content.add_child(_tool_description)


func _build_brush_card() -> void:
	var card: Dictionary = Style.make_card("Fırça", "Boyut ve etki dağılımını hızlıca kontrol et.")
	add_child(card.panel)

	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", int(8.0 * Style.editor_scale()))
	card.content.add_child(presets)
	for preset in [["Detay 4 m", 4.0], ["Orta 16 m", 16.0], ["Makro 64 m", 64.0]]:
		var button := Style.make_action_button(preset[0])
		button.pressed.connect(_set_radius.bind(float(preset[1])))
		presets.add_child(button)

	_radius = _make_spin_box(1.0, 256.0, 0.5, 16.0, " m")
	_radius_slider = _make_slider(1.0, 256.0, 0.5, 16.0)
	_link_slider_and_spin(_radius_slider, _radius)
	card.content.add_child(_make_parameter_row("Yarıçap", _radius_slider, _radius))

	_strength = _make_spin_box(0.01, 32.0, 0.05, 1.0, "")
	_strength_slider = _make_slider(0.01, 32.0, 0.05, 1.0)
	_link_slider_and_spin(_strength_slider, _strength)
	card.content.add_child(_make_parameter_row("Güç", _strength_slider, _strength))

	var compact := GridContainer.new()
	compact.columns = 2
	compact.add_theme_constant_override("h_separation", int(12.0 * Style.editor_scale()))
	card.content.add_child(compact)
	_falloff = _make_spin_box(0.25, 8.0, 0.25, 2.0, "")
	compact.add_child(_labeled_control("Falloff", _falloff))
	_spacing = _make_spin_box(0.05, 1.0, 0.05, 0.20, " × yarıçap")
	compact.add_child(_labeled_control("Stroke aralığı", _spacing))


func _build_advanced_card() -> void:
	var card: Dictionary = Style.make_card("Araç Ayarları", "Seçilen araca özel profesyonel kontroller.")
	add_child(card.panel)
	_advanced_box = VBoxContainer.new()
	_advanced_box.add_theme_constant_override("separation", int(8.0 * Style.editor_scale()))
	card.content.add_child(_advanced_box)

	_noise_scale = _make_spin_box(0.5, 512.0, 0.5, 24.0, " m")
	_advanced_box.add_child(_labeled_control("Gürültü ölçeği", _noise_scale))
	_terrace_step = _make_spin_box(0.25, 128.0, 0.25, 4.0, " m")
	_advanced_box.add_child(_labeled_control("Teras basamağı", _terrace_step))
	_seed = _make_spin_box(0.0, 2147483647.0, 1.0, 1.0, "")
	_seed.rounded = true
	_advanced_box.add_child(_labeled_control("Fırça seed", _seed))


func _build_history_card() -> void:
	var card: Dictionary = Style.make_card("Geçmiş", "Stroke bazlı, bellek sınırlandırılmış güvenli geri alma.")
	add_child(card.panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8.0 * Style.editor_scale()))
	card.content.add_child(row)
	var undo_button := Style.make_action_button("Geri Al")
	undo_button.pressed.connect(func() -> void: undo_requested.emit())
	row.add_child(undo_button)
	var redo_button := Style.make_action_button("Yinele")
	redo_button.pressed.connect(func() -> void: redo_requested.emit())
	row.add_child(redo_button)


func _add_tool_button(parent: GridContainer, text: String, tool: int, tooltip: String) -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.button_group = _tool_group
	Style.style_tool_button(button)
	button.pressed.connect(_select_tool.bind(tool))
	parent.add_child(button)
	_tool_buttons[tool] = button
	if tool == _selected_tool:
		button.button_pressed = true


func _select_tool(tool: int) -> void:
	_selected_tool = tool
	_refresh_tool_state()
	tool_changed.emit(tool)
	brush_settings_changed.emit()


func _refresh_tool_state() -> void:
	if _tool_description == null:
		return
	match _selected_tool:
		SculptCommand.Tool.RAISE:
			_tool_description.text = "Yükselt · Araziyi kontrollü şekilde yukarı iter. Büyük yarıçaplarda dağ kütlesi oluşturur."
		SculptCommand.Tool.LOWER:
			_tool_description.text = "Alçalt · Vadi, nehir yatağı ve çukur oluşturur."
		SculptCommand.Tool.SMOOTH:
			_tool_description.text = "Yumuşat · Komşu yükseklikleri dengeler; kırık yüzeyleri temizler."
		SculptCommand.Tool.FLATTEN:
			_tool_description.text = "Düzleştir · İlk dokunulan kotu hedef alır ve fırça alanına yayar."
		SculptCommand.Tool.NOISE:
			_tool_description.text = "Gürültü · Tekrarlanabilir seed ile doğal yüzey varyasyonu ekler."
		SculptCommand.Tool.TERRACE:
			_tool_description.text = "Teras · Yüksekliği belirlenen metre aralıklarına yumuşak biçimde oturtur."
	if _advanced_box != null:
		for child in _advanced_box.get_children():
			var control := child as Control
			if control != null:
				control.visible = false
		var noise_control := _advanced_box.get_child(0) as Control
		var terrace_control := _advanced_box.get_child(1) as Control
		var seed_control := _advanced_box.get_child(2) as Control
		if _selected_tool == SculptCommand.Tool.NOISE:
			noise_control.visible = true
			seed_control.visible = true
		elif _selected_tool == SculptCommand.Tool.TERRACE:
			terrace_control.visible = true


func _on_mode_toggled(enabled: bool) -> void:
	sculpt_mode_changed.emit(enabled)
	set_message("Şekillendirme aktif" if enabled else "Şekillendirme kapalı")


func _set_radius(value: float) -> void:
	_radius.value = value
	_radius_slider.value = value
	brush_settings_changed.emit()


func _link_slider_and_spin(slider: HSlider, spin: SpinBox) -> void:
	slider.value_changed.connect(func(value: float) -> void:
		if not is_equal_approx(spin.value, value):
			spin.value = value
		brush_settings_changed.emit()
	)
	spin.value_changed.connect(func(value: float) -> void:
		if not is_equal_approx(slider.value, value):
			slider.value = value
		brush_settings_changed.emit()
	)


func _make_parameter_row(label_text: String, slider: HSlider, spin: SpinBox) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10.0 * Style.editor_scale()))
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 110.0 * Style.editor_scale()
	row.add_child(label)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	spin.custom_minimum_size.x = 125.0 * Style.editor_scale()
	row.add_child(spin)
	return row


func _make_slider(minimum: float, maximum: float, step: float, default_value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = default_value
	slider.custom_minimum_size.y = 42.0 * Style.editor_scale()
	return slider


func _make_spin_box(
	minimum: float,
	maximum: float,
	step: float,
	default_value: float,
	suffix: String
) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = default_value
	spin.suffix = suffix
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.custom_minimum_size.y = 42.0 * Style.editor_scale()
	spin.value_changed.connect(func(_value: float) -> void: brush_settings_changed.emit())
	return spin


func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Style.make_section_label(label_text)
	container.add_child(label)
	container.add_child(control)
	return container
