extends Node
## Autoload "Style": the one place the look comes from. Builds the UI Theme from data/palette.json
## (colours, fonts, pixel window frames) and applies it to the whole game. Restyle by editing that file.
## The windows are Octopath-style: navy glass with gold trim, drawn as 9-slice pixel art (assets/ui/pixel/).
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

	var paper := _frame(p.panel_texture, 18, 18)  # windows: the gold trim is baked into the texture
	for type in ["PanelContainer", "Panel", "PopupMenu", "TabContainer"]:
		t.set_stylebox("panel", type, paper)
	t.set_stylebox("panel", "TooltipPanel", _frame(p.pixel_ui + "tooltip.png", 4, 8))

	for type in ["Label", "CheckBox", "TooltipLabel", "LineEdit", "PopupMenu"]:
		t.set_color("font_color", type, c("ink"))
	t.set_color("font_hover_color", "PopupMenu", c("header"))
	t.set_color("font_color", "CheckBox", c("ink"))
	t.set_color("font_hover_color", "CheckBox", c("header"))
	t.set_color("font_pressed_color", "CheckBox", c("ink"))

	# Pixel buttons: navy with a gold edge that brightens under the mouse.
	for type in ["Button", "OptionButton"]:
		t.set_stylebox("normal", type, _button(p.pixel_ui + "button.png"))
		t.set_stylebox("hover", type, _button(p.pixel_ui + "button_hover.png"))
		t.set_stylebox("pressed", type, _button(p.pixel_ui + "button_pressed.png"))
		t.set_stylebox("hover_pressed", type, _button(p.pixel_ui + "button_pressed.png"))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_stylebox("disabled", type, _button(p.pixel_ui + "button_disabled.png"))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			t.set_color(state, type, c("wax_text"))
		t.set_color("font_disabled_color", type, Color(c("wax_text"), 0.6))

	var field := _button(p.pixel_ui + "field.png")
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field)
	t.set_color("caret_color", "LineEdit", c("header"))
	t.set_color("selection_color", "LineEdit", Color(c("header"), 0.35))

	var tab := _button(p.pixel_ui + "tab.png")
	var tab_on := _button(p.pixel_ui + "tab_on.png")
	t.set_stylebox("tab_unselected", "TabContainer", tab)
	t.set_stylebox("tab_hovered", "TabContainer", tab_on)
	t.set_stylebox("tab_selected", "TabContainer", tab_on)
	for state in ["font_unselected_color", "font_hovered_color"]:
		t.set_color(state, "TabContainer", c("ink_soft"))
	t.set_color("font_selected_color", "TabContainer", c("header"))
	t.set_font("font", "TabContainer", font("pixel"))
	var scroll := StyleBoxFlat.new()  # thin gold scrollbars
	scroll.bg_color = c("header").darkened(0.3)
	scroll.set_content_margin_all(3)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(c("parchment_dark"), 0.6)
	track.set_content_margin_all(3)
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", type, scroll)
		t.set_stylebox("grabber_highlight", type, scroll)
		t.set_stylebox("grabber_pressed", type, scroll)
		t.set_stylebox("scroll", type, track)

	t.add_type("Title")
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", font("title"))
	t.set_font_size("font_size", "Title", int(p.font_sizes.title))
	t.set_color("font_color", "Title", c("ink"))
	t.add_type("Header")
	t.set_type_variation("Header", "Label")
	t.set_font("font", "Header", font("pixel"))
	t.set_font_size("font_size", "Header", int(p.font_sizes.header))
	t.set_color("font_color", "Header", c("header"))
	return t


## A 9-slice pixel frame: the corners stay crisp, the edges and middle stretch.
static func _frame(path: String, margin: int, content: int) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load(path)
	s.set_texture_margin_all(margin)
	s.set_content_margin_all(content)
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE  # repeat at 1:1, never smear the pixels
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return s


static func _button(path: String) -> StyleBoxTexture:
	var s := _frame(path, 6, 4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	return s
