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
var _wake: Array = []  # recent positions, for the foam trail
const TURN_RATE := 25.0  # per day: about half a second to come about at normal speed


func _ready() -> void:
	rng.randomize()
	Clock.ticked.connect(_on_tick)
	Clock.day_passed.connect(func(_d): _on_day())


func setup(new_state: Dictionary) -> void:
	state = new_state
	refresh_stats()


func refresh_stats() -> void:
	stats = ShipStats.effective(state.type, state.upgrades)
	$Hull.setup(state.type, state.get("flag", "white"))
	$Hull.set_look(state)
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
	$Hull.set_state(state.hull / stats.hull, state.sails / stats.sails, 0 if route.is_empty() else 2)
	if route.is_empty() or state.hull <= 0:
		speed_knots = 0.0
		if not _wake.is_empty():
			_wake.pop_front()
			queue_redraw()
		return
	if _wake.is_empty() or position.distance_to(_wake[-1]) > 2.5:
		_wake.append(position)
		if _wake.size() > 14:
			_wake.pop_front()

	heading = Geo.bearing(route[0] - position)
	var off_wind := Geo.angle_between(heading, wind.dir)
	sail_info = Sailing.best_course(stats.polar, off_wind)
	sail_info.off_wind = off_wind
	var cond := ShipStats.condition(state, stats)
	speed_knots = stats.speed_knots * sail_info.factor * wind.strength * cond.mult
	speed_text = "Top speed %.1f kn\nPoint of sail: x%.2f\nWind strength: x%.2f\n%s" % [
		stats.speed_knots, sail_info.factor, wind.strength, cond.text]
	for prize in state.get("prizes", []):  # a squadron sails at the pace of its slowest ship
		var pst := Fleet.stats(prize)
		var short: float = clampf(Fleet.hands(prize) / maxf(1.0, pst.crew_min), 0.4, 1.0)  # a short-handed ship is slow
		var pk: float = pst.speed_knots * Sailing.best_course(pst.polar, off_wind).factor * wind.strength * short
		if pk < speed_knots:
			speed_knots = pk
			speed_text += "\nHeld back by the prize %s: %.1f kn" % [prize.name, pk]
	$Hull.rotation = lerp_angle($Hull.rotation, deg_to_rad(heading), 1.0 - exp(-dd * TURN_RATE))  # she comes about, she doesn't snap

	if terrain:
		var here := terrain.at(position)
		if here == TerrainGrid.SHALLOW or here == TerrainGrid.REEF:
			_check_grounding(dd, here == TerrainGrid.REEF)

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
		message.emit(Data.rules.storms[wind.storm].message.format({"ship": state.name}))
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
func _check_grounding(dd: float, reef: bool) -> void:
	if rng.randf() < ShipStats.grounding_risk(state, stats, reef) * dd:
		var dmg: Array = Data.rules.grounding.hull_damage
		var hit := rng.randi_range(dmg[0], dmg[1]) * (2 if reef else 1)
		state.hull = maxf(1.0, state.hull - hit)
		message.emit("The %s %s! Hull -%d." % [state.name, "struck a reef" if reef else "touched bottom in the shallows", hit])


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
	for text in hardship(state, stats, anchored_at, People.rng):
		message.emit(text)
	for text in Crew.daily(state, stats, anchored_at, rng):
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


## The cost of running out, and of unpaid or resentful hands: thirst and hunger kill and breed grudges;
## in port, men with grudges or owed wages slip away. Better quarters (comfort) soften both.
static func hardship(s: Dictionary, stats: Dictionary, port_id: String, rng: RandomNumberGenerator) -> Array:
	var h: Dictionary = Data.rules.hardship
	var out := []
	var relief := clampf(1.0 - stats.get("comfort", 0) * h.comfort_relief_per_point, 0.2, 1.0)
	var thirsty: bool = s.cargo.get("water", 0.0) <= 0.0
	var hungry: bool = s.cargo.get("food", 0.0) <= 0.0
	if thirsty or hungry:
		var rate: float = (h.thirst_death_rate if thirsty else 0.0) + (h.hunger_death_rate if hungry else 0.0)
		var dead := 0
		for id in s.crew.duplicate():
			var c := People.person(id)
			c.relations[s.captain] = c.relations.get(s.captain, 0) - int(ceil(h.starving_grudge * relief))
			if rng.randf() < rate:
				Crew.mourn(s, id)
				_remove_hand(s, id)
				dead += 1
		out.append("%s aboard!%s" % ["No water" if thirsty else "No food", " %d men died." % dead if dead > 0 else " The crew curse your name."])
	if port_id != "":
		var bill: float = maxf(1.0, s.crew.size() * Data.rules.upkeep.wage_per_crew)
		var unpaid_days: float = s.wages_owed / bill
		var gone := []
		var low_morale: float = maxf(0.0, Data.rules.crew.desert_morale - Crew.morale(s, stats).value) * Data.rules.crew.desert_per_point
		for id in s.crew.duplicate():
			var c := People.person(id)
			var chance: float = minf(h.desert_max_chance, unpaid_days * h.desert_per_unpaid_day) + low_morale
			if c.relations.get(s.captain, 0) <= h.desert_grudge_threshold:
				chance += h.desert_grudge_chance
			if rng.randf() < chance * relief * maxf(0.0, 1.0 + Civics.bonus(s, "desertion")):
				gone.append(c.name)
				_remove_hand(s, id)
				Ports.state[port_id].sailors += 1
		if not gone.is_empty():
			out.append("%d hands deserted in %s%s." % [gone.size(), Ports.port(port_id).name,
				" over unpaid wages" if unpaid_days >= 1.0 else (" sick of the ship" if low_morale > 0.0 else ", nursing grudges against you")])
	return out


static func _remove_hand(s: Dictionary, id: String) -> void:
	Crew.remove_hand(s, id)


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
	# Planned route as a dotted gold line, drawn in local space (this node is never rotated).
	var prev := Vector2.ZERO
	for p in route:
		draw_dashed_line(prev, p - position, Color(Style.c("header"), 0.75), 1.5, 4.0)
		prev = p - position
	for i in _wake.size():  # foam left behind, fading
		var a := float(i + 1) / _wake.size()
		var w: Vector2 = _wake[i] - position
		draw_rect(Rect2(w - Vector2(1, 1), Vector2(2, 2)), Color(0.95, 0.98, 1.0, a * 0.7))
