extends Node
## Autoload "Events": the event engine. Events are data, in res://data/events/*.json (any number of files,
## so content can be added in batches). Each event has conditions, roles (variables bound when it fires:
## a crew member with a trait, a port, a nation, a good, an amount), a weight, and 1-4 choices.
## Choices can have conditions, a skill check, and outcomes. Outcomes can queue follow-up events (chains).
##
## Conditions are short strings:  "gold >= 200", "pirate", "not flag.met_morgan", "relation.spain < -20",
##   "cargo.rum >= 10", "captain.charisma >= 12", "war.england.spain", "port_faction == pirates".
## Outcomes are short strings:  "gold +200", "gold -10%", "crew -2", "opinion {drunk} -5", "relation {nation} +5",
##   "cargo {good} -all", "flag met_morgan", "event treasure_dig 0 120", "fight pirate pirates".
## {name} is replaced by the role's id in conditions and outcomes, and by its display name in texts.
## See docs/events.md for the full list. validate() checks every event at startup.

const DIR := "res://data/events/"
const VERBS := {  # verb: [min args, max args]
	"gold": [1, 1], "crew": [1, 1], "kill": [1, 1], "wound": [1, 1], "hire": [1, 1], "leave": [1, 1],
	"opinion": [2, 2], "relation": [2, 2], "honour": [1, 1], "fear": [1, 1], "notoriety": [1, 1],
	"cargo": [2, 2], "loot": [2, 2], "food": [1, 1], "water": [1, 1], "hull": [1, 1], "sails": [1, 1], "wages": [1, 1], "paywages": [0, 0],
	"skill": [3, 3], "trait": [2, 2], "untrait": [2, 2], "reveal": [1, 1],
	"flag": [1, 2], "unflag": [1, 1], "abandon": [1, 1],
	"favour": [2, 2], "secret": [1, 3], "influence": [3, 3], "stir": [1, 1], "scandal": [1, 1], "council_vote": [2, 2], "join_council": [0, 0],
	"bond": [2, 2], "rivalry": [2, 2], "strain": [1, 1], "betray": [1, 1], "peace": [1, 1], "own_ship": [2, 2],
	"reveal_cove": [0, 0], "intel": [1, 1], "base_gold": [2, 2], "base_loyalty": [2, 2], "base_visibility": [2, 2], "base_store": [3, 3],
	"base_garrison": [2, 2], "base_damage": [1, 1], "base_lost": [1, 1],
	"patrols": [2, 2], "town": [2, 2], "supply": [2, 2], "settle": [1, 1], "marque": [1, 1], "morale": [2, 2], "calm": [1, 1], "expose": [0, 0], "mutiny": [0, 0], "depose": [0, 0], "share": [1, 1], "confidence": [0, 0], "event": [1, 3], "fight": [1, 3], "market": [2, 2], "time": [1, 1],
}
const SOURCES := ["crew", "officer", "captain", "new", "port", "here", "nation", "enemy", "good", "number", "ringleader",
	"official", "creditor", "enemy_official", "council", "ally", "rival", "captain_npc", "base"]

var events := {}
var errors := PackedStringArray()
var fired := {}      # event id -> day it last fired
var flags := {}      # flag -> day it expires (-1: never)
var queue: Array = []  # [{id, at, until, vars}]
var rng := RandomNumberGenerator.new()


func _init() -> void:
	for file in DirAccess.get_files_at(DIR):
		if not file.ends_with(".json"):
			continue
		var batch := Data.read_json(DIR + file)
		for id in batch:
			if id.begins_with("_"):
				continue
			if events.has(id):
				errors.append("%s: event '%s' is defined twice" % [file, id])
			var ev: Dictionary = batch[id]
			ev.id = id
			ev.category = ev.get("category", file.get_basename())
			events[id] = ev
	errors.append_array(validate())
	for e in errors:
		push_error("Events: " + e)


func _ready() -> void:
	rng.randomize()


func reset() -> void:
	fired = {}
	flags = {}
	queue = []


static func cfg() -> Dictionary:
	return Data.rules.events


# ---- choosing an event ---------------------------------------------------------

## ctx: {s: ship state, stats: ship stats, port: anchored port id or "", storm: bool}.
## Returns an instance {id, vars} for `where` ("sea" or "port"), or {}.
func pick(where: String, ctx: Dictionary) -> Dictionary:
	var today := Clock.day
	for e in flags.keys():
		if flags[e] >= 0 and flags[e] < today:
			flags.erase(e)
	for q in queue.duplicate():  # chains first: they wait until their moment comes
		if today > q.until:
			queue.erase(q)
		elif today >= q.at and _fits(events[q.id], where):
			var inst := _instance(events[q.id], ctx, q.vars)
			if not inst.is_empty():
				queue.erase(q)
				return _materialize(inst, ctx)
	for ev in events.values():  # historical moments fire as soon as they can
		if ev.get("priority", false) and _eligible(ev, where):
			var inst := _instance(ev, ctx, {})
			if not inst.is_empty():
				return _materialize(inst, ctx)
	var chance: float = cfg().sea_daily_chance if where == "sea" else cfg().port_chance
	if rng.randf() >= chance:
		return {}
	var inst := _draw(where, ctx)
	return _materialize(inst, ctx) if not inst.is_empty() else {}


## Something to put on the map for the player to find (an event with a "find" key), not yet happening:
## its new faces are made when it's reached. `exclude`: events already out there.
func pick_find(ctx: Dictionary, exclude := []) -> Dictionary:
	return _draw("find", ctx, exclude)


## A particular event, bound to the situation now (for finds placed by the world: wreckage after a battle).
func instance_of(id: String, ctx: Dictionary) -> Dictionary:
	return _instance(events[id], ctx, {}) if events.has(id) else {}


## A weighted pick among the events that could happen here now.
func _draw(where: String, ctx: Dictionary, exclude := []) -> Dictionary:
	var pool := []
	var total := 0.0
	for ev in events.values():
		if ev.get("priority", false) or not _eligible(ev, where) or ev.id in exclude:
			continue
		var inst := _instance(ev, ctx, {})
		if inst.is_empty():
			continue
		var w: float = ev.get("weight", 10.0)
		for wm in ev.get("weight_mods", []):
			if test(wm[0], ctx, _with_builtins(inst.vars, ctx)):
				w *= wm[1]
		pool.append([inst, w])
		total += w
	var r := rng.randf() * total
	for p in pool:
		r -= p[1]
		if r <= 0.0:
			return p[0]
	return {}


## New faces are only created for the event that actually happens.
func materialize(inst: Dictionary, ctx: Dictionary) -> Dictionary:
	return _materialize(inst, ctx)


func _materialize(inst: Dictionary, ctx: Dictionary) -> Dictionary:
	var roles: Dictionary = events[inst.id].get("roles", {})
	for name in roles:
		if roles[name].from == "new" and str(inst.vars[name]) == "@new":
			var f := _sub(roles[name].get("nation", ""), inst.vars, false)  # a stranger from a nation the event named
			if not Data.rules.people.recruit_mix.has(f):
				f = Ports.port(ctx.port).faction if ctx.port != "" else "pirates"
			var mix: Dictionary = Data.rules.people.recruit_mix[f]
			var c := People.generate({"mix": mix, "pool": roles[name].get("pool", "crew")})
			if roles[name].has("name"):  # a historical figure
				c.name = roles[name].name
				c.traits = roles[name].get("traits", c.traits).duplicate()
				c.hidden = []
			c.history.append("Met %s, %s." % ["in " + Ports.port(ctx.port).name if ctx.port != "" else "at sea", Clock.date_string()])
			inst.vars[name] = People.add(c)
	return inst


func _fits(ev: Dictionary, where: String) -> bool:
	if ev.has("find"):  # waits on the map to be sailed to
		return where == "find"
	var w: String = ev.get("where", "sea")
	return w == "any" or w == where


func _eligible(ev: Dictionary, where: String) -> bool:
	if ev.get("chain_only", false) or not _fits(ev, where):
		return false
	if fired.has(ev.id):
		if ev.get("once", false):
			return false
		if Clock.day - fired[ev.id] < ev.get("cooldown", cfg().cooldown_days):
			return false
	return true


## Binds the roles and checks the conditions. {} if the event can't happen now.
func _instance(ev: Dictionary, ctx: Dictionary, given: Dictionary) -> Dictionary:
	var vars := given.duplicate()
	for name in ev.get("roles", {}):
		if vars.has(name):
			if ev.roles[name].from in ["crew", "officer", "captain", "new"] and not People.chars.has(str(vars[name])):
				return {}  # someone the chain was about has died or left
			continue
		var v = _bind(ev.roles[name], ctx, vars)
		if v == null:
			return {}
		vars[name] = v
	var full := _with_builtins(vars, ctx)
	for c in ev.get("conditions", []):
		if not test(c, ctx, full):
			return {}
	return {"id": ev.id, "vars": vars}


## {port} means the port you're in, unless the event has its own role called port.
static func _with_builtins(vars: Dictionary, ctx: Dictionary) -> Dictionary:
	var out := vars.duplicate()
	if not out.has("port") and ctx.port != "":
		out.port = ctx.port
	return out


func _bind(spec: Dictionary, ctx: Dictionary, vars: Dictionary) -> Variant:
	var s: Dictionary = ctx.s
	var cands: Array = []
	match spec.from:
		"crew": cands = s.crew.duplicate()
		"officer": cands = s.officers.values().filter(func(id): return People.chars.has(id))
		"captain": cands = [s.captain]
		"ringleader": cands = [s.unrest.leader] if s.unrest.leader in s.crew else []
		"official": cands = Politics.officials_at(ctx.port) if ctx.port != "" else []
		"creditor": cands = Politics.creditors(s)
		"enemy_official": cands = Politics.enemies(s)
		"council": cands = Politics.council_members()
		"ally": cands = Bonds.allies(s).filter(func(k): return not k.begins_with("f:"))
		"rival": cands = Bonds.rivals(s).filter(func(k): return not k.begins_with("f:"))
		"captain_npc": cands = Bonds.roster()
		"base": cands = Bases.bases.keys()
		"here": cands = [ctx.port] if ctx.port != "" else []
		"port": cands = Ports.state.keys()
		"nation": cands = Career.nations()
		"enemy": cands = Career.nations().filter(func(f): return Factions.at_war(f, _home(s)) or Factions.at_war(f, s.career.marque))
		"good": cands = Data.table("goods").keys().filter(func(g): return g != "food" and g != "water")
		"number": return rng.randi_range(int(spec.range[0]), int(spec.range[1]))
		"new": return "@new"
	cands = cands.filter(func(x): return not x in vars.values() and spec.get("where", []).all(func(w): return test_candidate(w, x, ctx, vars)))
	if cands.is_empty():
		return null
	return cands[rng.randi() % cands.size()]


# ---- conditions ----------------------------------------------------------------

## True if the condition holds for the player's situation.
func test(cond: String, ctx: Dictionary, vars: Dictionary) -> bool:
	return _compare(_sub(cond, vars, false), func(key): return value(key, ctx))


## True if the condition holds for a role candidate (a character, port, nation or good).
## Keys that don't describe the candidate fall through to the player's situation.
func test_candidate(cond: String, cand: Variant, ctx: Dictionary, vars: Dictionary) -> bool:
	return _compare(_sub(cond, vars, false), func(key): return _cand_value(key, cand, ctx))


func _compare(cond: String, get_value: Callable) -> bool:
	var neg := cond.begins_with("not ")
	var parts := cond.trim_prefix("not ").split(" ", false)
	var v = get_value.call(parts[0])
	var ok: bool
	if parts.size() == 1:
		ok = bool(v)
	else:
		var want: String = parts[2]
		if v is String or v is StringName:
			match parts[1]:
				"==": ok = v == want
				"!=": ok = v != want
				"<": ok = v < want
				">": ok = v > want
				"<=": ok = v <= want
				">=": ok = v >= want
		else:
			var a := float(v)
			var b := float(want)
			match parts[1]:
				"==": ok = is_equal_approx(a, b)
				"!=": ok = not is_equal_approx(a, b)
				"<": ok = a < b
				">": ok = a > b
				"<=": ok = a <= b
				">=": ok = a >= b
	return ok != neg


## The player's situation, by key. Unknown keys are caught by validate().
func value(key: String, ctx: Dictionary) -> Variant:
	var s: Dictionary = ctx.s
	var head := key.get_slice(".", 0)
	var rest := key.substr(head.length() + 1)
	match head:
		"town": return PortLife.situation(ctx.port).get(rest, 0.0) if ctx.get("port", "") != "" else 0.0  # what the port is like
		"life": return PortLife.is_on(ctx.get("port", ""), rest)  # what's going on there
		"gold": return s.gold
		"crew": return ShipStats.headcount(s)
		"hull": return s.hull / ctx.stats.hull * 100.0
		"sails": return s.sails / ctx.stats.sails * 100.0
		"notoriety", "honour", "fear": return s.reputation[head]
		"loyalty": return loyalty(s)
		"food", "water": return s.cargo.get(head, 0.0) / maxf(1.0, ShipStats.headcount(s) * Data.rules.upkeep[head + "_per_crew"])
		"wages_owed": return s.wages_owed
		"prizes": return s.prizes.size()
		"hostages": return s.hostages.size()
		"contracts": return Contracts.active.size()
		"year": return Clock.date().year
		"month": return Clock.date().month
		"date":
			var d := Clock.date()
			return "%04d-%02d-%02d" % [d.year, d.month, d.day]
		"guns": return ctx.stats.guns
		"stolen": return s.stolen.values().reduce(func(a, b): return a + b, 0.0)
		"cargo": return s.cargo.get(rest, 0.0)
		"relation": return s.relations.get(_faction(rest, ctx), 0)
		"captain": return People.value(ShipStats.captain(s), rest)
		"captain_trait": return rest in ShipStats.captain(s).traits
		"has_officer": return s.officers.has(rest)
		"at_sea": return ctx.port == ""
		"in_port": return ctx.port != ""
		"storm": return ctx.get("storm", false)
		"pirate": return s.career.pirate
		"privateer": return s.career.marque != ""
		"honest": return not s.career.pirate and s.career.marque == ""
		"wanted": return Career.wanted(s)
		"marque": return s.career.marque
		"home": return _home(s)
		"pardoned": return not s.career.pardoned_by.is_empty()
		"pardon_open": return rest in Factions.pardons
		"war": return Factions.at_war(_faction(rest.get_slice(".", 0), ctx), _faction(rest.get_slice(".", 1), ctx))
		"flag": return flags.has(rest)
		"contract": return Contracts.active.any(func(c): return c.template == rest and c.status == "active")
		"ship": return s.type
		"port": return ctx.port
		"port_faction": return Ports.port(ctx.port).faction if ctx.port != "" else ""
		"port_fence": return ctx.port != "" and Ports.port(ctx.port).get("fence", false)
		"port_is": return ctx.port != "" and Ports.port(ctx.port).faction == _faction(rest, ctx)
		"morale": return Crew.morale(s, ctx.stats).value
		"unrest": return s.unrest.stage
		"unrest_known": return s.unrest.known
		"sick": return Crew.sick_count(s)
		"shares": return s.articles.pay == "shares"
		"crew_share": return s.articles.crew_share * 100.0
		"owes": return Politics.creditors(s).size()
		"allies": return Bonds.allies(s).size()
		"rivals": return Bonds.rivals(s).size()
		"neutral": return Bonds.neutral(s)
		"bases": return Bases.bases.size()
		"at_base": return ctx.get("base", "") != ""
		"secrets": return s.get("secrets", []).size()
		"council_member": return s.get("council_member", false)
		"council_leader": return Politics.council_leader == "player"
		"power": return Politics.power(ctx.port).get(rest, 0.0) if ctx.port != "" else 0.0
		"true": return true
	return null


func _cand_value(key: String, cand: Variant, ctx: Dictionary) -> Variant:
	var head := key.get_slice(".", 0)
	var rest := key.substr(head.length() + 1)
	var id := str(cand)
	if People.chars.has(id):
		var c := People.person(id)
		match head:
			"trait": return rest in c.traits
			"known_trait": return rest in People.known_traits(c)
			"opinion": return c.relations.get(ctx.s.captain, 0)
			"officer": return id in ctx.s.officers.values()
			"post": return ctx.s.officers.find_key(id) if id in ctx.s.officers.values() else ""
			"nationality": return c.nationality
			"age": return c.age
			"hidden": return not c.hidden.is_empty()
			"office": return c.get("role", "")
			"bonded": return Bonds.level(ctx.s, id) != 0
			"in_town": return PortLife.captain_here(ctx.get("port", "")) == id  # drinking in this port's tavern
		if head in People.STATS or head in People.SKILLS:
			return People.value(c, head)
	elif Ports.state.has(id):
		match head:
			"faction": return Ports.port(id).faction
			"fence": return Ports.port(id).get("fence", false)
			"here": return id == ctx.port
			"contraband": return not Ports.state[id].laws.contraband.is_empty()
			"shipyard": return Ports.port(id).shipyard
	elif Data.table("factions").has(id):
		match head:
			"at_war": return Factions.at_war(id, _faction(rest, ctx))
			"mine": return id == _home(ctx.s)
			"standing": return ctx.s.relations.get(id, 0)
	elif Bases.bases.has(id):
		var b: Dictionary = Bases.bases[id]
		match head:
			"loyalty": return b.loyalty
			"visibility": return b.visibility
			"garrison": return b.garrison
			"built": return rest in b.buildings
			"managed": return b.manager != ""
			"manager_opinion": return People.person(b.manager).relations.get(ctx.s.captain, 0) if b.manager != "" else 0
	elif Data.table("goods").has(id):
		match head:
			"price": return Data.table("goods")[id].base_price
			"held": return ctx.s.cargo.get(id, 0.0)
	return value(key, ctx)


static func loyalty(s: Dictionary) -> float:
	if s.crew.is_empty():
		return 0.0
	var total := 0.0
	for id in s.crew:
		total += People.person(id).relations.get(s.captain, 0)
	return total / s.crew.size()


static func _home(s: Dictionary) -> String:
	return Career.home_faction(s)


# ---- showing and resolving -----------------------------------------------------

## {title, text, options} for the choice dialog. Choices that fail their conditions are shown greyed out.
func view(inst: Dictionary, ctx: Dictionary) -> Dictionary:
	var ev: Dictionary = events[inst.id]
	var vars := _with_builtins(inst.vars, ctx)
	var options := []
	for ch in ev.choices:
		var blocked: Array = ch.get("conditions", []).filter(func(c): return not test(c, ctx, vars))
		var tip := PackedStringArray()
		if ch.has("check"):
			var parts := check_parts(ch.check, ctx, vars)
			tip.append("%s check, DC %d: %d%% (%s)" % [People.SKILL_NAMES.get(ch.check.skill, ch.check.skill), ch.check.dc,
				int(Dice.chance(Dice.sum_parts(parts), int(ch.check.dc)) * 100), ", ".join(parts.map(func(p): return "%s %+d" % p))])
		if not ch.get("hidden", false):
			var good := _preview(ch.get("outcomes", []), vars)
			if good != "":
				tip.append(("If it works: " if ch.has("check") else "") + good)
			var bad := _preview(ch.get("fail_outcomes", []), vars)
			if bad != "":
				tip.append("If it fails: " + bad)
		if not blocked.is_empty():
			tip.append("Requires: " + ", ".join(blocked.map(func(c): return humanize(_sub(c, vars, true)))))
		options.append({"text": text(ch.text, vars, ctx), "tooltip": "\n".join(tip), "disabled": not blocked.is_empty()})
	return {"title": text(ev.title, vars, ctx), "text": text(ev.text, vars, ctx), "options": options}


## Applies a choice. Returns {text, effects: [lines], fight: {kind, faction, mode} or {}}.
func resolve(inst: Dictionary, index: int, ctx: Dictionary) -> Dictionary:
	var ev: Dictionary = events[inst.id]
	var ch: Dictionary = ev.choices[index]
	var vars := _with_builtins(inst.vars, ctx)
	fired[ev.id] = Clock.day
	var success := true
	var lines := PackedStringArray()
	if ch.has("check"):
		var c := Dice.check(rng, People.SKILL_NAMES.get(ch.check.skill, ch.check.skill), check_parts(ch.check, ctx, vars), int(ch.check.dc))
		success = c.success
		lines.append(Dice.describe(c).replace("[b]", "").replace("[/b]", "").replace("[/color]", "").replace("[color=#2e6b3a]", "").replace("[color=#a3261b]", ""))
		var who := _who(ch.check.get("who", "captain"), ctx, vars)
		if who != "" and ch.check.skill in People.SKILLS:
			People.gain_xp(People.person(who), ch.check.skill, cfg().check_xp)
	var res := {"text": text(ch.get("result" if success else "fail_result", ""), vars, ctx), "effects": [], "fight": {},
		"mutiny": false, "id": ev.id, "title": text(ev.title, vars, ctx)}
	for o in ch.get("outcomes" if success else "fail_outcomes", []):
		var line := _apply(_sub(o, vars, false), ctx, inst.vars, res)  # chains carry the roles, not the built-ins
		if line != "":
			res.effects.append(line)
	# structured effects ({type, ...}: the market, fences, the world; see scripts/economy/effects.gd)
	var named := {"s": ctx.s, "port": ctx.get("port", "")}
	for k in inst.vars:
		if Ports.state.has(str(inst.vars[k])):
			named[k] = inst.vars[k]
	res.effects.append_array(EconomyEffects.apply_all(ch.get("effects" if success else "fail_effects", []), named))
	res.effects = Array(lines) + res.effects
	_cleanup(inst, ctx)
	return res


## A new face that wasn't hired, and isn't wanted by a chain, never existed.
func _cleanup(inst: Dictionary, ctx: Dictionary) -> void:
	for name in events[inst.id].get("roles", {}):
		if events[inst.id].roles[name].from != "new":
			continue
		var id: String = inst.vars[name]
		if not id in ctx.s.crew and not queue.any(func(q): return id in q.vars.values()):
			People.remove(id)


func check_parts(check: Dictionary, ctx: Dictionary, vars: Dictionary) -> Array:
	var who := _who(check.get("who", "captain"), ctx, vars)
	var c := People.person(who)
	var parts := [["%s %s" % [c.name.get_slice(" ", 0), People.SKILL_NAMES.get(check.skill, check.skill)], Dice.mod(People.value(c, check.skill))]]
	for b in check.get("bonus", []):  # [condition, label, modifier]
		if test(b[0], ctx, vars):
			parts.append([b[1], int(b[2])])
	return parts


## "captain", "post.boatswain" (the captain covers an empty post), or a role holding a character.
func _who(who: String, ctx: Dictionary, vars: Dictionary) -> String:
	var s: Dictionary = ctx.s
	if who.begins_with("post."):
		var id: String = s.officers.get(who.substr(5), "")
		return id if People.chars.has(id) else s.captain
	if who == "captain":
		return s.captain
	var id := _sub(who, vars, false)
	return id if People.chars.has(id) else s.captain


# ---- outcomes ------------------------------------------------------------------

func _apply(o: String, ctx: Dictionary, vars: Dictionary, res: Dictionary) -> String:
	var s: Dictionary = ctx.s
	var a := o.split(" ", false)
	if a[0] in ["food", "water"]:  # shorthand for the hold's provisions
		a = PackedStringArray(["cargo", a[0], a[1]])
	var verb: String = a[0]
	match verb:
		"gold":
			var amt := float(a[1].trim_suffix("%"))
			if a[1].ends_with("%"):
				amt = s.gold * amt / 100.0
			amt = maxf(amt, -s.gold)
			s.gold += amt
			return "Gold %+d" % amt
		"crew":
			var n := int(a[1])
			if n < 0:
				var names := Encounters.kill_crew(s, -n, rng)
				return "%d hands lost%s" % [-n, (": " + ", ".join(names)) if not names.is_empty() else ""]
			n = mini(n, ctx.stats.crew_max - ShipStats.headcount(s))
			var mix: Dictionary = Data.rules.people.recruit_mix[Ports.port(ctx.port).faction if ctx.port != "" else "pirates"]
			for i in n:
				s.crew.append(People.add(People.generate({"mix": mix})))
			return "%d new hands join" % n if n > 0 else "No berths for more hands"
		"kill", "leave":
			var id := _who(a[1], ctx, vars)
			var nm: String = People.person(id).name
			if id == s.captain:
				if verb == "kill":
					Crew.captain_dies(s, "killed")
					return "Captain %s is dead" % nm
				return ""
			if verb == "kill":
				Crew.mourn(s, id)
			Crew.remove_hand(s, id)
			return "%s %s" % [nm, "is dead" if verb == "kill" else "leaves the ship"]
		"wound":
			var c := People.person(_who(a[1], ctx, vars))
			var t := People.wound(c)
			return "%s: %s" % [c.name, Data.table("traits")[t].name.to_lower()] if t != "" else "%s is hurt" % c.name
		"hire":
			if ShipStats.headcount(s) >= ctx.stats.crew_max:
				return "No berth for %s" % People.person(a[1]).name
			s.crew.append(a[1])
			People.person(a[1]).history.append("Joined the %s, %s." % [s.name, Clock.date_string()])
			return "%s joins the crew" % People.person(a[1]).name
		"opinion":
			var n := int(a[1 + 1])
			var ids: Array = s.crew if a[1] == "crew" else [_who(a[1], ctx, vars)]
			for id in ids:
				var c := People.person(id)
				c.relations[s.captain] = clampi(c.relations.get(s.captain, 0) + n, -100, 100)
			return "%s's opinion of you %+d" % ["The crew" if a[1] == "crew" else People.person(ids[0]).name, n]
		"relation":
			var f := _faction(a[1], ctx)
			s.relations[f] = s.relations.get(f, 0) + int(a[2])
			return "Standing with %s %+d" % [Data.table("factions")[f].name, int(a[2])]
		"honour", "fear", "notoriety":
			s.reputation[verb] = maxf(0.0, s.reputation[verb] + int(a[1])) if verb == "notoriety" else s.reputation[verb] + int(a[1])
			return "%s %+d" % [verb.capitalize(), int(a[1])]
		"cargo", "loot":
			var g: String = a[1]
			var have: float = s.cargo.get(g, 0.0)
			var n := -have if a[2] == "-all" else float(a[2])
			if n < 0:
				Ports.remove_cargo(s, g, minf(-n, have))
				return "%s %+d" % [Data.table("goods")[g].name, -minf(-n, have)]
			n = minf(n, floorf((ctx.stats.cargo - Market.cargo_used(s.cargo)) / Market.weight(g)))
			if n <= 0:
				return "No room in the hold for the %s" % Data.table("goods")[g].name.to_lower()
			s.cargo[g] = have + n
			if verb == "loot":
				s.stolen[g] = s.stolen.get(g, 0.0) + n
			return "%s %+d%s" % [Data.table("goods")[g].name, n, " (stolen)" if verb == "loot" else ""]
		"hull", "sails":
			var before: float = s[verb]
			s[verb] = clampf(s[verb] + float(a[1]), 1.0, ctx.stats[verb])
			return "%s %+d" % [verb.capitalize(), s[verb] - before]
		"wages":
			s.wages_owed = maxf(0.0, s.wages_owed + float(a[1]))
			return "Wages owed %+d" % int(a[1])
		"paywages":
			var paid := minf(s.gold, s.wages_owed)
			s.gold -= paid
			s.wages_owed -= paid
			return "Paid %d in back wages" % paid
		"skill":
			var c := People.person(_who(a[1], ctx, vars))
			var k: String = a[2]
			if k in People.SKILLS:
				c.skills[k] = clampi(c.skills[k] + int(a[3]), 0, 20)
			else:
				c.stats[k] = clampi(c.stats[k] + int(a[3]), 0, 20)
			return "%s: %s %+d" % [c.name, People.SKILL_NAMES[k], int(a[3])]
		"trait":
			var c := People.person(_who(a[1], ctx, vars))
			if a[2] in c.traits or People._conflicts(c.traits, a[2]):
				return ""
			c.traits.append(a[2])
			return "%s is now %s" % [c.name, Data.table("traits")[a[2]].name.to_lower()]
		"untrait":
			var c := People.person(_who(a[1], ctx, vars))
			if not a[2] in c.traits:
				return ""
			c.traits.erase(a[2])
			c.hidden.erase(a[2])
			return "%s is no longer %s" % [c.name, Data.table("traits")[a[2]].name.to_lower()]
		"reveal":
			var c := People.person(_who(a[1], ctx, vars))
			if c.hidden.is_empty():
				return ""
			var t := People.reveal_trait(c)
			return "You learn %s is %s" % [c.name, Data.table("traits")[t].name.to_lower()]
		"flag":
			flags[a[1]] = Clock.day + float(a[2]) if a.size() > 2 else -1.0
		"unflag":
			flags.erase(a[1])
		"abandon":
			for c in Contracts.active.duplicate():
				if c.template == a[1] and c.status == "active":
					return Contracts.fail(c, s, "you walked away from it")
		"event":
			var delay := float(a[2]) if a.size() > 2 else 0.0
			var window := float(a[3]) if a.size() > 3 else float(cfg().chain_window_days)
			queue.append({"id": a[1], "at": Clock.day + delay, "until": Clock.day + delay + window, "vars": vars.duplicate()})
		"fight":
			var kind: String = a[1]
			var f: String = _faction(a[2], ctx) if a.size() > 2 else ("pirates" if kind == "pirate" else Career.nations()[rng.randi() % Career.nations().size()])
			res.fight = {"kind": kind, "faction": f, "mode": a[3] if a.size() > 3 else "defend"}
		"market":
			Ports.start_market_event(a[1], a[2])
			return "Prices will move in %s" % Ports.port(a[1]).name
		"time":
			Clock.advance(float(a[1]))
			return "%d days pass" % int(a[1])
		"favour":
			var who := _who(a[1], ctx, vars)
			Politics.add_favours(who, s, int(a[2]))
			return ("%s owes you %d favour%s" if int(a[2]) > 0 else "You owe %s %d favour%s") % [People.person(who).name, absi(int(a[2])), "" if absi(int(a[2])) == 1 else "s"]
		"secret":
			var about := _who(a[2], ctx, vars) if a.size() > 2 and a[2] != "any" else ""
			if about == s.captain:
				about = ""
			return Politics.gain_secret(s, a[1], about, a.size() > 3 and a[3] == "fake", ctx.port if about == "" and ctx.port != "" and ctx.port != "nassau" else "")
		"influence":
			var g: String = a[2]
			Politics.shift(a[1], g, float(a[3]))
			return "%s in %s %+d" % [Data.table("politics").groups[g].name, Ports.port(a[1]).name, int(a[3])]
		"stir":
			Crew.stir(s, int(a[1]))
			return ""
		"scandal":
			var c := People.person(_who(a[1], ctx, vars))
			return Politics.replace(c.port, c.role, "was recalled in disgrace") if c.port != "" else ""
		"council_vote":
			return Politics.council_vote(s, a[1], a[2] == "yes", ctx).text
		"bond":
			var key := _who(a[1], ctx, vars) if not a[1].begins_with("f:") else a[1]
			var lvl := Bonds.level(s, key)
			var to := clampi(maxi(lvl, 0) + int(a[2]), 0, 4)
			if to == 0:
				Bonds.all(s).erase(key)
				return "Your bond with %s is gone" % Bonds.name_of(key)
			Bonds.all(s)[key] = {"type": "alliance", "level": to, "since": Clock.date_string(), "strain": 0, "history": Bonds.all(s).get(key, {}).get("history", [])}
			return "%s with %s" % [Bonds.level_name(key, to), Bonds.name_of(key)]
		"rivalry":
			return Bonds.start_rivalry(s, _who(a[1], ctx, vars), int(a[2]), res.title.to_lower())
		"strain":
			return Bonds.strain(s, _who(a[1], ctx, vars))
		"betray":
			return Bonds.betray(s, _who(a[1], ctx, vars))
		"peace":
			var key := _who(a[1], ctx, vars)
			if Bonds.level(s, key) < 0:
				Bonds.all(s).erase(key)
				return "Peace with %s" % Bonds.name_of(key)
			return ""
		"intel":  # everything about a named captain's ship
			var who := _who(a[1], ctx, vars)
			if not People.chars.has(who) or not People.person(who).has("ship"):
				return ""
			var c := People.person(who)
			Encounters.add_intel(s, c.id, ["all"], res.title.to_lower())
			return "You know the weak points of the %s, %s's ship" % [c.ship, c.name]
		"town":  # the town you're in feels what you did, for a while: town order +10
			if ctx.port == "":
				return ""
			PortLife.nudge(ctx.port, a[1], float(a[2]))
			return "%s in %s %+d" % [a[1].capitalize(), Ports.port(ctx.port).name, int(a[2])]
		"supply":  # from your hold into the town's market: food into a hungry town brings its price down
			if ctx.port == "":
				return ""
			var g: String = a[1]
			var n := minf(float(a[2]), s.cargo.get(g, 0.0))
			if n <= 0.0:
				return ""
			Ports.remove_cargo(s, g, n)
			Economy.add(ctx.port, g, n)
			return "%d %s into the market of %s" % [n, Data.table("goods")[g].name.to_lower(), Ports.port(ctx.port).name]
		"settle":  # a happening here ends now
			if ctx.port != "" and PortLife.is_on(ctx.port, a[1]):
				PortLife.end(ctx.port, a[1])
				return "The %s %s over" % [PortLife.name_of(ctx.port, a[1]).to_lower(), "are" if PortLife.name_of(ctx.port, a[1]).ends_with("s") else "is"]
			return ""
		"marque":  # a letter of marque from this nation, if they'll give you one
			var mf := _faction(a[1], ctx)
			var why := Career.marque_problem(s, mf)
			return why if why != "" else Career.grant_marque(s, mf)
		"patrols":  # you know where a navy will be, and keep out of its way
			var pf := _faction(a[1], ctx)
			s.patrol_warning = s.get("patrol_warning", {})
			s.patrol_warning[pf] = Clock.day + float(a[2])
			return "You know the %s patrols for %d days" % [Data.table("factions")[pf].adjective, int(a[2])]
		"reveal_cove":
			var found := Bases.reveal_random()
			return "You learn of a hidden anchorage: %s" % Bases.cove(found).name if found != "" else ""
		"base_gold", "base_loyalty", "base_visibility", "base_garrison":
			if not Bases.bases.has(a[1]):
				return ""
			var b: Dictionary = Bases.bases[a[1]]
			var field: String = {"base_gold": "gold", "base_loyalty": "loyalty", "base_visibility": "visibility", "base_garrison": "garrison"}[verb]
			var amt := float(a[2].trim_suffix("%"))
			if a[2].ends_with("%"):
				amt = b[field] * amt / 100.0
			b[field] = maxf(0.0, b[field] + amt) if field != "loyalty" and field != "visibility" else clampf(b[field] + amt, 0.0, 100.0)
			if field == "garrison":
				b.garrison = int(b.garrison)
			return "%s: %s %+d" % [b.name, field, int(amt)]
		"base_store":
			if not Bases.bases.has(a[1]):
				return ""
			var b: Dictionary = Bases.bases[a[1]]
			b.storage[a[2]] = maxf(0.0, b.storage.get(a[2], 0.0) + float(a[3]))
			return "%s: %s %+d" % [b.name, Data.table("goods")[a[2]].name.to_lower(), int(a[3])]
		"base_damage":
			if not Bases.bases.has(a[1]):
				return ""
			var b: Dictionary = Bases.bases[a[1]]
			var lost: Array = b.buildings.filter(func(x): return x != "dock")
			if lost.is_empty():
				return ""
			var gone: String = lost[rng.randi() % lost.size()]
			b.buildings.erase(gone)
			return "%s: the %s is destroyed" % [b.name, Bases.building(gone).name.to_lower()]
		"base_lost":
			if not Bases.bases.has(a[1]):
				return ""
			var name: String = Bases.bases[a[1]].name
			Bases.bases.erase(a[1])
			return "%s is lost to you" % name
		"own_ship":
			return Bonds.former_officer(s, _who(a[1], ctx, vars), int(a[2]))
		"join_council":
			Politics.council_members()
			s.council_member = true
			return "You have a seat on the council of captains"
		"morale":
			Crew.add_mod(s, "event_" + res.id, res.title, float(a[1]), float(a[2]))
			return "Morale %+d for %d days" % [int(a[1]), int(a[2])]
		"calm":
			var before: int = s.unrest.support.size()
			Crew.calm(s, int(a[1]))
			return "%d of the malcontents come round" % (before - s.unrest.support.size()) if before > s.unrest.support.size() else ""
		"expose":
			if s.unrest.leader == "":
				return ""
			s.unrest.known = true
			return "You know who is behind it: %s" % People.person(s.unrest.leader).name
		"mutiny":
			res.mutiny = true
		"depose":
			Crew.captain_dies(s, "stood down", true)
			return "You step down as captain"
		"share":
			s.articles.crew_share = clampf(s.articles.crew_share + float(a[1]), 0.0, 0.8)
			return "Crew's share of plunder now %d%%" % int(s.articles.crew_share * 100)
		"confidence":
			var v := Crew.vote(s, ctx.stats, 0.0, rng)
			if v.passed:
				Crew.calm(s, 999)
				Crew.add_mod(s, "confidence", "Won a vote of confidence", 8, 40)
				return "The crew back you, %d to %d" % [v.yes, v.no]
			Crew.captain_dies(s, "voted out by the crew", true)
			return "The crew vote you out, %d to %d" % [v.no, v.yes]
	return ""


## One outcome outside an event (favours, council votes): the same language, nothing to substitute.
func apply_outcome(o: String, ctx: Dictionary) -> String:
	return _apply(o, ctx, {}, {"fight": {}, "mutiny": false, "id": "politics", "title": "Politics"})


func _faction(word: String, ctx: Dictionary) -> String:
	match word:
		"port": return Ports.port(ctx.port).faction if ctx.port != "" else "pirates"
		"home": return _home(ctx.s) if _home(ctx.s) != "" else "pirates"
		"marque": return ctx.s.career.marque if ctx.s.career.marque != "" else _home(ctx.s)
	return word


# ---- text ----------------------------------------------------------------------

## Replaces {role} with its id (raw) or its display name.
func _sub(t: String, vars: Dictionary, display: bool) -> String:
	for k in vars:
		t = t.replace("{%s}" % k, show(vars[k]) if display else str(vars[k]))
	return t


func text(t: String, vars: Dictionary, ctx: Dictionary) -> String:
	var all := {"captain": ShipStats.captain(ctx.s).name, "ship": ctx.s.name, "port": Ports.port(ctx.port).name if ctx.port != "" else "the open sea"}
	for k in vars:
		all[k] = show(vars[k])
		if Data.table("factions").has(str(vars[k])):
			all[k + "_adj"] = Data.table("factions")[vars[k]].adjective
	return t.format(all)


## The display name of a bound value: a character, port, nation or good.
static func show(v: Variant) -> String:
	var id := str(v)
	if People.chars.has(id):
		return People.person(id).name
	if Ports.state.has(id):
		return Ports.port(id).name
	if Data.table("factions").has(id):
		return Data.table("factions")[id].name
	if Data.table("goods").has(id):
		return Data.table("goods")[id].name.to_lower()
	if Data.table("coves").has(id):
		return Bases.cove(id).name
	return id


func _preview(outcomes: Array, vars: Dictionary) -> String:
	var out := PackedStringArray()
	for o in outcomes:
		var a := Array(o.split(" ", false)).map(func(tok): return _sub(tok, vars, true))
		match a[0]:
			"gold", "honour", "fear", "notoriety", "hull", "sails", "wages":
				out.append("%s %s" % [a[0].capitalize(), a[1]])
			"crew": out.append("Crew %s" % a[1])
			"relation": out.append("Standing with %s %s" % [a[1].capitalize(), a[2]])
			"opinion": out.append("%s's opinion of you %s" % ["The crew" if a[1] == "crew" else a[1], a[2]])
			"cargo", "loot": out.append("%s %s" % [a[1].capitalize(), a[2]])
			"food", "water": out.append("%s %s" % [a[0].capitalize(), a[1]])
			"fight": out.append("A fight")
			"paywages": out.append("Pay the back wages")
			"kill": out.append("%s dies" % a[1])
			"hire": out.append("%s joins" % a[1])
			"leave": out.append("%s leaves" % a[1])
			"time": out.append("%s days" % a[1])
	return ", ".join(out)


static func humanize(cond: String) -> String:
	return cond.replace("_", " ").replace(".", " ").replace(" >= ", " at least ").replace(" <= ", " at most ").replace(" == ", " is ").replace(" != ", " is not ")


# ---- checking the data ---------------------------------------------------------

## Every event, choice, condition, role and outcome, checked against what the engine understands.
func validate() -> PackedStringArray:
	var out := PackedStringArray()
	for id in events:
		var ev: Dictionary = events[id]
		var where := "event '%s'" % id
		for f in ["title", "text", "choices"]:
			if not ev.has(f):
				out.append("%s is missing '%s'" % [where, f])
		if not ev.has("choices"):
			continue
		if ev.choices.size() < 1 or ev.choices.size() > 4:
			out.append("%s needs 1 to 4 choices" % where)
		var known := ["captain", "ship", "port"]
		for name in ev.get("roles", {}):
			known.append(name)
			if not ev.roles[name].get("from", "") in SOURCES:
				out.append("%s: role '%s' has an unknown source '%s'" % [where, name, ev.roles[name].get("from", "")])
		var conds: Array = ev.get("conditions", []).duplicate()
		for w in ev.get("weight_mods", []):
			conds.append(w[0])
		for name in ev.get("roles", {}):
			for c in ev.roles[name].get("where", []):
				out.append_array(_check_cond(c, where, true))
				for tok in _tokens(c):
					if not tok in known:
						out.append("%s: role '%s' uses an unbound {%s}" % [where, name, tok])
		var texts: Array = [ev.title, ev.text]
		for ch in ev.choices:
			texts.append(ch.get("text", ""))
			texts.append(ch.get("result", ""))
			texts.append(ch.get("fail_result", ""))
			conds.append_array(ch.get("conditions", []))
			if ch.has("check"):
				for b in ch.check.get("bonus", []):
					conds.append(b[0])
				var sk: String = ch.check.get("skill", "")
				if not (sk in People.SKILLS or sk in People.STATS):
					out.append("%s: unknown check skill '%s'" % [where, sk])
				if not ch.has("fail_outcomes") and not ch.has("fail_result"):
					out.append("%s: a check needs a fail_result" % where)
			for e in ch.get("effects", []) + ch.get("fail_effects", []):
				if not EconomyEffects.known(e.get("type", "")):
					push_warning("Events: %s uses effect '%s', which isn't handled; it will be skipped." % [where, e.get("type", "")])
			for o in ch.get("outcomes", []) + ch.get("fail_outcomes", []):
				var a: PackedStringArray = o.split(" ", false)
				if not VERBS.has(a[0]):
					out.append("%s: unknown outcome '%s'" % [where, o])
				elif a.size() - 1 < VERBS[a[0]][0] or a.size() - 1 > VERBS[a[0]][1]:
					out.append("%s: wrong number of arguments in '%s'" % [where, o])
				elif a[0] == "event" and not events.has(a[1]):
					out.append("%s: chains to unknown event '%s'" % [where, a[1]])
				elif a[0] in ["cargo", "loot"] and not a[1].begins_with("{") and not Data.table("goods").has(a[1]):
					out.append("%s: unknown good in '%s'" % [where, o])
				elif a[0] == "abandon" and not Data.table("contracts").has(a[1]):
					out.append("%s: unknown contract in '%s'" % [where, o])
				elif a[0] in ["trait", "untrait"] and not Data.table("traits").has(a[2]):
					out.append("%s: unknown trait in '%s'" % [where, o])
				for tok in _tokens(o):
					if not tok in known:
						out.append("%s: '%s' uses an unbound {%s}" % [where, o, tok])
		for c in conds:
			out.append_array(_check_cond(c, where, false))
			for tok in _tokens(c):
				if not tok in known:
					out.append("%s: condition '%s' uses an unbound {%s}" % [where, c, tok])
		for t in texts:
			for tok in _tokens(t):
				if not (tok in known or tok.trim_suffix("_adj") in known):
					out.append("%s: text uses an unknown {%s}" % [where, tok])
	return out


const COND_KEYS := ["gold", "crew", "hull", "sails", "notoriety", "honour", "fear", "loyalty", "food", "water", "wages_owed",
	"prizes", "hostages", "contracts", "year", "month", "date", "guns", "stolen", "cargo", "relation", "captain", "captain_trait",
	"has_officer", "at_sea", "in_port", "storm", "pirate", "privateer", "honest", "wanted", "marque", "home", "pardoned",
	"pardon_open", "war", "flag", "contract", "ship", "port", "port_faction", "port_fence", "port_is", "true",
	"morale", "unrest", "unrest_known", "sick", "shares", "crew_share", "owes", "secrets", "council_member", "council_leader", "power", "allies", "rivals", "neutral", "bases", "at_base",
	"town", "life"]
const TEXT_KEYS := ["office", "date", "ship", "port", "port_faction", "marque", "home", "post", "faction", "nationality"]
const CAND_KEYS := ["in_town", "loyalty", "visibility", "garrison", "built", "managed", "manager_opinion", "bonded", "office", "trait", "known_trait", "opinion", "officer", "post", "nationality", "age", "hidden", "faction", "fence",
	"here", "contraband", "shipyard", "at_war", "mine", "standing", "price", "held"]


func _check_cond(c: String, where: String, candidate: bool) -> PackedStringArray:
	var parts := c.trim_prefix("not ").split(" ", false)
	if parts.size() != 1 and parts.size() != 3:
		return PackedStringArray(["%s: can't read condition '%s'" % [where, c]])
	if parts.size() == 3 and not parts[1] in ["==", "!=", "<", ">", "<=", ">="]:
		return PackedStringArray(["%s: unknown comparison in '%s'" % [where, c]])
	var head := parts[0].get_slice(".", 0)
	if not (head in COND_KEYS or (candidate and (head in CAND_KEYS or head in People.STATS or head in People.SKILLS))):
		return PackedStringArray(["%s: unknown condition key '%s' in '%s'" % [where, head, c]])
	if parts.size() == 3 and not parts[2].is_valid_float() and not parts[2].contains("{") and not head in TEXT_KEYS:
		return PackedStringArray(["%s: '%s' compares a number with '%s'" % [where, c, parts[2]]])
	return PackedStringArray()


static func _tokens(t: String) -> Array:
	var out := []
	var rx := RegEx.create_from_string("\\{([a-z_0-9]+)\\}")
	for m in rx.search_all(t):
		out.append(m.get_string(1))
	return out


func save_state() -> Dictionary:
	return {"fired": fired, "flags": flags, "queue": queue, "rng": str(rng.state)}


func load_state(d: Dictionary) -> void:
	fired = d.fired
	flags = d.flags
	queue = d.queue
	rng.state = int(d.rng)
