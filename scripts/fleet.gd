class_name Fleet
## Your other ships. They begin as prizes, and the list keeps that name (s.prizes): each sails with you at the
## squadron's pace, with hands drawn from your crew, and carries her own cargo. Give one a captain and enough hands
## and she's a consort: she fights beside you (and draws fire), and her captain has opinions about you. A captain
## who comes to hate you may simply sail away with her.
## Entry: {type, name, faction, hull, sails, crew: [ids], cargo: {}, captain: id or "", upgrades: [], fouling,
##         guns_lost, look: {}, fights: bool}


static func cfg() -> Dictionary:
	return Data.rules.fleet


static func max_ships() -> int:
	return int(cfg().max_consorts)


## Fills in what older entries (plain prizes) lack.
static func ensure(p: Dictionary) -> Dictionary:
	for k in {"captain": "", "upgrades": [], "fouling": 0.0, "guns_lost": 0, "look": {}, "fights": true, "cargo": {}, "crew": []}.keys():
		if not p.has(k):
			p[k] = {"captain": "", "upgrades": [], "fouling": 0.0, "guns_lost": 0, "look": {}, "fights": true, "cargo": {}, "crew": []}[k]
	return p


static func stats(p: Dictionary) -> Dictionary:
	return ShipStats.effective(p.type, ensure(p).upgrades)


static func hands(p: Dictionary) -> int:
	return ensure(p).crew.size() + (1 if p.captain != "" else 0)


static func fight_need(p: Dictionary) -> int:
	return ceili(stats(p).crew_min * cfg().fight_crew_fraction)


## A consort: a captain and enough hands to fight her.
static func is_consort(p: Dictionary) -> bool:
	return ensure(p).captain != "" and People.chars.has(p.captain) and hands(p) >= fight_need(p)


static func headcount(s: Dictionary) -> int:
	var n := 0
	for p in s.get("prizes", []):
		n += hands(p)
	return n


## Daily cost of the other ships: their hands' wages, a captain's pay, and a consort's upkeep.
static func daily_cost(s: Dictionary) -> float:
	var u: Dictionary = Data.rules.upkeep
	var cost := 0.0
	for p in s.get("prizes", []):
		cost += ensure(p).crew.size() * u.wage_per_crew
		if p.captain != "":
			cost += u.wage_per_crew * u.officer_wage_mult + stats(p).upkeep * cfg().consort_upkeep_mult
	return cost


## Moves n hands to the ship at i (or back aboard the flagship if n < 0). Officers stay where they are.
static func transfer(s: Dictionary, i: int, n: int) -> String:
	var p := ensure(s.prizes[i])
	if n > 0:
		var spare: Array = s.crew.filter(func(id): return not id in s.officers.values())
		spare.sort_custom(func(a, b): return People.value(People.person(a), "seamanship") < People.value(People.person(b), "seamanship"))
		n = mini(n, mini(spare.size(), stats(p).crew_max - hands(p)))
		if n <= 0:
			return "No spare hands, or no berths aboard her."
		for id in spare.slice(0, n):
			s.crew.erase(id)
			p.crew.append(id)
		return "%d hands cross to the %s." % [n, p.name]
	n = mini(-n, p.crew.size())
	if n <= 0:
		return "Nobody aboard her to bring back."
	for k in n:
		s.crew.append(p.crew.pop_back())
	return "%d hands come back aboard." % n


## Puts a captain in command of the ship at i (from your crew; not an officer). "" brings her captain home.
static func appoint(s: Dictionary, i: int, id: String) -> String:
	var p := ensure(s.prizes[i])
	if p.captain != "":
		s.crew.append(p.captain)
		p.captain = ""
	if id == "":
		return "The %s has no captain now." % p.name
	if not id in s.crew or id in s.officers.values():
		return "Choose someone from the crew who holds no post."
	s.crew.erase(id)
	p.captain = id
	People.person(id).history.append("Given command of the %s, %s." % [p.name, Clock.date_string()])
	var dream: String = Wants.resolve(s, id, "done") if Wants.open(People.person(id), "own_ship") else ""  # what they always wanted
	return ("%s takes command of the %s. %s" % [People.person(id).name, p.name, dream]).strip_edges()


## Everyone aboard her rejoins the flagship's crew (when she's sold, laid up or given up).
static func return_people(s: Dictionary, p: Dictionary) -> void:
	ensure(p)
	s.crew.append_array(p.crew)
	p.crew = []
	if p.captain != "":
		s.crew.append(p.captain)
		p.captain = ""


## Shift your flag: you, your officers and your crew go aboard her; her crew and captain take your old ship.
## The cargo goes across with you, so it must fit.
static func shift_flag(s: Dictionary, i: int) -> String:
	var p := ensure(s.prizes[i])
	if Market.cargo_used(s.cargo) > stats(p).cargo:
		return "Your cargo won't fit in her hold."
	for k in ["type", "name", "hull", "sails", "upgrades", "fouling", "guns_lost", "look"]:
		var mine = s.get(k, {} if k == "look" else 0)
		s[k] = p[k]
		p[k] = mine
	return "You shift your flag to the %s." % s.name


## Moves up to qty of a good between the flagship's hold and hers (to_her: from you to her).
static func move_cargo(s: Dictionary, i: int, good: String, qty: float, to_her: bool, flagship_capacity: float) -> String:
	var p := ensure(s.prizes[i])
	var from: Dictionary = s.cargo if to_her else p.cargo
	var room: float = (stats(p).cargo - Market.cargo_used(p.cargo)) if to_her else (flagship_capacity - Market.cargo_used(s.cargo))
	qty = minf(minf(qty, from.get(good, 0.0)), room)
	if qty <= 0.0:
		return "No room, or nothing to move."
	from[good] -= qty
	if from[good] <= 0.0:
		from.erase(good)
	var into: Dictionary = p.cargo if to_her else s.cargo
	into[good] = into.get(good, 0.0) + qty
	if not to_her and p.get("faction", "") != "":
		s.stolen[good] = s.stolen.get(good, 0.0) + qty  # taken goods stay stolen
	return "Moved %d %s." % [qty, Data.table("goods")[good].name.to_lower()]


## Consorts that will fight beside you, as battle allies.
static func allies(s: Dictionary) -> Array:
	var out := []
	for i in s.get("prizes", []).size():
		var p: Dictionary = ensure(s.prizes[i])
		if is_consort(p) and p.fights:
			var st := stats(p)
			out.append({"name": p.name, "guns": maxi(0, st.guns - p.guns_lost), "gun_weight": st.gun_weight,
				"gunnery": People.value(People.person(p.captain), "gunnery"), "id": "", "consort": i, "hull_lost": 0.0,
				"type": p.type, "look": p.look})
	return out


## After a fight, consorts take the damage they drew. One driven under is lost with everyone aboard.
static func after_battle(s: Dictionary, allies: Array) -> Array:
	var msgs := []
	var lost := []
	for a in allies:
		if not a.has("consort") or a.consort >= s.prizes.size():
			continue
		var p: Dictionary = s.prizes[a.consort]
		p.hull -= a.hull_lost
		if p.hull <= 0.0:
			lost.append(p)
			for id in p.crew + ([p.captain] if p.captain != "" else []):
				People.person(id).alive = false
				People.person(id).history.append("Went down with the %s, %s." % [p.name, Clock.date_string()])
			msgs.append("The %s goes down with all hands%s." % [p.name, "" if p.captain == "" else ", Captain " + People.person(p.captain).name + " among them"])
		elif a.hull_lost > 0.0:
			msgs.append("The %s took %d damage covering you." % [p.name, a.hull_lost])
	for p in lost:
		s.prizes.erase(p)
	return msgs


## A captain who's come to hate you may take the ship and go. Returns messages.
static func daily(s: Dictionary, rng: RandomNumberGenerator) -> Array:
	var msgs := []
	for p in s.get("prizes", []).duplicate():
		ensure(p)
		if p.captain == "" or not People.chars.has(p.captain):
			continue
		var c := People.person(p.captain)
		var chance: float = cfg().desert_chance_per_day * (2.0 if "ambitious" in c.traits else 1.0)
		if c.relations.get(s.captain, 0) <= int(cfg().desert_opinion) and rng.randf() < chance:
			s.prizes.erase(p)
			for id in p.crew:
				People.person(id).history.append("Sailed off in the %s with %s." % [p.name, c.name])
			msgs.append("Mutiny in the squadron! " + Bonds.former_officer(s, p.captain, -2, p))
	return msgs
