class_name Portrait
extends Control
## Draws a character's layered portrait at any size. Use Portrait.make(c, "captain", 96) from code.

const PIXEL_SHADER := preload("res://assets/ui/pixel_portrait.gdshader")
static var _pixel: ShaderMaterial

var _layers: Array = []


func _init() -> void:
	if _pixel == null:
		_pixel = ShaderMaterial.new()
		_pixel.shader = PIXEL_SHADER
	material = _pixel


static func make(c: Dictionary, role: String, px := 64) -> Portrait:
	var p := Portrait.new()
	p.custom_minimum_size = Vector2(px, px)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	p.show_character(c, role)
	return p


func show_character(c: Dictionary, role: String) -> void:
	_layers = Portraits.layers(c, Portraits.tags_for(c, role))
	tooltip_text = People.describe(c) if c.has("stats") else ""
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	for l in _layers:
		draw_texture_rect(l.texture, rect, false, l.color)
	draw_rect(rect, Style.c("header").darkened(0.3), false, 2.0)
