class_name PortLife
## Life in a port. What the town is like right now, read from the rest of the world: rich or poor (its size and
## what its trade fetches), fed or hungry (the price of food), orderly or restless (who holds power, hunger, war),
## pious, lawless, at war, the fleet in. And the happenings that grow out of it: feast days in prosperous towns,
## press gangs in ports at war, bread riots where the poor go hungry, the governor's ball in rich and orderly
## capitals, hangings where the law is strong, fever in poor towns in the wet season, captains drinking in the
## tavern. Happenings are data (data/port_life.json): when they can start (event conditions, usually on the town.*
## keys), how long they last, what they do to the port while they last, and what a visiting captain can do there
## (an event, gated by your own standing). Events read the same keys: "town.hunger >= 40", "life.festival".
## State: Ports.state[id].life = {happenings: [{id, until, captain?}], ended: {happening id: day}}.


static func table() -> Dictionary:
	return Data.table("port_life")


static func defs() -> Array:
	return table().keys().filter(func(k): return not k.begins_with("_"))


static func _life(id: String) -> Dictionary:
	var ps: Dictionary = Ports.state[id]
	if not ps.has("life"):
		ps.life = {"happenings": [], "ended": {}}
	return ps.life


# ---- the town ----------------------------------------------------------------------

## What the town is like now, each 0-100 unless a yes/no:
## wealth (its size and how its trade does), prosperity (what it sells fetches, what it needs costs),
## hunger (the price of food), order (soldiers and priests against the hungry poor, and war), piety (the church's
## say), war (its nation is at war), lawless (a pirates' haven or a town that tolerates them), fleet (in port).
static func situation(id: String) -> Dictionary:
	var p := Ports.port(id)
	var t: Dictionary = table()._town
	var food := Economy.mult(id, "food")
	var hunger := clampf((food - float(t.hunger_from)) * float(t.hunger_per_mult), 0.0, 100.0)  # food a little dear is normal here
	var makes := _avg_mult(id, Economy.produces(id))
	var needs := _avg_mult(id, Economy.wants(id))
	var fleet := Economy.fleet_text(id) != ""
	var prosperity := clampf(50.0 + (makes - 1.0) * 40.0 - (needs - 1.0) * 40.0 - hunger * 0.3 + (20.0 if fleet else 0.0), 0.0, 100.0)
	var wealth := clampf(float(t.size_wealth[p.size]) * 0.6 + prosperity * 0.4, 0.0, 100.0)
	var power := Politics.power(id)
	var lawless: bool = p.faction == "pirates" or "pirate_haven" in p.get("tags", []) or float(Ports.state[id].laws.get("pirates", 0.0)) > 0.4
	var war: bool = p.faction != "pirates" and not Factions.enemies_of(p.faction).is_empty()
	var order := clampf(50.0 + float(power.get("military", 0.0)) * 0.8 + float(power.get("church", 0.0)) * 0.3
		- float(power.get("poor", 0.0)) * 0.4 - hunger * 0.4 - (10.0 if war else 0.0) - (20.0 if lawless else 0.0), 0.0, 100.0)
	return {"wealth": wealth, "prosperity": prosperity, "hunger": hunger, "order": order, "piety": float(power.get("church", 0.0)),
		"war": war, "lawless": lawless, "fleet": fleet, "food": food, "makes": makes, "needs": needs}


static func _avg_mult(id: String, goods: Array) -> float:
	var g := goods.filter(func(x): return Data.table("goods").has(x) and Data.table("goods")[x].get("economy", true))
	if g.is_empty():
		return 1.0
	return g.reduce(func(a, x): return a + Economy.mult(id, x), 0.0) / g.size()


## The town in a few words: "rich, hungry and restless, at war".
static func describe(id: String) -> String:
	var t := situation(id)
	var words := PackedStringArray()
	words.append(_band(t.wealth, ["poor", "modest", "well-off", "rich"]))
	if t.hunger >= 40.0:
		words.append("hungry")
	elif t.prosperity >= 65.0:
		words.append("thriving")
	elif t.prosperity < 35.0:
		words.append("struggling")
	words.append(_band(t.order, ["lawless" if t.lawless else "on the edge of riot", "restless", "orderly", "under a firm hand"]))
	var out := ", ".join(words)
	if t.war:
		out += ", at war"
	return out


static func _band(v: float, names: Array) -> String:
	return names[clampi(int(v / 25.0), 0, names.size() - 1)]


## Why the town is as it is, for a tooltip.
static func explain(id: String) -> String:
	var t := situation(id)
	var power := Politics.power(id)
	return "Wealth %d: a %s town, and its trade %s.\nProsperity %d: what it sells fetches %.1fx, what it needs costs %.1fx%s.\nHunger %d: food costs %.1fx its usual price.\nOrder %d: soldiers %d%%, church %d%%, townsfolk %d%%%s%s." % [
		t.wealth, Ports.port(id).size, "booms" if t.prosperity >= 65.0 else ("struggles" if t.prosperity < 35.0 else "gets by"),
		t.prosperity, t.makes, t.needs, "; the fleet is in" if t.fleet else "",
		t.hunger, t.food,
		t.order, int(power.get("military", 0.0)), int(power.get("church", 0.0)), int(power.get("poor", 0.0)),
		"; the war" if t.war else "", "; it tolerates pirates" if t.lawless else ""]


# ---- happenings ----------------------------------------------------------------------

static func active(id: String) -> Array:
	return _life(id).happenings if Ports.state.has(id) else []


static func is_on(id: String, what: String) -> bool:
	return Ports.state.has(id) and active(id).any(func(h): return h.id == what)


static func happening(id: String, what: String) -> Dictionary:
	for h in active(id):
		if h.id == what:
			return h
	return {}


## The named captain drinking in this port's tavern, or "".
static func captain_here(id: String) -> String:
	return str(happening(id, "captains_drinking").get("captain", "")) if id != "" else ""


## The product of a modifier across what's going on: "hire_cost", "sailors" (the pool of hands), "rumours" (added).
static func mult(id: String, key: String) -> float:
	var out := 1.0
	for h in active(id):
		out *= float(table()[h.id].get("effects", {}).get(key, 1.0))
	return out


static func bonus(id: String, key: String) -> int:
	var out := 0
	for h in active(id):
		out += int(table()[h.id].get("effects", {}).get(key, 0))
	return out


## The happening's name in this port ("Fiesta" in a Spanish town, "Kermis" in a Dutch one).
static func name_of(id: String, what: String) -> String:
	var d: Dictionary = table()[what]
	return d.get("names", {}).get(Ports.port(id).faction, d.name)


static func text_of(id: String, h: Dictionary) -> String:
	var t: String = table()[h.id].text
	return t.format({"port": Ports.port(id).name, "captain": People.person(h.captain).name if h.has("captain") and People.chars.has(h.captain) else "a captain",
		"ship": People.person(h.captain).get("ship", "her") if h.has("captain") and People.chars.has(h.captain) else "her ship", "name": name_of(id, h.id)})


## A day in every port: happenings end, and new ones may start where the town is ripe for them.
## Returns news: [{text, port}] (the world map passes it on at the speed of a ship).
static func daily(rng: RandomNumberGenerator, s: Dictionary) -> Array:
	var news := []
	for id in Ports.state:
		var life := _life(id)
		for h in life.happenings.duplicate():
			if h.until <= Clock.day:
				life.happenings.erase(h)
				life.ended[h.id] = Clock.day
		for what in defs():
			var d: Dictionary = table()[what]
			if is_on(id, what) or Clock.day - float(life.ended.get(what, -INF)) < float(d.get("cooldown", 30)):
				continue
			if rng.randf() >= float(d.chance) or not can_start(id, what, s):
				continue
			var h := start(id, what, rng)
			if not h.is_empty() and d.has("news"):
				news.append({"text": d.news.format({"port": Ports.port(id).name, "name": name_of(id, what)}), "port": id})
	return news


static func can_start(id: String, what: String, s: Dictionary) -> bool:
	var ctx := {"s": s, "port": id, "stats": {}, "storm": false}
	return table()[what].get("when", []).all(func(c): return Events.test(c, ctx, {}))


static func start(id: String, what: String, rng: RandomNumberGenerator) -> Dictionary:
	var d: Dictionary = table()[what]
	var h := {"id": what, "until": Clock.day + rng.randf_range(d.days[0], d.days[1]), "since": Clock.day}
	if d.get("captain", false):  # a named captain: one who haunts these waters if there is one
		var roster: Array = Bonds.roster().filter(func(c): return People.chars.has(c) and People.person(c).get("alive", true) and not active_anywhere(c))
		if roster.is_empty():
			return {}
		var local := roster.filter(func(c): return People.person(c).get("haunt", "") == id)
		var pool := local if not local.is_empty() else roster
		h.captain = pool[rng.randi() % pool.size()]
	if d.has("market"):
		Ports.start_market_event(id, d.market)
	_life(id).happenings.append(h)
	return h


static func active_anywhere(captain: String) -> bool:
	for id in Ports.state:
		if captain_here(id) == captain:
			return true
	return false


## What you can do about a happening while you're in port: {text, event, problem ("" if you can)}, or {}.
static func action(id: String, h: Dictionary, s: Dictionary, stats: Dictionary) -> Dictionary:
	var a: Dictionary = table()[h.id].get("action", {})
	if a.is_empty():
		return {}
	var ctx := {"s": s, "port": id, "stats": stats, "storm": false}
	var missing: Array = a.get("requires", []).filter(func(c): return not Events.test(c, ctx, {}))
	var problem := ""
	if not missing.is_empty():
		problem = a.get("refused", "") if a.has("refused") else "Requires: " + ", ".join(missing.map(func(c): return Events.humanize(c)))
	return {"text": a.text.format({"captain": People.person(h.captain).name if h.has("captain") and People.chars.has(h.captain) else "",
		"name": name_of(id, h.id)}), "event": a.event, "problem": problem}
