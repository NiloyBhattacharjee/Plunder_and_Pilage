class_name Civics
## Standing choices with a price, Paradox style (data/civics.json): the ship's articles (discipline, quarter,
## the maimed) and a held town's laws (rule, harbour). One option per slot, kept as civics: {slot: option id} on
## the ship state or the base, and civics_since: {slot: day} for when each last changed. A slot never set holds
## its default, which does nothing. Code asks bonus(holder, key) where a number is made, parts() to explain it.

const EFFECTS := {"morale": "Crew morale %+d", "unrest": "Unrest spreads %+d%%", "desertion": "Desertion in port %+d%%",
	"wages": "Wages %+d%%", "enemy_morale": "Enemy morale %+d as a battle starts", "merchant_morale": "A merchant's morale %+d as a battle starts",
	"honour_per_battle": "Honour %+d every battle", "fear_per_battle": "Fear %+d every battle", "loyalty": "Loyalty %+d",
	"order": "Order in the streets %+d", "tax": "Taxes %+d%%", "rebels": "Rebels in a rising %+d%%"}
const PERCENT := ["unrest", "desertion", "wages", "tax", "rebels"]


static func table() -> Dictionary:
	return Data.table("civics")


static func cfg() -> Dictionary:
	return table()._rules


## The slots of a ship ("ship") or of a town you hold ("town").
static func slots(where: String) -> Array:
	return table()._slots.keys().filter(func(k): return table()._slots[k].where == where)


static func options(slot: String) -> Array:
	return table().keys().filter(func(k): return not k.begins_with("_") and table()[k].slot == slot)


static func chosen(holder: Dictionary, slot: String) -> String:
	return holder.get("civics", {}).get(slot, table()._slots[slot].default)


## Every option in force that touches `key`: [[name, value]].
static func parts(holder: Dictionary, key: String) -> Array:
	var out := []
	for slot in table()._slots:
		var o: Dictionary = table()[chosen(holder, slot)]
		if o.get("bonus", {}).has(key):
			out.append([o.name, float(o.bonus[key])])
	return out


static func bonus(holder: Dictionary, key: String) -> float:
	return parts(holder, key).reduce(func(a, p): return a + p[1], 0.0)


## Why this can't be put in force now, or "".
static func problem(holder: Dictionary, id: String) -> String:
	var slot: String = table()[id].slot
	if chosen(holder, slot) == id:
		return "In force now."
	var wait: float = float(holder.get("civics_since", {}).get(slot, -1.0e9)) + float(cfg().change_days) - Clock.day
	if wait > 0.0:
		return "Changed lately: it can change again in %d days." % ceili(wait)
	return ""


## What an option is and does, for a tooltip.
static func describe(id: String) -> String:
	var o: Dictionary = table()[id]
	var lines := PackedStringArray([o.description])
	for k in o.get("bonus", {}):
		var v: float = float(o.bonus[k])
		lines.append(EFFECTS[k] % int(round(v * 100.0 if k in PERCENT else v)))
	for f in o.get("relations", {}):
		lines.append("Standing with %s %+d" % [Career.fname(f), int(o.relations[f])])
	return "\n".join(lines)


## Puts an option in force. s: the ship state (a pirate crew votes on new articles; any standing change is yours).
## town: the port id when the holder is a town you hold. Returns what happened.
static func adopt(s: Dictionary, stats: Dictionary, holder: Dictionary, id: String, rng: RandomNumberGenerator, town := "") -> String:
	var o: Dictionary = table()[id]
	var old: Dictionary = table()[chosen(holder, o.slot)]
	if not holder.has("civics_since"):
		holder.civics_since = {}
	holder.civics_since[o.slot] = Clock.day  # a vote lost counts too: no asking again every morning
	var text := ""
	if town == "":
		var benefit: float = float(o.get("benefit", 0.0)) - float(old.get("benefit", 0.0))
		if s.career.pirate:
			var v := Crew.vote(s, stats, clampf(benefit, -1.0, 1.0), rng)
			if not v.passed:
				Crew.add_mod(s, "vote_lost", "Outvoted on the articles", -5, 30)
				return "The crew vote down %s, %d to %d." % [o.name.to_lower(), v.no, v.yes]
			text = "The crew vote for %s, %d to %d." % [o.name.to_lower(), v.yes, v.no]
		else:
			if benefit < 0.0:
				Crew.add_mod(s, "articles_imposed", "Articles imposed: " + o.name.to_lower(), float(cfg().imposed_morale), float(cfg().imposed_days))
			text = "The articles read %s now." % o.name.to_lower()
	else:
		text = "%s: %s." % [holder.name, o.name.to_lower()]
	if not holder.has("civics"):
		holder.civics = {}
	holder.civics[o.slot] = id
	if town != "":
		for slot in slots("town"):
			Ports.state[town].laws.merge(table()[chosen(holder, slot)].get("laws", {}), true)
	for f in o.get("relations", {}):
		s.relations[f] = s.relations.get(f, 0) + int(o.relations[f])
	return text
