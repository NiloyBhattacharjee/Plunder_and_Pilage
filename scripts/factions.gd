extends Node
## Autoload "Factions": who is at war with whom, and which pardons are open. Driven by dated anchors in
## data/history.json (the Nine Years' War, Utrecht, the King's Pardon...). The Brethren are at war with everyone.
## Between the dated wars the world moves on its own: tension between each pair of nations drifts month by month,
## and grows with incidents (your raids under one flag on another's ships, false colours, sacks). Past war_at it's
## war, for a while; in a war each side sends invasion squadrons against the other's smaller towns: real ships that
## sail from their nearest port, which you can catch at sea. The peace may hand captured towns back.
## Tuning: rules.json "diplomacy".

signal changed(text: String)

var wars: Array = []        # sorted pairs: ["france", "spain"]
var pardons: Array = []     # factions currently offering a general pardon
var applied: Array = []     # history event ids already applied
var timed: Array = []       # [{pair, until "YYYY-MM-DD"}]: wars declared by events, with their end
var tension := {}           # "a|b" -> 0..war_at: how close two nations are to war
var taken: Array = []       # [{port, by, from}]: towns taken in the wars still going
var invasions: Array = []   # [{port, by, from, due, npc, spawned}]: squadrons on their way to take a town
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	reset()
	Clock.day_passed.connect(func(_d):
		apply_history()
		_invasions_due()
		if Clock.date().day == 1:
			monthly())


func reset() -> void:
	wars = []
	pardons = []
	applied = []
	timed = []
	taken = []
	invasions = []
	tension = {}
	for a in Career.nations():
		for b in Career.nations():
			if a < b:
				tension[_key(a, b)] = rng.randf_range(cfg().start[0], cfg().start[1])
	apply_history(true)


func at_war(a: String, b: String) -> bool:
	if a == b or a == "" or b == "":
		return false
	if a == "pirates" or b == "pirates":
		return true
	return _pair(a, b) in wars


func enemies_of(f: String) -> Array:
	return Data.table("factions").keys().filter(func(o): return o != "pirates" and at_war(f, o))


## Applies every history event whose date has come. Quiet on the first run (the starting situation).
func apply_history(quiet := false) -> void:
	var today := Clock.date()
	var stamp := "%04d-%02d-%02d" % [today.year, today.month, today.day]
	for id in Data.table("history"):
		if id.begins_with("_") or id in applied:
			continue
		var ev: Dictionary = Data.table("history")[id]
		if ev.date > stamp:
			continue
		applied.append(id)
		if ev.has("unless_flag") and Events.flags.has(ev.unless_flag):
			continue  # the player changed history
		if ev.has("if_flag") and not Events.flags.has(ev.if_flag):
			continue
		if ev.has("effects"):  # what it does to the market and the world (scripts/economy/effects.gd)
			EconomyEffects.apply_all(ev.effects, {"s": EconomyEffects.player})
		match ev.kind:
			"war", "peace":
				for a in ev.sides[0]:
					for b in ev.sides[1]:
						var pair := _pair(a, b)
						if ev.kind == "war" and not pair in wars:
							wars.append(pair)
						elif ev.kind == "peace":
							_make_peace(pair, quiet)
						timed = timed.filter(func(w): return w.pair != pair)  # history overrides a war of the moment
			"pardon":
				for f in ev.factions:
					if not f in pardons:
						pardons.append(f)
			"pardon_end":
				for f in ev.factions:
					pardons.erase(f)
		if not quiet:
			if ev.has("port"):
				Economy.add_news(ev.text, ev.port)  # news of it travels at sailing speed
			else:
				changed.emit(ev.text)
	for w in timed.duplicate():
		if w.until != "" and w.until <= stamp:
			timed.erase(w)
			if not quiet:
				changed.emit("Peace between %s and %s." % [Data.table("factions")[w.pair[0]].name, Data.table("factions")[w.pair[1]].name])
			_make_peace(w.pair, quiet)


## A war started by an event, ending on `until` ("YYYY-MM-DD", or "" for none).
func declare(a: String, b: String, until: String) -> void:
	var pair := _pair(a, b)
	if not pair in wars:
		wars.append(pair)
	if until != "":
		timed.append({"pair": pair, "until": until})


func war_summary() -> String:
	var text := "The nations are at peace (but never with the Brethren of the Coast)."
	if not wars.is_empty():
		text = "At war: " + ", ".join(wars.map(func(p): return "%s and %s" % [Data.table("factions")[p[0]].name, Data.table("factions")[p[1]].name])) + "."
	var close: Array = tension.keys().filter(func(k): return not Array(k.split("|")) in wars and tension[k] >= cfg().war_at * 0.7)
	if not close.is_empty():
		text += "\nTalk of war between " + ", ".join(close.map(func(k): return " and ".join(Array(k.split("|")).map(func(f): return Data.table("factions")[f].name)))) + "."
	return text


static func cfg() -> Dictionary:
	return Data.rules.diplomacy


static func _key(a: String, b: String) -> String:
	var p := _pair(a, b)
	return p[0] + "|" + p[1]


## Something that sets two nations against each other: a raid by one's privateer on the other's ships, a sack,
## a ship taken under false colours. Nothing between a nation and the Brethren, or a nation and itself.
func incident(a: String, b: String, amount: float) -> void:
	if a == b or a == "" or b == "" or a == "pirates" or b == "pirates" or not tension.has(_key(a, b)):
		return
	tension[_key(a, b)] = minf(cfg().war_at, tension[_key(a, b)] + amount)


## The month's drift: tempers rise and fall; past war_at, war (for war_months). Wars let each side take
## the other's smaller towns. Returns nothing: news goes out through `changed` and the economy's news.
func monthly() -> void:
	var c := cfg()
	for k in tension:
		var pair := Array(k.split("|"))
		if pair in wars:
			tension[k] = maxf(0.0, tension[k] - c.war_cools)
			_campaign(pair)
			continue
		tension[k] = clampf(tension[k] + rng.randf_range(c.drift[0], c.drift[1]), 0.0, c.war_at)
		if tension[k] >= c.war_at and wars.size() < int(c.max_wars):
			var d := Clock.date()
			var months := rng.randi_range(int(c.war_months[0]), int(c.war_months[1]))
			var until := "%04d-%02d-01" % [d.year + int((d.month - 1 + months) / 12), (d.month - 1 + months) % 12 + 1]
			declare(pair[0], pair[1], until)
			changed.emit("War! %s and %s have come to blows. Letters of marque against each other are to be had in every port." % [
				Data.table("factions")[pair[0]].name, Data.table("factions")[pair[1]].name])


## In a war, each side may send a squadron against one of the other's smaller towns (never a capital, never one
## you hold). It gathers for a while, sails lead_days before it's due (Shipping), and attacks on the day.
func _campaign(pair: Array) -> void:
	var inv: Dictionary = cfg().invasion
	for i in 2:
		var by: String = pair[i]
		var from: String = pair[1 - i]
		if rng.randf() >= cfg().capture_chance or invasions.any(func(x): return x.by == by):
			continue
		var towns: Array = Ports.state.keys().filter(func(id): return _takeable(id, from))
		if towns.is_empty() or Contracts._ports_of(from).size() <= 1 or Contracts._ports_of(by).is_empty():
			continue
		var id: String = towns[rng.randi() % towns.size()]
		var due := Clock.day + rng.randf_range(inv.days[0], inv.days[1])
		invasions.append({"port": id, "by": by, "from": from, "due": due, "npc": "", "spawned": false})
		Economy.add_news("A %s squadron is fitting out to attack %s. They say it sails within the month." % [Data.table("factions")[by].adjective, Ports.port(id).name], id)


static func _takeable(id: String, from: String) -> bool:
	var p := Ports.port(id)
	return p.faction == from and not "capital" in p.tags and p.size != "large" and not Bases.bases.has(id) \
		and not Factions.taken.any(func(t): return t.port == id) and not Factions.invasions.any(func(t): return t.port == id)


func invasion_at(port_id: String) -> Dictionary:
	for x in invasions:
		if x.port == port_id:
			return x
	return {}


## The squadron's day: its strength (and the state you've left it in) against the town's fort, walls and garrison.
## A town you've taken meanwhile, a peace, or a squadron that never arrived calls it off.
func _invasions_due() -> void:
	for x in invasions.duplicate():
		if Clock.day < x.due:
			continue
		invasions.erase(x)
		var sea: Node = Contracts.shipping if is_instance_valid(Contracts.shipping) else null
		var n: Dictionary = sea.find(x.npc) if sea != null and x.npc != "" else {}
		if not n.is_empty():
			sea.remove(n)
		if Ports.port(x.port).faction != x.from or Bases.bases.has(x.port) or not at_war(x.by, x.from) or (x.spawned and n.is_empty() and not x.get("unseen", false)):
			continue
		var check := Dice.contest(rng, "The attack on %s" % Ports.port(x.port).name, invasion_parts(x, n), defence_parts(x.port))
		var adj: String = Data.table("factions")[x.by].adjective
		if check.success:
			Ports.change_owner(x.port, x.by)
			taken.append({"port": x.port, "by": x.by, "from": x.from})
			Economy.add_news("%s has fallen to the %s squadron. The %s flag flies over the fort now." % [Ports.port(x.port).name, adj, adj], x.port)
		else:
			Economy.add_news("The %s attack on %s has been beaten off." % [adj, Ports.port(x.port).name], x.port)


static func invasion_parts(x: Dictionary, n := {}) -> Array:
	var parts := [["%s squadron" % Data.table("factions")[x.by].adjective, int(cfg().invasion.strength)]]
	if not n.is_empty():
		var st := ShipStats.effective(n.enemy.type, n.enemy.upgrades)
		var state := int(round((float(n.enemy.hull) / float(st.hull) - 1.0) * 6.0))
		if state != 0:
			parts.append(["Battered on the way", state])
	return parts


static func defence_parts(port_id: String) -> Array:
	var d := Sieges.defences(port_id)
	return [["The fort", int(d.fort)], ["Walls", int(d.walls)], ["Garrison of %d" % d.garrison, int(d.garrison / 40)]]


## You caught the squadron at sea and beat it: the attack is off, and the town's masters are grateful.
func invasion_beaten(port_id: String, s: Dictionary) -> String:
	var x := invasion_at(port_id)
	if x.is_empty():
		return ""
	invasions.erase(x)
	var rel := int(cfg().invasion.rescue_relation)
	s.relations[x.from] = s.relations.get(x.from, 0) + rel
	return "The squadron sent against %s is broken. %s owes you for it (standing +%d)." % [Ports.port(port_id).name, Career.fname(x.from), rel]


## Peace: the war is over, tempers cool, and the treaty may hand back what was taken.
func _make_peace(pair: Array, quiet := false) -> void:
	wars.erase(pair)
	tension[_key(pair[0], pair[1])] = cfg().peace_tension
	invasions = invasions.filter(func(x): return _pair(x.by, x.from) != pair)
	for t in taken.duplicate():
		if _pair(t.by, t.from) != pair:
			continue
		taken.erase(t)
		if not Bases.bases.has(t.port) and Ports.port(t.port).faction == t.by and rng.randf() < cfg().return_on_peace:
			Ports.change_owner(t.port, t.from)
			if not quiet:
				changed.emit("By the treaty, %s goes back to %s." % [Ports.port(t.port).name, Data.table("factions")[t.from].name])


func save_state() -> Dictionary:
	return {"wars": wars, "pardons": pardons, "applied": applied, "timed": timed, "tension": tension, "taken": taken, "invasions": invasions}


func load_state(d: Dictionary) -> void:
	wars = d.wars
	pardons = d.pardons
	applied = d.applied
	timed = d.get("timed", [])
	tension = d.get("tension", tension)
	taken = d.get("taken", [])
	invasions = d.get("invasions", [])


static func _pair(a: String, b: String) -> Array:
	return [a, b] if a < b else [b, a]
