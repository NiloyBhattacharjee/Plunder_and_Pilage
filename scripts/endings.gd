class_name Endings
## How a career ends. Some endings you choose when you've earned them (retire rich, a governorship from the Crown,
## a republic of the Brethren at Nassau); some choose you (hanged, lost at sea, no one left to take the helm).
## Every ending reads back the ship's log: the line of captains and what they did. Tuning: rules.json "endings".


static func cfg() -> Dictionary:
	return Data.rules.endings


## Everything the captain has: purse, treasuries ashore, and what the prizes would fetch.
static func fortune(s: Dictionary) -> int:
	var total: float = s.gold
	for id in Bases.bases:
		total += Bases.bases[id].gold
	return int(total)


## The endings you can choose: [{id, name, text, why}] (why: what's missing, or "").
static func choices(s: Dictionary, docked: bool) -> Array:
	var c := cfg()
	var out := []
	var why := ""
	if fortune(s) < c.retire_gold:
		why = "You need %d gold to your name (you have %d)." % [c.retire_gold, fortune(s)]
	elif not docked:
		why = "Retire from a port, or from one of your bases."
	out.append({"id": "retire", "name": "Retire rich", "why": why,
		"text": "Buy an estate, a wife's or husband's good name, a seat in some assembly, and never smell tar again."})
	var nation := patron(s)
	var town := _town(s)
	why = ""
	if town == "":
		why = "Hold a town of your own first."
	elif nation == "":
		why = "You need a nation to serve: a letter of marque, or a pardon."
	elif s.relations.get(nation, 0) < c.governor_standing:
		why = "Your standing with %s must be %d (it is %d)." % [Career.fname(nation), c.governor_standing, s.relations.get(nation, 0)]
	elif s.career.marque == nation and s.career.rank < int(c.governor_rank):
		why = "The Crown makes governors of %ss, not of %ss." % [Career.cfg().ranks[int(c.governor_rank)].name.to_lower(), Career.rank_name(s).to_lower()]
	out.append({"id": "governor", "name": "Become a governor", "why": why,
		"text": "Hand %s to %s and govern it in the Crown's name: respectable at last, and rich in a quieter way." % [
			Ports.port(town).name if town != "" else "a town you hold", Career.fname(nation) if nation != "" else "a Crown"]})
	why = ""
	var towns := Bases.bases.keys().filter(func(id): return Bases.is_town(id)).size()
	if Politics.council_leader != "player" or not Bases.bases.has("nassau"):
		why = "Lead Nassau's council and hold Nassau."
	elif towns < int(c.republic_towns):
		why = "Hold %d towns (you hold %d)." % [c.republic_towns, towns]
	out.append({"id": "republic", "name": "Found a pirate republic", "why": why,
		"text": "Declare the Republic of the Brethren at Nassau, under the black flag, with laws of your own making. Let the Crowns come."})
	return out


## The nation that would have you: your commission's, or the last that pardoned you.
static func patron(s: Dictionary) -> String:
	if s.career.marque != "":
		return s.career.marque
	return s.career.pardoned_by[-1] if not s.career.pardoned_by.is_empty() and not s.career.pirate else ""


static func _town(s: Dictionary) -> String:
	for id in Bases.bases:
		if Bases.is_town(id) and id != "nassau":
			return id
	return ""


## The last page of the log: how it ended, who sailed her, and what they did.
static func epitaph(s: Dictionary, id: String) -> Dictionary:
	var cap := ShipStats.captain(s)
	var title := ""
	var text := ""
	match id:
		"retire":
			title = "Captain %s retires" % cap.name
			text = "With %d gold to their name, Captain %s comes ashore for good. The %s is sold, the crew paid off, and the stories grow taller every year." % [fortune(s), cap.name, s.name]
		"governor":
			var town := _town(s)
			title = "Governor %s" % cap.name
			text = "%s hands %s to %s, and is sworn in as its governor. The pirate hunters who once chased the %s now salute its old captain." % [
				cap.name, Ports.port(town).name, Career.fname(patron(s)), s.name]
		"republic":
			title = "The Republic of the Brethren"
			text = "At Nassau, before the council and every crew in the harbour, %s declares a republic of free sailors. For a while, at least, the Brethren of the Coast answer to no Crown." % cap.name
		"hanged":
			title = "Captain %s is hanged" % cap.name
			text = "Captain %s goes to the gallows at low tide, as pirates do, and is left in chains for the ships to see." % cap.name
		"lost":
			title = "The %s is lost" % s.name
			text = "The %s went down with all hands. No one is left to tell how." % s.name
		_:
			title = "The end of the %s" % s.name
			text = "Captain %s %s, and there is no one left to take the helm." % [cap.name, s.get("succession", {}).get("cause", "is gone")]
	return {"title": title, "text": "%s\n\n%s" % [text, log_text(s)]}


## The ship's log as text: the line of captains, and the deeds of the one at the helm now.
static func log_text(s: Dictionary, deeds := 12) -> String:
	var cap := ShipStats.captain(s)
	var lines := PackedStringArray(["The captains of the %s:" % s.name])
	for c in s.get("captains", []):
		lines.append("  %s (until %s, %s)%s" % [c.name, c.until, c.fate, ", known as %s" % ", ".join(c.titles) if not c.get("titles", []).is_empty() else ""])
	var titles: Array = Ambitions.ensure(s).titles.map(func(a): return Data.table("ambitions")[a].title)
	lines.append("  %s (now)%s" % [cap.name, ", known as %s" % ", ".join(titles) if not titles.is_empty() else ""])
	var hist: Array = cap.history.slice(maxi(0, cap.history.size() - deeds))
	if not hist.is_empty():
		lines.append("\nFrom the log of Captain %s:" % cap.name)
		for h in hist:
			lines.append("  " + h)
	lines.append("\nGold %d. Notoriety %d, honour %+d, fear %+d. Towns taken: %d. Ships taken: %d." % [fortune(s), s.reputation.notoriety,
		s.reputation.honour, s.reputation.fear, int(s.get("tally", {}).get("towns_taken", 0)), int(s.get("tally", {}).get("ships_taken", 0))])
	return "\n".join(lines)


## Struck to a navy or a pirate hunter while wanted by them: the captain may hang. Returns the news, or "".
static func hanging(s: Dictionary, enemy: Dictionary, rng: RandomNumberGenerator) -> String:
	if not enemy.get("kind", "") in ["navy", "hunter", "guarda_costa"]:
		return ""
	var wanted: bool = Career.wanted(s) or s.get("bounty", {}).get(enemy.faction, 0.0) >= Data.rules.career.bounty.hunt_from
	if not wanted or rng.randf() >= cfg().hang_chance:
		return ""
	s.get("bounty", {}).erase(enemy.faction)  # they've had their money's worth
	Crew.captain_dies(s, "was carried off by the %s and hanged" % Data.table("factions")[enemy.faction].adjective)
	return "They know who you are. Captain %s is put in irons and taken away to be hanged." % ShipStats.captain(s).name
