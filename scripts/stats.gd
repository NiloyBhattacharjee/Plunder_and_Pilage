class_name Stats
## The weekly record behind the crew screen's Charts tab: a snapshot of your purse, your standing, the crew and the
## sea every week, kept in the ship state as s.stats (so it's saved with the game). Only what the captain could know:
## no live prices from ports you aren't in.

const MAX := 520  # ten years of weeks. ponytail: the oldest weeks drop off; thin them out if long careers want the whole line


## Takes this week's snapshot. npcs are the ships on the map (Shipping.npcs).
static func week(s: Dictionary, stats: Dictionary, npcs: Array) -> void:
	var rec: Array = s.get("stats", [])
	s.stats = rec
	var since: int = rec[-1].day if not rec.is_empty() else int(Clock.day) - 7
	var cap := ShipStats.captain(s)
	var crew := Crew.people(s)
	var traffic: Traffic = Economy.model.traffic
	var b: Brethren = Economy.model.brethren
	var counts := {}
	for n in npcs:
		counts[n.kind] = counts.get(n.kind, 0) + 1
	var regard := {}
	for id in Data.table("ports"):
		var r := PortLife.regard(id)
		if absf(r) >= 1.0:
			regard[id] = snappedf(r, 0.1)
	var towns := {}
	var people := {}
	for id in Data.table("ports"):
		if id.begins_with("_"):
			continue
		var p := Ports.port(id)
		towns[id] = int(p.population)
		people[p.faction] = people.get(p.faction, 0) + int(p.population)
	var maroons := {}
	for id in Maroons.bands:
		maroons[id] = int(Maroons.bands[id].strength)
	rec.append({
		"day": int(Clock.day),
		"gold": int(s.gold),
		"trade": s.get("ledger", []).filter(func(t): return t.day > since and t.qty < 0).reduce(func(a, t): return a + t.profit, 0),
		"costs": int(ShipStats.daily_cost(s, stats) * 7.0),
		"morale": int(Crew.morale(s, stats).value),
		"opinion": snappedf(crew.reduce(func(a, c): return a + Crew.opinion(c, s), 0) / float(maxi(1, crew.size())), 0.1),
		"crew": s.crew.size(),
		"relations": s.relations.duplicate(),
		"regard": regard,
		"bounty": int(Career.bounty_total(s)),
		"notoriety": int(s.reputation.notoriety), "honour": int(s.reputation.honour), "fear": int(s.reputation.fear),
		"pirates": counts.get("pirate", 0), "navy": counts.get("navy", 0) + counts.get("hunter", 0),
		"voyages": traffic.voyages.size(),
		"brethren": b.men(), "companies": b.companies.size(), "idle": int(b.idle),
		"navy_ships": snappedf(b.navy.values().reduce(func(a, x): return a + x, 0.0), 0.1),
		"losses": traffic.lost_log.filter(func(l): return l.day > since).size(),
		"wars": Factions.wars.duplicate(true),
		"towns": towns, "people": people, "maroons": maroons,  # people per port and per nation; Maroon strength per landing
		"notes": cap.history.slice(int(s.get("stats_seen", cap.history.size()))),  # what the captain did this week
	})
	s.stats_seen = cap.history.size()
	if rec.size() > MAX:
		rec.pop_front()


## One number per week from the record: key is a field, or "relations.england" for a field inside one.
static func line(s: Dictionary, key: String) -> Array:
	var parts := key.split(".")
	return s.get("stats", []).map(func(w):
		var v = w.get(parts[0], {} if parts.size() > 1 else 0)  # weeks from older saves lack newer fields
		return float(v.get(parts[1], 0) if parts.size() > 1 else v))


## History events (data/history.json) inside the record, as [{at: week index, text}].
static func history_marks(s: Dictionary) -> Array:
	var rec: Array = s.get("stats", [])
	var out := []
	if rec.size() < 2:
		return out
	var stamp := func(d: int) -> String:
		var t := Clock.date_of(d)
		return "%04d-%02d-%02d" % [t.year, t.month, t.day]
	for i in range(1, rec.size()):
		var a: String = stamp.call(rec[i - 1].day)
		var b: String = stamp.call(rec[i].day)
		for id in Data.table("history"):
			var ev = Data.table("history")[id]
			if ev is Dictionary and ev.date > a and ev.date <= b:
				out.append({"at": i, "text": ev.text})
	return out


## The weeks any war was on, as shaded bands: [{from, to, text}] in week indexes.
static func war_bands(s: Dictionary) -> Array:
	var rec: Array = s.get("stats", [])
	var out := []
	for i in rec.size():
		var on: Array = rec[i].wars
		if on.is_empty():
			continue
		var text := "At war: " + ", ".join(on.map(func(p): return "%s against %s" % [Career.fname(p[0]), Career.fname(p[1])]))
		if not out.is_empty() and out[-1].to == i - 1 and out[-1].text == text:
			out[-1].to = i
		else:
			out.append({"from": i, "to": i, "text": text})
	return out
