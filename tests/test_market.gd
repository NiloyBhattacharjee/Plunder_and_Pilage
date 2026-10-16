extends GutTest


func test_seizure_risk_only_for_contraband_and_grows_with_quantity():
	var laws := {"contraband": ["cloth"], "vigilance": 0.6}
	assert_eq(Market.seizure_chance(laws, "sugar", 50), 0.0)
	assert_gt(Market.seizure_chance(laws, "cloth", 50), Market.seizure_chance(laws, "cloth", 10))
	assert_lt(Market.seizure_chance(laws, "cloth", 50), 1.0)


func test_aliases_lead_to_real_goods():
	assert_eq(Market.canonical("provisions"), "food")
	assert_eq(Market.canonical("gems"), "gold")
	assert_eq(Market.canonical("weapons"), "gunpowder")
	assert_eq(Market.canonical("sugar"), "sugar")
