class_name Shocks
extends RefCounted
## Random shocks (data/shocks.json): hurricanes, epidemics, crop failures and bumper harvests, bankruptcies,
## warehouse fires, reinforced garrisons, a shortage of coin, a wave of piracy. Every day there's a chance one
## strikes somewhere; each has the months it can happen in, the ports it can hit (by tag), a weight, and effects
## from the shared vocabulary (EconomyModel.apply_effect). Its news goes out at sailing speed, so the player can
## react if they hear in time.

var m: EconomyModel
var events: Array = []   # [{shock, port, day, news}] for the game to report


func _init(model: EconomyModel) -> void:
	m = model


func table() -> Dictionary:
	var out := {}
	var t: Dictionary = m.cfg.get("shocks", {})
	for id in t:
		if not id.begins_with("_"):
			out[id] = t[id]
	return out


func step(day: int, month: int) -> void:
	if m.rng.randf() >= float(m.cfg.get("shock_chance_per_day", 0.0)):
		return
	var pool := []  # [shock id, port, weight]
	for id in table():
		var sh: Dictionary = table()[id]
		if sh.has("months") and not month in sh.months:
			continue
		for p in m.stock:
			var tags: Array = m.ports[p].tags
			if sh.has("tags") and not sh.tags.any(func(t): return t in tags):
				continue
			pool.append([id, p, float(sh.get("weight", 1.0))])
	if pool.is_empty():
		return
	var total := 0.0
	for x in pool:
		total += x[2]
	var r := m.rng.randf() * total
	for x in pool:
		r -= x[2]
		if r <= 0.0:
			strike(x[0], x[1], day)
			return


## Sets one shock off in one port. Returns the news.
func strike(id: String, port: String, day: int) -> String:
	var sh: Dictionary = table()[id]
	var pick := ""  # "random" (something made here) or "random_used" (something it ships in): chosen once, named in the news
	for e in sh.effects:
		var eff: Dictionary = e.duplicate(true)
		if eff.get("goods", null) is String and eff.goods in ["random", "random_used"]:
			if pick == "":
				var pool: Array = m.produces(port) if eff.goods == "random" else m.traded().filter(func(g): return m.params[port][g].make <= 0.0)
				if pool.is_empty():
					continue
				pick = pool[m.rng.randi() % pool.size()]
			eff.goods = [pick]
		eff.reason = eff.get("reason", sh.name)
		m.apply_effect(port, eff)
	var news: String = sh.news.format({"port": m.ports[port].name, "good": m.goods[pick].name.to_lower() if pick != "" else ""})
	events.append({"shock": id, "port": port, "day": day, "news": news})
	return news


func take_events() -> Array:
	var out := events
	events = []
	return out
