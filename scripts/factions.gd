extends Node
## Autoload "Factions": who is at war with whom, and which pardons are open. Driven by dated anchors in
## data/history.json (the Nine Years' War, Utrecht, the King's Pardon...). The Brethren are at war with everyone.
## Between the dated wars the world moves on its own: tension between each pair of nations drifts month by month,
## and grows with incidents (your raids under one flag on another's ships, false colours, sacks). Past war_at it's
## war, for a while; in a war each side may take the other's smaller towns, and the peace may hand them back.
## Tuning: rules.json "diplomacy".

signal changed(text: String)

var wars: Array = []        # sorted pairs: ["france", "spain"]
var pardons: Array = []     # factions currently offering a general pardon
var applied: Array = []     # history event ids already applied
var timed: Array = []       # [{pair, until "YYYY-MM-DD"}]: wars declared by events, with their end
var tension := {}           # "a|b" -> 0..war_at: how close two nations are to war
var taken: Array = []       # [{port, by, from}]: towns taken in the wars still going
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	reset()
	Clock.day_passed.connect(func(_d):
		apply_history()
		if Clock.date().day == 1:
			monthly())


func reset() -> void:
	wars = []
	pardons = []
	applied = []
	timed = []
	taken = []
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


## In a war, each side may take one of the other's smaller towns (never a capital, never one you hold).
func _campaign(pair: Array) -> void:
	for i in 2:
		var by: String = pair[i]
		var from: String = pair[1 - i]
		if rng.randf() >= cfg().capture_chance:
			continue
		var towns: Array = Ports.state.keys().filter(func(id): return _takeable(id, from))
		if towns.is_empty() or Contracts._ports_of(from).size() <= 1:
			continue
		var id: String = towns[rng.randi() % towns.size()]
		Ports.change_owner(id, by)
		taken.append({"port": id, "by": by, "from": from})
		Economy.add_news("%s has fallen to the %s. The %s flag flies over the fort now." % [Ports.port(id).name, Data.table("factions")[by].adjective,
			Data.table("factions")[by].adjective], id)


static func _takeable(id: String, from: String) -> bool:
	var p := Ports.port(id)
	return p.faction == from and not "capital" in p.tags and p.size != "large" and not Bases.bases.has(id) and not Factions.taken.any(func(t): return t.port == id)  # not straight back again


## Peace: the war is over, tempers cool, and the treaty may hand back what was taken.
func _make_peace(pair: Array, quiet := false) -> void:
	wars.erase(pair)
	tension[_key(pair[0], pair[1])] = cfg().peace_tension
	for t in taken.duplicate():
		if _pair(t.by, t.from) != pair:
			continue
		taken.erase(t)
		if not Bases.bases.has(t.port) and Ports.port(t.port).faction == t.by and rng.randf() < cfg().return_on_peace:
			Ports.change_owner(t.port, t.from)
			if not quiet:
				changed.emit("By the treaty, %s goes back to %s." % [Ports.port(t.port).name, Data.table("factions")[t.from].name])


func save_state() -> Dictionary:
	return {"wars": wars, "pardons": pardons, "applied": applied, "timed": timed, "tension": tension, "taken": taken}


func load_state(d: Dictionary) -> void:
	wars = d.wars
	pardons = d.pardons
	applied = d.applied
	timed = d.get("timed", [])
	tension = d.get("tension", tension)
	taken = d.get("taken", [])


static func _pair(a: String, b: String) -> Array:
	return [a, b] if a < b else [b, a]
