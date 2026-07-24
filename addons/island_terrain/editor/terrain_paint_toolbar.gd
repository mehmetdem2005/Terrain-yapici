@tool
extends VBoxContainer
class_name IslandTerrainPaintToolbar

signal undo_requested
signal redo_requested
signal paint_mode_changed(enabled: bool)

const PaintCommand = preload("res://addons/island_terrain/application/terrain_paint_command.gd")

var _enabled_toggle: CheckButton
var _tool_selector: OptionButton
var _biome_selector: OptionButton
var _material_selector: OptionButton
var _radius: SpinBox
var _strength: SpinBox
var _falloff: SpinBox
var _spacing: SpinBox
var _status: Label


func _ready() -> void:
	name = "Terrain Paint"
	custom_minimum_size = Vector2(280.0 * EditorInterface.get_editor_scale(), 0.0)
	_build_ui()


func is_paint_enabled() -> bool:
	return _enabled_toggle != null and _enabled_toggle.button_pressed


func selected_tool() -> int:
	return _tool_selector.get_selected_id() if _tool_selector != null else PaintCommand.Tool.BIOME


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


func set_terrain_name(terrain_name: String) -> void:
	if _status != null:
		_status.text = "Terrain: %s" % terrain_name


func set_message(message: String) -> void:
	if _status != null:
		_status.text = message


func disable_paint() -> void:
	if _enabled_toggle != null:
		_enabled_toggle.button_pressed = false


func _build_ui() -> void:
	if get_child_count() > 0:
		return
	var title := Label.new()
	title.text = "IslandTerrain Paint"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_enabled_toggle = CheckButton.new()
	_enabled_toggle.text = "Paint Modu"
	_enabled_toggle.custom_minimum_size.y = 52.0 * EditorInterface.get_editor_scale()
	_enabled_toggle.toggled.connect(func(enabled: bool) -> void: paint_mode_changed.emit(enabled))
	add_child(_enabled_toggle)

	_tool_selector = OptionButton.new()
	_tool_selector.add_item("Biyom Boya", PaintCommand.Tool.BIOME)
	_tool_selector.add_item("Malzeme Boya", PaintCommand.Tool.MATERIAL)
	_tool_selector.add_item("Biyomu Geri Yükle", PaintCommand.Tool.ERASE_BIOME)
	_tool_selector.add_item("Malzemeyi Geri Yükle", PaintCommand.Tool.ERASE_MATERIAL)
	_tool_selector.add_item("Tüm Paint'i Geri Yükle", PaintCommand.Tool.ERASE_ALL)
	_tool_selector.custom_minimum_size.y = 48.0 * EditorInterface.get_editor_scale()
	add_child(_labeled_control("Araç", _tool_selector))

	_biome_selector = OptionButton.new()
	for entry in [
		["Okyanus", 0], ["Sahil", 1], ["Çayır", 2], ["Orman", 3],
		["Sulak Alan", 4], ["Yayla", 5], ["Dağ", 6], ["Uçurum", 7],
	]:
		_biome_selector.add_item(entry[0], entry[1])
	_biome_selector.select(2)
	_biome_selector.custom_minimum_size.y = 48.0 * EditorInterface.get_editor_scale()
	add_child(_labeled_control("Biyom", _biome_selector))

	_material_selector = OptionButton.new()
	for entry in [
		["Kum", 0], ["Çim", 1], ["Orman Zemini", 2],
		["Sulak Zemin", 3], ["Kaya", 4], ["Dağ", 5],
	]:
		_material_selector.add_item(entry[0], entry[1])
	_material_selector.select(1)
	_material_selector.custom_minimum_size.y = 48.0 * EditorInterface.get_editor_scale()
	add_child(_labeled_control("Malzeme", _material_selector))

	_radius = _make_spin_box(1.0, 128.0, 0.5, 8.0, " m")
	add_child(_labeled_control("Yarıçap", _radius))
	_strength = _make_spin_box(0.01, 1.0, 0.05, 0.65, "")
	add_child(_labeled_control("Karışım Gücü", _strength))
	_falloff = _make_spin_box(0.25, 8.0, 0.25, 2.0, "")
	add_child(_labeled_control("Falloff", _falloff))
	_spacing = _make_spin_box(0.05, 1.0, 0.05, 0.20, " × radius")
	add_child(_labeled_control("Stroke Aralığı", _spacing))

	var history_row := HBoxContainer.new()
	var undo_button := Button.new()
	undo_button.text = "Geri Al"
	undo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo_button.custom_minimum_size.y = 52.0 * EditorInterface.get_editor_scale()
	undo_button.pressed.connect(func() -> void: undo_requested.emit())
	history_row.add_child(undo_button)
	var redo_button := Button.new()
	redo_button.text = "Yinele"
	redo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redo_button.custom_minimum_size.y = 52.0 * EditorInterface.get_editor_scale()
	redo_button.pressed.connect(func() -> void: redo_requested.emit())
	history_row.add_child(redo_button)
	add_child(history_row)

	_status = Label.new()
	_status.text = "IslandTerrain3D seç"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	var help := Label.new()
	help.text = "Paint açıkken tek parmak/sol tık biyom veya malzeme override'ı yazar. Silme araçları prosedürel tabana geri döndürür."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)


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
	spin.custom_minimum_size.y = 46.0 * EditorInterface.get_editor_scale()
	return spin


func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var container := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	container.add_child(label)
	container.add_child(control)
	return container
