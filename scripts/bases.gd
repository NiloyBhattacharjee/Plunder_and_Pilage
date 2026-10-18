extends Node
## Autoload "Bases": hidden coves, and the bases you build in them. A base is home, income and staging point:
## it stores plunder safely, produces goods, repairs and careens cheaply, recruits, holds prizes and hostages.
## It needs a garrison, food and money; an officer runs it, and their skills matter. Activity makes it visible,
## and visible bases get raided: be there to fight, or trust the walls. Tables: data/coves.json, data/buildings.json.
##   bases[cove]: {name, buildings: [ids], building: {id, left} or {}, garrison, manager, storage: {good: qty},
##                 stolen: {good: qty}, gold, visibility, loyalty, recruits, prizes: [], hostages: [{..., day}],
##                 raid: {day, kind, faction, captain, warned} or {}, unpaid,
##                 town: {from, since, failed (expeditions beaten)} and taxes ("light"/"fair"/"heavy") for a town you hold}
## A town taken and held (scripts/sieges.gd) is a base too, keyed by its port id: it pays taxes, needs no hiding,
## keeps your laws (no duties, no contraband, pirates welcome) and has no officials but your manager, and its old
## masters send ever stronger expeditions to take it back. A base whose loyalty collapses rises against you.

signal news(text: String)

var discovered: Array = []
var bases := {}
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func reset() -> void:
	discovered = []
	bases = {}


static func cfg() -> Dictionary:
	return Data.rules.bases


static func cove(id: String) -> Dictionary:
	if Data.table("ports").has(id):  # a town you hold
		var p: Dictionary = Data.table("ports")[id]
		return {"name": p.name, "lat": p.lat, "lon": p.lon, "shelter": 0, "soil": true, "water": true, "description": p.description}
	return Data.table("coves")[id]


static func building(id: String) -> Dictionary:
	return Data.table("buildings")[id]


static func cove_pos(id: String) -> Vector2:
	return Geo.latlon_to_px(cove(id).lat, cove(id).lon)


static func has(b: Dictionary, building_id: String) -> bool:
	return building_id in b.buildings


# ---- finding and claiming ------------------------------------------------------------

## Sailing close to an undiscovered cove: your navigator may spot it. Returns a message or "".
func look_for_coves(s: Dictionary, pos: Vector2) -> String:
	for id in Data.table("coves"):
		if id.begins_with("_") or id in discovered:
			continue
		if pos.distance_to(cove_pos(id)) > cfg().discover_nm * Geo.px_per_nm():
			continue
		var nav := ShipStats.officer_skill(s, "navigator")
		if Dice.check(rng, "Spot a cove", [["Navigation", Dice.mod(nav)], ["Well hidden", -int(cove(id).shelter)]], int(cfg().discover_dc)).success:
			discovered.append(id)
			return "Your navigator spots a sheltered anchorage: %s. %s" % [cove(id).name, cove(id).description]
	return ""


## An event or a tavern tale reveals a cove you haven't found. Returns its id or "".
func reveal_random() -> String:
	var hidden: Array = Data.table("coves").keys().filter(func(id): return not id.begins_with("_") and not id in discovered)
	if hidden.is_empty():
		return ""
	var id: String = hidden[rng.randi() % hidden.size()]
	discovered.append(id)
	return id


func claim_problem(s: Dictionary, id: String) -> String:
	if bases.has(id):
		return "It's already yours."
	if bases.size() >= cfg().max:
		return "You can't hold more than %d bases." % cfg().max
	if s.gold < cfg().claim_cost:
		return "Setting up costs %d gold." % cfg().claim_cost
	if s.crew.size() - s.officers.size() < cfg().claim_garrison + 5:
		return "You need %d spare hands to leave as a garrison." % cfg().claim_garrison
	return ""


func claim(s: Dictionary, id: String) -> String:
	var why := claim_problem(s, id)
	if why != "":
		return why
	s.gold -= cfg().claim_cost
	bases[id] = _new_base(id, [], float(cfg().visibility_start), float(cfg().loyalty_start))
	send_garrison(s, id, int(cfg().claim_garrison))
	ShipStats.captain(s).history.append("Founded a base at %s, %s." % [cove(id).name, Clock.date_string()])
	return "%s is yours. %d hands stay behind to clear the ground." % [cove(id).name, cfg().claim_garrison]


func _new_base(id: String, buildings: Array, visibility: float, loyalty: float) -> Dictionary:
	return {"name": cove(id).name, "buildings": buildings, "building": {}, "garrison": 0, "manager": "", "storage": {"food": 0.0, "water": 0.0},
		"stolen": {}, "gold": 0.0, "visibility": visibility, "loyalty": loyalty, "recruits": 0.0,
		"prizes": [], "hostages": [], "raid": {}, "unpaid": 0.0, "leave_until": 0.0}


## A town taken and held: its wharves, warehouses and guns already standing. garrison: hands left ashore;
## extra: men who come with it (Nassau's council). from: who will come to take it back (its old masters).
func hold_town(s: Dictionary, id: String, garrison: int, extra := 0, from := "") -> String:
	var h: Dictionary = Data.rules.sieges.hold
	var b := _new_base(id, h.buildings[Ports.port(id).size].duplicate(), 100.0, float(h.loyalty))
	b.town = {"from": from if from != "" else Ports.port(id).faction, "since": Clock.day, "failed": 0}
	b.taxes = "fair"
	bases[id] = b
	Ports.state[id].laws = h.laws.duplicate(true)  # your laws now
	Politics.depose(s, id)
	b.raid = _expedition(id)
	b.garrison = extra
	send_garrison(s, id, garrison)
	return "%s is yours. %d men hold the walls; it pays its taxes to you now. %s will want it back." % [b.name, b.garrison,
		Career.fname(b.town.from) if b.town.from != "pirates" else "The Brethren"]


func _expedition(id: String) -> Dictionary:
	var b: Dictionary = bases[id]
	var d: Array = Data.rules.sieges.hold.expedition_days
	return {"day": Clock.day + rng.randf_range(d[0], d[1]), "warned": true, "captain": "", "kind": "expedition", "faction": b.town.from,
		"label": "a %s expedition to retake %s" % [Data.table("factions")[b.town.from].adjective, b.name]}


func is_town(id: String) -> bool:
	return bases.has(id) and bases[id].has("town")


## Each expedition beaten makes the next one stronger, and a big town draws a big one.
func expedition_strength(id: String) -> int:
	var e: Dictionary = Data.rules.sieges.hold.expedition
	return int(cfg().raiders.expedition.strength) + int(e.per_failure) * int(bases[id].town.get("failed", 0)) + int(e.size[Ports.port(id).size])


func expedition_men(id: String) -> int:
	var e: Dictionary = Data.rules.sieges.hold.expedition
	return int(cfg().raiders.expedition.men * (1.0 + e.men_per_failure * bases[id].town.get("failed", 0)) * (1.0 + e.size[Ports.port(id).size] * 0.5))


## The expedition was caught and beaten at sea: the next one will be a while coming, and stronger.
func expedition_beaten(id: String) -> String:
	if not is_town(id):
		return ""
	var b: Dictionary = bases[id]
	b.town.failed = int(b.town.get("failed", 0)) + 1
	b.loyalty = minf(100.0, b.loyalty + 10)
	b.raid = _expedition(id)
	return "The expedition to retake %s is broken at sea. %s will send another, stronger, in about %d days." % [b.name,
		Career.fname(b.town.from) if b.town.from != "pirates" else "The Brethren", int(b.raid.day - Clock.day)]


static func taxes(id: String) -> float:
	return Ports.port(id).population / 1000.0 * Data.rules.sieges.hold.tax_per_1000


## What the town pays you a day now: its size, what you ask, and how loyal it is.
func tax_income(id: String) -> float:
	var b: Dictionary = bases[id]
	return taxes(id) * Data.rules.sieges.hold.taxes[b.get("taxes", "fair")].mult * b.loyalty / 100.0


func set_taxes(id: String, level: String) -> String:
	bases[id].taxes = level
	return "Taxes at %s are %s now." % [bases[id].name, Data.rules.sieges.hold.taxes[level].name.to_lower()]


## Where a base's loyalty is heading, every part of it: [[label, amount]]. It drifts toward the sum.
func loyalty_parts(id: String) -> Array:
	var c := cfg()
	var b: Dictionary = bases[id]
	var man := People.person(b.manager) if b.manager != "" and People.chars.has(b.manager) else {}
	var parts := []
	if b.has("town"):
		var h: Dictionary = Data.rules.sieges.hold
		var t := PortLife.situation(id)
		parts.append(["A conquered town", float(h.loyalty)])
		parts.append(["%s taxes" % h.taxes[b.get("taxes", "fair")].name, float(h.taxes[b.get("taxes", "fair")].loyalty)])
		parts.append(["Order in the streets %d" % t.order, (t.order - 50.0) * h.order])
		if t.hunger > 0:
			parts.append(["Hunger %d" % t.hunger, t.hunger * h.hunger])
	else:
		parts.append(["Your men", float(c.loyalty_start)])
	if man.is_empty():
		parts.append(["Nobody in charge", -20.0])
	else:
		parts.append(["%s's authority" % man.name, (People.value(man, "authority") - 8) * 2.0])
	if has(b, "tavern"):
		parts.append(["The tavern", 10.0])
	return parts


# ---- the people at a base ---------------------------------------------------------------

## Hands ashore: they come off the ship as a garrison (generic men, paid and fed from the base).
func send_garrison(s: Dictionary, id: String, n: int) -> String:
	var b: Dictionary = bases[id]
	var spare: Array = s.crew.filter(func(c): return not c in s.officers.values())
	spare.sort_custom(func(x, y): return Ports._usefulness(x) < Ports._usefulness(y))
	n = mini(n, spare.size())
	for i in n:
		Crew.remove_hand(s, spare[i])
	b.garrison += n
	return "%d hands join the garrison at %s." % [n, b.name]


func take_garrison(s: Dictionary, id: String, n: int, crew_max: int) -> String:
	var b: Dictionary = bases[id]
	n = mini(n, mini(b.garrison, crew_max - ShipStats.headcount(s)))
	for i in n:
		s.crew.append(People.add(People.generate({"mix": Data.rules.people.recruit_mix.pirates})))
	b.garrison -= n
	return "%d of the garrison come back aboard." % n


## An officer or hand who runs the base: trade raises income, authority keeps the garrison loyal,
## intimidation helps hold it, carpentry speeds building.
func appoint(s: Dictionary, id: String, who: String) -> String:
	var b: Dictionary = bases[id]
	if b.manager != "":
		s.crew.append(b.manager)
	if who != "":
		for post in s.officers.keys():
			if s.officers[post] == who:
				s.officers.erase(post)
		s.crew.erase(who)
		People.person(who).history.append("Put in charge of %s, %s." % [b.name, Clock.date_string()])
	b.manager = who
	return "%s runs %s now." % [People.person(who).name, b.name] if who != "" else "Nobody runs %s now." % b.name


func recruit(s: Dictionary, id: String, n: int, crew_max: int) -> String:
	var b: Dictionary = bases[id]
	n = mini(n, mini(int(b.recruits), crew_max - ShipStats.headcount(s)))
	var cost: int = n * Data.rules.tavern.hire_cost
	if n <= 0 or s.gold < cost:
		return "Nobody to hire, or not the gold to pay them."
	s.gold -= cost
	for i in n:
		s.crew.append(People.add(People.generate({"mix": Data.rules.people.recruit_mix.pirates})))
	b.recruits -= n
	return "%d hands sign on at the tavern for %d gold." % [n, cost]


# ---- building -------------------------------------------------------------------------

func build_problem(s: Dictionary, id: String, what: String) -> String:
	var b: Dictionary = bases[id]
	var bd := building(what)
	if has(b, what):
		return "Already built."
	if not b.building.is_empty():
		return "Already building the %s." % building(b.building.id).name.to_lower()
	for need in bd.needs:
		if not has(b, need):
			return "Needs a %s first." % building(need).name.to_lower()
	if bd.get("needs_soil", false) and not cove(id).soil:
		return "Nothing grows in this ground."
	if s.gold < bd.cost:
		return "Costs %d gold." % bd.cost
	return ""


func build(s: Dictionary, id: String, what: String) -> String:
	var why := build_problem(s, id, what)
	if why != "":
		return why
	s.gold -= building(what).cost
	bases[id].building = {"id": what, "left": float(building(what).days)}
	return "Work begins on the %s: %d days." % [building(what).name.to_lower(), building(what).days]


# ---- storage, money and trade -------------------------------------------------------------

func capacity(b: Dictionary) -> float:
	return float(building("warehouse").capacity) if has(b, "warehouse") else float(cfg().storage_without_warehouse)


func stored(b: Dictionary) -> float:
	return Market.cargo_used(b.storage)


## Moves goods between the ship and the base. qty > 0: ashore; < 0: aboard. Stolen marks travel with them.
func move_goods(s: Dictionary, id: String, good: String, qty: float, ship_capacity: float) -> String:
	var b: Dictionary = bases[id]
	var w := Market.weight(good)
	var ashore := qty > 0
	if ashore:
		qty = minf(qty, minf(s.cargo.get(good, 0.0), floorf((capacity(b) - stored(b)) / w)))
		if qty <= 0:
			return "No room ashore, or nothing to land."
		var stolen := minf(qty, s.stolen.get(good, 0.0))
		Ports.remove_cargo(s, good, qty, stolen)
		b.storage[good] = b.storage.get(good, 0.0) + qty
		if stolen > 0:
			b.stolen[good] = b.stolen.get(good, 0.0) + stolen
	else:
		qty = minf(-qty, minf(b.storage.get(good, 0.0), floorf((ship_capacity - Market.cargo_used(s.cargo)) / w)))
		if qty <= 0:
			return "No room aboard, or nothing stored."
		var stolen := minf(qty, b.stolen.get(good, 0.0))
		b.storage[good] -= qty
		b.stolen[good] = b.stolen.get(good, 0.0) - stolen
		s.cargo[good] = s.cargo.get(good, 0.0) + qty
		if stolen > 0:
			s.stolen[good] = s.stolen.get(good, 0.0) + stolen
	return "Moved %d %s %s." % [qty, Data.table("goods")[good].name.to_lower(), "ashore" if ashore else "aboard"]


static func nearest_port(id: String) -> String:
	var best := ""
	for p in Ports.state:
		if Ports.port(p).faction == "pirates":
			continue
		var d := Geo.latlon_to_px(Ports.port(p).lat, Ports.port(p).lon).distance_to(cove_pos(id))
		if best == "" or d < Geo.latlon_to_px(Ports.port(best).lat, Ports.port(best).lon).distance_to(cove_pos(id)):
			best = p
	return best


## What the smugglers pay for a unit: the nearest market's price, in full, with the manager's haggling.
func smuggler_price(id: String, good: String) -> float:
	var b: Dictionary = bases[id]
	var trade: int = People.value(People.person(b.manager), "trade") if b.manager != "" else 0
	return Ports.price(nearest_port(id), good, false) * (1.0 + trade * cfg().manager_trade_per_point)


func sell(s: Dictionary, id: String, good: String, qty: float) -> String:
	var b: Dictionary = bases[id]
	if not has(b, "smugglers_market"):
		return "There's no market here."
	qty = minf(qty, b.storage.get(good, 0.0))
	if qty <= 0:
		return "Nothing to sell."
	var income := floorf(smuggler_price(id, good) * qty)
	var stolen := minf(qty, b.stolen.get(good, 0.0))
	b.storage[good] -= qty
	b.stolen[good] = b.stolen.get(good, 0.0) - stolen
	s.gold += income
	b.visibility = minf(100.0, b.visibility + cfg().visibility_sale)
	var text := "Sold %d %s for %d." % [qty, Data.table("goods")[good].name.to_lower(), income]
	if stolen > 0:
		text += " " + Crew.plunder(s, income * stolen / qty)
	return text.strip_edges()


# ---- the daily round --------------------------------------------------------------------

## Building, production, wages and food, loyalty, visibility, ransoms and raids. Returns
## {messages, battle: base id if a raid is falling on a base where you are, else ""}.
## Why this ship can't be laid down at this base, or "".
func keel_problem(s: Dictionary, id: String, type: String) -> String:
	var b: Dictionary = bases[id]
	var sb: Dictionary = cfg().shipbuilding
	if not has(b, "shipyard"):
		return "Build a shipyard first."
	if b.has("keel"):
		return "The %s is already on the slip." % b.keel.name
	var missing: Array = sb.types[type].filter(func(x): return not has(b, x))
	if not missing.is_empty():
		return "A %s needs: %s." % [Data.table("ships")[type].name.to_lower(), ", ".join(missing.map(func(x): return building(x).name.to_lower()))]
	if keel_cost(type) > s.gold:
		return "You can't afford her."
	return ""


func keel_cost(type: String) -> int:
	return int(Data.table("ships")[type].price * cfg().shipbuilding.cost_mult)


func lay_keel(s: Dictionary, id: String, type: String, ship_name: String) -> String:
	var why := keel_problem(s, id, type)
	if why != "":
		return why
	s.gold -= keel_cost(type)
	bases[id].keel = {"type": type, "name": ship_name, "left": Data.table("ships")[type].hull * cfg().shipbuilding.days_per_hull}
	return "The keel of the %s is laid at %s." % [ship_name, bases[id].name]


func daily(s: Dictionary, here: String) -> Dictionary:
	var c := cfg()
	var msgs := []
	var battle := ""
	for id in bases.keys():
		var b: Dictionary = bases[id]
		var man := People.person(b.manager) if b.manager != "" and People.chars.has(b.manager) else {}
		# construction
		if not b.building.is_empty():
			b.building.left -= 1.0 + (People.value(man, "carpentry") * c.manager_build_per_point if not man.is_empty() else 0.0)
			if b.building.left <= 0:
				b.buildings.append(b.building.id)
				msgs.append("The %s at %s is finished." % [building(b.building.id).name.to_lower(), b.name])
				b.building = {}
		# a hull on the slip
		if b.has("keel"):
			b.keel.left -= 1.0 + (People.value(man, "carpentry") * c.manager_build_per_point if not man.is_empty() else 0.0)
			if b.keel.left <= 0:
				var st := ShipStats.effective(b.keel.type, [])
				b.prizes.append(Fleet.ensure({"type": b.keel.type, "name": b.keel.name, "faction": "", "hull": float(st.hull), "sails": float(st.sails)}))
				msgs.append("The %s is launched at %s. She's waiting at the dock for a crew." % [b.keel.name, b.name])
				b.erase("keel")
		# production
		if b.has("town"):
			b.gold += tax_income(id)
		for bid in b.buildings:
			var bd := building(bid)
			var work := worked(b, bid)
			if work > 0.0 and bd.has("produces"):
				for g in bd.produces:
					if stored(b) + Market.weight(g) <= capacity(b):
						b.storage[g] = b.storage.get(g, 0.0) + bd.produces[g] * work * (1.0 + (People.value(man, "trade") * c.manager_trade_per_point if not man.is_empty() else 0.0))
			if work > 0.0 and bd.has("converts"):
				var from := _stock_of(b, bd.converts.from, bd.converts.per_day * work)
				if from != "":
					b.storage[from] -= bd.converts.per_day * work
					b.storage[bd.converts.to] = b.storage.get(bd.converts.to, 0.0) + bd.converts.per_day * work
			if bd.has("recruits_per_day"):
				b.recruits = minf(c.recruits_cap, b.recruits + bd.recruits_per_day)
			b.visibility += bd.visibility
		# wages and food
		var cost: float = b.garrison * c.garrison_wage
		for bid in b.buildings:
			cost += building(bid).upkeep
		var paid := minf(cost, b.gold)
		b.gold -= paid
		var unpaid := paid < cost
		var eat: float = b.garrison * c.food_per_man if not b.has("town") else 0.0  # a town's garrison buys in the market
		var hungry: bool = b.storage.get("food", 0.0) < eat or (not cove(id).water and b.storage.get("water", 0.0) < eat)
		b.storage.food = maxf(0.0, b.storage.get("food", 0.0) - eat)
		if not cove(id).water:
			b.storage.water = maxf(0.0, b.storage.get("water", 0.0) - eat)
		# loyalty and its consequences
		var target: float = loyalty_parts(id).reduce(func(a, p): return a + p[1], 0.0)
		b.loyalty = lerpf(b.loyalty, target, c.loyalty_drift)
		if unpaid:
			b.loyalty += c.loyalty_unpaid
		if hungry:
			b.loyalty += c.loyalty_hungry
		b.loyalty = clampf(b.loyalty, 0.0, 100.0)
		if b.loyalty < c.desert_below and b.garrison > 0 and rng.randf() < 0.3:
			b.garrison -= 1
			if rng.randf() < 0.2:
				msgs.append("Men are deserting the garrison at %s%s." % [b.name, " (unpaid)" if unpaid else (" (hungry)" if hungry else "")])
		if b.loyalty < c.rebel_below and rng.randf() < c.rebel_chance:
			msgs.append(rebellion(s, id))
			if not bases.has(id):
				continue
		# visibility: activity gives it away; quiet and shelter hide it
		b.visibility += b.garrison * c.visibility_per_man - c.visibility_decay * (1.0 + cove(id).shelter * 0.25)
		b.visibility = clampf(b.visibility, 0.0, 100.0)
		# ransoms through the stockade
		for h in b.hostages.duplicate():
			if Clock.day >= h.day:
				var paid_r := int(h.ransom * building("stockade").ransom_mult)
				b.gold += paid_r
				b.hostages.erase(h)
				msgs.append("The ransom for %s arrives at %s: %d gold, into the treasury." % [People.person(h.id).name, b.name, paid_r])
				People.remove(h.id)
		# raids
		if b.raid.is_empty() and b.has("town"):  # a held town is no secret: its old masters keep coming
			b.raid = _expedition(id)
		elif b.raid.is_empty():
			var chance: float = b.visibility * c.raid_per_visibility + Bonds.rivals(s, 2).size() * c.raid_rival_bonus + (c.raid_wanted_bonus if Career.wanted(s) else 0.0)
			if rng.randf() < chance:
				b.raid = _raider(s, id)
				if b.raid.warned:
					msgs.append("Lookouts at %s report sails: %s is coming, in about %d days." % [b.name, b.raid.label, int(b.raid.day - Clock.day)])
		if not b.raid.is_empty() and Clock.day >= b.raid.day:
			if here == id:
				battle = id
			else:
				msgs.append(resolve_raid(s, id, 0))
	return {"messages": msgs, "battle": battle}


## How much of a building's work gets done (0 to 1): it needs the base manned (5 men), and fields and stills
## share the hands beyond that: with half the hands they need, they make half as much.
func worked(b: Dictionary, bid: String) -> float:
	if b.garrison < 5:
		return 0.0
	if building(bid).get("hands", 0) <= 0:
		return 1.0
	return clampf((b.garrison - 5) / float(maxi(1, hands_needed(b))), 0.0, 1.0)


func hands_needed(b: Dictionary) -> int:
	return b.buildings.reduce(func(a, x): return a + int(building(x).get("hands", 0)), 0)


## The first of a building's inputs there's enough of in store, or "".
func _stock_of(b: Dictionary, from: Variant, qty: float) -> String:
	for g in (from if from is Array else [from]):
		if b.storage.get(g, 0.0) >= qty:
			return g
	return ""


## A base is gone. A town goes back under its old laws and gets new officials from its old masters.
func lose(id: String) -> void:
	var town := is_town(id)
	bases.erase(id)
	if town:
		Ports.state[id].laws = Ports.port(id).laws.duplicate(true)
		Politics.officials.erase(id)
		Politics.apply_laws(id, true)
	if id == "nassau":
		Politics.council_leader = Politics.council_members()[0]


## Loyalty has collapsed and the base rises: the garrison (and the manager's nerve) against the angry.
## A town's people throw open the gates; a cove's garrison takes the base and its stores for themselves.
func rebellion(s: Dictionary, id: String) -> String:
	var b: Dictionary = bases[id]
	var town: bool = b.has("town")
	var rebels: float = Ports.port(id).population / float(cfg().town_rebels_per) * (1.0 - PortLife.situation(id).order / 100.0) if town else b.garrison * 0.5
	var loyal: float = b.garrison if town else b.garrison * 0.5
	var ours := [["%d loyal men against %d" % [loyal, rebels], int(clampf(round(log(maxf(1.0, loyal) / maxf(1.0, rebels)) / log(2.0) * 3.0), -8, 6))]]
	var man := People.person(b.manager) if b.manager != "" and People.chars.has(b.manager) else {}
	if not man.is_empty():
		ours.append(["%s's grip" % man.name, Dice.mod(People.value(man, "intimidation"))])
	if has(b, "fort"):
		ours.append(["The fort", 2])
	var check := Dice.contest(rng, "Put down the rising at %s" % b.name, ours, [["Their anger", int((cfg().rebel_below - b.loyalty) / 3.0) + 2]])
	if check.success:
		b.garrison = maxi(0, b.garrison - rng.randi_range(1, 5))
		b.loyalty = minf(100.0, b.loyalty + 20)
		s.reputation.fear += 1
		if town:
			PortLife.nudge(id, "order", 15)
		return "%s rose against you, and was put down%s. Fear holds it, for now." % [b.name, " by %s" % man.name if not man.is_empty() else ""]
	var text := ""
	if town:
		text = "%s has risen against you. The townsfolk open the gates, your garrison runs for the boats, and %s flag goes back up over the fort." % [
			b.name, ("the " + Data.table("factions")[b.town.from].adjective) if b.town.from != "pirates" else "the black"]
		if not man.is_empty():
			s.crew.append(b.manager)
	else:
		text = "The garrison at %s has mutinied and taken the base and everything in it for themselves." % b.name
		if not man.is_empty():  # whoever ran it sails off as a rival
			s.crew.append(b.manager)
			text += " " + Bonds.former_officer(s, b.manager, -1)
	ShipStats.captain(s).history.append("Lost %s to a rising, %s." % [b.name, Clock.date_string()])
	lose(id)
	news.emit(text)
	return text


func _raider(s: Dictionary, id: String) -> Dictionary:
	var b: Dictionary = bases[id]
	var warn: float = building("watchtower").warning_days if has(b, "watchtower") else 0.0
	var rivals: Array = Bonds.rivals(s, 2).filter(func(k): return not k.begins_with("f:") and People.person(k).get("role", "") == "captain")
	var raid := {"day": Clock.day + warn, "warned": warn > 0.0, "captain": ""}
	if not rivals.is_empty() and rng.randf() < 0.5:
		var r: String = rivals[rng.randi() % rivals.size()]
		raid.merge({"kind": "pirate" if People.person(r).faction == "pirates" else "hunter", "faction": People.person(r).faction, "captain": r,
			"label": "%s, your rival" % People.person(r).name})
	elif Career.wanted(s) or b.visibility > 40:
		var f: String = Ports.port(nearest_port(id)).faction
		var kind := "hunter" if Career.wanted(s) else "navy"
		raid.merge({"kind": kind, "faction": f, "label": "a %s %s" % [Data.table("factions")[f].adjective, "pirate hunter" if kind == "hunter" else "squadron"]})
	else:
		raid.merge({"kind": "pirate", "faction": "pirates", "label": "a pirate crew after your stores"})
	return raid


## The defence, every part of it: [[label, modifier]].
func defence_parts(s: Dictionary, id: String) -> Array:
	var b: Dictionary = bases[id]
	var r: Dictionary = b.raid if not b.raid.is_empty() else {"kind": "pirate", "warned": false}
	var men: int = expedition_men(id) if r.kind == "expedition" and b.has("town") else cfg().raiders[r.kind].men
	var parts := [["Garrison of %d" % b.garrison, int(clampf(round(log(maxf(1.0, b.garrison) / men) / log(2.0) * 3.0), -8, 6))]]
	for bid in ["battery", "fort", "watchtower"]:
		if has(b, bid):
			parts.append([building(bid).name, int(building(bid).defence)])
	if b.has("town"):
		var walls: int = Data.rules.sieges.size[Ports.port(id).size].walls
		if walls > 0:
			parts.append(["Town walls", walls])
	else:
		parts.append(["Hidden and hard to reach", int(cove(id).shelter)])
	if b.manager != "" and People.chars.has(b.manager):
		parts.append(["%s in command" % People.person(b.manager).name, Dice.mod(People.value(People.person(b.manager), "intimidation"))])
	if r.warned:
		parts.append(["Forewarned", 2])
	if b.loyalty < 30:
		parts.append(["A garrison with no heart for it", -3])
	if not Bonds.allies(s, 3).is_empty():
		parts.append(["Allies send help", 2])
	return parts


## A raid falls on the base. bonus: from your battle in its defence (+ won, - lost).
func resolve_raid(s: Dictionary, id: String, bonus: int) -> String:
	var b: Dictionary = bases[id]
	var r: Dictionary = b.raid
	b.raid = {}
	var ours := defence_parts(s, id)
	if bonus != 0:
		ours.append(["Your ship's fight", bonus])
	var theirs: int = expedition_strength(id) if r.kind == "expedition" and b.has("town") else int(cfg().raiders[r.kind].strength)
	var check := Dice.contest(rng, "Defend %s" % b.name, ours, [["Raiders", theirs]])
	if check.success:
		s.reputation.fear += 1
		b.loyalty = minf(100.0, b.loyalty + 10)
		b.garrison = maxi(0, b.garrison - rng.randi_range(0, 3))
		if r.kind == "expedition" and b.has("town"):
			b.town.failed = int(b.town.get("failed", 0)) + 1
			return "The expedition against %s is beaten off. They'll be back, and stronger." % b.name
		return "The raid on %s is beaten off: %s goes away empty-handed." % [b.name, r.label]
	if b.has("town") or -check.margin >= cfg().lost_margin or b.garrison <= 3:
		var text := "%s has fallen to %s. The stores are lost, the buildings burned, the garrison scattered." % [b.name, r.label]
		if b.has("town"):
			text = "%s has fallen to %s. Your garrison is marched off in chains, and the old flag flies over the fort again." % [b.name, r.label]
		if b.manager != "" and People.chars.has(b.manager):
			People.person(b.manager).history.append("Lost %s to raiders, %s." % [b.name, Clock.date_string()])
			s.crew.append(b.manager)  # they make it back to the ship somehow
		lose(id)
		news.emit(text)
		return text
	var lost: Array = b.buildings.filter(func(x): return x != "dock")
	var burned := ""
	if not lost.is_empty():
		burned = lost[rng.randi() % lost.size()]
		b.buildings.erase(burned)
	for g in b.storage.keys():
		b.storage[g] *= 0.6
	b.garrison = int(b.garrison * 0.6)
	b.loyalty = maxf(0.0, b.loyalty - 15)
	return "Raiders break into %s: they carry off much of the stores%s, and the garrison is badly hurt." % [b.name, (" and burn the %s" % building(burned).name.to_lower()) if burned != "" else ""]


# ---- benefits of a base --------------------------------------------------------------------

## A shore leave at a base with a tavern: once per visit.
func shore_leave(s: Dictionary, id: String) -> String:
	var b: Dictionary = bases[id]
	if not has(b, "tavern") or Clock.day < b.leave_until:
		return ""
	b.leave_until = Clock.day + cfg().shore_leave_days
	Crew.add_mod(s, "shore_leave", "Shore leave at %s" % b.name, building("tavern").morale, cfg().shore_leave_days)
	return "The crew go ashore at %s and drink the tavern dry." % b.name


func leave_hostage(s: Dictionary, id: String, index: int) -> String:
	var b: Dictionary = bases[id]
	if not has(b, "stockade"):
		return "You need a stockade to hold prisoners."
	var h: Dictionary = s.hostages[index]
	s.hostages.remove_at(index)
	h.day = Clock.day + building("stockade").ransom_days
	b.hostages.append(h)
	return "%s is locked in the stockade. A go-between will bring the ransom." % People.person(h.id).name


func visit(id: String) -> void:
	if bases.has(id):
		bases[id].visibility = minf(100.0, bases[id].visibility + cfg().visibility_visit)


## Ships the watchtowers can see.
func watch_points() -> Array:
	var out := []
	for id in bases:
		if has(bases[id], "watchtower"):
			out.append(cove_pos(id))
	return out


func save_state() -> Dictionary:
	return {"discovered": discovered, "bases": bases, "rng": str(rng.state)}


func load_state(d: Dictionary) -> void:
	discovered = d.discovered
	bases = d.bases
	rng.state = int(d.rng)
