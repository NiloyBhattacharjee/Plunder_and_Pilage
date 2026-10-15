extends GutTest


func before_each():
	People.reset()
	People.rng.seed = 3


func test_generated_people_have_full_model():
	var c := People.generate({"nationality": "french"})
	for k in People.STATS:
		assert_between(c.stats[k], 0, 20, k)
	for k in People.SKILLS:
		assert_between(c.skills[k], 0, 20, k)
	assert_between(c.traits.size(), 1, 3)
	assert_eq(c.nationality, "french")


func test_no_opposite_traits():
	for i in 300:
		var c := People.generate()
		assert_false("brave" in c.traits and "cowardly" in c.traits)
		assert_false("honest" in c.traits and "schemer" in c.traits)


func test_traits_change_values_even_when_hidden():
	var c := People.generate()
	c.skills.seamanship = 10
	c.traits = ["seasick"]
	c.hidden = ["seasick"]
	assert_eq(People.value(c, "seamanship"), 7)
	assert_string_contains(People.breakdown(c, "seamanship"), "don't know")
	assert_false(People.breakdown(c, "seamanship").contains("Seasick"))
	assert_eq(People.trait_names(c), "?")


func test_values_clamped():
	var c := People.generate()
	c.stats.charisma = 19
	c.traits = ["popular"]
	assert_eq(People.value(c, "charisma"), 20)


func test_skills_improve_with_use():
	var c := People.generate()
	c.skills.navigation = 5
	c.xp.navigation = 0.0
	assert_false(People.gain_xp(c, "navigation", 10.0))
	assert_true(People.gain_xp(c, "navigation", 50.0))
	assert_eq(c.skills.navigation, 6)


func test_reveal_trait():
	var c := People.generate()
	c.traits = ["drunkard", "brave"]
	c.hidden = ["drunkard"]
	assert_eq(People.reveal_trait(c), "drunkard")
	assert_eq(c.hidden, [])
	assert_eq(People.reveal_trait(c), "")


func test_captain_is_an_ordinary_character_with_background():
	var game := NewGame.build({"nationality": "dutch", "background": "merchant_son", "name": "Anna Visser"})
	var cap := People.person(game.state.captain)
	assert_eq(cap.name, "Anna Visser")
	assert_true("honest" in cap.traits)
	assert_eq(cap.hidden, [], "you know your own traits")
	assert_eq(game.state.type, "schooner")
	assert_eq(game.start_port, "willemstad")
	assert_eq(game.state.relations.dutch, 5)
	assert_eq(game.state.crew.size(), 20)


func test_background_can_override_start_port():
	var game := NewGame.build({"nationality": "english", "background": "indentured"})
	assert_eq(game.start_port, "tortuga")
	assert_lt(game.state.relations.england, 0)
