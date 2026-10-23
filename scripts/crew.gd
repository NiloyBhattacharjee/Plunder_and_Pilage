class_name Crew
## The crew as a body of people: morale, articles and shares, rum, disease, friendships and feuds,
## the slow build-up of a mutiny, and who takes over when the captain falls.
## Works on ship state:
##   articles: {pay: "wages" or "shares", crew_share: 0..1}   morale_mods: [{id, name, value, until}]
##   unrest: {leader, support: [ids], stage 0-5, known}        days_at_sea, last_plunder, heir, captains: [line]
##   succession: {cause, deposed} while a new captain is waiting to be chosen.
## Everyone involved is an ordinary character in People; a sick person carries c.sick = disease id.


static func cfg() -> Dictionary:
	return Data.rules.crew


static func ensure(s: Dictionary) -> void:
	for k in ["articles", "morale_mods", "unrest", "days_at_sea", "last_plunder", "heir", "captains", "hard_days", "good_days"]:
		if not s.has(k):
			s[k] = {"articles": {"pay": "wages", "crew_share": 0.25}, "morale_mods": [], "unrest": fresh_unrest(),
				"days_at_sea": 0, "last_plunder": Clock.day, "heir": "", "captains": [], "hard_days": 0, "good_days": 0}[k]


static func fresh_unrest() -> Dictionary:
	return {"leader": "", "support": [], "stage": 0, "known": false, "since": Clock.day}


static func people(s: Dictionary) -> Array:
	return s.crew.map(func(id): return People.person(id))


static func tags(c: Dictionary) -> Array:
	var out := []
	for t in c.traits:
		out.append_array(Data.table("traits")[t].get("tags", []))
	return out


static func opinion(c: Dictionary, s: Dictionary) -> int:
	return c.relations.get(s.captain, 0)


# ---- morale ----------------------------------------------------------------------

## The crew's mood, 0-100, with every part of it explained: {value, parts: [[label, value]], text}.
static func morale(s: Dictionary, stats: Dictionary) -> Dictionary:
	var c := cfg()
	var crew := people(s)
	var parts := [["Base", float(c.morale_base)]]
	if s.articles.pay == "wages":
		var bill: float = maxf(1.0, s.crew.size() * Data.rules.upkeep.wage_per_crew)
		var days: float = s.wages_owed / bill
		if days >= 1.0:
			parts.append(["Wages %d days unpaid" % days, -minf(c.unpaid_max, days * c.unpaid_per_day)])
		else:
			parts.append(["Wages paid", float(c.wages_paid)])
	else:
		var idle: float = Clock.day - s.last_plunder
		if idle > c.no_prey_grace:
			parts.append(["No prey, no pay: %d days without plunder" % idle, -minf(c.unpaid_max, (idle - c.no_prey_grace) * c.no_prey_per_day)])
		else:
			parts.append(["Fresh plunder in their pockets", float(c.wages_paid)])
	var greedy := 0
	for p in crew:
		if "greedy" in tags(p):
			greedy += 1
	var share_mult: float = 1.0 + (c.greedy_share_mult - 1.0) * greedy / maxf(1.0, crew.size())
	var share: float = (s.articles.crew_share - c.fair_share) * c.share_morale * share_mult
	if absf(share) >= 0.5:
		parts.append(["Crew's share of plunder %d%%" % int(s.articles.crew_share * 100), share])
	if s.cargo.get("food", 0.0) <= 0.0:
		parts.append(["No food", float(c.no_food)])
	if s.cargo.get("water", 0.0) <= 0.0:
		parts.append(["No water", float(c.no_water)])
	var drunks := crew.filter(func(p): return "drinks" in tags(p)).size()
	var rum: float = c.rum * (1.0 + float(drunks) / maxf(1.0, crew.size()) * 3.0)
	parts.append(["Rum ration" if s.cargo.get("rum", 0.0) > 0.0 else "No rum", rum if s.cargo.get("rum", 0.0) > 0.0 else -rum])
	if stats.get("comfort", 0) != 0:
		parts.append(["Quarters", stats.comfort * c.comfort])
	var sick := sick_count(s)
	if sick > 0:
		parts.append(["%d sick" % sick, -float(sick) / maxf(1.0, crew.size()) * c.sick])
	var cap := ShipStats.captain(s)
	var lead: float = (People.value(cap, "authority") + People.value(cap, "charisma") - 20) * c.captain_per_point
	if absf(lead) >= 0.5:
		parts.append(["Captain's authority and charisma", lead])
	var loyal: float = Events.loyalty(s) * c.opinion_weight
	if absf(loyal) >= 0.5:
		parts.append(["What they think of you", loyal])
	for m in s.morale_mods:
		parts.append([m.name, float(m.value)])
	parts.append_array(Civics.parts(s, "morale"))  # the articles
	parts.append_array(Bonds.morale_parts(s))
	for pair in [["superstitious", "superstitious_morale"], ["devout", "devout_morale"]]:  # the figurehead
		var v := ShipStats.look_effect(s, pair[1])
		var part_share: float = crew.filter(func(p): return pair[0] in tags(p)).size() / maxf(1.0, crew.size())
		if absf(v * part_share) >= 0.5:
			parts.append(["%s, to the %s" % [ShipStats.look(s, "figurehead").name, pair[0]], v * part_share])
	for id in [s.captain] + s.officers.values():
		if People.chars.has(id) and Growth.has_perk(People.person(id), "beloved"):
			parts.append(["%s is beloved" % People.person(id).name, 3.0])
	var total := 0.0
	var lines := PackedStringArray()
	for p in parts:
		total += p[1]
		lines.append("%s: %+d" % [p[0], int(round(p[1]))])
	var value := clampf(total, 0.0, 100.0)
	return {"value": value, "parts": parts, "text": "Morale %d\n%s" % [value, "\n".join(lines)]}


## A timed modifier on morale. The same id replaces an older one.
static func add_mod(s: Dictionary, id: String, name: String, value: float, days: float) -> void:
	s.morale_mods = s.morale_mods.filter(func(m): return m.id != id)
	s.morale_mods.append({"id": id, "name": name, "value": value, "until": Clock.day + days})


# ---- articles and shares -----------------------------------------------------------

## Plunder coming aboard: the crew take their share by the articles. Returns a message.
static func plunder(s: Dictionary, amount: float) -> String:
	if amount <= 0.0 or s.crew.is_empty():
		return ""
	var cut: float = floorf(amount * s.articles.crew_share)
	s.gold -= cut
	s.last_plunder = Clock.day
	if cut <= 0.0:
		return ""
	var per_man: float = cut / s.crew.size()
	add_mod(s, "shares", "Shares paid out", clampf(per_man * cfg().share_mod_per_gold, 1.0, cfg().shares_max_mod), cfg().shares_days)
	return "The crew take their share: %d gold (%d a man)." % [cut, per_man]


## A vote of the whole crew. benefit: how much the question favours them, -1..1. {passed, yes, no}
static func vote(s: Dictionary, stats: Dictionary, benefit: float, rng: RandomNumberGenerator) -> Dictionary:
	var c := cfg()
	var yes := 0
	var m: float = morale(s, stats).value
	for p in people(s):
		var b := benefit * (1.5 if "greedy" in tags(p) else 1.0)
		var chance: float = c.vote_base + b * c.vote_benefit + opinion(p, s) * c.vote_per_opinion + (m - 50.0) * c.vote_per_morale
		if p.id in s.unrest.support:
			chance -= 0.3
		if rng.randf() < chance:
			yes += 1
	return {"passed": yes * 2 > s.crew.size(), "yes": yes, "no": s.crew.size() - yes}


## Changing the articles. Pirates vote on it; anyone else just decides, but a cut is resented.
static func set_articles(s: Dictionary, stats: Dictionary, pay: String, share: float, rng: RandomNumberGenerator) -> String:
	share = clampf(snappedf(share, 0.05), 0.0, 0.8)
	var a: Dictionary = s.articles
	var benefit: float = (share - a.crew_share) * 3.0
	if s.career.pirate:
		var v := vote(s, stats, clampf(benefit, -1.0, 1.0), rng)
		if not v.passed:
			add_mod(s, "vote_lost", "Outvoted on the articles", -5, 30)
			return "The crew vote it down, %d to %d." % [v.no, v.yes]
		a.pay = pay
		a.crew_share = share
		return "The crew vote for the new articles, %d to %d." % [v.yes, v.no]
	if share < a.crew_share:
		add_mod(s, "shares_cut", "Shares cut", -10, 60)
	a.pay = pay
	a.crew_share = share
	return "New articles: %s, %d%% of plunder to the crew." % ["wages" if pay == "wages" else "no prey, no pay", int(share * 100)]


# ---- the daily round -----------------------------------------------------------------

## Rum, disease, friendships, desertion pressure and unrest. Returns messages.
static func daily(s: Dictionary, stats: Dictionary, port: String, rng: RandomNumberGenerator) -> Array:
	ensure(s)
	s.morale_mods = s.morale_mods.filter(func(m): return m.until > Clock.day)
	if s.cargo.get("rum", 0.0) > 0.0:
		Ports.remove_cargo(s, "rum", ShipStats.headcount(s) * cfg().rum_per_crew)
	for id in s.crew:  # hands who've levelled up improve on their own; you choose for officers
		if not id in s.officers.values():
			Growth.auto_spend(People.person(id))
	var msgs := disease_day(s, port, rng)
	msgs.append_array(social_day(s, rng))
	msgs.append_array(mood_day(s, morale(s, stats)))
	msgs.append_array(unrest_day(s, stats, rng))
	return msgs


## Day after day of hard times and the crew start to blame you: each hand's opinion of you falls (the greedy faster
## while unpaid, drinkers while the rum is gone), but hardship alone stops at a floor; past it, only what you do
## can sink you. Good times win some of it back, up to a point. m: morale() for today.
static func mood_day(s: Dictionary, m: Dictionary) -> Array:
	var g: Dictionary = cfg().grudge
	var hard: bool = m.value < g.below
	var good: bool = m.value > g.good_above
	s.hard_days = int(s.hard_days) + 1 if hard else 0
	s.good_days = int(s.good_days) + 1 if good else 0
	var days: int = s.hard_days if hard else s.good_days
	if not (hard or good) or days < int(g.after_days) or (days - int(g.after_days)) % int(g.every_days) != 0:
		return []
	var hurts: Array = m.parts.filter(func(p): return p[1] < 0).map(func(p): return p[0])
	var unpaid := hurts.any(func(l): return l.begins_with("Wages") or l.begins_with("No prey"))
	var dry := "No rum" in hurts
	for p in people(s):
		var op := opinion(p, s)
		if good:
			p.relations[s.captain] = mini(op + 1, maxi(op, int(g.good_cap)))
			continue
		var t := tags(p)
		var n := 1 + (1 if unpaid and "greedy" in t else 0) + (1 if dry and "drinks" in t else 0)
		p.relations[s.captain] = maxi(op - n, mini(op, int(g.floor)))
	if days != int(g.after_days):
		return []
	if good:
		return ["Good times aboard: the crew are warming to you."]
	return ["A hard week, and the crew have started to blame you for it. Their opinion of you will keep falling while morale stays below %d." % g.below]


## What a fight leaves in their minds: striking the colours shames every hand, a bloodbath is laid at your door,
## and a prize taken warms them (up to the good-times cap). after: your side at the end of the battle. Returns news, or "".
static func after_battle(s: Dictionary, outcome: String, after: Dictionary) -> String:
	var g: Dictionary = cfg().grudge
	var n := 0
	var why := []
	if outcome == "player_struck":
		n += int(g.struck)
		why.append("you struck the colours")
	if after.get("casualties", 0.0) > after.get("crew_start", INF) * float(g.heavy_losses):
		n += int(g.losses)
		why.append("so many dead")
	if n == 0 and outcome == "enemy_struck":
		for p in people(s):
			var op := opinion(p, s)
			p.relations[s.captain] = mini(op + int(g.prize), maxi(op, int(g.good_cap)))
		return ""
	if n == 0:
		return ""
	for p in people(s):
		p.relations[s.captain] = clampi(opinion(p, s) + n, -100, 100)
	return "The crew blame you: %s (opinion of you %+d)." % [" and ".join(why), n]


## Hands who can work: the sick still eat, but they don't haul on ropes.
static func able(s: Dictionary) -> int:
	return ShipStats.headcount(s) - sick_count(s)


static func sick_count(s: Dictionary) -> int:
	var n := 0
	for id in s.crew + [s.captain]:
		if People.chars.has(id) and People.person(id).get("sick", "") != "":
			n += 1
	return n


static func disease_day(s: Dictionary, port: String, rng: RandomNumberGenerator) -> Array:
	var c := cfg()
	var msgs := []
	s.days_at_sea = 0 if port != "" else s.days_at_sea + 1
	var med := ShipStats.officer_skill(s, "surgeon")
	var low_supplies: float = minf(s.cargo.get("food", 0.0), s.cargo.get("water", 0.0)) / maxf(1.0, ShipStats.headcount(s) * Data.rules.upkeep.food_per_crew)
	var dead := []
	var everyone: Array = s.crew.duplicate()
	if not s.has("succession"):  # a dead captain waiting for a successor can't die twice
		everyone.append(s.captain)
	for id in everyone:
		var p := People.person(id)
		var sick: String = p.get("sick", "")
		if sick != "":
			var d: Dictionary = c.disease[sick]
			if rng.randf() < d.death * maxf(0.2, 1.0 - med * c.surgeon_death_cut_per_point):
				if id == s.captain:
					captain_dies(s, "died of %s" % d.name.to_lower())
					msgs.append("Captain %s has died of %s." % [p.name, d.name.to_lower()])
				else:
					dead.append(p.name)
					mourn(s, id)
					remove_hand(s, id)
			elif rng.randf() < (d.recover_port if port != "" else d.recover) * (1.0 + med * c.surgeon_recover_per_point):
				p.sick = ""
			continue
		for kind in c.disease:
			var d: Dictionary = c.disease[kind]
			var chance: float = d.chance
			match kind:
				"scurvy": if s.days_at_sea < d.after_days_at_sea: chance = 0.0
				"flux": if low_supplies >= d.supplies_below_days: chance = 0.0
				"fever":
					if not float(Clock.date().month) in d.months: chance = 0.0
					elif port != "": chance *= d.port_mult
			if chance > 0.0 and rng.randf() < chance:
				p.sick = kind
				if id == s.captain or id in s.officers.values():
					msgs.append("%s has come down with %s." % [p.name, d.name.to_lower()])
				break
	if not dead.is_empty():
		msgs.append("Sickness carried off %s." % ", ".join(dead))
	return msgs


## Friendships and feuds form slowly, out of who people are.
static func social_day(s: Dictionary, rng: RandomNumberGenerator) -> Array:
	var c := cfg()
	var msgs := []
	if s.crew.size() < 2:
		return msgs
	for id in s.crew:
		if rng.randf() >= c.social_chance:
			continue
		var other: String = s.crew[rng.randi() % s.crew.size()]
		if other == id:
			continue
		var a := People.person(id)
		var b := People.person(other)
		var delta := affinity(a, b) * 3 + rng.randi_range(-8, 8)
		for pair in [[a, other], [b, id]]:
			pair[0].relations[pair[1]] = clampi(pair[0].relations.get(pair[1], 0) + delta, -100, 100)
	for pair in feuds(s):
		if rng.randf() < c.rival_fight_chance:
			var loser := People.person(pair[rng.randi() % 2])
			var t := People.wound(loser) if rng.randf() < 0.2 else ""
			add_mod(s, "bad_blood", "Bad blood below decks", -3, 10)
			msgs.append("%s and %s came to blows%s." % [People.person(pair[0]).name, People.person(pair[1]).name,
				" and %s will carry it: %s" % [loser.name, Data.table("traits")[t].name.to_lower()] if t != "" else ""])
	return msgs


## How well two people get on, from who they are.
static func affinity(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	if a.nationality == b.nationality:
		n += 2
	for pair in [[a, b], [b, a]]:
		var x: Dictionary = pair[0]
		var y: Dictionary = pair[1]
		if "popular" in y.traits: n += 2
		if "hated" in y.traits: n -= 3
		if "hot_headed" in x.traits: n -= 1
		if "devout" in x.traits and "drunkard" in y.traits: n -= 3
		if "veteran" in x.traits and "green" in y.traits: n += 1
	for shared in ["drunkard", "gambler", "calm", "devout", "former_navy"]:
		if shared in a.traits and shared in b.traits:
			n += 2
	return n


static func friends_of(s: Dictionary, id: String) -> Array:
	return s.crew.filter(func(o): return o != id and People.person(o).relations.get(id, 0) >= cfg().friend)


## Pairs aboard who can't stand each other: [[id, id]].
static func feuds(s: Dictionary) -> Array:
	var out := []
	for id in s.crew:
		var p := People.person(id)
		for o in p.relations:
			if o != s.captain and o > id and o in s.crew and p.relations[o] <= cfg().rival and People.person(o).relations.get(id, 0) <= cfg().rival:
				out.append([id, o])
	return out


## A death that hurts: friends grieve, the loss of a popular hand or an officer weighs on everyone, and a friend
## may take up their cause (or swear revenge on the killer). Returns the news.
static func mourn(s: Dictionary, id: String, killer := "") -> String:
	if not People.chars.has(id):
		return ""
	var p := People.person(id)
	var grief: int = friends_of(s, id).size() + (4 if "popular" in p.traits else 0) + (2 if id in s.officers.values() else 0)
	if grief > 0:
		add_mod(s, "mourning_" + id, "Mourning %s" % p.name, -(cfg().mourning_base + grief), cfg().mourning_days)
	return Wants.inherit(s, id, killer)


## keep: they live on elsewhere (a captain now), so stay in the registry.
static func remove_hand(s: Dictionary, id: String, keep := false) -> void:
	for post in s.officers.keys():
		if s.officers[post] == id:
			s.officers.erase(post)
	s.crew.erase(id)
	s.unrest.support.erase(id)
	if s.unrest.leader == id:
		s.unrest = fresh_unrest()
	if s.heir == id:
		s.heir = ""
	if not keep:
		People.remove(id)


# ---- mutiny: discontent, a ringleader, and support that grows -------------------------

## How much this person wants a change of captain.
static func discontent(p: Dictionary, s: Dictionary, morale_value: float) -> float:
	var d: float = -opinion(p, s) + (50.0 - morale_value) * 0.6
	var t := tags(p)
	if "loyal" in t:
		d -= 30.0
	if "greedy" in t and s.articles.crew_share < cfg().fair_share:
		d += 10.0
	if s.unrest.leader != "" and p.relations.get(s.unrest.leader, 0) >= cfg().friend:
		d += 20.0
	return d


static func unrest_day(s: Dictionary, stats: Dictionary, rng: RandomNumberGenerator) -> Array:
	var c := cfg()
	var u: Dictionary = s.unrest
	var msgs := []
	if u.leader != "" and not u.leader in s.crew:
		s.unrest = fresh_unrest()
		u = s.unrest
	var m: float = morale(s, stats).value
	if u.leader == "" and m < c.unrest_morale and rng.randf() < c.leader_chance:
		var best := ""
		var best_score := -INF
		for p in people(s):
			var stirs: bool = "ringleader" in tags(p) and (People.value(p, "charisma") >= c.leader_min_stat or People.value(p, "intimidation") >= c.leader_min_stat)
			var score: float = People.value(p, "charisma") + People.value(p, "intimidation") - opinion(p, s) / 5.0
			if stirs and discontent(p, s, m) > c.discontent and score > best_score:
				best = p.id
				best_score = score
		if best != "":
			u.leader = best
			u.support = [best]
	if u.leader == "":
		u.stage = 0
		return msgs
	var lead := People.person(u.leader)
	for p in people(s):
		if p.id in u.support:
			if p.id != u.leader and discontent(p, s, m) < 0.0 and rng.randf() < c.leave_chance:
				u.support.erase(p.id)
			continue
		var chance: float = c.recruit_chance * People.value(lead, "charisma") / 10.0 * (2.0 if p.relations.get(u.leader, 0) >= c.friend else 1.0) 			* maxf(0.0, 1.0 + Civics.bonus(s, "unrest"))
		if discontent(p, s, m) > c.discontent and rng.randf() < chance:
			u.support.append(p.id)
	if u.support.size() <= 1 and m >= c.unrest_morale + 10:
		s.unrest = fresh_unrest()  # the leader gives up: nobody's listening
		return msgs
	var frac := float(u.support.size()) / maxf(1.0, s.crew.size())
	var stage := 0
	for i in c.stages.size():
		if frac >= c.stages[i]:
			stage = i + 1
	# it builds a step at a time: each warning sign gets its week before the next
	if stage > u.stage and Clock.day - u.get("since", 0.0) >= c.stage_days:
		u.stage += 1
		u.since = Clock.day
	elif stage < u.stage:
		u.stage = stage
		u.since = Clock.day
	return msgs


static func stage_name(s: Dictionary) -> String:
	return cfg().stage_names[s.unrest.stage]


## Removes n of the plotters (not the leader): talked round, frightened off or bought.
static func calm(s: Dictionary, n: int) -> void:
	var u: Dictionary = s.unrest
	for i in n:
		var others: Array = u.support.filter(func(id): return id != u.leader)
		if others.is_empty():
			break
		u.support.erase(others[0])
		People.person(others[0]).relations[s.captain] = People.person(others[0]).relations.get(s.captain, 0) + 5


## Someone's money in the forecastle: n more hands join the plotters (and if nobody leads them yet, someone will).
static func stir(s: Dictionary, n: int) -> void:
	var u: Dictionary = s.unrest
	if u.leader == "" and not s.crew.is_empty():
		var pool: Array = s.crew.filter(func(id): return "ringleader" in tags(People.person(id)))
		u.leader = (pool if not pool.is_empty() else s.crew)[0]
		u.support = [u.leader]
		u.since = Clock.day
	for id in s.crew:
		if n <= 0:
			break
		if not id in u.support and not "loyal" in tags(People.person(id)):
			u.support.append(id)
			n -= 1


## The mutiny itself: the plotters against the captain and whoever stands with them.
## {won, outcome: crushed|deposed|killed|split, check, text}
static func mutiny(s: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var u: Dictionary = s.unrest
	var cap := ShipStats.captain(s)
	var rebels: Array = u.support.filter(func(id): return id in s.crew)
	var loyal: Array = s.crew.filter(func(id): return not id in rebels and opinion(People.person(id), s) >= 0)
	var lead := People.person(u.leader) if u.leader != "" else cap
	var ratio := log(maxf(1.0, rebels.size()) / maxf(1.0, loyal.size() + 1)) / log(2.0) * 3.0
	var theirs := [["Their numbers", int(clampf(ratio, -6, 6))], ["%s's menace" % lead.name, Dice.mod(People.value(lead, "intimidation"))]]
	var ours := [["Your sword", Dice.mod(People.value(cap, "swordplay"))], ["Your authority", Dice.mod(People.value(cap, "authority"))]]
	var officers: int = s.officers.values().filter(func(id): return id in loyal).size()
	if officers > 0:
		ours.append(["Loyal officers", officers])
	var check := Dice.contest(rng, "Mutiny", ours, theirs)
	if check.success:
		return {"won": true, "outcome": "crushed", "check": check, "rebels": rebels,
			"text": "The mutiny is crushed. %s and %d others are in irons, waiting to hear what you'll do with them." % [lead.name, rebels.size() - 1]}
	if float(rebels.size()) / maxf(1.0, s.crew.size()) < cfg().split_below:
		for id in rebels:
			remove_hand(s, id)
		s.unrest = fresh_unrest()
		return {"won": false, "outcome": "split", "check": check, "rebels": [],
			"text": "Neither side can win. The mutineers take the longboat and arms, %d of them, and pull for the shore." % rebels.size()}
	var killed: bool = -check.margin >= cfg().kill_margin
	captain_dies(s, "killed by mutineers" if killed else "deposed by the crew", not killed)
	s.succession.favour = u.leader
	return {"won": false, "outcome": "killed" if killed else "deposed", "check": check, "rebels": rebels,
		"text": "%s's mutineers take the ship. %s" % [lead.name, "Captain %s is cut down on the quarterdeck." % cap.name if killed
			else "Captain %s is put ashore on the nearest beach with a pistol and a bottle of water." % cap.name]}


## What happens to crushed mutineers: "hang" the ringleader, "maroon" them all, or "forgive".
static func punish(s: Dictionary, rebels: Array, how: String) -> String:
	var lead: String = s.unrest.leader
	var text := ""
	match how:
		"hang":
			if lead != "" and lead in s.crew:
				text = "%s hangs from the main yard at dawn." % People.person(lead).name
				text += " " + Wants.part(s, lead, "hanged")
			s.reputation.fear += 3
			for id in rebels:
				if id in s.crew:
					People.person(id).relations[s.captain] = People.person(id).relations.get(s.captain, 0) - 5
		"maroon":
			text = "%d mutineers are left on a sandbar with a cask of water." % rebels.size()
			for id in rebels:
				if id in s.crew:
					var after := Wants.part(s, id, "marooned")
					if after != "":
						text += " " + after
			s.reputation.fear += 2
		"forgive":
			for id in rebels:
				if id in s.crew:
					People.person(id).relations[s.captain] = People.person(id).relations.get(s.captain, 0) + 10
			s.reputation.honour += 2
			text = "You forgive them, every one. Some will remember it; some will think you weak."
	s.unrest = fresh_unrest()
	return text


# ---- succession ---------------------------------------------------------------------

## The captain is gone (dead, or put ashore). A new one is chosen at the next chance.
static func captain_dies(s: Dictionary, cause: String, alive := false) -> void:
	if not s.has("succession"):
		s.succession = {"cause": cause, "deposed": alive, "favour": ""}


static func culture(s: Dictionary) -> String:
	return "election" if s.career.pirate else "command"


## Who could take over, with the crew's support for each: [{id, support (0..1), why}].
static func candidates(s: Dictionary, rng: RandomNumberGenerator) -> Array:
	var c := cfg()
	var pool: Array = people(s)
	pool.sort_custom(func(a, b): return People.leadership(a) > People.leadership(b))
	var cands: Array = pool.slice(0, 3).map(func(p): return p.id)
	for extra in [s.heir, s.get("succession", {}).get("favour", ""), s.officers.get("quartermaster", "")]:
		if extra != "" and extra in s.crew and not extra in cands:
			cands.append(extra)
	var votes := {}
	for id in cands:
		votes[id] = 0
	for voter in pool:
		var best := ""
		var best_score := -INF
		for id in cands:
			var cand := People.person(id)
			var score: float = People.leadership(cand) + rng.randf_range(-8.0, 8.0)
			if id != voter.id:  # crews split along friendships, origins and temperament
				score += voter.relations.get(id, 0) + affinity(voter, cand) * 3
			if id == s.heir:
				score += c.heir_bonus * (0.5 + People.value(ShipStats.captain(s), "authority") / 20.0)
			if id == s.get("succession", {}).get("favour", "") and voter.id in s.unrest.support:
				score += c.leader_bonus
			if score > best_score:
				best = id
				best_score = score
		votes[best] += 1
	var out := []
	for id in cands:
		out.append({"id": id, "support": float(votes[id]) / maxf(1.0, pool.size()), "why": _why(s, id)})
	out.sort_custom(func(a, b): return a.support > b.support)
	return out


static func _why(s: Dictionary, id: String) -> String:
	var bits := PackedStringArray()
	if id == s.heir:
		bits.append("your chosen successor")
	if id in s.officers.values():
		bits.append(Data.rules.officer_roles[s.officers.find_key(id)].name.to_lower())
	if id == s.get("succession", {}).get("favour", ""):
		bits.append("led the mutiny")
	return ", ".join(bits)


## Who takes over by custom: pirates vote; others follow the chain of command (heir, quartermaster,
## then the most experienced officer) unless the crew won't have them. {id, how}
static func chosen(s: Dictionary, cands: Array) -> Dictionary:
	if cands.is_empty():
		return {}
	if culture(s) == "command":
		var chain: Array = []
		if s.heir in s.officers.values():
			chain.append(s.heir)
		if s.officers.has("quartermaster"):
			chain.append(s.officers.quartermaster)
		var officers: Array = s.officers.values().filter(func(id): return id in s.crew)
		officers.sort_custom(func(a, b): return People.value(People.person(a), "experience") > People.value(People.person(b), "experience"))
		chain.append_array(officers)
		for id in chain:  # the next in line takes over, unless the crew won't follow them
			var found := cands.filter(func(x): return x.id == id)
			if not found.is_empty() and found[0].support >= cfg().reject_below:
				return {"id": id, "how": "command"}
	return {"id": cands[0].id, "how": "elected"}


## Hands hard enough to take the ship whatever the crew want.
static func strongmen(s: Dictionary) -> Array:
	return s.crew.filter(func(id): return People.value(People.person(id), "intimidation") >= cfg().seize_intimidation)


## Hands over the ship. how: elected, command or force. Returns messages.
static func make_captain(s: Dictionary, id: String, how: String) -> Array:
	var c := cfg()
	var old := Ambitions.ensure(s)  # their ambition and titles go with them; the log keeps the titles
	var fate: String = s.succession.cause if s.has("succession") else "stood down"
	var new_cap := People.person(id)
	s.captains.append({"name": old.name, "until": Clock.date_string(), "fate": fate,
		"titles": old.titles.map(func(a): return Ambitions.table()[a].title)})
	old.history.append("%s, %s." % [fate.capitalize(), Clock.date_string()])
	for post in s.officers.keys():
		if s.officers[post] == id:
			s.officers.erase(post)
	s.crew.erase(id)
	s.captain = id
	People.remove(old.id)
	new_cap.hidden = []  # you know yourself
	new_cap.history.append("Took command of the %s (%s), %s." % [s.name, {"elected": "elected by the crew", "command": "by the chain of command",
		"force": "by force"}[how], Clock.date_string()])
	for f in s.relations:
		s.relations[f] = int(s.relations[f] * c.keep_relations)
	s.reputation.honour = int(s.reputation.honour * c.keep_honour_fear)
	s.reputation.fear = int(s.reputation.fear * c.keep_honour_fear)
	s.reputation.notoriety = s.reputation.notoriety * c.keep_notoriety
	var msgs := ["%s is captain of the %s now." % [new_cap.name, s.name]]
	if s.career.marque != "":
		msgs.append(Career.revoke(s, "because the commission named Captain %s" % old.name))
		s.career.crown_debt = 0.0
	s.career.pardoned_by = []
	if s.heir == id:
		s.heir = ""
	s.unrest = fresh_unrest()
	s.morale_mods = s.morale_mods.filter(func(m): return not m.id.begins_with("mourning"))
	match how:
		"elected": add_mod(s, "new_captain", "A captain of their own choosing", c.elected, c.new_captain_days)
		"force": add_mod(s, "new_captain", "Command taken by force", c.by_force, c.new_captain_days)
	s.erase("succession")
	var dream := Ambitions.from_want(s)
	if dream != "":
		msgs.append(dream)
	msgs.append_array(Bonds.reconsider(s))  # the ship's bonds carry over, but allies weigh up the new captain
	return msgs
