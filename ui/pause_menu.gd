extends CanvasLayer
## The Esc menu, over any screen: resume, fullscreen, volume, save, quit. The game stands still while it's open
## (the whole tree pauses; this layer alone keeps running). An autoload, so Esc works everywhere.
## Fullscreen and volume are your machine's settings, kept in user://settings.cfg beside the mute (ui/hud.gd).

const SETTINGS := "user://settings.cfg"

var _save: Button
var _full: CheckButton
var _volume: HSlider


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	var dim := ColorRect.new()  # catches clicks meant for the game underneath
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 320
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	UIKit.label(box, "Paused").theme_type_variation = &"Title"
	UIKit.button(box, "Resume (Esc)", close)
	_full = CheckButton.new()
	_full.text = "Fullscreen"
	_full.toggled.connect(_set_fullscreen)
	box.add_child(_full)
	var row := UIKit.row(box)
	UIKit.label(row, "Volume")
	_volume = HSlider.new()
	_volume.max_value = 1.0
	_volume.step = 0.05
	_volume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.value_changed.connect(_set_volume)
	row.add_child(_volume)
	_save = UIKit.button(box, "Save", _save_game, "Quick-save (F5). The game also saves itself every week at sea.")
	UIKit.button(box, "Quit to desktop", get_tree().quit, "Anything since your last save is lost.")
	_full.button_pressed = cfg.get_value("video", "fullscreen", false)
	_volume.value = cfg.get_value("audio", "volume", 0.8)
	_set_volume(_volume.value)  # value_changed doesn't fire when the value is already the default


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func open() -> void:
	var world := _world()
	_save.text = "Save"
	_save.disabled = world == null or not world.can_save()
	visible = true
	get_tree().paused = true


func close() -> void:
	visible = false
	get_tree().paused = false


## The world map, when that's the scene (not the new-game screen).
func _world() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null and scene.has_method("can_save") else null


func _save_game() -> void:
	var err: Error = _world()._save()
	_save.text = "Saved." if err == OK else "Save failed: %s" % error_string(err)


func _set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	_store("video", "fullscreen", on)


func _set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(v))
	_store("audio", "volume", v)


static func _store(section: String, key: String, v: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS)
	cfg.set_value(section, key, v)
	cfg.save(SETTINGS)
