extends GutTest
## How a career ends, the ship's log, and the first-voyage hints.

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	rng.seed = 2
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	for i in 80:
		s.crew.append(People.add(People.generate({})))


func after_each():
	Clock.day = 0.0
	Data.rules.endings.hang_chance = 0.5


func choice(id: String, docked := true) -> Dictionary:
	return Endings.choices(s, docked).filter(func(e): return e.id == id)[0]


func test_retiring_takes_a_fortune_and_a_harbour():
	assert_ne(choice("retire").why, "")
	s.gold = float(Data.rules.endings.retire_gold)
	assert_eq(choice("retire").why, "")
	assert_ne(choice("retire", false).why, "", "not from the middle of the sea")


func test_a_governorship_needs_a_town_a_crown_and_their_favour():
	assert_string_contains(choice("governor").why, "town")
	Sieges.hold(s, "maracaibo")
	assert_string_contains(choice("governor").why, "nation")
	s.career.marque = "england"
	s.relations.england = 80
	s.career.rank = 0
	assert_string_contains(choice("governor").why, "governors of")
	s.career.rank = int(Data.rules.endings.governor_rank)
	assert_eq(choice("governor").why, "")
	assert_string_contains(Endings.epitaph(s, "governor").text, "Maracaibo")


func test_a_republic_needs_nassau_and_another_town():
	assert_ne(choice("republic").why, "")
	Politics.council_leader = "player"
	Bases.hold_town(s, "nassau", 0, 20, "england")
	assert_string_contains(choice("republic").why, "towns")
	Sieges.hold(s, "maracaibo")
	assert_eq(choice("republic").why, "")
	Politics.council_leader = ""


func test_struck_to_the_hunters_who_want_you_you_may_hang():
	Data.rules.endings.hang_chance = 1.0
	var navy := Encounters.generate("spain", rng, "hunter")
	assert_eq(Endings.hanging(s, navy, rng), "", "nobody wants you yet")
	Career.add_bounty(s, "spain", 1000)
	assert_ne(Endings.hanging(s, navy, rng), "")
	assert_true(s.succession.cause.ends_with("hanged"))
	assert_false(s.get("bounty", {}).has("spain"), "they've collected")


func test_the_log_reads_back_the_line_of_captains():
	s.captains = [{"name": "Old Tom", "until": "1 May 1680", "fate": "died of fever"}]
	ShipStats.captain(s).history.append("Took the Spanish San Juan, 2 May 1680.")
	var text := Endings.log_text(s)
	assert_string_contains(text, "Old Tom")
	assert_string_contains(text, "San Juan")


func test_hints_show_once_and_only_when_wanted():
	assert_eq(Tutorial.note(s, "cove"), "", "off unless chosen")
	s.tutorial = true
	assert_string_contains(Tutorial.note(s, "cove"), "base")
	assert_eq(Tutorial.note(s, "cove"), "", "once")
