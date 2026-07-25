@tool
extends TabContainer
class_name IslandTerrainToolsPanel

signal generate_island_requested

var _map_scroll: ScrollContainer
var _sculpt_scroll: ScrollContainer
var _paint_scroll: ScrollContainer
var _terrain_status: Label


func configure(sculpt_toolbar: Control, paint_toolbar: Control) -> void:
	name = "IslandTerrain"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 310.0 * EditorInterface.get_editor_scale())

	_map_scroll = _create_tab("Harita")
	_sculpt_scroll = _create_tab("Şekillendir")
	_paint_scroll = _create_tab("Boya")
	_build_map_tab()

	sculpt_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sculpt_scroll.add_child(sculpt_toolbar)
	_paint_scroll.add_child(paint_toolbar)


func set_terrain(terrain_name: String) -> void:
	if _terrain_status != null:
		_terrain_status.text = "Seçili harita: %s\nDüz başlangıç aktiftir." % terrain_name


func set_message(message: String) -> void:
	if _terrain_status != null:
		_terrain_status.text = message


func select_map_tab() -> void:
	current_tab = 0


func select_sculpt_tab() -> void:
	current_tab = 1


func select_paint_tab() -> void:
	current_tab = 2


func _build_map_tab() -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	_map_scroll.add_child(box)

	var title := Label.new()
	title.text = "IslandTerrain Harita Hazırlama"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	_terrain_status = Label.new()
	_terrain_status.text = "IslandTerrain3D seç. Yeni node düz araziyle başlar."
	_terrain_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_terrain_status)

	var generate_button := Button.new()
	generate_button.text = "Prosedürel Ada Üret"
	generate_button.custom_minimum_size.y = 54.0 * EditorInterface.get_editor_scale()
	generate_button.pressed.connect(func() -> void: generate_island_requested.emit())
	box.add_child(generate_button)

	var note := Label.new()
	note.text = "Bu düğme isteğe bağlı başlangıç üretir. El ile map yapmak için Şekillendir sekmesine geç. Oyuncunun oyun sırasında kazması bu editör panelinden ayrı bir runtime sistemidir."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)


func _create_tab(tab_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	return scroll