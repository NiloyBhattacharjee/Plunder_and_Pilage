extends Node
## Autoload "Style": the one place the look comes from. Builds the UI Theme from data/palette.json
## (colours, fonts, paper panel texture) and applies it to the whole game. Restyle by editing that file.
## Labels use theme variations "Title" and "Header"; code asks Style.c("ink") for named colours.


func _ready() -> void:
	# UI under CanvasLayers doesn't inherit the window's theme, so fold ours into Godot's default theme,
	# which every control falls back to. This runs before any scene loads.
	var t := build_theme()
	ThemeDB.get_default_theme().merge_with(t)
	ThemeDB.get_default_theme().default_font = t.default_font
	ThemeDB.get_default_theme().default_font_size = t.default_font_size
	ThemeDB.fallback_font = t.default_font
	ThemeDB.fallback_font_size = t.default_font_size
	get_tree().root.theme = t


static func c(name: String) -> Color:
	return Color(Data.table("palette").colors[name])


static func font(kind: String) -> Font:
	return load(Data.table("palette").fonts[kind])


func build_theme() -> Theme:
	var p: Dictionary = Data.table("palette")
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = int(p.font_sizes.body)

	var paper := StyleBoxTexture.new()  # parchment panels with an inked border baked into the texture
	paper.texture = load(p.panel_texture)
	paper.set_texture_margin_all(10)
	paper.set_content_margin_all(14)
	paper.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	paper.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	for type in ["PanelContainer", "Panel", "TooltipPanel", "PopupMenu", "TabContainer"]:
		t.set_stylebox("panel", type, paper)

	for type in ["Label", "CheckBox", "TooltipLabel", "LineEdit", "PopupMenu"]:
		t.set_color("font_color", type, c("ink"))
	t.set_color("font_hover_color", "PopupMenu", c("header"))
	t.set_color("font_color", "CheckBox", c("ink"))
	t.set_color("font_hover_color", "CheckBox", c("header"))
	t.set_color("font_pressed_color", "CheckBox", c("ink"))

	# Wax-seal buttons: dark red, rounded, light lettering.
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _wax(c("wax")))
		t.set_stylebox("hover", type, _wax(c("wax_light")))
		t.set_stylebox("pressed", type, _wax(c("wax_dark")))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		var off := _wax(c("wax"))
		off.bg_color.a = 0.35
		t.set_stylebox("disabled", type, off)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(state, type, c("wax_text"))
		t.set_color("font_disabled_color", type, Color(c("wax_text"), 0.6))

	var field := StyleBoxFlat.new()
	field.bg_color = c("parchment_light")
	field.border_color = c("ink_soft")
	field.set_border_width_all(1)
	field.set_content_margin_all(6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field)

	var tab := _wax(c("parchment_dark"))
	var tab_on := _wax(c("parchment_light"))
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", tab_on)
	t.set_stylebox("tab_selected", "TabContainer", tab_on)
	for state in ["font_selected_color", "font_unselected_color", "font_hovered_color"]:
		t.set_color(state, "TabContainer", c("ink"))

	t.add_type("Title")
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", font("title"))
	t.set_font_size("font_size", "Title", int(p.font_sizes.title))
	t.set_color("font_color", "Title", c("ink"))
	t.add_type("Header")
	t.set_type_variation("Header", "Label")
	t.set_font("font", "Header", font("italic"))
	t.set_font_size("font_size", "Header", int(p.font_sizes.header))
	t.set_color("font_color", "Header", c("header"))
	return t


static func _wax(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(6)
	s.border_color = col.darkened(0.35)
	s.set_border_width_all(1)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s
