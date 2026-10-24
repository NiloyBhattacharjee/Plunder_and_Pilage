class_name Wants
## What your people want, and what only they have (data/wants.json). Officers and the standout hands in the taverns
## each want one thing (a debt paid, a family seen, a vow kept, a captain beaten, a warship taken, a ship of their
## own), and some carry something no replacement can: kin in a customs house, a friend in trade, a name in the
## taverns, the way into a hidden cove. Help them in time and they're yours; let it lapse and they remember. Lose
## them and what they had goes with them, and their parting has a cost: friends resent it, their home town hears of
## it, a dismissed officer may come back as a rival who knows your ship, and a friend takes up a dead one's cause.
## State, on the character: home (a port), want = {id, port?, target?, due, status: open/done/ignored, sworn?: the
## friend whose cause it was}, asset = {id, port?, cove?, used}, knows_ship (a rival who once sailed in her).


static func table() -> Dictionary:
	return Data.table("wants")


## Gives a person a want (and maybe an asset) if they have none yet. Works on characters not yet in the registry.
static func ensure(c: Dictionary, rng: RandomNumberGenerator) -> void:
	if not c.has("home"):
		c.home = _port_for(c, "home", rng)
	if not c.has("want"):
		var fits: Array = table().wants.keys().filter(func(w): return table().wants[w].traits.any(func(t): return t in c.traits))
		if fits.is_empty():
			fits = table().wants.keys().filter(func(w): return table().wants[w].traits.is_empty())
		var id: String = fits[rng.randi() % fits.size()]
		var d: Dictionary = table().wants[id]
		var r: Array = table()._rules.days
		var w := {"id": id, "due": Clock.day + rng.randf_range(r[0], r[1]), "status": "open"}
		if d.has("port"):
			w.port = c.home if d.port == "home" else _port_for(c, d.port, rng)
		c.want = w
		_aim(c, rng)
	if not c.has("asset"):
		c.asset = {}
		if rng.randf() < float(table()._rules.asset_chance):
			var id: String = table().assets.keys()[rng.randi() % table().assets.size()]
			var hidden: Array = Data.table("coves").keys().filter(func(k): return not k.begins_with("_") and not k in Bases.discovered)
			if id == "cove" and hidden.is_empty():
				id = "price"
			c.asset = {"id": id, "used": false}
			if id == "cove":
				c.asset.cove = hidden[rng.randi() % hidden.size()]
			else:
				c.asset.port = _port_for(c, "any" if rng.randf() < 0.5 else "home", rng)


## A grudge needs someone to hold it against: a named captain, once the roster has any (not Bonds.roster(), which
## would make them before the world is ready).
static func _aim(c: Dictionary, rng: RandomNumberGenerator) -> void:
	if not open(c, "revenge") or c.want.get("target", "") != "":
		return
	var foes: Array = Bonds.captains.filter(func(x): return People.chars.has(x) and People.person(x).get("alive", true))
	if not foes.is_empty():
		c.want.target = foes[rng.randi() % foes.size()]


static func _port_for(c: Dictionary, kind: String, rng: RandomNumberGenerator) -> String:
	var ports: Array = Data.table("ports").keys()  # (not Ports.state: tavern hands are made while it's still filling)
	var f: String = Data.table("nations")[c.nationality].faction if kind == "home" else ""
	var pool: Array = ports.filter(func(id): return Ports.port(id).faction == f) if f != "" else []
	if pool.is_empty():
		pool = ports.filter(func(id): return Ports.port(id).faction != "pirates")
	return pool[rng.randi() % pool.size()]


## The people whose wants and assets count: officers and anyone aboard who has one.
static func people(s: Dictionary) -> Array:
	return s.crew.filter(func(id): return People.chars.has(id) and People.person(id).has("want"))


static func open(c: Dictionary, id := "") -> bool:
	return c.has("want") and c.want.status == "open" and (id == "" or c.want.id == id)


## The want in words: "owes 300 gold to a moneylender in Havana".
static func want_text(c: Dictionary) -> String:
	if not c.has("want"):
		return ""
	return fill(c, table().wants[c.want.id].text)


## Text with their want's {port}, {target} and {ship} filled in.
static func fill(c: Dictionary, t: String) -> String:
	var w: Dictionary = c.want
	var target: Dictionary = People.chars.get(w.get("target", ""), {})
	return t.format({"port": Ports.port(w.port).name if w.has("port") else "", "target": target.get("name", "someone"), "ship": target.get("ship", "her")})


static func asset_text(c: Dictionary) -> String:
	var a: Dictionary = c.get("asset", {})
	if a.is_empty():
		return ""
	var t: String = table().assets[a.id].text
	return t.format({"port": Ports.port(a.port).name if a.has("port") else "", "cove": Bases.cove(a.cove).name if a.has("cove") else ""})


## A line for tooltips and the crew screen.
static func describe(c: Dictionary) -> String:
	var lines := PackedStringArray()
	if c.has("want"):
		var w: Dictionary = c.want
		var when := ""
		match w.status:
			"open": when = " (they'll give up on you in about %d days)" % maxi(0, int(w.due - Clock.day))
			"done": when = " (you saw to it)"
			"ignored": when = " (you let it go, and they remember)"
		var sworn: String = " (sworn over %s's body)" % w.sworn if w.has("sworn") else ""
		lines.append("Wants: %s, %s%s%s." % [table().wants[w.id].name, want_text(c), sworn, when])
	if not c.get("asset", {}).is_empty():
		lines.append("Knows: %s%s." % [asset_text(c), " (used)" if c.asset.used else ""])
	return "\n".join(lines)


## Seen to: they're yours. ignored: they remember. Returns the news.
static func resolve(s: Dictionary, id: String, how: String) -> String:
	if not People.chars.has(id):
		return ""
	var c := People.person(id)
	if not open(c):
		return ""
	var r: Dictionary = table()._rules
	c.want.status = how
	var name: String = table().wants[c.want.id].name.to_lower()
	if id == s.captain:  # their own want, chased as their ambition (Ambitions.from_want)
		c.history.append("Saw to %s at last, %s." % [name, Clock.date_string()])
		Ambitions.tally(s, "own_want")
		return "Captain %s has seen to %s at last." % [c.name, name]
	if how == "done":
		Crew.feel(s, c, int(r.done_opinion), "Saw to " + name)
		if not "loyal" in c.traits and not People._conflicts(c.traits, "loyal"):
			c.traits.append("loyal")
		c.history.append("Their captain saw to %s, %s." % [name, Clock.date_string()])
		return "%s won't forget that you saw to %s. They're yours now (opinion +%d, loyal)." % [c.name, name, r.done_opinion]
	c.relations[s.captain] = clampi(c.relations.get(s.captain, 0) - int(r.ignored_opinion), -100, 100)
	c.history.append("Gave up hoping their captain would help with %s, %s." % [name, Clock.date_string()])
	var text := "%s has given up hoping you'll help with %s (opinion -%d)." % [c.name, name, r.ignored_opinion]
	if c.want.id == "own_ship" and id in s.crew:  # they'll find a ship elsewhere, and feel as they feel about you
		var op: int = c.relations.get(s.captain, 0)
		text += " " + Bonds.former_officer(s, id, 1 if op >= 30 else (-1 if op < 0 else 0))
	return text


## Each day: wants that have waited too long lapse. Returns news.
static func daily(s: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out := []
	for id in s.officers.values():  # a new officer brings their own story
		if People.chars.has(id):
			ensure(People.person(id), rng)
	for id in people(s):
		var c := People.person(id)
		_aim(c, rng)
		if open(c) and Clock.day > float(c.want.due):
			out.append(resolve(s, id, "ignored"))
	return out.filter(func(m): return m != "")


# ---- partings: what losing someone costs -------------------------------------------------

## They leave the ship ("dismissed", "marooned", "hanged", "handed_over", "blessed", "deserted", "died": see
## _parting in data/wants.json). Friends aboard resent it; their home town hears of it; one who knew the ship may
## come back as a captain who knows her weak points. Removes them. Returns the news.
static func part(s: Dictionary, id: String, how: String) -> String:
	if not id in s.crew:
		return ""
	var c := People.person(id)
	var p: Dictionary = table()._parting.get(how, table()._parting.dismissed)
	var out := PackedStringArray()
	var friends := Crew.friends_of(s, id)
	if int(p.friends) != 0 and not friends.is_empty():
		for f in friends:
			var fc := People.person(f)
			fc.relations[s.captain] = clampi(fc.relations.get(s.captain, 0) + int(p.friends), -100, 100)
			fc.history.append("Never forgave their captain for what was done to %s, %s." % [c.name, Clock.date_string()])
		out.append("%s won't forgive you for it (opinion %d)." % [", ".join(friends.map(func(f): return People.person(f).name)), p.friends])
	if p.get("deed", "") != "" and c.get("home", "") != "":
		out.append(PortLife.remember(c.home, p.deed))
	if c.has("want") and Bonds.rng.randf() < float(p.rival):
		var op: int = c.relations.get(s.captain, 0)
		var lvl := 1 if op >= 30 else (-1 if op < 0 else 0)
		if lvl <= 0:
			c.knows_ship = s.name
		out.append(Bonds.former_officer(s, id, lvl) + (" They know every weak point of your ship." if lvl <= 0 else ""))
		Crew.remove_hand(s, id, true)
		return " ".join(out)
	if how == "marooned" and c.has("want"):  # one you knew doesn't die on the sandbar: the story "castaway" (data/stories.json)
		Events.queue.append({"id": "castaway_word", "at": Clock.day + 30.0, "until": Clock.day + 210.0, "vars": {"who": id}})
		Crew.remove_hand(s, id, true)
		return " ".join(out)
	Crew.remove_hand(s, id)
	return " ".join(out)


## What parting with them would cost, for a tooltip before you do it.
static func parting_text(s: Dictionary, id: String, how: String) -> String:
	var c := People.person(id)
	var p: Dictionary = table()._parting.get(how, table()._parting.dismissed)
	var out := PackedStringArray()
	var friends := Crew.friends_of(s, id)
	if int(p.friends) != 0 and not friends.is_empty():
		out.append("Their friends aboard won't forgive it (%s: opinion %d)." % [", ".join(friends.map(func(f): return People.person(f).name)), p.friends])
	if p.get("deed", "") != "" and c.get("home", "") != "":
		out.append("%s, their home town, will hear of it." % Ports.port(c.home).name)
	if not c.get("asset", {}).is_empty():
		out.append("What they know goes with them: %s." % asset_text(c))
	if c.has("want") and float(p.rival) > 0.0:
		out.append("They may come back with a ship of their own%s." % (", knowing every weak point of yours" if c.relations.get(s.captain, 0) < 30 else ""))
	return "\n".join(out)


## A rival who once sailed in your ship: their name, or "".
static func knows_you(enemy: Dictionary) -> String:
	var c: Dictionary = People.chars.get(enemy.get("captain_id", ""), {})
	return c.name if c.get("knows_ship", "") != "" else ""


## They died. Their closest friend aboard swears to finish what they started: their cause, or revenge on the
## captain who killed them. Returns the news.
static func inherit(s: Dictionary, id: String, killer := "") -> String:
	if not People.chars.has(id):
		return ""
	var dead := People.person(id)
	var w := {}
	if killer != "" and People.chars.has(killer) and People.person(killer).get("alive", true):
		w = {"id": "revenge", "target": killer, "status": "open"}
	elif open(dead) and table().wants[dead.want.id].get("inherit", false):
		w = dead.want.duplicate()
	if w.is_empty() or not dead.has("want"):  # only the people you know leave a cause behind
		return ""
	var heirs: Array = Crew.friends_of(s, id).filter(func(f): return not open(People.person(f)))
	if heirs.is_empty():
		return ""
	heirs.sort_custom(func(a, b): return People.person(a).relations.get(id, 0) > People.person(b).relations.get(id, 0))
	var f := People.person(heirs[0])
	var r: Array = table()._rules.days
	w.due = Clock.day + Bonds.rng.randf_range(r[0], r[1])
	w.sworn = dead.name
	f.want = w
	if not f.has("asset"):
		f.asset = {}
	if not f.has("home"):
		f.home = _port_for(f, "home", Bonds.rng)
	f.history.append("Swore over %s's body to finish what they started, %s." % [dead.name, Clock.date_string()])
	return "%s swears to finish what %s started: %s." % [f.name, dead.name, want_text(f)]


## After a battle: a rival beaten, a warship taken.
static func on_battle(s: Dictionary, enemy: Dictionary, outcome: String) -> Array:
	var out := []
	if not outcome in ["enemy_struck", "enemy_sunk"]:
		return out
	for id in people(s) + [s.captain]:
		var c := People.person(id)
		if open(c, "revenge") and enemy.get("captain_id", "") != "" and enemy.get("captain_id", "") == c.want.get("target", "") \
				or open(c, "glory") and enemy.get("kind", "") == "navy" and outcome == "enemy_struck":
			out.append(resolve(s, id, "done"))
	return out


## Anchored: the captain's own want is seen to in its port, if you can pay what it costs. Returns the news, or "".
static func captain_arrives(s: Dictionary, port: String) -> String:
	var cap := ShipStats.captain(s)
	if not open(cap) or cap.want.get("port", "") != port or table().wants[cap.want.id].resolve != "event":
		return ""
	var cost := int(table().wants[cap.want.id].get("cost", 0))
	if s.gold < cost:
		return "%s at last, but seeing to %s will take %d gold." % [Ports.port(port).name, table().wants[cap.want.id].name.to_lower(), cost]
	s.gold -= cost
	return resolve(s, cap.id, "done")


## Whoever aboard holds this asset for this port (and hasn't used it up), or {}.
static func helper(s: Dictionary, port: String, asset: String) -> Dictionary:
	for id in people(s):
		var a: Dictionary = People.person(id).get("asset", {})
		if a.get("id", "") == asset and a.get("port", "") == port and not a.get("used", false):
			return People.person(id)
	return {}


## Your seizure risk in this port, after the help of kin in the customs house.
static func customs_mult(s: Dictionary, port: String) -> float:
	return float(table().assets.customs.mult) if not helper(s, port, "customs").is_empty() else 1.0


## They lead you to their hidden anchorage. Returns the news.
static func show_cove(c: Dictionary) -> String:
	var a: Dictionary = c.get("asset", {})
	if a.get("id", "") != "cove" or a.used:
		return ""
	a.used = true
	if not a.cove in Bases.discovered:
		Bases.discovered.append(a.cove)
	c.history.append("Showed their captain the way into %s, %s." % [Bases.cove(a.cove).name, Clock.date_string()])
	return "%s marks the way into %s on your chart." % [c.name, Bases.cove(a.cove).name]
