extends CanvasLayer
## Crew and ship screen: the captain's sheet, the ship's numbers, officer posts and the crew as a group.
## Every number has a tooltip explaining where it comes from. Time is paused while it's open.

signal message(text: String)
signal closed

var ship: Node2D


func _ready() -> void:
	%SetSail.pressed.connect(close)


func open(player_ship: Node2D) -> void:
	ship = player_ship
	%Status.text = ""
	UIKit.pause_clock()
	refresh()
	show()


func close() -> void:
	hide()
	UIKit.resume_clock()
	closed.emit()


func refresh() -> void:
	var s: Dictionary = ship.state
	var cap := ShipStats.captain(s)
	%Title.text = "Captain %s of the %s" % [cap.name, s.name]
	%Info.text = "%s %s.  Crew %d (needs %d, berths %d).  Gold %d." % [
		Data.table("ships")[s.type].name, s.name, ShipStats.headcount(s), ShipStats.crew_needed(s, ship.stats),
		ship.stats.crew_max, s.gold]
	_build_captain(cap)
	_build_ship()
	_build_officers()
	_build_crew()


func _build_captain(cap: Dictionary) -> void:
	var box: VBoxContainer = %CaptainBox
	UIKit.clear(box)
	var bg: Dictionary = Data.table("backgrounds").get(cap.background, {})
	var head := UIKit.row(box)
	head.add_child(Portrait.make(cap, "captain", 128))
	var who := VBoxContainer.new()
	head.add_child(who)
	UIKit.label(who, "%s, %s, age %d. %s" % [cap.name, Data.table("nations")[cap.nationality].name, cap.age, bg.get("name", "")],
		bg.get("description", ""))
	box = who
	UIKit.label(box, "The captain is a crew member like any other. If they fall, someone else takes over.", "", Style.c("dim"))
	_character_sheet(box, cap)
	UIKit.label(box, "")
	var s: Dictionary = ship.state
	var rep: Dictionary = s.reputation
	UIKit.label(box, "Reputation: honour %+d, fear %+d, notoriety %d" % [rep.honour, rep.fear, rep.notoriety],
		"Honour grows from mercy and keeping your word; fear from cruelty. Notoriety is how widely your name is known.", Style.c("header"))
	UIKit.label(box, "Standing: " + ", ".join(s.relations.keys().map(func(f): return "%s %+d" % [Data.table("factions")[f].name, s.relations[f]])))
	var feelings: Array = s.crew.map(func(id): return People.person(id).relations.get(s.captain, 0))
	var unhappy: int = feelings.filter(func(v): return v < 0).size()
	if unhappy > 0:
		UIKit.label(box, "%d of your crew hold something against you." % unhappy,
			"Choices that clash with their traits (mercy to a bloodthirsty hand, cruelty to a merciful one) are remembered.", Style.c("bad"))
	if not s.hostages.is_empty():
		UIKit.label(box, "Hostages: " + ", ".join(s.hostages.map(func(h): return "%s (%s, %d gold)" % [
			People.person(h.id).name, Data.table("factions")[h.faction].name, h.ransom])))
	UIKit.label(box, "")
	UIKit.label(box, "Log", "", Style.c("header"))
	for line in cap.history:
		UIKit.label(box, line, "", Style.c("dim"))


## Stats, skills and traits for any character, with breakdown tooltips.
func _character_sheet(box: Node, c: Dictionary) -> void:
	var g := UIKit.grid(box, 4)
	for h in ["Leadership", "", "Skills", ""]:
		UIKit.label(g, h, "", Style.c("header"))
	for i in maxi(People.STATS.size(), People.SKILLS.size()):
		if i < People.STATS.size():
			var k: String = People.STATS[i]
			UIKit.label(g, People.SKILL_NAMES[k], People.breakdown(c, k))
			UIKit.label(g, str(People.value(c, k)), People.breakdown(c, k))
		else:
			UIKit.label(g, "")
			UIKit.label(g, "")
		var sk: String = People.SKILLS[i]
		UIKit.label(g, People.SKILL_NAMES[sk], People.breakdown(c, sk))
		UIKit.label(g, str(People.value(c, sk)), People.breakdown(c, sk))
	var traits := UIKit.row(box)
	UIKit.label(traits, "Traits:", "", Style.c("header"))
	for t in People.known_traits(c):
		var td: Dictionary = Data.table("traits")[t]
		var fx := PackedStringArray()
		for k in td.get("effects", {}):
			fx.append("%s %+d" % [People.SKILL_NAMES[k], td.effects[k]])
		UIKit.label(traits, td.name, td.description + ("\n" + ", ".join(fx) if not fx.is_empty() else ""))
	for i in c.hidden.size():
		UIKit.label(traits, "?", "A trait you haven't discovered yet.", Style.c("dim"))


func _build_ship() -> void:
	var box: VBoxContainer = %ShipBox
	UIKit.clear(box)
	var s: Dictionary = ship.state
	var st: Dictionary = ship.stats
	UIKit.label(box, Data.table("ships")[s.type].description, "", Style.c("dim"))
	var g := UIKit.grid(box, 2)
	var rows := [
		["hull", "%d / %d" % [s.hull, st.hull]],
		["sails", "%d / %d" % [s.sails, st.sails]],
		["speed_knots", "%.1f" % st.speed_knots],
		["turning", str(st.turning)],
		["cargo", "%d / %d" % [Market.cargo_used(s.cargo), st.cargo]],
		["crew_max", str(st.crew_max)],
		["crew_min", "%d (%d with your boatswain)" % [st.crew_min, ShipStats.crew_needed(s, st)]],
		["guns", "%d x %d-pounders%s" % [st.guns, st.gun_weight, " (%d dismounted)" % s.guns_lost if s.guns_lost > 0 else ""]],
		["swivels", str(st.swivels)],
		["chase_guns", str(st.chase_guns)],
		["comfort", str(st.comfort)],
		["fouling_rate", "%.2f" % st.fouling_rate],
	]
	for r in rows:
		var tip := ShipStats.breakdown(s.type, s.upgrades, r[0])
		UIKit.label(g, ShipStats.LABELS[r[0]], tip)
		UIKit.label(g, r[1], tip)
	var d: Dictionary = Data.rules.draught[st.draught]
	UIKit.label(g, "Draught", "Deeper keels avoid shallow water when routing and risk running aground in it.")
	UIKit.label(g, "%s (aground risk %.0f%% a day in shallows, %.0f%% on reefs)" % [d.name, 100 * ShipStats.grounding_risk(s, st),
		100 * ShipStats.grounding_risk(s, st, true)], "Base risk %.0f%% / %.0f%% per day, cut by navigation." % [100 * d.ground_risk_per_day, 100 * d.reef_risk_per_day])
	UIKit.label(g, "Hull fouling", "Weed and barnacles slow the ship. Careen at a shipyard to clean the hull.")
	UIKit.label(g, "%d%%" % int(s.fouling * 100))
	var officers: int = s.officers.size()
	var u: Dictionary = Data.rules.upkeep
	var cost_tip := "Crew wages: %d x %s\nOfficers: %d x %s\nShip upkeep: %d" % [s.crew.size() - officers,
		Market.fmt(u.wage_per_crew), officers, Market.fmt(u.wage_per_crew * u.officer_wage_mult), st.upkeep]
	UIKit.label(g, "Daily cost", cost_tip)
	UIKit.label(g, "%s gold" % Market.fmt(ShipStats.daily_cost(s, st)), cost_tip)
	UIKit.label(box, "")
	UIKit.label(box, "Upgrades: " + (", ".join(s.upgrades.map(func(x): return Data.table("upgrades")[x].name)) if not s.upgrades.is_empty() else "none"), "", Style.c("header"))


func _build_officers() -> void:
	var box: VBoxContainer = %OfficersBox
	UIKit.clear(box)
	var s: Dictionary = ship.state
	UIKit.label(box, "Officers are drawn from your crew. An empty post is covered by the captain at half skill.", "", Style.c("dim"))
	var g := UIKit.grid(box, 4)
	for role in Data.rules.officer_roles:
		var r: Dictionary = Data.rules.officer_roles[role]
		var holder: String = s.officers.get(role, "")
		if holder != "":
			g.add_child(Portrait.make(People.person(holder), "officer", 48))
		else:
			UIKit.icon(g, "", 48)
		UIKit.label(g, r.name, r.effect)
		var pick := OptionButton.new()
		pick.add_item("(none)")
		pick.set_item_metadata(0, "")
		var candidates: Array = s.crew.duplicate()
		candidates.sort_custom(func(a, b): return People.value(People.person(a), r.skill) > People.value(People.person(b), r.skill))
		for id in candidates.slice(0, 15):
			var c := People.person(id)
			var held := _post_of(id)
			pick.add_item("%s - %s %d%s" % [c.name, People.SKILL_NAMES[r.skill], People.value(c, r.skill),
				" (now %s)" % Data.rules.officer_roles[held].name if held != "" and held != role else ""])
			pick.set_item_metadata(pick.item_count - 1, id)
			pick.set_item_tooltip(pick.item_count - 1, People.describe(c))
			if s.officers.get(role, "") == id:
				pick.select(pick.item_count - 1)
		pick.item_selected.connect(func(i): _appoint(role, pick.get_item_metadata(i)))
		g.add_child(pick)
		var current: String = s.officers.get(role, "")
		UIKit.label(g, "%s %d" % [People.SKILL_NAMES[r.skill], ShipStats.officer_skill(s, role)],
			People.describe(People.person(current)) if current != "" else "Captain covering at half skill.")
	UIKit.button(box, "Appoint the best available to empty posts", func():
		NewGame.auto_appoint(s, 0)
		refresh())


func _post_of(id: String) -> String:
	for role in ship.state.officers:
		if ship.state.officers[role] == id:
			return role
	return ""


func _appoint(role: String, id: String) -> void:
	var s: Dictionary = ship.state
	var old_post := _post_of(id)
	if old_post != "":
		s.officers.erase(old_post)
	if id == "":
		s.officers.erase(role)
		%Status.text = "%s post left empty." % Data.rules.officer_roles[role].name
	else:
		s.officers[role] = id
		%Status.text = "%s is now %s." % [People.person(id).name, Data.rules.officer_roles[role].name]
		message.emit(%Status.text)
	refresh()


func _build_crew() -> void:
	var box: VBoxContainer = %CrewBox
	UIKit.clear(box)
	var s: Dictionary = ship.state
	var crew: Array = s.crew.map(func(id): return People.person(id))
	if crew.is_empty():
		UIKit.label(box, "No crew aboard.")
		return
	var avg := {}
	for sk in ["seamanship", "gunnery", "swordplay"]:
		var total := 0
		for c in crew:
			total += People.value(c, sk)
		avg[sk] = float(total) / crew.size()
	UIKit.label(box, "%d hands. Average seamanship %.1f, gunnery %.1f, swordplay %.1f." % [crew.size(),
		avg.seamanship, avg.gunnery, avg.swordplay])
	var nations := {}
	for c in crew:
		nations[c.nationality] = nations.get(c.nationality, 0) + 1
	UIKit.label(box, "Origins: " + ", ".join(nations.keys().map(func(n): return "%s %d" % [Data.table("nations")[n].name, nations[n]])), "", Style.c("dim"))
	var roles := UIKit.row(box)
	UIKit.label(roles, "Battle stations:", "How the crew is split in a fight: sailors work the ship, gunners serve the guns, marines lead boardings.", Style.c("header"))
	for preset in Data.rules.crew_roles.presets:
		var p: Dictionary = Data.rules.crew_roles.presets[preset]
		var b := UIKit.button(roles, p.name, func():
			s.roles = preset
			refresh(), "%s\nSailors %d%%, gunners %d%%, marines %d%%." % [p.description, p.sailors * 100, p.gunners * 100, p.marines * 100])
		b.disabled = s.get("roles", "balanced") == preset
	var unknown := crew.filter(func(c): return not c.hidden.is_empty()).size()
	UIKit.label(box, "%d hands still have traits you haven't discovered. Time at sea brings them out." % unknown, "", Style.c("dim"))

	var by_lead := crew.duplicate()
	by_lead.sort_custom(func(a, b): return People.leadership(a) > People.leadership(b))
	_people_list(box, "Possible successors", by_lead.slice(0, 3),
		"Authority + charisma + experience. If the captain falls, the crew will look to these.")
	var trouble := crew.filter(func(c):
		var known := People.known_traits(c)
		var stirs := known.any(func(t): return "ringleader" in Data.table("traits")[t].get("tags", []))
		return stirs and (People.value(c, "charisma") >= 9 or People.value(c, "intimidation") >= 9))
	_people_list(box, "Troublemakers", trouble.slice(0, 5),
		"Known schemers, greedy or ambitious hands with the charisma or menace to lead others.")
	var green := crew.filter(func(c): return c.age < 25)
	green.sort_custom(func(a, b): return _best_skill(a) > _best_skill(b))
	_people_list(box, "Rising stars", green.slice(0, 3), "Young hands already good at something.")


func _people_list(box: Node, title: String, people: Array, tip: String) -> void:
	UIKit.label(box, "")
	UIKit.label(box, title, tip, Style.c("header"))
	if people.is_empty():
		UIKit.label(box, "  None known.", "", Style.c("dim"))
	for c in people:
		var post := _post_of(c.id)
		var line := UIKit.row(box)
		line.add_child(Portrait.make(c, "officer" if post != "" else "crew", 40))
		UIKit.label(line, "%s%s - %s" % [c.name, " (%s)" % Data.rules.officer_roles[post].name if post != "" else "",
			People.trait_names(c)], People.describe(c))


static func _best_skill(c: Dictionary) -> int:
	var best := 0
	for sk in People.SKILLS:
		best = maxi(best, People.value(c, sk))
	return best
