@tool
extends VBoxContainer
class_name IslandTerrainToolsPanel

signal generate_island_requested(settings: Dictionary)
signal diagnostics_refresh_requested

const Style = preload("res://addons/island_terrain/editor/terrain_editor_style.gd")

var _tabs: TabContainer
var _map_scroll: ScrollContainer
var _sculpt_scroll: ScrollContainer
var _paint_scroll: ScrollContainer
var _diagnostics_scroll: ScrollContainer
var _terrain_name: Label
var _terrain_state: Label
var _status: Label
var _generation_progress: ProgressBar
var _preset_selector: OptionButton
var _seed: SpinBox
var _max_height: SpinBox
var _erosion: SpinBox
var _rivers: CheckButton
var _diagnostic_labels: Dictionary = {}


func configure(sculpt_toolbar: Control, paint_toolbar: Control) -> void:
	name = "IslandTerrain"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 360.0 * Style.editor_scale())
	add_theme_constant_override("separation", int(8.0 * Style.editor_scale()))
	add_theme_stylebox_override("panel", Style.make_panel_style(Style.COLOR_PANEL, 0.0))

	_build_header()
	_build_tabs()
	_build_map_tab()
	_build_diagnostics_tab()

	sculpt_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sculpt_scroll.add_child(sculpt_toolbar)
	_paint_scroll.add_child(paint_toolbar)
	_build_footer()


func set_terrain(terrain_name: String, snapshot: Dictionary = {}) -> void:
	if _terrain_name != null:
		_terrain_name.text = terrain_name
	if _terrain_state != null:
		_terrain_state.text = "HAZIR"
		_terrain_state.add_theme_color_override("font_color", Style.COLOR_SUCCESS)
	if not snapshot.is_empty():
		update_metrics(snapshot)
	set_message("Düz authoring yüzeyi seçildi · araçlar hazır")


func clear_terrain() -> void:
	if _terrain_name != null:
		_terrain_name.text = "Terrain seçilmedi"
	if _terrain_state != null:
		_terrain_state.text = "BEKLEMEDE"
		_terrain_state.add_theme_color_override("font_color", Style.COLOR_TEXT_MUTED)
	set_message("Sahne ağacından IslandTerrain3D seç")


func set_message(message: String, warning: bool = false) -> void:
	if _status != null:
		_status.text = message
		_status.add_theme_color_override(
			"font_color",
			Style.COLOR_WARNING if warning else Style.COLOR_TEXT_MUTED
		)


func set_generation_progress(progress: float, stage_name: String) -> void:
	if _generation_progress == null:
		return
	var normalized: float = clampf(progress, 0.0, 1.0)
	_generation_progress.value = normalized * 100.0
	_generation_progress.visible = normalized > 0.0 and normalized < 1.0
	if _terrain_state != null:
		_terrain_state.text = "ÜRETİLİYOR" if normalized < 1.0 else "HAZIR"
		_terrain_state.add_theme_color_override(
			"font_color",
			Style.COLOR_WARNING if normalized < 1.0 else Style.COLOR_SUCCESS
		)
	set_message("%s · %d%%" % [stage_name, roundi(normalized * 100.0)])


func update_metrics(metrics: Dictionary) -> void:
	_set_metric("world", "%s m" % _format_integer(int(metrics.get("world_size_m", 0))))
	_set_metric("height", "%.1f m" % float(metrics.get("max_height_m", 0.0)))
	_set_metric("resolution", str(metrics.get("macro_resolution", "—")))
	_set_metric("regions", str(metrics.get("region_axis", "—")))
	_set_metric("clipmap", str(metrics.get("clipmap_levels", "—")))
	_set_metric("collision", str(metrics.get("collision_patches", 0)))
	_set_metric("generation_memory", _format_bytes(int(metrics.get("generation_memory_bytes", 0))))
	_set_metric("material_memory", _format_bytes(int(metrics.get("material_memory_bytes", 0))))
	_set_metric("quality", str(metrics.get("quality_level", 0)))
	_set_metric("stage", str(metrics.get("generation_stage", "Idle")))


func generation_settings() -> Dictionary:
	return {
		"preset": _preset_selector.get_selected_id() if _preset_selector != null else 0,
		"seed": int(_seed.value) if _seed != null else 1,
		"max_height_m": float(_max_height.value) if _max_height != null else 512.0,
		"thermal_iterations": int(_erosion.value) if _erosion != null else 2,
		"rivers_enabled": _rivers.button_pressed if _rivers != null else true,
	}


func select_map_tab() -> void:
	_tabs.current_tab = 0


func select_sculpt_tab() -> void:
	_tabs.current_tab = 1


func select_paint_tab() -> void:
	_tabs.current_tab = 2


func select_diagnostics_tab() -> void:
	_tabs.current_tab = 3


func _build_header() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.make_panel_style(Style.COLOR_CARD, 8.0))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(12.0 * Style.editor_scale()))
	panel.add_child(row)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(identity)
	var product := Label.new()
	product.text = "ISLANDTERRAIN  AUTHORING"
	product.add_theme_font_size_override("font_size", int(18.0 * Style.editor_scale()))
	product.add_theme_color_override("font_color", Style.COLOR_ACCENT)
	identity.add_child(product)
	_terrain_name = Label.new()
	_terrain_name.text = "Terrain seçilmedi"
	_terrain_name.add_theme_font_size_override("font_size", int(14.0 * Style.editor_scale()))
	identity.add_child(_terrain_name)

	_terrain_state = Style.make_chip("BEKLEMEDE", Style.COLOR_TEXT_MUTED)
	row.add_child(_terrain_state)

	var refresh := Style.make_action_button("Analizi Yenile")
	refresh.custom_minimum_size.x = 156.0 * Style.editor_scale()
	refresh.pressed.connect(func() -> void: diagnostics_refresh_requested.emit())
	row.add_child(refresh)

	_generation_progress = ProgressBar.new()
	_generation_progress.min_value = 0.0
	_generation_progress.max_value = 100.0
	_generation_progress.show_percentage = false
	_generation_progress.visible = false
	_generation_progress.custom_minimum_size.y = 5.0 * Style.editor_scale()
	add_child(_generation_progress)


func _build_tabs() -> void:
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)
	_map_scroll = _create_tab("Oluştur")
	_sculpt_scroll = _create_tab("Şekillendir")
	_paint_scroll = _create_tab("Boya")
	_diagnostics_scroll = _create_tab("Analiz")


func _build_map_tab() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", int(10.0 * Style.editor_scale()))
	_map_scroll.add_child(root)

	var workflow: Dictionary = Style.make_card(
		"Harita Başlangıcı",
		"Düz yüzey üzerinde elle çalış veya üretim profiliyle başlangıç adası oluştur. Runtime kazma bu authoring aracından ayrıdır."
	)
	root.add_child(workflow["panel"])
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", int(10.0 * Style.editor_scale()))
	workflow["content"].add_child(mode_row)
	var flat_chip := Style.make_chip("DÜZ MAP AKTİF", Style.COLOR_SUCCESS)
	flat_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(flat_chip)
	var note := Label.new()
	note.text = "Yeni IslandTerrain3D otomatik ada üretmez."
	note.add_theme_color_override("font_color", Style.COLOR_TEXT_MUTED)
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mode_row.add_child(note)

	var generation: Dictionary = Style.make_card(
		"Prosedürel Başlangıç",
		"Bu işlem yalnız yeni ve düzenlenmemiş map için önerilir. Sonrasında bütün detayları fırçalarla kontrol edebilirsin."
	)
	root.add_child(generation["panel"])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(12.0 * Style.editor_scale()))
	grid.add_theme_constant_override("v_separation", int(8.0 * Style.editor_scale()))
	generation["content"].add_child(grid)

	_preset_selector = OptionButton.new()
	_preset_selector.add_item("Doğal Ada", 0)
	_preset_selector.add_item("Dağlık Ada", 1)
	_preset_selector.add_item("Takımada", 2)
	_preset_selector.add_item("Geniş Ovalar", 3)
	grid.add_child(_labeled_control("Üretim profili", _preset_selector))

	_seed = _make_spin_box(1.0, 2147483647.0, 1.0, 19077.0, "")
	_seed.rounded = true
	grid.add_child(_labeled_control("Dünya seed", _seed))

	_max_height = _make_spin_box(32.0, 2048.0, 1.0, 512.0, " m")
	grid.add_child(_labeled_control("Maksimum yükseklik", _max_height))

	_erosion = _make_spin_box(0.0, 8.0, 1.0, 2.0, " tur")
	_erosion.rounded = true
	grid.add_child(_labeled_control("Termal erozyon", _erosion))

	_rivers = CheckButton.new()
	_rivers.text = "Nehir üretimi"
	_rivers.button_pressed = true
	_rivers.custom_minimum_size.y = 44.0 * Style.editor_scale()
	grid.add_child(_labeled_control("Hidrografi", _rivers))

	var generate := Style.make_action_button("PROSEDÜREL ADA ÜRET", true)
	generate.pressed.connect(func() -> void: generate_island_requested.emit(generation_settings()))
	generation["content"].add_child(generate)

	var pipeline: Dictionary = Style.make_card("Üretim Zinciri")
	root.add_child(pipeline["panel"])
	var pipeline_label := Label.new()
	pipeline_label.text = "Kıyı maskesi  →  Makro yükseklik  →  Ridge  →  Termal erozyon  →  Akış  →  Nehir  →  Nem  →  Biyom  →  Materyal metadata"
	pipeline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pipeline_label.add_theme_color_override("font_color", Style.COLOR_TEXT_MUTED)
	pipeline["content"].add_child(pipeline_label)


func _build_diagnostics_tab() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", int(10.0 * Style.editor_scale()))
	_diagnostics_scroll.add_child(root)

	var overview: Dictionary = Style.make_card(
		"Canlı Terrain Telemetrisi",
		"Editör ve telefon bütçelerini takip ederek map büyürken erken performans problemi yakala."
	)
	root.add_child(overview["panel"])
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(10.0 * Style.editor_scale()))
	grid.add_theme_constant_override("v_separation", int(10.0 * Style.editor_scale()))
	overview["content"].add_child(grid)
	_add_metric(grid, "world", "Dünya boyutu")
	_add_metric(grid, "height", "Yükseklik tavanı")
	_add_metric(grid, "resolution", "Macro çözünürlük")
	_add_metric(grid, "regions", "Region ekseni")
	_add_metric(grid, "clipmap", "Clipmap LOD")
	_add_metric(grid, "collision", "Aktif collision")
	_add_metric(grid, "generation_memory", "Generation RAM")
	_add_metric(grid, "material_memory", "Material RAM")
	_add_metric(grid, "quality", "Kalite düşürme")
	_add_metric(grid, "stage", "Generation aşaması")

	var safety: Dictionary = Style.make_card(
		"Mobil Güvenlik",
		"Tam dünya mesh'i, tam dünya collision'ı veya bütün foliage transformları aynı anda bellekte tutulmaz."
	)
	root.add_child(safety["panel"])
	var safety_text := Label.new()
	safety_text.text = "Region streaming · Frame-budgeted clipmap · Sparse edit kanalları · Pooled collision · Bounded undo · Runtime watchdog"
	safety_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	safety_text.add_theme_color_override("font_color", Style.COLOR_SUCCESS)
	safety["content"].add_child(safety_text)


func _build_footer() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.make_panel_style(Style.COLOR_CARD_ALT, 6.0))
	add_child(panel)
	_status = Label.new()
	_status.text = "Sahne ağacından IslandTerrain3D seç"
	_status.add_theme_color_override("font_color", Style.COLOR_TEXT_MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)


func _create_tab(tab_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_tabs.add_child(scroll)
	return scroll


func _add_metric(parent: GridContainer, key: String, label_text: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.make_panel_style(Style.COLOR_CARD_ALT, 6.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var label := Style.make_section_label(label_text)
	box.add_child(label)
	var value := Label.new()
	value.text = "—"
	value.add_theme_font_size_override("font_size", int(18.0 * Style.editor_scale()))
	box.add_child(value)
	_diagnostic_labels[key] = value


func _set_metric(key: String, value: String) -> void:
	var label: Label = _diagnostic_labels.get(key) as Label
	if label != null:
		label.text = value


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
	return spin


func _labeled_control(label_text: String, control: Control) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Style.make_section_label(label_text)
	container.add_child(label)
	control.custom_minimum_size.y = 42.0 * Style.editor_scale()
	container.add_child(control)
	return container


func _format_integer(value: int) -> String:
	var text := str(value)
	var output := ""
	while text.length() > 3:
		output = ".%s%s" % [text.right(3), output]
		text = text.left(text.length() - 3)
	return text + output


func _format_bytes(bytes: int) -> String:
	if bytes >= 1024 * 1024:
		return "%.1f MB" % (float(bytes) / float(1024 * 1024))
	if bytes >= 1024:
		return "%.1f KB" % (float(bytes) / 1024.0)
	return "%d B" % bytes
