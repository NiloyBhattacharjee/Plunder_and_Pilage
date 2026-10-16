class_name LooksEditor
extends HBoxContainer
## Choose a character's face and clothes: a live portrait beside a row of < > pickers for each layer, and
## swatches for skin and hair. Writes into c.portrait (pick, skin, hair), which Portraits honours.
## Story marks (scars, eyepatches, hooks) aren't offered: they're earned.

signal changed

var c: Dictionary
var role := "captain"
var preview_size := 200
var _preview: Control
var _rows: VBoxContainer


func edit(character: Dictionary, as_role := "captain") -> void:
	c = character
	role = as_role
	if not c.has("portrait"):
		c.portrait = {"seed": hash(c.name)}
	c.portrait.pick = c.portrait.get("pick", {})
	add_theme_constant_override("separation", 16)
	_rebuild()


func _rebuild() -> void:
	UIKit.clear(self)
	_preview = Portrait.make(c, role, preview_size)
	add_child(_preview)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	add_child(_rows)
	var d: Dictionary = Data.table("portraits")
	var drawn := {}
	for l in Portraits.layers(c, Portraits.tags_for(c, role)):
		drawn[l.layer] = l.id
	var presets: Dictionary = d.get("presets", {})
	if not presets.is_empty():  # start from a pirate type, then change what you like
		var flow := HFlowContainer.new()
		_rows.add_child(flow)
		UIKit.label(flow, "Start from:  ")
		for id in presets:
			if not id.begins_with("_"):
				UIKit.button(flow, presets[id].name, apply_preset.bind(id))
	var g := UIKit.grid(_rows, 4)
	for layer in Portraits.EDITABLE:
		var options: Array = d.parts[layer].map(func(p): return p.id)
		if d.none_chance.has(layer):
			options.push_front("")  # can go without
		var now: String = c.portrait.pick.get(layer, drawn.get(layer, ""))
		UIKit.label(g, layer.capitalize())
		UIKit.button(g, " < ", _step.bind(layer, options, now, -1))
		var l := UIKit.label(g, now.capitalize() if now != "" else "(none)")
		l.custom_minimum_size.x = 130
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UIKit.button(g, " > ", _step.bind(layer, options, now, 1))
	_swatches("Skin", "skin", _all(d.skin_tones))
	_swatches("Hair", "hair", _all(d.hair_colors))
	UIKit.button(_rows, "Roll a new face", func():
		c.portrait = {"seed": randi(), "pick": {}}
		_changed())


func apply_preset(id: String) -> void:
	var pick: Dictionary = Data.table("portraits").presets[id].pick
	for layer in pick:
		c.portrait.pick[layer] = pick[layer]
	_changed()


func _step(layer: String, options: Array, now: String, dir: int) -> void:
	var i := options.find(now)
	c.portrait.pick[layer] = options[posmod(i + dir, options.size())]
	_changed()


func _swatches(label: String, key: String, colors: Array) -> void:
	var row := UIKit.row(_rows)
	UIKit.label(row, label).custom_minimum_size.x = 60
	for col in colors:
		var b := Button.new()
		b.custom_minimum_size = Vector2(26, 26)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col)
		sb.border_color = Style.c("ink")
		sb.set_border_width_all(3 if c.portrait.get(key, "") == col else 1)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(func():
			c.portrait[key] = col
			_changed())
		row.add_child(b)


static func _all(by_nation: Dictionary) -> Array:
	var out := []
	for k in by_nation:
		for col in by_nation[k]:
			if not col in out:
				out.append(col)
	return out


func _changed() -> void:
	_rebuild()
	changed.emit()
