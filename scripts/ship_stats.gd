class_name ShipStats
## A ship's numbers: the type's stats from ships.json, changed by installed upgrades (set, then add, then multiply),
## and its speed changed again by condition and people (sails, fouling, crew, captain, officers).
## Every number can explain itself for tooltips. Works on the plain ship `state` dict so saves stay simple.

const LABELS := {"hull": "Hull", "sails": "Sails", "speed_knots": "Top speed (knots)", "turning": "Turning",
	"cargo": "Hold (tons)", "crew_min": "Crew needed", "crew_max": "Berths", "guns": "Guns",
	"gun_weight": "Gun weight (lb)", "swivels": "Swivel guns", "chase_guns": "Chase guns", "comfort": "Comfort",
	"fouling_rate": "Fouling rate", "upkeep": "Upkeep per day"}
const INT_STATS := ["hull", "sails", "turning", "cargo", "crew_min", "crew_max", "guns", "gun_weight", "swivels", "chase_guns", "comfort"]


static func effective(type_id: String, upgrades: Array) -> Dictionary:
	var s: Dictionary = Data.table("ships")[type_id].duplicate(true)
	for k in ["swivels", "chase_guns", "comfort"]:
		s[k] = s.get(k, 0)
	s.fouling_rate = 1.0
	for op in ["set", "add", "mult"]:
		for u in upgrades:
			var fx: Dictionary = Data.table("upgrades")[u].effects.get(op, {})
			for k in fx:
				match op:
					"set": s[k] = fx[k]
					"add": s[k] += fx[k]
					"mult": s[k] *= fx[k]
	for k in INT_STATS:
		s[k] = int(round(s[k]))
	return s


static func breakdown(type_id: String, upgrades: Array, key: String) -> String:
	var base = Data.table("ships")[type_id].get(key, 1.0 if key == "fouling_rate" else 0)
	var lines := PackedStringArray(["%s: %s" % [LABELS.get(key, key), _fmt(effective(type_id, upgrades)[key])],
		"%s: %s" % [Data.table("ships")[type_id].name, _fmt(base)]])
	for u in upgrades:
		var fx: Dictionary = Data.table("upgrades")[u].effects
		var name: String = Data.table("upgrades")[u].name
		if fx.get("set", {}).has(key): lines.append("%s: set to %s" % [name, _fmt(fx.set[key])])
		if fx.get("add", {}).has(key): lines.append("%s: %+d" % [name, fx.add[key]])
		if fx.get("mult", {}).has(key): lines.append("%s: x%.2f" % [name, fx.mult[key]])
	return "\n".join(lines)


static func headcount(state: Dictionary) -> int:
	return state.crew.size() + 1  # the captain eats too


static func captain(state: Dictionary) -> Dictionary:
	return People.person(state.captain)


## Skill of the officer in `role`. With nobody appointed, the captain covers it at half skill.
static func officer_skill(state: Dictionary, role: String) -> int:
	var skill: String = Data.rules.officer_roles[role].skill
	var id: String = state.officers.get(role, "")
	if id != "" and People.chars.has(id):
		return People.value(People.person(id), skill)
	return int(People.value(captain(state), skill) * 0.5)


static func crew_needed(state: Dictionary, stats: Dictionary) -> int:
	var cut: float = officer_skill(state, "boatswain") * Data.rules.condition.boatswain_crew_min_reduction_per_point
	return maxi(1, int(round(stats.crew_min * (1.0 - cut))))


## Speed multiplier from condition and people: {mult, text} where text is the tooltip breakdown.
static func condition(state: Dictionary, stats: Dictionary) -> Dictionary:
	var c: Dictionary = Data.rules.condition
	var parts := []
	var sails_frac: float = clampf(state.sails / float(stats.sails), 0.0, 1.0)
	parts.append(["Sails %d%%" % int(sails_frac * 100), lerpf(c.min_sail_speed, 1.0, sails_frac)])
	parts.append(["Fouled hull %d%%" % int(state.fouling * 100), 1.0 - c.fouling_speed_loss * state.fouling])
	var need := crew_needed(state, stats)
	var have := Crew.able(state)  # the sick don't haul on ropes
	if have < need:
		parts.append(["Short-handed %d / %d" % [have, need], maxf(c.min_crew_speed, float(have) / need)])
	var seam := People.value(captain(state), "seamanship")
	parts.append(["Captain's seamanship %d" % seam, 1.0 + (seam - 10) * c.seamanship_speed_per_point])
	var nav := officer_skill(state, "navigator")
	parts.append(["Navigation %d" % nav, 1.0 + nav * c.navigation_speed_per_point])
	var mult := 1.0
	var lines := PackedStringArray()
	for p in parts:
		mult *= p[1]
		lines.append("%s: x%.2f" % [p[0], p[1]])
	return {"mult": mult, "text": "\n".join(lines)}


## Chance per day of touching bottom in shallows (or on reefs, which threaten even sloops). A good navigator cuts it.
static func grounding_risk(state: Dictionary, stats: Dictionary, reef := false) -> float:
	var nav := officer_skill(state, "navigator")
	var d: Dictionary = Data.rules.draught[stats.draught]
	var base: float = d.reef_risk_per_day if reef else d.ground_risk_per_day
	return base * maxf(0.0, 1.0 - nav * Data.rules.grounding.navigation_reduction_per_point)


## Multiplier on the merchant's spread: the better haggler of captain and quartermaster narrows it.
static func spread_mult(state: Dictionary) -> float:
	var trade := maxi(People.value(captain(state), "trade"), officer_skill(state, "quartermaster"))
	return maxf(0.2, 1.0 - trade * Data.rules.people.trade_spread_reduction_per_point)


static func daily_cost(state: Dictionary, stats: Dictionary) -> float:
	var u: Dictionary = Data.rules.upkeep
	var officers: int = state.officers.size()
	return (state.crew.size() - officers) * u.wage_per_crew + officers * u.wage_per_crew * u.officer_wage_mult + stats.upkeep


static func upgrade_cost(u: String, type_id: String) -> int:
	var up: Dictionary = Data.table("upgrades")[u]
	var ship: Dictionary = Data.table("ships")[type_id]
	return int(up.cost + up.get("cost_per_hull", 0) * ship.hull + up.get("cost_per_gun", 0) * ship.guns)


## Why an upgrade can't be fitted here, or "" if it can.
static func cannot_install(state: Dictionary, u: String, shipyard: int) -> String:
	var up: Dictionary = Data.table("upgrades")[u]
	if u in state.upgrades: return "Already fitted."
	if shipyard < up.shipyard: return "Needs a large shipyard."
	if up.has("gun_weight") and up.gun_weight > Data.table("ships")[state.type].max_gun_weight:
		return "Too heavy for a %s." % Data.table("ships")[state.type].name
	if up.has("group") and up.group == "cannons" and up.gun_weight == effective(state.type, state.upgrades).gun_weight:
		return "Already carrying these guns."
	return ""


## Fits an upgrade, replacing any other in the same group.
static func install(state: Dictionary, u: String) -> void:
	var group: String = Data.table("upgrades")[u].get("group", "")
	if group != "":
		state.upgrades = state.upgrades.filter(func(x): return Data.table("upgrades")[x].get("group", "") != group)
	state.upgrades.append(u)


## What a shipyard pays for your current ship: worn hulls and sails are worth less; upgrades recover a little.
static func trade_in_value(state: Dictionary) -> int:
	var y: Dictionary = Data.rules.shipyard
	var stats := effective(state.type, state.upgrades)
	var condition_frac: float = (state.hull / float(stats.hull) + state.sails / float(stats.sails)) / 2.0
	var v: float = Data.table("ships")[state.type].price * y.trade_in * condition_frac
	for u in state.upgrades:
		v += upgrade_cost(u, state.type) * y.trade_in_upgrades
	return int(v)


static func _fmt(v) -> String:
	return "%.2f" % v if v is float and not is_equal_approx(v, round(v)) else str(int(v))
