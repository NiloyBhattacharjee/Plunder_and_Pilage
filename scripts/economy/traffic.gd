class_name Traffic
extends RefCounted
## Merchant traffic between the ports, as scheduled voyages (no nodes: it runs headless with the model).
## Each day every port sends out merchants. Each one picks the cargo and destination with the best expected
## profit per day: cheap here, dear there by the prices this port has heard of, less the voyage's risk. The
## goods leave the market when she sails and reach the other only when she arrives, so gaps between ports
## close slowly, and only while ships get through. Ships also carry news: a port's knowledge of prices
## elsewhere is only as fresh as the last ship in from there.
## Routes remember their losses (pirates, storms, the player): a risky route sees fewer merchants, so the
## port at the end of it runs short. The game draws a voyage as a ship only when it passes near the player.

var m: EconomyModel
var voyages: Array = []   # {id, faction, origin, dest, good, qty, depart, arrive, news}
var board := {}           # port -> port -> {day, m: {good: price multiplier}}: what each port knows of the others
var risk := {}            # "a>b" -> 0..1, recent losses on that route
var approach := {}        # port -> 0..1: losses near a port frighten every route into it, not just one
var routes := {}          # "a>b" -> {sailings, losses, recent}: for the map and the reports
var wars: Array = []      # [faction, faction] pairs at war, set by the game each day
var lost_log: Array = []  # [{day, route, good, qty, cause}] recent losses, for news
var waiting: Array = []   # [{port, faction, day}] ships that have unloaded and look for a cargo where they are
var next_id := 1
var _dist := {}           # "a>b" -> sailing days


func _init(model: EconomyModel) -> void:
	m = model
	for a in m.stock:
		board[a] = {}
		for b in m.stock:
			if a != b:
				_dist[a + ">" + b] = _days(a, b)
				board[a][b] = {"day": -30, "m": _prices(b)}


func cfg() -> Dictionary:
	return m.cfg.traffic


## Sailing days between two ports: great-circle distance with a detour for coasts and wind.
func _days(a: String, b: String) -> float:
	var pa: Dictionary = m.ports[a]
	var pb: Dictionary = m.ports[b]
	var la := deg_to_rad(pa.lat)
	var lb := deg_to_rad(pb.lat)
	var dl := deg_to_rad(pb.lon - pa.lon)
	var c := acos(clampf(sin(la) * sin(lb) + cos(la) * cos(lb) * cos(dl), -1.0, 1.0))
	return c * 3440.0 * cfg().detour / cfg().speed_nm_per_day


func days(a: String, b: String) -> float:
	return _dist[a + ">" + b]


func _prices(id: String) -> Dictionary:
	var out := {}
	for g in m.traded():
		out[g] = m.mult(id, g)
	return out


func route_risk(a: String, b: String) -> float:
	return maxf(risk.get(a + ">" + b, 0.0), approach.get(b, 0.0))


func at_war(f: String, g: String) -> bool:
	return wars.any(func(w): return (w[0] == f and w[1] == g) or (w[0] == g and w[1] == f))


## May a merchant of faction f trade at this port? Spain admits only its own (smugglers come later); pirates'
## dens deal with the Dutch and the French; pirates' own sloops trade only with the dens and the free ports.
func allowed(f: String, dest: String) -> bool:
	var p: Dictionary = m.ports[dest]
	if p.faction == f:
		return true
	if f == "pirates":
		return "free_port" in p.tags or "pirate_haven" in p.tags
	if at_war(f, p.faction):
		return false
	if p.faction == "spain":
		if m.world_has("fair_access:" + f) and m.fleets.for_port(dest).get("status", "") == "fair":
			return true  # the asiento's annual ship, at the fair
		return f in cfg().smugglers  # as smugglers: only forbidden goods, at the risk of the guarda costas
	if p.faction == "pirates":
		return f in cfg().haven_traders
	return true


# ---- the day ------------------------------------------------------------------------------------

func step(day: int, month: int) -> void:
	for id in risk.keys():
		risk[id] *= cfg().risk_decay
		if risk[id] < 0.005:
			risk.erase(id)
	for id in approach.keys():
		approach[id] *= cfg().risk_decay
		if approach[id] < 0.005:
			approach.erase(id)
	for r in routes.values():
		r.recent *= cfg().recent_decay
	_voyages_at_sea(day, month)
	_sailings(day, month)


func _voyages_at_sea(day: int, month: int) -> void:
	var storm: float = cfg().storm_loss_per_day[month - 1]
	for v in voyages.duplicate():
		if day >= v.arrive:
			if v.get("smuggler", false) and m.rng.randf() < cfg().guarda_costa_seizure:
				lose(v, "guarda_costa", day)  # caught at the last, off the Spanish coast
			else:
				_arrive(v, day)
			continue
		var key: String = v.origin + ">" + v.dest
		if m.rng.randf() < cfg().pirate_loss_per_day * m.world_mult("pirates") * (1.0 + risk.get(key, 0.0) * cfg().risk_breeds_pirates):
			lose(v, "pirates", day)
		elif m.rng.randf() < storm:
			lose(v, "storm", day)


func _arrive(v: Dictionary, day: int) -> void:
	voyages.erase(v)
	m.add(v.dest, v.good, v.qty)
	if m.rng.randf() < cfg().tramp_chance:  # she looks for a cargo here rather than going home empty
		waiting.append({"port": v.dest, "faction": v.faction, "day": day + int(cfg().loading_days)})
	for id in v.news:  # the news she carries, where it's fresher than what's known here
		if id != v.dest and v.news[id].day > board[v.dest][id].day:
			board[v.dest][id] = v.news[id]


## What this port has sent out that's still at sea: "dest:good" -> units. Merchants know what left their own port.
func _en_route_from(o: String) -> Dictionary:
	var out := {}
	for v in voyages:
		if v.origin == o:
			var k: String = v.dest + ":" + v.good
			out[k] = out.get(k, 0.0) + v.qty
	return out


## A voyage that never arrives: its cargo is gone, and the route remembers.
func lose(v: Dictionary, cause: String, day: int) -> void:
	voyages.erase(v)
	var key: String = v.origin + ">" + v.dest
	risk[key] = minf(1.0, risk.get(key, 0.0) + cfg().loss_risk[cause])
	if cause != "storm":  # a raider off the port takes ships from every direction
		approach[v.dest] = minf(1.0, approach.get(v.dest, 0.0) + cfg().loss_risk[cause] * cfg().approach_share)
	_route(key).losses += 1
	lost_log.append({"day": day, "route": key, "good": v.good, "qty": v.qty, "cause": cause})
	if lost_log.size() > 40:
		lost_log.pop_front()


func lose_id(id: String, cause: String, day: int) -> bool:
	for v in voyages:
		if v.id == id:
			lose(v, cause, day)
			return true
	return false


func _route(key: String) -> Dictionary:
	if not routes.has(key):
		routes[key] = {"sailings": 0, "losses": 0, "recent": 0.0}
	return routes[key]


func _sailings(day: int, month: int) -> void:
	var sail: float = m.cfg.sailing[month - 1]
	for o in m.stock:
		var p: Dictionary = m.ports[o]
		var rate: float = p.population / 1000.0 * cfg().sailings_per_1000 * sail * m.world_mult("sailings:" + o) * m.world_mult("sailings:" + p.faction)
		for t in p.tags:
			rate *= cfg().tag_sailings.get(t, 1.0)
		var n := int(rate) + (1 if m.rng.randf() < rate - int(rate) else 0)
		for k in n:
			_send(o, day, month, p.faction)
	for w in waiting.duplicate():
		if w.day <= day:
			waiting.erase(w)
			_send(w.port, day, month, w.faction)


## One merchant leaves port o, if any cargo is worth carrying anywhere she may go.
func _send(o: String, day: int, month: int, f: String) -> void:
	var cap: float = m.rng.randf_range(cfg().cargo_tons[0], cfg().cargo_tons[1])
	var storm_days: float = m.cfg.traffic.storm_loss_per_day[month - 1]
	var options := []  # [value, {dest, good, qty, sell, t}]
	var sent := _en_route_from(o)
	for d in board[o]:
		if not allowed(f, d):
			continue
		var t: float = days(o, d) + cfg().loading_days
		var safe: float = maxf(0.0, 1.0 - route_risk(o, d) * cfg().risk_aversion - (storm_days + cfg().pirate_loss_per_day) * t)
		var spread_d: float = m.cfg.spread[m.ports[d].size] / 2.0
		var known: Dictionary = board[o][d].m
		var smuggling: bool = m.ports[d].faction == "spain" and f != "spain"
		var hold := cap
		if smuggling:
			safe *= 1.0 - cfg().guarda_costa_seizure
			hold *= cfg().smuggler_cargo  # a fast sloop, not a fat merchantman
		var enumerated: Array = m.ports[o].laws.get("enumerated", []) if f != m.ports[o].faction else []
		for g in m.traded():
			if (smuggling and not g in m.ports[d].laws.contraband) or g in enumerated:
				continue
			var buy := m.price(o, g, true)
			var normal_d: float = m.params[d][g].normal
			# what she expects to fetch: the price heard, lowered by what this port has already sent that way
			var coming: float = sent.get(d + ":" + g, 0.0)
			var expect: float = clampf(known[g] * pow(normal_d / (normal_d + coming), m.cfg.elasticity[m.goods[g].demand]), m.cfg.price_clamp[0], m.cfg.price_clamp[1])
			var sell: float = m.goods[g].base_price * expect * (1.0 - spread_d)
			if sell < buy * (1.0 + cfg().min_margin):
				continue
			var w := float(m.goods[g].weight)
			var spare: float = m.stock[o][g] - m.params[o][g].normal * cfg().keep_home
			var qty := minf(minf(hold / w, spare), normal_d * cfg().max_share_of_dest)  # no one ship floods a market
			if qty < 1.0:
				continue
			var value: float = (sell - buy) * qty * safe / t
			options.append([value, {"dest": d, "good": g, "qty": qty, "sell": sell, "t": t}])
	if options.is_empty():
		return
	options.sort_custom(func(a, b): return a[0] > b[0])
	var best: Dictionary = options[m.rng.randi() % mini(int(cfg().choose_among), options.size())][1]  # merchants don't all think alike
	var g: String = best.good
	var qty := 0
	while qty < int(best.qty) and m.unit_price(o, g, m.stock[o][g] - qty, true) < best.sell / (1.0 + cfg().min_margin):
		qty += 1  # buy until the next unit isn't worth carrying
	if qty <= 0:
		return
	m.add(o, g, -qty)
	var news: Dictionary = board[o].duplicate()  # what's known here goes with her, and the latest from here
	news[o] = {"day": day, "m": _prices(o)}
	var key: String = o + ">" + best.dest
	_route(key).sailings += 1
	_route(key).recent += 1.0
	voyages.append({"id": "v%d" % next_id, "faction": f, "origin": o, "dest": best.dest, "good": g, "qty": qty,
		"depart": day, "arrive": day + int(round(best.t * m.rng.randf_range(0.85, 1.2))), "news": news,
		"smuggler": m.ports[best.dest].faction == "spain" and f != "spain"})
	next_id += 1


# ---- what it means --------------------------------------------------------------------------------

## The riskiest route into a port and its risk: ["origin", risk], or ["", 0].
func worst_route_into(dest: String) -> Array:
	var worst := ["", 0.0]
	for key in risk:
		if key.ends_with(">" + dest) and risk[key] > worst[1]:
			worst = [key.get_slice(">", 0), risk[key]]
	if approach.get(dest, 0.0) > worst[1]:
		worst = [dest, approach[dest]]
	return worst


func save_state() -> Dictionary:
	return {"voyages": voyages, "board": board, "risk": risk, "routes": routes, "lost_log": lost_log, "next_id": next_id, "waiting": waiting,
		"approach": approach}


func load_state(d: Dictionary) -> void:
	voyages = d.voyages
	for v in voyages:
		v.depart = int(v.depart)
		v.arrive = int(v.arrive)
		v.qty = int(v.qty)
	board = d.board
	risk = d.risk
	routes = d.routes
	lost_log = d.lost_log
	next_id = int(d.next_id)
	waiting = d.get("waiting", [])
	approach = d.get("approach", {})
	for w in waiting:
		w.day = int(w.day)
