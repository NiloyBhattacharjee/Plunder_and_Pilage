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
	_build_people()


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
	UIKit.label(box, "Career: %s.%s" % [Career.status_text(s), "  The Crown is owed %d." % s.career.crown_debt if s.career.crown_debt > 0 else ""],
		"Privateers raid their nation's enemies lawfully and pay the Crown a share. Pirates take what they like, and every navy hunts them once they're wanted.")
	UIKit.label(box, Factions.war_summary(), "", Style.c("dim"))
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
	if not s.captains.is_empty():
		UIKit.label(box, "")
		UIKit.label(box, "Captains of the %s" % s.name, "Everyone who has commanded this ship before you.", Style.c("header"))
		for c in s.captains:
			UIKit.label(box, "%s, until %s: %s" % [c.name, c.until, c.fate], "", Style.c("dim"))


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
	_build_mood(box)
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

	_build_successors(box)
	_build_bonds(box)
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


## Morale and what drives it, the articles, unrest and sickness.
func _build_mood(box: Node) -> void:
	var s: Dictionary = ship.state
	var m := Crew.morale(s, ship.stats)
	UIKit.label(box, "Morale %d" % m.value, m.text + "\n\nMorale steadies the crew in battle, keeps them from deserting in port, and decides whether anyone listens to a would-be mutineer.",
		Style.c("header"))
	var a: Dictionary = s.articles
	var vote_note := "\nAs a pirate crew, they vote on any change to the articles." if s.career.pirate else ""
	var row := UIKit.row(box)
	UIKit.label(row, "Articles:", "The terms the crew signed on for." + vote_note, Style.c("header"))
	var w := UIKit.button(row, "Wages", func(): _articles("wages", a.crew_share),
		"Daily wages, paid or owed. Steady, and costly when there's no plunder." + vote_note)
	w.disabled = a.pay == "wages"
	var sh := UIKit.button(row, "No prey, no pay", func(): _articles("shares", a.crew_share),
		"No wages: the crew live on their share of plunder. Cheap, until a month goes by without a prize." + vote_note)
	sh.disabled = a.pay == "shares"
	UIKit.label(row, "  Crew's share of plunder: %d%%" % int(round(a.crew_share * 100)),
		"Taken from every strongbox, ransom, prize sale and sale of stolen goods. A fair share is %d%%; greedy hands care most." % int(Data.rules.crew.fair_share * 100))
	UIKit.button(row, "-5%", func(): _articles(a.pay, a.crew_share - 0.05), "Less for the crew, more for you. They'll resent it." + vote_note)
	UIKit.button(row, "+5%", func(): _articles(a.pay, a.crew_share + 0.05), "More for the crew." + vote_note)
	var u: Dictionary = s.unrest
	if u.stage > 0:
		var who := ("%s is behind it" % People.person(u.leader).name) if u.known and u.leader != "" else "Someone is stirring them up; you don't know who"
		UIKit.label(box, "Unrest: %s. %s, and %s hands are listening." % [Crew.stage_name(s), who, "a handful of" if u.support.size() < 5 else "about %d" % (int(round(u.support.size() / 5.0)) * 5)],
			"Unrest grows when morale is low and a ringleader (ambitious, greedy or a schemer, with charisma or menace) finds unhappy listeners. It runs: grumbling, a round robin, weapons going missing, the black spot, mutiny.\nPay, rum, plunder, a fair share and fewer floggings bring the listeners back.",
			Style.c("bad"))
	var sick: Array = (s.crew + [s.captain]).filter(func(id): return People.person(id).get("sick", "") != "")
	if not sick.is_empty():
		UIKit.label(box, "Sick: %s." % ", ".join(sick.map(func(id): return "%s (%s)" % [People.person(id).name, Data.rules.crew.disease[People.person(id).sick].name.to_lower()])),
			"The sick still eat but can't work: the ship sails as if short-handed. A good surgeon saves lives and speeds recovery; rest in port helps most.\nScurvy comes with long voyages, the flux with short supplies, yellow fever in the summer months.",
			Style.c("bad"))
	UIKit.label(box, "")


func _articles(pay: String, share: float) -> void:
	%Status.text = Crew.set_articles(ship.state, ship.stats, pay, share, People.rng)
	message.emit(%Status.text)
	refresh()


## Who would take over, and the heir you can name to give them the crew's backing.
func _build_successors(box: Node) -> void:
	var s: Dictionary = ship.state
	var steady := RandomNumberGenerator.new()
	steady.seed = hash(s.captain + str(int(Clock.day)))  # the same estimate every time you look, today
	var cands := Crew.candidates(s, steady)
	UIKit.label(box, "")
	UIKit.label(box, "If the captain falls", "%s\nName a successor to give them your backing: the crew weigh your word by your authority.\nSomeone with intimidation %d or more can seize the ship by force whatever the crew want." % [
		"A pirate crew vote for a new captain." if Crew.culture(s) == "election" else "The chain of command: your heir if they're an officer, then the quartermaster, then the most experienced officer, unless the crew won't follow them.",
		Data.rules.crew.seize_intimidation], Style.c("header"))
	for c in cands.slice(0, 4):
		var p := People.person(c.id)
		var line := UIKit.row(box)
		line.add_child(Portrait.make(p, "officer" if c.id in s.officers.values() else "crew", 40))
		UIKit.label(line, "%s%s - about %d%% of the crew would back them" % [p.name, " (%s)" % c.why if c.why != "" else "", int(c.support * 100)], People.describe(p))
		if c.id != s.heir:
			UIKit.button(line, "Name as successor", func():
				s.heir = c.id
				%Status.text = "%s is your chosen successor." % p.name
				refresh())


func _build_bonds(box: Node) -> void:
	var s: Dictionary = ship.state
	var friends := []
	for id in s.crew:
		for f in Crew.friends_of(s, id):
			if f > id:
				friends.append([id, f])
	var feuds := Crew.feuds(s)
	if friends.is_empty() and feuds.is_empty():
		return
	UIKit.label(box, "")
	UIKit.label(box, "Friends and feuds", "Friendships form between like-minded hands; feuds between clashing ones. Friends mourn each other and follow each other into a mutiny; feuding hands come to blows.", Style.c("header"))
	for pair in friends.slice(0, 6):
		UIKit.label(box, "%s and %s are friends." % [People.person(pair[0]).name, People.person(pair[1]).name], "", Style.c("good"))
	for pair in feuds.slice(0, 6):
		UIKit.label(box, "%s and %s can't stand each other." % [People.person(pair[0]).name, People.person(pair[1]).name], "", Style.c("bad"))


## Everyone you've dealt with ashore: officials, the council, and the secrets you hold.
func _build_people() -> void:
	var box: VBoxContainer = %PeopleBox
	UIKit.clear(box)
	var s: Dictionary = ship.state
	var P: Dictionary = Data.table("politics")
	UIKit.label(box, "People you know", "Officials you've met in port, and Nassau's captains. Their opinion of you, what they want, and favours owed either way.
Unknown traits show as ?. Use favours and secrets in each port's Politics tab.", Style.c("header"))
	var known: Array = []
	for port_id in Politics.officials:
		for id in Politics.officials[port_id].values():
			if People.chars.has(id):
				known.append(id)
	if s.get("council_member", false):
		known.append_array(Politics.council)
	if known.is_empty():
		UIKit.label(box, "Nobody yet. Visit a port and see who runs it.", "", Style.c("dim"))
	var g := UIKit.grid(box, 6)
	for h in ["", "Name", "Where", "Opinion", "Wants", "Favours"]:
		UIKit.label(g, h, "", Style.c("header"))
	for id in known:
		var c := People.person(id)
		g.add_child(Portrait.make(c, "captain", 36))
		UIKit.label(g, "%s (%s)" % [c.name, People.trait_names(c)], People.describe(c))
		var role: String = "Council captain" if c.role == "council" else P.roles[c.role].name
		UIKit.label(g, "%s, %s" % [role, Ports.port(c.port).name] if c.port != "" else role)
		var op: int = c.relations.get(s.captain, 0)
		UIKit.label(g, "%+d" % op, "", Style.c("good") if op >= 20 else (Style.c("bad") if op <= Data.table("politics").grudge else Color(0, 0, 0, 0)))
		UIKit.label(g, P.goals[c.get("goal", "keep_order")].name if c.role != "council" else "plunder")
		var owed := Politics.favours(id, s)
		UIKit.label(g, ("owes you %d" % owed) if owed > 0 else (("you owe %d" % -owed) if owed < 0 else ""), "", Style.c("bad") if owed < 0 else Color(0, 0, 0, 0))
	UIKit.label(box, "")
	UIKit.label(box, "Alliances and rivalries", "Every bond has benefits and costs. Allies hold fire, share news and prices, fight beside you and answer calls; they also call on you, drag their reputation onto yours and may betray you if you look weak.
Rivals compete, feud, then hunt you; beating one brings fame and bounties. With no bonds at all, nobody owes you anything, and pirates think you easy prey.", Style.c("header"))
	var bonds: Array = Bonds.all(s).keys().filter(func(k): return Bonds.exists(k))
	if bonds.is_empty():
		UIKit.label(box, "None. You're neutral: free to deal with anyone, with no one to call on.", "", Style.c("dim"))
	for key in bonds:
		var b: Dictionary = Bonds.all(s)[key]
		var lvl := Bonds.level(s, key)
		var owed := Politics.favours(key, s) if not key.begins_with("f:") else 0
		var kind := Bonds.kind(key)
		var what: String = Bonds.cfg().benefits[kind][lvl - 1] + "
Costs: " + Bonds.cfg().costs[kind][lvl - 1] if lvl > 0 else Bonds.cfg().rivalry[-lvl - 1].text
		UIKit.label(box, "%s: %s since %s.%s%s" % [Bonds.name_of(key), Bonds.level_name(key, lvl), b.since,
			("  Owes you %d favour%s." % [owed, "" if owed == 1 else "s"]) if owed > 0 else (("  You owe them %d." % -owed) if owed < 0 else ""),
			"  Strained." if b.strain > 0 else ""], what + ("

" + "
".join(b.history) if not b.history.is_empty() else ""),
			Style.c("good") if lvl > 0 else Style.c("bad"))
	UIKit.label(box, "")
	UIKit.label(box, "Captains of the Caribbean", "Named captains who sail these waters. Meet them in their home ports to deal with them.", Style.c("header"))
	var cg := UIKit.grid(box, 5)
	for id in Bonds.roster():
		var c := People.person(id)
		cg.add_child(Portrait.make(c, "captain", 32))
		UIKit.label(cg, "%s, %s" % [c.name, "pirate" if c.faction == "pirates" else Data.table("factions")[c.faction].adjective + " privateer"], People.describe(c))
		UIKit.label(cg, "the %s, out of %s" % [c.ship, Ports.port(c.haunt).name])
		UIKit.label(cg, "opinion %+d" % c.relations.get(s.captain, 0))
		UIKit.label(cg, Bonds.level_name(id, Bonds.level(s, id)) if Bonds.level(s, id) != 0 else "")
	UIKit.label(box, "")
	UIKit.label(box, "Secrets", "Letters, ledgers, receipts and schedules. Use them in the Politics tab of the port where their subject holds office.", Style.c("header"))
	var secrets: Array = s.get("secrets", [])
	if secrets.is_empty():
		UIKit.label(box, "None. Captured ships, tavern clerks and dangerous friends are where secrets come from.", "", Style.c("dim"))
	for sec in secrets:
		var where: String = Ports.port(sec.port).name if sec.port != "" else "nowhere now"
		var stale := " Worthless in %d days." % int(sec.expires - Clock.day) if sec.expires >= 0 else ""
		UIKit.label(box, "%s (%s)%s%s%s" % [Politics.describe(sec), where, " It may be forged." if sec.doubt else "", " You're blackmailing them." if sec.leverage else "", stale])
