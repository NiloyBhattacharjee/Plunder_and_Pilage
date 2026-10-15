extends Node2D
## The player's ship on the world map: follows a route, sails by the wind, uses up supplies each day.
## All persistent values live in `state` (a plain Dictionary) so save/load can write it straight to JSON.

signal arrived(port_id: String)
signal message(text: String)
signal foundered

var state := {}
var stats: Dictionary  # ship type entry from ships.json
var terrain: TerrainGrid
var route := PackedVector2Array()
var target_port := ""
var anchored_at := ""

# Current sailing readout, for the HUD.
var heading := 0.0
var speed_knots := 0.0
var sail_info := {}
var wind := {}
var _last_storm := ""


func _ready() -> void:
	var start: Dictionary = Data.rules.start
	state = {"type": start.ship, "hull": float(Data.table("ships")[start.ship].hull),
		"crew": int(start.crew), "gold": float(start.gold), "wages_owed": 0.0,
		"cargo": start.cargo.duplicate(), "cargo_cost": {}}
	stats = Data.table("ships")[state.type]
	Clock.ticked.connect(_on_tick)
	Clock.day_passed.connect(func(_d): apply_daily_upkeep(state, Data.rules.upkeep))


func set_route(path: PackedVector2Array, port_id := "") -> void:
	route = path
	target_port = port_id
	if not path.is_empty():
		anchored_at = ""
	queue_redraw()


func _on_tick(dd: float) -> void:
	wind = Weather.wind_at(position)
	if wind.storm != _last_storm and wind.storm != "":
		message.emit("%s! The ship is taking a beating." % Data.rules.storms[wind.storm].name)
	_last_storm = wind.storm
	if wind.storm != "" and state.hull > 0:
		var dmg: float = Data.rules.storms[wind.storm].hull_damage_per_day * dd
		state.hull -= dmg * (Data.rules.storm_shelter if anchored_at != "" else 1.0)
		if state.hull <= 0:
			state.hull = 0.0
			route.clear()
			foundered.emit()
	if route.is_empty() or state.hull <= 0:
		speed_knots = 0.0
		return

	heading = Geo.bearing(route[0] - position)
	var off_wind := Geo.angle_between(heading, wind.dir)
	sail_info = Sailing.best_course(stats.polar, off_wind)
	sail_info.off_wind = off_wind
	speed_knots = stats.speed_knots * sail_info.factor * wind.strength
	$Hull.rotation = deg_to_rad(heading)

	var step := Geo.knots_to_px_per_day(speed_knots) * dd
	while step > 0.0 and not route.is_empty():
		var d := position.distance_to(route[0])
		if step < d:
			position = position.move_toward(route[0], step)
			break
		position = route[0]
		step -= d
		route.remove_at(0)
	if route.is_empty():
		speed_knots = 0.0
		if target_port != "":
			anchored_at = target_port
			arrived.emit(target_port)
	queue_redraw()


# Food and water are eaten from the hold each day; wages come out of the purse, and anything unpaid is owed.
static func apply_daily_upkeep(s: Dictionary, upkeep: Dictionary) -> void:
	Ports.remove_cargo(s, "food", s.crew * upkeep.food_per_crew)
	Ports.remove_cargo(s, "water", s.crew * upkeep.water_per_crew)
	var wages: float = s.crew * upkeep.wage_per_crew
	var paid := minf(wages, s.gold)
	s.gold -= paid
	s.wages_owed += wages - paid


func days_of(supply: String) -> float:
	var per_day: float = state.crew * Data.rules.upkeep[supply + "_per_crew"]
	return state.cargo.get(supply, 0.0) / per_day if per_day > 0 else INF


func capacity() -> float:
	return stats.cargo


func save_state() -> Dictionary:
	return {"state": state, "position": position, "route": route, "target_port": target_port,
		"anchored_at": anchored_at, "heading": heading}


func load_state(d: Dictionary) -> void:
	state = d.state
	stats = Data.table("ships")[state.type]
	position = d.position
	route = d.route
	target_port = d.target_port
	anchored_at = d.anchored_at
	heading = d.heading
	$Hull.rotation = deg_to_rad(heading)
	queue_redraw()


func _draw() -> void:
	# Planned route as a dashed line, drawn in local space (this node is never rotated).
	var prev := Vector2.ZERO
	for p in route:
		draw_dashed_line(prev, p - position, Color(0.15, 0.1, 0.05, 0.6), 1.5, 6.0)
		prev = p - position
