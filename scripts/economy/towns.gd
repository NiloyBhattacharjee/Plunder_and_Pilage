class_name Towns
extends RefCounted
## Living towns (data/economy.json "towns"): each port's people change. Plantation towns grow with the sugar
## trade, and most of the newcomers are enslaved people the slave ships bring to work the cane; capitals and free
## ports grow with trade in peace; a war stops the settlers coming. Fever, hurricanes, sacks and earthquakes take
## people away (the "population" effect), and a town that lost people slowly fills again. A pirate haven swells
## with the companies that use it. A town's people set what it eats and makes (EconomyModel._params), how many
## ships sail from it (Traffic), the taxes and the rebels of a town you hold (Bases).
## The port data's population is the live figure (like Ports.change_owner's faction); orig_population keeps
## the data's, so a new game starts from it.

var m: EconomyModel
var settled := {}  # port -> people living there (pirates ashore come on top)
var losses := {}   # port -> [{day (model day), n, why}]: the blows it took, newest last


func _init(model: EconomyModel) -> void:
	m = model
	for id in m.ports:
		if id.begins_with("_"):
			continue
		var p: Dictionary = m.ports[id]
		if not p.has("orig_population"):
			p.orig_population = p.population
		p.population = p.orig_population
		settled[id] = float(p.orig_population)
		losses[id] = []


func cfg() -> Dictionary:
	return m.cfg.get("towns", {})


## The people working the town against what the data gave it: its trades scale with them.
func labour(id: String) -> float:
	return settled.get(id, 1.0) / float(m.ports[id].get("orig_population", m.ports[id].population))


## Growth a year, as parts: [[why, rate]]. Empty without a "towns" config.
func growth_parts(id: String) -> Array:
	var c := cfg()
	if c.is_empty():
		return []
	var p: Dictionary = m.ports[id]
	var parts := [["Births and newcomers", float(c.growth.default)]]
	for t in p.tags:
		if c.growth.has(t):
			parts.append([c.why[t], float(c.growth[t])])
	var orig := float(p.orig_population)
	if settled[id] < orig:  # those who fled come back, and the empty houses draw others
		parts.append(["Filling up again after its losses", float(c.regrow) * (1.0 - settled[id] / orig)])
	var arrivals: float = parts.reduce(func(a, x): return a + maxf(0.0, x[1]), 0.0)
	if m.traffic.wars.any(func(w): return p.faction in w):
		parts.append(["At war: few settlers sail", -arrivals * float(c.war_cut)])
	var sail := m.world_mult("sailings:" + id) * m.world_mult("sailings:" + p.faction)
	if sail < 1.0:
		parts.append(["Few ships put in", -arrivals * (1.0 - sail)])
	return parts


func growth(id: String) -> float:
	return growth_parts(id).reduce(func(a, x): return a + x[1], 0.0)


## Once a week: every town grows or shrinks a little, havens fill with pirates, and the trades follow.
func week() -> void:
	var c := cfg()
	if c.is_empty():
		return
	var ashore := {}
	for co in m.brethren.companies:
		if co.haven != "" and not co.away:
			ashore[co.haven] = ashore.get(co.haven, 0.0) + co.men * float(c.haven_ashore)
	for id in settled:
		var orig := float(m.ports[id].orig_population)
		settled[id] = clampf(settled[id] * (1.0 + growth(id) / 52.0), orig * float(c.limits[0]), orig * float(c.limits[1]))
		m.ports[id].population = int(round(settled[id] + ashore.get(id, 0.0)))
		m.refresh(id)


## A blow: fever, a hurricane, a sack. mult: the share of the people left.
func lose(id: String, mult: float, why: String) -> void:
	if not settled.has(id):
		return
	var n: float = settled[id] * (1.0 - clampf(mult, 0.0, 1.0))
	settled[id] -= n
	m.ports[id].population = maxi(0, int(round(m.ports[id].population - n)))
	losses[id].append({"day": m.day, "n": int(round(n)), "why": why})
	if losses[id].size() > int(cfg().get("keep", 5)):
		losses[id].pop_front()
	m.refresh(id)


func save_state() -> Dictionary:
	var pop := {}
	for id in settled:
		pop[id] = m.ports[id].population
	return {"settled": settled, "losses": losses, "population": pop}


func load_state(d: Dictionary) -> void:
	for id in d.get("settled", {}):
		if settled.has(id):
			settled[id] = float(d.settled[id])
			m.ports[id].population = int(d.population.get(id, settled[id]))
			losses[id] = d.losses.get(id, [])
			m.refresh(id)
