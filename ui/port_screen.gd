extends CanvasLayer
## Port screen: market, shipyard and tavern. Time is paused while it's open;
## only actions that take time (repairs, careening, refits) move the clock.
## Hover over prices and stats for a breakdown of why they are what they are.

signal message(text: String)
signal closed

var port_id := ""
var ship: Node2D
var rumours_left := 0


func _ready() -> void:
	%SetSail.pressed.connect(close)
	%Hire1.pressed.connect(_act.bind(func(): return Ports.hire(port_id, 1, ship.state, ship.stats.crew_max)))
	%Hire10.pressed.connect(_act.bind(func(): return Ports.hire(port_id, 10, ship.state, ship.stats.crew_max)))
	%Dismiss10.pressed.connect(_act.bind(func(): return Ports.dismiss(port_id, 10, ship.state)))
	%PayWages.pressed.connect(_pay_wages)
	%Rumour.pressed.connect(_rumour)


func open(id: String, player_ship: Node2D) -> void:
	port_id = id
	ship = player_ship
	rumours_left = Data.rules.tavern.rumours_per_visit
	%Rumours.text = ""
	%Status.text = ""
	UIKit.pause_clock()
	Ports.record_prices(port_id, int(Clock.day))
	refresh()
	show()


func close() -> void:
	hide()
	UIKit.resume_clock()
	closed.emit()


func refresh() -> void:
	var p := Ports.port(port_id)
	var laws: Dictionary = Ports.state[port_id].laws
	%Title.text = "%s  (%s)" % [p.name, Data.table("factions")[p.faction].name]
	var law_text := "No contraband laws." if laws.contraband.is_empty() else "Contraband: %s. Customs vigilance %d%%." % [
		", ".join(laws.contraband.map(func(g): return Data.table("goods")[g].name)), int(laws.vigilance * 100)]
	law_text += "  Stolen goods sell at %s here." % ("full price through the fence" if p.get("fence", false) else "half price, no questions asked")
	%Info.text = "Governor: %s\n%s\n%s\nGold %d   Hold %d / %d tons" % [p.governor, p.description, law_text,
		ship.state.gold, Market.cargo_used(ship.state.cargo), ship.capacity()]
	_build_market()
	_build_shipyard()
	_refresh_tavern()


func _build_market() -> void:
	var grid: GridContainer = %MarketGrid
	UIKit.clear(grid)
	for h in ["Good", "In hold", "Buy", "Sell", "Best known elsewhere", "", "Buy", "", "", "Sell", ""]:
		UIKit.label(grid, h, "", UIKit.HEADER)

	var p := Ports.port(port_id)
	var ps: Dictionary = Ports.state[port_id]
	var s: Dictionary = ship.state
	var haggle := ShipStats.spread_mult(s)
	for good in Data.table("goods"):
		var tip := Market.breakdown(p, good, ps, ps.laws, haggle)
		var contraband: bool = good in ps.laws.contraband
		var sell := Ports.price(port_id, good, false, haggle)
		UIKit.label(grid, Data.table("goods")[good].name + (" (contraband)" if contraband else ""), tip, UIKit.BAD if contraband else Color.WHITE)

		var have: float = s.cargo.get(good, 0.0)
		var hold := ""
		if have > 0:
			hold = "%d" % have
			if s.cargo_cost.get(good, 0.0) > 0:
				hold += " (paid %s)" % Market.fmt(s.cargo_cost[good] / have)
			if s.stolen.get(good, 0) > 0:
				hold += " [%d stolen]" % s.stolen[good]
		UIKit.label(grid, hold)
		UIKit.label(grid, Market.fmt(Ports.price(port_id, good, true, haggle)), tip)
		UIKit.label(grid, Market.fmt(sell), tip)

		var best := Ports.best_known_sale(good, port_id)
		if best.is_empty():
			UIKit.label(grid, "-")
		else:
			UIKit.label(grid, "%s at %s, %dd ago" % [Market.fmt(best.sell), Ports.port(best.port).name, int(Clock.day) - int(best.day)], "",
				UIKit.GOOD if best.sell > sell * 1.15 else UIKit.DIM)

		var lot := 10 if Market.weight(good) < 1.0 else 1  # provisions trade in larger lots
		for q in [lot, lot * 10, 100000]:
			UIKit.button(grid, "+%d" % q if q < 100000 else "Max", _act.bind(func(): return _traded(Ports.buy(port_id, good, q, s, ship.capacity(), haggle))))
		for q in [lot, lot * 10, 100000]:
			var b := UIKit.button(grid, "-%d" % q if q < 100000 else "All", _act.bind(func(): return _traded(Ports.sell(port_id, good, q, s, haggle))))
			if contraband:
				b.tooltip_text = "Risk of seizure: %d%%" % int(100 * Market.seizure_chance(ps.laws, good, mini(q, int(have))))
			b.disabled = have < 1


func _build_shipyard() -> void:
	var box: VBoxContainer = %YardBox
	UIKit.clear(box)
	var level: int = Ports.port(port_id).shipyard
	if level == 0:
		UIKit.label(box, "There is no shipyard here. Your carpenter can patch the ship at sea, but only so far.")
		return
	var s: Dictionary = ship.state
	var st: Dictionary = ship.stats
	var y: Dictionary = Data.rules.shipyard
	var per_day: int = y.hull_per_day[level]
	UIKit.label(box, "%s shipyard. Work here takes days; the crew still eat and draw wages while you wait." % ["", "Small", "Large"][level], "", UIKit.DIM)

	UIKit.label(box, "")
	UIKit.label(box, "Condition", "", UIKit.HEADER)
	UIKit.label(box, "Hull %d / %d   Sails %d / %d   Guns dismounted %d   Fouling %d%%" % [s.hull, st.hull, s.sails, st.sails, s.guns_lost, int(s.fouling * 100)])
	var r := UIKit.row(box)
	for days in [1, 0]:
		var job := _repair_job(per_day, days)
		var b := UIKit.button(r, ("Work 1 day (%d gold)" if days == 1 else "Full repair (%d gold, " + str(job.days) + " days)") % job.cost,
			_repair.bind(days), "Repairs up to %d hull and %d sails a day." % [per_day, per_day])
		b.disabled = job.cost <= 0 or job.cost > s.gold
	var careen_cost := int(y.careen_cost_per_hull * st.hull)
	var cb := UIKit.button(r, "Careen (%d gold, %d days)" % [careen_cost, y.careen_days], _careen.bind(careen_cost),
		"Heel her over on the beach and scrape the hull clean. Removes all fouling.")
	cb.disabled = s.fouling < 0.01 or careen_cost > s.gold

	if s.prizes.size() > 0:
		UIKit.label(box, "")
		UIKit.label(box, "Your prizes", "", UIKit.HEADER)
		var pg := UIKit.grid(box, 4)
		for i in s.prizes.size():
			var prize: Dictionary = s.prizes[i]
			var value := Ports.prize_value(port_id, prize)
			UIKit.label(pg, "%s (%s), hull %d, %d prize crew" % [prize.name, Data.table("ships")[prize.type].name, prize.hull, prize.crew.size()])
			UIKit.label(pg, "worth %d" % value, "Hull condition and any cargo left aboard (stolen goods at fence rates).")
			UIKit.button(pg, "Sell", _act.bind(func(): return Ports.sell_prize(port_id, i, s)), "The prize crew rejoins you.")
			UIKit.button(pg, "Make her your flagship", _act.bind(func():
				var res := Ports.prize_to_flagship(i, s)
				if res.ok:
					ship.refresh_stats()
				return res), "Your current ship is sold to the yard at trade-in value. Upgrades are lost.")

	UIKit.label(box, "")
	var trade_in := ShipStats.trade_in_value(s)
	UIKit.label(box, "Ships for sale (your %s is worth %d in trade)" % [Data.table("ships")[s.type].name, trade_in], "", UIKit.HEADER)
	var g := UIKit.grid(box, 6)
	for type_id in Ports.port(port_id).ships_for_sale:
		if type_id == s.type:
			continue
		var t: Dictionary = Data.table("ships")[type_id]
		var tip := "%s\n\n%s" % [t.description, _compare(type_id)]
		UIKit.label(g, t.name, tip)
		UIKit.label(g, "%d gold" % t.price, tip)
		UIKit.label(g, "hull %d, hold %d, guns %d" % [t.hull, t.cargo, t.guns], tip)
		UIKit.label(g, "crew %d-%d, %s draught" % [t.crew_min, t.crew_max, Data.rules.draught[t.draught].name.to_lower()], tip)
		UIKit.label(g, "net %d" % (t.price - trade_in), "Price minus what your ship fetches in trade.")
		var b := UIKit.button(g, "Buy", _act.bind(func():
			var res := Ports.buy_ship(type_id, s)
			if res.ok:
				ship.refresh_stats()
			return res), "Your upgrades stay with the old ship.")
		b.disabled = t.price - trade_in > s.gold

	UIKit.label(box, "")
	UIKit.label(box, "Upgrades", "", UIKit.HEADER)
	var ug := UIKit.grid(box, 4)
	for u in Data.table("upgrades"):
		var up: Dictionary = Data.table("upgrades")[u]
		var reason := ShipStats.cannot_install(s, u, level)
		var cost := ShipStats.upgrade_cost(u, s.type)
		var tip := "%s\n%s" % [up.description, _effects_text(up.effects)]
		UIKit.label(ug, up.name + (" (fitted)" if u in s.upgrades else ""), tip, UIKit.GOOD if u in s.upgrades else Color.WHITE)
		UIKit.label(ug, "%d gold, %d day%s" % [cost, up.days, "" if up.days == 1 else "s"], tip)
		UIKit.label(ug, reason, "", UIKit.DIM)
		var b := UIKit.button(ug, "Fit", _install.bind(u, cost), "Replaces other guns." if up.get("group", "") == "cannons" else "")
		b.disabled = reason != "" or cost > s.gold


func _compare(type_id: String) -> String:
	var now: Dictionary = ship.stats
	var new_st := ShipStats.effective(type_id, [])
	var lines := PackedStringArray(["Compared with your ship (before upgrades):"])
	for k in ["hull", "sails", "speed_knots", "turning", "cargo", "crew_min", "crew_max", "guns", "gun_weight", "upkeep"]:
		var d = new_st[k] - now[k]
		lines.append("%s: %s (%s%s)" % [ShipStats.LABELS[k], ShipStats._fmt(new_st[k]), "+" if d >= 0 else "", ShipStats._fmt(d)])
	return "\n".join(lines)


static func _effects_text(fx: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in fx.get("set", {}):
		parts.append("%s = %s" % [ShipStats.LABELS.get(k, k), fx.set[k]])
	for k in fx.get("add", {}):
		parts.append("%s %+d" % [ShipStats.LABELS.get(k, k), fx.add[k]])
	for k in fx.get("mult", {}):
		parts.append("%s x%.2f" % [ShipStats.LABELS.get(k, k), fx.mult[k]])
	return ", ".join(parts)


# days = 1: one day of work; days = 0: everything.
func _repair_job(per_day: int, days: int) -> Dictionary:
	var y: Dictionary = Data.rules.shipyard
	var hull_missing := int(ship.stats.hull - ship.state.hull)
	var sails_missing := int(ship.stats.sails - ship.state.sails)
	var need_days := ceili(maxf(hull_missing, sails_missing) / per_day)
	var d := need_days if days == 0 else mini(1, need_days)
	var h := mini(hull_missing, per_day * d)
	var sl := mini(sails_missing, per_day * d)
	var guns: int = ship.state.guns_lost if d > 0 or days == 0 else 0
	return {"days": maxi(d, 1 if guns > 0 else 0), "hull": h, "sails": sl, "guns": guns,
		"cost": int(h * y.cost_per_hull + sl * y.cost_per_sail + guns * y.cost_per_gun)}


func _repair(days: int) -> void:
	var job := _repair_job(Data.rules.shipyard.hull_per_day[Ports.port(port_id).shipyard], days)
	ship.state.gold -= job.cost
	ship.state.hull += job.hull
	ship.state.sails += job.sails
	ship.state.guns_lost -= job.guns
	Clock.advance(job.days)  # the world moves on while you wait: upkeep, storms, prices
	_act(func(): return {"ok": true, "text": "Repaired %d hull, %d sails and %d guns in %d days for %d gold." % [job.hull, job.sails, job.guns, job.days, job.cost]})


func _careen(cost: int) -> void:
	var days: int = Data.rules.shipyard.careen_days
	ship.state.gold -= cost
	ship.state.fouling = 0.0
	Clock.advance(days)
	_act(func(): return {"ok": true, "text": "Careened the %s in %d days for %d gold. Her hull is clean." % [ship.state.name, days, cost]})


func _install(u: String, cost: int) -> void:
	var up: Dictionary = Data.table("upgrades")[u]
	ship.state.gold -= cost
	ShipStats.install(ship.state, u)
	ship.refresh_stats()
	Clock.advance(up.days)
	_act(func(): return {"ok": true, "text": "Fitted %s in %d days for %d gold." % [up.name, up.days, cost]})


func _refresh_tavern() -> void:
	var ps: Dictionary = Ports.state[port_id]
	var t: Dictionary = Data.rules.tavern
	%TavernInfo.text = "Sailors looking for a berth: %d. Signing bounty %d each.\nCrew %d (needs %d, berths %d). Each hand eats, drinks and draws %s a day in wages.\nNew hands may hide their true nature until they've been at sea a while." % [
		ps.sailors, t.hire_cost, ShipStats.headcount(ship.state), ShipStats.crew_needed(ship.state, ship.stats),
		ship.stats.crew_max, Market.fmt(Data.rules.upkeep.wage_per_crew)]
	%PayWages.text = "Pay wages owed (%d)" % ship.state.wages_owed
	%PayWages.disabled = ship.state.wages_owed <= 0 or ship.state.gold <= 0
	%Rumour.text = "Buy a round and listen (%d gold, %d left this visit)" % [t.round_cost, rumours_left]
	%Rumour.disabled = rumours_left <= 0 or ship.state.gold < t.round_cost
	%Dismiss10.tooltip_text = "Pays off your 10 least useful hands (never officers). Fewer mouths and wages, but a short-handed ship sails slower."
	for c in %Hostages.get_children():
		c.queue_free()
	var s: Dictionary = ship.state
	for i in s.hostages.size():
		var h: Dictionary = s.hostages[i]
		if h.faction == Ports.port(port_id).faction:
			UIKit.button(%Hostages, "Ransom %s for %d gold" % [People.person(h.id).name, h.ransom],
				_act.bind(func(): return Ports.ransom(port_id, s, i)))


func _act(action: Callable) -> void:
	var result: Dictionary = action.call()
	%Status.text = result.text
	if result.ok:
		message.emit("%s: %s" % [Ports.port(port_id).name, result.text])
	Ports.record_prices(port_id, int(Clock.day))
	refresh()


## The captain learns to haggle by trading: XP grows with the value of each deal.
func _traded(result: Dictionary) -> Dictionary:
	var cap := ShipStats.captain(ship.state)
	if People.gain_xp(cap, "trade", result.get("value", 0) / 200.0):
		result.text += " Your Trade skill improves to %d." % cap.skills.trade
	return result


func _pay_wages() -> void:
	var paid := minf(ship.state.gold, ship.state.wages_owed)
	ship.state.gold -= paid
	ship.state.wages_owed -= paid
	_act(func(): return {"ok": true, "text": "Paid %d in owed wages." % paid})


func _rumour() -> void:
	rumours_left -= 1
	ship.state.gold -= Data.rules.tavern.round_cost
	var text := Ports.rumour(port_id, int(Clock.day))
	%Rumours.text += "\"%s\"\n" % text
	_act(func(): return {"ok": true, "text": "Rumour: " + text})
