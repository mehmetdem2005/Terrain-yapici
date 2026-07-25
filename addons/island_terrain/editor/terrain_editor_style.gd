@tool
extends RefCounted
class_name IslandTerrainEditorStyle

const COLOR_PANEL := Color(0.055, 0.063, 0.075, 0.98)
const COLOR_CARD := Color(0.085, 0.096, 0.115, 0.98)
const COLOR_CARD_ALT := Color(0.105, 0.118, 0.142, 0.98)
const COLOR_ACCENT := Color(0.20, 0.62, 1.0, 1.0)
const COLOR_ACCENT_SOFT := Color(0.20, 0.62, 1.0, 0.20)
const COLOR_SUCCESS := Color(0.22, 0.78, 0.48, 1.0)
const COLOR_WARNING := Color(1.0, 0.67, 0.20, 1.0)
const COLOR_DANGER := Color(1.0, 0.34, 0.34, 1.0)
const COLOR_TEXT_MUTED := Color(0.69, 0.73, 0.80, 1.0)


static func editor_scale() -> float:
	return maxf(1.0, EditorInterface.get_editor_scale())


static func make_panel_style(background: Color = COLOR_CARD, radius: float = 8.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.corner_radius_top_left = int(radius * editor_scale())
	style.corner_radius_top_right = int(radius * editor_scale())
	style.corner_radius_bottom_left = int(radius * editor_scale())
	style.corner_radius_bottom_right = int(radius * editor_scale())
	style.content_margin_left = 12.0 * editor_scale()
	style.content_margin_right = 12.0 * editor_scale()
	style.content_margin_top = 10.0 * editor_scale()
	style.content_margin_bottom = 10.0 * editor_scale()
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1.0, 1.0, 1.0, 0.055)
	return style


static func make_accent_style(background: Color = COLOR_ACCENT_SOFT) -> StyleBoxFlat:
	var style := make_panel_style(background, 7.0)
	style.border_color = Color(COLOR_ACCENT.r, COLOR_ACCENT.g, COLOR_ACCENT.b, 0.55)
	return style


static func make_card(title_text: String, subtitle_text: String = "") -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", make_panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", int(8.0 * editor_scale()))
	panel.add_child(content)

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", int(16.0 * editor_scale()))
	content.add_child(title)

	if not subtitle_text.is_empty():
		var subtitle := Label.new()
		subtitle.text = subtitle_text
		subtitle.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		subtitle.add_theme_font_size_override("font_size", int(12.0 * editor_scale()))
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(subtitle)

	return {"panel": panel, "content": content}


static func make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	label.add_theme_font_size_override("font_size", int(11.0 * editor_scale()))
	return label


static func make_action_button(text: String, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44.0 * editor_scale()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if accent:
		button.add_theme_stylebox_override("normal", make_accent_style())
		button.add_theme_stylebox_override("hover", make_accent_style(Color(0.24, 0.68, 1.0, 0.30)))
		button.add_theme_stylebox_override("pressed", make_accent_style(Color(0.16, 0.50, 0.88, 0.45)))
	return button


static func make_chip(text: String, color: Color) -> Label:
	var chip := Label.new()
	chip.text = "  %s  " % text
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.custom_minimum_size.y = 28.0 * editor_scale()
	chip.add_theme_color_override("font_color", color)
	var style := make_panel_style(Color(color.r, color.g, color.b, 0.12), 12.0)
	style.border_color = Color(color.r, color.g, color.b, 0.42)
	style.content_margin_left = 8.0 * editor_scale()
	style.content_margin_right = 8.0 * editor_scale()
	style.content_margin_top = 3.0 * editor_scale()
	style.content_margin_bottom = 3.0 * editor_scale()
	chip.add_theme_stylebox_override("normal", style)
	return chip


static func style_tool_button(button: Button) -> void:
	button.toggle_mode = true
	button.custom_minimum_size = Vector2(116.0, 48.0) * editor_scale()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var normal := make_panel_style(COLOR_CARD_ALT, 6.0)
	var hover := make_panel_style(Color(0.14, 0.16, 0.19, 1.0), 6.0)
	var pressed := make_accent_style(Color(0.18, 0.52, 0.88, 0.32))
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
