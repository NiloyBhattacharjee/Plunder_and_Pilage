class_name SceneView
extends Control
## A painted scene from assets/scenes/<key>/ (made by tools/make_scenes.py): back.png, then front.png over it if
## there is one (the town, the water and the ships), then lights.png (windows and lanterns, added on from dusk).
## A scene with lights is drawn for any hour, so it takes the hour's tint like the map; the others are painted
## at their own hour. `cover`: scaled to fill (the port screen); otherwise drawn at its own size and centred,
## cropped to fit (a dialog's picture). `depth`: how far the front shifts with the mouse, in screen pixels (the
## back shifts half as far), so the town stands out from the hills.
## Which scene goes with which event or ending: data/scenes.json.

const DIR := "res://assets/scenes/"

var cover := true
var depth := 0.0
var _layers: Array = []  # [TextureRect, how far it shifts]


static func exists(key: String) -> bool:
	return key != "" and ResourceLoader.exists(DIR + key + "/back.png")


## The scene data/scenes.json names for `what` ("event.sea", "ending.hanged", "sail_ho"...), or "".
static func pick(what: String) -> String:
	return Data.table("scenes").get(what, "")


func _init() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_IGNORE


## Shows the scene; false (and hidden) if there's no such scene.
func show_scene(key: String) -> bool:
	for l in _layers:
		l[0].queue_free()
	_layers = []
	visible = exists(key)
	if not visible:
		return false
	for part in [["back", 0.5], ["front", 1.0], ["lights", 1.0]]:
		var path: String = DIR + key + "/" + part[0] + ".png"
		if not ResourceLoader.exists(path):
			continue
		var t := TextureRect.new()
		t.texture = load(path)
		t.texture_filter = TEXTURE_FILTER_NEAREST
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if cover else TextureRect.STRETCH_KEEP_CENTERED
		t.mouse_filter = MOUSE_FILTER_IGNORE
		if part[0] == "lights":
			t.material = CanvasItemMaterial.new()
			t.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		add_child(t)
		_layers.append([t, part[1]])
	_light()
	return true


func _light() -> void:
	var lit: bool = _layers.size() == 3
	modulate = Weather.tint() if lit else Color.WHITE
	if lit:  # lights come on at dusk, and the tint mustn't dim them
		_layers[2][0].self_modulate = Color(1, 1, 1, clampf(Weather.night() * 1.6 - 0.3, 0.0, 1.0)) / Weather.tint()


func _process(_delta: float) -> void:
	if _layers.is_empty() or not is_visible_in_tree():
		return
	var m := Vector2.ZERO
	if depth > 0.0:
		m = (get_local_mouse_position() / size - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * 2.0
	for l in _layers:
		var t: TextureRect = l[0]
		t.size = size + Vector2.ONE * depth * 2.0
		t.position = -Vector2.ONE * depth - m * depth * l[1]
