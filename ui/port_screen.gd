extends CanvasLayer
## Port screen: market, shipyard and tavern. Time is paused while it's open;
## only actions that take time (repairs) move the clock.
## Hover over prices for a breakdown of why they are what they are.

signal message(text: String)
signal closed

const BAD := Color("#c0392b")
const GOOD := Color("#2e8b57")

var port_id := ""
var ship: Node2D
var rumours_left := 0


func _ready() -> void:
	%SetSail.pressed.connect(close)
	%Repair10.pressed.connect(_repair.bind(10))
	%RepairAll.pressed.connect(_repair.bind(100000))
	%Hire1.pressed.connect(_act.bind(func(): return Ports.hire(port_id, 1, ship.state, ship.stats.crew_max)))
	%Hire10.pressed.connect(_act.bind(func(): return Ports.hire(port_id, 10, ship.state, ship.stats.crew_max)))
	%Dismiss10.pressed.connect(_dismiss)
	%PayWages.pressed.connect(_pay_wages)
	%Rumour.pressed.connect(_rumour)


func open(id: String, player_ship: Node2D) -> void:
	port_id = id
	ship = player_ship
	rumours_left = Data.rules.tavern.rumours_per_visit
	%Rumours.text = ""
	%Status.text = ""
	if Clock.speed_index > 0:
		Clock.toggle_pause()
	Ports.record_prices(port_id, int(Clock.day))
	refresh()
	show()


func close() -> void:
	hide()
	if Clock.speed_index == 0:
		Clock.toggle_pause()
	closed.emit()


func refresh() -> void:
	var p := Ports.port(port_id)
	var laws: Dictionary = Ports.state[port_id].laws
	%Title.text = "%s  (%s)" % [p.name, Data.table("factions")[p.faction].name]
	var law_text := "No contraband laws." if laws.contraband.is_empty() else "Contraband: %s. Customs vigilance %d%%." % [
		", ".join(laws.contraband.map(func(g): return Data.table("goods")[g].name)), int(laws.vigilance * 100)]
	%Info.text = "Governor: %s\n%s\n%s\nGold %d   Hold %d / %d tons" % [p.governor, p.description, law_text,
		ship.state.gold, Market.cargo_used(ship.state.cargo), ship.capacity()]
	_build_market()
	_refresh_shipyard()
	_refresh_tavern()


func _build_market() -> void:
	var grid: GridContainer = %MarketGrid
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	for h in ["Good", "In hold", "Buy", "Sell", "Best known elsewhere", "", "Buy", "", "", "Sell", ""]:
		_label(grid, h, "", Color(0.8, 0.75, 0.6))

	var p := Ports.port(port_id)
	var ps: Dictionary = Ports.state[port_id]
	var s: Dictionary = ship.state
	for good in Data.table("goods"):
		var tip := Market.breakdown(p, good, ps, ps.laws)
		var contraband: bool = good in ps.laws.contraband
		var sell := Ports.price(port_id, good, false)
		_label(grid, Data.table("goods")[good].name + (" (contraband)" if contraband else ""), tip, BAD if contraband else Color.WHITE)

		var have: float = s.cargo.get(good, 0.0)
		var hold := ""
		if have > 0:
			hold = "%d" % have
			if s.cargo_cost.has(good) and s.cargo_cost[good] > 0:
				hold += " (paid %s)" % Market.fmt(s.cargo_cost[good] / have)
		_label(grid, hold)
		_label(grid, Market.fmt(Ports.price(port_id, good, true)), tip)
		_label(grid, Market.fmt(sell), tip)

		var best := Ports.best_known_sale(good, port_id)
		if best.is_empty():
			_label(grid, "-")
		else:
			var age := int(Clock.day) - int(best.day)
			_label(grid, "%s at %s, %dd ago" % [Market.fmt(best.sell), Ports.port(best.port).name, age], "",
				GOOD if best.sell > sell * 1.15 else Color(0.85, 0.85, 0.85))

		var lot := 10 if Market.weight(good) < 1.0 else 1  # provisions trade in larger lots
		for q in [lot, lot * 10, 100000]:
			_button(grid, "+%d" % q if q < 100000 else "Max", _act.bind(func(): return Ports.buy(port_id, good, q, s, ship.capacity())))
		for q in [lot, lot * 10, 100000]:
			var b := _button(grid, "-%d" % q if q < 100000 else "All", _act.bind(func(): return Ports.sell(port_id, good, q, s)))
			if contraband:
				b.tooltip_text = "Risk of seizure: %d%%" % int(100 * Market.seizure_chance(ps.laws, good, mini(q, int(have))))
			b.disabled = have < 1


func _refresh_shipyard() -> void:
	var level: int = Ports.port(port_id).shipyard
	var per_day: int = Data.rules.shipyard.hull_per_day[level]
	var cost: float = Data.rules.shipyard.cost_per_hull
	var missing := int(ship.stats.hull - ship.state.hull)
	if level == 0:
		%YardInfo.text = "There is no shipyard here."
	else:
		%YardInfo.text = "Hull %d / %d. %s shipyard: repairs %d hull a day at %s gold per point.\nRepairs take time; the crew still eat and draw wages while you wait." % [
			ship.state.hull, ship.stats.hull, ["", "Small", "Large"][level], per_day, Market.fmt(cost)]
	for pair in [[%Repair10, 10], [%RepairAll, missing]]:
		var amount := mini(pair[1], missing)
		var days := ceili(float(amount) / per_day) if per_day > 0 else 0
		pair[0].text = "Repair %d (%d gold, %d day%s)" % [amount, amount * cost, days, "" if days == 1 else "s"]
		pair[0].disabled = level == 0 or amount <= 0 or ship.state.gold < amount * cost


func _refresh_tavern() -> void:
	var ps: Dictionary = Ports.state[port_id]
	var t: Dictionary = Data.rules.tavern
	%TavernInfo.text = "Sailors looking for a berth: %d. Signing bounty %d each.\nCrew %d / %d. Each sailor eats, drinks and draws %s a day in wages." % [
		ps.sailors, t.hire_cost, ship.state.crew, ship.stats.crew_max, Market.fmt(Data.rules.upkeep.wage_per_crew)]
	%PayWages.text = "Pay wages owed (%d)" % ship.state.wages_owed
	%PayWages.disabled = ship.state.wages_owed <= 0 or ship.state.gold <= 0
	%Rumour.text = "Buy a round and listen (%d gold, %d left this visit)" % [t.round_cost, rumours_left]
	%Rumour.disabled = rumours_left <= 0 or ship.state.gold < t.round_cost


func _act(action: Callable) -> void:
	var result: Dictionary = action.call()
	%Status.text = result.text
	if result.ok:
		message.emit("%s: %s" % [Ports.port(port_id).name, result.text])
	Ports.record_prices(port_id, int(Clock.day))
	refresh()


func _repair(amount: int) -> void:
	var per_day: int = Data.rules.shipyard.hull_per_day[Ports.port(port_id).shipyard]
	var cost: float = Data.rules.shipyard.cost_per_hull
	amount = mini(amount, int(ship.stats.hull - ship.state.hull))
	var days := ceili(float(amount) / per_day)
	ship.state.gold -= amount * cost
	ship.state.hull += amount
	Clock.advance(days)  # the world moves on while you wait: upkeep, storms, prices
	_act(func(): return {"ok": true, "text": "Repaired %d hull in %d days for %d gold." % [amount, days, amount * cost]})


func _dismiss() -> void:
	var n := mini(10, ship.state.crew - 1)
	ship.state.crew -= n
	_act(func(): return {"ok": n > 0, "text": "Paid off %d sailors." % n})


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


func _label(parent: Node, text: String, tip := "", color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if tip != "":
		l.tooltip_text = tip
		l.mouse_filter = Control.MOUSE_FILTER_PASS  # labels ignore the mouse by default, so no tooltip
	parent.add_child(l)
	return l


func _button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b
