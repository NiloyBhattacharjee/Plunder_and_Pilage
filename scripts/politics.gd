extends Node
## Autoload "Politics": the people who run each port, the interest groups behind them, secrets, favours,
## and the pirate council of Nassau. Built from existing systems: officials are ordinary characters (People),
## political jobs are contracts, political twists are events. Tables in data/politics.json.
## Favours are kept on the official, keyed by captain (like their opinion of you), so a new captain starts afresh.

signal news(text: String)

var officials := {}   # port id -> {role: character id}
var influence := {}   # port id -> {group: 0..100, summing to 100}
var council: Array = []      # Nassau's council of captains (character ids)
var council_leader := ""     # a council member's id, or "player"
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	Clock.day_passed.connect(func(_d):
		if Clock.date().day == 1:
			monthly())


func reset() -> void:
	officials = {}
	influence = {}
	council = []
	council_leader = ""
	for id in Ports.state:
		apply_laws(id, true)


static func cfg() -> Dictionary:
	return Data.table("politics")


# ---- officials -----------------------------------------------------------------

## The offices a port has: a small colony has fewer; a pirate haven has only its broker (and its council).
static func offices(port_id: String) -> Array:
	var p := Ports.port(port_id)
	var o: Dictionary = cfg().offices
	var list: Array = (o.pirates if p.faction == "pirates" else (o.small if p.size == "small" else o.default)).duplicate()
	if Bases.is_town(port_id):  # yours: your manager governs, and only the broker keeps their trade
		list = []
	if p.has("broker") and not "broker" in list:
		list.append("broker")
	return list


## Whoever holds this office now, met for the first time when you ask. "" if the port has no such office.
func official(port_id: String, role: String) -> String:
	if Bases.is_town(port_id) and role == "governor":
		return Bases.bases[port_id].manager
	if not role in offices(port_id):
		return ""
	if not officials.has(port_id):
		officials[port_id] = {}
	if not officials[port_id].has(role) or not People.chars.has(officials[port_id][role]):
		officials[port_id][role] = _appoint(port_id, role, true)
	return officials[port_id][role]


## Everyone in office here, in office order.
func officials_at(port_id: String) -> Array:
	return offices(port_id).map(func(r): return official(port_id, r))


func _appoint(port_id: String, role: String, first: bool) -> String:
	var p := Ports.port(port_id)
	var c := People.generate({"mix": Data.rules.people.recruit_mix[p.faction], "pool": "official"})
	if first and role == "governor":
		c.name = p.governor
	elif first and role == "broker":
		c.name = p.broker
	c.age = maxi(c.age, 30)
	c.role = role
	c.port = port_id
	c.goal = _goal(c)
	c.favours = {}
	c.history.append("%s of %s, %s." % [cfg().roles[role].name, p.name, Clock.date_string()])
	var id := People.add(c)
	for other in officials.get(port_id, {}).values():  # colleagues, and old rivalries
		if People.chars.has(other):
			var feeling := rng.randi_range(-45, 35)
			c.relations[other] = feeling
			People.person(other).relations[id] = feeling + rng.randi_range(-10, 10)
	return id


func _goal(c: Dictionary) -> String:
	for g in cfg().goals:
		if c.get("role", "") == "broker" and g in ["crush_piracy", "protect_trade"]:
			continue  # a fence doesn't want an end to piracy, whatever else they believe
		if c.traits.any(func(t): return t in cfg().goals[g].traits):
			return g
	return "get_rich" if c.get("role", "") == "broker" else "keep_order"


## A new face in office. why: "died of fever", "was promoted home", "was recalled in disgrace".
func replace(port_id: String, role: String, why: String) -> String:
	var old_id: String = officials.get(port_id, {}).get(role, "")
	var text := ""
	if old_id != "" and People.chars.has(old_id):
		var old := People.person(old_id)
		old.history.append("%s, %s." % [why.capitalize(), Clock.date_string()])
		old.port = ""  # gone from office, but still remembered: contracts and favours keep pointing at them
		old.role = "former_" + role
		text = "%s, %s of %s, %s." % [old.name, cfg().roles[role].name.to_lower(), Ports.port(port_id).name, why]
	officials[port_id][role] = _appoint(port_id, role, false)
	Contracts.offers.erase(port_id)
	text += " %s takes office." % People.person(officials[port_id][role]).name
	news.emit(text.strip_edges())
	return text.strip_edges()


# ---- interest groups and laws ----------------------------------------------------

func power(port_id: String) -> Dictionary:
	if not influence.has(port_id):
		var base: Dictionary = cfg().influence[Ports.port(port_id).faction]
		var p := {}
		for g in base:
			p[g] = maxf(0.0, base[g] + rng.randf_range(-5.0, 5.0) if base[g] > 0 else 0.0)
		influence[port_id] = p
		_normalise(port_id)
	return influence[port_id]


## Working for one group raises it, and everyone else loses a little.
func shift(port_id: String, group: String, amount: float) -> void:
	power(port_id)[group] = maxf(0.0, power(port_id)[group] + amount)
	_normalise(port_id)
	apply_laws(port_id)


func _normalise(port_id: String) -> void:
	var p: Dictionary = influence[port_id]
	var total := 0.0
	for g in p:
		total += p[g]
	for g in p:
		p[g] = p[g] * 100.0 / maxf(1.0, total)


func dominant(port_id: String) -> String:
	var p := power(port_id)
	var best := ""
	for g in p:
		if best == "" or p[g] > p[best]:
			best = g
	return best


## What the groups want, weighted by their influence: {law: {value, parts: [[group, contribution]]}}.
func target_laws(port_id: String) -> Dictionary:
	var out := {}
	var p := power(port_id)
	for law in ["vigilance", "tariff", "pirates", "pardon"]:
		var total := 0.0
		var parts := []
		for g in p:
			var v: float = cfg().groups[g].laws[law] * p[g] / 100.0
			total += v
			parts.append([cfg().groups[g].name, v])
		out[law] = {"value": total, "parts": parts}
	return out


## The live laws follow the powerful: tariff, pirate policy and pardons at once, customs vigilance gradually
## (so a seizure still keeps the customs house alert for a while). A town you hold keeps your laws.
func apply_laws(port_id: String, at_once := false) -> void:
	if Bases.is_town(port_id):
		return
	var t := target_laws(port_id)
	var laws: Dictionary = Ports.state[port_id].laws
	var base: float = Ports.port(port_id).laws.vigilance
	var want: float = (base + t.vigilance.value) / 2.0
	laws.vigilance = want if at_once else lerpf(laws.vigilance, want, 0.3)
	laws.tariff = t.tariff.value
	laws.pirates = t.pirates.value
	laws.pardon = t.pardon.value


func law_text(port_id: String) -> String:
	var laws: Dictionary = Ports.state[port_id].laws
	var pir: float = laws.get("pirates", 0.0)
	return "%s hold sway. Customs %d%%, tariff %+d%%, pirates %s." % [cfg().groups[dominant(port_id)].name, int(laws.vigilance * 100),
		int(laws.get("tariff", 0.0) * 100), "welcome" if pir > 0.4 else ("tolerated" if pir > -0.2 else ("hunted" if pir > -0.6 else "hanged"))]


# ---- the monthly round -------------------------------------------------------------

## Influence drifts back toward the colony's nature, officials push for their goals, and offices change hands.
func monthly() -> void:
	var c := cfg()
	for port_id in Ports.state:
		if Bases.is_town(port_id):
			continue
		var base: Dictionary = c.influence[Ports.port(port_id).faction]
		var p := power(port_id)
		for g in p:
			p[g] = lerpf(p[g], base[g], c.drift)
		for id in officials.get(port_id, {}).values():
			var goal: String = People.person(id).get("goal", "keep_order")
			var g: String = c.goals[goal].group if c.goals[goal].group != "" else c.roles[People.person(id).role].group
			if g != "":
				p[g] += c.goal_push
		_normalise(port_id)
		apply_laws(port_id)
		for role in officials.get(port_id, {}).keys():
			var o := People.person(officials[port_id][role])
			var death: float = c.official_death_chance * (c.summer_death_mult if Clock.date().month in [6, 7, 8, 9, 10] else 1.0)
			if rng.randf() < death:
				replace(port_id, role, "died of fever")
			elif o.goal == "promotion" and People.value(o, "authority") >= 11 and rng.randf() < c.promotion_chance:
				replace(port_id, role, "was promoted home")


# ---- favours ------------------------------------------------------------------------

## Favours this official owes your captain (negative: you owe them).
static func favours(off_id: String, s: Dictionary) -> int:
	return People.person(off_id).get("favours", {}).get(s.captain, 0)


static func add_favours(off_id: String, s: Dictionary, n: int) -> void:
	var c := People.person(off_id)
	if not c.has("favours"):
		c.favours = {}
	c.favours[s.captain] = c.favours.get(s.captain, 0) + n


## Why you can't have this favour from them, or "". asking: they'd do it on credit (you'll owe them).
static func favour_problem(off_id: String, s: Dictionary, kind: String, asking: bool) -> String:
	var f: Dictionary = cfg().favours[kind]
	var c := People.person(off_id)
	if f.get("needs", "") == "pirate" and not s.career.pirate:
		return "You've nothing to be pardoned for."
	if not asking and favours(off_id, s) < f.cost:
		return "%s owes you %d favour%s; this takes %d." % [c.name, maxi(0, favours(off_id, s)), "" if favours(off_id, s) == 1 else "s", f.cost]
	if asking and c.relations.get(s.captain, 0) < 0:
		return "%s doesn't like you enough to do you favours." % c.name
	if asking and favours(off_id, s) - f.cost < -2:
		return "You already owe %s too much." % c.name
	return ""


## Calls in (or asks for) a favour. Returns what happened.
func use_favour(off_id: String, s: Dictionary, kind: String, ctx: Dictionary, asking := false) -> String:
	var why := favour_problem(off_id, s, kind, asking)
	if why != "":
		return why
	var f: Dictionary = cfg().favours[kind]
	var c := People.person(off_id)
	var port_id: String = c.port
	add_favours(off_id, s, -int(f.cost))
	var done := PackedStringArray()
	match kind:
		"pardon":
			done.append_array(Career.pardon(s, Ports.port(port_id).faction, true))
		"blind_eye":
			s.blind_eye = s.get("blind_eye", {})
			s.blind_eye[port_id] = Clock.day + 60
			done.append("%s's harbour is open to you for two months, whatever happens." % Ports.port(port_id).name)
		"patrol_warning":
			s.patrol_warning = s.get("patrol_warning", {})
			s.patrol_warning[Ports.port(port_id).faction] = Clock.day + 30
			done.append("For a month you'll know where the %s patrols are." % Data.table("factions")[Ports.port(port_id).faction].adjective)
		"market_tip":
			for id in Ports.state:
				Ports.record_prices(id, int(Clock.day))
			done.append("You know every port's prices as of today.")
	for o in f.get("outcomes", []):
		var line := Events.apply_outcome(o, ctx)
		if line != "":
			done.append(line)
	var owe := " You owe %s a favour now; they'll call it in." % c.name if asking else ""
	return "%s: %s.%s" % [f.name, " ".join(done).trim_suffix("."), owe]


## Whose favour is owed: officials you owe, anywhere ([id]).
static func creditors(s: Dictionary) -> Array:
	return People.chars.keys().filter(func(id): return People.person(id).get("favours", {}).get(s.captain, 0) < 0)


## Officials who hate you enough to act on it.
func enemies(s: Dictionary) -> Array:
	var out := []
	for port_id in officials:
		for id in officials[port_id].values():
			if People.chars.has(id) and People.person(id).relations.get(s.captain, 0) <= cfg().grudge:
				out.append(id)
	for id in council:
		if People.chars.has(id) and People.person(id).relations.get(s.captain, 0) <= cfg().grudge:
			out.append(id)
	for id in Bonds.rivals(s, 2):  # a feuding rival schemes like any enemy in office
		if not id.begins_with("f:") and not id in out:
			out.append(id)
	return out


# ---- secrets ------------------------------------------------------------------------

## A secret about someone. about "" picks an official somewhere who fits the kind. Returns a message.
func gain_secret(s: Dictionary, kind: String, about := "", fake := false, port_id := "") -> String:
	var k: Dictionary = cfg().secrets[kind]
	if about == "":
		var ports := [port_id] if port_id != "" else Ports.state.keys().filter(func(id): return Ports.port(id).faction != "pirates")
		var pairs := []
		for p in ports:
			for role in k.about:
				if role in offices(p):
					pairs.append([p, role])
		if pairs.is_empty():
			return ""
		var pick: Array = pairs[rng.randi() % pairs.size()]
		about = official(pick[0], pick[1])
	var c := People.person(about)
	var doubt := false
	if fake:  # a sharp eye can spot a forgery
		doubt = Dice.check(rng, "Spot a forgery", [["Experience", Dice.mod(People.value(ShipStats.captain(s), "experience"))]], int(cfg().forgery_spot_dc)).success
	s.secrets = s.get("secrets", [])
	var sec := {"id": "x%d_%d" % [int(Clock.day), rng.randi() % 100000], "kind": kind, "about": about, "port": c.port,
		"fake": fake, "doubt": doubt, "leverage": false,
		"expires": Clock.day + k.expires_days if k.has("expires_days") else -1.0}
	s.secrets.append(sec)
	return "You hold a secret: %s%s" % [describe(sec), " (though something about it smells forged)" if doubt else "."]


static func describe(sec: Dictionary) -> String:
	var c := People.person(sec.about)
	var role: String = c.role.trim_prefix("former_")
	return cfg().secrets[sec.kind].text.format({"name": c.name, "role": cfg().roles[role].name.to_lower() if cfg().roles.has(role) else "official"})


static func value(sec: Dictionary) -> int:
	return int(cfg().secrets[sec.kind].power * cfg().secret_value)


## Stale secrets lose their worth.
static func prune_secrets(s: Dictionary) -> void:
	s.secrets = s.get("secrets", []).filter(func(x): return (x.expires < 0 or x.expires > Clock.day) and People.chars.has(x.about))


## Who here would pay to ruin them: the official who likes them least.
func rival_of(sec: Dictionary) -> String:
	var c := People.person(sec.about)
	var best := ""
	if c.port == "":
		return ""
	for id in officials_at(c.port):
		if id != sec.about and People.chars.has(id) and (best == "" or People.person(id).relations.get(sec.about, 0) < People.person(best).relations.get(sec.about, 0)):
			best = id
	return best


## Blackmail: favours now and every month after, and an enemy who'd like you gone.
func blackmail(s: Dictionary, sec: Dictionary) -> String:
	var c := People.person(sec.about)
	if sec.fake:
		s.secrets.erase(sec)
		c.relations[s.captain] = c.relations.get(s.captain, 0) - 40
		return "%s laughs in your face: the letters are forgeries. You've made an enemy for nothing." % c.name
	sec.leverage = true
	add_favours(sec.about, s, int(cfg().blackmail_favours))
	c.relations[s.captain] = c.relations.get(s.captain, 0) + int(cfg().blackmail_grudge)
	return "%s goes white, and agrees to everything. They owe you %d favours, and will owe you more each month you keep quiet. They'll also be looking for a way to be rid of you." % [c.name, cfg().blackmail_favours]


## Sell it to their rival: money and a favour, unless they find out who sold it.
func sell(s: Dictionary, sec: Dictionary) -> String:
	var buyer_id := rival_of(sec)
	if buyer_id == "":
		return "Nobody here would pay for it."
	var buyer := People.person(buyer_id)
	var c := People.person(sec.about)
	var pay := value(sec)
	s.secrets.erase(sec)
	s.gold += pay
	if sec.fake:
		buyer.relations[s.captain] = buyer.relations.get(s.captain, 0) - 30
		return "%s pays %d, and soon learns the papers were forged. You've made an enemy." % [buyer.name, pay]
	add_favours(buyer_id, s, 1)
	var text := "%s pays %d and owes you a favour. %s will never know where it came from" % [buyer.name, pay, c.name]
	if rng.randf() < cfg().sell_discovered:
		c.relations[s.captain] = c.relations.get(s.captain, 0) + int(cfg().sell_grudge)
		text = "%s pays %d and owes you a favour. But %s finds out who sold them, and won't forget it" % [buyer.name, pay, c.name]
	if c.port != "" and cfg().roles.has(c.role) and cfg().roles[c.role].group != "":
		shift(c.port, cfg().roles[c.role].group, -3)  # a scandal weakens their side
	return text + "."


## Hand it to the Crown: a scandal, a recall, and the nation's thanks.
func expose(s: Dictionary, sec: Dictionary) -> String:
	var c := People.person(sec.about)
	var f: String = Ports.port(sec.port).faction if sec.port != "" else "pirates"
	s.secrets.erase(sec)
	if sec.fake:
		s.relations[f] = s.relations.get(f, 0) - 10
		return "The Crown's investigators find the papers forged. Your name is mud with %s (standing -10)." % Data.table("factions")[f].name
	var gain: int = cfg().secrets[sec.kind].power * int(cfg().expose_standing)
	s.relations[f] = s.relations.get(f, 0) + gain
	s.reputation.honour += 1
	var text := "The Crown takes note. Standing with %s +%d." % [Data.table("factions")[f].name, gain]
	if c.port != "" and cfg().roles.has(c.role):
		var group: String = cfg().roles[c.role].group
		if group != "":
			shift(c.port, group, -6)
		text = "Scandal! %s %s" % [replace(c.port, c.role, "was recalled in disgrace"), text]
	return text


## Act on a sailing schedule: the ship is waiting to be caught.
func act_on_schedule(s: Dictionary, sec: Dictionary) -> String:
	s.secrets.erase(sec)
	var f: String = Ports.port(sec.port).faction if sec.port != "" else "spain"
	Events.queue.append({"id": "schedule_prize", "at": Clock.day + 3.0, "until": Clock.day + 30.0, "vars": {"nation": f, "owner": sec.about}})
	return "You'll be waiting on her course in a few days." if not sec.fake else "You'll be waiting on her course in a few days. If the schedule is true."


## Each month, every secret held over someone's head pays another favour, and deepens the hatred.
func leverage_month(s: Dictionary) -> void:
	for sec in s.get("secrets", []):
		if sec.leverage and People.chars.has(sec.about):
			add_favours(sec.about, s, 1 if favours(sec.about, s) < 5 else 0)
			var c := People.person(sec.about)
			c.relations[s.captain] = c.relations.get(s.captain, 0) - 3


# ---- the pirate council of Nassau ----------------------------------------------------

func council_members() -> Array:
	if council.is_empty():
		for i in int(cfg().council.members):
			var c := People.generate({"mix": Data.rules.people.recruit_mix.pirates})
			c.stats.authority = mini(20, c.stats.authority + 4)
			c.stats.intimidation = mini(20, c.stats.intimidation + 4)
			c.skills.swordplay = mini(20, c.skills.swordplay + 4)
			c.role = "council"
			c.faction = "pirates"
			c.port = "nassau"
			c.ship = Data.table("factions").pirates.ship_names[i % Data.table("factions").pirates.ship_names.size()]
			c.favours = {}
			c.hidden = []
			c.history.append("Captain of the %s, of the Nassau council." % c.ship)
			council.append(People.add(c))
		council.sort_custom(func(a, b): return People.leadership(People.person(a)) > People.leadership(People.person(b)))
		council_leader = council[0]
	return council


static func council_problem(s: Dictionary) -> String:
	var c: Dictionary = cfg().council
	if s.get("council_member", false):
		return "You already sit on the council."
	if s.reputation.notoriety < c.join_notoriety:
		return "Nobody's heard of you (notoriety %d of %d)." % [s.reputation.notoriety, c.join_notoriety]
	if s.relations.get("pirates", 0) < c.join_pirate_relation:
		return "The Brethren don't trust you yet (standing %d of %d)." % [s.relations.get("pirates", 0), c.join_pirate_relation]
	return ""


func bribe_cost(s: Dictionary) -> int:
	return int(cfg().council.bribe * (0.5 if Growth.captain_has(s, "open_palm") else 1.0))


func bribe(s: Dictionary, id: String) -> String:
	var cost := bribe_cost(s)
	if s.gold < cost:
		return "That takes %d gold." % cost
	s.gold -= cost
	var c := People.person(id)
	c.relations[s.captain] = c.relations.get(s.captain, 0) + int(cfg().council.bribe_opinion)
	return "%s takes your %d gold, and your side, for now." % [c.name, cost]


## How a council captain votes. side: what you want (true = yes). Your friends and debtors follow you;
## otherwise their own nature decides.
func member_votes_yes(s: Dictionary, id: String, topic: String, side: bool) -> bool:
	var c := People.person(id)
	var lean := 0.0
	match topic:
		"pardon": lean = (0.4 if "family_man" in c.traits else 0.0) - (0.4 if "bloodthirsty" in c.traits else 0.0) - 0.1
		"defend": lean = (0.3 if "brave" in c.traits else 0.0) - (0.4 if "cowardly" in c.traits else 0.0) + 0.1
		"punish": lean = (0.3 if "honest" in c.traits else 0.0) - (0.3 if "schemer" in c.traits else 0.0)
	var mine: float = c.relations.get(s.captain, 0) / 50.0 + favours(id, s) * 0.3 + Bonds.level(s, id) * 0.25
	var yes := 0.5 + lean + (mine if side else -mine) + rng.randf_range(-0.25, 0.25)
	return yes > 0.5


## A vote of the council (and you, if you sit on it). Applies the topic's outcomes. {passed, yes, no, text}
func council_vote(s: Dictionary, topic: String, side: bool, ctx: Dictionary) -> Dictionary:
	var yes := 0
	var no := 0
	for id in council_members():
		if member_votes_yes(s, id, topic, side):
			yes += 1
		else:
			no += 1
	if s.get("council_member", false):
		if side: yes += 1
		else: no += 1
	var passed := yes > no
	var t: Dictionary = cfg().council.topics[topic]
	var lines := PackedStringArray()
	for o in t.get("yes" if passed else "no", []):
		var line := Events.apply_outcome(o, ctx)
		if line != "":
			lines.append(line)
	return {"passed": passed, "yes": yes, "no": no,
		"text": "The council votes %s on '%s', %d to %d. %s" % ["yes" if passed else "no", t.name, yes, no, ", ".join(lines)]}


## Stand for the leadership. Members back you if they like you better than the leader.
func leadership_vote(s: Dictionary) -> String:
	if council_leader == "player":
		return "You already lead the council."
	var lead := People.person(council_leader)
	var mine := 1
	var theirs := 0
	for id in council_members():
		if id == council_leader:
			theirs += 1
			continue
		var c := People.person(id)
		var for_me: float = c.relations.get(s.captain, 0) + favours(id, s) * 15 + People.leadership(ShipStats.captain(s))
		var for_them: float = c.relations.get(council_leader, 0) + People.leadership(lead) + rng.randf_range(-8, 8)
		if for_me > for_them: mine += 1
		else: theirs += 1
	if mine > theirs:
		council_leader = "player"
		s.reputation.fear += 2
		return "The council elects you its leader, %d to %d. %s will not take it well.%s" % [mine, theirs, lead.name, _take_nassau(s)]
	lead.relations[s.captain] = lead.relations.get(s.captain, 0) - 20
	return "The council stands by %s, %d to %d. You've made an enemy of the leader." % [lead.name, theirs, mine]


## Challenge the leader to a duel, by the old code.
func challenge(s: Dictionary) -> String:
	var lead := People.person(council_leader)
	var cap := ShipStats.captain(s)
	var c := Dice.contest(rng, "Duel", [["Your swordplay", Dice.mod(People.value(cap, "swordplay"))]], [["%s's swordplay" % lead.name, Dice.mod(People.value(lead, "swordplay"))]])
	var roll := Dice.describe(c).replace("[b]", "").replace("[/b]", "").replace("[/color]", "").replace("[color=#2e6b3a]", "").replace("[color=#a3261b]", "")
	if c.success:
		council_leader = "player"
		s.reputation.fear += 4
		lead.relations[s.captain] = -60
		lead.history.append("Beaten in a duel for the council's leadership, %s." % Clock.date_string())
		return "Steel on the beach at dawn. %s yields, bleeding, and the council is yours.%s\n%s" % [lead.name, _take_nassau(s), roll]
	var t := People.wound(cap)
	s.relations.pirates = s.relations.get("pirates", 0) - 5
	return "%s beats you on the beach, and the council laughs. You'll carry it: %s.\n%s" % [lead.name, Data.table("traits")[t].name.to_lower() if t != "" else "a cut and a lesson", roll]


## A town has been taken and held: its officials are out (the broker stays in business). The governor won't forget.
func depose(s: Dictionary, port_id: String) -> void:
	var held: Dictionary = officials.get(port_id, {})
	for role in held.keys():
		if role == "broker" or not People.chars.has(held[role]):
			continue
		var old := People.person(held[role])
		old.history.append("Turned out of %s when %s took it, %s." % [Ports.port(port_id).name, ShipStats.captain(s).name, Clock.date_string()])
		old.port = ""
		old.role = "former_" + role
		if role == "governor" and Bonds.level(s, held[role]) > -1:
			Bonds.start_rivalry(s, held[role], 1, "you took their town")
		held.erase(role)
	Contracts.offers.erase(port_id)


## Leading the council makes Nassau yours to run, if you've room for another base. England has long claimed it.
func _take_nassau(s: Dictionary) -> String:
	if Bases.bases.has("nassau") or Bases.bases.size() >= Data.rules.bases.max:
		return ""
	return " " + Bases.hold_town(s, "nassau", 0, int(Data.rules.sieges.hold.council_men), "england")


func save_state() -> Dictionary:
	return {"officials": officials, "influence": influence, "council": council, "council_leader": council_leader, "rng": str(rng.state)}


func load_state(d: Dictionary) -> void:
	officials = d.officials
	influence = d.influence
	council = d.council
	council_leader = d.council_leader
	rng.state = int(d.rng)
