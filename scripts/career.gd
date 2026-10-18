class_name Career
## Your legal standing at sea: honest captain, privateer under a letter of marque, or pirate.
## Works on ship state:  state.career = {pirate, marque, service, rank, crown_debt, pardoned_by}
## Every attack is judged: lawful prizes earn rank and owe the Crown its share; piracy earns notoriety,
## enemies in every nation and, once wanted, closed ports and hunters on your trail.


static func cfg() -> Dictionary:
	return Data.rules.career


static func fname(f: String) -> String:
	return Data.table("factions")[f].name


static func nations() -> Array:
	return Data.table("factions").keys().filter(func(f): return f != "pirates")


static func status_text(s: Dictionary) -> String:
	var c: Dictionary = s.career
	if c.pirate:
		return "Pirate" + (", wanted in every lawful port" if wanted(s) else "")
	if c.marque != "":
		return "%s of %s" % [rank_name(s), fname(c.marque)]
	return "Honest captain" + (" (pardoned)" if not c.pardoned_by.is_empty() else "")


static func wanted(s: Dictionary) -> bool:
	return s.career.pirate and s.reputation.notoriety >= cfg().notoriety_wanted


# ---- the price on your head ------------------------------------------------------------
## Each nation you've wronged puts up gold for you: piracy against them raises it, a sack raises it a lot,
## their pardon clears it, and it fades slowly. Pirate hunters come for it, in bigger ships as it grows.

static func add_bounty(s: Dictionary, f: String, gold: float) -> void:
	if f == "" or f == "pirates" or gold <= 0.0:
		return
	if not s.has("bounty"):
		s.bounty = {}
	s.bounty[f] = s.bounty.get(f, 0.0) + gold


static func bounty_total(s: Dictionary) -> float:
	return s.get("bounty", {}).values().reduce(func(a, x): return a + x, 0.0)


## The nation that wants you most, or "".
static func bounty_by(s: Dictionary) -> String:
	var best := ""
	for f in s.get("bounty", {}):
		if best == "" or s.bounty[f] > s.bounty[best]:
			best = f
	return best


static func hunted(s: Dictionary) -> bool:
	return bounty_total(s) >= cfg().bounty.hunt_from


## The ship a hunter brings: the bigger the price, the bigger the ship.
static func hunter_ship(s: Dictionary) -> String:
	var type := ""
	for tier in cfg().bounty.ships:
		if bounty_total(s) >= tier[0]:
			type = tier[1]
	return type


static func bounty_text(s: Dictionary) -> String:
	if bounty_total(s) < 1.0:
		return "No price on your head."
	var parts: Array = s.bounty.keys().filter(func(f): return s.bounty[f] >= 1.0).map(func(f): return "%s %d" % [fname(f), s.bounty[f]])
	return "A price of %d gold on your head (%s).%s" % [bounty_total(s), ", ".join(parts),
		" Pirate hunters are out for it." if hunted(s) else ""]


static func bounty_daily(s: Dictionary) -> void:
	for f in s.get("bounty", {}).keys():
		s.bounty[f] *= 1.0 - float(cfg().bounty.decay_per_day)
		if s.bounty[f] < 1.0:
			s.bounty.erase(f)


static func rank_name(s: Dictionary) -> String:
	return cfg().ranks[s.career.rank].name


## Your true colours: the nation you were born to ("" for none).
static func home_faction(s: Dictionary) -> String:
	return Data.table("nations")[People.person(s.captain).nationality].faction


## The nation a flag claims ("pirates" for the black or red flag, "" for plain white).
static func flag_faction(flag: String) -> String:
	if flag == "black" or flag == "red":
		return "pirates"
	for f in nations():
		if Data.table("factions")[f].flag == flag:
			return f
	return ""


static func false_colours(s: Dictionary) -> bool:
	var f := flag_faction(s.get("flag", "white"))
	return f != "" and f != "pirates" and f != home_faction(s)


## Is attacking a ship of `target` lawful? {legal, why}
static func judge_attack(s: Dictionary, target: String) -> Dictionary:
	if target == "pirates":
		return {"legal": true, "why": "Pirates are the enemies of all mankind: lawful prey for anyone."}
	var m: String = s.career.marque
	if m != "" and Factions.at_war(m, target):
		return {"legal": true, "why": "A lawful prize under your %s letter of marque." % Data.table("factions")[m].adjective}
	if m != "":
		return {"legal": false, "why": "%s is not at war with %s. Attacking her is piracy, and an abuse of your commission." % [fname(m), fname(target)]}
	return {"legal": false, "why": "You hold no commission against %s. Attacking her is piracy." % fname(target)}


## The consequences of opening fire on someone who wasn't attacking you. Returns messages.
static func on_attack(s: Dictionary, enemy: Dictionary) -> Array:
	var verdict := judge_attack(s, enemy.faction)
	enemy.legal = verdict.legal
	var hit := int(Data.table("encounters")[enemy.kind].relation_hit)
	var c := cfg()
	var msgs := [verdict.why]
	if enemy.faction == "pirates":
		for f in nations():
			s.relations[f] += int(c.pirate_hunting_bonus)
		s.relations.pirates -= hit
		return msgs
	s.relations[enemy.faction] -= hit
	if verdict.legal:
		s.relations[s.career.marque] += int(c.lawful_raid_issuer_bonus)
		Factions.incident(s.career.marque, enemy.faction, Data.rules.diplomacy.incident.marque_raid)  # their privateer, our ships
		return msgs
	for f in nations():
		if f != enemy.faction:
			s.relations[f] -= int(c.piracy_all_nations)
	if s.career.marque != "":
		s.relations[s.career.marque] -= int(c.marque_abuse)
		msgs.append(revoke(s, "for piracy"))
	if not s.career.pirate:
		msgs.append("There's no going back: every navy now counts you a pirate.")
	s.career.pirate = true
	s.reputation.notoriety += int(c.notoriety_piracy) + int(Data.table("encounters")[enemy.kind].notoriety)
	add_bounty(s, enemy.faction, c.bounty.per_attack + c.bounty.per_notoriety * Data.table("encounters")[enemy.kind].notoriety)
	s.relations.pirates += int(c.pirate_relation_gain)
	return msgs


static func crown_cut(s: Dictionary) -> float:
	if s.career.marque == "":
		return 0.0
	return maxf(0.0, cfg().crown_cut - s.career.rank * cfg().crown_cut_per_rank)


## A lawful prize taken under a commission: the Crown is owed its share, and your service counts toward rank.
static func record_prize(s: Dictionary, value: float) -> Array:
	var c: Dictionary = s.career
	if c.marque == "" or value <= 0.0:
		return []
	var share := value * crown_cut(s)
	c.crown_debt += share
	c.service += value
	var msgs := ["The Crown's share of this prize: %d gold (pay it at any %s port)." % [share, Data.table("factions")[c.marque].adjective]]
	var ranks: Array = cfg().ranks
	while c.rank + 1 < ranks.size() and c.service >= ranks[c.rank + 1].service:
		c.rank += 1
		s.relations[c.marque] += int(cfg().rank_standing_bonus)
		msgs.append("For your service, %s makes you %s." % [fname(c.marque), ranks[c.rank].name])
	return msgs


static func pay_crown(s: Dictionary) -> String:
	var paid := minf(s.gold, s.career.crown_debt)
	s.gold -= paid
	s.career.crown_debt -= paid
	s.relations[s.career.marque] += 1
	return "Paid %d to the Admiralty." % paid


## Why this nation won't commission you, or "".
static func marque_problem(s: Dictionary, f: String) -> String:
	var c: Dictionary = s.career
	if f == "pirates":
		return "The Brethren don't issue commissions."
	if c.marque == f:
		return "You already hold a %s commission." % Data.table("factions")[f].adjective
	if c.marque != "":
		return "You already sail under a %s commission." % Data.table("factions")[c.marque].adjective
	if c.pirate:
		return "No governor commissions a known pirate. Seek a pardon first."
	if s.relations.get(f, 0) < cfg().marque_min_standing:
		return "Your standing with %s is too low (needs %+d, you have %+d)." % [fname(f), cfg().marque_min_standing, s.relations.get(f, 0)]
	if Factions.enemies_of(f).is_empty():
		return "%s is at peace with every nation: there is no one to commission you against." % fname(f)
	return ""


static func grant_marque(s: Dictionary, f: String) -> String:
	s.career.marque = f
	s.career.rank = 0
	s.career.service = 0.0
	ShipStats.captain(s).history.append("Took a %s letter of marque, %s." % [Data.table("factions")[f].adjective, Clock.date_string()])
	return "You hold a %s letter of marque against %s." % [Data.table("factions")[f].adjective,
		", ".join(Factions.enemies_of(f).map(func(e): return fname(e)))]


static func revoke(s: Dictionary, reason: String) -> String:
	var f: String = s.career.marque
	if f == "":
		return ""
	s.career.marque = ""
	s.career.rank = 0
	ShipStats.captain(s).history.append("Lost the %s commission %s, %s." % [Data.table("factions")[f].adjective, reason, Clock.date_string()])
	return "Your %s letter of marque is revoked %s." % [Data.table("factions")[f].adjective, reason]


## Peace voids letters of marque. Returns a message if yours just went.
static func check_peace(s: Dictionary) -> String:
	var f: String = s.career.marque
	if f != "" and Factions.enemies_of(f).is_empty():
		return revoke(s, "now that %s is at peace. Raid on and you're a pirate" % fname(f))
	return ""


static func pardon_cost(s: Dictionary, f: String, port_id := "") -> int:
	if f in Factions.pardons or Bonds.level(s, "f:" + f) >= 4:  # a patron nation forgives for nothing
		return 0
	var cost: float = Data.rules.pardon.base_cost + s.reputation.notoriety * Data.rules.pardon.per_notoriety
	if port_id != "":  # where the church holds sway, repentance comes cheaper
		cost *= clampf(1.0 - Ports.state[port_id].laws.get("pardon", 0.0) * 0.5, 0.5, 1.5)
	return int(cost)


static func pardon_problem(s: Dictionary, f: String, port_id := "") -> String:
	if not s.career.pirate:
		return "You've nothing to be pardoned for."
	if f == "pirates":
		return "The Brethren have no pardons to give."
	if s.relations.get(f, 0) < Data.rules.pardon.min_standing:
		return "%s would sooner hang you." % fname(f)
	if s.gold < pardon_cost(s, f, port_id):
		return "The pardon costs %d gold." % pardon_cost(s, f, port_id)
	return ""


## Old crew may resent it, and old enemies remember: only the pardoning nation forgives.
static func pardon(s: Dictionary, f: String, free := false, port_id := "") -> Array:
	var p: Dictionary = Data.rules.pardon
	var cost := 0 if free else pardon_cost(s, f, port_id)
	s.gold -= cost
	s.career.pirate = false
	s.career.pardoned_by.append(f)
	s.get("bounty", {}).erase(f)
	s.reputation.notoriety = int(s.reputation.notoriety * p.notoriety_mult)
	s.relations[f] = maxi(s.relations[f], 0)
	s.relations.pirates -= int(p.pirate_relation_hit)
	var resent := 0
	for id in s.crew:
		var c := People.person(id)
		var tags := []
		for t in c.traits:
			tags.append_array(Data.table("traits")[t].get("tags", []))
		if tags.any(func(t): return t in p.resent_tags):
			c.relations[s.captain] = c.relations.get(s.captain, 0) - 5
			resent += 1
	ShipStats.captain(s).history.append("Pardoned by %s, %s." % [fname(f), Clock.date_string()])
	Ambitions.tally(s, "pardons")
	var msgs := ["%s pardons you%s. Other nations' grudges remain." % [fname(f), "" if cost == 0 else " for %d gold" % cost]]
	if resent > 0:
		msgs.append("%d of your crew call it a betrayal of the Brethren." % resent)
	return msgs


## Can you come into this port? {open, reason, detect (false-flag risk), bribe}
static func port_access(s: Dictionary, port_id: String) -> Dictionary:
	var p := Ports.port(port_id)
	var f: String = p.faction
	var rel: int = s.relations.get(f, 0)
	var pa: Dictionary = Data.rules.port_access
	var reason := ""
	var tolerant: bool = Ports.state[port_id].laws.get("pirates", 0.0) > 0.4  # the townsfolk rule here, and pirates spend money
	if Bases.bases.has(port_id):
		reason = ""  # your own town
	elif EconomyEffects.active(s, "closed_ports", port_id) != null:
		reason = "The harbour is closed to you after what happened."
	elif s.get("blind_eye", {}).get(port_id, 0.0) > Clock.day or Bonds.port_open(s, port_id):
		reason = ""  # the harbour master owes you
	elif f == "pirates":
		if rel <= pa.closed:
			reason = "The Brethren remember the pirates you've hanged."
	elif wanted(s) and not p.get("fence", false) and not tolerant:
		reason = "Your name is posted on every quay. The governor will hang you on sight."
	elif rel <= pa.closed:
		reason = "%s has closed its ports to you." % fname(f)
	var detect := clampf(pa.detect_base + s.reputation.notoriety * pa.detect_per_notoriety
		+ Ports.state[port_id].laws.vigilance * pa.detect_per_vigilance, 0.05, 0.9)
	var harsh: float = 1.0 - minf(0.0, Ports.state[port_id].laws.get("pirates", 0.0))  # a hanging town's harbour master costs more
	return {"open": reason == "", "reason": reason, "detect": detect,
		"bribe": int((pa.bribe_base + s.reputation.notoriety * pa.bribe_per_notoriety) * harsh)}


## Can these colours get you past this port's fort? A flag of a nation not at war with the port.
static func flag_fools_port(s: Dictionary, port_id: String) -> bool:
	var f := flag_faction(s.get("flag", "white"))
	return f != "" and f != "pirates" and not Factions.at_war(f, Ports.port(port_id).faction)


## Goods Spain forbids foreigners to bring (the union of its ports' contraband) in your hold?
static func carries_spanish_contraband(s: Dictionary) -> bool:
	for id in Data.table("ports"):
		var p: Dictionary = Data.table("ports")[id]
		if p.faction == "spain" and p.laws.contraband.any(func(g): return s.cargo.get(g, 0.0) >= 1.0):
			return true
	return false


## Friendly ports trade a little better; hostile ones gouge you.
static func price_mult(s: Dictionary, port_id: String) -> float:
	var pa: Dictionary = Data.rules.port_access
	var rel: int = s.relations.get(Ports.port(port_id).faction, 0)
	return clampf(1.0 - rel * pa.price_per_standing, pa.price_clamp[0], pa.price_clamp[1]) * Bonds.price_mult(s, port_id)  # the tariff is a duty now (Economy.duty)


## Will this ship attack you on sight? Navies judge you by your record and by the colours you fly.
static func npc_hostile(s: Dictionary, enemy: Dictionary, rng: RandomNumberGenerator) -> bool:
	var bond = Bonds.hostile_override(s, enemy)  # allies hold fire; sworn rivals never do
	if bond != null:
		return bond
	var shown := flag_faction(s.get("flag", "white"))
	match enemy.behaviour:
		"aggressive":  # a captain with no friends anywhere looks like easy prey
			var easy: int = Data.table("bonds").neutral_easy_target if Bonds.neutral(s) else 0
			return s.relations.get("pirates", 0) < Data.rules.encounters.friendly_pirate_relation + easy
		"warship":
			if enemy.kind == "hunter" and (wanted(s) or s.get("bounty", {}).get(enemy.faction, 0.0) >= cfg().bounty.hunt_from):
				return true
			if enemy.kind == "guarda_costa" and shown != "spain" and (carries_spanish_contraband(s) or rng.randf() < cfg().guarda_search):
				return true  # they stop and search every foreign hull in Spanish waters
			if EconomyEffects.active(s, "hostile", enemy.faction) != null:
				return true  # they've been fitted out against you
			if enemy.faction == "spain" and shown != "spain" and carries_spanish_contraband(s):
				return true  # a guarda costa: every foreign hull with forbidden goods aboard is a prize
			if s.get("patrol_warning", {}).get(enemy.faction, 0.0) > Clock.day:
				return false  # you know where they'll be, and keep out of their way
			if shown == "pirates" or Factions.at_war(shown, enemy.faction):
				return true
			if s.relations.get(enemy.faction, 0) < Data.rules.encounters.hostile_relation:
				return true
			if wanted(s):  # a wanted pirate might pass under false colours, or might be recognised
				return not false_colours(s) or rng.randf() < port_access_detect(s)
	return false


static func port_access_detect(s: Dictionary) -> float:
	var pa: Dictionary = Data.rules.port_access
	return clampf(pa.detect_base + s.reputation.notoriety * pa.detect_per_notoriety, 0.05, 0.9)
