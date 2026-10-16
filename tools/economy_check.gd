extends SceneTree
## The economy's health checks, headless (market milestone 6). Run after any change to the economy data:
##
##   bin/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/economy_check.gd -- --years 15 --seed 1
##
## Prints PASS or FAIL for each:
##   1. No price stays pinned at its floor or ceiling for long.
##   2. No port runs out of food for good, or piles up stock forever.
##   3. Price gaps between ports open and close (a set of real trade runs).
##   4. Seasons and fleets repeat: sugar is cheap after the harvest; the fair floods Cartagena.
##   5. A shock (a warehouse fire) fades back to normal within half a year.
##   6. Raiding a route for a season raises prices at its end.
## 5 and 6 are paired runs: the same seed with and without the shock or the raid, so only it differs.

var Data: Node
var Clock: Node
var failures := 0


func _process(_delta: float) -> bool:
	Data = root.get_node("Data")
	Clock = root.get_node("Clock")
	var args := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			args[a[i].trim_prefix("--")] = a[i + 1]
	var years := int(args.get("years", "15"))
	var seed := int(args.get("seed", "1"))
	print("Economy checks: %d years, seed %d" % [years, seed])
	_long_run(years, seed)
	_shock(seed)
	_raid(seed)
	print("%s: %d check%s failed." % ["ALL PASS" if failures == 0 else "FAILURES", failures, "" if failures == 1 else "s"])
	return true


func _model(seed: int) -> EconomyModel:
	var m := EconomyModel.new()
	m.setup(Data.table("goods"), Data.table("ports"), Data.table("economy"), seed)
	m.warm_up(int(Data.table("economy").warm_up_days), 1, 1680)
	return m


func _report(name: String, ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
	print("  %s  %s: %s" % ["PASS" if ok else "FAIL", name, detail])


func _long_run(years: int, seed: int) -> void:
	var m := _model(seed)
	var clamp: Array = Data.table("economy").price_clamp
	var pinned := {}    # port:good -> weeks at a limit
	var empty_run := {} # port -> current run of weeks with food almost gone
	var worst_empty := {}
	var pile := {}      # port:good -> current run of weeks at over 8x normal stock
	var worst_pile := {}
	var weeks := 0
	var gaps := {"bridgetown>nassau:sugar": [], "tortuga>port_royal:hides": [], "maracaibo>port_royal:cocoa": [],
		"santo_domingo>bridgetown:food": [], "st_eustatius>cartagena:cloth": [], "port_royal>tortuga:rum": []}
	var sugar := {}     # year -> {spring: [], autumn: []}
	var fair_drops := [0, 0]  # fairs where cloth fell, fairs seen
	var before_fair := {}
	for d in years * 365:
		var date: Dictionary = Clock.date_of(d)
		var cloth_before := m.mult("cartagena", "cloth")  # yesterday's price, before any fleet lands today
		m.step(date.month, date.year)
		for ev in m.fleets.take_events():
			if ev.fleet == "galeones" and ev.kind == "arrived":
				before_fair = {"mult": cloth_before, "day": d}
		if not before_fair.is_empty() and d == before_fair.day + 21:  # three weeks into the fair
			fair_drops[1] += 1
			if m.mult("cartagena", "cloth") < before_fair.mult:
				fair_drops[0] += 1
			before_fair = {}
		if d % 7 != 0:
			continue
		weeks += 1
		var y: int = date.year
		if not sugar.has(y):
			sugar[y] = {"spring": [], "autumn": []}
		if date.month in [4, 5]:
			sugar[y].spring.append(m.mult("bridgetown", "sugar"))
		elif date.month in [10, 11]:
			sugar[y].autumn.append(m.mult("bridgetown", "sugar"))
		for id in m.stock:
			var low: bool = m.stock[id].food < m.params[id].food.normal * 0.05
			empty_run[id] = empty_run.get(id, 0) + 1 if low else 0
			worst_empty[id] = maxi(worst_empty.get(id, 0), empty_run[id])
			for g in m.traded():
				var mu := m.mult(id, g)
				if mu <= clamp[0] + 0.001 or mu >= clamp[1] - 0.001:
					pinned[id + ":" + g] = pinned.get(id + ":" + g, 0) + 1
				var key: String = id + ":" + g
				pile[key] = pile.get(key, 0) + 1 if m.stock[id][g] > m.params[id][g].normal * 8.0 else 0
				worst_pile[key] = maxi(worst_pile.get(key, 0), pile[key])
		for k in gaps:
			var o: String = k.get_slice(">", 0)
			var dg: String = k.get_slice(">", 1)
			var dest := dg.get_slice(":", 0)
			var g := dg.get_slice(":", 1)
			gaps[k].append(m.price(dest, g, false) / m.price(o, g, true))
	# 1
	var stuck := pinned.keys().filter(func(k): return pinned[k] > weeks * 0.2)
	_report("Prices never pinned long", stuck.is_empty(), "none at a limit over a fifth of the time" if stuck.is_empty() else ", ".join(stuck.map(func(k): return "%s %d%%" % [k, 100 * pinned[k] / weeks])))
	# 2
	var starving := worst_empty.keys().filter(func(id): return worst_empty[id] > 8)
	var piling := worst_pile.keys().filter(func(k): return worst_pile[k] > 26)
	_report("Food never runs out for good", starving.is_empty(), "longest run without food: %d weeks" % worst_empty.values().max() if starving.is_empty() else ", ".join(starving))
	_report("Stock never piles up forever", piling.is_empty(), "nothing over 8x its normal stock for half a year" if piling.is_empty() else ", ".join(piling))
	# 3
	var lines := []
	var gaps_ok := true
	for k in gaps:
		var opens := 0
		var open := false
		var profitable := 0
		for r in gaps[k]:
			if not open and r > 1.35:
				opens += 1
				open = true
			elif open and r < 1.1:
				open = false
			if r > 1.35:
				profitable += 1
		var share: float = float(profitable) / gaps[k].size()
		var smuggling: bool = k.contains("cartagena")  # the law keeps this one open: smuggling's premium
		var ok: bool = opens >= 3 or (smuggling and share > 0.5)
		gaps_ok = gaps_ok and ok
		lines.append("%s opened %dx, profitable %d%% of weeks" % [k, opens, int(share * 100)])
	_report("Price gaps open and close", gaps_ok, "; ".join(lines))
	# 4
	var years_ok := 0
	var years_seen := 0
	for y in sugar:
		if sugar[y].spring.size() > 0 and sugar[y].autumn.size() > 0:
			years_seen += 1
			var sp: float = sugar[y].spring.reduce(func(a, x): return a + x, 0.0) / sugar[y].spring.size()
			var au: float = sugar[y].autumn.reduce(func(a, x): return a + x, 0.0) / sugar[y].autumn.size()
			if sp < au:
				years_ok += 1
	_report("Sugar is cheap after the harvest", years_ok >= years_seen * 0.8, "cheaper in spring than autumn in %d of %d years" % [years_ok, years_seen])
	_report("The fair floods the Spanish Main", fair_drops[1] > 0 and fair_drops[0] >= fair_drops[1] * 0.7,
		"Cartagena's cloth fell during %d of %d fairs" % [fair_drops[0], fair_drops[1]])


func _shock(seed: int) -> void:
	var calm := _model(seed)
	var hit := _model(seed)
	hit.cfg = Data.table("economy").duplicate(true)
	calm.cfg = hit.cfg
	hit.cfg.shock_chance_per_day = 0.0  # only our fire, so the runs differ by it alone
	for d in 30:
		calm.step(3)
		hit.step(3)
	hit.apply_effect("port_royal", {"type": "stock", "goods": "all", "mult": 0.4})
	var weeks := -1
	for w in 52:
		for k in 7:
			calm.step((2 + w / 4) % 12 + 1)
			hit.step((2 + w / 4) % 12 + 1)
		var off := 0.0  # the average gap across goods: the two runs drift apart a little on their own (merchants choose differently)
		for g in hit.traded():
			off += absf(hit.mult("port_royal", g) / calm.mult("port_royal", g) - 1.0)
		off /= hit.traded().size()
		if w == 0:
			print("    the fire's first week: prices %+.0f%% on average" % (off * 100))
		if off < 0.1 and weeks < 0:
			weeks = w + 1
	_report("A shock fades", weeks > 0 and weeks <= 26, "a fire that burned 60%% of Port Royal's stock: prices back within 10%% on average in %s" % ("%d weeks" % weeks if weeks > 0 else "over a year"))


func _raid(seed: int) -> void:
	var calm := _model(seed)
	var raided := _model(seed)
	calm.cfg = Data.table("economy").duplicate(true)
	calm.cfg.shock_chance_per_day = 0.0
	raided.cfg = calm.cfg
	var busiest := ""  # the busiest route into a pirate haven: few ships feed them, so a raider is felt
	for k in calm.traffic.routes:
		var into: String = k.get_slice(">", 1)
		if "pirate_haven" in calm.ports[into].tags and (busiest == "" or calm.traffic.routes[k].sailings > calm.traffic.routes[busiest].sailings):
			busiest = k
	var dest := busiest.get_slice(">", 1)
	var o := busiest.get_slice(">", 0)
	var carried := {}  # the goods that route carries
	var sums := [0.0, 0.0]
	for d in 180:
		for v in raided.traffic.voyages.duplicate():
			if v.origin == o and v.dest == dest and raided.rng.randf() < 0.25:
				raided.traffic.lose(v, "player", raided.day)
		for v in calm.traffic.voyages:
			if v.origin == o and v.dest == dest:
				carried[v.good] = true
		calm.step(6)
		raided.step(6)
		if d >= 60:  # once the raids have bitten
			for g in carried:
				sums[0] += calm.mult(dest, g)
				sums[1] += raided.mult(dest, g)
	var rise: float = sums[1] / maxf(sums[0], 0.001) - 1.0
	_report("Raiding a route raises prices at its end", rise > 0.05, "a season raiding %s: %s in %s %+.0f%% against a calm season" % [
		busiest, ", ".join(carried.keys()), dest, rise * 100])
