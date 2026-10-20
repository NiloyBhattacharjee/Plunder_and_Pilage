class_name Ambitions
## What the captain is striving for, Paradox style: take up one ambition at a time, chase it, and win a title for
## life (and sometimes a lasting edge in a fight). Data in data/ambitions.json. Progress is either a value of your
## situation (gold, fear, prizes in company: the event conditions' keys) or a tally of deeds done since you took
## the ambition up (ships taken, treasure galleons, rescues, finds...). The ambition and titles are the captain's
## (cap.ambition: the one they're chasing, cap.titles: achieved), so they die with them; the ship keeps s.tally
## (deeds counted all game). A captain who came up from the crew starts out chasing what they always wanted.


static func table() -> Dictionary:
	return Data.table("ambitions")


## Returns the captain, with their ambition and titles.
static func ensure(s: Dictionary) -> Dictionary:
	if not s.has("tally"):
		s.tally = {}
	var cap := ShipStats.captain(s)
	if s.has("titles"):  # older saves kept these on the ship
		cap.ambition = s.get("ambition", {})
		cap.titles = s.titles
		s.erase("ambition")
		s.erase("titles")
	if not cap.has("ambition"):
		cap.ambition = {}
	if not cap.has("titles"):
		cap.titles = []
	return cap


## Counts a deed toward ambitions: tally(s, "ships_taken"), tally(s, "trade_profit", 340).
static func tally(s: Dictionary, key: String, n := 1.0) -> void:
	if not s.has("tally"):
		s.tally = {}
	s.tally[key] = float(s.tally.get(key, 0.0)) + n


## The ambitions you could take up now: not yet achieved, and their conditions met. (A want's ambition only comes
## with a captain who had that want: from_want.)
static func offered(s: Dictionary, ctx: Dictionary) -> Array:
	var cap := ensure(s)
	var out := []
	for id in table():
		if id.begins_with("_") or id in cap.titles or table()[id].has("want"):
			continue
		if table()[id].get("requires", []).all(func(c): return Events.test(c, ctx, {})):
			out.append(id)
	return out


## goal: the goal in words, when it's particular to this captain ("Beat Captain Vane of the Ranger").
static func take(s: Dictionary, id: String, goal := "") -> void:
	var cap := ensure(s)
	var a: Dictionary = table()[id]
	cap.ambition = {"id": id, "start": float(s.tally.get(a.tally, 0.0)) if a.has("tally") else 0.0, "day": Clock.day}
	if goal != "":
		cap.ambition.goal = goal


## A new captain up from the crew chases what they always wanted: their open want becomes their ambition (the
## ambitions.json entry with that "want"). One who wanted a ship of their own has one now. Returns the news, or "".
static func from_want(s: Dictionary) -> String:
	var cap := ensure(s)
	if not Wants.open(cap):
		return ""
	if cap.want.id == "own_ship":
		cap.want.status = "done"
		return "%s always wanted a ship of their own. Now they have one." % cap.name
	for id in table():
		if not id.begins_with("_") and table()[id].get("want", "") == cap.want.id:
			take(s, id, Wants.fill(cap, table()[id].goal))
			return "%s's ambition is their own: %s." % [cap.name, cap.ambition.goal]
	return ""


## Giving up costs the crew's faith in you a little: they'd started to believe in it.
static func abandon(s: Dictionary, ctx: Dictionary) -> String:
	var cap := ensure(s)
	if cap.ambition.is_empty():
		return ""
	var name: String = table()[cap.ambition.id].name
	cap.ambition = {}
	return "You give up on %s. %s" % [name.to_lower(), Events.apply_outcome("opinion crew -2", ctx)]


## [have, need] for the ambition you're chasing (or [0, 0]).
static func progress(s: Dictionary, ctx: Dictionary) -> Array:
	var cap := ensure(s)
	if cap.ambition.is_empty():
		return [0.0, 0.0]
	var a: Dictionary = table()[cap.ambition.id]
	var have: float = float(s.tally.get(a.tally, 0.0)) - float(cap.ambition.start) if a.has("tally") else float(Events.value(a.value, ctx))
	return [maxf(0.0, have), float(a.target)]


## "Take five ships (2/5)".
static func summary(s: Dictionary, ctx: Dictionary) -> String:
	var cap := ensure(s)
	if cap.ambition.is_empty():
		return ""
	var p := progress(s, ctx)
	return "%s (%s/%s)" % [cap.ambition.get("goal", table()[cap.ambition.id].goal), _num(p[0]), _num(p[1])]


static func _num(x: float) -> String:
	return "%d" % x if x < 1000.0 else "%.1fk" % (x / 1000.0)


## Achieved? Applies the rewards, grants the title and clears the ambition. Returns {name, title, text} or {}.
static func check(s: Dictionary, ctx: Dictionary) -> Dictionary:
	var cap := ensure(s)
	if cap.ambition.is_empty():
		return {}
	var p := progress(s, ctx)
	if p[0] < p[1]:
		return {}
	var id: String = cap.ambition.id
	var a: Dictionary = table()[id]
	var lines := PackedStringArray()
	for o in a.get("rewards", []):
		var line := Events.apply_outcome(o, ctx)
		if line != "":
			lines.append(line)
	for k in a.get("bonus", {}):
		if k == "enemy_morale":
			lines.append("Enemies' morale %+d when they face you" % int(a.bonus[k]))
	cap.titles.append(id)
	cap.ambition = {}
	cap.history.append("Became known as %s, %s." % [a.title, Clock.date_string()])
	return {"name": a.name, "title": a.title, "text": "%s\n\nYou are known now as %s.\n\n%s" % [a.description, a.title, "\n".join(lines)]}


## The sum of a lasting edge from every title you hold.
static func bonus(s: Dictionary, key: String) -> float:
	var cap := ensure(s)
	var total := 0.0
	for id in cap.titles:
		total += float(table()[id].get("bonus", {}).get(key, 0.0))
	return total


## The title you're best known by (the latest), or "".
static func title(s: Dictionary) -> String:
	var cap := ensure(s)
	return table()[cap.titles[-1]].title if not cap.titles.is_empty() else ""
