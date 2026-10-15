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
	var stolen: float = s.get("stolen", {}).get(good, 0.0)
	var n_clean := mini(qty, int(have - stolen))
	var n_stolen := qty - n_clean
	var income := Market.quote(port(id), good, ps.stock[good], n_clean, false, spread_mult)
	if n_stolen > 0:  # stolen goods sell cheap unless there's a fence
		var stolen_income := Market.quote(port(id), good, ps.stock[good] + n_clean * Market.weight(good), n_stolen, false, spread_mult)
		income += int(stolen_income * fence_mult(id))
	if rng.randf() < Market.seizure_chance(ps.laws, good, qty):
		var fine := int(round(income * Data.rules.smuggling.fine_mult))
		remove_cargo(s, good, have)
		s.gold = maxf(0.0, s.gold - fine)
		return {"ok": false, "text": "Customs officers seized all your %s and fined you %d!" % [_name(good), fine]}
	remove_cargo(s, good, qty, n_stolen)
	s.gold += income
	ps.stock[good] += qty * Market.weight(good)
	return {"ok": true, "text": "Sold %d %s for %d." % [qty, _name(good), income], "value": income}


## Removes cargo and the matching share of what was paid for it. `stolen_part` of it was stolen
## (by default: whatever stolen units no longer fit in what's left).
static func remove_cargo(s: Dictionary, good: String, qty: float, stolen_part := -1.0) -> void:
	var have: float = s.cargo.get(good, 0)
	var left := maxf(0.0, have - qty)
	if have > 0:
		s.cargo_cost[good] = s.cargo_cost.get(good, 0.0) * left / have
	if s.has("stolen") and s.stolen.has(good):
		var st: float = s.stolen[good] - stolen_part if stolen_part >= 0.0 else s.stolen[good]
		s.stolen[good] = minf(st, left)
		if s.stolen[good] <= 0.0:
			s.stolen.erase(good)
	if left <= 0.0:
		s.cargo.erase(good)
		s.cargo_cost.erase(good)
	else:
		s.cargo[good] = left


## Stolen goods fetch full price only through a fence (pirate havens, some free ports).
func fence_mult(id: String) -> float:
	return 1.0 if port(id).get("fence", false) else Data.rules.fence.legal_mult


## Sells a prize ship at the shipyard, with whatever cargo is left aboard. The prize crew rejoins.
func sell_prize(id: String, index: int, s: Dictionary) -> Dictionary:
	var prize: Dictionary = s.prizes[index]
	var value := prize_value(id, prize)
	s.gold += value
	s.crew.append_array(prize.crew)
	s.prizes.remove_at(index)
	return {"ok": true, "text": "Sold the prize %s for %d." % [prize.name, value]}


func prize_value(id: String, prize: Dictionary) -> int:
	var st := ShipStats.effective(prize.type, [])
	var v: float = Data.table("ships")[prize.type].price * Data.rules.prizes.sale_mult * clampf(prize.hull / st.hull, 0.2, 1.0)
	for g in prize.cargo:
		v += Market.quote(port(id), g, state[id].stock[g], int(prize.cargo[g]), false) * fence_mult(id)
	return int(v)


## Makes a prize your flagship. Your old ship is sold to the yard at trade-in value.
func prize_to_flagship(index: int, s: Dictionary) -> Dictionary:
	var prize: Dictionary = s.prizes[index]
	var old_value := ShipStats.trade_in_value(s)
	var new_stats := ShipStats.effective(prize.type, [])
	if Market.cargo_used(s.cargo) > new_stats.cargo:
		return {"ok": false, "text": "Your cargo won't fit in her hold."}
	s.gold += old_value
	s.crew.append_array(prize.crew)
	s.type = prize.type
	s.name = prize.name
	s.upgrades = []
	s.hull = minf(prize.hull, new_stats.hull)
	s.sails = minf(prize.sails, new_stats.sails)
	s.fouling = 0.0
	s.guns_lost = 0
	for g in prize.cargo:
		s.cargo[g] = s.cargo.get(g, 0) + prize.cargo[g]
		s.stolen[g] = s.stolen.get(g, 0) + prize.cargo[g]
	s.prizes.remove_at(index)
	return {"ok": true, "text": "The %s is your flagship now. The yard paid %d for your old ship." % [prize.name, old_value]}


## Hostages from this port's nation can be ransomed here.
func ransom(id: String, s: Dictionary, index: int) -> Dictionary:
	var h: Dictionary = s.hostages[index]
	if h.faction != port(id).faction:
		return {"ok": false, "text": "Nobody here will pay for them."}
	s.gold += h.ransom
	var name: String = People.person(h.id).name
	People.remove(h.id)
	s.hostages.remove_at(index)
	return {"ok": true, "text": "%s is ransomed for %d gold." % [name, h.ransom]}


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
