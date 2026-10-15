class_name WorldMap
extends Node2D
## World map scene: builds the chart from data, routes the ship on click, and runs the camera.
## Controls: left-click sea or a port to sail there. Right/middle-drag pans, wheel zooms, F follows the ship.
## Space pauses, 1/2/3 set time speed. F5 quick-saves, F9 quick-loads.

const PORT_CLICK_RADIUS := 14.0  # screen pixels
const ZOOM_MAX := 4.0

var terrain: TerrainGrid
var port_positions := {}  # where the port marker is drawn
var anchorages := {}      # nearest navigable point to each port
var follow_ship := true
var combat: Node = null
var rng := RandomNumberGenerator.new()

## Set by the new-game screen before switching here: {name, nationality, background, ship_name} or {"load": true}.
static var start_config := {}

@onready var ship: Node2D = $Ship
@onready var camera: Camera2D = $Camera2D
@onready var hud = $HUD
@onready var port_screen = $PortScreen
@onready var crew_screen = $CrewScreen
@onready var prize_screen = $PrizeScreen
@onready var dialog = $ChoiceDialog


func _ready() -> void:
	rng.randomize()
	terrain = TerrainGrid.new(load("res://data/map/terrain.png").get_image(), int(Data.map.cell_px))
	for id in Data.table("ports"):
		var p: Dictionary = Data.table("ports")[id]
		port_positions[id] = Geo.latlon_to_px(p.lat, p.lon)
		anchorages[id] = terrain.nearest_sea(port_positions[id])
	$PortLayer.port_positions = port_positions

	camera.limit_right = int(Data.map.size[0])
	camera.limit_bottom = int(Data.map.size[1])

	ship.terrain = terrain
	ship.stats_changed.connect(func():
		var d: Dictionary = Data.rules.draught[ship.stats.draught]
		terrain.set_shallow_cost(d.route_cost, d.reef_route_cost))
	# Loading still builds a default game first; the save then overwrites it (and it's a safe fallback if loading fails).
	var cfg: Dictionary = start_config if start_config.has("background") else Data.rules.start
	var game := NewGame.build(cfg)
	var start_port: String = game.start_port
	ship.setup(game.state)
	ship.position = anchorages[start_port]
	ship.anchored_at = start_port
	ship.arrived.connect(_on_arrived)
	ship.message.connect(hud.show_message)
	ship.foundered.connect(_on_foundered)
	hud.ship = ship
	hud.enter_port_pressed.connect(func(): port_screen.open(ship.anchored_at, ship))
	hud.save_pressed.connect(_save)
	hud.load_pressed.connect(_load)
	hud.map_mode_changed.connect(func(good): $PortLayer.trade_good = good)
	port_screen.message.connect(hud.show_message)
	port_screen.closed.connect($PortLayer.queue_redraw)
	Clock.day_passed.connect(func(_d): if $PortLayer.trade_good != "": $PortLayer.queue_redraw())
	hud.crew_pressed.connect(func(): crew_screen.open(ship))
	crew_screen.message.connect(hud.show_message)
	Clock.day_passed.connect(func(_d): _maybe_encounter())
	hud.show_message("Captain %s and the %s lie at anchor in %s. Click the sea or a port to set a course. C opens the crew and ship." % [
		ShipStats.captain(ship.state).name, ship.state.name, Data.table("ports")[start_port].name])
	if start_config.get("load", false):
		_load.call_deferred()
	else:
		port_screen.open.call_deferred(start_port, ship)


func _process(_delta: float) -> void:
	if follow_ship:
		camera.position = ship.position


func _unhandled_input(event: InputEvent) -> void:
	if busy():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _set_course(get_global_mouse_position())
			MOUSE_BUTTON_WHEEL_UP: _zoom(1.15)
			MOUSE_BUTTON_WHEEL_DOWN: _zoom(1.0 / 1.15)
	elif event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		follow_ship = false
		camera.position -= event.relative / camera.zoom
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE: Clock.toggle_pause()
			KEY_1: Clock.set_speed(1)
			KEY_2: Clock.set_speed(2)
			KEY_3: Clock.set_speed(3)
			KEY_F: follow_ship = true
			KEY_C: crew_screen.open(ship)
			KEY_F5: _save()
			KEY_F9: _load()


func _set_course(target: Vector2) -> void:
	if ship.state.hull <= 0:
		return
	var port_id := _port_near(target)
	if port_id != "" and port_id == ship.anchored_at:
		port_screen.open(port_id, ship)
		return
	if port_id != "":
		target = anchorages[port_id]
	elif terrain.at(target) == TerrainGrid.LAND:
		hud.show_message("That's dry land, Captain.")
		return
	var path := terrain.find_path(ship.position, target)
	if path.is_empty():
		hud.show_message("No sea route to there.")
		return
	ship.set_route(path, port_id)
	if port_id != "":
		hud.show_message("Setting course for %s." % Data.table("ports")[port_id].name)


func _port_near(pos: Vector2) -> String:
	var radius := PORT_CLICK_RADIUS / camera.zoom.x
	for id in port_positions:
		if pos.distance_to(port_positions[id]) < radius or pos.distance_to(anchorages[id]) < radius:
			return id
	return ""


func _zoom(factor: float) -> void:
	# Never zoom out past the point where the map stops filling the window.
	var fit := get_viewport_rect().size / Vector2(Data.map.size[0], Data.map.size[1])
	var z := clampf(camera.zoom.x * factor, maxf(fit.x, fit.y), ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	$PortLayer.zoom = z


func _on_arrived(id: String) -> void:
	hud.show_message("Anchored at %s." % Data.table("ports")[id].name)
	port_screen.open(id, ship)


func _save() -> void:
	var err := SaveGame.save_game(self)
	hud.show_message("Game saved." if err == OK else "Save failed: %s" % error_string(err))


func _load() -> void:
	for screen in [port_screen, crew_screen]:
		if screen.visible:
			screen.close()
	var err := SaveGame.load_game(self)
	$PortLayer.queue_redraw()
	match err:
		OK: hud.show_message("Game loaded (paused).")
		ERR_INVALID_DATA: hud.show_message("That save is from an older version of the game and can't be loaded. Started a new game instead.")
		_: hud.show_message("Load failed: %s" % error_string(err))


## True while a screen, dialog or battle has the player's attention.
func busy() -> bool:
	return combat != null or port_screen.visible or crew_screen.visible or prize_screen.visible or dialog.visible


# ---- Encounters and battle -------------------------------------------------

func _maybe_encounter() -> void:
	if busy() or ship.anchored_at != "" or ship.route.is_empty() or ship.state.hull <= 0:
		return
	if rng.randf() < Data.rules.encounters.daily_chance:
		encounter(Encounters.generate(_nearest_port_faction(), rng))


func _nearest_port_faction() -> String:
	var best := ""
	for id in port_positions:
		if best == "" or ship.position.distance_to(port_positions[id]) < ship.position.distance_to(port_positions[best]):
			best = id
	return Data.table("ports")[best].faction


func encounter(enemy: Dictionary) -> void:
	UIKit.pause_clock()
	var s: Dictionary = ship.state
	var seen := Encounters.sighting(enemy, rng)
	var hit: int = Data.table("encounters")[enemy.kind].relation_hit
	var fname: String = Data.table("factions")[enemy.faction].name
	if Encounters.hostile(enemy, s):
		var pick: int = await dialog.ask("Enemy sail!", "A %s is bearing down on you.\n%s" % [enemy.label, seen], [
			{"text": "Clear for action", "tooltip": "Turn and fight."},
			{"text": "Crowd on sail and run", "tooltip": "Start the fight already running. Outdistance her (%d) and you're free." % Data.rules.combat.escape_distance},
			{"text": "Strike your colours", "tooltip": "Surrender without a fight. They'll strip your hold and take half your gold."},
		])
		match pick:
			0: start_combat(enemy, "defend")
			1: start_combat(enemy, "flee")
			2:
				hud.show_message("You strike without a fight. " + Encounters.surrender_losses(s))
				UIKit.resume_clock()
	else:
		var pick: int = await dialog.ask("Sail ho!", "A %s.\n%s" % [enemy.label, seen], [
			{"text": "Attack her", "tooltip": "Standing with %s -%d, notoriety +%d. Her cargo and gold could be yours." % [fname, hit, Data.table("encounters")[enemy.kind].notoriety]},
			{"text": "Let her pass", "tooltip": "Hold your course."},
		])
		if pick == 0:
			hud.show_message(Encounters.attacked(s, enemy))
			start_combat(enemy, "attack")
		else:
			UIKit.resume_clock()


func start_combat(enemy: Dictionary, mode: String) -> void:
	UIKit.pause_clock()
	combat = load("res://scenes/combat.tscn").instantiate()
	_show_world(false)
	get_tree().root.add_child(combat)
	var w := Weather.wind_at(ship.position)
	combat.start(Encounters.player_side(ship.state), enemy, mode, w.dir, w.strength)
	combat.get_node("Camera2D").make_current()
	combat.finished.connect(_on_combat_finished)


func _show_world(on: bool) -> void:
	visible = on
	hud.visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _on_combat_finished(result: Dictionary) -> void:
	combat.queue_free()
	combat = null
	_show_world(true)
	camera.make_current()
	var s: Dictionary = ship.state
	for m in Encounters.apply_battle(s, result.player, rng):
		hud.show_message(m)
	var e: Dictionary = result.enemy_data
	match result.outcome:
		"enemy_struck":
			ShipStats.captain(s).history.append("Took the %s %s, %s." % [Data.table("factions")[e.faction].name, e.name, Clock.date_string()])
			prize_screen.open(ship, result)
			for m in await prize_screen.done:
				hud.show_message(m)
		"enemy_sunk":
			hud.show_message("The %s sank with all her cargo." % e.name)
		"separated":
			hud.show_message("You and the %s go your separate ways." % e.name)
		"player_struck":
			hud.show_message("You struck your colours. " + Encounters.surrender_losses(s))
		"player_sunk":
			s.hull = 0.0
			ship.route.clear()
			_on_foundered()
			return
	ship.refresh_stats()
	UIKit.resume_clock()


func _on_foundered() -> void:
	Clock.set_speed(0)
	hud.show_message("The ship has foundered. All hands lost. (Restart to try again.)")
