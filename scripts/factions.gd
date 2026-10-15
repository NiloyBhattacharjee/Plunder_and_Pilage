extends Node
## Autoload "Factions": who is at war with whom, and which pardons are open. Driven by dated anchors in
## data/history.json (the Nine Years' War, Utrecht, the King's Pardon...). The Brethren are at war with everyone.

signal changed(text: String)

var wars: Array = []        # sorted pairs: ["france", "spain"]
var pardons: Array = []     # factions currently offering a general pardon
var applied: Array = []     # history event ids already applied


func _ready() -> void:
	reset()
	Clock.day_passed.connect(func(_d): apply_history())


func reset() -> void:
	wars = []
	pardons = []
	applied = []
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
			changed.emit(ev.text)


func war_summary() -> String:
	if wars.is_empty():
		return "The nations are at peace (but never with the Brethren of the Coast)."
	return "At war: " + ", ".join(wars.map(func(p): return "%s and %s" % [Data.table("factions")[p[0]].name, Data.table("factions")[p[1]].name])) + "."


func save_state() -> Dictionary:
	return {"wars": wars, "pardons": pardons, "applied": applied}


func load_state(d: Dictionary) -> void:
	wars = d.wars
	pardons = d.pardons
	applied = d.applied


static func _pair(a: String, b: String) -> Array:
	return [a, b] if a < b else [b, a]
