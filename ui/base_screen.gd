extends CanvasLayer
## Your base: the cove, its buildings, its storehouse and its shipyard. Time is paused while it's open,
## except for work that takes days (careening, repairs). Every number explains itself on hover.

signal message(text: String)
signal closed

var base_id := ""
var ship: Node2D


func _ready() -> void:
	%Close.pressed.connect(close)


func open(id: String, player_ship: Node2D) -> void:
	base_id = id
	ship = player_ship
	%Status.text = ""
	UIKit.pause_clock()
	refresh()
	show()


func close() -> void:
	hide()
	UIKit.resume_clock()
	closed.emit()


func _act(action: Callable) -> void:
	var text: String = action.call()
	%Status.text = text
	if text != "":
		message.emit(text)
	if not Bases.bases.has(base_id):
		close()
		return
	refresh()


func refresh() -> void:
	var b: Dictionary = Bases.bases[base_id]
	var s: Dictionary = ship.state
	%Title.text = "%s  (your base)" % b.name
	var upkeep: float = b.garrison * Data.rules.bases.garrison_wage
	for bid in b.buildings:
		upkeep += Bases.building(bid).upkeep
	var raid := ""
	if not b.raid.is_empty() and b.raid.warned:
		raid = "\nRAID COMING: %s, in about %d days." % [b.raid.label, maxi(0, int(b.raid.day - Clock.day))]
	%Info.text = "%s\nTreasury %d gold, upkeep %s a day.   Your gold %d.   Hold %d / %d tons.%s" % [Bases.cove(base_id).description, b.gold,
		Market.fmt(upkeep), s.gold, Market.cargo_used(s.cargo), ship.capacity(), raid]
	_build_cove(b, s)
	_build_buildings(b, s)
	_build_stores(b, s)
	_build_yard(b, s)


# ---- the cove: people, money, defence -----------------------------------------------------

func _build_cove(b: Dictionary, s: Dictionary) -> void:
	var box: VBoxContainer = %CoveBox
	UIKit.clear(box)
	var R: Dictionary = Data.rules.bases
	var chance: float = b.visibility * R.raid_per_visibility + Bonds.rivals(s, 2).size() * R.raid_rival_bonus + (R.raid_wanted_bonus if Career.wanted(s) else 0.0)
	UIKit.label(box, "Visibility %d%%   (raid risk about %.1f%% a day)" % [b.visibility, chance * 100],
		"How easy the base is to find. Every building, every man ashore, every visit and every sale gives it away a little; quiet days and a well-hidden cove (shelter %d) let it fade.\nRivals in a feud and a price on your head make raids likelier." % Bases.cove(base_id).shelter, Style.c("header"))
	var parts := Bases.defence_parts(s, base_id)
	var total := 0
	var lines := PackedStringArray()
	for p in parts:
		total += p[1]
		lines.append("%s: %+d" % p)
	UIKit.label(box, "Defence %+d" % total, "Rolled against the raiders (pirates %+d, hunters %+d, a navy squadron %+d) if a raid comes while you're away:\n%s\nBe here and you fight it at sea, with the shore guns beside you." % [
		R.raiders.pirate.strength, R.raiders.hunter.strength, R.raiders.navy.strength, "\n".join(lines)])

	UIKit.label(box, "")
	var row := UIKit.row(box)
	UIKit.label(row, "Garrison %d, loyalty %d.   " % [b.garrison, b.loyalty],
		"The garrison is paid %s a day each from the treasury and eats from the storehouse%s. Unpaid or hungry, loyalty falls; below %d they desert.\nA good manager's authority and a tavern keep them happy. Fewer than 5 men and nothing gets grown or made." % [
			Market.fmt(R.garrison_wage), "" if Bases.cove(base_id).water else " (food and water: there's no spring here)", R.desert_below])
	UIKit.button(row, "Leave 5 hands ashore", func(): _act(func(): return Bases.send_garrison(s, base_id, 5)), "Five of your least useful hands join the garrison.")
	UIKit.button(row, "Take 5 aboard", func(): _act(func(): return Bases.take_garrison(s, base_id, 5, ship.stats.crew_max)))

	var mrow := UIKit.row(box)
	var man: String = b.manager
	UIKit.label(mrow, "Run by: %s.   " % (People.person(man).name if man != "" else "nobody"),
		"Whoever runs the base: their trade raises what it grows and what the smugglers pay, their authority keeps the garrison loyal, their intimidation holds it in a raid, their carpentry speeds building.\nA manager who comes to hate you may take the base for themselves.")
	var pick := OptionButton.new()
	pick.add_item("(appoint someone)")
	pick.set_item_metadata(0, "")
	var cands: Array = s.crew.duplicate()
	cands.sort_custom(func(x, y): return People.leadership(People.person(x)) > People.leadership(People.person(y)))
	for id in cands.slice(0, 12):
		var c := People.person(id)
		pick.add_item("%s (authority %d, trade %d)" % [c.name, People.value(c, "authority"), People.value(c, "trade")])
		pick.set_item_metadata(pick.item_count - 1, id)
	pick.item_selected.connect(func(i): if i > 0: _act(func(): return Bases.appoint(s, base_id, pick.get_item_metadata(i))))
	mrow.add_child(pick)
	if man != "":
		UIKit.button(mrow, "Bring them back aboard", func(): _act(func(): return Bases.appoint(s, base_id, "")))

	var trow := UIKit.row(box)
	UIKit.label(trow, "Treasury %d.   " % b.gold, "Wages and upkeep come out of the treasury, not your purse. Ransoms from the stockade land here. Gold ashore is safe if you lose a fight at sea.")
	for amt in [100, 500]:
		var d := UIKit.button(trow, "Deposit %d" % amt, func(): _act(func():
			s.gold -= amt
			b.gold += amt
			return "Deposited %d." % amt))
		d.disabled = s.gold < amt
	var w := UIKit.button(trow, "Withdraw all", func(): _act(func():
		var g: float = b.gold
		s.gold += g
		b.gold = 0.0
		return "Took %d from the treasury." % g))
	w.disabled = b.gold <= 0

	var food_days: float = b.storage.get("food", 0.0) / maxf(0.1, b.garrison * R.food_per_man)
	var srow := UIKit.row(box)
	UIKit.label(srow, "Food ashore %d (%d days)%s.   " % [b.storage.get("food", 0.0), food_days,
		"" if Bases.cove(base_id).water else ", water %d" % b.storage.get("water", 0.0)], "Land provisions for the garrison from your hold.")
	for g in ["food", "water"]:
		if g == "water" and Bases.cove(base_id).water:
			continue
		var l := UIKit.button(srow, "Land 50 %s" % g, func(): _act(func(): return Bases.move_goods(s, base_id, g, 50, ship.capacity())))
		l.disabled = s.cargo.get(g, 0.0) < 1

	if Bases.has(b, "tavern"):
		var rrow := UIKit.row(box)
		UIKit.label(rrow, "%d sailors at the tavern looking for a berth.   " % int(b.recruits))
		var h := UIKit.button(rrow, "Hire 5 (%d gold)" % (5 * Data.rules.tavern.hire_cost), func(): _act(func(): return Bases.recruit(s, base_id, 5, ship.stats.crew_max)))
		h.disabled = b.recruits < 1
	if Bases.has(b, "stockade"):
		UIKit.label(box, "")
		UIKit.label(box, "Stockade", "Hostages left here are ransomed through a go-between: half again what a port pays, after %d days." % Bases.building("stockade").ransom_days, Style.c("header"))
		for h in b.hostages:
			UIKit.label(box, "%s: ransom due in %d days." % [People.person(h.id).name, maxi(0, int(h.day - Clock.day))])
		for i in s.hostages.size():
			UIKit.button(box, "Lock up %s" % People.person(s.hostages[i].id).name, func(): _act(func(): return Bases.leave_hostage(s, base_id, i)))


# ---- buildings -----------------------------------------------------------------------

func _build_buildings(b: Dictionary, s: Dictionary) -> void:
	var box: VBoxContainer = %BuildBox
	UIKit.clear(box)
	if not b.building.is_empty():
		UIKit.label(box, "Building the %s: %d days left." % [Bases.building(b.building.id).name.to_lower(), ceili(b.building.left)], "", Style.c("header"))
	var g := UIKit.grid(box, 5)
	for h in ["Building", "Cost", "Time", "Upkeep", ""]:
		UIKit.label(g, h, "", Style.c("header"))
	for bid in Data.table("buildings"):
		if bid.begins_with("_"):
			continue
		var bd := Bases.building(bid)
		var built := Bases.has(b, bid)
		UIKit.label(g, bd.name + (" (built)" if built else ""), bd.description, Style.c("good") if built else Color(0, 0, 0, 0))
		UIKit.label(g, "%d gold" % bd.cost)
		UIKit.label(g, "%d days" % bd.days)
		UIKit.label(g, "%s a day" % Market.fmt(bd.upkeep), "Paid from the base treasury. It also makes the base a little easier to find (+%.2f visibility a day)." % bd.visibility)
		if built:
			UIKit.label(g, "")
			continue
		var why := Bases.build_problem(s, base_id, bid)
		var btn := UIKit.button(g, "Build", func(): _act(func(): return Bases.build(s, base_id, bid)), why if why != "" else bd.description)
		btn.disabled = why != ""


# ---- the storehouse ---------------------------------------------------------------------

func _build_stores(b: Dictionary, s: Dictionary) -> void:
	var box: VBoxContainer = %StoreBox
	UIKit.clear(box)
	var market := Bases.has(b, "smugglers_market")
	UIKit.label(box, "Ashore %d / %d tons. Goods here are safe if you strike your colours at sea.%s" % [Bases.stored(b), Bases.capacity(b),
		" The smugglers pay full price for stolen goods, at the rates in %s." % Ports.port(Bases.nearest_port(base_id)).name if market else ""], "", Style.c("header"))
	var g := UIKit.grid(box, 9 if market else 7)
	for h in (["", "Good", "Aboard", "Ashore", "", "", ""] + (["Price", ""] if market else [])):
		UIKit.label(g, h, "", Style.c("header"))
	for good in Data.table("goods"):
		var have: float = s.cargo.get(good, 0.0)
		var ashore: float = b.storage.get(good, 0.0)
		if have < 1 and ashore < 1:
			continue
		UIKit.icon(g, Data.table("goods")[good].get("icon", ""), 24)
		UIKit.label(g, Data.table("goods")[good].name)
		UIKit.label(g, "%d%s" % [have, " [%d stolen]" % s.stolen.get(good, 0) if s.stolen.get(good, 0) > 0 else ""])
		UIKit.label(g, "%d%s" % [ashore, " [%d stolen]" % b.stolen.get(good, 0) if b.stolen.get(good, 0.0) >= 1 else ""])
		var land := UIKit.button(g, "Land all", func(): _act(func(): return Bases.move_goods(s, base_id, good, have, ship.capacity())))
		land.disabled = have < 1
		var load := UIKit.button(g, "Load 10", func(): _act(func(): return Bases.move_goods(s, base_id, good, -10, ship.capacity())))
		load.disabled = ashore < 1
		var load_all := UIKit.button(g, "Load all", func(): _act(func(): return Bases.move_goods(s, base_id, good, -ashore, ship.capacity())))
		load_all.disabled = ashore < 1
		if market:
			UIKit.label(g, Market.fmt(Bases.smuggler_price(base_id, good)))
			var sell := UIKit.button(g, "Sell all ashore", func(): _act(func(): return Bases.sell(s, base_id, good, ashore)), "Selling draws attention: visibility +%d." % Data.rules.bases.visibility_sale)
			sell.disabled = ashore < 1


# ---- the shipyard ------------------------------------------------------------------------

func _build_yard(b: Dictionary, s: Dictionary) -> void:
	var box: VBoxContainer = %YardBox
	UIKit.clear(box)
	var st: Dictionary = ship.stats
	var y: Dictionary = Data.rules.shipyard
	UIKit.label(box, "Hull %d / %d   Sails %d / %d   Guns dismounted %d   Fouling %d%%" % [s.hull, st.hull, s.sails, st.sails, s.guns_lost, int(s.fouling * 100)])
	if Bases.has(b, "careening_yard"):
		var c := UIKit.button(box, "Careen her here (free, 2 days)", func(): _act(func():
			s.fouling = 0.0
			Clock.advance(2)
			return "Careened at %s. Her hull is clean." % b.name), "Your own beach and tackle: no fee.")
		c.disabled = s.fouling < 0.01
	else:
		UIKit.label(box, "Build a careening yard to clean her hull here.", "", Style.c("dim"))
	if Bases.has(b, "shipyard"):
		var mult: float = Bases.building("shipyard").repair_mult
		var hull: int = int(st.hull - s.hull)
		var sails: int = int(st.sails - s.sails)
		var cost := int((hull * y.cost_per_hull + sails * y.cost_per_sail + s.guns_lost * y.cost_per_gun) * mult)
		var days := maxi(1, ceili(maxf(hull, sails) / float(y.hull_per_day[2])))
		var r := UIKit.button(box, "Full repair (%d gold, %d days)" % [cost, days], func(): _act(func():
			s.gold -= cost
			s.hull = float(st.hull)
			s.sails = float(st.sails)
			s.guns_lost = 0
			Clock.advance(days)
			return "Repaired at %s for %d gold." % [b.name, cost]), "Half what a port's yard charges.")
		r.disabled = cost <= 0 or cost > s.gold
	else:
		UIKit.label(box, "Build a shipyard for cheap repairs.", "", Style.c("dim"))
	UIKit.label(box, "")
	UIKit.label(box, "Prizes", "Leave prizes at the dock and they stop slowing you down. Take them again when you want to sell them.", Style.c("header"))
	if not Bases.has(b, "dock"):
		UIKit.label(box, "Build a dock to keep prizes here.", "", Style.c("dim"))
		return
	for i in s.prizes.size():
		var p: Dictionary = s.prizes[i]
		UIKit.button(box, "Leave the %s here" % p.name, func(): _act(func():
			s.prizes.remove_at(i)
			s.crew.append_array(p.crew)
			p.crew = []
			b.prizes.append(p)
			return "The %s is moored at %s. Her prize crew rejoins you." % [p.name, b.name]))
	for i in b.prizes.size():
		var p: Dictionary = b.prizes[i]
		var need := Encounters.prize_crew_needed({"type": p.type})
		UIKit.button(box, "Take the %s with you (needs %d hands)" % [p.name, need], func(): _act(func():
			if s.prizes.size() >= Data.rules.prizes.max:
				return "You can't manage more prizes at sea."
			var movers: Array = s.crew.filter(func(c): return not c in s.officers.values()).slice(0, need)
			if movers.size() < need:
				return "Not enough hands for a prize crew."
			for c in movers:
				s.crew.erase(c)
			p.crew = movers
			b.prizes.remove_at(i)
			s.prizes.append(p)
			return "A prize crew takes the %s out." % p.name))
