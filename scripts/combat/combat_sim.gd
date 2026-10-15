class_name CombatSim
extends RefCounted
## Ship-to-ship battle maths, kept apart from drawing so it can be tested.
## Two ships manoeuvre in the real wind (same polars as the world map); broadsides only bear within an arc
## off either beam. Units: combat pixels and seconds. ships[0] is the player, ships[1] the enemy.

const SIDE_SIGN := {"port": -1.0, "starboard": 1.0}

var ships: Array = []
var wind_dir := 70.0
var wind_strength := 1.0
var rng := RandomNumberGenerator.new()
var events: Array = []  # for the view: broadsides and notable hits; the view clears it
var result := ""        # "", "enemy_struck", "player_struck", "enemy_sunk", "player_sunk", "separated", "boarding"
var boarded_by := -1    # who started a boarding
var time := 0.0


static func cfg() -> Dictionary:
	return Data.rules.combat


## data: {name, type, upgrades, hull, sails, crew, gunnery, swordplay, captain_swordplay, morale, carpentry,
##        behaviour, guns_lost}. Returns the live combat dict.
static func make_ship(data: Dictionary) -> Dictionary:
	var s := data.duplicate(true)
	s.stats = ShipStats.effective(data.type, data.get("upgrades", []))
	s.pos = Vector2.ZERO
	s.heading = 0.0
	s.speed = 0.0
	s.helm = 0.0          # -1 turn to port .. +1 turn to starboard
	s.sail_setting = 1
	s.rudder = 1.0
	s.masts = int(s.stats.masts)
	s.leak = 0.0
	s.guns_working = int(s.stats.guns) - int(data.get("guns_lost", 0))
	s.reload = {"port": 0.0, "starboard": 0.0}
	s.ammo = "round"
	s.crew = float(s.crew)
	s.crew_start = s.crew
	s.hull_start = float(s.hull)
	s.casualties = 0.0
	s.struck = false
	return s


func setup(player: Dictionary, enemy: Dictionary, wdir: float, wstrength: float, mode: String) -> void:
	ships = [player, enemy]
	wind_dir = wdir
	wind_strength = wstrength
	var dist: float = cfg().start_distance[mode]
	var bearing := rng.randf_range(0.0, 360.0)
	enemy.pos = player.pos + Geo.from_bearing(bearing) * dist
	match mode:
		"attack":  # you close on them; merchants already turning away
			player.heading = bearing
			enemy.heading = bearing + rng.randf_range(-60.0, 60.0)
		"defend":  # they bear down on you
			player.heading = bearing + 90.0
			enemy.heading = bearing + 180.0
		"flee":    # you're running, they're chasing
			player.heading = bearing + 180.0
			enemy.heading = bearing + 180.0
			player.sail_setting = 2
	for s in ships:
		s.heading = fposmod(s.heading, 360.0)
		s.speed = target_speed(s) * 0.7


func other(s: Dictionary) -> Dictionary:
	return ships[1] if s == ships[0] else ships[0]


func distance() -> float:
	return ships[0].pos.distance_to(ships[1].pos)


func step(dt: float) -> void:
	if result != "":
		return
	time += dt
	_ai(ships[1])
	for s in ships:
		_move(s, dt)
		for side in s.reload:
			s.reload[side] = maxf(0.0, s.reload[side] - dt)
		if s.leak > 0.0:
			s.hull -= s.leak * dt
			s.leak = maxf(0.0, s.leak - s.get("carpentry", 0) * 0.0015 * dt)  # the carpenter plugs shot holes
	_check_end()


func _move(s: Dictionary, dt: float) -> void:
	var max_speed: float = s.stats.speed_knots * cfg().px_per_knot
	var way := clampf(s.speed / maxf(max_speed, 1.0), 0.0, 1.0)  # ships need way on to answer the helm
	var turn: float = cfg().turn_deg_per_point * s.stats.turning * s.rudder * (0.4 + 0.6 * way)
	s.heading = fposmod(s.heading + s.helm * turn * dt, 360.0)
	s.speed += (target_speed(s) - s.speed) * minf(1.0, cfg().accel_per_second * dt)
	s.pos += Geo.from_bearing(s.heading) * s.speed * dt


func target_speed(s: Dictionary, heading := -1.0) -> float:
	var h: float = s.heading if heading < 0.0 else heading
	var c: Dictionary = Data.rules.condition
	var sails_frac := clampf(s.sails / float(s.stats.sails), 0.0, 1.0)
	var crew_frac := clampf(s.crew / float(s.stats.crew_min), c.min_crew_speed, 1.0)
	return (s.stats.speed_knots * Sailing.polar_factor(s.stats.polar, Geo.angle_between(h, wind_dir)) * wind_strength
		* cfg().sail_settings[s.sail_setting].speed * lerpf(c.min_sail_speed, 1.0, sails_frac)
		* float(s.masts) / s.stats.masts * crew_frac * cfg().px_per_knot)


static func gun_range(s: Dictionary, ammo := "") -> float:
	var a: String = s.ammo if ammo == "" else ammo
	return (cfg().gun_range_base + cfg().gun_range_per_lb * s.stats.gun_weight) * cfg().ammo[a].range


## Guns that can fire in one broadside: half the working guns, if there are hands to serve them.
static func manned_guns(s: Dictionary) -> int:
	return mini(int(s.guns_working / 2.0), int(s.crew / cfg().crew_per_gun))


static func reload_time(s: Dictionary) -> float:
	var shorthanded := maxf(1.0, s.stats.crew_min / maxf(s.crew, 1.0))
	return cfg().reload_seconds * (1.3 - s.gunnery * 0.03) * cfg().sail_settings[s.sail_setting].reload * shorthanded


## Which broadside bears on a point: "port", "starboard" or "".
static func bearing_side(s: Dictionary, target: Vector2) -> String:
	var rel := fposmod(Geo.bearing(target - s.pos) - s.heading + 180.0, 360.0) - 180.0
	var arc: float = cfg().broadside_arc
	if absf(rel - 90.0) <= arc: return "starboard"
	if absf(rel + 90.0) <= arc: return "port"
	return ""


func hit_chance(s: Dictionary, t: Dictionary, dist: float) -> float:
	var r := dist / gun_range(s)
	return clampf(cfg().base_accuracy * (1.0 - 0.7 * r * r) * (0.6 + s.gunnery / 25.0) * (0.8 + t.stats.hull / 1000.0), 0.02, 0.95)


## Switching shot means drawing the old charges: both broadsides start reloading.
func set_ammo(s: Dictionary, ammo: String) -> void:
	if s.ammo == ammo:
		return
	s.ammo = ammo
	for side in s.reload:
		s.reload[side] = reload_time(s)


func fire(s: Dictionary, side: String) -> bool:
	if s.reload[side] > 0.0 or s.struck or result != "":
		return false
	var guns := manned_guns(s)
	if guns <= 0:
		return false
	var t := other(s)
	var dist: float = s.pos.distance_to(t.pos)
	var bears := bearing_side(s, t.pos) == side and dist <= gun_range(s)
	var hits := 0
	if bears:
		var p := hit_chance(s, t, dist)
		for i in guns:
			if rng.randf() < p:
				hits += 1
		apply_hits(t, hits, s.stats.gun_weight, s.ammo)
	s.reload[side] = reload_time(s)
	var aim: Vector2 = t.pos if bears else s.pos + Geo.from_bearing(s.heading + 90.0 * SIDE_SIGN[side]) * gun_range(s)
	events.append({"kind": "broadside", "from": s.pos, "to": aim, "who": ships.find(s), "hits": hits, "guns": guns, "ammo": s.ammo})
	return true


func apply_hits(t: Dictionary, hits: int, gun_weight: float, ammo: String) -> void:
	if hits <= 0:
		return
	var a: Dictionary = cfg().ammo[ammo]
	var crew_before: float = t.crew
	var hull_before: float = t.hull
	for i in hits:
		t.hull -= gun_weight * a.hull
		t.sails = maxf(0.0, t.sails - gun_weight * a.sails)
		var killed := minf(t.crew, gun_weight * a.crew * rng.randf_range(0.5, 1.5))
		t.crew -= killed
		t.casualties += killed
		if rng.randf() < a.get("gun_chance", 0.0) and t.guns_working > 0:
			t.guns_working -= 1
			_note(t, "A gun is dismounted")
		if rng.randf() < a.get("leak_chance", 0.0):
			t.leak += gun_weight * cfg().leak_per_lb
			_note(t, "Holed below the waterline")
		if rng.randf() < a.get("rudder_chance", 0.0) and t.rudder > 0.25:
			t.rudder -= 0.25
			_note(t, "Rudder damaged")
		if rng.randf() < a.get("mast_chance", 0.0) and t.masts > 0:
			t.masts -= 1
			_note(t, "A mast comes down!")
	var crew_pct: float = (crew_before - t.crew) / maxf(t.crew_start, 1.0) * 100.0
	var hull_pct: float = (hull_before - t.hull) / t.hull_start * 100.0
	t.morale -= crew_pct * cfg().morale_per_crew_lost_pct + hull_pct * cfg().morale_per_hull_lost_pct


func _note(t: Dictionary, text: String) -> void:
	events.append({"kind": "note", "who": ships.find(t), "text": text, "pos": t.pos})


func relative_speed() -> float:
	var v0: Vector2 = Geo.from_bearing(ships[0].heading) * ships[0].speed
	var v1: Vector2 = Geo.from_bearing(ships[1].heading) * ships[1].speed
	return (v0 - v1).length()


func can_board() -> bool:
	return distance() <= cfg().board_distance and relative_speed() <= cfg().board_max_relative_speed


func board(who: int) -> bool:
	if not can_board() or result != "":
		return false
	result = "boarding"
	boarded_by = who
	return true


func strike(who: int) -> void:
	ships[who].struck = true
	result = "player_struck" if who == 0 else "enemy_struck"


func _check_end() -> void:
	if result != "":
		return
	if ships[1].hull <= 0.0:
		result = "enemy_sunk"
	elif ships[0].hull <= 0.0:
		result = "player_sunk"
	elif ships[0].morale <= 0.0:
		strike(0)  # your crew strike the colours themselves
	elif distance() > cfg().escape_distance:
		result = "separated"


# ---- Enemy AI --------------------------------------------------------------

func _ai(s: Dictionary) -> void:
	if s.struck:
		return
	var p := other(s)
	var dist := distance()
	var mode: String = s.behaviour
	if mode != "merchant" and (s.hull < cfg().ai_flee_hull * s.hull_start or s.morale < cfg().ai_flee_morale):
		mode = "flee"
	if _should_strike(s, mode, dist):
		strike(1)
		return

	var desired: float
	if mode == "merchant" or mode == "flee":
		desired = _escape_heading(s, p)
		s.sail_setting = 2
	else:
		var to_p := Geo.bearing(p.pos - s.pos)
		if _wants_board(s, p):
			desired = to_p
			s.sail_setting = 1
			if can_board():
				board(1)
				return
		elif dist > gun_range(s) * 0.8:
			desired = to_p
			s.sail_setting = 2
		else:  # turn to present a broadside: whichever beam is closer to the current heading
			var a := fposmod(to_p - 90.0, 360.0)
			var b := fposmod(to_p + 90.0, 360.0)
			desired = a if Geo.angle_between(a, s.heading) < Geo.angle_between(b, s.heading) else b
			s.sail_setting = 1
		desired = _avoid_irons(desired)
	s.helm = clampf((fposmod(desired - s.heading + 180.0, 360.0) - 180.0) / 30.0, -1.0, 1.0)

	var side := bearing_side(s, p.pos)
	if side != "":
		set_ammo(s, _ai_ammo(s, p, dist))
		if dist <= gun_range(s) * 0.95:
			fire(s, side)


func _should_strike(s: Dictionary, mode: String, dist: float) -> bool:
	var sr: Dictionary = cfg().surrender
	var threshold: float = sr.merchant_morale if s.behaviour == "merchant" else sr.morale
	var close := dist < gun_range(other(s)) * 1.1
	return close and (s.morale <= threshold or s.hull < sr.hull_fraction * s.hull_start)


func _wants_board(s: Dictionary, p: Dictionary) -> bool:
	var edge := 1.3 if s.behaviour == "aggressive" else 1.8
	return s.crew > p.crew * edge


func _ai_ammo(s: Dictionary, p: Dictionary, dist: float) -> String:
	if s.behaviour == "aggressive":  # pirates want the prize intact
		if dist <= gun_range(s, "grape") and _wants_board(s, p):
			return "grape"
		return "chain" if p.sails > p.stats.sails * 0.4 and dist <= gun_range(s, "chain") else s.ammo
	return "round"


## Best heading to open the distance: fast and away.
func _escape_heading(s: Dictionary, p: Dictionary) -> float:
	var away := Geo.bearing(s.pos - p.pos)
	var best := away
	var best_score := -INF
	for h in range(0, 360, 15):
		var score := target_speed(s, float(h)) * cos(deg_to_rad(Geo.angle_between(float(h), away)))
		if score > best_score:
			best_score = score
			best = float(h)
	return best


## Never point straight into the wind: bear away to a close-hauled course instead.
func _avoid_irons(desired: float) -> float:
	if Geo.angle_between(desired, wind_dir) >= 45.0:
		return desired
	var a := fposmod(wind_dir - 50.0, 360.0)
	var b := fposmod(wind_dir + 50.0, 360.0)
	return a if Geo.angle_between(a, desired) < Geo.angle_between(b, desired) else b
