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
		m.step(date.month)
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
