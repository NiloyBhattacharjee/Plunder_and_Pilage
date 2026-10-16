extends Node
## Autoload "Factions": who is at war with whom, and which pardons are open. Driven by dated anchors in
## data/history.json (the Nine Years' War, Utrecht, the King's Pardon...). The Brethren are at war with everyone.

signal changed(text: String)

var wars: Array = []        # sorted pairs: ["france", "spain"]
var pardons: Array = []     # factions currently offering a general pardon
var applied: Array = []     # history event ids already applied
var timed: Array = []       # [{pair, until "YYYY-MM-DD"}]: wars declared by events, with their end


func _ready() -> void:
	reset()
	Clock.day_passed.connect(func(_d): apply_history())


func reset() -> void:
	wars = []
	pardons = []
	applied = []
	timed = []
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
							wars.erase(pair)
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
			wars.erase(w.pair)
			if not quiet:
				changed.emit("Peace between %s and %s." % [Data.table("factions")[w.pair[0]].name, Data.table("factions")[w.pair[1]].name])


## A war started by an event, ending on `until` ("YYYY-MM-DD", or "" for none).
func declare(a: String, b: String, until: String) -> void:
	var pair := _pair(a, b)
	if not pair in wars:
		wars.append(pair)
	if until != "":
		timed.append({"pair": pair, "until": until})


func war_summary() -> String:
	if wars.is_empty():
		return "The nations are at peace (but never with the Brethren of the Coast)."
	return "At war: " + ", ".join(wars.map(func(p): return "%s and %s" % [Data.table("factions")[p[0]].name, Data.table("factions")[p[1]].name])) + "."


func save_state() -> Dictionary:
	return {"wars": wars, "pardons": pardons, "applied": applied, "timed": timed}


func load_state(d: Dictionary) -> void:
	wars = d.wars
	pardons = d.pardons
	applied = d.applied
	timed = d.get("timed", [])


static func _pair(a: String, b: String) -> Array:
	return [a, b] if a < b else [b, a]
