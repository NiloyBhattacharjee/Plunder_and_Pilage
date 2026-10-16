extends CanvasLayer
## Port screen: the town (what it's like and what's going on: see scripts/port_life.gd), market, shipyard and tavern. Time is paused while it's open;
## only actions that take time (repairs, careening, refits) move the clock.
## Hover over prices and stats for a breakdown of why they are what they are.

signal message(text: String)
signal closed
signal life_event(event_id: String)  # a happening's event: the world map runs it, then brings you back here

var port_id := ""
var ship: Node2D
var rumours_left := 0
var disguised := false  # came in under false colours or by bribe: keep your head down
var _town: VBoxContainer
var _done := {}         # happenings you've already taken part in this visit


func _ready() -> void:
	%SetSail.pressed.connect(close)
	%Hire1.pressed.connect(_act.bind(func(): return Ports.hire(port_id, 1, ship.state, ship.stats.crew_max)))
	%Hire10.pressed.connect(_act.bind(func(): return Ports.hire(port_id, 10, ship.state, ship.stats.crew_max)))
	%Dismiss10.pressed.connect(_act.bind(func(): return Ports.dismiss(port_id, 10, ship.state)))
	%PayWages.pressed.connect(_pay_wages)
	%Rumour.pressed.connect(_rumour)
	var scroll := ScrollContainer.new()  # the town comes first: it's what you see stepping ashore
	scroll.name = "Town"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	%Tabs.add_child(scroll)
	%Tabs.move_child(scroll, 0)
	_town = VBoxContainer.new()
	_town.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_town.add_theme_constant_override("separation", 6)
	scroll.add_child(_town)


func open(id: String, player_ship: Node2D, in_disguise := false) -> void:
	port_id = id
	ship = player_ship
	disguised = in_disguise
	rumours_left = Data.rules.tavern.rumours_per_visit + PortLife.bonus(id, "rumours")
	_done = {}
	%Tabs.current_tab = 0
	%Rumours.text = ""
	%Status.text = ""
	UIKit.pause_clock()
	Ports.record_prices(port_id, int(Clock.day))
	var heard := Ports.learn_board(port_id)
	if heard > 0:
		%Status.text = "Ships in harbour bring news of prices at %d other port%s." % [heard, "" if heard == 1 else "s"]
	refresh()
	show()


## Back from a happening's event: the same visit, picked up where you left it.
func reopen() -> void:
	UIKit.pause_clock()
	refresh()
	show()


func close() -> void:
	var s: Dictionary = ship.state
	if s.career.marque == Ports.port(port_id).faction and s.career.crown_debt > 0 and not disguised:
		s.relations[s.career.marque] -= int(Data.rules.career.arrears_visit_penalty)  # the Admiralty notes your arrears
		message.emit("You sail without settling the Crown's share. The Admiralty takes note (standing -%d)." % Data.rules.career.arrears_visit_penalty)
		if s.career.crown_debt > Data.rules.career.arrears_revoke:
			message.emit(Career.revoke(s, "for cheating the Crown of its share"))
	hide()
	UIKit.resume_clock()
	closed.emit()


func refresh() -> void:
	var p := Ports.port(port_id)
	var laws: Dictionary = Ports.state[port_id].laws
	%Title.text = "%s  (%s)" % [p.name, Data.table("factions")[p.faction].name]
	var law_text := "No contraband laws." if laws.contraband.is_empty() else "Contraband: %s. Customs vigilance %d%%." % [
		", ".join(laws.contraband.map(func(g): return Data.table("goods")[g].name)), int(laws.vigilance * 100)]
	law_text += "  Stolen goods sell at %s here." % ("nearly full price through the fence (it has %d gold to spare)" % Ports.state[port_id].fence_cash
		if p.get("fence", false) else "half price, no questions asked")
	if not laws.get("enumerated", []).is_empty():
		law_text += "  %s go only in %s ships." % [", ".join(laws.enumerated.map(func(g): return Data.table("goods")[g].name)), Data.table("factions")[p.faction].adjective]
	var gov := Politics.official(port_id, "governor")
	law_text += "  " + Politics.law_text(port_id)
	var fleet := Economy.fleet_text(port_id)
	if fleet != "":
		law_text += "
" + fleet
	%Info.text = "%s\n%s\n%s\nGold %d   Hold %d / %d tons" % ["Governor: " + People.person(gov).name if gov != "" else "Ruled by the council of captains",
		p.description, law_text, ship.state.gold, Market.cargo_used(ship.state.cargo), ship.capacity()]
	_build_town()
	_build_market()
	_build_shipyard()
	_refresh_tavern()
	_build_governor()
	_build_contracts()
	_build_politics()


func _build_market() -> void:
	var grid: GridContainer = %MarketGrid
	UIKit.clear(grid)
	grid.columns = 14
	for h in ["", "Good", "Stock", "In hold", "Buy", "Sell", "Trend", "Elsewhere", "", "Buy", "", "", "Sell", ""]:
		UIKit.label(grid, h, "", Style.c("header"))

	var ps: Dictionary = Ports.state[port_id]
	var s: Dictionary = ship.state
	var haggle := ShipStats.spread_mult(s) * Career.price_mult(s, port_id)  # haggling, and how they regard you here
	for good in Data.table("goods"):
		var gd: Dictionary = Data.table("goods")[good]
		var tip := Economy.breakdown(port_id, good, haggle)
		var contraband: bool = good in ps.laws.contraband
		var sell := Ports.price(port_id, good, false, haggle)
		UIKit.icon(grid, gd.get("icon", ""), 24)
		var name_box := VBoxContainer.new()
		name_box.add_theme_constant_override("separation", -4)
		grid.add_child(name_box)
		UIKit.label(name_box, gd.name, tip + ("
" + gd.note if gd.has("note") else ""), Style.c("bad") if contraband else Color(0, 0, 0, 0))
		var why := Economy.reason(port_id, good)
		if contraband:
			why = "Contraband here" + (": " + why if why != "" else "")
		elif good in ps.laws.get("enumerated", []) and Career.flag_faction(s.get("flag", "white")) != Ports.port(port_id).faction:
			why = "%s ships only: loading it is smuggling" % Data.table("factions")[Ports.port(port_id).faction].adjective.capitalize()
		if why != "":
			UIKit.label(name_box, why, tip, Style.c("dim")).add_theme_font_size_override("font_size", 14)

		var lv := Economy.level(port_id, good)
		UIKit.label(grid, {"scarce": "Scarce", "plenty": "Plenty", "normal": "Normal"}[lv] if Economy.model.is_traded(good) else "",
			"%d in the warehouses." % Economy.stock(port_id, good) if Economy.model.is_traded(good) else "",
			{"scarce": Style.c("bad"), "plenty": Style.c("good"), "normal": Style.c("dim")}[lv])

		var have: float = s.cargo.get(good, 0.0)
		var hold := ""
		if have > 0:
			hold = "%d" % have
			if s.cargo_cost.get(good, 0.0) > 0:
				hold += " (paid %s)" % Market.fmt(s.cargo_cost[good] / have)
			if s.stolen.get(good, 0) > 0:
				hold += " [%d stolen]" % s.stolen[good]
		UIKit.label(grid, hold, "What you hold, and the average you paid for it.")
		UIKit.label(grid, Market.fmt(Ports.price(port_id, good, true, haggle)), tip)
		UIKit.label(grid, Market.fmt(sell), tip)
		if Economy.model.is_traded(good):
			grid.add_child(PriceSpark.make(Economy.history(port_id, good), Economy.mult(port_id, good)))
		else:
			UIKit.label(grid, "")

		var best := Ports.best_known_sale(good, port_id, s)
		if best.is_empty():
			UIKit.label(grid, "-", "You've heard nothing of its price anywhere else. Ships in harbour, tavern talk and captured papers bring news.")
		else:
			var est: Dictionary = best.est
			var age := int(Clock.day) - int(best.day)
			var sale_tip := "Best place you know of to sell it: %s." % Ports.port(best.port).name
			if not est.is_empty():
				var how: String = {"seen": "you saw it there", "news": "news on the quay", "papers": "a captured ship's papers", "hail": "a ship you spoke at sea", "rumour": "tavern talk"}.get(est.heard.get("source", "seen"), "")
				sale_tip += "\nHeard %d days ago (%s): it sold at %s." % [age, how, Market.fmt(est.heard.sell)]
				if age > 0:
					sale_tip += "\n%s reckons it's about %s now, give or take %d%%. Old news leans on what the port usually pays; trade skill and allies make the guess better." % [
						est.who, Market.fmt(est.sell), int(round(est.err * 100))]
				if est.heard.get("source", "") == "rumour":
					sale_tip += "\nRumours can be wrong."
			UIKit.label(grid, "%s%s %s %dd" % ["~" if age > 0 else "", Market.fmt(best.sell), Ports.port(best.port).name, age], sale_tip,
				Style.c("good") if best.sell > sell * 1.15 else Style.c("dim"))

		var lot := 10 if Market.weight(good) <= 0.2 else 1  # provisions and water trade in larger lots
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
	UIKit.label(box, "%s shipyard. Work here takes days; the crew still eat and draw wages while you wait." % ["", "Small", "Large"][level], "", Style.c("dim"))

	UIKit.label(box, "")
	UIKit.label(box, "Condition", "", Style.c("header"))
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
		UIKit.label(box, "Your prizes", "", Style.c("header"))
		var pg := UIKit.grid(box, 4)
		for i in s.prizes.size():
			var prize: Dictionary = s.prizes[i]
			var value := Ports.prize_value(port_id, prize)
			UIKit.label(pg, "%s (%s), hull %d, %d hands%s" % [prize.name, Data.table("ships")[prize.type].name, prize.hull, Fleet.hands(prize),
				", Captain " + People.person(prize.captain).name if Fleet.ensure(prize).captain != "" else ""])
			UIKit.label(pg, "worth %d" % value, "Hull condition and any cargo left aboard (stolen goods at fence rates).")
			UIKit.button(pg, "Sell", _act.bind(func(): return Ports.sell_prize(port_id, i, s)), "Everyone aboard her rejoins you.")
			UIKit.button(pg, "Make her your flagship", _act.bind(func():
				var res := Ports.prize_to_flagship(i, s)
				if res.ok:
					ship.refresh_stats()
				return res), "Your current ship is sold to the yard at trade-in value. (To keep her, shift your flag from the Fleet tab instead.)")

	UIKit.label(box, "")
	var trade_in := ShipStats.trade_in_value(s)
	UIKit.label(box, "Ships for sale (your %s is worth %d in trade)" % [Data.table("ships")[s.type].name, trade_in], "", Style.c("header"))
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
		var why := Ports.cannot_buy_ship(port_id, type_id, s)
		var b := UIKit.button(g, "Buy", _act.bind(func():
			var res := Ports.buy_ship(port_id, type_id, s)
			if res.ok:
				ship.refresh_stats()
			return res), why if why != "" else "Your upgrades stay with the old ship.")
		b.disabled = why != ""

	UIKit.label(box, "")
	UIKit.label(box, "Upgrades  (%s)" % ShipStats.slots_text(s), "Every ship has only so much room in her hull, rigging, hold and on deck. Cannons don't take a slot.", Style.c("header"))
	var ug := UIKit.grid(box, 5)
	for u in Data.table("upgrades"):
		var up: Dictionary = Data.table("upgrades")[u]
		var reason := ShipStats.cannot_install(s, u, level)
		var cost := ShipStats.upgrade_cost(u, s.type)
		var tip := "%s\n%s" % [up.description, _effects_text(up.effects)]
		UIKit.label(ug, up.name + (" (fitted)" if u in s.upgrades else ""), tip, Style.c("good") if u in s.upgrades else Color(0, 0, 0, 0))
		UIKit.label(ug, "%d gold, %d day%s" % [cost, up.days, "" if up.days == 1 else "s"], tip)
		UIKit.label(ug, reason, "", Style.c("dim"))
		var b := UIKit.button(ug, "Fit", _install.bind(u, cost), "Replaces other guns." if up.get("group", "") == "cannons" else "")
		b.disabled = reason != "" or cost > s.gold
		if u in s.upgrades and up.has("slot"):
			UIKit.button(ug, "Take out", _act.bind(func():
				ShipStats.remove(s, u)
				ship.refresh_stats()
				return {"ok": true, "text": "Took out the %s. Nothing comes back but the room." % up.name.to_lower()}), "Frees the %s slot. No refund." % up.slot)
		else:
			UIKit.label(ug, "")
	UIKit.label(box, "")
	ShipLooksUI.build(box, s, s, func(text):
		ship.refresh_stats()
		_act(func(): return {"ok": true, "text": text}))


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
	var discount = EconomyEffects.active(ship.state, "repair_discount")
	var mult: float = 1.0 - (discount.percent / 100.0 if discount != null else 0.0)
	return {"days": maxi(d, 1 if guns > 0 else 0), "hull": h, "sails": sl, "guns": guns,
		"cost": int((h * y.cost_per_hull + sl * y.cost_per_sail + guns * y.cost_per_gun) * mult)}


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


func _build_governor() -> void:
	var box: VBoxContainer = %GovBox
	UIKit.clear(box)
	var s: Dictionary = ship.state
	var p := Ports.port(port_id)
	var f: String = p.faction
	UIKit.label(box, "Governor %s" % (People.person(Politics.official(port_id, "governor")).name if f != "pirates" else ""), "", Style.c("header"))
	UIKit.label(box, "Your standing with %s: %+d.  You are: %s." % [Career.fname(f), s.relations.get(f, 0), Career.status_text(s)],
		"Standing changes prices here (x%.2f), who will deal with you, and whether the harbour stays open." % Career.price_mult(s, port_id))
	UIKit.label(box, Factions.war_summary(), "", Style.c("dim"))
	if f != "pirates" and not disguised:
		var brow := UIKit.row(box)
		UIKit.label(brow, "Your bond with %s: %s.  " % [Career.fname(f), Bonds.level_name("f:" + f, Bonds.level(s, "f:" + f))], "Beyond standing: a nation can be your ally, or your patron.")
		_bond_buttons(brow, "f:" + f, s)
	if disguised:
		UIKit.label(box, "You're here under false colours. The governor's door is not one to knock on.", "", Style.c("bad"))
		return
	if f == "pirates":
		UIKit.label(box, "There is no governor's mansion here. The haven is ruled by its council of captains: see the Politics tab.", "", Style.c("dim"))
		return

	UIKit.label(box, "")
	var c: Dictionary = s.career
	if c.marque == f:
		var ranks: Array = Data.rules.career.ranks
		var next_rank: String = "" if c.rank + 1 >= ranks.size() else " Next: %s at %d service." % [ranks[c.rank + 1].name, ranks[c.rank + 1].service]
		UIKit.label(box, "Your commission: %s, %d service.%s" % [Career.rank_name(s), c.service, next_rank],
			"Service is the value of the lawful prizes you've taken. Rank cuts the Crown's share (now %d%%) and raises your standing." % int(Career.crown_cut(s) * 100))
		UIKit.label(box, "Lawful targets: " + ", ".join(Factions.enemies_of(f).map(func(e): return Career.fname(e))) + ", and any pirate.")
		var row := UIKit.row(box)
		var pay := UIKit.button(row, "Pay the Crown's share (%d)" % c.crown_debt, _act.bind(func(): return {"ok": true, "text": Career.pay_crown(s)}),
			"Leave without paying and the Admiralty marks you down each visit; owe too much and you lose the commission.")
		pay.disabled = c.crown_debt <= 0 or s.gold <= 0
		UIKit.button(row, "Hand back your commission", _act.bind(func(): return {"ok": true, "text": Career.revoke(s, "at your own request")}),
			"You'll be an honest captain again: no lawful targets except pirates.")
	else:
		var why := Career.marque_problem(s, f)
		var enemies := Factions.enemies_of(f)
		var tip := "Benefits: attack %s ships lawfully; their prizes sell clean; rank brings a smaller Crown's share, better standing and the right to buy warships.\nCosts: the Crown takes %d%% of every prize; %s will hate you; peace voids the letter, and raiding after that is piracy." % [
			", ".join(enemies.map(func(e): return Career.fname(e))) if not enemies.is_empty() else "no one", int(Data.rules.career.crown_cut * 100),
			", ".join(enemies.map(func(e): return Career.fname(e))) if not enemies.is_empty() else "nobody"]
		var b := UIKit.button(box, "Request a letter of marque", _act.bind(func(): return {"ok": true, "text": Career.grant_marque(s, f)}),
			why if why != "" else tip)
		b.disabled = why != ""
		if why != "":
			UIKit.label(box, why, "", Style.c("dim"))

	if c.pirate:
		UIKit.label(box, "")
		var cost := Career.pardon_cost(s, f, port_id)
		var why2 := Career.pardon_problem(s, f, port_id)
		var tip2 := "%s forgives you%s. Notoriety halves; standing with %s rises to at least 0.\nThe Brethren will call you a turncoat (standing -%d), crew who love the trade will resent it, and other nations remember." % [
			Career.fname(f), "" if cost == 0 else " for %d gold" % cost, Career.fname(f), Data.rules.pardon.pirate_relation_hit]
		var b2 := UIKit.button(box, ("Accept the King's Pardon (free)" if cost == 0 else "Seek a pardon (%d gold)" % cost),
			_act.bind(func(): return {"ok": true, "text": " ".join(Career.pardon(s, f, false, port_id))}), why2 if why2 != "" else tip2)
		b2.disabled = why2 != ""


func _build_contracts() -> void:
	var box: VBoxContainer = %ContractBox
	UIKit.clear(box)
	var s: Dictionary = ship.state
	var free: float = ship.capacity() - Market.cargo_used(s.cargo)
	var offers := Contracts.offers_at(port_id, s)
	for role in ["governor", "broker"]:
		var emp := Contracts.employer(port_id, role)
		if emp == "":
			continue
		var e := People.person(emp)
		var r := UIKit.row(box)
		r.add_child(Portrait.make(e, "captain", 48))
		UIKit.label(r, "%s %s.   Trust in you: %+d" % ["Governor" if role == "governor" else "The broker", e.name, Contracts.trust(emp, s)],
			People.describe(e) + "\n\nTrust grows with every job done and unlocks bigger ones. Failing a job costs it.")
		if role == "governor" and disguised:
			UIKit.label(box, "You're here under false colours: the governor's office is no place for you.", "", Style.c("bad"))
			continue
		var g := UIKit.grid(box, 3)
		var mine := offers.filter(func(c): return c.employer == emp)
		if mine.is_empty():
			UIKit.label(g, "No work on offer just now.", "", Style.c("dim"))
		for c in mine:
			var tip := Contracts.details(c, s)
			UIKit.label(g, c.name, tip)
			UIKit.label(g, "%d gold, %d days, risk: %s" % [c.reward, c.days, Contracts.risk(c, s)], tip)
			var why := Contracts.problem(c, s, free)
			var b := UIKit.button(g, "Accept", _act.bind(func(): return {"ok": true, "text": Contracts.accept(c, s, free)}), why if why != "" else tip)
			b.disabled = why != ""
		UIKit.label(box, "")

	UIKit.label(box, "Your contracts (%d of %d)" % [Contracts.active.size(), Data.rules.contracts.max_active], "", Style.c("header"))
	if Contracts.active.is_empty():
		UIKit.label(box, "None. Every job pays, and every job is a promise.", "", Style.c("dim"))
	for c in Contracts.active.duplicate():
		var r := UIKit.row(box)
		UIKit.label(r, Contracts.summary(c), Contracts.details(c, s))
		if c.status == "done":
			if c.pay_port != port_id:
				continue
			var pay := Contracts.offered_pay(c)
			if c.lied:
				var full: int = c.reward + int(c.get("deposit", 0))
				UIKit.button(r, "Take the %d offered" % pay, _act.bind(func(): return {"ok": true, "text": Contracts.collect(c, s)}),
					"You were promised %d. Take what's offered and keep the peace." % full)
				UIKit.button(r, "Demand the full %d (%d%%)" % [full, int(Contracts.demand_odds(c, s) * 100)], _act.bind(func(): return {"ok": true, "text": Contracts.collect(c, s, true)}),
					"Your intimidation and fearsome name against their authority. Lose and you take the short pay and lose their trust.")
			else:
				UIKit.button(r, "Collect %d gold" % pay, _act.bind(func(): return {"ok": true, "text": Contracts.collect(c, s)}))
			continue
		if c.objective == "deliver" and c.dest == port_id:
			var tip := "Hand over the dispatches." if c.good == "dispatches" else "Chance customs seize the goods on the quay: %d%%." % int(Contracts.seizure_risk(c) * 100)
			if c.trap and c.good != "dispatches":
				UIKit.label(box, "Customs men swarm the quay today, as if someone told them to expect you.", "", Style.c("bad"))
			UIKit.button(r, "Deliver", _act.bind(func(): return {"ok": true, "text": Contracts.deliver(c, s)}), tip)
		if c.good == "dispatches" and Ports.port(port_id).faction != "pirates" and Factions.at_war(Ports.port(port_id).faction, c.faction) and not disguised:
			UIKit.button(r, "Sell the dispatches here (%d)" % int(c.reward * Data.rules.contracts.betray.mult), _act.bind(func(): return {"ok": true, "text": Contracts.betray(c, s, port_id)}),
				"The enemy pays well for those seals. Your employer will never trust you again, and if word gets out (%d%%), %s brands you a traitor." % [
					int(Data.rules.contracts.betray.discovery * 100), Data.table("factions")[c.faction].name])
		UIKit.button(r, "Abandon", _act.bind(func(): return {"ok": true, "text": Contracts.abandon(c, s)}), "Counts as failing the job.")


## Who holds power, the laws it makes, the people in office, the secrets you hold over them, and Nassau's council.
func _build_politics() -> void:
	var box: VBoxContainer = %PolBox
	UIKit.clear(box)
	var s: Dictionary = ship.state
	var P: Dictionary = Data.table("politics")
	var ctx := {"s": s, "stats": ship.stats, "port": port_id, "storm": false}
	var power := Politics.power(port_id)
	var groups: Array = power.keys().filter(func(g): return power[g] >= 1.0)
	groups.sort_custom(func(a, b): return power[a] > power[b])
	UIKit.label(box, "Who holds power", "Interest groups and their sway over the governor. The strongest shape the laws.\nWorking for a group (political contracts) raises its influence; scandals cut it.", Style.c("header"))
	var row := UIKit.row(box)
	for g in groups:
		var gd: Dictionary = P.groups[g]
		var prefs := "Wants: customs %d%%, tariff %+d%%, pirates %s, pardons %s." % [int(gd.laws.vigilance * 100), int(gd.laws.tariff * 100),
			"welcome" if gd.laws.pirates > 0.3 else ("hanged" if gd.laws.pirates < -0.6 else "watched"), "easier" if gd.laws.pardon > 0.2 else "harder"]
		UIKit.label(row, "%s %d%%    " % [gd.name, power[g]], gd.description + "\n" + prefs, Style.c("good") if g == Politics.dominant(port_id) else Color(0, 0, 0, 0))
	var t := Politics.target_laws(port_id)
	var laws: Dictionary = Ports.state[port_id].laws
	var lrow := UIKit.row(box)
	for pair in [["vigilance", "Customs vigilance %d%%" % int(laws.vigilance * 100), "Catches smugglers and sees through false colours. Moves gradually toward what the powerful want (%d%%)." % int(t.vigilance.value * 100)],
			["tariff", "Tariff %+d%%" % int(laws.get("tariff", 0.0) * 100), "Added to the price of everything you buy and taken off what you sell."],
			["pirates", "Pirates: %s" % ("welcome" if laws.get("pirates", 0.0) > 0.4 else ("tolerated" if laws.get("pirates", 0.0) > -0.2 else ("hunted" if laws.get("pirates", 0.0) > -0.6 else "hanged"))),
				"Where pirates are welcome, a wanted pirate can still come ashore. Where they're hanged, the harbour master's bribe costs more."],
			["pardon", "Pardons %s" % ("cheaper" if laws.get("pardon", 0.0) > 0.1 else ("dearer" if laws.get("pardon", 0.0) < -0.1 else "at the usual price")), "Where the church is strong, repentance costs less."]]:
		var parts := PackedStringArray()
		for p in t[pair[0]].parts:
			if absf(p[1]) >= 0.005:
				parts.append("%s %+.2f" % p)
		UIKit.label(lrow, pair[1] + "    ", pair[2] + "\n" + ", ".join(parts))
	UIKit.label(box, "")

	var here := Politics.officials_at(port_id)
	if not here.is_empty():
		UIKit.label(box, "People who matter", "Favours are owed both ways and tied to the person (and to you: a new captain starts afresh).\nCall one in for what gold can't buy, or ask now and owe them; they'll call it in when it suits them.", Style.c("header"))
	for id in here:
		var c := People.person(id)
		var line := UIKit.row(box)
		line.add_child(Portrait.make(c, "captain", 44))
		var owed := Politics.favours(id, s)
		UIKit.label(line, "%s: %s.  Opinion of you %+d.  Wants to %s.  %s%s" % [P.roles[c.role].name, c.name, c.relations.get(s.captain, 0),
			P.goals[c.get("goal", "keep_order")].name, ("Owes you %d favour%s." % [owed, "" if owed == 1 else "s"]) if owed > 0 else (("You owe them %d." % -owed) if owed < 0 else ""),
			("  " + Bonds.level_name(id, Bonds.level(s, id)) + ".") if Bonds.level(s, id) != 0 else ""],
			People.describe(c))
		if disguised and c.role == "governor":
			continue
		var acts := UIKit.row(box)  # favours on their own line, under the person
		var indent := Control.new()
		indent.custom_minimum_size = Vector2(52, 0)
		acts.add_child(indent)
		_bond_buttons(acts, id, s)
		for kind in P.roles[c.role].favours:
			var f: Dictionary = P.favours[kind]
			var why := Politics.favour_problem(id, s, kind, false)
			var b := UIKit.button(acts, "%s (%d)" % [f.name, f.cost], _act.bind(func(): return {"ok": true, "text": Politics.use_favour(id, s, kind, ctx)}),
				why if why != "" else f.description)
			b.disabled = why != ""
			if why != "":
				var ask := Politics.favour_problem(id, s, kind, true)
				var ab := UIKit.button(acts, "Ask", _act.bind(func(): return {"ok": true, "text": Politics.use_favour(id, s, kind, ctx, true)}),
					ask if ask != "" else f.description + "\nYou'll owe %s %d favour%s." % [c.name, f.cost, "" if f.cost == 1 else "s"])
				ab.disabled = ask != ""

	var mine: Array = s.get("secrets", []).filter(func(x): return x.port == port_id)
	if not mine.is_empty():
		UIKit.label(box, "")
		UIKit.label(box, "Secrets you hold here", "Blackmail: favours now and every month, and an enemy. Sell: to the person who likes them least. Expose: the Crown recalls them and thanks you.\nA forgery ruins whatever you try.", Style.c("header"))
	for sec in mine:
		var line := UIKit.row(box)
		UIKit.label(line, Politics.describe(sec) + (" (it may be forged)" if sec.doubt else "") + (" (you're blackmailing them)" if sec.leverage else ""))
		if sec.kind == "schedule":
			UIKit.button(line, "Act on it", _act.bind(func(): return {"ok": true, "text": Politics.act_on_schedule(s, sec)}), "Lie in wait on her course.")
		elif not sec.leverage:
			UIKit.button(line, "Blackmail", _act.bind(func(): return {"ok": true, "text": Politics.blackmail(s, sec)}), "Favours now and every month after. They'll want you gone.")
		var rival := Politics.rival_of(sec)
		if rival != "":
			UIKit.button(line, "Sell to %s (%d)" % [People.person(rival).name, Politics.value(sec)], _act.bind(func(): return {"ok": true, "text": Politics.sell(s, sec)}),
				"%s likes them least. Gold and a favour; %d%% chance they learn who sold it." % [People.person(rival).name, int(P.sell_discovered * 100)])
		if Ports.port(port_id).faction != "pirates" and not disguised:
			UIKit.button(line, "Expose to the Crown", _act.bind(func(): return {"ok": true, "text": Politics.expose(s, sec)}),
				"A scandal: they're recalled and replaced, their side loses influence, and %s thanks you." % Data.table("factions")[Ports.port(port_id).faction].name)

	var here_captains: Array = Bonds.roster().filter(func(id): return People.person(id).haunt == port_id)
	if not here_captains.is_empty():
		UIKit.label(box, "")
		UIKit.label(box, "Captains in port", "Named captains who use this port. Ally with them and their ship fights beside you; cross them and they come after you.", Style.c("header"))
	for id in here_captains:
		var c := People.person(id)
		var line := UIKit.row(box)
		line.add_child(Portrait.make(c, "captain", 44))
		var lvl := Bonds.level(s, id)
		UIKit.label(line, "%s of the %s (%s).  Opinion of you %+d.%s" % [c.name, c.ship, Data.table("ships")[c.ship_type].name.to_lower(),
			c.relations.get(s.captain, 0), ("  " + Bonds.level_name(id, lvl) + ".") if lvl != 0 else ""], People.describe(c))
		_bond_buttons(line, id, s)
	if Ports.port(port_id).faction == "pirates":
		UIKit.label(box, "")
		var brethren := UIKit.row(box)
		UIKit.label(brethren, "The Brethren of the Coast: %s.  " % Bonds.level_name("f:pirates", Bonds.level(s, "f:pirates")), "Your bond with the pirates as a whole.", Style.c("header"))
		_bond_buttons(brethren, "f:pirates", s)
	if port_id == "nassau":
		_build_council(box, s)


## Propose the next step, declare a rivalry, or break a bond. Every button explains itself first.
func _bond_buttons(parent: Node, key: String, s: Dictionary) -> void:
	var lvl := Bonds.level(s, key)
	var acc := Bonds.acceptance(s, key)
	if lvl < 4:
		var label := "Make peace" if lvl < 0 else "Propose: %s" % Bonds.level_name(key, acc.next)
		var b := UIKit.button(parent, label + (" (%d/%d)" % [acc.score, acc.need]), _act.bind(func(): return {"ok": true, "text": Bonds.propose(s, key)}), Bonds.preview(s, key))
		b.modulate = Color(1, 1, 1, 1.0 if acc.ok else 0.6)
	if lvl > 0:
		UIKit.button(parent, "Break it", _act.bind(func(): return {"ok": true, "text": Bonds.break_bond(s, key)}),
			"Honour -%d, and everyone you know trusts you a little less.%s" % [lvl * Data.table("bonds").break_honour,
				" They'll be your rival." if lvl >= 2 and not key.begins_with("f:") else ""])
	elif not key.begins_with("f:") and lvl > -3:
		UIKit.button(parent, "Declare a rivalry" if lvl == 0 else "Escalate", _act.bind(func(): return {"ok": true, "text": Bonds.declare(s, key)}),
			"%s
Rivals compete, then feud, then hunt you. Beating a rival brings fame, and a bounty if they're a pirate; your crew pull together against a common enemy." % Bonds.cfg().rivalry[mini(2, -lvl)].text)


func _build_council(box: Node, s: Dictionary) -> void:
	UIKit.label(box, "")
	var lead := Politics.council_leader
	UIKit.label(box, "The council of captains", "Nassau's captains decide its great matters by vote: pardons, defence, the code. You can win votes with friendship, gold and favours, and lead the council by vote or by the sword.", Style.c("header"))
	for id in Politics.council_members():
		var c := People.person(id)
		var line := UIKit.row(box)
		line.add_child(Portrait.make(c, "captain", 44))
		var owed := Politics.favours(id, s)
		UIKit.label(line, "%s of the %s%s.  Opinion of you %+d.%s" % [c.name, c.ship, " (leader)" if id == lead else "", c.relations.get(s.captain, 0),
			"  Owes you %d." % owed if owed > 0 else ""], People.describe(c))
		_bond_buttons(line, id, s)
		var b := UIKit.button(line, "Buy their vote (%d)" % Data.table("politics").council.bribe, _act.bind(func(): return {"ok": true, "text": Politics.bribe(s, id)}),
			"Gold talks: their opinion of you +%d." % Data.table("politics").council.bribe_opinion)
		b.disabled = s.gold < Data.table("politics").council.bribe
	var row := UIKit.row(box)
	if not s.get("council_member", false):
		var why := Politics.council_problem(s)
		var j := UIKit.button(row, "Take a seat on the council", _act.bind(func():
			s.council_member = true
			return {"ok": true, "text": "You sit with the captains of Nassau now."}), why if why != "" else "Votes, favours and enemies come with it.")
		j.disabled = why != ""
	elif lead == "player":
		UIKit.label(row, "You lead the council.", "", Style.c("good"))
	else:
		UIKit.button(row, "Stand for leader", _act.bind(func(): return {"ok": true, "text": Politics.leadership_vote(s)}),
			"Each captain backs whoever they like better, with favours counting for you. Lose, and the leader holds it against you.")
		UIKit.button(row, "Challenge %s to a duel" % People.person(lead).name, _act.bind(func(): return {"ok": true, "text": Politics.challenge(s)}),
			"By the old code. Your swordplay against theirs. Win and the council is yours; lose and you'll carry the scar.")


func _refresh_tavern() -> void:
	var ps: Dictionary = Ports.state[port_id]
	var t: Dictionary = Data.rules.tavern
	%TavernInfo.text = "Sailors looking for a berth: %d. Signing bounty %d each.\nCrew %d (needs %d, berths %d). Each hand eats, drinks and draws %s a day in wages.\nNew hands may hide their true nature until they've been at sea a while." % [
		ps.sailors, Ports.hire_cost(port_id), ShipStats.headcount(ship.state), ShipStats.crew_needed(ship.state, ship.stats),
		ship.stats.crew_max, Market.fmt(Data.rules.upkeep.wage_per_crew)]
	%PayWages.text = "Pay wages owed (%d)" % ship.state.wages_owed
	%PayWages.disabled = ship.state.wages_owed <= 0 or ship.state.gold <= 0
	%Rumour.text = "Buy a round and listen (%d gold, %d left this visit)" % [t.round_cost, rumours_left]
	%Rumour.disabled = rumours_left <= 0 or ship.state.gold < t.round_cost
	%Dismiss10.tooltip_text = "Pays off your 10 least useful hands (never officers). Fewer mouths and wages, but a short-handed ship sails slower."
	UIKit.clear(%Notables)
	var ps2: Dictionary = Ports.state[port_id]
	if not ps2.notables.is_empty():
		UIKit.label(%Notables, "Hands worth a closer look (hover for what you know):", "", Style.c("header"))
		var ng := UIKit.grid(%Notables, 5)
		for i in ps2.notables.size():
			var c: Dictionary = ps2.notables[i]
			ng.add_child(Portrait.make(c, "crew", 44))
			UIKit.label(ng, "%s, %s" % [c.name, Data.table("nations")[c.nationality].name], People.describe(c))
			UIKit.label(ng, People.trait_names(c), People.describe(c))
			UIKit.button(ng, "Interview (%d)" % t.interview_cost, _act.bind(func(): return Ports.interview(port_id, i, ship.state)),
				"Buy them a drink. Your charisma decides how much they let slip.")
			UIKit.button(ng, "Hire (%d)" % Ports.notable_cost(c), _act.bind(func(): return Ports.hire_notable(port_id, i, ship.state, ship.stats.crew_max)))
	for c in %Hostages.get_children():
		c.queue_free()
	var s: Dictionary = ship.state
	for i in s.hostages.size():
		var h: Dictionary = s.hostages[i]
		if h.faction == Ports.port(port_id).faction:
			UIKit.button(%Hostages, "Ransom %s for %d gold" % [People.person(h.id).name, h.ransom],
				_act.bind(func(): return Ports.ransom(port_id, s, i)))


## The town: what it's like (and why, in the tooltips), how it sees you, and what's going on.
func _build_town() -> void:
	UIKit.clear(_town)
	var t := PortLife.situation(port_id)
	var head := UIKit.label(_town, "%s is %s." % [Ports.port(port_id).name, PortLife.describe(port_id)], PortLife.explain(port_id), Style.c("header"))
	head.theme_type_variation = &"Header"
	var g := UIKit.grid(_town, 10)
	var tips := {
		"Wealth": "How rich the town is: its size, and how its trade is doing. Rich towns give balls; poor ones breed fever and beggars.",
		"Prosperity": "What its goods fetch against what it must buy. Prosperous towns hold feast days and pay for errands.",
		"Hunger": "The price of food against its usual price. Hungry towns riot, and hungry men sign on cheap.",
		"Order": "Soldiers and priests against the hungry poor, and war. Orderly towns hang pirates; restless ones riot and set curfews.",
		"Piety": "The church's say in the town."}
	for k in tips:
		var v: float = t[k.to_lower()]
		UIKit.label(g, k, tips[k])
		var l := UIKit.label(g, "%d" % v, PortLife.explain(port_id))
		var bad: bool = (k == "Hunger" and v >= 40.0) or (k != "Hunger" and k != "Piety" and v < 30.0)
		l.add_theme_color_override("font_color", Style.c("bad") if bad else Style.c("ink"))
	var s: Dictionary = ship.state
	var rel: int = s.relations.get(Ports.port(port_id).faction, 0)
	var seen := "a stranger"
	if Career.wanted(s):
		seen = "a wanted pirate (keep your head down)"
	elif rel >= 30:
		seen = "a friend of the town"
	elif rel >= 10:
		seen = "a respected captain"
	elif rel <= -20:
		seen = "unwelcome"
	if s.reputation.notoriety >= 40 and not Career.wanted(s):
		seen += ", and everyone knows your name"
	UIKit.label(_town, "Here you are %s. (Standing %+d, honour %+d, notoriety %d.)" % [seen, rel, s.reputation.honour, s.reputation.notoriety],
		"How the town sees you decides what you're invited to, and what's said behind your back.", Style.c("dim"))
	UIKit.label(_town, "What's going on", "", Style.c("header"))
	var on := PortLife.active(port_id)
	if on.is_empty():
		UIKit.label(_town, "Nothing out of the ordinary. (Feast days come to prosperous towns, bread riots to hungry ones, press gangs to ports at war, balls to rich and orderly capitals, fever to poor towns in the wet season.)", "", Style.c("dim")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for h in on:
		var box := VBoxContainer.new()
		_town.add_child(box)
		var days := ceili(h.until - Clock.day)
		UIKit.label(box, "%s  (%d more day%s)" % [PortLife.name_of(port_id, h.id), days, "" if days == 1 else "s"], "", Style.c("header"))
		var txt := UIKit.label(box, PortLife.text_of(port_id, h), "")
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.custom_minimum_size.x = 1000
		var fx: Dictionary = PortLife.table()[h.id].get("effects", {})
		var lines := PackedStringArray()
		if fx.has("hire_cost"):
			lines.append("signing bounty x%.1f" % fx.hire_cost)
		if fx.has("sailors"):
			lines.append("seamen looking for a berth x%.1f" % fx.sailors)
		if fx.has("rumours"):
			lines.append("%d more rumours in the tavern" % fx.rumours)
		if not lines.is_empty():
			UIKit.label(box, "While it lasts: " + ", ".join(lines) + ".", "", Style.c("dim"))
		var a := PortLife.action(port_id, h, s, ship.stats)
		if not a.is_empty() and not disguised:
			var done: bool = _done.has(h.id)
			var b := UIKit.button(box, a.text if not done else a.text + " (done)", func():
				_done[h.id] = true
				hide()
				life_event.emit(a.event), a.problem)
			b.disabled = a.problem != "" or done
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


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


func _officer_charisma(role: String) -> int:
	var id: String = ship.state.officers.get(role, "")
	return People.value(People.person(id), "charisma") if id != "" else 0


func _rumour() -> void:
	rumours_left -= 1
	ship.state.gold -= Data.rules.tavern.round_cost
	var t: Dictionary = Data.rules.tavern
	var charisma := maxi(People.value(ShipStats.captain(ship.state), "charisma"), _officer_charisma("quartermaster"))
	var text := Ports.rumour(port_id, int(Clock.day), maxf(0.05, t.false_rumour_chance - charisma * t.false_rumour_per_charisma))
	%Rumours.text += "\"%s\"\n" % text
	_act(func(): return {"ok": true, "text": "Rumour: " + text})
