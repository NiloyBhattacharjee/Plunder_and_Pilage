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
		state[id] = {"stock": stock, "mods": [], "sailors": float(p.sailors), "laws": p.laws.duplicate(true),
			"notables": [], "notables_age": 0}
		refresh_notables(id)


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
		# customs forget slowly: vigilance drifts back to the port's normal level
		var base: float = p.laws.vigilance
		ps.laws.vigilance = move_toward(ps.laws.vigilance, base, Data.rules.smuggling.vigilance_decay_per_day)
		ps.notables_age += 1
		if ps.notables_age >= Data.rules.tavern.notables_refresh_days:
			refresh_notables(id)
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
	var sm: Dictionary = Data.rules.smuggling
	var contraband: bool = good in ps.laws.contraband
	if rng.randf() < Market.seizure_chance(ps.laws, good, qty):
		var fine := int(round(income * sm.fine_mult))
		remove_cargo(s, good, have)
		s.gold = maxf(0.0, s.gold - fine)
		var f: String = port(id).faction
		s.relations[f] = s.relations.get(f, 0) - int(sm.seizure_relation)
		s.reputation.notoriety += 1
		ps.laws.vigilance = minf(1.0, ps.laws.vigilance + sm.seizure_vigilance)
		return {"ok": false, "text": "Customs officers seized all your %s and fined you %d! %s will remember (standing -%d), and customs here are watching closer." % [
			_name(good), fine, Data.table("factions")[f].name, sm.seizure_relation]}
	if contraband:  # even a clean sale gets noticed
		ps.laws.vigilance = minf(1.0, ps.laws.vigilance + sm.sale_vigilance)
	remove_cargo(s, good, qty, n_stolen)
	s.gold += income
	ps.stock[good] += qty * Market.weight(good)
	var text := "Sold %d %s for %d." % [qty, _name(good), income]
	if n_stolen > 0:  # plunder: the crew take their share by the articles
		text += " " + Crew.plunder(s, income * n_stolen / float(qty))
	return {"ok": true, "text": text.strip_edges(), "value": income}


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


## Why a yard won't sell you this ship, or "". Warships need the owners' trust.
func cannot_buy_ship(id: String, type_id: String, s: Dictionary) -> String:
	var t: Dictionary = Data.table("ships")[type_id]
	var f: String = port(id).faction
	if s.relations.get(f, 0) < t.min_standing - (20 if Bonds.level(s, "f:" + f) >= 2 else 0):  # a pact opens the yard
		return "%s won't sell a %s to someone with your standing (needs %+d, you have %+d)." % [
			Data.table("factions")[f].name, t.name.to_lower(), t.min_standing, s.relations.get(f, 0)]
	if t.price - ShipStats.trade_in_value(s) > s.gold:
		return "You can't afford her, even trading in your ship."
	if Market.cargo_used(s.cargo) > ShipStats.effective(type_id, []).cargo:
		return "Your cargo won't fit in her hold. Sell some first."
	if ShipStats.headcount(s) > t.crew_max:
		return "Too many crew for her berths. Pay some off first."
	return ""


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
	return {"ok": true, "text": ("Sold the prize %s for %d. " % [prize.name, value] + Crew.plunder(s, value)).strip_edges()}


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
	return {"ok": true, "text": ("%s is ransomed for %d gold. " % [name, h.ransom] + Crew.plunder(s, h.ransom)).strip_edges()}


func recruit_opts(id: String) -> Dictionary:
	return {"mix": Data.rules.people.recruit_mix[port(id).faction], "bonus": port(id).get("recruits", {})}


## A few hands worth a closer look: you see their skills, but not every trait until you interview them.
func refresh_notables(id: String) -> void:
	var ps: Dictionary = state[id]
	ps.notables = []
	ps.notables_age = 0
	for i in Data.rules.tavern.notables:
		var c := People.generate(recruit_opts(id))
		var best: String = People.SKILLS[0]
		for sk in People.SKILLS:
			if c.skills[sk] > c.skills[best]:
				best = sk
		c.skills[best] = mini(20, c.skills[best] + 3)  # they stand out for a reason
		ps.notables.append(c)


static func notable_cost(c: Dictionary) -> int:
	var best := 0
	for sk in People.SKILLS:
		best = maxi(best, People.value(c, sk))
	return int(Data.rules.tavern.hire_cost + best * Data.rules.tavern.notable_cost_per_skill)


func hire_notable(id: String, index: int, s: Dictionary, crew_max: int) -> Dictionary:
	var c: Dictionary = state[id].notables[index]
	var cost := notable_cost(c)
	if ShipStats.headcount(s) >= crew_max:
		return {"ok": false, "text": "No berth for them."}
	if s.gold < cost:
		return {"ok": false, "text": "You can't afford their price."}
	s.gold -= cost
	c.history.append("Signed on at %s, %s." % [port(id).name, Clock.date_string()])
	s.crew.append(People.add(c))
	state[id].notables.remove_at(index)
	return {"ok": true, "text": "%s signs your articles for %d." % [c.name, cost]}


## Buy them a drink and size them up: a chance to learn one hidden trait. Captain's charisma helps.
func interview(id: String, index: int, s: Dictionary) -> Dictionary:
	var t: Dictionary = Data.rules.tavern
	var c: Dictionary = state[id].notables[index]
	if s.gold < t.interview_cost:
		return {"ok": false, "text": "Not even the price of a drink."}
	s.gold -= t.interview_cost
	c.interviewed = true
	var chance: float = t.interview_base + People.value(ShipStats.captain(s), "charisma") * t.interview_per_charisma
	if not c.hidden.is_empty() and rng.randf() < chance:
		var found: String = People.reveal_trait(c)
		return {"ok": true, "text": "Over a drink, %s lets slip that they're %s." % [c.name, Data.table("traits")[found].name.to_lower()]}
	return {"ok": true, "text": "%s gives nothing away%s." % [c.name, "" if not c.hidden.is_empty() else " (there's nothing more to learn)"]}


## Signs on n new hands, each a generated character shaped by the port they come from.
func hire(id: String, n: int, s: Dictionary, crew_max: int) -> Dictionary:
	var ps: Dictionary = state[id]
	var cost_each: float = Data.rules.tavern.hire_cost
	n = mini(n, mini(int(ps.sailors), crew_max - ShipStats.headcount(s)))
	n = mini(n, int(s.gold / cost_each))
	if n <= 0:
		return {"ok": false, "text": "No one to hire: no sailors left, no money, or no room aboard."}
	for i in n:
		s.crew.append(People.add(People.generate(recruit_opts(id))))
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
func buy_ship(id: String, type_id: String, s: Dictionary) -> Dictionary:
	var why := cannot_buy_ship(id, type_id, s)
	if why != "":
		return {"ok": false, "text": why}
	var new_stats := ShipStats.effective(type_id, [])
	var cost: int = Data.table("ships")[type_id].price - ShipStats.trade_in_value(s)
	var old_name: String = Data.table("ships")[s.type].name
	s.gold -= cost
	s.type = type_id
	s.upgrades = []
	s.hull = float(new_stats.hull)
	s.sails = float(new_stats.sails)
	s.fouling = 0.0
	return {"ok": true, "text": "Traded your %s for a %s, paying %d." % [old_name, new_stats.name, cost]}


## A tavern rumour: news of a market event somewhere, or a tip about prices. The player learns those prices,
## but some rumours are wrong; you find out when you get there. `false_chance` comes from your charisma.
func rumour(here: String, day: int, false_chance := 0.0) -> String:
	var others := state.keys().filter(func(id): return id != here)
	var with_news := others.filter(func(id): return not state[id].mods.is_empty())
	var id: String
	var good: String
	var text: String
	var price_tip := false
	if not with_news.is_empty() and rng.randf() < 0.6:
		id = with_news[rng.randi() % with_news.size()]
		var m: Dictionary = state[id].mods[rng.randi() % state[id].mods.size()]
		good = m.good
		text = m.rumour.format({"good": _name(good), "port": port(id).name})
	else:
		price_tip = true
		id = others[rng.randi() % others.size()]
		var goods: Array = port(id).produces + port(id).wants
		good = goods[rng.randi() % goods.size()]
		text = "A captain fresh from %s says %s buys at %s and sells at %s there." % [
			port(id).name, _name(good), Market.fmt(price(id, good, true)), Market.fmt(price(id, good, false))]
	var heard := day - rng.randi_range(1, 6)  # rumours are a few days old
	record_prices(id, heard, [good])
	known[id][good].source = "rumour"
	if rng.randf() < false_chance:  # a tall tale: the numbers you heard are off
		var off := rng.randf_range(1.4, 1.9) if rng.randf() < 0.5 else rng.randf_range(0.4, 0.7)
		known[id][good].buy *= off
		known[id][good].sell *= off
		known[id][good].fake = true
		if price_tip:
			text = text.replace(Market.fmt(price(id, good, true)), Market.fmt(known[id][good].buy)).replace(
				Market.fmt(price(id, good, false)), Market.fmt(known[id][good].sell))
	return text


func save_state() -> Dictionary:
	return {"rng": str(rng.state), "state": state, "known": known}


func load_state(d: Dictionary) -> void:
	rng.state = int(d.rng)
	state = d.state
	known = d.known


static func _name(good: String) -> String:
	return Data.table("goods")[good].name
