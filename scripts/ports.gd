extends Node
## Autoload "Ports": the living state of every port, and what the player knows about prices elsewhere.
## Stock and prices live in the Economy; this is the port's side of a trade: laws, customs, the ledger.
##   state[id] = {sailors, laws, notables}
##   known[id][good] = {buy, sell, m (price multiplier), day, source: seen/news/papers/rumour}: the latest the player
##   saw or heard for that port. News comes by ship, so it's old; estimate() guesses what it is now.
## Laws start from ports.json but live here, so interest groups (milestone 8b) can rewrite them.
## Trade functions take the player's state dict `s` (gold, cargo, cargo_cost, crew) and return {ok, text}.

var rng := RandomNumberGenerator.new()
var state := {}
var known := {}
var owners := {}   # port id -> faction: towns that have changed hands in a war (Factions)


func _ready() -> void:
	rng.randomize()
	reset()
	Clock.day_passed.connect(func(_d): daily())


func reset() -> void:
	state = {}
	known = {}
	_restore_owners()
	owners = {}
	Economy.reset()
	for id in Data.table("ports"):
		var p := port(id)
		state[id] = {"sailors": float(p.sailors), "laws": p.laws.duplicate(true),
			"notables": [], "notables_age": 0, "fence_cash": _fence_cash_max(id)}
		refresh_notables(id)


func port(id: String) -> Dictionary:
	return Data.table("ports")[id]


## A town changes hands: the new nation's flag, laws and officials. The static port data's faction is changed in
## place (and its first owner kept in orig_faction), so everything that asks a port's faction sees the new one.
func change_owner(id: String, f: String) -> void:
	var p := port(id)
	if not p.has("orig_faction"):
		p.orig_faction = p.faction
	p.faction = f
	owners[id] = f
	for other in Data.table("ports"):  # the laws of the nation's other towns
		var o: Dictionary = Data.table("ports")[other]
		if other != id and o.get("orig_faction", o.faction) == f:
			state[id].laws = o.laws.duplicate(true)
			state[id].laws.vigilance = p.laws.vigilance
			break
	Politics.officials.erase(id)
	Politics.influence.erase(id)
	Politics.apply_laws(id, true)
	Contracts.offers.erase(id)


func _restore_owners() -> void:
	for id in Data.table("ports"):
		var p: Dictionary = Data.table("ports")[id]
		if p.has("orig_faction"):
			p.faction = p.orig_faction
			p.erase("orig_faction")


func price(id: String, good: String, buying: bool, spread_mult := 1.0) -> float:
	return Economy.price(id, good, buying, spread_mult)


func daily() -> void:
	for n in PortLife.daily(rng, EconomyEffects.player):  # feast days, press gangs, riots: news of them travels
		Economy.add_news(n.text, n.port)
	for id in state:
		var p := port(id)
		var ps: Dictionary = state[id]
		var pool: float = p.sailors * PortLife.mult(id, "sailors")  # press gangs empty the waterfront; riots fill it
		ps.sailors = move_toward(ps.sailors, pool, p.sailors * Data.rules.tavern.regen_per_day)
		ps.fence_cash = minf(_fence_cash_max(id), ps.get("fence_cash", 0.0) + _fence_cash_max(id) * Data.rules.fence.cash_regen)
		# customs forget slowly: vigilance drifts back to the port's normal level
		var base: float = p.laws.vigilance
		ps.laws.vigilance = move_toward(ps.laws.vigilance, base, Data.rules.smuggling.vigilance_decay_per_day)
		ps.notables_age += 1
		if ps.notables_age >= Data.rules.tavern.notables_refresh_days:
			refresh_notables(id)


## A market shock (economy.json "shocks") in this port, on purpose: events use it. Returns the news.
func start_market_event(id: String, shock: String) -> String:
	var news := Economy.model.shocks.strike(shock, id, Economy.model.day)
	Economy.model.shocks.take_events()
	Economy.add_news(news, id)
	return news


func record_prices(id: String, day: int, goods: Array = []) -> void:
	if not known.has(id):
		known[id] = {}
	for good in (goods if not goods.is_empty() else Data.table("goods").keys()):
		known[id][good] = {"buy": price(id, good, true), "sell": price(id, good, false), "m": Economy.mult(id, good), "day": day, "source": "seen"}


## Learns a port's prices from news (a price multiplier per good, as of `day`), where it's newer than what's known.
func learn(id: String, mults: Dictionary, day: int, source: String) -> bool:
	if not known.has(id):
		known[id] = {}
	var learned := false
	for good in mults:
		var k: Dictionary = known[id].get(good, {})
		if k.is_empty() or day > int(k.day):
			known[id][good] = {"buy": Economy.price_at(id, good, mults[good], true), "sell": Economy.price_at(id, good, mults[good], false),
				"m": mults[good], "day": day, "source": source}
			learned = true
	return learned


## News on the quay: what this port has heard of the others, from the ships that came in. Returns how many ports.
func learn_board(here: String) -> int:
	return learn_news(Economy.model.traffic.board.get(here, {}), "news", here)


## A packet of news ({port: {day, m}}, a port's board or a captured ship's papers). Returns how many ports were news.
func learn_news(board: Dictionary, source: String, skip := "") -> int:
	var n := 0
	for id in board:
		if id != skip and state.has(id) and not board[id].m.is_empty():
			if learn(id, board[id].m, Economy.to_game_day(int(board[id].day)), source):
				n += 1
	return n


## What your best trader reckons a good fetches in a port today, from the latest news of it:
## {m, sell, buy, age, err, heard, who}, or {} if you've heard nothing. Old news leans on what the port usually
## fetches; the guess is off by a fixed amount (so it doesn't change every time you look) that shrinks with skill.
func estimate(id: String, good: String, s: Dictionary) -> Dictionary:
	var k: Dictionary = known.get(id, {}).get(good, {})
	if k.is_empty():
		return {}
	var info: Dictionary = Economy.cfg().information
	var age := maxf(0.0, Clock.day - float(k.day))
	var w := exp(-age / float(info.estimate_tau_days))
	var hist := Economy.history(id, good)
	var typical: float = hist.reduce(func(a, x): return a + x, 0.0) / hist.size() if not hist.is_empty() else 1.0
	var est: float = float(k.get("m", 1.0)) * w + typical * (1.0 - w)
	var who := ShipStats.captain(s)
	for post in s.get("officers", {}):
		var o := People.person(s.officers[post])
		if People.value(o, "trade") > People.value(who, "trade"):
			who = o
	var net: float = minf(info.network_max, Bonds.allies(s).size() * info.network_per_ally)
	var err: float = info.estimate_error * (1.0 - People.value(who, "trade") / 20.0) * (1.0 - net) * (1.0 - w)
	var noise := float(abs(hash(id + good + str(int(k.day)))) % 2001) / 1000.0 - 1.0
	est = maxf(0.1, est * (1.0 + err * noise))
	return {"m": est, "sell": Economy.price_at(id, good, est, false), "buy": Economy.price_at(id, good, est, true),
		"age": int(age), "err": err, "heard": k, "who": who.name}


## Best place you know of to sell `good` (other than here), by your trader's estimate of today's price:
## {port, sell (estimated), day, est}, or {} if none known.
func best_known_sale(good: String, exclude: String, s := {}) -> Dictionary:
	var best := {}
	for id in known:
		if id == exclude or not known[id].has(good):
			continue
		var est := estimate(id, good, s) if not s.is_empty() else {}
		var sell: float = est.sell if not est.is_empty() else known[id][good].sell
		if best.is_empty() or sell > best.sell:
			best = {"port": id, "sell": sell, "day": known[id][good].day, "est": est}
	return best


func buy(id: String, good: String, qty: int, s: Dictionary, capacity: float, spread_mult := 1.0) -> Dictionary:
	var w := Market.weight(good)
	qty = mini(qty, Economy.max_buy(id, good))
	qty = mini(qty, int((capacity - Market.cargo_used(s.cargo)) / w + 0.0001))
	qty = mini(qty, int(s.gold / price(id, good, true, spread_mult)))
	var cost := Economy.quote(id, good, qty, true, spread_mult)
	if good in ["food", "water"] and EconomyEffects.active(s, "free_supplies", id) != null:
		cost = 0  # the town gives what you need
	while qty > 0 and cost > s.gold:  # rising prices during the trade can push the total over budget
		qty -= 1
		cost = Economy.quote(id, good, qty, true, spread_mult)
	if qty <= 0:
		return {"ok": false, "text": "Can't buy: no money, no room in the hold, or none left."}
	var laws: Dictionary = state[id].laws
	if good in laws.get("enumerated", []) and Career.flag_faction(s.get("flag", "white")) != port(id).faction:
		# the Navigation Acts: these goods go home in the nation's own ships. Loading them under other colours is smuggling.
		if rng.randf() < Market.seizure_chance({"contraband": [good], "vigilance": laws.vigilance}, good, qty):
			var sm: Dictionary = Data.rules.smuggling
			var fine := int(round(cost * sm.fine_mult))
			s.gold = maxf(0.0, s.gold - fine)
			var f: String = port(id).faction
			s.relations[f] = s.relations.get(f, 0) - int(sm.seizure_relation)
			laws.vigilance = minf(1.0, laws.vigilance + sm.seizure_vigilance)
			return {"ok": false, "text": "Customs stop the loading: %s may leave here only in %s ships. Fined %d (standing -%d)." % [
				_name(good), Data.table("factions")[f].adjective, fine, sm.seizure_relation]}
	s.gold -= cost
	s.cargo[good] = s.cargo.get(good, 0) + qty
	s.cargo_cost[good] = s.cargo_cost.get(good, 0.0) + cost
	Economy.add(id, good, -qty)
	log_trade(s, id, good, qty, -cost, 0.0)
	return {"ok": true, "text": "Bought %d %s for %d." % [qty, _name(good), cost], "value": cost}


## The ship's trade ledger: every purchase and sale, and what a sale made over what was paid.
static func log_trade(s: Dictionary, id: String, good: String, qty: int, value: float, profit: float) -> void:
	s.ledger = s.get("ledger", [])
	s.ledger.append({"day": int(Clock.day), "port": id, "good": good, "qty": qty, "value": int(value), "profit": int(profit)})
	if s.ledger.size() > int(Data.rules.ledger_max):
		s.ledger.pop_front()


func sell(id: String, good: String, qty: int, s: Dictionary, spread_mult := 1.0) -> Dictionary:
	var ps: Dictionary = state[id]
	var have: float = s.cargo.get(good, 0.0)
	var paid: float = s.cargo_cost.get(good, 0.0) * minf(1.0, qty / maxf(have, 1.0))
	qty = mini(qty, int(have))
	if qty <= 0:
		return {"ok": false, "text": "Nothing to sell."}
	var stolen: float = s.get("stolen", {}).get(good, 0.0)
	var n_clean := mini(qty, int(have - stolen))
	var n_stolen := qty - n_clean
	var income := Economy.quote(id, good, qty, false, spread_mult)
	var note := ""
	if n_stolen > 0:  # stolen goods sell cheap unless there's a fence (they're sold last, at the lower end of the quote)
		var clean_part := Economy.quote(id, good, n_clean, false, spread_mult)
		var stolen_income := int((income - clean_part) * fence_mult(id, s))
		if is_fence(id, s):
			while n_stolen > 0 and stolen_income > ps.fence_cash:  # a fence has only so much coin
				n_stolen -= maxi(1, n_stolen / 8)
				qty = n_clean + n_stolen
				income = Economy.quote(id, good, qty, false, spread_mult)
				stolen_income = int((income - clean_part) * fence_mult(id, s))
				note = " The fence has no more coin today."
			ps.fence_cash -= stolen_income
			s.fence_trust = s.get("fence_trust", {})
			s.fence_trust[id] = s.fence_trust.get(id, 0.0) + stolen_income
		income = clean_part + stolen_income
		if qty <= 0:
			return {"ok": false, "text": "The fence has no coin left for stolen goods. Come back in a few days."}
	if Data.table("goods")[good].demand == "treasure" and port(id).faction != "spain" and not is_fence(id, s):
		income = int(income * Data.rules.fence.treasure_legal_mult)  # few honest buyers for a heap of Spanish silver
		note += " Few here will touch so much Spanish treasure; it went cheap."
	var sm: Dictionary = Data.rules.smuggling
	var contraband: bool = good in ps.laws.contraband
	var opened = EconomyEffects.active(s, "open_market", id)
	if opened != null and contraband:  # a smugglers' night: they want what's forbidden, and no customs
		income = int(income * (1.0 + opened.bonus))
		note += " The interlopers pay well."
	var trade = EconomyEffects.active(s, "trade_mult")
	if trade != null:
		income = int(income * trade.value)
	var risk: float = Market.seizure_chance(ps.laws, good, qty) * (1.0 - EconomyEffects.econ(s).smugglers / 200.0)  # friends among the smugglers
	if opened != null and contraband:
		risk = 0.0
	if rng.randf() < risk:
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
	Economy.add(id, good, qty)
	log_trade(s, id, good, -qty, income, income - paid)
	Ambitions.tally(s, "trade_profit", maxf(0.0, income - paid))
	var text := "Sold %d %s for %d.%s" % [qty, _name(good), income, note]
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
## What stolen goods fetch here, as a share of the price: a fence pays nearly full (more as they come to trust you);
## an honest market pays a pittance and asks no questions it would rather not hear the answers to.
func fence_mult(id: String, s := {}) -> float:
	var f: Dictionary = Data.rules.fence
	if not is_fence(id, s):
		return f.legal_mult
	var trust: float = s.get("fence_trust", {}).get(id, 0.0)
	var dependence: float = s.get("econ", {}).get("fence_dependence", {}).get(id, 0.0)  # they know you need them
	return clampf(f.fence_mult + trust * f.trust_per_gold - dependence * f.dependence_per_point, f.legal_mult, 1.0)


## Is there a fence here for you? The havens' own (unless the law has closed them), or one an event found you.
func is_fence(id: String, s := {}) -> bool:
	if s.get("econ", {}).get("fences", {}).get(id, false):
		return true
	return port(id).get("fence", false) and not state.get(id, {}).get("fence_closed", false)


func _fence_cash_max(id: String) -> float:
	return float(Data.rules.fence.cash.get(port(id).size, 0)) if port(id).get("fence", false) else 0.0


## Sells a prize ship at the shipyard, with whatever cargo is left aboard. The prize crew rejoins.
func sell_prize(id: String, index: int, s: Dictionary) -> Dictionary:
	if s.get("econ", {}).get("prize_banned", {}).get(id, false):
		return {"ok": false, "text": "No one here will touch your prize."}
	var prize: Dictionary = s.prizes[index]
	var value := prize_value(id, prize)
	s.gold += value
	Fleet.return_people(s, prize)
	s.prizes.remove_at(index)
	return {"ok": true, "text": ("Sold the prize %s for %d. " % [prize.name, value] + Crew.plunder(s, value)).strip_edges()}


func prize_value(id: String, prize: Dictionary) -> int:
	var st := ShipStats.effective(prize.type, [])
	var v: float = Data.table("ships")[prize.type].price * Data.rules.prizes.sale_mult * clampf(prize.hull / st.hull, 0.2, 1.0)
	for g in prize.cargo:
		v += Economy.quote(id, g, int(prize.cargo[g]), false) * (1.0 if prize.get("laundered", false) else fence_mult(id))
	return int(v)


## Makes a prize your flagship. Your old ship is sold to the yard at trade-in value.
func prize_to_flagship(index: int, s: Dictionary) -> Dictionary:
	var prize: Dictionary = s.prizes[index]
	var old_value := ShipStats.trade_in_value(s)
	var new_stats := ShipStats.effective(prize.type, [])
	if Market.cargo_used(s.cargo) > new_stats.cargo:
		return {"ok": false, "text": "Your cargo won't fit in her hold."}
	s.gold += old_value
	Fleet.return_people(s, prize)
	s.type = prize.type
	s.name = prize.name
	s.upgrades = prize.get("upgrades", [])
	s.look = prize.get("look", {})
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
	var cost_each: float = hire_cost(id)
	n = mini(n, mini(int(ps.sailors), crew_max - ShipStats.headcount(s)))
	n = mini(n, int(s.gold / cost_each))
	if n <= 0:
		return {"ok": false, "text": "No one to hire: no sailors left, no money, or no room aboard."}
	for i in n:
		s.crew.append(People.add(People.generate(recruit_opts(id))))
	ps.sailors -= n
	s.gold -= n * cost_each
	return {"ok": true, "text": "Signed on %d sailors for %d." % [n, n * cost_each]}


## A sailor's signing bounty here: dearer when the press gangs are out, cheaper when the poor are starving.
func hire_cost(id: String) -> float:
	return roundf(Data.rules.tavern.hire_cost * PortLife.mult(id, "hire_cost"))


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
	var with_news := others.filter(func(id): return not Economy.mods(id).is_empty())
	var id: String
	var good: String
	var text: String
	if not with_news.is_empty() and rng.randf() < 0.6:  # word of a shortage or a glut
		id = with_news[rng.randi() % with_news.size()]
		var m: Dictionary = Economy.mods(id)[rng.randi() % Economy.mods(id).size()]
		good = m.good
		if m.get("rumour", "") != "":
			text = m.rumour.format({"good": _name(good), "port": port(id).name})
		else:  # a shock with no rumour of its own: say what it's doing
			text = "Word from %s: %s. %s is %s there." % [port(id).name, str(m.get("reason", "trouble")).to_lower(), _name(good),
				"dear" if Economy.level(id, good) == "scarce" else ("cheap" if Economy.level(id, good) == "plenty" else "unsettled")]
		record_prices(id, day - rng.randi_range(1, 6), [good])
		known[id][good].source = "rumour"
	else:  # a price, as a captain in from there would know it: this port's own news, as old as the last ship in
		id = others[rng.randi() % others.size()]
		var goods: Array = Economy.produces(id) + Economy.wants(id)
		if goods.is_empty():
			goods = Economy.model.traded()
		good = goods[rng.randi() % goods.size()]
		var b: Dictionary = Economy.model.traffic.board.get(here, {}).get(id, {})
		var mult: float = b.get("m", {}).get(good, Economy.mult(id, good))
		var heard: int = Economy.to_game_day(int(b.day)) if not b.is_empty() else day
		if not known.has(id):
			known[id] = {}
		known[id][good] = {"buy": Economy.price_at(id, good, mult, true), "sell": Economy.price_at(id, good, mult, false), "m": mult,
			"day": heard, "source": "rumour"}
		text = "A captain in from %s %s says %s buys at %s and sells at %s there." % [port(id).name,
			"this week" if day - heard < 7 else "%d days ago" % (day - heard), _name(good), "%s", "%s"]
	if rng.randf() < false_chance:  # a tall tale: the numbers you heard are off
		var off := rng.randf_range(1.4, 1.9) if rng.randf() < 0.5 else rng.randf_range(0.4, 0.7)
		known[id][good].buy *= off
		known[id][good].sell *= off
		known[id][good].m = float(known[id][good].get("m", 1.0)) * off
		known[id][good].fake = true
	if text.contains("%s"):
		text = text % [Market.fmt(known[id][good].buy), Market.fmt(known[id][good].sell)]
	return text


func save_state() -> Dictionary:
	return {"rng": str(rng.state), "state": state, "known": known, "owners": owners}


func load_state(d: Dictionary) -> void:
	rng.state = int(d.rng)
	state = d.state
	known = d.known
	_restore_owners()
	owners = d.get("owners", {})
	for id in owners:
		var p := port(id)
		p.orig_faction = p.faction
		p.faction = owners[id]


static func _name(good: String) -> String:
	return Data.table("goods")[good].name
