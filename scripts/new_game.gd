class_name NewGame
## Builds a fresh game from the new-game screen's choices. The captain is an ordinary character
## (same model as any crew member) with a background layered on top, so anyone can succeed them later.


## Point-buy for a new captain: a base, the background's bonuses, and the points spent ({stats: {k: n}, skills: {k: n}}).
static func build_value(bg: Dictionary, b: Dictionary, key: String) -> int:
	var g: Dictionary = Data.rules.growth.build
	if key in People.STATS:
		return int(g.stat_base) + 1 + int(bg.stats.get(key, 0)) + int(b.get("stats", {}).get(key, 0))
	return int(g.skill_base) + int(bg.skills.get(key, 0)) + int(b.get("skills", {}).get(key, 0))


## Points left to spend: {stats, skills}. A flaw buys more skill points.
static func build_points(b: Dictionary) -> Dictionary:
	var g: Dictionary = Data.rules.growth.build
	var spent := func(d: Dictionary) -> int: return d.values().reduce(func(a, x): return a + int(x), 0)
	return {"stats": int(g.stat_points) - spent.call(b.get("stats", {})),
		"skills": int(g.skill_points) + (int(g.flaw_points) if b.get("flaw", "") != "" else 0) - spent.call(b.get("skills", {}))}


## cfg: {name, nationality, background, ship_name, build?, focus? (data/focus.json), night? (open on the background's
## "night": how you took the ship, data/events/night.json)}. Returns {state, start_port}.
static func build(cfg: Dictionary) -> Dictionary:
	People.reset()
	Bases.reset()
	Ports.reset()
	Factions.reset()
	Politics.reset()
	Bonds.reset()
	Contracts.reset()
	Events.reset()
	var bg: Dictionary = Data.table("backgrounds")[cfg.background]
	var nation: Dictionary = Data.table("nations")[cfg.nationality]
	var start_port: String = bg.get("start_port", nation.start_port)

	var cap := People.generate({"nationality": cfg.nationality})
	cap.age = 28
	cap.background = cfg.background
	if cfg.get("name", "") != "":
		cap.name = cfg.name
	if cfg.has("build"):  # you built your captain point by point
		var b: Dictionary = cfg.build
		for k in People.STATS + People.SKILLS:
			var v := build_value(bg, b, k)
			if k in People.STATS:
				cap.stats[k] = v
			else:
				cap.skills[k] = v
		cap.traits = bg.traits.duplicate() + b.get("traits", []).filter(func(x): return not x in bg.traits)
		if b.get("flaw", "") != "":
			cap.traits.append(b.flaw)
		if b.has("portrait"):
			cap.portrait = b.portrait.duplicate(true)
	else:
		for s in People.STATS:  # captains are a cut above the average hand
			cap.stats[s] = clampi(cap.stats[s] + 1 + bg.stats.get(s, 0), 0, 20)
		for s in People.SKILLS:
			cap.skills[s] = clampi(cap.skills[s] + bg.skills.get(s, 0), 0, 20)
		var extra: Array = cap.traits.filter(func(t): return not t in bg.traits and not People._conflicts(bg.traits, t))
		cap.traits = bg.traits.duplicate() + extra.slice(0, 1)
	cap.hidden = []  # you know yourself
	cap.focus = cfg.get("focus", "")
	cap.history.append("Took command, %s." % Clock.date_string())
	var cap_id := People.add(cap)

	var mix: Dictionary = Data.rules.people.recruit_mix[Ports.port(start_port).faction]
	var crew := []
	for i in bg.crew:
		crew.append(People.add(People.generate({"mix": mix})))

	var relations := {}
	for f in Data.table("factions"):
		relations[f] = 0
	for key in bg.relations:
		var f: String = nation.faction if key == "own" else key
		if f != "":
			relations[f] += int(bg.relations[key])

	var stats := ShipStats.effective(bg.ship, [])
	var names: Array = Data.rules.ship_names
	var state := {
		"type": bg.ship, "name": cfg.get("ship_name", "") if cfg.get("ship_name", "") != "" else names[People.rng.randi() % names.size()],
		"hull": float(stats.hull), "sails": float(stats.sails), "fouling": 0.0, "upgrades": [],
		"captain": cap_id, "crew": crew, "officers": {},
		"gold": float(bg.gold), "wages_owed": 0.0,
		"cargo": Data.rules.start.cargo.duplicate(), "cargo_cost": {},
		"relations": relations,
		"reputation": {"honour": 0, "fear": 0, "notoriety": 0},
		"stolen": {}, "prizes": [], "hostages": [], "guns_lost": 0, "roles": "balanced",
		"flag": Data.table("factions")[nation.faction].flag if nation.faction != "" else "white",
		"career": {"pirate": false, "marque": "", "service": 0.0, "rank": 0, "crown_debt": 0.0, "pardoned_by": []},
	}
	auto_appoint(state, 7)
	for id in state.officers.values():  # your officers each want something
		Wants.ensure(People.person(id), People.rng)
	Crew.ensure(state)
	state.secrets = []
	state.bonds = {}
	state.ironman = cfg.get("ironman", false)
	state.tutorial = cfg.get("tutorial", false)
	if cfg.get("night", false):
		state.night = bg.get("night", "")  # played before anything else (WorldMap._play_night)
	return {"state": state, "start_port": start_port}


## Appoints the best available hand to each empty officer post, if they're at least `min_skill` at it.
static func auto_appoint(state: Dictionary, min_skill: int) -> void:
	for role in Data.rules.officer_roles:
		if state.officers.has(role):
			continue
		var id := best_for(state, role)
		if id != "" and People.value(People.person(id), Data.rules.officer_roles[role].skill) >= min_skill:
			state.officers[role] = id


## Best crew member for a post who doesn't already hold one.
static func best_for(state: Dictionary, role: String) -> String:
	var skill: String = Data.rules.officer_roles[role].skill
	var taken: Array = state.officers.values()
	var best := ""
	for id in state.crew:
		if id in taken:
			continue
		if best == "" or People.value(People.person(id), skill) > People.value(People.person(best), skill):
			best = id
	return best
