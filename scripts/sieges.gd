class_name Sieges
## Taking a town. Lay siege, then each day choose: scout the walls, silence the fort, fight off the guard ship,
## starve them, wait for your allies, buy the gate, arm the townsfolk, raid by night, or storm it. Time is on your
## side (the town goes hungry) and against you (a relief squadron is coming). Then sack it, ransom it back, or
## hold it as one of your bases (Bases.hold_town) until its old masters come to take it back.
## A siege is a plain dict, g = {port, day, fort (0-100: how much of the fort still fights), garrison, supplies
## (days of food behind the walls), starving, scouted, weak (the side that's weak), guard (a warship under the fort),
## alarm, bribed, uprising, allies: [ids], relief (the day a relief squadron arrives)}. Tuning: rules.json "sieges".
## A siege you lift is kept in s.sieges[port] for a while: come back and the fort's damage is still there, less what
## they've repaired since. Your consorts' crews land with you, and share the losses.


static func cfg() -> Dictionary:
	return Data.rules.sieges


## What the town has: {fort, garrison, walls, supplies}. A garrison town is stronger; a pirate haven weaker.
static func defences(id: String) -> Dictionary:
	var p := Ports.port(id)
	var d: Dictionary = cfg().size[p.size]
	var fort: int = d.fort
	var men: float = d.garrison
	if "garrison" in p.tags:
		fort += int(cfg().garrison_tag.fort)
		men *= cfg().garrison_tag.garrison_mult
	if "pirate_haven" in p.tags:
		men *= cfg().haven_mult
	return {"fort": fort, "garrison": int(men), "walls": int(d.walls), "supplies": float(d.supplies)}


static func problem(s: Dictionary, id: String) -> String:
	if Bases.bases.has(id):
		return "It's yours."
	if "capital" in Ports.port(id).tags and 1 + s.get("prizes", []).filter(func(p): return Fleet.is_consort(p)).size() < cfg().capital_min_ships:
		return "A capital: it would take a squadron of %d ships to try it." % cfg().capital_min_ships
	if Crew.able(s) < cfg().min_men:
		return "You need at least %d fit men to land." % cfg().min_men
	return ""


## Laying siege is an act of war: it counts as attacking the town's nation. Returns {g, messages}.
static func begin(s: Dictionary, id: String, rng: RandomNumberGenerator) -> Dictionary:
	var p := Ports.port(id)
	var d := defences(id)
	var g := {"port": id, "day": Clock.day, "fort": 100.0, "garrison": int(d.garrison * rng.randf_range(0.85, 1.15)),
		"supplies": d.supplies * rng.randf_range(0.7, 1.3), "starving": false, "scouted": false,
		"weak": rng.randi() % cfg().sides.size(), "guard": rng.randf() < float(cfg().guard_chance[p.size]),
		"alarm": 0, "bribed": false, "uprising": false, "allies": [],
		"relief": Clock.day + rng.randf_range(cfg().relief_days[0], cfg().relief_days[1])}
	var msgs := Career.on_attack(s, {"faction": p.faction, "kind": "pirate" if p.faction == "pirates" else "navy"})
	s.reputation.notoriety += int(cfg().notoriety)
	msgs.append("You lay siege to %s." % p.name)
	return {"g": g, "messages": msgs}


## Back to a siege you lifted: the fort has been patched, the garrison reinforced, the stores refilled.
## Returns {g, messages}, or {} if there's no siege to come back to (or it's too long ago).
static func resume(s: Dictionary, id: String, rng: RandomNumberGenerator) -> Dictionary:
	var g: Dictionary = s.get("sieges", {}).get(id, {})
	if g.is_empty() or Clock.day - g.left > cfg().memory_days:
		forget(s, id)
		return {}
	var d := defences(id)
	var days: float = Clock.day - g.left
	g.fort = minf(100.0, g.fort + days * cfg().fort_repair_per_day)
	g.garrison += int((d.garrison - g.garrison) * minf(1.0, days * cfg().garrison_regrow))
	g.supplies = minf(d.supplies, maxf(0.0, g.supplies) + days)
	g.starving = g.supplies <= 0.0
	g.uprising = false
	g.allies = []
	if not g.guard:
		g.guard = rng.randf() < float(cfg().guard_chance[Ports.port(id).size]) * minf(1.0, days / 30.0)
	if g.relief < Clock.day:
		g.relief = Clock.day + rng.randf_range(cfg().relief_days[0], cfg().relief_days[1])
	g.day = Clock.day
	var p := Ports.port(id)
	var msgs := Career.on_attack(s, {"faction": p.faction, "kind": "pirate" if p.faction == "pirates" else "navy"})
	msgs.append("You come back to %s. In %d days they've patched the fort (%d%% of its guns) and brought the garrison up to about %d." % [
		p.name, int(days), int(g.fort), int(round(g.garrison / 10.0) * 10)])
	return {"g": g, "messages": msgs}


## You sail away: the town remembers what you broke, and so do you.
static func remember(s: Dictionary, g: Dictionary) -> void:
	g.left = Clock.day
	if not s.has("sieges"):
		s.sieges = {}
	s.sieges[g.port] = g


static func forget(s: Dictionary, id: String) -> void:
	s.get("sieges", {}).erase(id)


## Men who can go ashore: the flagship's crew less ten to keep her, and each consort's less a few.
static func landing(s: Dictionary) -> int:
	var n := maxi(0, s.crew.size() - 10)
	for p in _landing_ships(s):
		n += maxi(0, p.crew.size() - int(cfg().ship_keepers))
	return n


static func _landing_ships(s: Dictionary) -> Array:
	return s.get("prizes", []).filter(func(p): return Fleet.is_consort(p) and p.fights)


## The dead of a landing, spread over the ships the men came from. Returns the notable dead.
static func casualties(s: Dictionary, men: int, dead: int, rng: RandomNumberGenerator) -> Array:
	var total := maxi(1, landing(s))
	var named := []
	var left := dead
	for p in _landing_ships(s):
		var share := mini(p.crew.size(), int(round(dead * maxi(0, p.crew.size() - int(cfg().ship_keepers)) / float(total))))
		for i in share:
			var id: String = p.crew.pop_at(rng.randi() % p.crew.size())
			if People.person(id).traits.has("popular"):
				named.append("%s of the %s" % [People.person(id).name, p.name])
			People.remove(id)
		left -= share
	return named + Encounters.kill_crew(s, maxi(0, left), rng)


## The fort's modifier now: its full strength, times how much of it still fights.
static func fort_mod(g: Dictionary) -> int:
	return int(round(defences(g.port).fort * g.fort / 100.0))


static func guns(s: Dictionary, stats: Dictionary) -> int:
	return int(stats.guns) - int(s.get("guns_lost", 0)) + Fleet.allies(s).reduce(func(a, x): return a + int(x.guns), 0)


static func _ally_part(g: Dictionary, per: int) -> Array:
	return [["%d allied captain%s" % [g.allies.size(), "" if g.allies.size() == 1 else "s"], g.allies.size() * per]] if not g.allies.is_empty() else []


# ---- the days of a siege ---------------------------------------------------------------

## Days go by under the walls: the town eats its stores and grows hungry. Stops early if relief arrives.
## Returns {messages, relief: true if the relief squadron is here}.
static func pass_days(g: Dictionary, days: int) -> Dictionary:
	var msgs := []
	for i in days:
		Clock.advance(1)
		g.supplies -= 1.0
		PortLife.nudge(g.port, "hunger", cfg().hunger_per_day)  # hungry towns riot: and a riot can be armed
		if g.supplies <= 0.0 and not g.starving:
			g.starving = true
			g.garrison = int(g.garrison * cfg().starving_garrison)
			msgs.append("%s is starving. Men are slipping over the walls at night; the garrison is down to about %d." % [Ports.port(g.port).name, g.garrison])
		if Clock.day >= g.relief:
			return {"messages": msgs, "relief": true}
	return {"messages": msgs, "relief": false}


## A night in the boats, sounding the walls. Success shows the weak side, their numbers and when relief is due.
static func scout_parts(s: Dictionary, g: Dictionary) -> Array:
	var parts := [["Navigator's eye", Dice.mod(ShipStats.officer_skill(s, "navigator"))]]
	if g.alarm > 0:
		parts.append(["The town is on alert", -2 * g.alarm])
	return parts


static func scout(s: Dictionary, g: Dictionary, rng: RandomNumberGenerator) -> String:
	var c := Dice.check(rng, "Scout the defences", scout_parts(s, g), int(cfg().scout_dc))
	if c.success:
		g.scouted = true
		return "Your boats come back before dawn. %s is weak; there are %d men behind the walls; relief is expected in about %d days." % [
			side_name(g.weak).capitalize(), g.garrison, maxi(0, int(g.relief - Clock.day))]
	g.alarm += 1
	return "A sentry spots your boats and the alarm bells ring. You learn little, and the town is on its guard."


static func side_name(i: int) -> String:
	return cfg().sides[i].name


## Your guns against the fort's. Each success knocks out part of the fort; every day under its guns costs hull.
static func bombard_parts(s: Dictionary, stats: Dictionary, g: Dictionary) -> Array:
	var n := guns(s, stats)
	return [["%d guns" % n, int(n / float(cfg().guns_per_point))], ["Master gunner", Dice.mod(ShipStats.officer_skill(s, "master_gunner"))]] + _ally_part(g, 1)


static func bombard(s: Dictionary, stats: Dictionary, g: Dictionary, rng: RandomNumberGenerator) -> String:
	var c := Dice.contest(rng, "Bombard the fort", bombard_parts(s, stats, g), [["The fort", fort_mod(g)]])
	var hull: float = rng.randf_range(cfg().bombard_hull[0], cfg().bombard_hull[1]) * g.fort / 100.0 * (0.5 if c.success else 1.0)
	s.hull = maxf(1.0, s.hull - hull)
	if c.success:
		var hit: float = rng.randf_range(cfg().bombard_fort[0], cfg().bombard_fort[1]) * (1.5 if c.crit else 1.0)
		g.fort = maxf(0.0, g.fort - hit)
		g.garrison = maxi(1, g.garrison - rng.randi_range(0, 4))
		return "Your broadsides batter the fort: %d%% of its guns still answer. Hull -%d." % [g.fort, hull] if g.fort > 0 else "The fort falls silent. Hull -%d." % hull
	return "The fort gives better than it gets. Hull -%d." % hull


## Allied captains answer the call, maybe. Returns a message.
static func call_allies(s: Dictionary, g: Dictionary, rng: RandomNumberGenerator) -> String:
	var came := []
	for k in Bonds.allies(s).filter(func(k): return not k.begins_with("f:") and not k in g.allies):
		if g.allies.size() < cfg().allies_max and rng.randf() < cfg().ally_join_chance:
			g.allies.append(k)
			came.append(Bonds.name_of(k))
	return "%s join%s the siege." % [" and ".join(came), "s" if came.size() == 1 else ""] if not came.is_empty() else "No sails on the horizon. Your allies haven't come."


static func can_wait_for_allies(s: Dictionary, g: Dictionary) -> bool:
	return g.allies.size() < cfg().allies_max and Bonds.allies(s).any(func(k): return not k.begins_with("f:") and not k in g.allies)


## Gold for the gate: the officer of the watch opens it at night, or takes your money to the governor.
static func bribe_cost(g: Dictionary) -> int:
	return int(g.garrison * cfg().bribe_per_man * (cfg().haven_bribe_mult if "pirate_haven" in Ports.port(g.port).tags else 1.0))


static func bribe_parts(s: Dictionary, g: Dictionary) -> Array:
	var t := PortLife.situation(g.port)
	var parts := [["Your charisma", Dice.mod(People.value(ShipStats.captain(s), "charisma"))], ["Order in the town %d" % t.order, -int(t.order / 20.0)]]
	if g.starving:
		parts.append(["They're starving", 3])
	if t.lawless:
		parts.append(["Everyone here has a price", 3])
	return parts


static func bribe(s: Dictionary, g: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	s.gold -= bribe_cost(g)
	g.bribed = true
	var c := Dice.check(rng, "Bribe the garrison", bribe_parts(s, g), int(cfg().bribe_dc))
	if c.success:
		return {"taken": true, "text": "At midnight a lantern swings twice above the gate, and it opens. %s is yours without a shot." % Ports.port(g.port).name}
	g.alarm += 2
	return {"taken": false, "text": "Your gold goes to the governor, and your go-between to the gallows. The town is on its guard."}


## A town on the edge of riot (or in revolt) can be raised against its garrison, with muskets from your hold.
static func uprising_possible(g: Dictionary) -> bool:
	return not g.uprising and (PortLife.is_on(g.port, "bread_riot") or PortLife.is_on(g.port, "revolt")
		or PortLife.situation(g.port).order < cfg().uprising_order)


static func raise_town(s: Dictionary, g: Dictionary) -> String:
	s.gold -= int(cfg().uprising_cost)
	g.uprising = true
	g.garrison = int(g.garrison * (1.0 - cfg().uprising_garrison))
	PortLife.nudge(g.port, "order", -20)
	return "Muskets go ashore by night. By morning the streets are barricaded, and the garrison has a war on two fronts."


## The landing: everything that decides it, [[label, modifier]]. side: index into sides, or -1 for a night raid.
static func assault_parts(s: Dictionary, g: Dictionary, men: int, side: int) -> Array:
	var night := side < 0
	var parts := [["%d men against %s%d" % [men, "" if g.scouted else "about ", g.garrison], int(clampf(round(log(maxf(1.0, men) / maxf(1.0, g.garrison)) / log(2.0) * 3.0), -8, 6))]]
	var blade := ShipStats.captain(s)
	for id in s.officers.values():
		if People.chars.has(id) and People.value(People.person(id), "swordplay") > People.value(blade, "swordplay"):
			blade = People.person(id)
	parts.append(["%s leads them" % blade.name, Dice.mod(People.value(blade, "swordplay"))])
	var morale: float = Crew.morale(s, {}).value
	parts.append(["Crew morale %d" % morale, int((morale - 50.0) / 10.0)])
	if night:
		parts.append(["Under cover of darkness", int(cfg().night_bonus)])
		if g.alarm > 0:
			parts.append(["They're waiting for you", -3 * g.alarm])
	else:
		var under := int(round(fort_mod(g) * float(cfg().sides[side].fort)))
		if under > 0:
			parts.append(["The fort's guns on %s" % side_name(side), -under])
		if side == g.weak:
			parts.append(["A weak point in the walls", int(cfg().weak_bonus)])
	if g.uprising:
		parts.append(["The town has risen", int(cfg().uprising_bonus)])
	if g.starving:
		parts.append(["A starving garrison", int(cfg().starving_bonus)])
	var band := Maroons.sworn_near(s, g.port)
	if band != "":
		parts.append(["%s come down from the hills" % band.capitalize(), int(Data.rules.maroons.siege_bonus)])
	return parts + _ally_part(g, int(cfg().ally_bonus))


static func defender_parts(g: Dictionary) -> Array:
	var walls: int = defences(g.port).walls
	return [["Walls", walls]] if walls > 0 else []


## Storm the town (or raid it by night: side -1). Returns {taken, text, check}.
static func assault(s: Dictionary, g: Dictionary, men: int, side: int, rng: RandomNumberGenerator) -> Dictionary:
	var c := Dice.contest(rng, "Storm %s" % Ports.port(g.port).name, assault_parts(s, g, men, side), defender_parts(g))
	var losses: Array = cfg().losses_won if c.success else (cfg().night_losses_lost if side < 0 else cfg().losses_lost)
	var dead := int(men * rng.randf_range(losses[0], losses[1]))
	var named := casualties(s, men, dead, rng)
	var lost := " %d of your men are dead%s." % [dead, (", among them " + ", ".join(named)) if not named.is_empty() else ""]
	if c.success:
		return {"taken": true, "check": c, "text": "Over the walls and into the square: %s has fallen.%s" % [Ports.port(g.port).name, lost]}
	g.garrison = maxi(1, g.garrison - int(g.garrison * rng.randf_range(cfg().garrison_losses[0], cfg().garrison_losses[1])))
	g.alarm += 1
	Crew.add_mod(s, "assault", "Thrown back from the walls", -8, 20)
	return {"taken": false, "check": c, "text": "The assault breaks on the walls and your men stream back to the boats.%s" % lost}


# ---- after the fall -------------------------------------------------------------------

## What a sack would bring: the size of the town, and how rich it is now.
static func sack_gold(id: String) -> int:
	return int(cfg().size[Ports.port(id).size].sack_gold * (0.5 + PortLife.situation(id).wealth / 100.0))


static func _taken(s: Dictionary, id: String, how: String) -> Array:
	forget(s, id)
	Ambitions.tally(s, "towns_taken")
	ShipStats.captain(s).history.append("%s %s, %s." % [how, Ports.port(id).name, Clock.date_string()])
	return Contracts.on_town_taken(s, id, {"Sacked": "sack", "Ransomed": "ransom"}.get(how, "hold"))


## Plunder taken under a commission is the Crown's business too.
static func _plunder(s: Dictionary, id: String, gold: int) -> Array:
	s.gold += gold
	var msgs := [Crew.plunder(s, gold)]
	if Career.judge_attack(s, Ports.port(id).faction).legal:
		msgs.append_array(Career.record_prize(s, gold))
	return msgs.filter(func(m): return m != "")


## Sack it: the biggest haul, and the world never forgets. The governor becomes your enemy for life.
static func sack(s: Dictionary, id: String) -> String:
	var k: Dictionary = cfg().sack
	var p := Ports.port(id)
	var gold := sack_gold(id)
	var jobs := _taken(s, id, "Sacked")
	var msgs := ["You sack %s: %d gold in coin and plate." % [p.name, gold]] + _plunder(s, id, gold) + jobs
	s.reputation.fear += int(k.fear)
	s.reputation.honour += int(k.honour)
	s.reputation.notoriety += int(k.notoriety)
	for f in Career.nations():
		s.relations[f] = s.relations.get(f, 0) - int(k.relation if f == p.faction else k.relation_all)
	s.relations.pirates = s.relations.get("pirates", 0) + int(k.pirates)
	Career.add_bounty(s, p.faction, Data.rules.career.bounty.sack)
	if s.career.marque != "":
		Factions.incident(s.career.marque, p.faction, Data.rules.diplomacy.incident.sack)
	Events.flags["sacked_" + id] = -1  # the town remembers, and so do the events
	Ports.start_market_event(id, "sacked")
	PortLife.nudge(id, "wealth", k.wealth)
	PortLife.nudge(id, "order", k.order)
	Ports.state[id].sailors *= k.sailors
	var gov := Politics.official(id, "governor")
	if gov != "":
		var r := Bonds.start_rivalry(s, gov, 2, "you sacked %s" % p.name)
		if r != "":
			msgs.append(r)
	msgs.append("Fear +%d, honour %d, notoriety +%d. Every nation will remember %s." % [k.fear, k.honour, k.notoriety, p.name])
	PortLife.remember(id, "sacked")
	return " ".join(msgs)


static func ransom_gold(id: String) -> int:
	return int(sack_gold(id) * cfg().ransom.share)


## Ransom it back: half the haul, the town left standing, and your word kept.
static func ransom(s: Dictionary, id: String) -> String:
	var k: Dictionary = cfg().ransom
	var p := Ports.port(id)
	var gold := ransom_gold(id)
	var jobs := _taken(s, id, "Ransomed")
	var msgs := ["The town council of %s scrapes together %d gold, and you sail away as promised." % [p.name, gold]] + _plunder(s, id, gold) + jobs
	s.reputation.fear += int(k.fear)
	s.reputation.honour += int(k.honour)
	s.relations[p.faction] = s.relations.get(p.faction, 0) - int(k.relation)
	PortLife.remember(id, "ransomed")
	return " ".join(msgs)


static func hold_problem(s: Dictionary, id: String) -> String:
	if Bases.bases.size() >= Data.rules.bases.max:
		return "You can't hold more than %d bases." % Data.rules.bases.max
	if s.crew.size() - s.officers.size() < garrison_needed(id) + 10:
		return "You need %d spare hands to leave as a garrison." % garrison_needed(id)
	return ""


static func garrison_needed(id: String) -> int:
	return int(cfg().hold.min_garrison[Ports.port(id).size])


## Hold it: a base with walls and wharves, paying taxes, and a target until its old masters take it back.
static func hold(s: Dictionary, id: String) -> String:
	var k: Dictionary = cfg().hold
	var p := Ports.port(id)
	var jobs := _taken(s, id, "Took and held")
	s.reputation.fear += int(k.fear)
	s.relations[p.faction] = s.relations.get(p.faction, 0) - int(k.relation)
	if s.career.marque != "" and Career.judge_attack(s, p.faction).legal:
		s.relations[s.career.marque] += int(Data.rules.career.lawful_raid_issuer_bonus)
	if id == "nassau":
		Politics.council_leader = "player"
	var held := Bases.hold_town(s, id, garrison_needed(id))  # (a town that liked you before takes to your rule more easily)
	PortLife.remember(id, "took")
	return " ".join([held] + jobs)
