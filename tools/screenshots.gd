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

	var clock = root.get_node("Clock")  # half a year, so the charts have weeks to show
	var s: Dictionary = w.ship.state
	var crew_gd = load("res://scripts/crew.gd")
	for i in 180:  # stocked, paid and earning, as if trading: idle at anchor the crew would starve and desert
		s.cargo.food = maxf(s.cargo.get("food", 0), 120)
		s.cargo.water = maxf(s.cargo.get("water", 0), 120)
		s.gold += 14 + int(40 * sin(i / 9.0)) + (300 if i % 45 == 30 else 0)
		crew_gd.add_mod(s, "screenshot", "A good voyage", 20, 2)
		clock.advance(1.0)
		w.dialog.hide()  # a day's event would wait for an answer
		w._in_event = false
		await process_frame
	clock.day = floor(clock.day) + 0.55
	w.crew_screen.open(w.ship)
	w.crew_screen.show_charts()
	await _shot("charts")
	w.crew_screen.close()

	w.start_combat(load("res://scripts/combat/encounters.gd").generate("spain", w.rng, "merchant"), "attack")
	await _shot("battle", 150)
	quit()
