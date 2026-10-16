extends Node
## Autoload "Weather": the trade wind, calm spells, and storms that move across the map.
## Storms are visible circles so the player can choose to wait in port, run before them or sail around them.

var rng := RandomNumberGenerator.new()
var wind_dir := 70.0      # compass bearing the wind blows FROM
var wind_strength := 1.0  # multiplies ship speed
var calm := false
var storms: Array = []  # {kind, pos: Vector2, vel: Vector2 (px/day), radius, days_left}


func _ready() -> void:
	rng.randomize()
	wind_dir = Data.rules.weather.trade_wind_from
	Clock.ticked.connect(move_storms)
	Clock.day_passed.connect(func(_d): new_day(Clock.date().month))


## Wind felt at a map position: {dir, strength, storm: kind id or ""}.
func wind_at(pos: Vector2) -> Dictionary:
	for s in storms:
		if pos.distance_to(s.pos) < s.radius:
			var spec: Dictionary = Data.rules.storms[s.kind]
			# Fronts (northers) blow from one direction; true storms turn anticlockwise in the northern
			# hemisphere, so the wind comes from 90 degrees clockwise of the bearing to the eye.
			var dir: float = spec.wind_from if spec.has("wind_from") else fposmod(Geo.bearing(pos - s.pos) + 90.0, 360.0)
			return {"dir": dir, "strength": spec.wind_strength, "storm": s.kind}
	return {"dir": wind_dir, "strength": wind_strength, "storm": ""}


## The light of the hour: "dawn", "day", "dusk" or "night" (matching the map's day and night tint).
static func light() -> String:
	var hour := fposmod(Clock.day, 1.0) * 24.0
	if hour >= 4.5 and hour < 7.0:
		return "dawn"
	if hour >= 17.5 and hour < 20.0:
		return "dusk"
	return "night" if hour >= 20.0 or hour < 4.5 else "day"


## How far a lookout sees here, as a share of a clear day's sight: fog, rain and the dark hide ships,
## both from you and you from them.
func visibility(pos: Vector2) -> float:
	var v: Dictionary = Data.rules.visibility
	return float(v.get(wind_at(pos).storm, 1.0)) * float(v.get(light(), 1.0))


func move_storms(delta_days: float) -> void:
	for s in storms:
		s.pos += s.vel * delta_days


func new_day(month: int) -> void:
	var w: Dictionary = Data.rules.weather
	# Wind wanders randomly but is pulled back toward the trade wind.
	var off := fposmod(wind_dir - w.trade_wind_from + 180.0, 360.0) - 180.0
	wind_dir = fposmod(wind_dir + rng.randfn(0.0, w.wind_drift_deg) - off * w.wind_pull, 360.0)

	calm = rng.randf() < (w.calm_persist if calm else w.calm_chance)
	wind_strength = w.calm_strength if calm else rng.randf_range(w.fair_strength[0], w.fair_strength[1])

	for s in storms:
		s.days_left -= 1
	storms = storms.filter(func(s): return s.days_left > 0)
	for kind in Data.rules.storms:
		if rng.randf() < Data.rules.storms[kind].daily_chance_by_month[month - 1]:
			spawn_storm(kind)


func spawn_storm(kind: String) -> Dictionary:
	var spec: Dictionary = Data.rules.storms[kind]
	var size := Vector2(Data.map.size[0], Data.map.size[1])
	var area: Array = spec.spawn_area
	var heading: float = spec.heading + rng.randf_range(-spec.heading_spread, spec.heading_spread)
	var s := {
		"kind": kind,
		"pos": Vector2(rng.randf_range(area[0], area[2]) * size.x, rng.randf_range(area[1], area[3]) * size.y),
		"vel": Geo.from_bearing(heading) * Geo.knots_to_px_per_day(spec.speed_knots),
		"radius": spec.radius_nm * Geo.px_per_nm(),
		"days_left": rng.randi_range(spec.days[0], spec.days[1]),
	}
	storms.append(s)
	return s


func save_state() -> Dictionary:
	return {"rng": str(rng.state), "wind_dir": wind_dir, "wind_strength": wind_strength, "calm": calm, "storms": storms}


func load_state(d: Dictionary) -> void:
	rng.state = int(d.rng)
	wind_dir = d.wind_dir
	wind_strength = d.wind_strength
	calm = d.calm
	storms = d.storms
