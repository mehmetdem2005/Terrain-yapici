@tool
extends VBoxContainer
class_name IslandTerrainPaintToolbar

signal undo_requested
signal redo_requested
signal paint_mode_changed(enabled: bool)
signal brush_settings_changed
signal tool_changed(tool: int)

const PaintCommand = preload("res://addons/island_terrain/application/terrain_paint_command.gd")
const Style = preload("res://addons/island_terrain/editor/terrain_editor_style.gd")

const BIOME_COLORS := [
	Color(0.08, 0.24, 0.38), Color(0.76, 0.67, 0.43), Color(0.26, 0.47, 0.17),
	Color(0.09, 0.29, 0.10), Color(0.22, 0.32, 0.16), Color(0.42, 0.48, 0.25),
	Color(0.63, 0.64, 0.61), Color(0.34, 0.34, 0.33),
]
const MATERIAL_COLORS := [
	Color(0.72, 0.62, 0.40), Color(0.25, 0.39, 0.14), Color(0.10, 0.24, 0.09),
	Color(0.18, 0.24, 0.13), Color(0.36, 0.35, 0.33), Color(0.58, 0.59, 0.57),
]

var _enabled_toggle: CheckButton
var _tool_group: ButtonGroup
var _selected_tool: int = PaintCommand.Tool.BIOME
var _biome_selector: OptionButton
var _material_selector: OptionButton
var _swatch: ColorRect
var _radius_slider: HSlider
var _radius: SpinBox
var _strength_slider: HSlider
var _strength: SpinBox
var _falloff: SpinBox
var _spacing: SpinBox
var _target_box: VBoxContainer
var _status: Label


func _ready() -> void:
	name = "Terrain Paint"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 0.0)
	add_theme_constant_override("separation", int(10.0 * Style.editor_scale()))
	_build_ui()
	_refresh_target_state()


func is_paint_enabled() -> bool:
	return _enabled_toggle != null and _enabled_toggle.button_pressed


func selected_tool() -> int:
	return _selected_tool


func selected_biome() -> int:
	return _biome_selector.get_selected_id() if _biome_selector != null else 2


func selected_material() -> int:
	return _material_selector.get_selected_id() if _material_selector != null else 1


func brush_radius_m() -> float:
	return float(_radius.value) if _radius != null else 8.0


func brush_strength() -> float:
	return float(_strength.value) if _strength != null else 0.65


func falloff_exponent() -> float:
	return float(_falloff.value) if _falloff != null else 2.0


func spacing_ratio() -> float:
	return float(_spacing.value) if _spacing != null else 0.20


func brush_color() -> Color:
	match _selected_tool:
		PaintCommand.Tool.BIOME:
			return BIOME_COLORS[clampi(selected_biome(), 0, BIOME_COLORS.size() - 1)]
		PaintCommand.Tool.MATERIAL:
			return MATERIAL_COLORS[clampi(selected_material(), 0, MATERIAL_COLORS.size() - 1)]
		PaintCommand.Tool.ERASE_BIOME, PaintCommand.Tool.ERASE_MATERIAL, PaintCommand.Tool.ERASE_ALL:
			return Color(1.0, 0.36, 0.34, 1.0)
	return Style.COLOR_ACCENT


func set_terrain_name(terrain_name: String) -> void:
	set_message("Hazır · %s" % terrain_name)


func set_message(message: String) -> void:
	if _status != null:
		_status.text = message


func disable_paint() -> void:
	if _enabled_toggle != null:
		_enabled_toggle.button_pressed = false


func _build_ui() -> void:
	if get_child_count() > 0:
		return
	_build_mode_header()
	_build_tool_card()
	_build_target_card()
	_build_brush_card()
	_build_history_card()


func _build_mode_header() -> void:
	var card: Dictionary = Style.make_card(
		"Yüzey Boyama Atölyesi",
		"Biyom ve fiziksel zemin katmanlarını prosedürel tabanı bozmadan override et."
	)
	add_child(card.panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(12.0 * Style.editor_scale()))
	card.content.add_child(row)

	_enabled_toggle = CheckButton.new()
	_enabled_toggle.text = "Boyama Aktif"
	_enabled_toggle.custom_minimum_size = Vector2(220.0, 48.0) * Style.editor_scale()
	_enabled_toggle.toggled.connect(_on_mode_toggled)
	row.add_child(_enabled_toggle)

	_status = Style.make_chip("IslandTerrain3D seç", Style.COLOR_TEXT_MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(_status)


func _build_tool_card() -> void:
	var card: Dictionary = Style.make_card("Katman İşlemi", "Boya veya prosedürel veriye geri dön.")
	add_child(card.panel)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(8.0 * Style.editor_scale()))
	grid.add_theme_constant_override("v_separation", int(8.0 * Style.editor_scale()))
	card.content.add_child(grid)
	_tool_group = ButtonGroup.new()
	_add_tool_button(grid, "Biyom", PaintCommand.Tool.BIOME)
	_add_tool_button(grid, "Malzeme", PaintCommand.Tool.MATERIAL)
	_add_tool_button(grid, "Biyomu Sil", PaintCommand.Tool.ERASE_BIOME)
	_add_tool_button(grid, "Malzemeyi Sil", PaintCommand.Tool.ERASE_MATERIAL)
	_add_tool_button(grid, "Tümünü Geri Yükle", PaintCommand.Tool.ERASE_ALL)


func _build_target_card() -> void:
	var card: Dictionary = Style.make_card("Hedef Katman", "Seçilen biyom veya malzeme fırça renginde sahnede önizlenir.")
	add_child(card.panel)
	_target_box = VBoxContainer.new()
	_target_box.add_theme_constant_override("separation", int(8.0 * Style.editor_scale()))
	card.content.add_child(_target_box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(12.0 * Style.editor_scale()))
	_target_box.add_child(row)

	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(52.0, 52.0) * Style.editor_scale()
	_swatch.color = BIOME_COLORS[2]
	row.add_child(_swatch)

	var selectors := GridContainer.new()
	selectors.columns = 2
	selectors.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selectors.add_theme_constant_override("h_separation", int(12.0 * Style.editor_scale()))
	row.add_child(selectors)

	_biome_selector = OptionButton.new()
	for entry in [
		["Okyanus", 0], ["Sahil", 1], ["Çayır", 2], ["Orman", 3],
		["Sulak Alan", 4], ["Yayla", 5], ["Dağ", 6], ["Uçurum", 7],
	]:
		_biome_selector.add_item(entry[0], entry[1])
	_biome_selector.select(2)
	_biome_selector.item_selected.connect(func(_index: int) -> void:
		_refresh_swatch()
		brush_settings_changed.emit()
	)
	selectors.add_child(_labeled_control("Biyom", _biome_selector))

	_material_selector = OptionButton.new()
	for entry in [
		["Kum", 0], ["Çim", 1], ["Orman Zemini", 2],
		["Sulak Zemin", 3], ["Kaya", 4], ["Dağ", 5],
	]:
		_material_selector.add_item(entry[0], entry[1])
	_material_selector.select(1)
	_material_selector.item_selected.connect(func(_index: int) -> void:
		_refresh_swatch()
		brush_settings_changed.emit()
	)
	selectors.add_child(_labeled_control("Malzeme", _material_selector))


func _build_brush_card() -> void:
	var card: Dictionary = Style.make_card("Fırça", "Yumuşak geçişlerle doğal katman dağılımı oluştur.")
	add_child(card.panel)
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", int(8.0 * Style.editor_scale()))
	card.content.add_child(presets)
	for preset in [["Detay 4 m", 4.0], ["Alan 24 m", 24.0], ["Bölge 96 m", 96.0]]:
		var button := Style.make_action_button(preset[0])
		button.pressed.connect(_set_radius.bind(float(preset[1])))
		presets.add_child(button)

	_radius = _make_spin_box(1.0, 256.0, 0.5, 24.0, " m")
	_radius_slider = _make_slider(1.0, 256.0, 0.5, 24.0)
	_link_slider_and_spin(_radius_slider, _radius)
	card.content.add_child(_make_parameter_row("Yarıçap", _radius_slider, _radius))

	_strength = _make_spin_box(0.01, 1.0, 0.01, 0.65, "")
	_strength_slider = _make_slider(0.01, 1.0, 0.01, 0.65)
	_link_slider_and_spin(_strength_slider, _strength)
	card.content.add_child(_make_parameter_row("Karışım", _strength_slider, _strength))

	var compact := GridContainer.new()
	compact.columns = 2
	compact.add_theme_constant_override("h_separation", int(12.0 * Style.editor_scale()))
	card.content.add_child(compact)
	_falloff = _make_spin_box(0.25, 8.0, 0.25, 2.0, "")
	compact.add_child(_labeled_control("Falloff", _falloff))
	_spacing = _make_spin_box(0.05, 1.0, 0.05, 0.20, " × yarıçap")
	compact.add_child(_labeled_control("Stroke aralığı", _spacing))


func _build_history_card() -> void:
	var card: Dictionary = Style.make_card("Geçmiş", "Paint kanalları ayrı tutulur; geri alma diğer katmanı ezmez.")
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


func _add_tool_button(parent: GridContainer, text: String, tool: int) -> void:
	var button := Button.new()
	button.text = text
	button.button_group = _tool_group
	Style.style_tool_button(button)
	button.pressed.connect(_select_tool.bind(tool))
	parent.add_child(button)
	if tool == _selected_tool:
		button.button_pressed = true


func _select_tool(tool: int) -> void:
	_selected_tool = tool
	_refresh_target_state()
	_refresh_swatch()
	tool_changed.emit(tool)
	brush_settings_changed.emit()


func _refresh_target_state() -> void:
	if _biome_selector == null or _material_selector == null:
		return
	_biome_selector.disabled = _selected_tool != PaintCommand.Tool.BIOME
	_material_selector.disabled = _selected_tool != PaintCommand.Tool.MATERIAL


func _refresh_swatch() -> void:
	if _swatch != null:
		_swatch.color = brush_color()


func _on_mode_toggled(enabled: bool) -> void:
	paint_mode_changed.emit(enabled)
	set_message("Boyama aktif" if enabled else "Boyama kapalı")


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
	control.custom_minimum_size.y = 42.0 * Style.editor_scale()
	container.add_child(control)
	return container
