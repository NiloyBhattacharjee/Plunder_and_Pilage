class_name NewGame
## Builds a fresh game from the new-game screen's choices. The captain is an ordinary character
## (same model as any crew member) with a background layered on top, so anyone can succeed them later.


## cfg: {name, nationality, background, ship_name}. Returns {state, start_port}.
static func build(cfg: Dictionary) -> Dictionary:
	People.reset()
	Ports.reset()
	var bg: Dictionary = Data.table("backgrounds")[cfg.background]
	var nation: Dictionary = Data.table("nations")[cfg.nationality]
	var start_port: String = bg.get("start_port", nation.start_port)

	var cap := People.generate({"nationality": cfg.nationality})
	cap.age = 28
	cap.background = cfg.background
	if cfg.get("name", "") != "":
		cap.name = cfg.name
	for s in People.STATS:  # captains are a cut above the average hand
		cap.stats[s] = clampi(cap.stats[s] + 1 + bg.stats.get(s, 0), 0, 20)
	for s in People.SKILLS:
		cap.skills[s] = clampi(cap.skills[s] + bg.skills.get(s, 0), 0, 20)
	var extra: Array = cap.traits.filter(func(t): return not t in bg.traits and not People._conflicts(bg.traits, t))
	cap.traits = bg.traits.duplicate() + extra.slice(0, 1)
	cap.hidden = []  # you know yourself
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
		"stolen": {}, "prizes": [], "hostages": [], "guns_lost": 0,
	}
	auto_appoint(state, 7)
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
