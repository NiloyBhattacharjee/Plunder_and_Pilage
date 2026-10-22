extends CanvasLayer
## A titled message with 1-4 choice buttons. Used for sightings and boarding now, events later.
## Usage:  var i: int = await dialog.ask("Sail ho!", "text", [{"text": "Attack", "tooltip": "..."}, ...], "sail_ho")
## The last argument is a painted scene (assets/scenes/<key>/) shown above the text; none if it doesn't exist.

signal chosen(index: int)

var _picture := SceneView.new()


func _ready() -> void:
	hide()
	_picture.cover = false
	_picture.custom_minimum_size = Vector2(580, 190)
	%Title.get_parent().add_child(_picture)
	%Title.get_parent().move_child(_picture, 0)


func ask(title: String, text: String, options: Array, scene := "") -> int:
	_picture.show_scene(scene)
	%Title.text = title
	%Text.text = text
	UIKit.clear(%Options)
	for i in options.size():
		var o: Dictionary = options[i]
		var b := UIKit.button(%Options, o.text, func(): _pick(i), o.get("tooltip", ""))
		b.disabled = o.get("disabled", false)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	show()
	return await chosen


func _pick(i: int) -> void:
	hide()
	chosen.emit(i)
