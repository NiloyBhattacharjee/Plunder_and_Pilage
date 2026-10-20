extends Node
## Autoload "People": every named character in one registry, all on the same model:
## the captain, crew and officers now; governors, officials, rivals and council captains later.
## Characters are plain dictionaries, so saving is trivial:
##   {id, name, nationality, age, background,
##    stats:  {authority, experience, intimidation, charisma}     0-20, the leadership stats
##    skills: {seamanship, navigation, gunnery, swordplay, trade, carpentry, medicine}  0-20
##    xp:     {skill: progress toward the next level}
##    traits: [trait ids], hidden: [trait ids the player hasn't discovered yet],
##    relations: {other id: -100..100}, history: [text]}
## Traits change numbers even while hidden; the player just sees "unknown" in the breakdown.

const STATS := ["authority", "experience", "intimidation", "charisma"]
const SKILLS := ["seamanship", "navigation", "gunnery", "swordplay", "trade", "carpentry", "medicine"]
const SKILL_NAMES := {"seamanship": "Seamanship", "navigation": "Navigation", "gunnery": "Gunnery",
	"swordplay": "Swordplay", "trade": "Trade", "carpentry": "Carpentry", "medicine": "Medicine",
	"authority": "Authority", "experience": "Experience", "intimidation": "Intimidation", "charisma": "Charisma"}

var chars := {}
var next_id := 1
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	Clock.day_passed.connect(func(_d):
		var d := Clock.date()
		if d.month == 1 and d.day == 1:
			for id in chars:
				chars[id].age += 1)


func person(id: String) -> Dictionary:
	return chars[id]


func add(c: Dictionary) -> String:
	c.id = "c%d" % next_id
	next_id += 1
	chars[c.id] = c
	return c.id


func remove(id: String) -> void:
	chars.erase(id)


func reset() -> void:
	chars = {}
	next_id = 1


## Random character. opts: nationality, mix ({nationality: weight}), pool ("crew"/"official"),
## bonus ({skills: {skill: +n}, traits: {trait: chance}}: what a particular port's hands are like).
func generate(opts := {}) -> Dictionary:
	var cfg: Dictionary = Data.rules.people
	var nat: String = opts.get("nationality", _weighted(opts.get("mix", {"english": 1})))
	var nation: Dictionary = Data.table("nations")[nat]
	var age := rng.randi_range(16, 50)
	var c := {
		"name": "%s %s" % [_pick(nation.first), _pick(nation.last)],
		"nationality": nat, "age": age, "background": "",
		"stats": {}, "skills": {}, "xp": {}, "traits": [], "hidden": [], "relations": {}, "history": [],
	}
	for s in STATS:
		c.stats[s] = _roll(cfg.stat_mean, cfg.stat_spread)
	c.stats.experience = clampi(c.stats.experience + int((age - 25) / 5.0), 0, 20)  # older hands have seen more
	for s in SKILLS:
		c.skills[s] = _roll(cfg.skill_mean, cfg.skill_spread)
		c.xp[s] = 0.0
	c.skills.seamanship = mini(20, c.skills.seamanship + cfg.seamanship_bonus)
	var specialty: String = _pick(SKILLS)  # most hands are good at one thing
	c.skills[specialty] = mini(20, c.skills[specialty] + cfg.specialty_bonus)

	var bonus: Dictionary = opts.get("bonus", {})
	for sk in bonus.get("skills", {}):
		c.skills[sk] = mini(20, c.skills[sk] + int(bonus.skills[sk]))
	for t in bonus.get("traits", {}):
		if rng.randf() < bonus.traits[t] and not _conflicts(c.traits, t):
			c.traits.append(t)
	c.portrait = {"seed": rng.randi()}  # rebuilds the same face after loading

	var pool: String = opts.get("pool", "crew")
	var candidates := Data.table("traits").keys().filter(func(t): return pool in Data.table("traits")[t].pools)
	for i in rng.randi_range(cfg.traits[0], cfg.traits[1]):
		var t: String = _pick(candidates)
		if not t in c.traits and not _conflicts(c.traits, t) and c.traits.size() < 3:
			c.traits.append(t)
			if rng.randf() < Data.table("traits")[t].get("hidden_chance", 0.0):
				c.hidden.append(t)
	return c


## Effective value of a stat or skill: base plus every trait's modifier (hidden ones too), 0..20.
func value(c: Dictionary, key: String) -> int:
	var v: int = c.stats[key] if key in STATS else c.skills[key]
	for t in c.traits:
		v += Data.table("traits")[t].get("effects", {}).get(key, 0)
	return clampi(v, 0, 20)


## Tooltip text: where a stat or skill comes from. Undiscovered traits are lumped together as "unknown".
func breakdown(c: Dictionary, key: String) -> String:
	var base: int = c.stats[key] if key in STATS else c.skills[key]
	var lines := PackedStringArray(["%s %d" % [SKILL_NAMES[key], value(c, key)], "Base: %d" % base])
	var unknown := 0
	for t in c.traits:
		var mod: int = Data.table("traits")[t].get("effects", {}).get(key, 0)
		if mod == 0:
			continue
		if t in c.hidden:
			unknown += mod
		else:
			lines.append("%s: %+d" % [Data.table("traits")[t].name, mod])
	if unknown != 0:
		lines.append("Something you don't know about them: %+d" % unknown)
	if key in SKILLS and value(c, key) < 20:
		lines.append("Progress to next level: %d / %d" % [c.xp.get(key, 0.0), xp_needed(c.skills[key])])
	lines.append("")
	lines.append(effect_text(key, value(c, key)))
	return "\n".join(lines)


## What a stat or skill does, and how much: "Charisma 12 is +1 on a d20 roll. Battle: Rally the crew..."
func effect_text(key: String, score := -1) -> String:
	var out := ""
	if score >= 0:
		out = "%s %d is %+d on a d20 roll. " % [SKILL_NAMES[key], score, Dice.mod(score)]
	out += Data.rules.people.skill_effects[key]
	var n := check_count(key)
	return out + ("\nRolled in %d event choices." % n if n > 0 else "")


var _checks := {}

## How many event choices roll this stat or skill.
func check_count(key: String) -> int:
	if _checks.is_empty():
		for id in Events.events:
			for ch in Events.events[id].get("choices", []):
				var k: String = ch.get("check", {}).get("skill", "")
				if k != "":
					_checks[k] = _checks.get(k, 0) + 1
		_checks[""] = 0  # marks it counted, even with no events loaded
	return _checks.get(key, 0)


func xp_needed(level: int) -> int:
	return int(Data.rules.people.xp_per_level) * (level + 1)


## Skills improve with use. Returns true if the skill went up a level.
func gain_xp(c: Dictionary, skill: String, amount: float) -> bool:
	if Growth.has_perk(c, "quick_study"):
		amount *= 1.5
	Growth.add_xp(c, amount)
	c.xp[skill] = c.xp.get(skill, 0.0) + amount
	var levelled := false
	while c.skills[skill] < 20 and c.xp[skill] >= xp_needed(c.skills[skill]):
		c.xp[skill] -= xp_needed(c.skills[skill])
		c.skills[skill] += 1
		levelled = true
	return levelled


## Reveals one hidden trait. Returns its id, or "" if they have no secrets left.
func reveal_trait(c: Dictionary) -> String:
	if c.hidden.is_empty():
		return ""
	var t: String = c.hidden.pop_at(rng.randi() % c.hidden.size())
	return t


## A lasting wound: scar, lost eye, leg or hand. Returns the trait id, or "" if they've had them all.
func wound(c: Dictionary) -> String:
	var options: Array = Data.rules.wounds.traits.filter(func(t): return not t in c.traits)
	if options.is_empty():
		return ""
	var t: String = options[rng.randi() % options.size()]
	c.traits.append(t)
	c.history.append("Wounded: %s, %s." % [Data.table("traits")[t].name.to_lower(), Clock.date_string()])
	return t


func known_traits(c: Dictionary) -> Array:
	return c.traits.filter(func(t): return not t in c.hidden)


func has_trait(c: Dictionary, t: String) -> bool:
	return t in c.traits


func trait_names(c: Dictionary) -> String:
	var names := known_traits(c).map(func(t): return Data.table("traits")[t].name)
	if not c.hidden.is_empty():
		names.append("?")
	return ", ".join(names) if not names.is_empty() else "-"


## How likely the crew would follow this person: used to spot possible successors (milestone 8).
func leadership(c: Dictionary) -> int:
	return value(c, "authority") + value(c, "charisma") + value(c, "experience")


func describe(c: Dictionary) -> String:
	var lines := PackedStringArray(["%s, %s, age %d" % [c.name, Data.table("nations")[c.nationality].name, c.age]])
	lines.append("Authority %d  Experience %d  Intimidation %d  Charisma %d" % [
		value(c, "authority"), value(c, "experience"), value(c, "intimidation"), value(c, "charisma")])
	var best := SKILLS.duplicate()
	best.sort_custom(func(a, b): return value(c, a) > value(c, b))
	lines.append("Best at: %s %d, %s %d" % [SKILL_NAMES[best[0]], value(c, best[0]), SKILL_NAMES[best[1]], value(c, best[1])])
	lines.append("Traits: " + trait_names(c))
	if Wants.describe(c) != "":
		lines.append(Wants.describe(c))
	return "\n".join(lines)


func save_state() -> Dictionary:
	return {"chars": chars, "next_id": next_id, "rng": str(rng.state)}


func load_state(d: Dictionary) -> void:
	chars = d.chars
	next_id = d.next_id
	rng.state = int(d.rng)


func _conflicts(traits: Array, t: String) -> bool:
	var tt: Dictionary = Data.table("traits")
	for other in traits:
		if tt[t].get("opposite", "") == other or tt[other].get("opposite", "") == t:
			return true
	return false


func _roll(mean: float, spread: float) -> int:
	return clampi(int(round(rng.randfn(mean, spread))), 0, 20)


func _pick(arr: Array) -> Variant:
	return arr[rng.randi() % arr.size()]


func _weighted(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[-1]
