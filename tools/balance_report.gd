extends RefCounted
## The balance report itself (run it with tools/balance_sim.gd, which explains what it prints).

var root: Node


func run(tree_root: Node, args: Dictionary) -> void:
	root = tree_root
	_wars(int(args.get("runs", "20")), int(args.get("years", "50")))
	_bounty(float(args.get("attacks", "3")), int(args.get("sack", "12")))
	_towns()
	_invasions()


func _node(n: String) -> Node:
	return root.get_node(n)  # autoloads aren't known to a SceneTree script at compile time


func _rules() -> Dictionary:
	return _node("Data").rules


# ---- 1. wars ---------------------------------------------------------------------------

func _wars(runs: int, years: int) -> void:
	var f := _node("Factions")
	var clock := _node("Clock")
	var started := 0
	var war_days := 0
	var dynamic_days := 0
	var changes := 0
	var foreign_at_end := 0
	var first_war := []
	for r in runs:
		NewGame.build(_rules().start)
		f.rng.seed = r + 1
		f.reset()
		var owners := _owners()
		var timed := 0
		var first := -1.0
		for d in years * 365:
			clock.day = float(d)
			f.apply_history(true)
			f._invasions_due()
			if clock.date().day == 1:
				f.monthly()
			if f.timed.size() > timed:
				started += f.timed.size() - timed
				if first < 0.0:
					first = d / 365.0
			timed = f.timed.size()
			if not f.wars.is_empty():
				war_days += 1
			if not f.timed.is_empty():
				dynamic_days += 1
			if d % 30 == 0:
				var now := _owners()
				for id in now:
					if now[id] != owners[id]:
						changes += 1
				owners = now
		for id in owners:
			if owners[id] != _node("Data").table("ports")[id].get("orig_faction", owners[id]):
				foreign_at_end += 1
		first_war.append(first)
	clock.day = 0.0
	var total_years := float(runs * years)
	print("\n== Wars of the moment (%d runs x %d years from %s) ==" % [runs, years, _rules().time.start_date])
	print("  wars started on their own: %.1f per decade" % (started / total_years * 10.0))
	print("  first such war after: %s years (median)" % _median(first_war.filter(func(x): return x >= 0.0)))
	print("  some war on (history or not): %d%% of the time; a war of the moment: %d%%" % [war_days * 100.0 / (total_years * 365.0), dynamic_days * 100.0 / (total_years * 365.0)])
	print("  towns changing hands: %.1f per decade; still under a new flag at the end: %.1f per game" % [changes / total_years * 10.0, foreign_at_end / float(runs)])
	_node("Ports").reset()
	f.reset()


func _owners() -> Dictionary:
	var out := {}
	for id in _node("Data").table("ports"):
		out[id] = _node("Data").table("ports")[id].faction
	return out


# ---- 2. bounty --------------------------------------------------------------------------

func _bounty(attacks: float, sack_every: int) -> void:
	var s: Dictionary = NewGame.build(_rules().start).state
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var b: Dictionary = _rules().career.bounty
	var nations := ["spain", "spain", "england", "france", "dutch"]  # the Spanish Main is where the prizes are
	print("\n== The price on your head: %.0f ships a month%s ==" % [attacks, ", a sack every %d months" % sack_every if sack_every > 0 else ""])
	print("  month   total   most   hunter ship   hunters at most   spawn chance a day")
	var owed := 0.0
	for m in range(1, 37):
		owed += attacks
		while owed >= 1.0:
			owed -= 1.0
			Career.on_attack(s, Encounters.generate(nations[rng.randi() % nations.size()], rng, "merchant"))
		if sack_every > 0 and m % sack_every == 0:
			Career.add_bounty(s, "spain", b.sack)
		for d in 30:
			Career.bounty_daily(s)
		if m in [1, 3, 6, 12, 18, 24, 36]:
			var price := Career.bounty_total(s)
			var sh: Dictionary = _rules().shipping
			print("  %5d  %6d   %-6s %-12s  %d                 %.0f%%" % [m, price, Career.bounty_by(s), Career.hunter_ship(s) if Career.hunted(s) else "-",
				(int(sh.hunters_max) + int(price / b.per_hunter)) if Career.hunted(s) else 0,
				minf(1.0, sh.hunter_spawn_chance * (1.0 + price / b.per_hunter)) * 100.0 if Career.hunted(s) else 0.0])


# ---- 3. held towns ----------------------------------------------------------------------

func _towns() -> void:
	var h: Dictionary = _rules().sieges.hold
	var bases := _node("Bases")
	print("\n== Held towns: a day's money at each tax level (loyalty settled), and the odds against expeditions ==")
	print("  (run by an officer with authority and intimidation 10, at the minimum garrison, forewarned)")
	print("  town            size    fair: tax - upkeep = net (loyalty)   light          heavy          defence  vs expeditions 0..4 beaten")
	for id in _node("Data").table("ports"):
		var p: Dictionary = _node("Data").table("ports")[id]
		if "capital" in p.tags:
			continue
		var s: Dictionary = NewGame.build(_rules().start).state
		for i in 80:
			s.crew.append(_node("People").add(_node("People").generate({})))
		Sieges.hold(s, id)
		var b: Dictionary = bases.bases[id]
		var man: Dictionary = _node("People").generate({})  # an ordinary officer runs it
		man.stats.authority = 10
		man.stats.intimidation = 10
		b.manager = _node("People").add(man)
		var upkeep: float = bases.upkeep(b)
		var cols := []
		for level in ["fair", "light", "heavy"]:
			b.taxes = level
			b.loyalty = clampf(bases.loyalty_parts(id).reduce(func(a, x): return a + x[1], 0.0), 0.0, 100.0)
			var tax: float = bases.tax_income(id)
			cols.append("%4.1f - %4.1f = %+5.1f (%2d)" % [tax, upkeep, tax - upkeep, b.loyalty] if level == "fair" else "%+5.1f (%2d)" % [tax - upkeep, b.loyalty])
		b.taxes = "fair"
		b.loyalty = clampf(bases.loyalty_parts(id).reduce(func(a, x): return a + x[1], 0.0), 0.0, 100.0)
		b.raid = {"kind": "expedition", "warned": true, "faction": b.town.from, "label": "", "captain": "", "day": 0.0}
		var odds := []
		for failed in 5:
			b.town.failed = failed
			odds.append("%d%%" % int(Dice.contest_chance(Dice.sum_parts(bases.defence_parts(s, id)), bases.expedition_strength(id)) * 100))
		print("  %-15s %-7s %-34s %-14s %-14s %+3d      %s" % [p.name, p.size, cols[0], cols[1], cols[2], Dice.sum_parts(bases.defence_parts(s, id)), " ".join(odds)])
		bases.lose(id)
	var d: Array = h.expedition_days
	print("  (an expedition every %d-%d days; with you there, you fight it at sea with the shore guns, and win or lose adds +4/-3)" % [d[0], d[1]])


# ---- 4. invasions -----------------------------------------------------------------------

func _invasions() -> void:
	NewGame.build(_rules().start)
	var inv: Dictionary = _rules().diplomacy.invasion
	print("\n== Invasion squadrons (%+d) against the smaller towns ==" % inv.strength)
	for id in _node("Data").table("ports"):
		var p: Dictionary = _node("Data").table("ports")[id]
		if "capital" in p.tags or p.size == "large" or p.faction == "pirates":
			continue
		var def := Dice.sum_parts(_node("Factions").defence_parts(id))
		print("  %-15s defence %+3d   falls %d%%   (beaten at sea first: never)" % [p.name, def, int(Dice.contest_chance(int(inv.strength), def) * 100)])


static func _median(xs: Array) -> String:
	if xs.is_empty():
		return "never"
	xs.sort()
	return "%.1f" % xs[xs.size() / 2]
