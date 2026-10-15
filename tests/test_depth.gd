extends GutTest
## The depth pass: hardship, desertion, smuggling memory, unreliable rumours, recruits worth interviewing,
## standing for warships, crew roles, lasting wounds, reefs and weather fronts.

const Ship = preload("res://scripts/ship.gd")
var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	rng.seed = 21
	Ports.reset()
	Ports.rng.seed = 4
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state


func test_thirst_kills_and_breeds_grudges():
	s.cargo = {"food": 100.0}
	var before: int = s.crew.size()
	var msgs := Ship.hardship(s, ShipStats.effective(s.type, []), "", rng)
	assert_eq(msgs.size(), 1)
	assert_string_contains(msgs[0], "No water")
	var c := People.person(s.crew[0])
	assert_lt(c.relations.get(s.captain, 0), 0)
	for i in 30:
		Ship.hardship(s, ShipStats.effective(s.type, []), "", rng)
	assert_lt(s.crew.size(), before)


func test_unpaid_wages_cause_desertion_in_port():
	s.wages_owed = 200.0  # weeks of wages
	var before: int = s.crew.size()
	var pool: float = Ports.state.port_royal.sailors
	for i in 5:
		Ship.hardship(s, ShipStats.effective(s.type, []), "port_royal", rng)
	assert_lt(s.crew.size(), before)
	assert_gt(Ports.state.port_royal.sailors, pool, "deserters join the port's pool")


func test_comfort_softens_hardship():
	var st := ShipStats.effective(s.type, ["better_quarters"])
	s.cargo = {"food": 100.0}
	Ship.hardship(s, st, "", rng)
	var with_comfort: int = People.person(s.crew[0]).relations[s.captain]
	assert_gte(with_comfort, -1)


func test_smuggling_seizure_has_lasting_consequences():
	Ports.state.cartagena.laws.vigilance = 1000.0
	s.cargo["cloth"] = 20.0
	var before: int = s.relations.spain
	Ports.sell("cartagena", "cloth", 10, s)
	assert_lt(s.relations.spain, before)
	assert_gt(s.reputation.notoriety, 0)


func test_customs_remember_and_slowly_forget():
	var base: float = Data.table("ports").cartagena.laws.vigilance
	s.cargo["cloth"] = 5.0
	Ports.rng.seed = 99
	Ports.state.cartagena.laws.vigilance = base
	var r := Ports.sell("cartagena", "cloth", 1, s)
	if r.ok:
		assert_gt(Ports.state.cartagena.laws.vigilance, base, "a clean contraband sale is still noticed")
	Ports.state.cartagena.laws.vigilance = base + 0.2
	for i in 100:
		Ports.daily()
	assert_almost_eq(Ports.state.cartagena.laws.vigilance, base, 0.01)


func test_false_rumours_are_marked_and_wrong():
	Ports.rumour("port_royal", 50, 1.0)
	var id: String = Ports.known.keys()[0]
	var good: String = Ports.known[id].keys()[0]
	var k: Dictionary = Ports.known[id][good]
	assert_eq(k.source, "rumour")
	assert_true(k.get("fake", false))
	assert_ne(snappedf(k.sell, 0.01), snappedf(Ports.price(id, good, false), 0.01))


func test_notable_recruits_can_be_interviewed_and_hired():
	var ps: Dictionary = Ports.state.tortuga
	assert_eq(ps.notables.size(), int(Data.rules.tavern.notables))
	var c: Dictionary = ps.notables[0]
	c.hidden = c.traits.duplicate()
	People.person(s.captain).stats.charisma = 20
	var r := Ports.interview("tortuga", 0, s)
	assert_true(r.ok)
	s.gold = 1000.0
	var crew_before: int = s.crew.size()
	assert_true(Ports.hire_notable("tortuga", 0, s, 200).ok)
	assert_eq(s.crew.size(), crew_before + 1)
	assert_eq(ps.notables.size(), int(Data.rules.tavern.notables) - 1)


func test_port_recruits_reflect_the_port():
	var total_tortuga := 0
	var total_bridgetown := 0
	for i in 40:
		total_tortuga += People.generate(Ports.recruit_opts("tortuga")).skills.swordplay
		total_bridgetown += People.generate(Ports.recruit_opts("bridgetown")).skills.swordplay
	assert_gt(total_tortuga, total_bridgetown)


func test_warships_need_standing():
	s.gold = 50000.0
	s.relations.spain = 0
	assert_ne(Ports.cannot_buy_ship("havana", "galleon", s), "")
	s.relations.spain = 40
	s.crew.resize(0)
	for i in 150:
		s.crew.append(People.add(People.generate()))
	assert_eq(Ports.cannot_buy_ship("havana", "galleon", s), "")


func test_crew_roles_change_the_fight():
	var side := Encounters.player_side(s)
	var guns_deck := CombatSim.make_ship(side)
	var sim := CombatSim.new()
	sim.set_roles(guns_deck, "gun_deck")
	var boarders := CombatSim.make_ship(side)
	sim.set_roles(boarders, "boarders")
	assert_gte(CombatSim.manned_guns(guns_deck), CombatSim.manned_guns(boarders))
	assert_gt(Boarding.fighting_factor({"marines": 0.45}), Boarding.fighting_factor({"marines": 0.1}))


func test_starving_crew_fight_worse():
	var fed: float = Encounters.player_side(s).morale
	s.cargo = {}
	assert_lt(Encounters.player_side(s).morale, fed)


func test_wounds_are_lasting_traits():
	var c := People.person(s.crew[0])
	c.traits = []
	var t := People.wound(c)
	assert_true(t in Data.rules.wounds.traits)
	assert_true(t in c.traits)
	assert_string_contains(c.history[-1], "Wounded")


func test_captain_wound_from_boarding_sticks():
	var after := {"hull": 80.0, "sails": 50.0, "masts": 1, "guns_working": 8, "casualties": 0.0, "captain_wounded": true}
	var cap := ShipStats.captain(s)
	var traits_before: int = cap.traits.size()
	Encounters.apply_battle(s, after, rng)
	assert_eq(cap.traits.size(), traits_before + 1)


func test_reefs_are_their_own_terrain():
	var img := Image.create(10, 10, false, Image.FORMAT_L8)
	img.fill(Color8(0, 0, 0))
	img.set_pixel(5, 5, Color8(192, 192, 192))
	var g := TerrainGrid.new(img, 4)
	assert_eq(g.at(Vector2(22, 22)), TerrainGrid.REEF)
	var sloop := ShipStats.effective("sloop", [])
	assert_gt(ShipStats.grounding_risk(s, sloop, true), 0.0, "reefs threaten even sloops")
	assert_eq(ShipStats.grounding_risk(s, sloop, false), 0.0)


func test_real_map_has_reefs():
	var g := TerrainGrid.new(load("res://data/map/terrain.png").get_image(), int(Data.map.cell_px))
	assert_gt(g._reef_cells.size(), 20)


func test_norther_blows_from_the_north_and_calms_kill_the_wind():
	Weather.storms = [{"kind": "norther", "pos": Vector2(500, 500), "vel": Vector2.ZERO, "radius": 300.0, "days_left": 3}]
	var w := Weather.wind_at(Vector2(600, 450))
	assert_eq(w.dir, 350.0)
	Weather.storms = [{"kind": "calm", "pos": Vector2(500, 500), "vel": Vector2.ZERO, "radius": 300.0, "days_left": 3}]
	assert_lt(Weather.wind_at(Vector2(600, 450)).strength, 0.3)
	Weather.storms = []
