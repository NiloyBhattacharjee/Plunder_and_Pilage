class_name Ambitions
## What the captain is striving for, Paradox style: take up one ambition at a time, chase it, and win a title for
## life (and sometimes a lasting edge in a fight). Data in data/ambitions.json. Progress is either a value of your
## situation (gold, fear, prizes in company: the event conditions' keys) or a tally of deeds done since you took
## the ambition up (ships taken, treasure galleons, rescues, finds...). Kept in the ship state: s.ambition (the
## one you're chasing), s.tally (deeds counted all game), s.titles (ambitions achieved).


static func table() -> Dictionary:
	return Data.table("ambitions")


static func ensure(s: Dictionary) -> void:
	if not s.has("ambition"):
		s.ambition = {}
	if not s.has("tally"):
		s.tally = {}
	if not s.has("titles"):
		s.titles = []


## Counts a deed toward ambitions: tally(s, "ships_taken"), tally(s, "trade_profit", 340).
static func tally(s: Dictionary, key: String, n := 1.0) -> void:
	ensure(s)
	s.tally[key] = float(s.tally.get(key, 0.0)) + n


## The ambitions you could take up now: not yet achieved, and their conditions met.
static func offered(s: Dictionary, ctx: Dictionary) -> Array:
	ensure(s)
	var out := []
	for id in table():
		if id.begins_with("_") or id in s.titles:
			continue
		if table()[id].get("requires", []).all(func(c): return Events.test(c, ctx, {})):
			out.append(id)
	return out


static func take(s: Dictionary, id: String) -> void:
	ensure(s)
	var a: Dictionary = table()[id]
	s.ambition = {"id": id, "start": float(s.tally.get(a.tally, 0.0)) if a.has("tally") else 0.0, "day": Clock.day}


## Giving up costs the crew's faith in you a little: they'd started to believe in it.
static func abandon(s: Dictionary, ctx: Dictionary) -> String:
	ensure(s)
	if s.ambition.is_empty():
		return ""
	var name: String = table()[s.ambition.id].name
	s.ambition = {}
	return "You give up on %s. %s" % [name.to_lower(), Events.apply_outcome("opinion crew -2", ctx)]


## [have, need] for the ambition you're chasing (or [0, 0]).
static func progress(s: Dictionary, ctx: Dictionary) -> Array:
	ensure(s)
	if s.ambition.is_empty():
		return [0.0, 0.0]
	var a: Dictionary = table()[s.ambition.id]
	var have: float = float(s.tally.get(a.tally, 0.0)) - float(s.ambition.start) if a.has("tally") else float(Events.value(a.value, ctx))
	return [maxf(0.0, have), float(a.target)]


## "Take five ships (2/5)".
static func summary(s: Dictionary, ctx: Dictionary) -> String:
	ensure(s)
	if s.ambition.is_empty():
		return ""
	var p := progress(s, ctx)
	return "%s (%s/%s)" % [table()[s.ambition.id].goal, _num(p[0]), _num(p[1])]


static func _num(x: float) -> String:
	return "%d" % x if x < 1000.0 else "%.1fk" % (x / 1000.0)


## Achieved? Applies the rewards, grants the title and clears the ambition. Returns {name, title, text} or {}.
static func check(s: Dictionary, ctx: Dictionary) -> Dictionary:
	ensure(s)
	if s.ambition.is_empty():
		return {}
	var p := progress(s, ctx)
	if p[0] < p[1]:
		return {}
	var id: String = s.ambition.id
	var a: Dictionary = table()[id]
	var lines := PackedStringArray()
	for o in a.get("rewards", []):
		var line := Events.apply_outcome(o, ctx)
		if line != "":
			lines.append(line)
	for k in a.get("bonus", {}):
		if k == "enemy_morale":
			lines.append("Enemies' morale %+d when they face you" % int(a.bonus[k]))
	s.titles.append(id)
	s.ambition = {}
	ShipStats.captain(s).history.append("Became known as %s, %s." % [a.title, Clock.date_string()])
	return {"name": a.name, "title": a.title, "text": "%s\n\nYou are known now as %s.\n\n%s" % [a.description, a.title, "\n".join(lines)]}


## The sum of a lasting edge from every title you hold.
static func bonus(s: Dictionary, key: String) -> float:
	ensure(s)
	var total := 0.0
	for id in s.titles:
		total += float(table()[id].get("bonus", {}).get(key, 0.0))
	return total


## The title you're best known by (the latest), or "".
static func title(s: Dictionary) -> String:
	ensure(s)
	return table()[s.titles[-1]].title if not s.titles.is_empty() else ""
