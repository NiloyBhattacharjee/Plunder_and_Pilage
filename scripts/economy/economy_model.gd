class_name EconomyModel
extends RefCounted
## The trade economy as plain data and maths: no nodes, no scenes, no clock, so it runs the same in the game
## (the Economy autoload), in tests, and headless for years at a time (tools/economy_sim.gd).
## Every port, every day, for every good:
##   stock += production x season + imports - consumption - exports - spoilage
## Consumption falls when a good is dear; outside merchants bring more when it's dear and carry more off when
## it's cheap. So each port settles at a price of its own, and a big trade knocks it off balance for weeks.
## Price = base x (normal stock / stock) ^ elasticity, clamped. All the knobs are in data/economy.json.

var goods: Dictionary
var ports: Dictionary
var cfg: Dictionary
var rng := RandomNumberGenerator.new()
var stock := {}      # port -> good -> units in the warehouses
var mods := {}       # port -> [{good, make, use, days_left, reason, rumour}]: timed shocks on production and use
var history := {}    # port -> good -> weekly price multipliers, oldest first
var params := {}     # port -> good -> {make, use, imp, exp, normal}, fixed by the data
var traffic: Traffic # merchant voyages between the ports (scripts/economy/traffic.gd)
var fleets: Fleets   # the treasure fleets and sugar convoys (scripts/economy/fleets.gd)
var shocks: Shocks   # random shocks: hurricanes, epidemics, fires... (scripts/economy/shocks.gd)
var world := {}      # key -> {value, until}: world conditions in force (pirates, sailings:<faction or port>,
                     # imports:<faction>, spread:<port>, fleet_blocked:<fleet>, fair_access:<faction>, state:<key>)
var day := 0         # days the model has run
var _seasons := {}
var _traded: Array = []


func setup(goods_t: Dictionary, ports_t: Dictionary, cfg_t: Dictionary, seed: int) -> void:
	goods = goods_t
	ports = ports_t
	cfg = cfg_t
	rng.seed = seed
	_seasons = {}
	for k in cfg.seasons:
		if not k.begins_with("_"):
			var curve: Array = cfg.seasons[k]
			var mean: float = curve.reduce(func(a, x): return a + x, 0.0) / curve.size()
			_seasons[k] = curve.map(func(x): return x / mean)
	_traded = goods.keys().filter(func(g): return not g.begins_with("_") and goods[g].get("economy", true))
	params = {}
	stock = {}
	mods = {}
	history = {}
	for id in ports:
		if id.begins_with("_"):
			continue
		params[id] = {}
		stock[id] = {}
		mods[id] = []
		history[id] = {}
		for g in _traded:
			params[id][g] = _params(id, g)
			stock[id][g] = params[id][g].normal
			history[id][g] = []
	day = 0
	traffic = Traffic.new(self)
	fleets = Fleets.new(self)
	shocks = Shocks.new(self)
	world = {}


func traded() -> Array:
	return _traded


func is_traded(good: String) -> bool:
	return good in _traded


func _params(id: String, g: String) -> Dictionary:
	var p: Dictionary = ports[id]
	var gd: Dictionary = goods[g]
	var use: float = p.population / 1000.0 * float(cfg.per_1000.get(g, 0.0))
	var o: Dictionary = cfg.outside
	var imp: float = o.import[gd.origin] * o.faction_import.get(p.faction, {}).get(gd.origin, 1.0)
	var ex: float = o.export[gd.origin]
	var rex: float = o.reexport[gd.origin]
	for t in p.tags:
		use *= cfg.tag_use.get(t, {}).get(g, 1.0)
		imp *= o.tag_import.get(t, 1.0)
		ex *= o.tag_export.get(t, 1.0)
		rex *= o.tag_export.get(t, 1.0)
	use *= p.get("use", {}).get(g, 1.0)
	imp *= p.get("import_mult", 1.0)  # a port's own extra supply (Portobelo's mule trains from Panama)
	var make := float(p.make.get(g, 0.0))
	return {"make": make, "use": use, "imp": imp, "exp": ex, "rex": rex, "normal": maxf(cfg.min_normal, (make + use) * cfg.cover_days)}


# ---- prices ------------------------------------------------------------------------------------

## The price multiplier at a given stock: base x this is the middle price.
func mult_at(id: String, g: String, s: float) -> float:
	var e: float = cfg.elasticity[goods[g].demand]
	return clampf(pow(params[id][g].normal / maxf(s, 0.01), e), cfg.price_clamp[0], cfg.price_clamp[1])


func mult(id: String, g: String) -> float:
	return mult_at(id, g, stock[id][g]) if is_traded(g) else 1.0


## One unit's price at a given stock: the middle price, the merchant's spread (wider in small ports; spread_mult
## carries haggling and standing), and the duty.
func unit_price(id: String, g: String, s: float, buying: bool, spread_mult := 1.0, duty := 0.0) -> float:
	var mid: float = goods[g].base_price * (mult_at(id, g, s) if is_traded(g) else 1.0)
	var half: float = cfg.spread[ports[id].size] * spread_mult * world_mult("spread:" + id) / 2.0
	return mid * (1.0 + half if buying else 1.0 - half) * (1.0 + duty if buying else 1.0 - duty)


## A price for a given multiplier rather than today's stock: for prices remembered or heard of.
func price_at_mult(id: String, g: String, mult: float, buying: bool, spread_mult := 1.0, duty := 0.0) -> float:
	var half: float = cfg.spread[ports[id].size] * spread_mult / 2.0
	return goods[g].base_price * mult * (1.0 + half if buying else 1.0 - half) * (1.0 + duty if buying else 1.0 - duty)


func price(id: String, g: String, buying: bool, spread_mult := 1.0, duty := 0.0) -> float:
	return unit_price(id, g, stock[id].get(g, 1.0), buying, spread_mult, duty)


## The total for qty units. Each unit moves the stock, so a big trade gets steadily worse prices.
func quote(id: String, g: String, qty: int, buying: bool, spread_mult := 1.0, duty := 0.0) -> int:
	var s: float = stock[id].get(g, 1.0)
	var total := 0.0
	for i in qty:
		total += unit_price(id, g, s - i if buying else s + i, buying, spread_mult, duty)
	return int(round(total))


## Most units the market will sell before it runs dry.
func max_buy(id: String, g: String) -> int:
	return 100000 if not is_traded(g) else maxi(0, int(stock[id][g] - 1.0))


func add(id: String, g: String, qty: float) -> void:
	if is_traded(g):
		stock[id][g] = maxf(0.0, stock[id][g] + qty)


## "scarce", "plenty" or "normal", from the price.
func level(id: String, g: String) -> String:
	var m := mult(id, g)
	if m >= cfg.levels.scarce:
		return "scarce"
	if m <= cfg.levels.plenty:
		return "plenty"
	return "normal"


# ---- the day ------------------------------------------------------------------------------------

## Today's flows for one good in one port, at today's price: {make, use, imp, exp, spoil}.
func flows(id: String, g: String, month: int) -> Dictionary:
	var pr: Dictionary = params[id][g]
	var gd: Dictionary = goods[g]
	var m := mult(id, g)
	var make_mod := 1.0
	var use_mod := 1.0
	for x in mods[id]:
		if x.good == g:
			make_mod *= x.get("make", 1.0)
			use_mod *= x.get("use", 1.0)
	var cap: float = cfg.flow_cap
	var sail: float = cfg.sailing[month - 1]
	var sr: float = cfg.supply_response
	return {
		"make": pr.make * _seasons[gd.season][month - 1] * make_mod,
		"use": pr.use * use_mod * fleets.use_mult(id, g) * minf(cap, pow(m, -cfg.demand_response[gd.demand])),
		"imp": pr.use * pr.imp * sail * world_mult("imports:" + ports[id].faction) * world_mult("imports:" + id) * minf(cap, pow(m, sr)),
		"exp": (pr.make * pr.exp + pr.use * pr.rex) * sail * minf(cap, pow(m, -sr)),
		"spoil": stock[id][g] * gd.get("spoils", 0.0),
	}


## One day for every port, and the ships between them. `month` is 1-12; `year` matters only to the fleets
## (irregular after 1700); without one, each 365 days counts as a new year.
func step(month: int, year := -1) -> void:
	day += 1
	for k in world.keys():
		if world[k].until >= 0 and world[k].until < day:
			world.erase(k)
	shocks.step(day, month)
	traffic.step(day, month)
	fleets.step(day, month, year if year > 0 else 1000 + day / 365)
	for id in stock:
		for g in _traded:
			var f := flows(id, g, month)
			stock[id][g] = maxf(0.0, stock[id][g] + f.make + f.imp - f.use - f.exp - f.spoil)
		for x in mods[id]:
			x.days_left -= 1
		mods[id] = mods[id].filter(func(x): return x.days_left > 0)


## Runs the economy for a while before the game starts, so it opens at its own balance, not at the data's guess.
func warm_up(days: int, start_month: int, start_year := -1) -> void:
	var weeks: int = cfg.history_weeks
	for i in days:
		var back: int = start_month - 1 - (days - i) / 30
		step(posmod(back, 12) + 1, start_year + floori(back / 12.0) if start_year > 0 else -1)
		if days - i <= weeks * 7 and (days - i) % 7 == 0:  # the last months become the opening price history
			sample_week()


func sample_week() -> void:
	var keep: int = cfg.history_weeks
	for id in stock:
		for g in _traded:
			var h: Array = history[id][g]
			h.append(snappedf(mult(id, g), 0.001))
			if h.size() > keep:
				h.pop_front()


## A timed shock: the stock jumps now, production and use change for a while.
## shock: {good, stock (mult), make (mult), use (mult), days, reason, rumour}
func add_mod(id: String, shock: Dictionary) -> void:
	var g: String = shock.good
	stock[id][g] *= shock.get("stock", 1.0)
	mods[id].append({"good": g, "make": shock.get("make", 1.0), "use": shock.get("use", 1.0), "days_left": int(shock.days),
		"reason": shock.get("reason", ""), "rumour": shock.get("rumour", "")})


# ---- world conditions and shocks ------------------------------------------------------------------

## A world condition for `days` (negative: until further notice).
func set_world(key: String, value: Variant, days: int) -> void:
	world[key] = {"value": value, "until": day + days if days >= 0 else -1}


func world_mult(key: String) -> float:
	return float(world[key].value) if world.has(key) else 1.0


func world_has(key: String) -> bool:
	return world.has(key)


## Applies a market effect to a port (shared by shocks, history and story events). Returns false if the type
## isn't one the model handles. Prefer stock, production and consumption to direct price changes, so the effect
## fades as trade restores supply.
func apply_effect(id: String, e: Dictionary) -> bool:
	match e.type:
		"market_shock":  # price_multiplier on goods for days: the stock falls (or rises) to match, supply stays short
			var p: float = float(e.get("price_multiplier", 1.0))
			for g in _goods_of(id, e.get("goods", [])):
				var el: float = cfg.elasticity[goods[g].demand]
				stock[id][g] *= pow(p, -1.0 / el)
				mods[id].append({"good": g, "make": 1.0 / p, "use": 1.0, "days_left": int(e.get("days", 60)),
					"reason": e.get("reason", "Short since the disaster" if p > 1.0 else "A glut after the windfall"), "rumour": ""})
		"port_damage":  # warehouses wrecked and work stopped for a while
			var sev: float = clampf(float(e.get("severity", 0.5)), 0.0, 1.0)
			for g in _traded:
				stock[id][g] *= 1.0 - sev * 0.6
			for g in produces(id):
				mods[id].append({"good": g, "make": 1.0 - sev * 0.6, "use": 1.0, "days_left": int(120 + sev * 240),
					"reason": e.get("reason", "Still rebuilding after the disaster"), "rumour": ""})
			set_world("sailings:" + id, 1.0 - sev * 0.5, int(90 + sev * 180))
		"flows":  # make and use multipliers on goods for days (crops, epidemics, garrisons)
			for g in _goods_of(id, e.get("goods", [])):
				mods[id].append({"good": g, "make": float(e.get("make", 1.0)), "use": float(e.get("use", 1.0)),
					"days_left": int(e.get("days", 60)), "reason": e.get("reason", ""), "rumour": ""})
		"stock":  # stock multiplied at once (a fire, a windfall)
			for g in _goods_of(id, e.get("goods", [])):
				stock[id][g] *= float(e.get("mult", 1.0))
		"spread":  # merchants' margins widen (a shortage of coin, a scare)
			set_world("spread:" + id, float(e.get("mult", 1.5)), int(e.get("days", 60)))
		"sailings":  # fewer ships leave this port (a bankruptcy, a plague)
			set_world("sailings:" + id, float(e.get("mult", 0.5)), int(e.get("days", 60)))
		"route_risk":  # a wave of piracy on the routes into this port
			for o in stock:
				if o != id:
					var key: String = o + ">" + id
					traffic.risk[key] = minf(1.0, traffic.risk.get(key, 0.0) + float(e.get("risk", 0.3)))
		_:
			return false
	return true


## Goods named in an effect: a list of ids (aliases allowed), "made" (what the port produces), "used" (what it
## doesn't), "all", or "random" (one of what it makes).
func _goods_of(id: String, spec: Variant) -> Array:
	if spec is String:
		match spec:
			"made": return produces(id)
			"used": return _traded.filter(func(g): return params[id][g].make <= 0.0)
			"all": return _traded
			"random":
				var made := produces(id)
				return [made[rng.randi() % made.size()]] if not made.is_empty() else []
		spec = spec.split("/")
	var out := []
	for g in spec:
		var real: String = cfg.aliases.get(g, g)
		if real in _traded:
			out.append(real)
	return out


# ---- what it means ------------------------------------------------------------------------------

## Goods this port makes (its exports).
func produces(id: String) -> Array:
	return _traded.filter(func(g): return params[id][g].make > 0.0)


## Goods it's short of right now: where a merchant would want to sell.
func wants(id: String) -> Array:
	return _traded.filter(func(g): return level(id, g) == "scarce")


## Why the price is unusual, in a few words, or "" if it isn't.
func reason(id: String, g: String, month: int) -> String:
	var lv := level(id, g)
	if lv == "normal" or not is_traded(g):
		return ""
	for x in mods[id]:
		if x.good == g and x.reason != "":
			return x.reason
	var pr: Dictionary = params[id][g]
	var gd: Dictionary = goods[g]
	var notes: Dictionary = cfg.season_notes.get(gd.season, {})
	var season: float = _seasons[gd.season][month - 1]
	if pr.make > 0.0 and not notes.is_empty():
		if lv == "plenty" and season >= 1.2:
			return notes.high
		if lv == "scarce" and season <= 0.75:
			return notes.low
	var fleet := fleets.for_port(id)
	if not fleet.is_empty():
		var fname: String = cfg.fleets[fleet.id].name
		if lv == "plenty" and fleet.status == "fair" and cfg.fleets[fleet.id].get("brings", {}).has(g):
			return "%s is in: the fair floods the market" % fname.capitalize()
		if lv == "scarce" and fleet.status == "fair" and cfg.fleets[fleet.id].get("fair_use", {}).has(g):
			return "%s is buying for home" % fname.capitalize()
		if lv == "scarce" and fleet.status != "fair" and cfg.fleets[fleet.id].get("brings", {}).has(g):
			return "Scarce: %s hasn't come" % fname
	if lv == "scarce":
		var raid := traffic.worst_route_into(id)
		if raid[1] >= cfg.traffic.raid_reason_risk:
			return "Raiders on the route from " + ports[raid[0]].name
		if gd.origin == "european" and pr.imp < 0.5:
			return "Foreign goods are banned: only the fleets and smugglers bring them"
		if cfg.sailing[month - 1] < 0.8:
			return "Few ships sail in the hurricane season"
		return "Little made here, and not enough shipped in"
	if pr.make > pr.use * 2.0:
		return "Made here, more than the town can use"
	if pr.imp > 1.2:
		return "A free port: ships bring everything"
	return "Plenty on hand"


## A Paradox-style tooltip for the price.
func breakdown(id: String, g: String, month: int, spread_mult := 1.0, duty := 0.0) -> String:
	var gd: Dictionary = goods[g]
	var lines := PackedStringArray(["Base price: %.1f" % gd.base_price])
	if not is_traded(g):
		return "\n".join(lines)
	var pr: Dictionary = params[id][g]
	var f := flows(id, g, month)
	lines.append("Stock %d against a normal %d: price x%.2f (%s, reacts %s)" % [stock[id][g], pr.normal, mult(id, g), level(id, g),
		"sharply: people need it" if gd.demand == "necessity" else ("hardly at all" if gd.demand == "treasure" else "gently")])
	lines.append("Each day: made %.1f, shipped in %.1f, used %.1f, shipped out %.1f%s" % [f.make, f.imp, f.use, f.exp,
		", spoiled %.1f" % f.spoil if f.spoil > 0.05 else ""])
	for x in mods[id]:
		if x.good == g:
			lines.append("  %s (%d days left)" % [x.reason, x.days_left])
	var why := reason(id, g, month)
	if why != "":
		lines.append(why + ".")
	lines.append("Merchant's spread: %d%%" % int(cfg.spread[ports[id].size] * spread_mult * 100))
	if duty > 0.0:
		lines.append("Duty: %d%%" % int(round(duty * 100)))
	return "\n".join(lines)


func save_state() -> Dictionary:
	return {"rng": str(rng.state), "stock": stock, "mods": mods, "history": history, "day": day, "traffic": traffic.save_state(),
		"fleets": fleets.save_state(), "world": world}


func load_state(d: Dictionary) -> void:
	rng.state = int(d.rng)
	for id in d.stock:
		if stock.has(id):
			for g in d.stock[id]:
				if stock[id].has(g):
					stock[id][g] = float(d.stock[id][g])
	for id in d.mods:
		mods[id] = d.mods[id]
	for id in d.history:
		history[id] = d.history[id]
	day = int(d.get("day", 0))
	if d.has("traffic"):
		traffic.load_state(d.traffic)
	if d.has("fleets"):
		fleets.load_state(d.fleets)
	world = d.get("world", {})
	for k in world:
		world[k].until = int(world[k].until)
