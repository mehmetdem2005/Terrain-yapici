@tool
extends TabContainer
class_name IslandTerrainToolsPanel

var _sculpt_scroll: ScrollContainer
var _paint_scroll: ScrollContainer


func configure(sculpt_toolbar: Control, paint_toolbar: Control) -> void:
	name = "IslandTerrain"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 310.0 * EditorInterface.get_editor_scale())

	_sculpt_scroll = _create_tab("Şekillendir")
	_paint_scroll = _create_tab("Boya")

	sculpt_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paint_toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sculpt_scroll.add_child(sculpt_toolbar)
	_paint_scroll.add_child(paint_toolbar)


func select_sculpt_tab() -> void:
	current_tab = 0


func select_paint_tab() -> void:
	current_tab = 1


func _create_tab(tab_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	return scroll
