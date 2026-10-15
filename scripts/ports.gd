extends Node
## Autoload "Ports": the living state of every port, and what the player knows about prices elsewhere.
##   state[id] = {stock: {good: tons}, mods: [{good, mult, days_left, reason, rumour}], sailors, laws}
##   known[id][good] = {buy, sell, day}: the last prices the player saw or heard for that port.
## Laws start from ports.json but live here, so interest groups (milestone 8b) can rewrite them.
## Trade functions take the player's state dict `s` (gold, cargo, cargo_cost, crew) and return {ok, text}.

var rng := RandomNumberGenerator.new()
var state := {}
var known := {}


func _ready() -> void:
	rng.randomize()
	reset()
	Clock.day_passed.connect(func(_d): daily())


func reset() -> void:
	state = {}
	known = {}
	for id in Data.table("ports"):
		var p := port(id)
		var stock := {}
		for good in Data.table("goods"):
			stock[good] = Market.normal_stock(p, good, [])
		state[id] = {"stock": stock, "mods": [], "sailors": float(p.sailors), "laws": p.laws.duplicate(true)}


func port(id: String) -> Dictionary:
	return Data.table("ports")[id]


func price(id: String, good: String, buying: bool, spread_mult := 1.0) -> float:
	return Market.unit_price(port(id), good, state[id].stock[good], buying, spread_mult)


func daily() -> void:
	for id in state:
		var p := port(id)
		var ps: Dictionary = state[id]
		Market.daily_update(p, ps, rng)
		ps.sailors = minf(p.sailors, ps.sailors + p.sailors * Data.rules.tavern.regen_per_day)
		for ev in Data.rules.market_events:
			if rng.randf() < ev.daily_chance:
				start_market_event(id, ev)


func start_market_event(id: String, ev: Dictionary) -> void:
	var ps: Dictionary = state[id]
	var goods := Data.table("goods").keys().filter(func(g):
		return Market.kind(port(id), g) == ev.kind and not ps.mods.any(func(m): return m.good == g))
	if goods.is_empty():
		return
	var good: String = goods[rng.randi() % goods.size()]
	ps.mods.append({"good": good, "mult": ev.mult, "days_left": rng.randi_range(ev.days[0], ev.days[1]),
		"reason": ev.name, "rumour": ev.rumour})
	ps.stock[good] *= ev.mult


func record_prices(id: String, day: int, goods: Array = []) -> void:
	if not known.has(id):
		known[id] = {}
	for good in (goods if not goods.is_empty() else Data.table("goods").keys()):
		known[id][good] = {"buy": price(id, good, true), "sell": price(id, good, false), "day": day}


## Best known selling price for `good` in any other port: {port, sell, day}, or {} if none known.
func best_known_sale(good: String, exclude: String) -> Dictionary:
	var best := {}
	for id in known:
		if id != exclude and known[id].has(good) and (best.is_empty() or known[id][good].sell > best.sell):
			best = {"port": id, "sell": known[id][good].sell, "day": known[id][good].day}
	return best


func buy(id: String, good: String, qty: int, s: Dictionary, capacity: float, spread_mult := 1.0) -> Dictionary:
	var ps: Dictionary = state[id]
	var w := Market.weight(good)
	qty = mini(qty, Market.max_buy(good, ps.stock[good]))
	qty = mini(qty, int((capacity - Market.cargo_used(s.cargo)) / w + 0.0001))
	qty = mini(qty, int(s.gold / price(id, good, true, spread_mult)))
	var cost := Market.quote(port(id), good, ps.stock[good], qty, true, spread_mult)
	while qty > 0 and cost > s.gold:  # rising prices during the trade can push the total over budget
		qty -= 1
		cost = Market.quote(port(id), good, ps.stock[good], qty, true, spread_mult)
	if qty <= 0:
		return {"ok": false, "text": "Can't buy: no money, no room in the hold, or none left."}
	s.gold -= cost
	s.cargo[good] = s.cargo.get(good, 0) + qty
	s.cargo_cost[good] = s.cargo_cost.get(good, 0.0) + cost
	ps.stock[good] -= qty * w
	return {"ok": true, "text": "Bought %d %s for %d." % [qty, _name(good), cost], "value": cost}


func sell(id: String, good: String, qty: int, s: Dictionary, spread_mult := 1.0) -> Dictionary:
	var ps: Dictionary = state[id]
	var have: float = s.cargo.get(good, 0.0)
	qty = mini(qty, int(have))
	if qty <= 0:
		return {"ok": false, "text": "Nothing to sell."}
	var income := Market.quote(port(id), good, ps.stock[good], qty, false, spread_mult)
	if rng.randf() < Market.seizure_chance(ps.laws, good, qty):
		var fine := int(round(income * Data.rules.smuggling.fine_mult))
		remove_cargo(s, good, have)
		s.gold = maxf(0.0, s.gold - fine)
		return {"ok": false, "text": "Customs officers seized all your %s and fined you %d!" % [_name(good), fine]}
	remove_cargo(s, good, qty)
	s.gold += income
	ps.stock[good] += qty * Market.weight(good)
	return {"ok": true, "text": "Sold %d %s for %d." % [qty, _name(good), income], "value": income}


## Removes cargo and the matching share of what was paid for it.
static func remove_cargo(s: Dictionary, good: String, qty: float) -> void:
	var have: float = s.cargo.get(good, 0)
	var left := maxf(0.0, have - qty)
	if have > 0:
		s.cargo_cost[good] = s.cargo_cost.get(good, 0.0) * left / have
	if left <= 0.0:
		s.cargo.erase(good)
		s.cargo_cost.erase(good)
	else:
		s.cargo[good] = left


## Signs on n new hands, each a generated character. Their nationality follows the port's mix.
func hire(id: String, n: int, s: Dictionary, crew_max: int) -> Dictionary:
	var ps: Dictionary = state[id]
	var cost_each: float = Data.rules.tavern.hire_cost
	n = mini(n, mini(int(ps.sailors), crew_max - ShipStats.headcount(s)))
	n = mini(n, int(s.gold / cost_each))
	if n <= 0:
		return {"ok": false, "text": "No one to hire: no sailors left, no money, or no room aboard."}
	var mix: Dictionary = Data.rules.people.recruit_mix[port(id).faction]
	for i in n:
		s.crew.append(People.add(People.generate({"mix": mix})))
	ps.sailors -= n
	s.gold -= n * cost_each
	return {"ok": true, "text": "Signed on %d sailors for %d." % [n, n * cost_each]}


## Pays off the n least useful hands (never officers). They go back to the port's pool.
func dismiss(id: String, n: int, s: Dictionary) -> Dictionary:
	var officers: Array = s.officers.values()
	var pool: Array = s.crew.filter(func(c): return not c in officers)
	pool.sort_custom(func(a, b): return _usefulness(a) < _usefulness(b))
	var gone: Array = pool.slice(0, n)
	for c in gone:
		s.crew.erase(c)
		People.remove(c)
	state[id].sailors += gone.size()
	return {"ok": not gone.is_empty(), "text": "Paid off %d hands." % gone.size()}


static func _usefulness(id: String) -> int:
	var c := People.person(id)
	var best := 0
	for sk in People.SKILLS:
		best = maxi(best, People.value(c, sk))
	return best + People.value(c, "experience")


## Trades in the current ship for a new one. Crew, cargo and officers move across; upgrades stay with the old ship.
func buy_ship(type_id: String, s: Dictionary) -> Dictionary:
	var new_stats := ShipStats.effective(type_id, [])
	var cost: int = Data.table("ships")[type_id].price - ShipStats.trade_in_value(s)
	if cost > s.gold:
		return {"ok": false, "text": "You can't afford her, even trading in your ship."}
	if Market.cargo_used(s.cargo) > new_stats.cargo:
		return {"ok": false, "text": "Your cargo won't fit in her hold. Sell some first."}
	if ShipStats.headcount(s) > new_stats.crew_max:
		return {"ok": false, "text": "Too many crew for her berths. Pay some off first."}
	var old_name: String = Data.table("ships")[s.type].name
	s.gold -= cost
	s.type = type_id
	s.upgrades = []
	s.hull = float(new_stats.hull)
	s.sails = float(new_stats.sails)
	s.fouling = 0.0
	return {"ok": true, "text": "Traded your %s for a %s, paying %d." % [old_name, new_stats.name, cost]}


## A tavern rumour: news of a market event somewhere, or a tip about prices. The player learns those prices.
func rumour(here: String, day: int) -> String:
	var others := state.keys().filter(func(id): return id != here)
	var with_news := others.filter(func(id): return not state[id].mods.is_empty())
	var id: String
	var good: String
	var text: String
	if not with_news.is_empty() and rng.randf() < 0.6:
		id = with_news[rng.randi() % with_news.size()]
		var m: Dictionary = state[id].mods[rng.randi() % state[id].mods.size()]
		good = m.good
		text = m.rumour.format({"good": _name(good), "port": port(id).name})
	else:
		id = others[rng.randi() % others.size()]
		var goods: Array = port(id).produces + port(id).wants
		good = goods[rng.randi() % goods.size()]
		text = "A captain fresh from %s says %s buys at %s and sells at %s there." % [
			port(id).name, _name(good), Market.fmt(price(id, good, true)), Market.fmt(price(id, good, false))]
	record_prices(id, day - rng.randi_range(1, 6), [good])  # rumours are a few days old
	return text


func save_state() -> Dictionary:
	return {"rng": str(rng.state), "state": state, "known": known}


func load_state(d: Dictionary) -> void:
	rng.state = int(d.rng)
	state = d.state
	known = d.known


static func _name(good: String) -> String:
	return Data.table("goods")[good].name
