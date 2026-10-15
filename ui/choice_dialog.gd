extends CanvasLayer
## A titled message with 1-4 choice buttons. Used for sightings and boarding now, events later.
## Usage:  var i: int = await dialog.ask("Sail ho!", "text", [{"text": "Attack", "tooltip": "..."}, ...])

signal chosen(index: int)


func _ready() -> void:
	hide()


func ask(title: String, text: String, options: Array) -> int:
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
