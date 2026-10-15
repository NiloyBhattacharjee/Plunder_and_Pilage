class_name Encounters
## Who you meet at sea (from data/encounters.json), and what a fight leaves behind:
## damage and dead crew, plunder, prize ships, prisoners, ransom, and how it all changes your name.
## Milestone 5 replaces random sightings with real NPC ships on the map; this aftermath stays.


## A random ship near waters owned by `faction`. Pirate waters only produce pirates.
static func generate(faction: String, rng: RandomNumberGenerator, kind := "", type := "") -> Dictionary:
	var table: Dictionary = Data.table("encounters")
	if kind == "":
		kind = "pirate" if faction == "pirates" else _weighted(table, rng)
	var e: Dictionary = table[kind]
	var f: String = e.get("faction", faction)
	if type == "":
		type = e.ships[rng.randi() % e.ships.size()]
	var upgrades: Array = e.get("upgrades", []).filter(func(u): return ShipStats.cannot_install({"type": type, "upgrades": []}, u, 2) == "")
	var st := ShipStats.effective(type, upgrades)
	var names: Array = Data.table("factions")[f].ship_names
	var mix: Dictionary = Data.rules.people.recruit_mix[f]
	var captain := People.generate({"mix": mix})
	captain.stats.authority = mini(20, captain.stats.authority + 3)
	var skill: Array = e.skill
	var enemy := {
		"kind": kind, "label": e.label, "faction": f, "behaviour": e.behaviour,
		"name": names[rng.randi() % names.size()], "type": type, "upgrades": upgrades,
		"hull": float(st.hull), "sails": float(st.sails),
		"crew": int(st.crew_max * rng.randf_range(e.crew_fraction[0], e.crew_fraction[1])),
		"gunnery": rng.randi_range(skill[0], skill[1]), "swordplay": rng.randi_range(skill[0], skill[1]),
		"carpentry": rng.randi_range(skill[0], skill[1]),
		"captain": captain, "captain_swordplay": People.value(captain, "swordplay"),
		"morale": float(e.morale), "gold": rng.randi_range(e.gold[0], e.gold[1]), "cargo": {},
		"roles": e.get("roles", Data.rules.crew_roles.presets.balanced).duplicate(),
	}
	var tons: float = st.cargo * rng.randf_range(e.cargo_fraction[0], e.cargo_fraction[1])
	var goods := _faction_goods(f)
	for i in rng.randi_range(1, 3):
		if goods.is_empty() or tons < 1.0:
			break
		var g: String = goods[rng.randi() % goods.size()]
		var qty := int(tons * rng.randf_range(0.3, 0.7) / Market.weight(g))
		enemy.cargo[g] = enemy.cargo.get(g, 0) + qty
		tons -= qty * Market.weight(g)
	return enemy


## A rough look through the glass: guns exact, crew estimated.
static func sighting(enemy: Dictionary, rng: RandomNumberGenerator) -> String:
	var st := ShipStats.effective(enemy.type, enemy.upgrades)
	var est := int(enemy.crew * rng.randf_range(0.8, 1.2) / 5.0) * 5
	return "%s %s, the %s. %d guns (%d-pounders), perhaps %d men aboard." % [
		Data.table("factions")[enemy.faction].adjective.capitalize(), Data.table("ships")[enemy.type].name.to_lower(),
		enemy.name, st.guns, st.gun_weight, est]


## The player's side as the combat sim needs it, drawn from the real crew.
static func player_side(s: Dictionary) -> Dictionary:
	var cap := ShipStats.captain(s)
	var crew: Array = s.crew.map(func(id): return People.person(id))
	var avg := func(skill: String) -> float:
		if crew.is_empty():
			return 0.0
		var total := 0
		for c in crew:
			total += People.value(c, skill)
		return float(total) / crew.size()
	var brave := crew.filter(func(c): return "brave" in c.traits or "bloodthirsty" in c.traits).size()
	var cowards := crew.filter(func(c): return "cowardly" in c.traits).size()
	var share := float(brave - cowards) / maxf(crew.size(), 1.0)
	var morale := 40.0 + People.value(cap, "authority") + People.value(cap, "charisma") + share * 60.0
	if s.cargo.get("food", 0.0) <= 0.0 or s.cargo.get("water", 0.0) <= 0.0:
		morale -= Data.rules.hardship.starving_morale  # starving men fight badly
	morale = clampf(morale, 10.0, 95.0)
	var preset: Dictionary = Data.rules.crew_roles.presets[s.get("roles", "balanced")]
	return {
		"name": s.name, "type": s.type, "upgrades": s.upgrades, "hull": s.hull, "sails": s.sails,
		"crew": ShipStats.headcount(s), "guns_lost": s.get("guns_lost", 0),
		"gunnery": (ShipStats.officer_skill(s, "master_gunner") + avg.call("gunnery")) / 2.0,
		"swordplay": avg.call("swordplay"), "captain_swordplay": People.value(cap, "swordplay"),
		"carpentry": ShipStats.officer_skill(s, "carpenter"),
		"morale": morale, "swivels": ShipStats.effective(s.type, s.upgrades).swivels, "behaviour": "player",
		"roles": {"sailors": preset.sailors, "gunners": preset.gunners, "marines": preset.marines},
		"flag": s.get("flag", "white"),
		"fear": s.reputation.fear,
		"party": party(s),
	}


## Your officers as a battle party: the captain and whoever holds each post, with their real skills.
static func party(s: Dictionary) -> Dictionary:
	var out := {"captain": _member(s.captain)}
	for post in s.officers:
		if People.chars.has(s.officers[post]):
			out[post] = _member(s.officers[post])
	return out


static func _member(id: String) -> Dictionary:
	var c := People.person(id)
	var m := {"name": c.name, "id": id, "skills": {}, "stats": {}}
	for k in People.SKILLS:
		m.skills[k] = People.value(c, k)
	for k in People.STATS:
		m.stats[k] = People.value(c, k)
	return m


## Writes battle damage back to the ship and buries the dead. Returns messages.
static func apply_battle(s: Dictionary, after: Dictionary, rng: RandomNumberGenerator) -> Array:
	var st := ShipStats.effective(s.type, s.upgrades)
	s.hull = maxf(0.0, after.hull)
	s.sails = minf(after.sails, st.sails * float(after.masts) / st.masts)  # lost masts are jury-rigged
	s.guns_lost = st.guns - after.guns_working
	var msgs := []
	var lost := int(round(after.casualties))
	if lost > 0:
		var saves: float = minf(0.8, ShipStats.officer_skill(s, "surgeon") * Data.rules.combat.surgeon_saves_per_point)
		var dead := int(round(lost * (1.0 - saves)))
		var names := kill_crew(s, dead, rng)
		var text := "%d of your men fell; the surgeon saved %d." % [lost, lost - dead]
		if not names.is_empty():
			text += " Among the dead: " + ", ".join(names) + "."
		msgs.append(text)
		var maimed := []  # some of the saved carry the battle with them for life
		for i in lost - dead:
			if s.crew.is_empty() or rng.randf() >= Data.rules.wounds.crew_chance:
				continue
			var c := People.person(s.crew[rng.randi() % s.crew.size()])
			var t := People.wound(c)
			if t != "":
				maimed.append("%s (%s)" % [c.name, Data.table("traits")[t].name.to_lower()])
		if not maimed.is_empty():
			msgs.append("Maimed: " + ", ".join(maimed) + ".")
	if after.get("captain_wounded", false):
		var t := People.wound(ShipStats.captain(s))
		if t != "":
			msgs.append("Your captain will carry this fight forever: %s." % Data.table("traits")[t].name.to_lower())
	for id in after.get("officer_wounds", []):
		if People.chars.has(id) and id in s.crew:
			var t := People.wound(People.person(id))
			if t != "":
				msgs.append("%s will carry a %s from this fight." % [People.person(id).name, Data.table("traits")[t].name.to_lower()])
	for id in after.get("xp", {}):  # officers learn by doing: every roll in battle counts
		if People.chars.has(id):
			for skill in after.xp[id]:
				if People.gain_xp(People.person(id), skill, after.xp[id][skill]):
					msgs.append("%s's %s improves to %d." % [People.person(id).name, People.SKILL_NAMES[skill].to_lower(), People.person(id).skills[skill]])
	return msgs


## Removes n random crew (officers included). The captain isn't killed until succession exists (milestone 8).
static func kill_crew(s: Dictionary, n: int, rng: RandomNumberGenerator) -> Array:
	var named := []
	for i in mini(n, s.crew.size()):
		var id: String = s.crew[rng.randi() % s.crew.size()]
		var post := ""
		for role in s.officers:
			if s.officers[role] == id:
				post = role
		if post != "":
			s.officers.erase(post)
			named.append("%s (%s)" % [People.person(id).name, Data.rules.officer_roles[post].name])
		elif People.person(id).traits.has("popular"):
			named.append(People.person(id).name)
		s.crew.erase(id)
		People.remove(id)
	return named


## Takes cargo from the prize into your hold, marked as stolen. Returns units taken.
static func take_cargo(s: Dictionary, enemy: Dictionary, good: String, qty: int, capacity: float, stolen := true) -> int:
	var w := Market.weight(good)
	qty = mini(qty, mini(enemy.cargo.get(good, 0), int((capacity - Market.cargo_used(s.cargo)) / w + 0.0001)))
	if qty <= 0:
		return 0
	enemy.cargo[good] -= qty
	if enemy.cargo[good] <= 0:
		enemy.cargo.erase(good)
	s.cargo[good] = s.cargo.get(good, 0) + qty
	if stolen:
		s.stolen[good] = s.stolen.get(good, 0) + qty
	return qty


## Puts a prize crew aboard and keeps the ship. Returns "" or why not.
static func take_prize(s: Dictionary, enemy: Dictionary, prize_crew: int) -> String:
	if s.prizes.size() >= Data.rules.prizes.max:
		return "You can't manage more than %d prizes." % Data.rules.prizes.max
	if prize_crew < 3 or prize_crew > s.crew.size() - s.officers.size():
		return "Not enough spare hands for a prize crew."
	var officers: Array = s.officers.values()
	var movers: Array = s.crew.filter(func(id): return not id in officers).slice(0, prize_crew)
	for id in movers:
		s.crew.erase(id)
	s.prizes.append({"type": enemy.type, "name": enemy.name, "faction": enemy.faction, "hull": maxf(1.0, enemy.hull),
		"sails": enemy.sails, "crew": movers, "cargo": enemy.cargo.duplicate()})
	return ""


static func prize_crew_needed(enemy: Dictionary) -> int:
	return maxi(3, int(ShipStats.effective(enemy.type, []).crew_min * Data.rules.prizes.crew_fraction))


## What becomes of the prisoners. Shapes honour and fear, and how each crew member feels about the captain.
static func prisoner_fate(s: Dictionary, fate: String) -> String:
	var f: Dictionary = Data.rules.prisoners.fates[fate]
	s.reputation.honour += int(f.honour)
	s.reputation.fear += int(f.fear)
	var upset := 0
	var pleased := 0
	for id in s.crew:
		var c := People.person(id)
		var delta := 0
		for t in c.traits:
			for tag in Data.table("traits")[t].get("tags", []):
				delta += int(f.tags.get(tag, 0))
			delta += int(f.tags.get(t, 0))  # fates can also name traits directly (e.g. devout)
		if delta != 0:
			c.relations[s.captain] = c.relations.get(s.captain, 0) + delta
			if delta < 0: upset += 1
			else: pleased += 1
	var text := "%s." % f.name
	if upset > 0:
		text += " %d of your crew resent it." % upset
	if pleased > 0:
		text += " %d approve." % pleased
	return text


## Crew who'd react to a fate, for the tooltip before choosing.
static func fate_reaction(s: Dictionary, fate: String) -> Dictionary:
	var f: Dictionary = Data.rules.prisoners.fates[fate]
	var out := {"upset": 0, "pleased": 0}
	for id in s.crew:
		var delta := 0
		for t in People.person(id).traits:
			for tag in Data.table("traits")[t].get("tags", []):
				delta += int(f.tags.get(tag, 0))
			delta += int(f.tags.get(t, 0))
		if delta < 0: out.upset += 1
		elif delta > 0: out.pleased += 1
	return out


## Some prisoners will sign articles. Returns how many joined.
static func recruit_prisoners(s: Dictionary, enemy: Dictionary, survivors: int, crew_max: int, rng: RandomNumberGenerator) -> int:
	var willing := int(survivors * Data.table("encounters")[enemy.kind].prisoner_willingness)
	var n := mini(willing, crew_max - ShipStats.headcount(s))
	var mix: Dictionary = Data.rules.people.recruit_mix[enemy.faction]
	for i in maxi(n, 0):
		var c := People.generate({"mix": mix})
		c.history.append("Joined from the captured %s." % enemy.name)
		s.crew.append(People.add(c))
	return maxi(n, 0)


static func ransom_value(captain: Dictionary) -> int:
	return int(People.value(captain, "authority") * Data.rules.prisoners.ransom_per_authority + 100)


## Hold the enemy captain for ransom: they become a real character, payable at a port of their nation.
static func take_hostage(s: Dictionary, enemy: Dictionary) -> void:
	var c: Dictionary = enemy.captain.duplicate(true)
	c.history.append("Captured aboard the %s." % enemy.name)
	var id := People.add(c)
	s.hostages.append({"id": id, "faction": enemy.faction, "ransom": ransom_value(c)})


## What a beaten enemy takes when you strike your colours or lose a boarding.
static func surrender_losses(s: Dictionary) -> String:
	var taken := 0.0
	for g in s.cargo.keys():
		if g != "food" and g != "water":
			taken += s.cargo[g]
			Ports.remove_cargo(s, g, s.cargo[g])
	var gold: float = floor(s.gold / 2.0)
	s.gold -= gold
	s.reputation.fear -= 2
	return "They strip your hold (%d units of cargo) and take %d gold." % [taken, gold]


static func _faction_goods(f: String) -> Array:
	var goods := []
	for id in Data.table("ports"):
		if Data.table("ports")[id].faction == f:
			for g in Data.table("ports")[id].produces:
				if not g in goods:
					goods.append(g)
	return goods if not goods.is_empty() else ["rum", "hides", "gunpowder"]


static func _weighted(table: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in table:
		total += table[k].weight
	var r := rng.randf() * total
	for k in table:
		r -= table[k].weight
		if r <= 0.0:
			return k
	return table.keys()[0]
