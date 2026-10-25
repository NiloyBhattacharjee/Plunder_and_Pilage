extends SceneTree
## The README screenshots, into docs/screenshots/. Needs a window, so not --headless:
##   bin/Godot_v4.7.2-stable_win64_console.exe --path . -s tools/screenshots.gd

const OUT := "res://docs/screenshots/"


func _initialize() -> void:
	_run.call_deferred()


func _shot(file: String, frames := 40) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + file + ".png"))
	print("saved ", file)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	AudioServer.set_bus_mute(0, true)
	change_scene_to_file("res://ui/new_game.tscn")
	await _shot("new_game")

	change_scene_to_file("res://scenes/world_map.tscn")
	await process_frame
	root.get_node("Clock").day = 0.55  # a new game starts at night: show them by day
	await _shot("port", 240)  # a new game opens on the port screen, after its name card
	var w = current_scene
	w.port_screen.get_node("%Tabs").current_tab = 1
	await _shot("market")
	w.port_screen.close()
	await _shot("map")
	w._zoom(2.0)
	await _shot("map_close")
	w._zoom(0.5)

	w._open_crew()
	await _shot("crew")
	w.crew_screen.close()

	var data = root.get_node("Data")  # autoloads aren't known by name in a -s script
	var night: String = data.table("backgrounds")[data.rules.start.background].get("night", "")
	var events = root.get_node("Events")
	w.run_event(events.materialize(events.instance_of(night, w._event_ctx()), w._event_ctx()))  # as WorldMap._play_night
	await _shot("event")
	w.dialog.hide()
	w._in_event = false

	w.start_combat(load("res://scripts/combat/encounters.gd").generate("spain", w.rng, "merchant"), "attack")
	await _shot("battle", 150)
	quit()
