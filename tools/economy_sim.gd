extends SceneTree
## Runs the economy alone, headless, for years of game time, and writes what happened to a CSV: one row per
## port, good and week. Then prints a few health checks. Same seed, same run.
##
##   bin/Godot_v4.7.2-stable_win64_console.exe --headless --path . -s tools/economy_sim.gd -- --years 15 --seed 1
##
## Options: --years N (default 15), --seed N (default 1), --out PATH (default tools/out/economy.csv),
## --raid ORIGIN:DEST:DAYS:CHANCE (a raider working that route from the start of year 2: each day, each ship on it
## is taken with CHANCE). Also writes routes.csv beside the main file: sailings, losses and risk per route per week.

var _done := false
var Data: Node   # autoloads aren't known to a SceneTree script at compile time: look them up instead
var Clock: Node


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	Data = root.get_node("Data")
	Clock = root.get_node("Clock")
	var args := _args()
	var years := int(args.get("years", "15"))
	var seed := int(args.get("seed", "1"))
	var out: String = args.get("out", "tools/out/economy.csv")
	var m := EconomyModel.new()
	m.setup(Data.table("goods"), Data.table("ports"), Data.table("economy"), seed)
	m.warm_up(int(Data.table("economy").warm_up_days), Clock.date_of(0).month)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out.get_base_dir()))
	var f := FileAccess.open("res://" + out, FileAccess.WRITE)
	f.store_line("week,date,port,good,stock,normal,mult,buy,sell,make,use,imports,exports")
	var stats := {}  # port:good -> {min, max, sum, n, clamped}
	var raid: Array = args.get("raid", "").split(":") if args.has("raid") else []
	var rf := FileAccess.open("res://" + out.get_base_dir().path_join("routes.csv"), FileAccess.WRITE)
	rf.store_line("week,route,sailings,losses,risk")
	var at_sea := 0.0
	var days := years * 365
	for d in days:
		var date: Dictionary = Clock.date_of(d)
		if raid.size() == 4 and d >= 365 and d < 365 + int(raid[2]):
			for v in m.traffic.voyages.duplicate():
				if v.origin == raid[0] and v.dest == raid[1] and m.rng.randf() < float(raid[3]):
					m.traffic.lose(v, "player", m.day)
		_history(m, date)
		m.step(date.month, date.year)
		if date.month == 1 and date.day == 1:
			_brethren_line(m, date.year)
		at_sea += m.traffic.voyages.size()
		if d % 7 != 0:
			continue
		for key in m.traffic.routes:
			var r: Dictionary = m.traffic.routes[key]
			rf.store_line("%d,%s,%d,%d,%.3f" % [d / 7, key, r.sailings, r.losses, m.traffic.risk.get(key, 0.0)])
		var date_text := "%04d-%02d-%02d" % [date.year, date.month, date.day]
		for id in m.stock:
			for g in m.traded():
				var fl := m.flows(id, g, date.month)
				var mu := m.mult(id, g)
				f.store_line("%d,%s,%s,%s,%.1f,%.1f,%.3f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f" % [d / 7, date_text, id, g, m.stock[id][g],
					m.params[id][g].normal, mu, m.price(id, g, true), m.price(id, g, false), fl.make, fl.use, fl.imp, fl.exp])
				var key: String = id + ":" + g
				var st: Dictionary = stats.get(key, {"min": 99.0, "max": 0.0, "sum": 0.0, "n": 0, "clamped": 0})
				st.min = minf(st.min, mu)
				st.max = maxf(st.max, mu)
				st.sum += mu
				st.n += 1
				var c: Array = Data.table("economy").price_clamp
				if mu <= c[0] + 0.001 or mu >= c[1] - 0.001:
					st.clamped += 1
				stats[key] = st
	f.close()
	rf.close()
	print("Wrote %s and routes.csv: %d years, seed %d." % [out, years, seed])
	var sailings := 0
	var losses := 0
	for r in m.traffic.routes.values():
		sailings += r.sailings
		losses += r.losses
	print("Merchants: %d voyages a year, %.0f at sea on an average day, %.1f%% lost." % [sailings / years, at_sea / days, 100.0 * losses / maxf(1, sailings)])
	_report(stats)
	return true


## The timeline's effects on the market (data/history.json), applied on their dates: the economy alone, with no
## player, so only the world's own effects (the game applies the rest through EconomyEffects).
var _applied := {}


func _history(m: EconomyModel, date: Dictionary) -> void:
	var stamp := "%04d-%02d-%02d" % [date.year, date.month, date.day]
	for id in Data.table("history"):
		var ev = Data.table("history")[id]
		if id.begins_with("_") or _applied.has(id) or ev.date > stamp:
			continue
		_applied[id] = true
		_wars_and_pardons(m, ev)  # what Factions does in the game
		if not ev.has("effects"):
			continue
		if ev.date < "%04d-01-01" % (date.year - 1):
			continue  # long before this run began
		for e in ev.effects:
			var port: String = e.get("port", ev.get("port", ""))
			if m.stock.has(port) and m.apply_effect(port, e):
				continue
			match e.type:
				"pirate_spawn_rate_multiplier": m.set_world("pirates", float(e.value), int(e.get("days", 365)))
				"trade_slump":
					m.set_world("sailings:" + e.faction, float(e.get("sailings", 0.6)), int(e.days))
					m.set_world("imports:" + e.faction, float(e.get("imports", 0.7)), int(e.days))
				"fleet_blocked": m.set_world("fleet_blocked:" + e.fleet, true, int(e.days))
				"fair_access": m.set_world("fair_access:" + e.faction, true, int(e.get("days", -1)))
		print("  %s: %s" % [stamp, id])


func _wars_and_pardons(m: EconomyModel, ev: Dictionary) -> void:
	match ev.kind:
		"war", "peace":
			for a in ev.sides[0]:
				for b in ev.sides[1]:
					var pair := [a, b] if a < b else [b, a]
					if ev.kind == "war" and not pair in m.traffic.wars:
						m.traffic.wars.append(pair)
					elif ev.kind == "peace":
						m.traffic.wars.erase(pair)
		"pardon":
			m.brethren.pardons.append_array(ev.factions)
		"pardon_end":
			for f in ev.factions:
				m.brethren.pardons.erase(f)


## The pirates and the navy each year, against the historical numbers.
func _brethren_line(m: EconomyModel, year: int) -> void:
	var b := m.brethren
	var navy := 0.0
	for f in b.navy:
		navy += b.navy[f]
	var at_home := b.companies.filter(func(co): return not co.away).size()
	print("  %d  pirates %5d in %2d companies (%2d in the islands)  idle seamen %5d  in service %5d  men-of-war %4.1f  %s  hanged %d, pardoned %d" % [
		year, b.men(), b.companies.size(), at_home, int(b.idle), int(b.service), navy, "war" if not m.traffic.wars.is_empty() else "   ",
		b.tally.hanged, b.tally.pardoned])


func _report(stats: Dictionary) -> void:
	var pinned := []
	var swings := []
	for key in stats:
		var st: Dictionary = stats[key]
		if st.clamped > st.n * 0.2:
			pinned.append("%s (%d%% of weeks)" % [key, 100 * st.clamped / st.n])
		swings.append([key, st.max / maxf(st.min, 0.01), st.sum / st.n])
	print("Prices pinned at a limit for over a fifth of the time: %s" % (", ".join(pinned) if not pinned.is_empty() else "none"))
	swings.sort_custom(func(a, b): return a[1] > b[1])
	print("Widest swings (high / low, mean multiplier):")
	for s in swings.slice(0, 8):
		print("  %s  x%.1f  mean %.2f" % [s[0], s[1], s[2]])
	var means := {}
	for key in stats:
		var g: String = key.get_slice(":", 1)
		if not means.has(g):
			means[g] = []
		means[g].append([key.get_slice(":", 0), stats[key].sum / stats[key].n])
	print("Cheapest and dearest port for each good (mean multiplier):")
	for g in means:
		var l: Array = means[g]
		l.sort_custom(func(a, b): return a[1] < b[1])
		print("  %-13s %s %.2f  ->  %s %.2f" % [g, l[0][0], l[0][1], l[-1][0], l[-1][1]])


func _args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].trim_prefix("--")] = a[i + 1]
	return out
