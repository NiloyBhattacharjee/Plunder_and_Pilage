extends Node
## Autoload "Bonds": alliances and rivalries. Partners are named NPC captains (a roster who really sail the map),
## Nassau's council captains, officials, and nations (the Brethren included). Every bond has benefits and costs,
## and staying neutral is a choice with its own. Your bonds live on the ship (state.bonds), so a new captain
## inherits them, though allies may reconsider. NPCs have their own friendships and feuds (npc), so the world
## shifts around you. Numbers and texts in data/bonds.json.
##   state.bonds: {key: {type: "alliance"/"rivalry", level, since, strain, history: [text]}}
##   key: a character id, or "f:<faction>" for a nation.

signal news(text: String)

var captains: Array = []   # the roster of named captains (character ids)
var npc := {}              # "a|b" -> how two NPCs feel about each other, -100..100
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


func reset() -> void:
	captains = []
	npc = {}


static func cfg() -> Dictionary:
	return Data.table("bonds")


# ---- the roster of captains ---------------------------------------------------------

## Named captains: pirates who haunt the havens and trade routes, and privateers out of the colonies.
func roster() -> Array:
	if captains.is_empty():
		var c: Dictionary = cfg().captains
		for i in int(c.count):
			captains.append(_make_captain("pirates" if i < c.pirates else Career.nations()[rng.randi() % Career.nations().size()]))
		var everyone := captains.duplicate()
		for i in everyone.size():  # old friendships and older grudges
			for j in range(i + 1, everyone.size()):
				if rng.randf() < 0.35:
					npc_set(everyone[i], everyone[j], rng.randi_range(-70, 70))
	return captains.filter(func(id): return People.chars.has(id) and People.person(id).get("alive", true))


func _make_captain(f: String) -> String:
	var c := People.generate({"mix": Data.rules.people.recruit_mix[f]})
	var cc: Dictionary = cfg().captains
	for k in ["authority", "intimidation", "experience"]:
		c.stats[k] = mini(20, c.stats[k] + rng.randi_range(3, 6))
	for k in ["seamanship", "gunnery", "swordplay"]:
		c.skills[k] = mini(20, c.skills[k] + rng.randi_range(3, 7))
	var parts: PackedStringArray = c.name.split(" ")
	c.name = '%s "%s" %s' % [parts[0], cc.epithets[rng.randi() % cc.epithets.size()], " ".join(parts.slice(1))]
	c.role = "captain"
	c.faction = f
	var names: Array = Data.table("factions")[f].ship_names
	c.ship = names[rng.randi() % names.size()]
	var types: Array = cc.ships.pirates if f == "pirates" else cc.ships.privateer
	c.ship_type = types[rng.randi() % types.size()]
	var havens := Ports.state.keys().filter(func(id): return Ports.port(id).get("fence", false)) if f == "pirates" else Contracts._ports_of(f)
	c.haunt = havens[rng.randi() % havens.size()]
	c.port = c.haunt
	c.alive = true
	c.fame = rng.randi_range(10, 60)
	c.favours = {}
	c.hidden = []
	c.history.append("Captain of the %s, %s." % [c.ship, "a pirate" if f == "pirates" else "sailing under a %s commission" % Data.table("factions")[f].adjective])
	return People.add(c)


static func pair_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func npc_rel(a: String, b: String) -> int:
	return npc.get(pair_key(a, b), 0)


func npc_set(a: String, b: String, v: int) -> void:
	npc[pair_key(a, b)] = clampi(v, -100, 100)


# ---- partners ------------------------------------------------------------------------

static func kind(key: String) -> String:
	if key.begins_with("f:"):
		return "faction"
	return "captain" if People.person(key).get("role", "") in ["captain", "council"] else "official"


static func name_of(key: String) -> String:
	return Data.table("factions")[key.substr(2)].name if key.begins_with("f:") else People.person(key).name


static func exists(key: String) -> bool:
	return key.begins_with("f:") or (People.chars.has(key) and People.person(key).get("alive", true))


static func level_name(key: String, lvl: int) -> String:
	if lvl > 0:
		var a: Dictionary = cfg().alliance[lvl - 1]
		return a.get(kind(key) + "_name", a.name)
	if lvl < 0:
		return cfg().rivalry[-lvl - 1].name
	return "No bond"


static func all(s: Dictionary) -> Dictionary:
	if not s.has("bonds"):
		s.bonds = {}
	return s.bonds


## +1..+4 for an alliance, -1..-3 for a rivalry, 0 for nothing.
static func level(s: Dictionary, key: String) -> int:
	var b: Dictionary = all(s).get(key, {})
	if b.is_empty():
		return 0
	return b.level if b.type == "alliance" else -b.level


static func allies(s: Dictionary, min_level := 1) -> Array:
	return all(s).keys().filter(func(k): return exists(k) and level(s, k) >= min_level)


static func rivals(s: Dictionary, min_level := 1) -> Array:
	return all(s).keys().filter(func(k): return exists(k) and level(s, k) <= -min_level)


static func neutral(s: Dictionary) -> bool:
	return allies(s).is_empty() and rivals(s).is_empty()


## How they regard you: a person's opinion of your captain, or your standing with a nation.
static func regard(s: Dictionary, key: String) -> int:
	if key.begins_with("f:"):
		return s.relations.get(key.substr(2), 0)
	return People.person(key).relations.get(s.captain, 0)


static func _note(s: Dictionary, key: String, text: String) -> void:
	var b: Dictionary = all(s)[key]
	b.history.append("%s: %s" % [Clock.date_string(), text])
	if b.history.size() > 6:
		b.history.remove_at(0)


# ---- the people a partner brings with them -----------------------------------------------

## Who will think less of you for siding with them: a nation's enemies, a person's rivals.
func enemies_of(key: String) -> Array:
	if key.begins_with("f:"):
		var f := key.substr(2)
		var out: Array = Factions.enemies_of(f).map(func(e): return "f:" + e) if f != "pirates" else Career.nations().map(func(e): return "f:" + e)
		if f != "pirates":
			out.append("f:pirates")
		return out
	var out := []
	for other in roster() + Politics.council + _officials_known():
		if other != key and People.chars.has(other) and (npc_rel(key, other) <= -30 or People.person(key).relations.get(other, 0) <= -30):
			out.append(other)
	return out


func friends_of(key: String) -> Array:
	if key.begins_with("f:"):
		return []
	var out := []
	for other in roster() + Politics.council + _officials_known():
		if other != key and People.chars.has(other) and (npc_rel(key, other) >= 30 or People.person(key).relations.get(other, 0) >= 30):
			out.append(other)
	return out


static func _officials_known() -> Array:
	var out := []
	for port_id in Politics.officials:
		out.append_array(Politics.officials[port_id].values())
	return out


# ---- proposing, breaking, declaring ------------------------------------------------------

## Will they take the next step with you? Paradox style: every reason, with its weight.
## {ok, score, need, next, parts: [[label, value]]}
func acceptance(s: Dictionary, key: String) -> Dictionary:
	var lvl := level(s, key)
	var next := lvl + 1 if lvl >= 0 else 0  # a rivalry can only become peace first
	var parts := []
	var need: int
	if key.begins_with("f:"):
		var f := key.substr(2)
		need = int(cfg().faction_need[next - 1]) if next > 0 else -10
		parts.append(["Your standing with %s" % Data.table("factions")[f].name, regard(s, key)])
		if f != "pirates" and s.career.pirate:
			parts.append(["You're a pirate", -40])
		if f == "pirates" and not s.career.pirate:
			parts.append(["You've never sailed on the account", -15])
		if next == 3 and f != "pirates" and s.career.marque != f:
			parts.append(["No %s commission" % Data.table("factions")[f].adjective, -30])
	else:
		var c := People.person(key)
		need = int(cfg().alliance[next - 1].need) if next > 0 else -10
		parts.append(["%s's opinion of you" % c.name, regard(s, key)])
		if kind(key) == "captain":
			parts.append(["Your name on the seas", mini(10, int(s.reputation.notoriety / 5))])
		parts.append(["Favours they owe you", Politics.favours(key, s) * 5])
		if "loyal" in c.traits: parts.append(["Loyal by nature", 10])
		if "schemer" in c.traits: parts.append(["A schemer, wary of ties", -10])
		if "honest" in c.traits and s.reputation.honour < 0: parts.append(["Honest, and you're not", -10])
		var theirs := enemies_of(key)
		var shared := rivals(s).filter(func(r): return r in theirs).size()
		if shared > 0: parts.append(["A common enemy", 15 * shared])
		var mine_with_their_enemies := allies(s).filter(func(a): return a in theirs).size()
		if mine_with_their_enemies > 0: parts.append(["You're allied with their enemies", -30 * mine_with_their_enemies])
		if lvl < 0: parts.append(["Bad blood between you", 10 * lvl])
	var score := 0
	for p in parts:
		score += int(p[1])
	return {"ok": score >= need, "score": score, "need": need, "next": next, "parts": parts}


static func acceptance_text(acc: Dictionary) -> String:
	var lines := PackedStringArray()
	for p in acc.parts:
		lines.append("%s: %+d" % p)
	lines.append("Total %d, needs %d: %s" % [acc.score, acc.need, "they'll agree" if acc.ok else "they'll refuse"])
	return "\n".join(lines)


## What taking the next step means: benefits, costs, and who'll think less of you.
func preview(s: Dictionary, key: String) -> String:
	var acc := acceptance(s, key)
	if acc.next == 0:
		return "Make peace: the rivalry ends.\n\n" + acceptance_text(acc)
	var k := kind(key)
	var lines := PackedStringArray(["%s: %s" % [level_name(key, acc.next), cfg().alliance[acc.next - 1].text],
		"Gain: " + cfg().benefits[k][acc.next - 1], "Cost: " + cfg().costs[k][acc.next - 1]])
	var foes: Array = enemies_of(key).filter(func(e): return exists(e))
	if not foes.is_empty():
		lines.append("Will think less of you: " + ", ".join(foes.slice(0, 6).map(func(e): return name_of(e))))
	lines.append("")
	lines.append(acceptance_text(acc))
	return "\n".join(lines)


## Ask for the next step (or peace, with a rival).
func propose(s: Dictionary, key: String) -> String:
	var acc := acceptance(s, key)
	if not acc.ok:
		if not key.begins_with("f:"):
			People.person(key).relations[s.captain] = regard(s, key) - 2
		return "%s declines." % name_of(key)
	if acc.next == 0:
		all(s).erase(key)
		return "You make peace with %s. The rivalry is over." % name_of(key)
	var b: Dictionary = all(s).get(key, {"type": "alliance", "level": 0, "since": Clock.date_string(), "strain": 0, "history": []})
	b.type = "alliance"
	b.level = acc.next
	all(s)[key] = b
	_note(s, key, "%s agreed" % level_name(key, acc.next))
	var hit: int = cfg().enemy_hit[acc.next - 1]
	var hurt := PackedStringArray()
	for e in enemies_of(key):  # their enemies become yours
		if not exists(e):
			continue
		if e.begins_with("f:"):
			s.relations[e.substr(2)] = s.relations.get(e.substr(2), 0) - hit
		else:
			People.person(e).relations[s.captain] = regard(s, e) - hit
		hurt.append(name_of(e))
	var text := "%s with %s: %s" % [level_name(key, acc.next), name_of(key), cfg().alliance[acc.next - 1].text]
	if not hurt.is_empty():
		text += " %s think less of you for it." % ", ".join(hurt.slice(0, 4))
	return text


## Walk away from an alliance. The deeper it was, the more it costs, and everyone hears.
func break_bond(s: Dictionary, key: String, why := "you broke it") -> String:
	var lvl := level(s, key)
	if lvl <= 0:
		return ""
	all(s).erase(key)
	s.reputation.honour -= lvl * int(cfg().break_honour)
	for c in roster() + Politics.council:  # betraying an ally shakes everyone's trust
		People.person(c).relations[s.captain] = regard(s, c) - lvl * int(cfg().break_opinion_all)
	var text := "Your %s with %s is over (%s). Honour -%d." % [level_name(key, lvl).to_lower(), name_of(key), why, lvl * cfg().break_honour]
	if key.begins_with("f:"):
		s.relations[key.substr(2)] = s.relations.get(key.substr(2), 0) - 10 * lvl
	else:
		People.person(key).relations[s.captain] = regard(s, key) - 20 * lvl
		if lvl >= 2:
			start_rivalry(s, key, mini(3, lvl - 1), "a broken alliance")
			text += " %s is your rival now." % name_of(key)
	if lvl == 4 and kind(key) == "captain":
		s.relations.pirates = s.relations.get("pirates", 0) - int(cfg().brotherhood_break_pirates)
		text += " Every pirate in the Caribbean hears you broke a sworn brotherhood."
	return text


## Begin a rivalry, or make one worse.
func start_rivalry(s: Dictionary, key: String, lvl: int, why: String) -> String:
	if not exists(key) or key.begins_with("f:"):
		return ""
	var current := level(s, key)
	if current > 0:
		all(s).erase(key)
	if current < 0 and -current >= lvl:
		return ""
	all(s)[key] = {"type": "rivalry", "level": clampi(lvl, 1, 3), "since": Clock.date_string(), "strain": 0,
		"history": all(s).get(key, {}).get("history", [])}
	_note(s, key, "%s: %s" % [level_name(key, -lvl), why])
	People.person(key).relations[s.captain] = mini(regard(s, key), -20 * lvl)
	return "%s: %s with %s (%s)." % ["Rivalry" if lvl == 1 else ("Feud" if lvl == 2 else "Blood feud"), level_name(key, -lvl), name_of(key), why]


## Declare a rivalry on purpose, or escalate one.
func declare(s: Dictionary, key: String) -> String:
	var current := level(s, key)
	if current > 0:
		return break_bond(s, key, "you declared against them")
	return start_rivalry(s, key, -current + 1 if current < 0 else 1, "you declared it")


## A call ignored, a promise broken: two strains and the bond drops a level.
func strain(s: Dictionary, key: String) -> String:
	var b: Dictionary = all(s).get(key, {})
	if b.is_empty() or b.type != "alliance":
		return ""
	b.strain += 1
	if b.strain < int(cfg().strain_drop):
		_note(s, key, "strained")
		return "%s is disappointed in you." % name_of(key)
	b.strain = 0
	b.level -= 1
	if b.level <= 0:
		all(s).erase(key)
		return "%s no longer counts you a friend." % name_of(key)
	_note(s, key, "down to %s" % level_name(key, b.level))
	return "Your bond with %s weakens to %s." % [name_of(key), level_name(key, b.level).to_lower()]


## An ally turns on you.
func betray(s: Dictionary, key: String) -> String:
	if level(s, key) <= 0:
		return ""
	all(s).erase(key)
	start_rivalry(s, key, 2, "they betrayed you")
	return "%s has betrayed you." % name_of(key)


# ---- what bonds do ---------------------------------------------------------------------

## Overrides whether a ship attacks you. null: no opinion, let the usual rules decide.
func hostile_override(s: Dictionary, enemy: Dictionary) -> Variant:
	if enemy.has("captain_id"):
		var l := level(s, enemy.captain_id)
		if l >= 1:
			return false
		if l <= -2:
			return true
	var f: String = enemy.get("faction", "")
	if f != "" and level(s, "f:" + f) >= 1 and not (enemy.get("kind", "") == "hunter" and Career.wanted(s)):
		return false
	return null


## Pacts mean better prices: with the port's nation, or with someone in office there.
func price_mult(s: Dictionary, port_id: String) -> float:
	var m := 1.0
	if level(s, "f:" + Ports.port(port_id).faction) >= 2:
		m *= 1.0 - cfg().price_cut
	for id in Politics.officials.get(port_id, {}).values():
		if level(s, id) >= 2:
			m *= 1.0 - cfg().price_cut
			break
	return m


## Patronage keeps a port open to you whatever your name.
func port_open(s: Dictionary, port_id: String) -> bool:
	if level(s, "f:" + Ports.port(port_id).faction) >= 4:
		return true
	for id in Politics.officials.get(port_id, {}).values():
		if level(s, id) >= 4:
			return true
	return false


## Ships that will fight beside you: allied captains, and allied nations' warships, within sight.
func battle_allies(s: Dictionary, pos: Vector2, shipping: Node) -> Array:
	var out := []
	if shipping == null:
		return out
	var sight: float = shipping.nm(Data.rules.shipping.sight_nm)
	for n in shipping.npcs:
		if n.pos.distance_to(pos) > sight:
			continue
		var e: Dictionary = n.enemy
		var joins := false
		if n.has("captain_id"):
			joins = level(s, n.captain_id) >= 3
		elif n.kind in ["navy", "pirate"]:
			joins = level(s, "f:" + e.faction) >= 3
		if joins:
			var st := ShipStats.effective(e.type, e.upgrades)
			out.append({"name": e.name, "guns": st.guns, "gun_weight": st.gun_weight, "gunnery": e.get("gunnery", 8), "id": n.get("captain_id", ""), "type": e.type})
	return out


## How bonds sit with the crew.
func morale_parts(s: Dictionary) -> Array:
	var parts := []
	var feuds := rivals(s, 2)
	if not feuds.is_empty():
		parts.append(["A common enemy: %s" % name_of(feuds[0]), float(cfg().unity_morale)])
	var crew: Array = s.crew.map(func(id): return People.person(id))
	if crew.is_empty():
		return parts
	var navy := crew.filter(func(c): return "navy" in Crew.tags(c)).size() / float(crew.size())
	var wild := crew.filter(func(c): return "pirate_friendly" in Crew.tags(c) or "hates_mercy" in Crew.tags(c)).size() / float(crew.size())
	for key in allies(s, 2):
		var pirate_ally: bool = key == "f:pirates" or (not key.begins_with("f:") and People.person(key).get("faction", "") == "pirates")
		var crown_ally: bool = (key.begins_with("f:") and key != "f:pirates") or kind(key) == "official"
		if pirate_ally and navy >= 0.15:
			parts.append(["Old navy hands hate sailing with %s" % name_of(key), -float(cfg().ally_morale)])
		elif crown_ally and (s.career.pirate or wild >= 0.2):
			parts.append(["Hands who hate the Crown: allied with %s" % name_of(key), -float(cfg().ally_morale)])
	return parts


# ---- the world moves ---------------------------------------------------------------------

## Monthly: reputation drag, gifts from patrons, calls for help, betrayals, rivals' moves, NPC feuds.
func monthly(s: Dictionary) -> Array:
	var c := cfg()
	var msgs := []
	var weak: bool = s.crew.size() < 15 or s.hull < ShipStats.effective(s.type, s.upgrades).hull * 0.4
	for key in allies(s):
		var lvl := level(s, key)
		var pirate_ally: bool = key == "f:pirates" or (not key.begins_with("f:") and People.person(key).get("faction", "") == "pirates")
		if lvl >= 2 and pirate_ally:  # your friends' names rub off on yours
			for f in Career.nations():
				s.relations[f] -= int(c.drag)
		elif lvl >= 2:
			s.relations.pirates = s.relations.get("pirates", 0) - int(c.drag)
		if kind(key) == "official" and lvl >= 3:
			Politics.add_favours(key, s, 1)
			if lvl >= 4 and People.person(key).port != "":
				var g: String = Data.table("politics").roles.get(People.person(key).role, {}).get("group", "")
				if g != "":
					Politics.shift(People.person(key).port, g, 2)
		if lvl >= 2 and rng.randf() < c.call_chance[lvl - 1]:
			Events.queue.append({"id": "ally_calls_for_help", "at": Clock.day, "until": Clock.day + 30, "vars": {"ally": key, "nation": _foe_nation(key)}})
		if not key.begins_with("f:"):
			var p := People.person(key)
			var chance: float = c.betray_base + (c.betray_weak if weak else 0.0)
			for t in p.traits:
				chance += c.betray_traits.get(t, 0.0)
			if rng.randf() < chance:
				Events.queue.append({"id": "ally_betrays", "at": Clock.day, "until": Clock.day + 20, "vars": {"ally": key, "nation": _foe_nation(key)}})
	for key in rivals(s):
		var lvl := -level(s, key)
		if lvl == 1 and not Contracts.offers.is_empty():  # competition: they get there first
			var port_id: String = Contracts.offers.keys()[rng.randi() % Contracts.offers.size()]
			if not Contracts.offers[port_id].list.is_empty():
				Contracts.offers[port_id].list.pop_back()
				msgs.append("%s beat you to a job in %s." % [name_of(key), Ports.port(port_id).name])
		if lvl == 3:  # a blood feud: they spread your name and pay for your head
			s.reputation.notoriety += 2
			msgs.append("%s is spreading your name in every tavern and paying for news of your course." % name_of(key))
	for i in 3:  # NPCs make friends and enemies of their own
		var r := roster()
		if r.size() < 2:
			break
		var a: String = r[rng.randi() % r.size()]
		var b: String = r[rng.randi() % r.size()]
		if a != b:
			var before := npc_rel(a, b)
			npc_set(a, b, before + rng.randi_range(-int(c.npc_drift), int(c.npc_drift)))
			if npc_rel(a, b) <= -50 and rng.randf() < c.npc_fight_chance:
				msgs.append("News from the havens: %s and %s fought it out off %s." % [People.person(a).name, People.person(b).name, Ports.port(People.person(a).haunt).name])
	return msgs


func _foe_nation(key: String) -> String:
	if key.begins_with("f:"):
		var foes := Factions.enemies_of(key.substr(2)) if key != "f:pirates" else Career.nations()
		return foes[rng.randi() % foes.size()] if not foes.is_empty() else "pirates"
	var f: String = People.person(key).get("faction", Ports.port(People.person(key).port).faction if People.person(key).port != "" else "pirates")
	if f == "pirates":
		return Career.nations()[rng.randi() % Career.nations().size()]
	var foes := Factions.enemies_of(f)
	return foes[rng.randi() % foes.size()] if not foes.is_empty() else "pirates"


## After a fight with a named captain. attacked: you opened fire. Returns messages.
func on_battle(s: Dictionary, enemy: Dictionary, outcome: String, attacked: bool) -> Array:
	var msgs := []
	if not enemy.has("captain_id") or not People.chars.has(enemy.captain_id):
		return msgs
	var id: String = enemy.captain_id
	var c := People.person(id)
	var lvl := level(s, id)
	if attacked and lvl > 0:
		msgs.append(break_bond(s, id, "you attacked them"))
		lvl = level(s, id)
	elif lvl == 0:
		msgs.append(start_rivalry(s, id, 2, "you fought"))
		lvl = level(s, id)
	if outcome in ["enemy_struck", "enemy_sunk"]:
		var fame: int = cfg().fame_per_level * maxi(1, -lvl)
		s.reputation.notoriety += fame
		s.reputation.fear += maxi(1, -lvl)
		Crew.add_mod(s, "beat_" + id, "We beat %s!" % c.name, 8 + 2 * maxi(0, -lvl), 40)
		msgs.append("You've beaten %s. Your name grows (notoriety +%d)." % [c.name, fame])
		if c.get("faction", "") == "pirates":
			var bounty: int = c.get("fame", 20) * int(cfg().bounty_per_notoriety)
			s.gold += bounty
			msgs.append("The bounty on %s pays %d gold." % [c.name, bounty])
		c.alive = false
		c.history.append("%s by Captain %s, %s." % ["Sunk" if outcome == "enemy_sunk" else "Taken", ShipStats.captain(s).name, Clock.date_string()])
		all(s).erase(id)
		for f in roster():  # their friends swear revenge; their enemies warm to you
			if npc_rel(f, id) >= 30:
				msgs.append(start_rivalry(s, f, 1, "you beat their friend %s" % c.name))
			elif npc_rel(f, id) <= -30:
				People.person(f).relations[s.captain] = regard(s, f) + 15
	return msgs.filter(func(m): return m != "")


## A new captain: allies weigh them up, and some step back.
func reconsider(s: Dictionary) -> Array:
	var msgs := []
	for key in allies(s):
		var acc := acceptance(s, key)
		var lvl := level(s, key)
		var need: int = int(cfg().faction_need[lvl - 1]) if key.begins_with("f:") else int(cfg().alliance[lvl - 1].need)
		if acc.score < need:
			all(s)[key].level -= 1
			if all(s)[key].level <= 0:
				all(s).erase(key)
				msgs.append("%s doesn't know the new captain, and lets the bond lapse." % name_of(key))
			else:
				msgs.append("%s is wary of the new captain: %s now." % [name_of(key), level_name(key, lvl - 1).to_lower()])
	return msgs


## A crew member leaves to captain their own ship, and joins the roster, bound to you at `lvl`.
## An officer leaves to captain a ship of their own: a new one, or `ship` (a squadron ship they take with them).
func former_officer(s: Dictionary, id: String, lvl: int, ship := {}) -> String:
	if not id in s.crew and ship.is_empty():
		return ""
	var c := People.person(id)
	for post in s.officers.keys():
		if s.officers[post] == id:
			s.officers.erase(post)
	s.crew.erase(id)
	c.role = "captain"
	c.faction = "pirates" if s.career.pirate else (Career.home_faction(s) if Career.home_faction(s) != "" else "pirates")
	var names: Array = Data.table("factions")[c.faction].ship_names
	c.ship = ship.get("name", names[rng.randi() % names.size()])
	c.ship_type = ship.get("type", "sloop")
	var havens: Array = Ports.state.keys().filter(func(p): return Ports.port(p).get("fence", false)) if c.faction == "pirates" else Contracts._ports_of(c.faction)
	c.haunt = havens[rng.randi() % havens.size()]
	c.port = c.haunt
	c.alive = true
	c.fame = 10
	c.favours = c.get("favours", {})
	c.history.append("Left the %s to captain the %s, %s." % [s.name, c.ship, Clock.date_string()])
	captains.append(id)
	if lvl > 0:
		all(s)[id] = {"type": "alliance", "level": lvl, "since": Clock.date_string(), "strain": 0, "history": ["%s: sailed from your ship" % Clock.date_string()]}
	elif lvl < 0:
		start_rivalry(s, id, -lvl, "they left your ship on bad terms")
	return "%s sails away in the %s, %s." % [c.name, c.ship, "a friend" if lvl > 0 else ("an enemy" if lvl < 0 else "owing you nothing")]


## Keeps the roster's ships at sea.
func ensure_on_map(shipping: Node) -> void:
	if shipping == null:
		return
	for id in roster():
		if shipping.npcs.any(func(n): return n.get("captain_id", "") == id):
			continue
		if rng.randf() < 0.15:  # some days they're in port
			shipping.spawn_captain(id)


func save_state() -> Dictionary:
	return {"captains": captains, "npc": npc, "rng": str(rng.state)}


func load_state(d: Dictionary) -> void:
	captains = d.captains
	npc = d.npc
	rng.state = int(d.rng)
