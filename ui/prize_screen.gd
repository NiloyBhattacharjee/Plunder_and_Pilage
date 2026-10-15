extends CanvasLayer
## After a ship strikes: take her cargo, decide her fate, the prisoners' fate and her captain's.
## Every choice shows its consequences in a tooltip before you commit.

signal done(messages: Array)

var ship: Node2D
var enemy: Dictionary      # encounter data (cargo is taken from here)
var survivors := 0
var messages := []
var taken_value := 0.0   # base value of cargo taken, for the Crown's share and your service

var _ship_fate: OptionButton
var _prisoner_fate: OptionButton
var _recruit: CheckBox
var _captain_fate: OptionButton


func _ready() -> void:
	hide()
	%Done.pressed.connect(_finish)


func open(player_ship: Node2D, result: Dictionary) -> void:
	ship = player_ship
	enemy = result.enemy_data
	enemy.hull = result.enemy.hull
	enemy.sails = result.enemy.sails
	survivors = int(result.enemy.crew)
	messages = []
	taken_value = 0.0
	ship.state.gold += enemy.gold
	messages.append("Plundered %d gold from the %s's strongbox." % [enemy.gold, enemy.name])
	var share := Crew.plunder(ship.state, enemy.gold)
	if share != "":
		messages.append(share)
	%Title.text = "The %s is yours" % enemy.name
	%Status.text = ""
	_build()
	show()


func _build() -> void:
	var box: VBoxContainer = %Body
	UIKit.clear(box)
	var s: Dictionary = ship.state
	%Info.text = "%s\n%d of her crew survive.  Gold taken: %d.  Your hold %d / %d tons." % [
		Encounters.sighting(enemy, RandomNumberGenerator.new()).split(".")[0], survivors, enemy.gold,
		Market.cargo_used(s.cargo), ship.capacity()]

	var lawful: bool = enemy.get("legal", true)
	UIKit.label(box, "Her cargo (%s)" % ("a lawful prize: it sells like any other goods, but the Crown takes its share" if lawful and s.career.marque != ""
		else ("lawfully taken" if lawful else "stolen goods: they sell for full price only through a fence")), "", Style.c("header"))
	var g := UIKit.grid(box, 5)
	if enemy.cargo.is_empty():
		UIKit.label(box, "  Her hold is empty.", "", Style.c("dim"))
	for good in enemy.cargo.keys():
		var lot := 10 if Market.weight(good) < 1.0 else 1
		var name_row := UIKit.row(g)
		UIKit.icon(name_row, Data.table("goods")[good].get("icon", ""), 22)
		UIKit.label(name_row, Data.table("goods")[good].name)
		UIKit.label(g, "%d aboard" % enemy.cargo[good])
		UIKit.label(g, "%d in your hold" % s.cargo.get(good, 0))
		UIKit.button(g, "Take %d" % (lot * 10), _take.bind(good, lot * 10))
		UIKit.button(g, "Take all", _take.bind(good, 100000))

	UIKit.label(box, "")
	UIKit.label(box, "The ship", "", Style.c("header"))
	_ship_fate = OptionButton.new()
	var need := Encounters.prize_crew_needed(enemy)
	var spare: int = s.crew.size() - s.officers.size()
	_ship_fate.add_item("Take her as a prize (%d of your hands to sail her)" % need)
	_ship_fate.set_item_tooltip(0, "Sell her at a shipyard (about %d gold, plus any cargo left aboard) or make her your flagship.\nShe sails with you and you go at her pace." % int(Data.table("ships")[enemy.type].price * Data.rules.prizes.sale_mult * clampf(enemy.hull / ShipStats.effective(enemy.type, []).hull, 0.2, 1.0)))
	_ship_fate.set_item_disabled(0, s.prizes.size() >= Data.rules.prizes.max or need > spare)
	_ship_fate.add_item("Scuttle her")
	_ship_fate.set_item_tooltip(1, "Burn her to the waterline. Nothing left to trace back to you.")
	_ship_fate.add_item("Let her go, crew and all")
	_ship_fate.set_item_tooltip(2, "Merciful (+1 honour). Her crew sails away; no prisoners to deal with.")
	_ship_fate.select(0 if not _ship_fate.is_item_disabled(0) else 1)
	_ship_fate.item_selected.connect(func(_i): _refresh_enabled())
	box.add_child(_ship_fate)

	UIKit.label(box, "")
	UIKit.label(box, "The prisoners (%d)" % survivors, "", Style.c("header"))
	var willing := int(survivors * Data.table("encounters")[enemy.kind].prisoner_willingness)
	_recruit = CheckBox.new()
	_recruit.text = "Offer them a place in your crew (about %d willing, berths for %d)" % [willing, ship.stats.crew_max - ShipStats.headcount(s)]
	_recruit.button_pressed = true
	box.add_child(_recruit)
	_prisoner_fate = OptionButton.new()
	var fates: Dictionary = Data.rules.prisoners.fates
	for f in fates:
		var react := Encounters.fate_reaction(s, f)
		_prisoner_fate.add_item("The rest: " + fates[f].name)
		_prisoner_fate.set_item_tooltip(_prisoner_fate.item_count - 1, "%s\nHonour %+d, fear %+d, standing with %s %+d.\nAmong your crew: %d would resent it, %d approve." % [
			fates[f].description, fates[f].honour, fates[f].fear, Data.table("factions")[enemy.faction].name,
			fates[f].get("relation", 0), react.upset, react.pleased])
	box.add_child(_prisoner_fate)

	UIKit.label(box, "")
	var cap_row := UIKit.row(box)
	cap_row.add_child(Portrait.make(enemy.captain, "captain", 72))
	UIKit.label(cap_row, "Their captain: %s" % enemy.captain.name, People.describe(enemy.captain), Style.c("header"))
	_captain_fate = OptionButton.new()
	_captain_fate.add_item("Hold for ransom (worth about %d from %s)" % [Encounters.ransom_value(enemy.captain), Data.table("factions")[enemy.faction].name])
	_captain_fate.set_item_tooltip(0, "Collect the ransom at any %s port. Until then they sail with you." % Data.table("factions")[enemy.faction].name)
	_captain_fate.add_item("Let them go with their crew")
	box.add_child(_captain_fate)
	_refresh_enabled()


func _refresh_enabled() -> void:
	var released := _ship_fate.selected == 2
	_recruit.disabled = released
	_prisoner_fate.disabled = released
	_captain_fate.disabled = released


func _take(good: String, qty: int) -> void:
	var n := Encounters.take_cargo(ship.state, enemy, good, qty, ship.capacity(), not enemy.get("legal", true))
	taken_value += n * Data.table("goods")[good].base_price
	%Status.text = "Took %d %s." % [n, Data.table("goods")[good].name] if n > 0 else "No room in your hold."
	_build()


func _finish() -> void:
	var s: Dictionary = ship.state
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if _ship_fate.selected == 2:
		s.reputation.honour += 1
		messages.append("You let the %s sail away." % enemy.name)
	else:
		var left := survivors
		if _recruit.button_pressed:
			var joined := Encounters.recruit_prisoners(s, enemy, survivors, ship.stats.crew_max, rng)
			left -= joined
			if joined > 0:
				messages.append("%d prisoners signed your articles." % joined)
		if left > 0:
			var fate: String = Data.rules.prisoners.fates.keys()[_prisoner_fate.selected]
			s.relations[enemy.faction] = s.relations.get(enemy.faction, 0) + int(Data.rules.prisoners.fates[fate].get("relation", 0))
			messages.append("%d prisoners: %s" % [left, Encounters.prisoner_fate(s, fate)])
		if _captain_fate.selected == 0:
			Encounters.take_hostage(s, enemy)
			messages.append("%s is held for ransom." % enemy.captain.name)
		if _ship_fate.selected == 0:
			var err := Encounters.take_prize(s, enemy, Encounters.prize_crew_needed(enemy))
			messages.append(err if err != "" else "A prize crew takes the %s." % enemy.name)
		else:
			messages.append("The %s burns and sinks." % enemy.name)
	if enemy.get("legal", true):
		var value: float = enemy.gold + taken_value
		if _ship_fate.selected == 0:
			value += Data.table("ships")[enemy.type].price * Data.rules.prizes.sale_mult
		messages.append_array(Career.record_prize(s, value))
	hide()
	done.emit(messages)
