extends Node2D
## The player's ship on the world map: follows a route, sails by the wind, wears down, and its people
## eat, earn, learn and reveal themselves day by day.
## All persistent values live in `state` (a plain Dictionary, see NewGame.build) so saves stay simple.

signal arrived(port_id: String)
signal message(text: String)
signal foundered
signal stats_changed  # ship type or upgrades changed: draught, speed and routes may differ

var state := {}
var stats: Dictionary  # effective stats: type + upgrades (ShipStats.effective)
var terrain: TerrainGrid
var route := PackedVector2Array()
var target_port := ""
var anchored_at := ""
var rng := RandomNumberGenerator.new()

# Current sailing readout, for the HUD.
var heading := 0.0
var speed_knots := 0.0
var sail_info := {}
var speed_text := ""
var wind := {}
var _last_storm := ""


func _ready() -> void:
	rng.randomize()
	Clock.ticked.connect(_on_tick)
	Clock.day_passed.connect(func(_d): _on_day())


func setup(new_state: Dictionary) -> void:
	state = new_state
	refresh_stats()


func refresh_stats() -> void:
	stats = ShipStats.effective(state.type, state.upgrades)
	state.hull = minf(state.hull, stats.hull)
	state.sails = minf(state.sails, stats.sails)
	stats_changed.emit()


func set_route(path: PackedVector2Array, port_id := "") -> void:
	route = path
	target_port = port_id
	if not path.is_empty():
		anchored_at = ""
	queue_redraw()


func capacity() -> float:
	return stats.cargo


func _on_tick(dd: float) -> void:
	if state.is_empty():
		return
	wind = Weather.wind_at(position)
	_storm_damage(dd)
	if route.is_empty() or state.hull <= 0:
		speed_knots = 0.0
		return

	heading = Geo.bearing(route[0] - position)
	var off_wind := Geo.angle_between(heading, wind.dir)
	sail_info = Sailing.best_course(stats.polar, off_wind)
	sail_info.off_wind = off_wind
	var cond := ShipStats.condition(state, stats)
	speed_knots = stats.speed_knots * sail_info.factor * wind.strength * cond.mult
	speed_text = "Top speed %.1f kn\nPoint of sail: x%.2f\nWind strength: x%.2f\n%s" % [
		stats.speed_knots, sail_info.factor, wind.strength, cond.text]
	for prize in state.get("prizes", []):  # a squadron sails at the pace of its slowest ship
		var pst := ShipStats.effective(prize.type, [])
		var pk: float = pst.speed_knots * Sailing.best_course(pst.polar, off_wind).factor * wind.strength
		if pk < speed_knots:
			speed_knots = pk
			speed_text += "\nHeld back by the prize %s: %.1f kn" % [prize.name, pk]
	$Hull.rotation = deg_to_rad(heading)

	if terrain and terrain.at(position) == TerrainGrid.SHALLOW:
		_check_grounding(dd)

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


func _storm_damage(dd: float) -> void:
	if wind.storm != _last_storm and wind.storm != "":
		message.emit("%s! The %s is taking a beating." % [Data.rules.storms[wind.storm].name, state.name])
	_last_storm = wind.storm
	if wind.storm == "" or state.hull <= 0:
		return
	var spec: Dictionary = Data.rules.storms[wind.storm]
	var shelter: float = Data.rules.storm_shelter if anchored_at != "" else 1.0
	state.hull -= spec.hull_damage_per_day * dd * shelter
	state.sails = maxf(0.0, state.sails - spec.sail_damage_per_day * dd * shelter)
	if state.hull <= 0:
		state.hull = 0.0
		route.clear()
		foundered.emit()


# Deep keels in shallow water: a chance per day of touching bottom. A good navigator cuts it.
func _check_grounding(dd: float) -> void:
	if rng.randf() < ShipStats.grounding_risk(state, stats) * dd:
		var dmg: Array = Data.rules.grounding.hull_damage
		var hit := rng.randi_range(dmg[0], dmg[1])
		state.hull = maxf(1.0, state.hull - hit)
		message.emit("The %s touched bottom in the shallows! Hull -%d." % [state.name, hit])


func _on_day() -> void:
	if state.is_empty():
		return
	var at_sea := anchored_at == ""
	apply_daily_upkeep(state, ShipStats.headcount(state), Data.rules.upkeep, ShipStats.daily_cost(state, stats))
	state.fouling = minf(1.0, state.fouling + Data.rules.condition.fouling_per_day * stats.fouling_rate)
	if at_sea:
		_carpenter_repairs()
	for text in daily_people(state, at_sea and not route.is_empty(), People.rng):
		message.emit(text)


# The carpenter patches hull and sails at sea, but only so far without a shipyard.
func _carpenter_repairs() -> void:
	var c: Dictionary = Data.rules.condition
	var amount: float = ShipStats.officer_skill(state, "carpenter") * c.carpenter_repair_per_point
	var worked := false
	for part in ["hull", "sails"]:
		var cap: float = stats[part] * c.carpenter_max_fraction
		if state[part] < cap and state.hull > 0:
			state[part] = minf(cap, state[part] + amount)
			worked = true
	if worked and state.officers.has("carpenter"):
		People.gain_xp(People.person(state.officers.carpenter), "carpentry", 1.0)


## Food and water come out of the hold for every mouth aboard; wages and ship upkeep come out of the purse,
## and anything unpaid is owed.
static func apply_daily_upkeep(s: Dictionary, mouths: int, upkeep: Dictionary, cost: float) -> void:
	Ports.remove_cargo(s, "food", mouths * upkeep.food_per_crew)
	Ports.remove_cargo(s, "water", mouths * upkeep.water_per_crew)
	var paid := minf(cost, s.gold)
	s.gold -= paid
	s.wages_owed += cost - paid


## A day in the life of the crew: skills grow with use, hands gain experience, hidden traits come out.
## Returns messages worth telling the player.
static func daily_people(s: Dictionary, sailing: bool, rng: RandomNumberGenerator) -> Array:
	var cfg: Dictionary = Data.rules.people
	var out := []
	if sailing:
		var cap := People.person(s.captain)
		if People.gain_xp(cap, "seamanship", 0.3):
			out.append("Captain %s's seamanship improves to %d." % [cap.name, cap.skills.seamanship])
		if s.officers.has("navigator"):
			var nav := People.person(s.officers.navigator)
			if People.gain_xp(nav, "navigation", 0.5):
				out.append("Navigator %s's navigation improves to %d." % [nav.name, nav.skills.navigation])
	for id in s.crew:
		var c := People.person(id)
		if sailing:
			People.gain_xp(c, "seamanship", 0.1)
			if rng.randf() < cfg.experience_gain_chance_per_day:
				c.stats.experience = mini(20, c.stats.experience + 1)
		if not c.hidden.is_empty() and rng.randf() < cfg.reveal_chance_per_day:
			var t := People.reveal_trait(c)
			out.append("You learn something about %s: %s. %s" % [c.name, Data.table("traits")[t].name,
				Data.table("traits")[t].description])
	return out


func days_of(supply: String) -> float:
	var per_day: float = ShipStats.headcount(state) * Data.rules.upkeep[supply + "_per_crew"]
	return state.cargo.get(supply, 0.0) / per_day if per_day > 0 else INF


func save_state() -> Dictionary:
	return {"state": state, "position": position, "route": route, "target_port": target_port,
		"anchored_at": anchored_at, "heading": heading}


func load_state(d: Dictionary) -> void:
	state = d.state
	position = d.position
	route = d.route
	target_port = d.target_port
	anchored_at = d.anchored_at
	heading = d.heading
	$Hull.rotation = deg_to_rad(heading)
	refresh_stats()
	queue_redraw()


func _draw() -> void:
	# Planned route as a dashed line, drawn in local space (this node is never rotated).
	var prev := Vector2.ZERO
	for p in route:
		draw_dashed_line(prev, p - position, Color(0.15, 0.1, 0.05, 0.6), 1.5, 6.0)
		prev = p - position
