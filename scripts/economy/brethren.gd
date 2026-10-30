class_name Brethren
extends RefCounted
## The pirates of the Caribbean as a population (data/economy.json "piracy"): companies of men, each with a captain
## and a ship, working the cruising grounds where the shipping is rich and the navy thin. Out-of-work seamen are the
## pool they recruit from: a war takes men into the navies and privateers, and the peace pays them off (Utrecht
## most of all). Prizes bring volunteers, big companies split, and disease, the navy, the gallows and the King's
## pardon thin them out. A nation that loses merchants sends more men-of-war, a year or so late. Many companies
## go north in the hurricane months, as the real ones did, and come back in the autumn.

var m: EconomyModel
var companies: Array = []  # [{id, captain, name, ship, men, ground, haven, prizes, formed, away}]
var idle := 0.0            # seamen out of work in the Americas
var service := 0.0         # seamen the wars have taken into navies and privateers
var pool := 0.0            # recruits gathering at the havens, not yet a crew
var war_weeks := 0         # how long the current war has run: a long war takes in far more men than a short one
var navy := {}             # nation -> men-of-war on station against the pirates
var pressure := {}         # nation -> its recent merchant losses, fading
var heat := {}             # ground -> recent prizes taken there: the navy hunts where it's hot
var pardons: Array = []    # nations offering a pardon, set by the game each day (like Traffic.wars)
var tally := {"hanged": 0, "pardoned": 0, "killed": 0, "gone_east": 0, "prizes": 0}
var events: Array = []     # [{text, port}]: news for the game to pass on
var next_id := 1


func _init(model: EconomyModel) -> void:
	m = model
	if not m.cfg.has("piracy"):
		return
	var c := cfg()
	idle = float(c.start.idle)
	service = float(c.start.get("service", 0))
	for f in c.navy_base:
		navy[f] = float(c.navy_base[f])
	for g in c.grounds:
		if not g.begins_with("_"):
			heat[g] = 0.0
	var left := int(c.start.men)
	while left >= int(c.new_crew):
		var men := mini(left, m.rng.randi_range(int(c.new_crew), int(c.split_at)))
		_form(men, havens(int(c.start.year)), _choose_ground(1), false)
		left -= men


func cfg() -> Dictionary:
	return m.cfg.piracy


func grounds() -> Array:
	return cfg().grounds.keys().filter(func(g): return not g.begins_with("_"))


## Men on the account, wherever they are.
func men() -> int:
	return companies.reduce(func(a, co): return a + co.men, 0)


func find(id: String) -> Dictionary:
	for co in companies:
		if co.id == id:
			return co
	return {}


## Havens open to pirates this year: where they sell their plunder and recruit.
func havens(year: int) -> Array:
	var out := []
	for id in cfg().havens:
		var h: Dictionary = cfg().havens[id]
		if year >= int(h.get("from", 0)) and year <= int(h.get("until", 99999)) and not m.world_has("haven_closed:" + id):
			out.append(id)
	return out


## How far the war has drawn in the seamen, 0 (peace) to 1: it builds up over war_ramp_weeks.
func mobilised() -> float:
	return minf(1.0, war_weeks / float(cfg().war_ramp_weeks))


func at_war(f: String) -> bool:
	return m.traffic.wars.any(func(p): return f in p)


# ---- the week ---------------------------------------------------------------------------------

func step(day: int, month: int, year: int) -> void:
	if day % 7 != 0 or not m.cfg.has("piracy"):
		return
	var c := cfg()
	war_weeks = war_weeks + 1 if not m.traffic.wars.is_empty() else 0
	var war := war_weeks > 0
	if war:  # the navies and the privateers take men in...
		var take := minf(idle, maxf(0.0, float(c.war_service) * mobilised() - service) * float(c.enlist_rate))
		idle -= take
		service += take
	else:  # ...and the peace pays them off
		var off := service * float(c.pay_off_rate)
		service -= off
		idle += off
	idle += float(c.new_hands) - idle * float(c.hired_rate)
	var open := havens(year)
	var prizes: float = heat.values().reduce(func(a, x): return a + x, 0.0)
	var lure := 1.0 + minf(float(c.lure_max), prizes * float(c.lure_per_prize))  # good hunting draws men
	var recruits := idle * float(c.recruit_rate) * (1.0 if not open.is_empty() else float(c.no_haven)) \
		* lerpf(1.0, float(c.war_recruit), mobilised()) * lure * m.world_mult("pirates")
	idle -= recruits
	pool += recruits
	if pool >= float(c.new_crew):
		_form(int(pool), open, _choose_ground(month), true)
		pool = 0.0
	_navy()
	for co in companies.duplicate():
		_week(co, month, open)
	for g in heat:
		heat[g] *= float(c.heat_decay)
	for f in pressure:
		pressure[f] *= float(c.pressure_decay)


func _week(co: Dictionary, month: int, open: Array) -> void:
	var c := cfg()
	co.men = int(round(co.men * (1.0 - float(c.attrition))))  # disease, drink and the sea
	if co.away:
		if month == int(c.return_month):
			co.away = false
			co.ground = _choose_ground(month)
	elif _in(month, c.north_months) and m.rng.randf() < float(c.north_chance):
		co.away = true  # gone north for the hurricane months, to the Carolinas and the Banks
	else:
		var hunt := hunting(co.ground)
		if m.rng.randf() < float(c.catch_rate) * hunt / (1.0 + co.men / float(c.catch_men)):
			lose(co.id, "navy")
			return
		if not pardons.is_empty() and m.rng.randf() < float(c.pardon_take) * (1.0 + hunt):
			lose(co.id, "pardon")
			return
		if open.is_empty() and m.rng.randf() < float(c.east_chance):
			lose(co.id, "east")
			return
		if m.rng.randf() < float(c.war_commission) * mobilised():
			lose(co.id, "commission")
			return
		if co.men > int(c.split_at) and m.rng.randf() < float(c.split_chance):
			var part := int(co.men * float(c.split_share))
			co.men -= part
			_form(part, open, _choose_ground(month), true, co)
		elif m.rng.randf() < float(c.regroup_chance):
			co.ground = _choose_ground(month)
		if not co.haven in open:
			co.haven = open[m.rng.randi() % open.size()] if not open.is_empty() else ""
	if co.men < int(c.disband_below):
		idle += co.men
		companies.erase(co)
		return
	co.ship = ship_for(co.men)


## Each nation's men-of-war against the pirates: a base squadron, and more as its merchants are lost, slowly.
func _navy() -> void:
	var c := cfg()
	for f in c.navy_base:
		var target := minf(float(c.navy_max[f]), float(c.navy_base[f]) + pressure.get(f, 0.0) * float(c.ships_per_loss))
		navy[f] += (target - navy[f]) * (float(c.navy_up) if target > navy[f] else float(c.navy_down))


## Men-of-war hunting on a ground: those not busy with a war, spread toward where prizes are being taken.
func hunting(g: String) -> float:
	var c := cfg()
	var total := 0.0
	for f in navy:
		total += navy[f] * (float(c.war_diversion) if at_war(f) else 1.0)
	var sum: float = heat.values().reduce(func(a, x): return a + x, 0.0)
	return total * (heat.get(g, 0.0) + float(c.heat_floor)) / (sum + float(c.heat_floor) * heat.size())


## Where a company goes cruising: rich shipping, few men-of-war.
func _choose_ground(month: int) -> String:
	var best := ""
	var best_score := -1.0
	for g in grounds():
		var ports: Array = cfg().grounds[g].ports
		var ships := m.traffic.voyages.filter(func(v): return v.origin in ports or v.dest in ports).size()
		var score := (ships + 1.0) / (1.0 + hunting(g) * float(cfg().navy_fear)) * m.rng.randf_range(0.5, 1.5)
		if _in(month, cfg().grounds[g].get("quiet_months", [])):
			score *= 0.5
		if score > best_score:
			best = g
			best_score = score
	return best


static func _in(month: int, months: Array) -> bool:  # JSON numbers are floats
	return months.any(func(x): return int(x) == month)


func ship_for(n: int) -> String:
	for step in cfg().ships:
		if n <= int(step[0]):
			return step[1]
	return cfg().ships[-1][1]


func _form(n: int, open: Array, ground: String, tell: bool, parent := {}) -> void:
	var c := cfg()
	var names: Dictionary = c.names
	var co := {"id": "co%d" % next_id, "captain": "%s %s" % [names.first[m.rng.randi() % names.first.size()], names.last[m.rng.randi() % names.last.size()]],
		"name": names.ships[m.rng.randi() % names.ships.size()], "ship": ship_for(n), "men": n,
		"ground": ground if ground != "" else grounds()[m.rng.randi() % grounds().size()],
		"haven": open[m.rng.randi() % open.size()] if not open.is_empty() else "", "prizes": 0, "formed": m.day, "away": false}
	next_id += 1
	companies.append(co)
	if not tell:
		return
	var where: String = c.grounds[co.ground].name
	if not parent.is_empty():
		_news("Captain %s has left %s with %d men and a prize sloop renamed the %s, to cruise %s." % [co.captain, parent.captain, n, co.name, where], co)
	else:
		_news("A new company of %d men has gone on the account%s: Captain %s in the %s, bound for %s." % [n,
			" at " + m.ports[co.haven].name if co.haven != "" else "", co.captain, co.name, where], co)


# ---- what happens to them -----------------------------------------------------------------------

## A merchant voyage lost (Traffic.lose): her nation feels it, and the pirates who took her grow.
## company: the company that took her, if known (a ship on the map); otherwise one working her route.
func on_loss(v: Dictionary, cause: String, company := "") -> void:
	if not m.cfg.has("piracy") or not cause in ["pirates", "player"]:
		return
	pressure[v.faction] = pressure.get(v.faction, 0.0) + 1.0
	if cause != "pirates":
		return
	var co := find(company) if company != "" else _raider(v.origin, v.dest)
	if co.is_empty():
		return
	co.prizes += 1
	co.men += m.rng.randi_range(int(cfg().volunteers[0]), int(cfg().volunteers[1]))  # her sailors sign the articles
	heat[co.ground] = heat.get(co.ground, 0.0) + 1.0
	tally.prizes += 1


func _raider(a: String, b: String) -> Dictionary:
	var on := companies.filter(func(co): return not co.away and covers(co.ground, a, b))
	return on[m.rng.randi() % on.size()] if not on.is_empty() else {}


func covers(g: String, a: String, b: String) -> bool:
	var ports: Array = cfg().grounds.get(g, {}).get("ports", [])
	return a in ports or b in ports


## How dangerous a route is, 0 to 1, from the men cruising the grounds at either end. It levels off: twice the
## pirates don't take twice the ships, they compete for the same prey.
func threat(a: String, b: String) -> float:
	if not m.cfg.has("piracy"):
		return m.world_mult("pirates")
	var n := 0.0
	for co in companies:
		if not co.away and covers(co.ground, a, b):
			n += co.men
	return (1.0 - exp(-n / float(cfg().threat_men))) * m.world_mult("pirates")


## A company's end. cause: navy (run down; some hang), player (you took or sank her), pardon (they take the King's
## mercy, and go back to the pool of idle men: some will be back), east (off to Africa and the Indian Ocean).
func lose(id: String, cause: String) -> void:
	var co := find(id)
	if co.is_empty():
		return
	companies.erase(co)
	var c := cfg()
	var port: String = c.grounds[co.ground].ports[0]
	match cause:
		"navy", "player":
			var hanged := int(co.men * float(c.hanged_share))
			tally.hanged += hanged
			tally.killed += co.men - hanged
			idle += co.men * float(c.escaped_share)
			if cause == "navy":
				_news("Men-of-war have taken Captain %s's %s off %s. %d of the company will hang." % [co.captain, co.name, c.grounds[co.ground].name, hanged], co, port)
		"pardon":
			tally.pardoned += co.men
			idle += co.men
			_news("Captain %s and %d men of the %s have come in for the King's pardon." % [co.captain, co.men, co.name], co, port)
		"commission":  # a war on: privateering pays as well, and you don't hang for it
			service += co.men
			_news("With a war on, Captain %s and the %s have taken a privateer's commission." % [co.captain, co.name], co, port)
		"east":
			tally.gone_east += co.men
			_news("With no haven left in the islands, Captain %s has taken the %s east, for the coast of Africa." % [co.captain, co.name], co, port)


func _news(text: String, co: Dictionary, port := "") -> void:
	events.append({"text": text, "port": port if port != "" else (co.haven if co.haven != "" else cfg().grounds[co.ground].ports[0])})


func take_events() -> Array:
	var out := events
	events = []
	return out


func save_state() -> Dictionary:
	return {"companies": companies, "idle": idle, "service": service, "pool": pool, "navy": navy, "pressure": pressure,
		"heat": heat, "tally": tally, "next_id": next_id, "war_weeks": war_weeks}


func load_state(d: Dictionary) -> void:
	companies = d.companies
	for co in companies:
		co.men = int(co.men)
		co.prizes = int(co.prizes)
	idle = float(d.idle)
	service = float(d.service)
	pool = float(d.pool)
	navy = d.navy
	pressure = d.pressure
	heat = d.heat
	tally = d.tally
	next_id = int(d.next_id)
	war_weeks = int(d.get("war_weeks", 0))
