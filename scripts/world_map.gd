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

## Set by the new-game screen before switching here: {name, nationality, background, ship_name} or {"load": true}.
static var start_config := {}

@onready var ship: Node2D = $Ship
@onready var camera: Camera2D = $Camera2D
@onready var hud = $HUD
@onready var port_screen = $PortScreen
@onready var crew_screen = $CrewScreen


func _ready() -> void:
	terrain = TerrainGrid.new(load("res://data/map/terrain.png").get_image(), int(Data.map.cell_px))
	for id in Data.table("ports"):
		var p: Dictionary = Data.table("ports")[id]
		port_positions[id] = Geo.latlon_to_px(p.lat, p.lon)
		anchorages[id] = terrain.nearest_sea(port_positions[id])
	$PortLayer.port_positions = port_positions

	camera.limit_right = int(Data.map.size[0])
	camera.limit_bottom = int(Data.map.size[1])

	ship.terrain = terrain
	ship.stats_changed.connect(func(): terrain.set_shallow_cost(Data.rules.draught[ship.stats.draught].route_cost))
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
	if port_screen.visible or crew_screen.visible:
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


func _on_foundered() -> void:
	Clock.set_speed(0)
	hud.show_message("The ship has foundered. All hands lost. (Restart to try again.)")
