class_name SiegeFlow
extends RefCounted
## A siege as a council of war: each turn you see the state of the town and choose what to do next; every choice
## says what it risks and its odds on hover. Runs on the world map's choice dialog; a guard ship or a relief
## squadron is fought in the battle scene. The rules are in scripts/sieges.gd.

var world: Node  # the WorldMap
var g := {}


func _init(w: Node) -> void:
	world = w


func run(id: String) -> void:
	var s: Dictionary = world.ship.state
	UIKit.pause_clock()
	world._in_event = true
	world.ship.route.clear()
	world.ship.anchored_at = ""
	var start := Sieges.resume(s, id, world.rng)  # a siege you lifted, if you're coming back to one
	if start.is_empty():
		start = Sieges.begin(s, id, world.rng)
	g = start.g
	for m in start.messages:
		world.hud.show_message(m)
	var taken := await _council(s)
	world._in_event = false
	if taken:
		await _after_the_fall(s, id)
	else:
		Sieges.remember(s, g)
	world.port_layer.queue_redraw()
	UIKit.resume_clock()
	if world.ship.anchored_at == id:  # you hold it: step ashore
		world.port_screen.open(id, world.ship)


## Turn after turn until the town falls (true) or you give up (false).
func _council(s: Dictionary) -> bool:
	var stats: Dictionary = world.ship.stats
	while s.hull > 0:
		UIKit.pause_clock()  # a battle lets the clock run again when it ends
		var cfg := Sieges.cfg()
		var options := []  # [{text, tooltip, disabled}, action]
		options.append([{"text": "Scout the defences (1 day)", "disabled": g.scouted,
			"tooltip": "Boats by night along the walls. Find the weak side, count the garrison, learn when relief is due.\n%d%% chance:\n%s\nFail and the town is put on alert." % [
				Dice.chance(Dice.sum_parts(Sieges.scout_parts(s, g)), int(cfg.scout_dc)) * 100, _lines(Sieges.scout_parts(s, g))]}, "scout"])
		if g.guard:
			options.append([{"text": "Engage the guard ship", "tooltip": "A warship lies under the fort. Nothing else can be done from the sea while she's there.\nYou fight her where she lies: the fort's guns join in."}, "guard"])
		options.append([{"text": "Bombard the fort (1 day)", "disabled": g.guard or g.fort <= 0.0,
			"tooltip": ("The guard ship is in the way." if g.guard else "Your guns against the fort's: each success silences part of it. Its guns cost you hull every day you lie under them.\n%d%% chance:\n%s\nagainst the fort %+d" % [
				Dice.contest_chance(Dice.sum_parts(Sieges.bombard_parts(s, stats, g)), Sieges.fort_mod(g)) * 100, _lines(Sieges.bombard_parts(s, stats, g)), Sieges.fort_mod(g)])}, "bombard"])
		options.append([{"text": "Blockade: starve them (5 days)", "tooltip": "Nothing goes in or out. The town eats its stores and grows hungry: a starving garrison loses heart and men, and a hungry town riots.\nBut every day brings their relief squadron closer, and your own crew eats too."}, "blockade"])
		options.append([{"text": "Wait for your allies (3 days)", "disabled": not Sieges.can_wait_for_allies(s, g),
			"tooltip": "Allied captains may answer your call (%d%% each): +%d to the assault each, and their guns at the fort." % [cfg.ally_join_chance * 100, cfg.ally_bonus]
				if Sieges.can_wait_for_allies(s, g) else "No allied captains left to call (make allies through bonds)."}, "allies"])
		var cost := Sieges.bribe_cost(g)
		options.append([{"text": "Bribe the garrison (%d gold)" % cost, "disabled": g.bribed or s.gold < cost,
			"tooltip": "Buy the officer of the watch, and the gate opens at night. Only one try.\n%d%% chance:\n%s\nFail: the gold is lost and the town is on alert." % [
				Dice.chance(Dice.sum_parts(Sieges.bribe_parts(s, g)), int(cfg.bribe_dc)) * 100, _lines(Sieges.bribe_parts(s, g))]}, "bribe"])
		if Sieges.uprising_possible(g):
			options.append([{"text": "Arm the townsfolk (%d gold)" % cfg.uprising_cost, "disabled": s.gold < cfg.uprising_cost,
				"tooltip": "The town is on the edge of revolt. Muskets and powder for the angry poor: the garrison loses %d%% of its men to street-fighting, and +%d to your assault." % [cfg.uprising_garrison * 100, cfg.uprising_bonus]}, "rising"])
		var raiders := mini(int(cfg.night_max_men), _landing(s))
		options.append([{"text": "Night raid with %d men" % raiders, "tooltip": _assault_tip(s, raiders, -1) + "\nA small party, no fort to face, but a failed raid is a massacre."}, "night"])
		options.append([{"text": "Storm the town", "tooltip": "Land your men and assault the walls: you'll choose how many, and where."}, "storm"])
		options.append([{"text": "Lift the siege", "tooltip": "Sail away. Come back within %d days and the damage you've done is still there, less what they repair (%d%% of the fort a day)." % [
			cfg.memory_days, cfg.fort_repair_per_day]}, "lift"])
		var pick: int = await world.dialog.ask("The siege of %s, day %d" % [Ports.port(g.port).name, int(Clock.day - g.day) + 1], _status(s), options.map(func(o): return o[0]))
		var text := ""
		match options[pick][1]:
			"scout":
				text = Sieges.scout(s, g, world.rng)
				text += _days(1)
			"guard":
				var outcome: String = await _battle(Encounters.generate(Ports.port(g.port).faction, world.rng, "pirate" if Ports.port(g.port).faction == "pirates" else "navy"), "attack")
				if outcome in ["enemy_struck", "enemy_sunk"]:
					g.guard = false
					text = "The guard ship is gone. The fort stands alone."
				else:
					return false
			"bombard":
				text = Sieges.bombard(s, stats, g, world.rng)
				text += _days(1)
			"blockade":
				text = _days(5)
			"allies":
				text = Sieges.call_allies(s, g, world.rng) + _days(3)
			"bribe":
				var r := Sieges.bribe(s, g, world.rng)
				world.hud.show_message(r.text)
				if r.taken:
					return true
			"rising":
				text = Sieges.raise_town(s, g)
			"night":
				var r := Sieges.assault(s, g, raiders, -1, world.rng)
				world.hud.show_message(r.text)
				if r.taken:
					return true
			"storm":
				var r := await _storm(s)
				if r.get("taken", false):
					return true
			"lift":
				world.hud.show_message("You lift the siege of %s." % Ports.port(g.port).name)
				return false
		if text != "":
			world.hud.show_message(text.strip_edges())
		if g.get("relief_here", false):
			g.erase("relief_here")
			world.hud.show_message("Sails to windward: the relief squadron for %s has come." % Ports.port(g.port).name)
			var outcome: String = await _battle(Encounters.generate(Ports.port(g.port).faction, world.rng, "pirate" if Ports.port(g.port).faction == "pirates" else "navy"), "defend")
			if not outcome in ["enemy_struck", "enemy_sunk"]:
				world.hud.show_message("The siege of %s is broken." % Ports.port(g.port).name)
				return false
			s.reputation.fear += 2
			g.relief = Clock.day + world.rng.randf_range(Sieges.cfg().relief_days[0], Sieges.cfg().relief_days[1])
			world.hud.show_message("The relief squadron is beaten off. They'll send another.")
	return false


## The landing: how many men, and where. {taken} or {} if you think better of it.
func _storm(s: Dictionary) -> Dictionary:
	var all := _landing(s)
	var sizes := [maxi(1, all / 3), maxi(1, all / 2), all]
	var pick: int = await world.dialog.ask("Storm %s" % Ports.port(g.port).name, "How many men go ashore? Those left aboard keep the ship; the more you land, the more you can lose.", [
		{"text": "A third: %d men" % sizes[0]}, {"text": "Half: %d men" % sizes[1]}, {"text": "Everyone but the ship-keepers: %d men" % sizes[2]}, {"text": "Think better of it"}])
	if pick == 3:
		return {}
	var men: int = sizes[pick]
	var sides := []
	for i in Sieges.cfg().sides.size():
		var known: String = " (the weak side)" if g.scouted and i == g.weak else ""
		sides.append({"text": "Attack %s%s" % [Sieges.side_name(i), known], "tooltip": _assault_tip(s, men, i)})
	sides.append({"text": "Think better of it"})
	var side: int = await world.dialog.ask("Where do you land?", "Scouts would tell you where the walls are weak. %s" % (
		"Yours did: %s." % Sieges.side_name(g.weak) if g.scouted else "You haven't scouted: one side is weaker, but you don't know which."), sides)
	if side == sides.size() - 1:
		return {}
	var r := Sieges.assault(s, g, men, side, world.rng)
	world.hud.show_message(r.text)
	return r


func _assault_tip(s: Dictionary, men: int, side: int) -> String:
	var ours := Sieges.assault_parts(s, g, men, side)
	if not g.scouted:
		ours = ours.filter(func(p): return p[0] != "A weak point in the walls")  # you don't know it's there
	var theirs := Sieges.defender_parts(g)
	return "%s%d%% chance:\n%s\nagainst %s" % ["" if g.scouted else "Unscouted, roughly ", Dice.contest_chance(Dice.sum_parts(ours), Dice.sum_parts(theirs)) * 100,
		_lines(ours), _lines(theirs) if not theirs.is_empty() else "the garrison"]


func _landing(s: Dictionary) -> int:
	return Sieges.landing(s)  # your consorts' crews too, less those who keep the ships


func _days(n: int) -> String:
	var r := Sieges.pass_days(g, n)
	for m in r.messages:
		world.hud.show_message(m)
	if r.relief:
		g.relief_here = true
	return ""


func _battle(enemy: Dictionary, mode: String) -> String:
	world.start_combat(enemy, mode)
	return await world.battle_over


func _status(s: Dictionary) -> String:
	var p := Ports.port(g.port)
	var lines := PackedStringArray()
	lines.append("The fort: %s." % ("silenced" if g.fort <= 0 else "%d%% of its guns still firing (%+d against you at the harbour front)" % [g.fort, Sieges.fort_mod(g)]))
	lines.append("The garrison: %s%d men%s." % ["" if g.scouted else "about ", g.garrison if g.scouted else int(round(g.garrison / 10.0) * 10), ", starving" if g.starving else ""])
	lines.append("Food behind the walls: %s." % ("none" if g.supplies <= 0 else ("%d days" % g.supplies if g.scouted else "unknown")))
	if g.guard:
		lines.append("A guard ship lies under the fort.")
	lines.append("The town is %s.%s" % [PortLife.describe(g.port), " The townsfolk have risen against the garrison." if g.uprising else ""])
	lines.append("Relief: %s." % ("expected in about %d days" % maxi(0, int(g.relief - Clock.day)) if g.scouted else "who knows when"))
	if not g.allies.is_empty():
		lines.append("With you: %s." % ", ".join(g.allies.map(func(k): return Bonds.name_of(k))))
	lines.append("\nYou have %d men fit to land, hull %d, gold %d." % [_landing(s), s.hull, s.gold])
	return "%s is under siege.\n\n%s%s" % [p.name, "\n".join(lines), Tutorial.note(s, "siege")]


## What you'd be taking on, for a tooltip before you start.
static func preview(id: String) -> String:
	var d := Sieges.defences(id)
	var f: String = Ports.port(id).faction
	return "About %d men%s, and a fort (%+d at full strength).\nAn act of war against %s: your standing drops, and without a commission against them it's piracy.\nThen scout it, bombard it, starve it, bribe it or storm it; and sack it, ransom it or hold it." % [
		d.garrison, " behind walls (%+d)" % d.walls if d.walls > 0 else "", d.fort, Career.fname(f) if f != "pirates" else "the Brethren"]


static func _lines(parts: Array) -> String:
	return "\n".join(parts.filter(func(p): return int(p[1]) != 0).map(func(p): return "  %s %+d" % [p[0], p[1]]))


## The town is yours. Sack it, ransom it back, or hold it.
func _after_the_fall(s: Dictionary, id: String) -> void:
	var p := Ports.port(id)
	var k: Dictionary = Sieges.cfg()
	var why := Sieges.hold_problem(s, id)
	var said := Voices.dress(s, "The governor hands over the keys of %s. What now?" % p.name, [
		{"text": "Sack it (about %d gold)" % Sieges.sack_gold(id), "tooltip": "Strip it bare: the biggest haul, and the crew's shares.\nThe town is ruined for a long time. Fear +%d, honour %d, notoriety +%d. %s never forgives (standing -%d), every other nation -%d; the governor becomes your enemy. The Brethren love it (+%d)." % [
			k.sack.fear, k.sack.honour, k.sack.notoriety, Career.fname(p.faction), k.sack.relation, k.sack.relation_all, k.sack.pirates],
			"voice": {"cruel": 2, "greedy": 1}},
		{"text": "Ransom it back (%d gold)" % Sieges.ransom_gold(id), "tooltip": "The town council pays to see you go, and the town is left standing.\nFear +%d, honour +%d, standing with %s -%d." % [
			k.ransom.fear, k.ransom.honour, Career.fname(p.faction), k.ransom.relation], "voice": {"cruel": -1, "decent": 1}},
		{"text": "Hold it as your own (leave %d men)" % Sieges.garrison_needed(id), "disabled": why != "",
			"tooltip": why if why != "" else "A base with walls, wharves and guns already built, and taxes of about %d gold a day.\nIt counts toward your %d bases. %s will send expeditions to take it back (standing -%d): garrison it and build up its fort." % [
				Bases.taxes(id) * k.hold.loyalty / 100.0, Data.rules.bases.max, Career.fname(p.faction), k.hold.relation], "voice": {"bold": 1}},
	], [], world.rng)
	var pick: int = await world.dialog.ask("%s is yours" % p.name, said.text, said.options)
	for m in Voices.heard(s, said.voices, pick):
		world.hud.show_message(m)
	match pick:
		0: world.hud.show_message(Sieges.sack(s, id))
		1: world.hud.show_message(Sieges.ransom(s, id))
		2:
			world.hud.show_message(Sieges.hold(s, id))
			world.ship.anchored_at = id
	world.ship.refresh_stats()
