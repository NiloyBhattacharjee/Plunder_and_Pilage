extends GutTest
## The living crew: why each hand feels what they feel about you, life below decks, what's on their mind.

var s: Dictionary
var rng := RandomNumberGenerator.new()


func before_each():
	Clock.day = 0.0
	s = NewGame.build({"nationality": "english", "background": "ex_navy"}).state
	Crew.ensure(s)
	rng.seed = 9


func after_each():
	Clock.day = 0.0


func test_a_hand_remembers_why_and_the_same_reason_adds_up():
	var c := People.person(s.crew[0])
	var before := Crew.opinion(c, s)
	Crew.feel(s, c, -3, "Overruled me: sail on")
	Crew.feel(s, c, 2, "A prize taken")
	Crew.feel(s, c, -3, "Overruled me: sail on")
	assert_eq(Crew.opinion(c, s), before - 4)
	var mem := Crew.memories(c, s)
	assert_eq(mem.size(), 2)
	assert_eq([mem[0].why, mem[0].n], ["Overruled me: sail on", -6], "newest first, and it adds up")
	assert_string_contains(Aboard.reasons(c, s), "A prize taken")


func test_memories_are_capped_and_belong_to_the_captain():
	var c := People.person(s.crew[0])
	for i in 10:
		Crew.feel(s, c, 1, "reason %d" % i)
	assert_eq(Crew.memories(c, s).size(), int(Data.rules.crew.memories))
	s.captain = s.crew[1]
	assert_true(Crew.memories(c, s).is_empty(), "a new captain starts with a clean slate")


func test_life_below_decks_happens_and_leaves_a_mark():
	Data.table("aboard")._rules.chance = 1.0
	var news := []
	for d in 30:
		Clock.day = float(d)
		news.append_array(Aboard.day(s, "", rng))
	Data.table("aboard")._rules.chance = 0.35
	assert_false(news.is_empty(), "something happened in a month at sea")
	assert_eq(s.aboard.log[0].text, news[-1], "the newest first")
	assert_false("{a}" in news[0] or "{b}" in news[0], "names filled in")


func test_a_moment_picks_the_right_people():
	var m: Dictionary = Data.table("aboard").moments.sickbay
	assert_true(Aboard._cast(s, m, "", rng).is_empty(), "nobody sick, nobody to sit with")
	People.person(s.crew[1]).sick = Data.rules.crew.disease.keys()[0]
	var cast := Aboard._cast(s, m, "", rng)
	assert_eq(cast.b.id, s.crew[1])
	assert_true(Aboard._cast(s, Data.table("aboard").moments.letter, "", rng).is_empty(), "letters go from port")


func test_whats_on_their_mind():
	var c := People.person(s.crew[0])
	c.sick = Data.rules.crew.disease.keys()[0]
	assert_string_contains(Aboard.mind(c, s), "Down with")
	c.sick = ""
	c.erase("want")
	Crew.feel(s, c, -4, "Hanged a shipmate")
	assert_string_contains(Aboard.mind(c, s), "hanged a shipmate")
