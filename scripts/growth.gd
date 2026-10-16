class_name Growth
## Characters grow. Every bit of experience a skill earns by use also counts toward the character's level; each
## level brings a point to put into any skill or stat, and every few levels a perk (data/perks.json). You choose for
## the captain and officers; ordinary hands spend their points on their own, on what they're already good at.


static func cfg() -> Dictionary:
	return Data.rules.growth


static func level(c: Dictionary) -> int:
	return int(c.get("level", 1))


static func xp_to_next(c: Dictionary) -> int:
	return int(cfg().xp_per_level) * level(c)


## Adds level experience. Returns true on a level-up.
static func add_xp(c: Dictionary, amount: float) -> bool:
	c.lxp = c.get("lxp", 0.0) + amount
	var up := false
	while level(c) < int(cfg().max_level) and c.lxp >= xp_to_next(c):
		c.lxp -= xp_to_next(c)
		c.level = level(c) + 1
		c.points = int(c.get("points", 0)) + 1
		if level(c) % int(cfg().perk_every) == 0:
			c.perk_picks = int(c.get("perk_picks", 0)) + 1
		up = true
	return up


static func can_raise(c: Dictionary, key: String) -> String:
	if int(c.get("points", 0)) <= 0:
		return "No points to spend."
	var base: int = c.stats[key] if key in People.STATS else c.skills[key]
	if base >= int(cfg().max_skill):
		return "Already at the most it can be."
	return ""


static func raise(c: Dictionary, key: String) -> void:
	if can_raise(c, key) != "":
		return
	if key in People.STATS:
		c.stats[key] += 1
	else:
		c.skills[key] += 1
	c.points -= 1


static func has_perk(c: Dictionary, id: String) -> bool:
	return id in c.get("perks", [])


## Perks this character could take now: not taken, and the needs met.
static func perks_open(c: Dictionary) -> Array:
	var out := []
	for id in Data.table("perks"):
		if id.begins_with("_") or has_perk(c, id):
			continue
		var p: Dictionary = Data.table("perks")[id]
		if p.needs.keys().all(func(k): return People.value(c, k) >= int(p.needs[k])):
			out.append(id)
	return out


static func perk_needs_text(id: String) -> String:
	var p: Dictionary = Data.table("perks")[id]
	return "none" if p.needs.is_empty() else ", ".join(p.needs.keys().map(func(k): return "%s %d" % [People.SKILL_NAMES[k], p.needs[k]]))


static func take_perk(c: Dictionary, id: String) -> void:
	if int(c.get("perk_picks", 0)) <= 0 or not id in perks_open(c):
		return
	c.perks = c.get("perks", []) + [id]
	c.perk_picks -= 1


## Ordinary hands put their points into their best skill and take the first perk they can.
static func auto_spend(c: Dictionary) -> void:
	while int(c.get("points", 0)) > 0:
		var best := ""
		for k in People.SKILLS:
			if can_raise(c, k) == "" and (best == "" or c.skills[k] > c.skills[best]):
				best = k
		if best == "":
			break
		raise(c, best)
	while int(c.get("perk_picks", 0)) > 0 and not perks_open(c).is_empty():
		take_perk(c, perks_open(c)[0])


## One line for tooltips and sheets.
static func summary(c: Dictionary) -> String:
	var bits := ["Level %d (%d / %d to the next)" % [level(c), c.get("lxp", 0.0), xp_to_next(c)]]
	if int(c.get("points", 0)) > 0:
		bits.append("%d point%s to spend" % [c.points, "" if c.points == 1 else "s"])
	if int(c.get("perk_picks", 0)) > 0:
		bits.append("a perk to choose")
	if not c.get("perks", []).is_empty():
		bits.append("perks: " + ", ".join(c.perks.map(func(p): return Data.table("perks")[p].name)))
	return ". ".join(bits)
