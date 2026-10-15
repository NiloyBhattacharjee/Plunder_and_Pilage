extends Node
## Autoload "Contracts": jobs from the people who run the Caribbean. Governors hire privateers and pirate hunters;
## brokers in the havens and free ports hire pirates and smugglers. Templates live in data/contracts.json.
## Employers are ordinary characters (the People model). Their trust in you is their relation to your captain,
## so bigger jobs unlock as it grows, and a new captain starts from scratch.
## Three objectives cover every template: raid (take ships of a nation near a port), intercept (a named ship
## sailing the map), deliver (dispatches or contraband to a port). Some employers lie about pay; some jobs are traps.

signal changed

var employers := {}   # "port:role" -> character id
var offers := {}      # port id -> {day, list: [contract]}
var active: Array = []
var next_id := 1
var rng := RandomNumberGenerator.new()
var shipping: Node    # the world map's NPC shipping, which sails intercept targets


func _ready() -> void:
	rng.randomize()


func reset() -> void:
	employers = {}
	offers = {}
	active = []
	next_id = 1


static func cfg() -> Dictionary:
	return Data.rules.contracts


static func template(id: String) -> Dictionary:
	return Data.table("contracts")[id]


# ---- employers -----------------------------------------------------------------

## The governor or broker of a port, met for the first time when you ask. "" if the port has none.
func employer(port_id: String, role: String) -> String:
	var p := Ports.port(port_id)
	if (role == "governor" and p.faction == "pirates") or (role == "broker" and not p.has("broker")):
		return ""
	var key := port_id + ":" + role
	if not employers.has(key):
		var c := People.generate({"mix": Data.rules.people.recruit_mix[p.faction], "pool": "official"})
		c.name = p.governor if role == "governor" else p.broker
		c.age = maxi(c.age, 34)
		c.role = role
		c.port = port_id
		employers[key] = People.add(c)
	return employers[key]


static func employer_faction(e: Dictionary) -> String:
	return "pirates" if e.role == "broker" else Ports.port(e.port).faction


static func trust(emp_id: String, s: Dictionary) -> int:
	return People.person(emp_id).relations.get(s.captain, 0)


static func _add_trust(emp_id: String, s: Dictionary, n: int) -> void:
	var e := People.person(emp_id)
	e.relations[s.captain] = clampi(e.relations.get(s.captain, 0) + n, -100, 100)


static func lie_chance(t: Dictionary, e: Dictionary) -> float:
	if cfg().honest_trait in e.traits:
		return 0.0
	var p: float = t.lie_chance
	for tr in e.traits:
		p += cfg().lie_traits.get(tr, 0.0)
	return p


static func trap_chance(t: Dictionary, e: Dictionary) -> float:
	if cfg().honest_trait in e.traits:
		return 0.0
	var p: float = t.trap_chance
	for tr in e.traits:
		p += cfg().trap_traits.get(tr, 0.0)
	return p


# ---- offers --------------------------------------------------------------------

## What's on offer at this port, refreshed every couple of weeks.
func offers_at(port_id: String, s: Dictionary) -> Array:
	var o: Dictionary = offers.get(port_id, {})
	if o.is_empty() or Clock.day - o.day >= cfg().refresh_days:
		o = {"day": Clock.day, "list": []}
		for role in ["governor", "broker"]:
			var emp := employer(port_id, role)
			if emp == "":
				continue
			var ids: Array = Data.table("contracts").keys().filter(func(k): return not k.begins_with("_") and template(k).employer == role)
			ids.shuffle()
			var want := rng.randi_range(cfg().offers_per_employer[0], cfg().offers_per_employer[1])
			for id in ids:
				if o.list.filter(func(c): return c.employer == emp).size() >= want:
					break
				var c := make(id, emp, s)
				if not c.is_empty():
					o.list.append(c)
		offers[port_id] = o
	return o.list


## Builds a contract from a template for this employer, or {} if the world offers no target for it right now.
func make(tid: String, emp_id: String, s: Dictionary) -> Dictionary:
	var t := template(tid)
	var e := People.person(emp_id)
	var f := employer_faction(e)
	var tier := 0
	for i in t.tiers.size():
		if trust(emp_id, s) >= t.tiers[i].trust:
			tier = i
	var td: Dictionary = t.tiers[tier]
	var c := {"id": "k%d" % next_id, "template": tid, "objective": t.objective, "employer": emp_id, "employer_port": e.port,
		"faction": f, "tier": tier, "reward": int(td.reward), "days": int(t.days), "count": int(td.get("count", 1)), "progress": 0,
		"status": "offer", "target": "", "port": "", "dest": "", "good": "", "qty": int(td.get("qty", 0)), "npc": "", "ship": "", "captain": ""}
	match t.get("target", ""):
		"enemy":
			var en := Factions.enemies_of(f)
			if en.is_empty():
				return {}
			c.target = _pick(en)
		"nation":
			c.target = _pick(Career.nations().filter(func(n): return n != f))
		"pirates":
			c.target = "pirates"
	match t.objective:
		"raid":
			var ports := _ports_of(c.target)
			if ports.is_empty():
				return {}
			c.port = _pick(ports)
		"intercept":
			if not _plan_intercept(c, t, td):
				return {}
		"deliver":
			if not _plan_delivery(c, t, e):
				return {}
	c.lied = rng.randf() < lie_chance(t, e)
	c.trap = rng.randf() < trap_chance(t, e)
	c.name = _fill(t.name, c)
	c.description = _fill(t.description, c)
	next_id += 1
	return c


func _plan_intercept(c: Dictionary, t: Dictionary, td: Dictionary) -> bool:
	c.kind = t.kind
	c.capture = t.capture
	var enemy := Encounters.generate(c.target, rng, t.kind, _pick(td.ships))
	if t.kind == "merchant":
		var origins := _ports_of(c.target)
		if origins.is_empty():
			return false
		c.port = _pick(origins)
		var dests := Ports.state.keys().filter(func(id): return id != c.port and Ports.port(id).faction != "pirates" and not Factions.at_war(c.target, Ports.port(id).faction))
		if dests.is_empty():
			return false
		dests.sort_custom(func(a, b): return _pos(a).distance_to(_pos(c.port)) > _pos(b).distance_to(_pos(c.port)))
		c.dest = _pick(dests.slice(0, 3))  # a long voyage gives you a chance to find her
		c.good = _pick(t.cargo)
		var st := ShipStats.effective(enemy.type, enemy.upgrades)
		enemy.cargo = {c.good: maxi(1, int(st.cargo * 0.6 / Market.weight(c.good)))}
	else:
		var lairs := _ports_of(c.target) if t.kind == "hunter" else Ports.state.keys().filter(func(id): return Ports.port(id).faction != "pirates")
		c.port = _pick(lairs)
	c.enemy = enemy
	c.ship = enemy.name
	c.captain = enemy.captain.name
	return true


func _plan_delivery(c: Dictionary, t: Dictionary, e: Dictionary) -> bool:
	if t.cargo[0] == "dispatches":
		var dests := _ports_of(c.faction).filter(func(id): return id != e.port)
		if dests.is_empty():
			return false
		c.dest = _pick(dests)
		c.good = "dispatches"
		return true
	var dests := Ports.state.keys().filter(func(id): return not Ports.state[id].laws.contraband.is_empty())
	if dests.is_empty():
		return false
	c.dest = _pick(dests)
	c.good = _pick(Ports.state[c.dest].laws.contraband)
	c.deposit = int(Ports.price(e.port, c.good, true) * c.qty)  # you pay for the goods; they're refunded with the fee
	return true


func _fill(text: String, c: Dictionary) -> String:
	return text.format({
		"target": Data.table("factions")[c.target].adjective if c.target != "" else "",
		"ship": c.ship, "captain": c.captain, "count": c.count, "qty": c.qty,
		"port": Ports.port(c.port).name if c.port != "" else "", "dest": Ports.port(c.dest).name if c.dest != "" else "",
		"good": Data.table("goods")[c.good].name.to_lower() if Data.table("goods").has(c.good) else c.good,
	})


# ---- taking a job --------------------------------------------------------------

## Why you can't take this job, or "".
func problem(c: Dictionary, s: Dictionary, free_tons := 9999.0) -> String:
	var t := template(c.template)
	var f: String = c.faction
	if active.size() >= cfg().max_active:
		return "You can't juggle more than %d contracts." % cfg().max_active
	if People.person(c.employer).role == "governor" and s.career.pirate:
		return "No governor hires a known pirate. Seek a pardon first."
	if trust(c.employer, s) <= -cfg().fail_trust * 3:
		return "%s won't deal with you again." % People.person(c.employer).name
	if t.needs.get("marque", false) and s.career.marque != f:
		return "Only for holders of a %s letter of marque." % Data.table("factions")[f].adjective
	if s.relations.get(f, 0) < t.needs.get("standing", -100):
		return "Your standing with %s is too low (needs %+d)." % [Data.table("factions")[f].name, t.needs.standing]
	if t.get("target", "") == "enemy" and not Factions.at_war(f, c.target):
		return "%s is no longer at war with %s." % [Data.table("factions")[f].name, Data.table("factions")[c.target].name]
	if c.has("deposit"):
		if s.gold < c.deposit:
			return "The goods cost %d gold up front." % c.deposit
		if free_tons < c.qty * Market.weight(c.good):
			return "Needs %d tons of free hold." % ceili(c.qty * Market.weight(c.good))
	return ""


func accept(c: Dictionary, s: Dictionary, free_tons := 9999.0) -> String:
	var why := problem(c, s, free_tons)
	if why != "":
		return why
	for port_id in offers:
		offers[port_id].list.erase(c)
	c.status = "active"
	c.deadline = Clock.day + c.days
	c.pay_port = c.dest if c.objective == "deliver" else c.employer_port
	active.append(c)
	var text := "Contract taken: %s. %d days." % [c.name, c.days]
	match c.objective:
		"intercept":
			var enemy: Dictionary = c.enemy
			if c.trap:  # the promised ship is a warship flying the same name
				var bait := enemy
				enemy = Encounters.generate(c.target, rng, "hunter" if c.target != "pirates" else "pirate", "frigate")
				enemy.name = bait.name
				enemy.cargo = bait.cargo
			enemy.contract = c.id
			c.npc = shipping.spawn_target(c.kind, enemy, c.port, c.dest).id
			c.erase("enemy")
		"deliver":
			if c.has("deposit"):
				s.gold -= c.deposit
				s.cargo[c.good] = s.cargo.get(c.good, 0.0) + c.qty
				text += " You pay %d for the goods; it comes back with your fee." % c.deposit
			elif c.trap:  # someone sold word of your errand to the other side
				var foes := Factions.enemies_of(c.faction)
				shipping.spawn("hunter", _pick(foes) if not foes.is_empty() else "pirates")
	changed.emit()
	return text


# ---- the job unfolds -----------------------------------------------------------

## After every battle. pos: where it was fought. Returns messages.
func on_battle(s: Dictionary, enemy: Dictionary, outcome: String, pos: Vector2) -> Array:
	var msgs := []
	var won := outcome in ["enemy_struck", "enemy_sunk"]
	for c in active.duplicate():
		if c.status != "active":
			continue
		match c.objective:
			"intercept":
				if enemy.get("contract", "") != c.id:
					continue
				if outcome == "enemy_struck" or (outcome == "enemy_sunk" and not c.capture):
					msgs.append(_complete(c, s))
				elif outcome == "enemy_sunk":
					msgs.append(fail(c, s, "the %s went down with what you were sent for" % c.ship))
			"raid":
				if won and enemy.faction == c.target and pos.distance_to(_pos(c.port)) <= cfg().region_nm * Geo.px_per_nm():
					c.progress += 1
					msgs.append("%s: %d of %d." % [c.name, c.progress, c.count])
					if c.progress >= c.count:
						msgs.append(_complete(c, s))
			"deliver":
				if outcome == "player_struck" and c.good == "dispatches":
					msgs.append(fail(c, s, "the enemy found the dispatches when they boarded"))
	return msgs


## Deadlines, and intercept targets that reached port or vanished. Returns messages.
func daily(s: Dictionary) -> Array:
	var msgs := []
	for c in active.duplicate():
		if c.status != "active":
			continue
		if Clock.day > c.deadline:
			msgs.append(fail(c, s, "time ran out"))
		elif c.objective == "intercept" and shipping != null and shipping.find(c.npc).is_empty():
			msgs.append(fail(c, s, "the %s made port before you found her" % c.ship if c.kind == "merchant" else "the %s is gone" % c.ship))
	return msgs


func _complete(c: Dictionary, s: Dictionary) -> String:
	c.status = "done"
	var t := template(c.template)
	for k in t.success.get("relations", {}):
		var f: String = c.target if k == "target" else k
		s.relations[f] = s.relations.get(f, 0) + int(t.success.relations[k])
	changed.emit()
	return "Job done: %s. Collect your pay at %s." % [c.name, Ports.port(c.pay_port).name]


## Failing or walking away costs you with the employer and their nation.
func fail(c: Dictionary, s: Dictionary, why: String) -> String:
	active.erase(c)
	_add_trust(c.employer, s, -int(cfg().fail_trust))
	s.relations[c.faction] = s.relations.get(c.faction, 0) - int(cfg().fail_standing)
	if c.npc != "" and shipping != null:  # the target sails on as an ordinary ship
		var n: Dictionary = shipping.find(c.npc)
		if not n.is_empty():
			n.erase("contract")
			n.enemy.erase("contract")
	changed.emit()
	return "Contract failed: %s (%s). %s will remember (trust -%d, standing with %s -%d)." % [
		c.name, why, People.person(c.employer).name, cfg().fail_trust, Data.table("factions")[c.faction].name, cfg().fail_standing]


## Hand over the goods or the dispatches at the destination.
func deliver(c: Dictionary, s: Dictionary) -> String:
	if c.good == "dispatches":
		return _complete(c, s)
	if s.cargo.get(c.good, 0.0) < c.qty:
		return "You no longer carry the %d %s." % [c.qty, Data.table("goods")[c.good].name.to_lower()]
	var caught := rng.randf() < seizure_risk(c)
	Ports.remove_cargo(s, c.good, c.qty)
	if caught:
		var f: String = Ports.port(c.dest).faction
		s.relations[f] -= int(Data.rules.smuggling.seizure_relation)
		s.reputation.notoriety += 1
		return fail(c, s, "customs seized the %s on the quay%s" % [Data.table("goods")[c.good].name.to_lower(), "; someone had tipped them off" if c.trap else ""])
	return _complete(c, s)


func seizure_risk(c: Dictionary) -> float:
	return minf(1.0, Market.seizure_chance(Ports.state[c.dest].laws, c.good, c.qty) * (cfg().trap_seizure_mult if c.trap else 1.0))


## What the employer actually puts on the table.
static func offered_pay(c: Dictionary) -> int:
	return int(c.reward * (cfg().lie_pay if c.lied else 1.0)) + int(c.get("deposit", 0))


func demand_parts(s: Dictionary) -> Array:
	return [["Your intimidation", Dice.mod(People.value(ShipStats.captain(s), "intimidation"))],
		["Your fearsome name", clampi(int(s.reputation.fear / 10), 0, 3)]]


func demand_odds(c: Dictionary, s: Dictionary) -> float:
	return Dice.contest_chance(Dice.sum_parts(demand_parts(s)), Dice.mod(People.value(People.person(c.employer), "authority")))


## Take your pay. If they're short-changing you, `demand` presses for the full sum: an opposed roll
## against the employer's authority. Win and you're paid in full; lose and you take the short pay and their grudge.
func collect(c: Dictionary, s: Dictionary, demand := false) -> String:
	var e := People.person(c.employer)
	var t := template(c.template)
	var pay := offered_pay(c)
	var gain := int(t.success.trust)
	var text := ""
	if c.lied and demand:
		var roll := Dice.contest(rng, "Demand full payment", demand_parts(s),
			[["%s's authority" % e.name, Dice.mod(People.value(e, "authority"))]])
		if roll.success:
			pay = c.reward + int(c.get("deposit", 0))
			text = "You lean on %s until the full %d appears. " % [e.name, pay]
		else:
			gain = -int(cfg().demand_lose_trust)
			text = "%s doesn't budge, and won't forget you tried. " % e.name
	elif c.lied:
		text = "%s pleads hard times and pays short. " % e.name
	active.erase(c)
	s.gold += pay
	s.relations[c.faction] = s.relations.get(c.faction, 0) + int(t.success.standing)
	_add_trust(c.employer, s, gain)
	ShipStats.captain(s).history.append("%s for %s, %s." % [c.name, e.name, Clock.date_string()])
	changed.emit()
	return text + "Paid %d gold for %s. %s trusts you %s." % [pay, c.name, e.name, "more" if gain > 0 else "less"]


## Dispatches sold to their enemy: a fortune, and if it comes out, a nation that never forgives you.
func betray(c: Dictionary, s: Dictionary, port_id: String) -> String:
	var b: Dictionary = cfg().betray
	var pay := int(c.reward * b.mult)
	active.erase(c)
	s.gold += pay
	People.person(c.employer).relations[s.captain] = -100
	var text := "The governor of %s pays %d for a look at the seals. " % [Ports.port(port_id).name, pay]
	if rng.randf() < b.discovery:
		s.relations[c.faction] -= int(b.standing)
		text += "Word gets back: %s calls you a traitor (standing -%d)." % [Data.table("factions")[c.faction].name, b.standing]
	else:
		text += "For now, nobody knows."
	changed.emit()
	return text


func abandon(c: Dictionary, s: Dictionary) -> String:
	return fail(c, s, "you gave it up")


# ---- describing jobs -----------------------------------------------------------

## A rough measure of danger: the target's strength against yours.
func risk(c: Dictionary, s: Dictionary) -> String:
	match c.objective:
		"deliver":
			if c.good == "dispatches":
				return "Low"
			return "%d%% seizure at %s" % [int(seizure_risk(c) * 100 / (cfg().trap_seizure_mult if c.trap else 1.0)), Ports.port(c.dest).name]
		"raid":
			return "Moderate"
	var e: Dictionary = c.get("enemy", {})
	if e.is_empty():
		return "?"
	var st := ShipStats.effective(e.type, e.upgrades)
	var mine := ShipStats.effective(s.type, s.upgrades)
	var ratio: float = (st.guns * st.gun_weight * 0.5 + e.crew) / maxf(1.0, mine.guns * mine.gun_weight * 0.5 + ShipStats.headcount(s))
	for pair in cfg().risk_labels:
		if ratio <= pair[0]:
			return pair[1]
	return "Deadly"


## The full tooltip: pay, time, danger, legality and what it does to your name.
func details(c: Dictionary, s: Dictionary) -> String:
	var t := template(c.template)
	var e := People.person(c.employer)
	var fname: String = Data.table("factions")[c.faction].name
	var lines := PackedStringArray([c.description, ""])
	lines.append("Pay: %d gold%s.   Time: %d days.   Risk: %s." % [c.reward, " (plus your %d back for the goods)" % c.deposit if c.has("deposit") else "", c.days, risk(c, s)])
	lines.append("Success: standing with %s %+d, %s's trust %+d." % [fname, t.success.standing, e.name, t.success.trust])
	for k in t.success.get("relations", {}):
		var f: String = c.target if k == "target" else k
		lines.append("   and %s %+d." % [Data.table("factions")[f].name, t.success.relations[k]])
	lines.append("Failure: trust -%d, standing with %s -%d." % [cfg().fail_trust, fname, cfg().fail_standing])
	if c.objective in ["raid", "intercept"]:
		lines.append(Career.judge_attack(s, c.target).why)
	var known := People.known_traits(e).filter(func(tr): return cfg().lie_traits.has(tr) or cfg().trap_traits.has(tr) or tr == cfg().honest_trait)
	if not known.is_empty():
		lines.append("%s is known to be %s." % [e.name, ", ".join(known.map(func(tr): return Data.table("traits")[tr].name.to_lower()))])
	return "\n".join(lines)


## One line for the HUD.
func summary(c: Dictionary) -> String:
	if c.status == "done":
		return "%s: done, collect at %s" % [c.name, Ports.port(c.pay_port).name]
	var left := int(ceil(c.deadline - Clock.day))
	var prog := " %d/%d," % [c.progress, c.count] if c.objective == "raid" else ""
	return "%s:%s %d days left" % [c.name, prog, left]


## Where to look on the chart: {pos, radius} circles and {from, to} lines, in map pixels.
func hints() -> Array:
	var out := []
	for c in active:
		if c.status != "active":
			continue
		match c.objective:
			"raid":
				out.append({"pos": _pos(c.port), "radius": cfg().region_nm * Geo.px_per_nm(), "label": c.name})
			"intercept":
				if c.kind == "merchant":
					out.append({"from": _pos(c.port), "to": _pos(c.dest), "label": "The %s's course" % c.ship})
				else:
					out.append({"pos": _pos(c.port), "radius": cfg().lurk_nm * Geo.px_per_nm(), "label": "The %s was last seen here" % c.ship})
			"deliver":
				out.append({"pos": _pos(c.dest), "radius": 12.0, "label": c.name})
	return out


func find(id: String) -> Dictionary:
	for c in active:
		if c.id == id:
			return c
	return {}


# ---- helpers and saving --------------------------------------------------------

static func _ports_of(f: String) -> Array:
	return Ports.state.keys().filter(func(id): return Ports.port(id).faction == f)


static func _pos(port_id: String) -> Vector2:
	var p := Ports.port(port_id)
	return Geo.latlon_to_px(p.lat, p.lon)


func _pick(arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()]


func save_state() -> Dictionary:
	return {"employers": employers, "offers": offers, "active": active, "next_id": next_id, "rng": str(rng.state)}


func load_state(d: Dictionary) -> void:
	employers = d.employers
	offers = d.offers
	active = d.active
	next_id = d.next_id
	rng.state = int(d.rng)
	changed.emit()
